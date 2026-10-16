#!/bin/sh
# Open Raspberry Pi Imager with the Terra OS list.
# Imager 1.8, 1.9, and 2.x all accept --repo.
REPO_URL="${TERRA_IMAGER_REPO_URL:-https://github.com/Super-Yojan/terra-image-gen/releases/latest/download/terra-os-list.json}"
exec open -a "Raspberry Pi Imager" --args --repo "$REPO_URL"
