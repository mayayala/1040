"""Capture a read-only Android battery snapshot; does not reset statistics."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess


def capture(serial):
    adb = ["adb"] + (["-s", serial] if serial else [])

    def shell(*args):
        return subprocess.check_output([*adb, "shell", *args], text=True, timeout=15).strip()

    battery = {}
    for line in shell("dumpsys", "battery").splitlines():
        key, sep, value = line.strip().partition(": ")
        if sep and key in {"AC powered", "USB powered", "Wireless powered", "Dock powered",
                           "Charge counter", "level", "scale", "temperature", "status"}:
            battery[key] = int(value) if re.fullmatch(r"-?\d+", value) else value.lower()
    if not {"level", "scale", "status"} <= battery.keys():
        raise ValueError("Android no devolvió nivel, escala y estado de batería")
    if any(battery.get(key) == "true" for key in battery if key.endswith(" powered")):
        raise ValueError("El dispositivo está conectado a una fuente. Use ADB inalámbrico.")
    return {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "android_model": shell("getprop", "ro.product.model"),
        "android_release": shell("getprop", "ro.build.version.release"),
        "battery": battery,
    }


def compare(start, end):
    for key in ["android_model", "android_release", "case"]:
        if start[key] != end[key]:
            raise ValueError(f"Las capturas no coinciden en {key}")
    if start["phase"] != "start" or end["phase"] != "end":
        raise ValueError("La comparación requiere captura inicial y final, en ese orden")
    hours = (datetime.fromisoformat(end["captured_utc"]) -
             datetime.fromisoformat(start["captured_utc"])).total_seconds() / 3600
    if hours <= 0:
        raise ValueError("El intervalo debe ser positivo")
    before, after = start["battery"], end["battery"]
    level_change = 100 * (before["level"] / before["scale"] - after["level"] / after["scale"])
    ca, cb = before.get("Charge counter"), after.get("Charge counter")
    return {
        "case": start["case"], "duration_hours": hours,
        "battery_level_change_percentage_points": level_change,
        "battery_level_change_percentage_points_per_hour": level_change / hours,
        "battery_charge_change_mAh_if_available": (ca - cb) / 1000
        if isinstance(ca, int) and isinstance(cb, int) and ca > 0 and cb > 0 else None,
        "scope": "whole_device_not_app_attribution",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    command = parser.add_subparsers(dest="command", required=True)
    snapshot = command.add_parser("capture")
    snapshot.add_argument("--device")
    snapshot.add_argument("--case", choices=["baseline", "monitoring"], required=True)
    snapshot.add_argument("--phase", choices=["start", "end"], required=True)
    snapshot.add_argument("--out", type=Path, required=True)
    diff = command.add_parser("compare")
    diff.add_argument("start", type=Path)
    diff.add_argument("end", type=Path)
    args = parser.parse_args()
    if args.command == "capture":
        report = {**capture(args.device), "case": args.case, "phase": args.phase}
        with args.out.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2)
            stream.write("\n")
    else:
        print(json.dumps(compare(json.loads(args.start.read_text()),
                                 json.loads(args.end.read_text())), indent=2))
