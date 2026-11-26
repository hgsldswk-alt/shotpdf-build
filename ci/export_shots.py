import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

LANGUAGES = ("ja", "en", "zh-Hans", "zh-Hant")
SCENES = ("01-home", "02-arrange", "03-layout", "04-split", "05-result")
EXPECTED = {f"store-{lang}-{shot}" for lang in LANGUAGES for shot in SCENES} | {"paid-01-paywall"}
NAMES = re.compile(r"store-(?:ja|en|zh-Hans|zh-Hant)-\d{2}-[a-z]+|paid-01-paywall")


def export_manifest(raw, output):
    current = {}

    def find(node):
        if isinstance(node, list):
            for item in node:
                find(item)
        elif isinstance(node, dict):
            if "exportedFileName" in node:
                name = NAMES.search(str(node.get("suggestedHumanReadableName", "")))
                if name and name[0] in EXPECTED:
                    asset = (raw / node["exportedFileName"]).resolve()
                    if not asset.is_relative_to(raw.resolve()) or not asset.is_file() or asset.suffix.lower() != ".png":
                        raise ValueError(f"Invalid attachment for {name[0]}")
                    if name[0] in current:
                        raise ValueError(f"Duplicate attachment: {name[0]}")
                    current[name[0]] = asset
            else:
                for item in node.values():
                    find(item)

    find(json.loads((raw / "manifest.json").read_text(encoding="utf-8")))
    if missing := EXPECTED - current.keys():
        raise ValueError("Missing screenshots: " + ", ".join(sorted(missing)))
    output.mkdir(parents=True, exist_ok=True)
    for name, asset in current.items():
        shutil.copy2(asset, output / f"{name}.png")


def main(result, output):
    with TemporaryDirectory(prefix="shotpdf-shots-") as temp:
        raw = Path(temp)
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", result,
                        "--output-path", str(raw)], check=True)
        export_manifest(raw, Path(output))
    print(f"Exported {len(EXPECTED)} screenshots to {output}")


if __name__ == "__main__":
    main(*sys.argv[1:])
