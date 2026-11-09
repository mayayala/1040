"""Comparación nueva: referencia fija independiente y las mismas observaciones GNSS."""
import argparse
import json
from pathlib import Path

import numpy as np

from comparacion import AR1GNSSModel, GEOFENCE_POIS, generate_2d_trajectory, haversine


def radius(base, accuracy, speed, hour, risk):
    value = (base * (1 + .15 * max(0, accuracy) / 10)
             * (1 + .05 * max(0, speed)) * (1.2 if hour >= 22 or hour <= 5 else 1)
             * {"high": .9, "medium": 1., "low": 1.1}.get(risk, 1.))
    return min(base * 1.5, max(base * .75, value))


def trajectory_counts(poi, seed):
    rng = np.random.default_rng(seed)
    trajectory = generate_2d_trajectory(poi, 150, rng)
    sensor = AR1GNSSModel(poi["terrain"], rng)
    counts = np.zeros((2, 2, 2), dtype=int)  # método × referencia × predicción
    inside = False
    for pt in trajectory:
        obs = sensor.observe(pt["lat"], pt["lng"], pt["speed"])
        # El radio nominal se fija antes de observar el error GNSS.
        actual_out = haversine(pt["lat"], pt["lng"], poi["lat"], poi["lng"]) > poi["radius"]
        measured_distance = haversine(obs.meas_lat, obs.meas_lng, poi["lat"], poi["lng"])
        r = radius(poi["radius"], obs.accuracy, pt["speed"], pt["hour"], poi["risk"])
        inside = measured_distance <= r * (1.05 if inside else .95)
        for model, predicted_out in enumerate((measured_distance > poi["radius"], not inside)):
            counts[model, int(actual_out), int(predicted_out)] += 1
    return counts


def metrics(matrix):
    tn, fp, fn, tp = [int(x) for x in matrix.ravel()]
    return {
        "matrix": matrix.tolist(),
        "false_positive_rate": fp / (tn + fp),
        "sensitivity": tp / (tp + fn),
        "precision": tp / (tp + fp),
        "f1": 2 * tp / (2 * tp + fp + fn),
    }


def run(n):
    if n < 1:
        raise ValueError("Se requiere al menos una trayectoria por zona")
    rng = np.random.default_rng(42)
    zones = {}
    pairs = []
    for name, poi in GEOFENCE_POIS.items():
        zone = np.stack([trajectory_counts(poi, int(seed))
                         for seed in rng.integers(0, 10**8, size=n)])
        zones[name] = zone.sum(axis=0).tolist()
        pairs.append(zone)
    static, adaptive = np.concatenate(pairs).sum(axis=0)
    # Remuestreo pareado por trayectoria, estratificado por zona.
    deltas = []
    boot = np.random.default_rng(43)
    for _ in range(1000):
        base, changed = sum(zone[boot.integers(0, n, size=n)].sum(axis=0) for zone in pairs)
        deltas.append(metrics(changed)["false_positive_rate"] - metrics(base)["false_positive_rate"])
    return {
        "protocol": "nominal_reference_paired_circular_geofences_v1",
        "seed": 42,
        "trajectories_per_zone": n,
        "zones": len(zones),
        "observations": int(static.sum()),
        "static": metrics(static),
        "adaptive": metrics(adaptive),
        "adaptive_minus_static_fpr_ci95": np.quantile(deltas, [.025, .975]).tolist(),
        "zone_matrices": zones,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trajectories", type=int, default=1000)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = json.dumps(run(args.trajectories), indent=2) + "\n"
    if args.output:
        args.output.write_text(report, encoding="utf-8")
    else:
        print(report, end="")
