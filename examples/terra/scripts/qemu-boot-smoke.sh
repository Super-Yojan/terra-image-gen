#!/bin/bash
# Best-effort boot of the Terra image under QEMU. The Fusion HAT and Bluetooth
# controller are absent. Success is systemd reaching terra-rover and the
# process staying up (it logs "Enrollment unavailable" and waits). A restart
# loop is a failure. If the Pi kernel cannot see the virt disk, the result is
# "not verified" rather than a pass.
set -euo pipefail

image=${1:?usage: qemu-boot-smoke.sh IMAGE.img}
log=${2:-/tmp/terra-qemu-boot.log}
[[ -f $image ]] || { echo "missing $image" >&2; exit 1; }
command -v qemu-system-aarch64 >/dev/null 2>&1 || { echo "qemu-system-aarch64 is not installed" >&2; exit 1; }

tmpdir=$(mktemp -d)
cleanup() {
   if [[ -n ${loop:-} ]]; then
      sudo partx --delete "$loop" 2>/dev/null || true
      sudo losetup -d "$loop" 2>/dev/null || true
   fi
   sudo umount "$tmpdir/boot" 2>/dev/null || true
   rm -rf "$tmpdir"
}
trap cleanup EXIT

loop=$(sudo losetup --find --show --partscan "$image")
for _ in 1 2 3 4 5 6 7 8 9 10; do
   [[ -b ${loop}p1 ]] && break
   sudo partx --add "$loop" 2>/dev/null || true
   sleep 0.2
done
[[ -b ${loop}p1 ]] || { echo "no boot partition on $loop" >&2; exit 1; }
mkdir -p "$tmpdir/boot"
kernel=
if sudo mount -o ro "${loop}p1" "$tmpdir/boot" 2>/dev/null; then
   for candidate in kernel8.img kernel_2712.img; do
      if sudo test -f "$tmpdir/boot/$candidate"; then
         sudo cp "$tmpdir/boot/$candidate" "$tmpdir/$candidate"
         sudo chmod 0644 "$tmpdir/$candidate"
         kernel=$tmpdir/$candidate
         # Prefer the 4K v8 kernel under QEMU's virt machine.
         [[ $candidate == kernel8.img ]] && break
      fi
   done
   sudo umount "$tmpdir/boot"
else
   command -v mcopy >/dev/null 2>&1 || { echo "cannot mount vfat and mtools is not installed" >&2; exit 1; }
   start=$(sudo partx -o START -g -n 1 "$loop")
   fat="${image}@@${start}s"
   for candidate in kernel8.img kernel_2712.img; do
      if MTOOLS_SKIP_CHECK=1 mcopy -n -i "$fat" "::/$candidate" "$tmpdir/" 2>/dev/null; then
         kernel=$tmpdir/$candidate
         [[ $candidate == kernel8.img ]] && break
      fi
   done
fi
[[ -n $kernel ]] || { echo "no kernel8.img or kernel_2712.img on the boot partition" >&2; exit 1; }

echo "qemu-boot: kernel $kernel" | tee "$log"
# 90s is enough to reach multi-user on virt when the kernel has virtio.
# The Pi kernel often does not, which this script reports as not verified.
set +e
timeout 90 qemu-system-aarch64 \
   -machine virt -cpu cortex-a72 -m 2048 -smp 2 -nographic -no-reboot \
   -kernel "$kernel" \
   -append "console=ttyAMA0,115200 root=/dev/vda2 rootwait rw" \
   -drive "file=$image,if=virtio,format=raw,readonly=on" \
   -serial "file:$log.append" \
   >> "$log" 2>&1
rc=$?
set -e
cat "$log.append" >> "$log" 2>/dev/null || true

if grep -E -q 'Start request repeated too quickly|terra-rover.service: Failed with result' "$log"; then
   echo "qemu-boot: FAIL terra-rover crash-looped" | tee -a "$log"
   exit 1
fi
# A mention of the unit name is not success. bluetooth.service is Required,
# so a missing controller can stop the unit from ever starting.
if grep -E -q 'Enrollment unavailable|Started Terra owner-only' "$log"; then
   echo "qemu-boot: PASS systemd reached terra-rover and it stayed up without the HAT" | tee -a "$log"
   exit 0
fi
if grep -E -q 'systemd|Welcome to' "$log"; then
   echo "qemu-boot: NOT VERIFIED systemd started but terra-rover was not observed" | tee -a "$log"
   exit 2
fi
echo "qemu-boot: NOT VERIFIED (QEMU virt did not boot this Raspberry Pi kernel far enough). See $log" | tee -a "$log"
exit 2
