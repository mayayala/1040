"""Write the fictional google-services.json for the Android integration test."""
import json
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "android/app/google-services.json"
if path.exists():
    raise SystemExit("Refusing to overwrite existing Firebase configuration.")
path.write_text(json.dumps({
    "project_info": {"project_number": "1234567890", "project_id": "demo-geocercas"},
    "client": [{
        "client_info": {
            "mobilesdk_app_id": "1:1234567890:android:0000000000000000",
            "android_client_info": {"package_name": "com.umsa.geocercas"},
        },
        "api_key": [{"current_key": "emulator-only-not-a-real-key"}],
    }],
    "configuration_version": "1",
}, indent=2) + "\n")
