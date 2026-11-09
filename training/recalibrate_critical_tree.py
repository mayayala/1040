"""Select a depth-three Android tree on grouped validation; audit on new synthetic users."""
import argparse
from contextlib import redirect_stdout
from hashlib import sha256
from io import StringIO
from itertools import product
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.model_selection import GroupShuffleSplit
from sklearn.preprocessing import StandardScaler
from sklearn.tree import DecisionTreeClassifier

from evaluate_shipped_tree import ASSET_NAMES, ROOT, scores_at_leaf
from generate_dataset import generate_dataset

ASSETS = ROOT / "assets" / "ml"
BASELINE = ROOT / "training" / "baseline_android_tree"
HOLDOUT_SEED = 104081
MINIMUM = .80
VALIDATION_TARGET = .82


def read_assets(folder):
    return tuple(json.loads((folder / name).read_text()) for name in ASSET_NAMES)


def scores(tree, x):
    return np.asarray([scores_at_leaf(tree, row) for row in x])


def normalized(x, scaler):
    return (x - scaler["mean"]) / (np.asarray(scaler["scale"]) + 1e-10)


def predict(p, anomalous, critical):
    return np.where(p[:, 2] >= critical, 2, np.where(p[:, 1] >= anomalous, 1, 0))


def metrics(y, pred):
    cm = np.bincount(3 * y + pred, minlength=9).reshape(3, 3)
    tp = cm[2, 2]
    fp = cm[:, 2].sum() - tp
    fn = cm[2, :].sum() - tp
    class_f1 = 2 * cm.diagonal() / (cm.sum(axis=0) + cm.sum(axis=1))
    return {
        "matrix": cm.tolist(), "samples": int(cm.sum()),
        "true_critical": int(tp), "false_critical": int(fp), "missed_critical": int(fn),
        "sensitivity_critical": float(tp / (tp + fn)),
        "precision_critical": float(tp / (tp + fp)) if tp + fp else 0.,
        "f1_critical": float(class_f1[2]), "f1_macro": float(class_f1.mean()),
        "fpr_critical": float(fp / (cm.sum() - tp - fn)),
        "accuracy": float(cm.trace() / cm.sum()),
    }


def evaluate(assets, x, y):
    tree, scaler, thresholds = assets
    return metrics(y, predict(scores(tree, normalized(x, scaler)),
                             thresholds["threshold_anomalous"],
                             thresholds["threshold_critical"]))


def export(model, x, y, features):
    t = model.tree_
    leaf_ids = model.apply(x)
    def node(i):
        if t.children_left[i] == -1:
            # Class frequencies from training rows, before class weighting.
            counts = np.bincount(y[leaf_ids == i], minlength=3)
            return {"scores": (counts / counts.sum()).tolist()}
        return {"feature": features[t.feature[i]], "threshold": float(t.threshold[i]),
                "left": node(t.children_left[i]), "right": node(t.children_right[i])}
    return node(0)


def select(x, y, train, validation, names, baseline):
    fitted = StandardScaler().fit(x[train])
    scaler = {"feature_names": names, "mean": fitted.mean_.tolist(), "scale": fitted.scale_.tolist()}
    x_train = normalized(x[train], scaler)
    x_val = normalized(x[validation], scaler)
    y_val = y[validation]
    best = None

    def consider(tree, params, model_scaler, values):
        nonlocal best
        anomalous_set = set(values[:, 1]) | {.25, .5, 1.}
        for critical in sorted(set(values[:, 2]) | {.4, .5, 1.}):
            crit = values[:, 2] >= critical
            tp = (crit & (y_val == 2)).sum()
            if tp / (y_val == 2).sum() < VALIDATION_TARGET:
                continue
            for anomalous in sorted(anomalous_set):
                m = metrics(y_val, predict(values, anomalous, critical))
                # Prefer critical F1, then fewer false criticals, then class balance.
                key = (m["f1_critical"], -m["false_critical"], m["f1_macro"], m["accuracy"])
                if best is None or key > best[0]:
                    thresholds = {"threshold_anomalous": float(anomalous),
                                  "threshold_critical": float(critical)}
                    best = (key, (tree, model_scaler, thresholds), params, m)

    consider(baseline[0], {"family": "original_tree_thresholds_only"},
             baseline[1], scores(baseline[0], normalized(x[validation], baseline[1])))
    feature_sets = (tuple(range(len(names))), (0, 1, 2, 6), (0, 1, 2, 4, 5, 6))
    for features, leaf, critical_weight, anomalous_weight, criterion in product(
            feature_sets, (10, 20, 40, 80), (1., 2., 3., 5., 8., 12., 18.),
            (1., 2., 4., None), ("gini", "entropy")):
        binary = anomalous_weight is None
        target = (y[train] == 2).astype(int) if binary else y[train]
        weights = ({0: 1., 1: critical_weight} if binary
                   else {0: 1., 1: anomalous_weight, 2: critical_weight})
        params = dict(max_depth=3, min_samples_leaf=leaf, criterion=criterion,
                      class_weight=weights, random_state=42)
        model = DecisionTreeClassifier(**params).fit(x_train[:, features], target)
        tree = export(model, x_train[:, features], y[train], features)
        family = "critical_split_decision_tree" if binary else "weighted_decision_tree"
        consider(tree, {"family": family, "eligible_features": [names[i] for i in features],
                        **params}, scaler, scores(tree, x_val))
    if best is None:
        raise ValueError("No candidate meets the validation threshold.")
    return best[1:]


def run(dataset):
    baseline = read_assets(BASELINE)
    names = baseline[1]["feature_names"]
    df = pd.read_csv(dataset)
    x, y, users = df[names].to_numpy(dtype=float), df["label"].to_numpy(), df["user_id"].to_numpy()
    train, rest = next(GroupShuffleSplit(n_splits=1, test_size=.30, random_state=42)
                       .split(x, y, users))
    val, test = next(GroupShuffleSplit(n_splits=1, test_size=.50, random_state=42)
                     .split(x[rest], y[rest], users[rest]))
    val, test = rest[val], rest[test]
    assert not any(set(users[a]) & set(users[b]) for a, b in ((train, val), (val, test), (train, test)))
    candidate, params, m_val = select(x, y, train, val, names, baseline)

    # Generate only after selection, with new synthetic users and a fixed seed.
    np.random.seed(HOLDOUT_SEED)
    with redirect_stdout(StringIO()):
        holdout = generate_dataset(n_users=200, windows_per_user=10)
    holdout["user_id"] += int(users.max()) + 1
    assert not set(holdout["user_id"]) & set(users)
    xa, ya = holdout[names].to_numpy(dtype=float), holdout["label"].to_numpy()
    result = {
        "protocol": "group_validation_then_new_synthetic_users_v1",
        "dataset_sha256": sha256(dataset.read_bytes()).hexdigest(),
        "baseline_assets_sha256": {p: sha256((BASELINE / p).read_bytes()).hexdigest() for p in ASSET_NAMES},
        "validation_target": VALIDATION_TARGET, "minimum_sensitivity": MINIMUM,
        "candidate": params, "thresholds": candidate[2],
        "partitions": {
            "validation": {"users": len(set(users[val])), "baseline": evaluate(baseline, x[val], y[val]),
                           "candidate": m_val},
            "historical_test_comparison": {
                "users": len(set(users[test])), "baseline": evaluate(baseline, x[test], y[test]),
                "candidate": evaluate(candidate, x[test], y[test])},
            "new_synthetic_test": {
                "users": int(holdout["user_id"].nunique()), "seed": HOLDOUT_SEED,
                "baseline": evaluate(baseline, xa, ya), "candidate": evaluate(candidate, xa, ya)},
        },
    }
    for partition in ("historical_test_comparison", "new_synthetic_test"):
        result["partitions"][partition]["meets_minimum"] = (
            result["partitions"][partition]["candidate"]["sensitivity_critical"] >= MINIMUM)
    return candidate, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=ROOT / "training/mobility_dataset.csv")
    parser.add_argument("--asset-output", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    candidate, result = run(args.dataset)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    args.asset_output.mkdir(parents=True, exist_ok=True)
    for name, data in zip(ASSET_NAMES, candidate):
        (args.asset_output / name).write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
