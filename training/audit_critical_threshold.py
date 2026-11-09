"""Explora los umbrales del árbol congelado sólo en validación."""
import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.model_selection import GroupShuffleSplit

from evaluate_shipped_tree import ASSETS, ASSET_NAMES, ROOT, scores_at_leaf


def audit(dataset):
    tree, scaler, thresholds = [json.loads((ASSETS / path).read_text()) for path in ASSET_NAMES]
    table = pd.read_csv(dataset)
    features = table[scaler["feature_names"]].to_numpy(dtype=float)
    labels = table["label"].to_numpy()
    users = table["user_id"].to_numpy()
    _, candidates = next(GroupShuffleSplit(n_splits=1, test_size=.30, random_state=42)
                         .split(features, labels, users))
    val, _ = next(GroupShuffleSplit(n_splits=1, test_size=.50, random_state=42)
                  .split(features[candidates], labels[candidates], users[candidates]))
    idx = candidates[val]
    normalized = (features[idx] - scaler["mean"]) / (np.asarray(scaler["scale"]) + 1e-10)
    critical = labels[idx] == 2
    scores = np.array([scores_at_leaf(tree, row)[2] for row in normalized])
    original = thresholds["threshold_critical"]
    results = []
    for threshold in sorted(set(scores) | {original, 1.0}, reverse=True):
        predicted = scores >= threshold
        tp = int((critical & predicted).sum())
        fp = int((~critical & predicted).sum())
        fn = int((critical & ~predicted).sum())
        results.append({
            "threshold": float(threshold), "original": bool(threshold == original),
            "true_critical": tp, "false_critical": fp, "missed_critical": fn,
            "sensitivity": tp / (tp + fn),
            "precision": tp / (tp + fp) if tp + fp else None,
            "f1": 2 * tp / (2 * tp + fp + fn),
        })
    return {"partition": "validation", "sample_count": len(idx),
            "user_count": len(set(users[idx])), "critical_count": int(critical.sum()),
            "thresholds": results, "model_changed": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=ROOT / "training/mobility_dataset.csv")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = json.dumps(audit(args.dataset), indent=2) + "\n"
    if args.output:
        args.output.write_text(report, encoding="utf-8")
    else:
        print(report, end="")
