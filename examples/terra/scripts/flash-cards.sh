#!/bin/bash
# Write one Terra image to one or more SD cards and verify each write.
#
#   sudo ./examples/terra/scripts/flash-cards.sh --yes IMAGE.img.xz /dev/sdX [/dev/sdY ...]
#
# IMAGE.img.bmap must sit next to the .img.xz (or pass --bmap).
# Without --yes the script only prints the plan.
set -euo pipefail

yes=0
bmap=
image=
devices=()

usage() {
   echo "usage: sudo flash-cards.sh [--yes] [--bmap FILE] IMAGE.img.xz /dev/disk..." >&2
   exit 2
}

while [[ $# -gt 0 ]]; do
   case "$1" in
      --yes) yes=1; shift ;;
      --bmap) bmap=${2:?}; shift 2 ;;
      -h|--help) usage ;;
      --) shift; break ;;
      -*) echo "unknown option: $1" >&2; usage ;;
      *)
         if [[ -z $image ]]; then image=$1; else devices+=("$1"); fi
         shift
         ;;
   esac
done
[[ -n $image && ${#devices[@]} -gt 0 ]] || usage
[[ -f $image ]] || { echo "flash-cards: image not found: $image" >&2; exit 1; }
image=$(realpath "$image")
if [[ -z $bmap ]]; then
   case "$image" in
      *.xz) bmap=${image%.xz}.bmap ;;
      *) bmap=$image.bmap ;;
   esac
fi
[[ -f $bmap ]] || { echo "flash-cards: bmap not found: $bmap" >&2; exit 1; }
command -v bmaptool >/dev/null 2>&1 || { echo "flash-cards: install bmap-tools" >&2; exit 1; }

root_src=$(findmnt -no SOURCE / || true)
root_disk=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n 1 || true)

for dev in "${devices[@]}"; do
   [[ -b $dev ]] || { echo "flash-cards: not a block device: $dev" >&2; exit 1; }
   base=$(basename "$dev")
   case "$base" in
      *[0-9]) echo "flash-cards: $dev looks like a partition. Pass the whole disk." >&2; exit 1 ;;
   esac
   if [[ -n $root_disk && $base == "$root_disk" ]]; then
      echo "flash-cards: refusing to write the disk that holds / ($dev)" >&2
      exit 1
   fi
   # Removable or mmc only, unless the caller really means a USB stick.
   tran=$(lsblk -no TRAN "$dev" 2>/dev/null | head -n 1 || true)
   rm=$(lsblk -no RM "$dev" 2>/dev/null | head -n 1 || true)
   case "$tran" in
      usb|mmc) ;;
      *)
         if [[ $rm != 1 ]]; then
            echo "flash-cards: $dev is not removable (tran=${tran:-unknown}). Refusing." >&2
            exit 1
         fi
         ;;
   esac
done

echo "image: $image"
echo "bmap:  $bmap"
printf 'cards:'
printf ' %s' "${devices[@]}"
printf '\n'

if [[ $yes -ne 1 ]]; then
   echo "flash-cards: dry run. Re-run with --yes to write and verify."
   exit 0
fi
[[ $(id -u) -eq 0 ]] || { echo "flash-cards: --yes needs root" >&2; exit 1; }

for dev in "${devices[@]}"; do
   echo "flash-cards: writing $dev"
   # bmaptool copies and verifies the blocks listed in the bmap.
   bmaptool copy --bmap "$bmap" "$image" "$dev"
   sync
   echo "flash-cards: verified $dev"
done
echo "flash-cards: wrote ${#devices[@]} card(s)"
