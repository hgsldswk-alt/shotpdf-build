import os
from pathlib import Path
import plistlib
import sys


def options(env):
    data = plistlib.loads(Path(__file__).with_name("ExportOptions.plist").read_bytes())
    data["teamID"] = env["TEAM_ID"]
    data["provisioningProfiles"] = {
        env.get("APP_ID", "com.hgsldswk.shotpdf"): env.get("APP_PROFILE", "ShotPDF AppStore")
    }
    return data


if __name__ == "__main__":
    sys.stdout.buffer.write(plistlib.dumps(options(os.environ)))
