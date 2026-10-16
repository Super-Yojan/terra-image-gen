#!/bin/sh
# Open Raspberry Pi Imager with the Terra OS list.
# Imager 1.8, 1.9, and 2.x all accept --repo.
REPO_URL="${TERRA_IMAGER_REPO_URL:-https://github.com/Super-Yojan/terra-image-gen/releases/latest/download/terra-os-list.json}"
if command -v rpi-imager >/dev/null 2>&1; then
   exec rpi-imager --repo "$REPO_URL"
fi
echo "rpi-imager is not on PATH. Install Raspberry Pi Imager, then run:" >&2
echo "  rpi-imager --repo $REPO_URL" >&2
exit 1
