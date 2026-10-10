#!/bin/bash
# One command: build the pinned Terra Bookworm arm64 image.
# Usage:
#   ./examples/terra/scripts/build-image.sh
#   TERRA_ROVER_TARBALL=/path/to/terra-rover-0.2.0-linux-arm64.tar.gz \
#     ./examples/terra/scripts/build-image.sh
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../../.." && pwd)
# shellcheck disable=SC1091
source "$here/../pins.env"

cd "$root"

if [[ ! -x $root/rpi-image-gen ]]; then
   echo "build-image: missing $root/rpi-image-gen" >&2
   exit 1
fi
if ! command -v mmdebstrap >/dev/null 2>&1; then
   echo "build-image: mmdebstrap is not installed. Run: sudo ./install_deps.sh" >&2
   exit 1
fi
for tool in curl sha256sum xz bmaptool; do
   command -v "$tool" >/dev/null 2>&1 || {
      echo "build-image: missing host tool '$tool' (bmaptool is in the bmap-tools package)" >&2
      exit 1
   }
done

tarball=${TERRA_ROVER_TARBALL:-}
sha=${TERRA_ROVER_SHA256:-}
url=${TERRA_ROVER_URL:-}

if [[ -n $tarball ]]; then
   [[ -f $tarball ]] || { echo "build-image: tarball not found: $tarball" >&2; exit 1; }
   tarball=$(realpath "$tarball")
   if [[ -z $sha && -f ${tarball}.sha256 ]]; then
      sha=$(awk 'NF { print $1; exit }' "${tarball}.sha256")
   fi
   if [[ -z $sha ]]; then
      echo "build-image: set TERRA_ROVER_SHA256 or place ${tarball}.sha256 beside the tarball" >&2
      exit 1
   fi
   echo "$sha  $tarball" | sha256sum -c -
else
   [[ $sha =~ ^[0-9a-f]{64}$ ]] || {
      echo "build-image: no terra-rover tarball." >&2
      echo "Terra has no GitHub Release for this pin yet. Build one and pass it:" >&2
      echo "  git clone $TERRA_GIT_URL terra-src && cd terra-src && git checkout $TERRA_GIT_REF" >&2
      echo "  docker buildx build --platform linux/arm64 -f packaging/rover/Dockerfile --output type=local,dest=/tmp/terra-dist ." >&2
      echo "  TERRA_ROVER_TARBALL=/tmp/terra-dist/terra-rover-${TERRA_ROVER_VERSION}-linux-arm64.tar.gz $0" >&2
      exit 1
   }
   cache=$root/work/terra-cache
   mkdir -p "$cache"
   tarball=$cache/terra-rover-${TERRA_ROVER_VERSION}-linux-arm64.tar.gz
   if [[ ! -f $tarball ]] || ! echo "$sha  $tarball" | sha256sum -c - >/dev/null; then
      echo "build-image: downloading $url"
      curl --fail --location --retry 5 --retry-delay 2 --output "$tarball.partial" "$url"
      mv -f "$tarball.partial" "$tarball"
   fi
   echo "$sha  $tarball" | sha256sum -c -
fi

echo "build-image: terra-rover $(basename "$tarball") sha256 $sha"
echo "build-image: fusion-hat $TERRA_FUSION_COMMIT"

exec "$root/rpi-image-gen" build -S "$root/examples/terra" -c "$root/config/terra.yaml" -- \
   "IGconf_terra_source_ref=$TERRA_GIT_REF" \
   "IGconf_terra_rover_tarball=$tarball" \
   "IGconf_terra_rover_sha256=$sha" \
   "IGconf_terra_rover_url=$url" \
   "IGconf_terra_rover_version=$TERRA_ROVER_VERSION" \
   "IGconf_terra_fusion_commit=$TERRA_FUSION_COMMIT" \
   "IGconf_terra_fusion_sha256=$TERRA_FUSION_SHA256" \
   "IGconf_terra_fusion_version=$TERRA_FUSION_VERSION" \
   "IGconf_terra_fusion_driver_version=$TERRA_FUSION_DRIVER_VERSION"
