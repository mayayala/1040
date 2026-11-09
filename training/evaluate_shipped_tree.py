"""Evalúa el artefacto Android congelado sobre la partición Test del repositorio."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd
import sklearn
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import GroupShuffleSplit

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "ml"
ASSET_NAMES = ("decision_tree.json", "tree_scaler_params.json", "threshold_params.json")
CLASSES = [0, 1, 2]
NAMES = ["Normal", "Anómalo", "Crítico"]


def scores_at_leaf(node, row):
    while "scores" not in node:
        branch = "left" if row[node["feature"]] < node["threshold"] else "right"
        node = node[branch]
    return node["scores"]


def evaluate(dataset, assets=ASSETS):
    tree, scaler, thresholds = [json.loads((assets / p).read_text()) for p in ASSET_NAMES]
    df = pd.read_csv(dataset)
    features = df[scaler["feature_names"]].to_numpy(dtype=float)
    labels = df["label"].to_numpy()
    users = df["user_id"].to_numpy()
    if not np.isfinite(features).all() or set(labels) != set(CLASSES):
        raise ValueError("Se esperaban características finitas y las tres clases")
    train, temp = next(GroupShuffleSplit(n_splits=1, test_size=.30, random_state=42)
                       .split(features, labels, users))
    val_i, test_i = next(GroupShuffleSplit(n_splits=1, test_size=.50, random_state=42)
                        .split(features[temp], labels[temp], users[temp]))
    val, test = temp[val_i], temp[test_i]
    groups = [set(users[indices]) for indices in (train, val, test)]
    if any(a & b for i, a in enumerate(groups) for b in groups[i + 1:]):
        raise ValueError("Hay usuarios en más de una partición")
    normalized = (features[test] - scaler["mean"]) / (np.asarray(scaler["scale"]) + 1e-10)
    scores = np.asarray([scores_at_leaf(tree, row) for row in normalized])
    predictions = np.where(scores[:, 2] >= thresholds["threshold_critical"], 2,
                           np.where(scores[:, 1] >= thresholds["threshold_anomalous"], 1, 0))
    cm = confusion_matrix(labels[test], predictions, labels=CLASSES)
    return {
        "protocol": "frozen_android_tree_group_test_v1",
        "dataset_sha256": hashlib.sha256(dataset.read_bytes()).hexdigest(),
        "assets_sha256": {p: hashlib.sha256((assets / p).read_bytes()).hexdigest() for p in ASSET_NAMES},
        "versions": {"numpy": np.__version__, "pandas": pd.__version__, "sklearn": sklearn.__version__},
        "split_seed": 42,
        "splits": {name: {"samples": len(idx), "users": len(group)}
                   for name, idx, group in zip(("train", "validation", "test"), (train, val, test), groups)},
        "class_order": NAMES,
        "confusion_matrix": cm.tolist(),
        "accuracy": accuracy_score(labels[test], predictions),
        "report": classification_report(labels[test], predictions, labels=CLASSES,
                                        target_names=NAMES, output_dict=True, zero_division=0),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=ROOT / "training/mobility_dataset.csv")
    parser.add_argument("--assets", type=Path, default=ASSETS)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = json.dumps(evaluate(args.dataset, args.assets), ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(result, encoding="utf-8")
    else:
        print(result, end="")
