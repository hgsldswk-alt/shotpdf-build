import json
import sys

want_promax = "--promax" in sys.argv
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.rsplit("iOS-", 1)[-1].split("-") if part.isdigit())
    for device in devices:
        if not device.get("isAvailable") or not device["name"].startswith("iPhone"):
            continue
        key = (version, not want_promax or "Pro Max" in device["name"])
        if best is None or key > best[0]:
            best = (key, device)
if best is None:
    sys.exit("No available iPhone simulator")
print(best[1]["udid"])
print(best[1]["name"], file=sys.stderr)
