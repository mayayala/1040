#!/usr/bin/env bash
set -euo pipefail

log="${RUNNER_TEMP:-/tmp}/geocercas-integration.log"
rm -f "$log"
flutter test integration_test/monitoring_flow_test.dart -d emulator-5554 \
  --dart-define=LOCAL_FIREBASE_INTEGRATION=true --reporter expanded 2>&1 | tee "$log"

python3 - "$log" <<'PY'
import json
import math
from pathlib import Path
import re
import sys

log = Path(sys.argv[1])
records = re.findall(r"INTEGRATION_EVIDENCE (\{[^\r\n]*\})", log.read_text())
if len(records) != 1:
    raise SystemExit("Expected one Android integration result.")
result = json.loads(records[0])
times = sorted(result["sync_sample_ms"])
result["sync_p50_ms"] = times[math.ceil(len(times) * 0.50) - 1]
result["sync_p95_ms"] = times[math.ceil(len(times) * 0.95) - 1]
result["sync_max_ms"] = times[-1]
result["tree_mean_us"] = result["tree_total_us"] / result["tree_inferences"]
result["battery_physical_measurement"] = None
path = log.with_name("geocercas-android-integration.json")
path.write_text(json.dumps(result, indent=2) + "\n")
print(path.read_text())
PY
