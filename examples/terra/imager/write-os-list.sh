#!/bin/bash
# Fill examples/terra/imager/terra-os-list.json from a built image.
#   write-os-list.sh path/to/terra-bookworm-arm64.img path/to/terra-bookworm-arm64.img.xz
set -euo pipefail

img=${1:?uncompressed image}
xz=${2:?compressed image}
[[ -f $img && -f $xz ]] || { echo "missing image" >&2; exit 1; }

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=$here/terra-os-list.json
url=${TERRA_IMAGE_URL:-https://github.com/Super-Yojan/terra-image-gen/releases/download/terra-image-v0.1.0-rc3/terra-bookworm-arm64.img.xz}
date=${TERRA_RELEASE_DATE:-2026-10-14}

extract_size=$(stat -c '%s' "$img")
extract_sha=$(sha256sum "$img" | awk '{ print $1 }')
download_size=$(stat -c '%s' "$xz")
download_sha=$(sha256sum "$xz" | awk '{ print $1 }')

python3 - "$out" "$url" "$date" "$extract_size" "$extract_sha" "$download_size" "$download_sha" << 'PY'
import json, sys
out, url, date, extract_size, extract_sha, download_size, download_sha = sys.argv[1:]
doc = {
  "imager": {
    "latest_version": "1.8.5",
    "devices": [
      {
        "name": "Raspberry Pi 4",
        "description": "Pi 4, Pi 400, and Compute Module 4",
        "tags": ["pi4", "pi4-64bit"],
        "matching_type": "exclusive",
        "architecture": "armv8"
      },
      {
        "name": "Raspberry Pi 5",
        "description": "Pi 5 and Compute Module 5",
        "tags": ["pi5", "pi5-64bit"],
        "matching_type": "exclusive",
        "architecture": "armv8"
      }
    ]
  },
  "os_list": [
    {
      "name": "Terra (64-bit)",
      "description": "Raspberry Pi OS Bookworm with the Fusion HAT driver and terra-rover, for Pi 4 and Pi 5. OS customisation sets the username, password, SSH key, Wi-Fi, hostname, and locale.",
      "icon": "https://downloads.raspberrypi.com/raspios_armhf/Raspberry_Pi_OS_(32-bit).png",
      "url": url,
      "extract_size": int(extract_size),
      "extract_sha256": extract_sha,
      "image_download_size": int(download_size),
      "image_download_sha256": download_sha,
      "release_date": date,
      "devices": ["pi4", "pi5", "pi4-64bit", "pi5-64bit"],
      "init_format": "systemd"
    }
  ]
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
print(out)
print("extract_sha256", extract_sha)
print("image_download_sha256", download_sha)
PY
