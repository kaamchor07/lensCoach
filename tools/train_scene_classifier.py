"""
LensCoach — Scene Classifier Training & ONNX Export Script

Fine-tunes MobileNetV3-Small on Places365 → 6-class scene classifier.
Exports a CLEAN 6-class ONNX model with softmax output. No Kotlin remapping.

Requirements:
  pip install torch torchvision onnx onnxruntime pillow

Usage:
  python train_scene_classifier.py --epochs 10 --batch_size 64 --output scene_classifier.onnx

Output:
  scene_classifier.onnx — drop into android/src/main/assets/
"""

import argparse
import os
import sys
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Dataset, random_split
from torchvision import transforms, models
from torchvision.datasets import ImageFolder
from PIL import Image
import onnx
import numpy as np

# ─── Configuration ──────────────────────────────────────────────────────────

SCENE_CLASSES = [
    "landscape",       # 0 — outdoor scenes, mountains, fields, skies
    "architecture",    # 1 — buildings, interiors, structures
    "portrait",        # 2 — people, faces, single subjects
    "street",          # 3 — urban scenes, cars, city life
    "macro",           # 4 — close-ups, flowers, insects, textures
    "lowLight",        # 5 — night scenes, dim lighting, indoor dark
]
NUM_CLASSES = len(SCENE_CLASSES)
INPUT_SIZE = 224

# ImageNet normalization
IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]

# Places365 category → our 6-class mapping
# These are approximate mappings from Places365's 365 categories
PLACES365_MAPPING = {
    # Landscape (outdoor nature)
    "mountain": 0, "mountain_path": 0, "field_road": 0, "valley": 0,
    "beach": 0, "ocean": 0, "lake_natural": 0, "forest_path": 0,
    "cliff": 0, "desert_sand": 0, "waterfall": 0, "park": 0,
    "sky": 0, "snowfield": 0, "field_cultivated": 0, "pasture": 0,

    # Architecture (buildings, structures)
    "church_outdoor": 1, "church_indoor": 1, "building_facade": 1,
    "tower": 1, "bridge": 1, "skyscraper": 1, "palace": 1,
    "castle": 1, "arch": 1, "corridor": 1, "staircase": 1,
    "abbey": 1, "basilica": 1, "cathedral_outdoor": 1, "mosque_outdoor": 1,

    # Portrait (people-centric — use a people dataset or subset)
    "beauty_salon": 2, "dressing_room": 2, "phone_booth": 2,

    # Street (urban)
    "street": 3, "alley": 3, "crosswalk": 3, "market_outdoor": 3,
    "parking_lot": 3, "gas_station": 3, "bus_station_indoor": 3,
    "subway_station_platform": 3, "shopping_mall_indoor": 3,
    "plaza": 3, "highway": 3, "intersection": 3,

    # Macro (close-up — typically not in Places365, supplement separately)
    "florist_shop_indoor": 4, "herb_garden": 4, "greenhouse_indoor": 4,

    # Low-Light (dark scenes)
    "bar": 5, "nightclub": 5, "movie_theater_indoor": 5,
    "music_studio": 5, "home_theater": 5, "basement": 5,
    "attic": 5, "dark_alley": 5,
}


# ─── Model Definition ───────────────────────────────────────────────────────

def create_model(pretrained=True):
    """
    MobileNetV3-Small with replaced classification head.
    Final output: 6 classes with softmax.
    This is the ONNX-exported model — Kotlin receives clean 6-class softmax.
    """
    model = models.mobilenet_v3_small(pretrained=pretrained)

    # Replace the classifier head
    # MobileNetV3-Small: classifier is Sequential(Linear(576, 1024), Hardswish, Dropout, Linear(1024, 1000))
    in_features = model.classifier[0].in_features  # 576
    model.classifier = nn.Sequential(
        nn.Linear(in_features, 256),
        nn.Hardswish(),
        nn.Dropout(p=0.2),
        nn.Linear(256, NUM_CLASSES),
        # No softmax here — CrossEntropyLoss applies log_softmax internally
        # Softmax is added during ONNX export
    )

    return model


class SoftmaxWrapper(nn.Module):
    """Wraps model with final softmax for ONNX export."""
    def __init__(self, base_model):
        super().__init__()
        self.base = base_model

    def forward(self, x):
        logits = self.base(x)
        return torch.softmax(logits, dim=1)


# ─── Dataset ────────────────────────────────────────────────────────────────

def get_transforms(train=True):
    """Data augmentation for training, standard transforms for validation."""
    if train:
        return transforms.Compose([
            transforms.RandomResizedCrop(INPUT_SIZE, scale=(0.8, 1.0)),
            transforms.RandomHorizontalFlip(),
            transforms.ColorJitter(brightness=0.2, contrast=0.2, saturation=0.1),
            transforms.ToTensor(),
            transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
        ])
    else:
        return transforms.Compose([
            transforms.Resize(256),
            transforms.CenterCrop(INPUT_SIZE),
            transforms.ToTensor(),
            transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
        ])


# ─── Training ───────────────────────────────────────────────────────────────

def train_model(model, train_loader, val_loader, epochs, lr, device):
    """Standard fine-tuning loop with early stopping."""
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)

    best_val_acc = 0.0
    best_state = None
    patience = 3
    patience_counter = 0

    for epoch in range(epochs):
        # Training
        model.train()
        train_loss = 0.0
        train_correct = 0
        train_total = 0

        for inputs, labels in train_loader:
            inputs, labels = inputs.to(device), labels.to(device)

            optimizer.zero_grad()
            outputs = model(inputs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()

            train_loss += loss.item() * inputs.size(0)
            _, predicted = outputs.max(1)
            train_total += labels.size(0)
            train_correct += predicted.eq(labels).sum().item()

        # Validation
        model.eval()
        val_correct = 0
        val_total = 0

        with torch.no_grad():
            for inputs, labels in val_loader:
                inputs, labels = inputs.to(device), labels.to(device)
                outputs = model(inputs)
                _, predicted = outputs.max(1)
                val_total += labels.size(0)
                val_correct += predicted.eq(labels).sum().item()

        train_acc = 100.0 * train_correct / train_total
        val_acc = 100.0 * val_correct / val_total
        train_loss /= train_total

        print(f"Epoch {epoch+1}/{epochs} | Loss: {train_loss:.4f} | "
              f"Train: {train_acc:.1f}% | Val: {val_acc:.1f}%")

        scheduler.step()

        # Early stopping check
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            best_state = model.state_dict().copy()
            patience_counter = 0
        else:
            patience_counter += 1
            if patience_counter >= patience:
                print(f"Early stopping at epoch {epoch+1}")
                break

    # Restore best weights
    if best_state is not None:
        model.load_state_dict(best_state)

    print(f"Best validation accuracy: {best_val_acc:.1f}%")
    return model


# ─── ONNX Export ─────────────────────────────────────────────────────────────

def export_onnx(model, output_path, device):
    """
    Export model to ONNX with softmax wrapper.
    Output is a CLEAN 6-class softmax — no remapping needed in Kotlin.
    """
    model.eval()
    wrapped = SoftmaxWrapper(model).to(device)
    wrapped.eval()

    dummy_input = torch.randn(1, 3, INPUT_SIZE, INPUT_SIZE).to(device)

    torch.onnx.export(
        wrapped,
        dummy_input,
        output_path,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={
            "input": {0: "batch_size"},
            "output": {0: "batch_size"},
        },
        opset_version=13,
        do_constant_folding=True,
    )

    # Verify
    onnx_model = onnx.load(output_path)
    onnx.checker.check_model(onnx_model)

    # Quick inference test
    import onnxruntime as ort
    session = ort.InferenceSession(output_path)
    test_input = np.random.randn(1, 3, INPUT_SIZE, INPUT_SIZE).astype(np.float32)
    result = session.run(None, {"input": test_input})
    probs = result[0][0]

    print(f"\nONNX export successful: {output_path}")
    print(f"Output shape: {result[0].shape}")
    print(f"Sum of probabilities: {sum(probs):.4f} (should be ~1.0)")
    print(f"Class labels: {SCENE_CLASSES}")
    print(f"Test probs: {[f'{p:.3f}' for p in probs]}")
    print(f"\nFile size: {os.path.getsize(output_path) / 1024 / 1024:.1f} MB")


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Train LensCoach scene classifier")
    parser.add_argument("--data_dir", type=str, default="./scene_data",
                        help="Path to dataset (ImageFolder format with 6 class subdirs)")
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch_size", type=int, default=64)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--output", type=str, default="scene_classifier.onnx")
    parser.add_argument("--pretrained_only", action="store_true",
                        help="Skip training, just export pretrained model with new head")
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")
    print(f"Classes: {SCENE_CLASSES}")

    model = create_model(pretrained=True).to(device)
    print(f"Model parameters: {sum(p.numel() for p in model.parameters()):,}")

    if args.pretrained_only:
        print("\nSkipping training — exporting pretrained model with random 6-class head")
        print("NOTE: This model will produce random predictions. Train on real data for production.")
    elif os.path.isdir(args.data_dir):
        print(f"\nLoading dataset from {args.data_dir}")
        dataset = ImageFolder(args.data_dir, transform=get_transforms(train=True))
        val_dataset = ImageFolder(args.data_dir, transform=get_transforms(train=False))

        # 80/20 split
        train_size = int(0.8 * len(dataset))
        val_size = len(dataset) - train_size
        train_dataset, _ = random_split(dataset, [train_size, val_size])
        _, val_subset = random_split(val_dataset, [train_size, val_size])

        train_loader = DataLoader(train_dataset, batch_size=args.batch_size,
                                  shuffle=True, num_workers=4)
        val_loader = DataLoader(val_subset, batch_size=args.batch_size,
                                shuffle=False, num_workers=4)

        print(f"Training samples: {len(train_dataset)}")
        print(f"Validation samples: {len(val_subset)}")
        print()

        model = train_model(model, train_loader, val_loader, args.epochs, args.lr, device)
    else:
        print(f"\nDataset directory '{args.data_dir}' not found.")
        print("To train: create ./scene_data/ with 6 subdirs: landscape/, architecture/, portrait/, street/, macro/, lowLight/")
        print("Each subdir should contain ~200+ images of that scene type.")
        print("\nExporting pretrained model with random head for testing...")

    export_onnx(model, args.output, device)
    print(f"\nDone! Copy {args.output} to:")
    print("  lenscoach/android/src/main/assets/scene_classifier.onnx")


if __name__ == "__main__":
    main()
