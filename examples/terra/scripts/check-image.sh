#!/bin/bash
# Offline checks for a Terra image or an extracted rootfs.
#   check-image.sh --image path/to/terra.img
#   check-image.sh --root /mnt/rootfs [--skip-exec] [--allow-lab]
set -euo pipefail

image=
root=
skip_exec=0
allow_lab=0
cleanup_mount=0
loop=

usage() {
   echo "usage: check-image.sh --image FILE | --root DIR [--skip-exec] [--allow-lab]" >&2
   exit 2
}

while [[ $# -gt 0 ]]; do
   case "$1" in
      --image) image=${2:?}; shift 2 ;;
      --root) root=${2:?}; shift 2 ;;
      --skip-exec) skip_exec=1; shift ;;
      --allow-lab) allow_lab=1; shift ;;
      -h|--help) usage ;;
      *) echo "unknown argument: $1" >&2; usage ;;
   esac
done
[[ -n $image || -n $root ]] || usage
[[ -z $image || -z $root ]] || usage

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

tmpdir=
bootfs=
cleanup() {
   if [[ -n $root && $cleanup_mount -eq 1 ]]; then
      sudo umount "$root/proc" 2>/dev/null || true
      sudo umount "$root/dev" 2>/dev/null || true
      sudo umount "$root" 2>/dev/null || true
   fi
   if [[ -n $bootfs && $cleanup_mount -eq 1 ]]; then
      sudo umount "$bootfs" 2>/dev/null || true
   fi
   if [[ -n $loop ]]; then
      sudo losetup -d "$loop" 2>/dev/null || true
   fi
   if [[ -n $tmpdir ]]; then
      rm -rf "$tmpdir"
   fi
}
trap cleanup EXIT

if [[ -n $image ]]; then
   [[ -f $image ]] || fail "image not found: $image"
   tmpdir=$(mktemp -d)
   raw=$image
   case "$image" in
      *.xz)
         raw=$tmpdir/image.img
         echo "decompressing $image"
         xz -dc "$image" > "$raw"
         ;;
   esac
   loop=$(sudo losetup --find --show --partscan "$raw")
   # Partition nodes can lag the ioctl.
   for _ in 1 2 3 4 5 6 7 8 9 10; do
      [[ -b ${loop}p2 ]] && break
      sleep 0.2
   done
   [[ -b ${loop}p1 && -b ${loop}p2 ]] || fail "expected boot and root partitions on $loop"
   fstype=$(sudo blkid -o value -s TYPE "${loop}p2" || true)
   [[ $fstype == ext4 ]] || fail "root partition type is '${fstype:-unknown}', expected ext4"
   root=$tmpdir/root
   bootfs=$tmpdir/boot
   mkdir -p "$root" "$bootfs"
   sudo mount -o ro "${loop}p2" "$root"
   sudo mount -o ro "${loop}p1" "$bootfs"
   cleanup_mount=1
else
   bootfs=$root/boot/firmware
fi

[[ -d $root ]] || fail "rootfs not found: $root"

# Reads go through sudo when the mount is root-owned.
readf() { if [[ $cleanup_mount -eq 1 ]]; then sudo cat "$1"; else cat "$1"; fi; }
exists() { if [[ $cleanup_mount -eq 1 ]]; then sudo test -e "$1"; else test -e "$1"; fi; }
isdir() { if [[ $cleanup_mount -eq 1 ]]; then sudo test -d "$1"; else test -d "$1"; fi; }

[[ $(readf "$root/etc/hostname" | tr -d '[:space:]') == terra ]] || fail "hostname is not the placeholder 'terra'"
ok "hostname placeholder"

if exists "$root/etc/machine-id"; then
   mid=$(readf "$root/etc/machine-id" | tr -d '[:space:]')
   [[ -z $mid ]] || fail "machine-id is not empty ($mid)"
else
   fail "missing /etc/machine-id (must be an empty file, not absent)"
fi
ok "machine-id empty"

if exists "$root/etc/ssh"; then
   keys=$(if [[ $cleanup_mount -eq 1 ]]; then sudo find "$root/etc/ssh" -name 'ssh_host_*' -print; else find "$root/etc/ssh" -name 'ssh_host_*' -print; fi)
   [[ -z $keys ]] || fail "SSH host keys baked in: $keys"
fi
ok "no SSH host keys"

if [[ $allow_lab -eq 0 ]]; then
   if exists "$root/etc/systemd/system/multi-user.target.wants/ssh.service"; then
      fail "sshd is enabled (lab SSH must stay off by default)"
   fi
   ok "sshd disabled"
fi

owner_hits=$(if [[ $cleanup_mount -eq 1 ]]; then
   sudo find "$root/var/lib/terra-rover" "$root/etc/terra-rover" \( -iname '*owner*' -o -name 'device-name.json' \) -print 2>/dev/null || true
else
   find "$root/var/lib/terra-rover" "$root/etc/terra-rover" \( -iname '*owner*' -o -name 'device-name.json' \) -print 2>/dev/null || true
fi)
[[ -z $owner_hits ]] || fail "owner bond or rover name baked in: $owner_hits"
ok "no owner bond or rover name"

if [[ $allow_lab -eq 0 ]]; then
   creds=$(if [[ $cleanup_mount -eq 1 ]]; then
      sudo find "$root/etc" "$root/boot" -type f \( -name '*.nmconnection' -o -name 'wpa_supplicant*.conf' -o -name 'userconf*' \) -print 2>/dev/null || true
   else
      find "$root/etc" "$root/boot" -type f \( -name '*.nmconnection' -o -name 'wpa_supplicant*.conf' -o -name 'userconf*' \) -print 2>/dev/null || true
   fi)
   [[ -z $creds ]] || fail "Wi-Fi or user credentials baked in: $creds"
   if exists "$root/etc/shadow"; then
      hashed=$(readf "$root/etc/shadow" | awk -F: '$2 ~ /^\$/ { print $1 }')
      [[ -z $hashed ]] || fail "password hashes in /etc/shadow: $hashed"
   fi
   keys=$(if [[ $cleanup_mount -eq 1 ]]; then
      sudo find "$root/home" "$root/root" "$root/etc" -name 'authorized_keys' -size +0c -print 2>/dev/null || true
   else
      find "$root/home" "$root/root" "$root/etc" -name 'authorized_keys' -size +0c -print 2>/dev/null || true
   fi)
   [[ -z $keys ]] || fail "authorized_keys is not empty: $keys"
   ok "no Wi-Fi credentials, password hashes, or SSH public keys"
fi

[[ $(readf "$root/etc/terra-rover/rover.env" | grep -c '^TERRA_PWM_PORTS=$') -eq 1 ]] || fail "TERRA_PWM_PORTS is not empty"
unit=$(readf "$root/etc/systemd/system/terra-rover.service")
grep -q -- '--button-pairing' <<< "$unit" || fail "service is not the button-pairing command"
grep -q -- '--gate-file' <<< "$unit" && fail "service sets --gate-file"
ok "safety defaults (empty PWM list, button pairing, no gate file)"

exists "$root/etc/systemd/system/multi-user.target.wants/terra-rover.service" || fail "terra-rover.service is not enabled"
exists "$root/etc/systemd/system/sysinit.target.wants/terra-firstboot.service" || fail "terra-firstboot.service is not enabled"
ok "terra-rover and first-boot services enabled"

passwd=$(readf "$root/etc/passwd")
group=$(readf "$root/etc/group")
grep -q '^terra-rover:x:[0-9]*:[0-9]*:.*:/var/lib/terra-rover:/usr/sbin/nologin$' <<< "$passwd" || fail "terra-rover user missing or wrong"
uid=$(awk -F: '$1=="terra-rover" { print $3 }' <<< "$passwd")
gid=$(awk -F: '$1=="terra-rover" { print $4 }' <<< "$passwd")
grep -q "^terra-rover:x:${gid}:" <<< "$group" || fail "terra-rover group missing"
for g in i2c bluetooth; do
   line=$(awk -F: -v g="$g" '$1==g { print }' <<< "$group")
   [[ -n $line ]] || fail "group $g missing"
   members=${line##*:}
   case ",$members," in
      *,terra-rover,*) ;;
      *) fail "terra-rover is not in group $g ($line)" ;;
   esac
done
ok "user and groups"

own=$(if [[ $cleanup_mount -eq 1 ]]; then sudo stat -c '%u %g %a' "$root/var/lib/terra-rover"; else stat -c '%u %g %a' "$root/var/lib/terra-rover"; fi)
[[ $own == "$uid $gid 700" ]] || fail "/var/lib/terra-rover ownership is '$own', expected '$uid $gid 700'"
ok "state directory ownership"

exists "$root/usr/local/bin/terra-rover" || fail "terra-rover binary missing"
magic=$(if [[ $cleanup_mount -eq 1 ]]; then sudo od -An -tx1 -N6 "$root/usr/local/bin/terra-rover"; else od -An -tx1 -N6 "$root/usr/local/bin/terra-rover"; fi | tr -d ' \n')
machine=$(if [[ $cleanup_mount -eq 1 ]]; then sudo od -An -tx1 -j18 -N2 "$root/usr/local/bin/terra-rover"; else od -An -tx1 -j18 -N2 "$root/usr/local/bin/terra-rover"; fi | tr -d ' \n')
[[ $magic == 7f454c460201 && $machine == b700 ]] || fail "terra-rover is not an ARM64 ELF ($magic $machine)"
ok "ARM64 ELF"

if [[ $skip_exec -eq 0 ]]; then
   if [[ $cleanup_mount -eq 1 ]]; then
      sudo mount -o remount,rw "$root"
      sudo mkdir -p "$root/proc" "$root/dev" "$root/tmp"
      sudo chmod 1777 "$root/tmp"
      sudo mount -t proc proc "$root/proc"
      sudo mount --bind /dev "$root/dev"
      # The onefile binary is AArch64. Copy the interpreter into the chroot so
      # binfmt works even when the host registration does not use the F flag.
      if [[ $(uname -m) != aarch64 && -x /usr/bin/qemu-aarch64-static ]]; then
         sudo cp /usr/bin/qemu-aarch64-static "$root/usr/bin/qemu-aarch64-static"
      fi
      sudo chroot "$root" /usr/local/bin/terra-rover --check-bundle
      sudo umount "$root/dev" || true
      sudo umount "$root/proc" || true
      sudo mount -o remount,ro "$root" || true
   else
      [[ $(id -u) -eq 0 ]] || fail "--root exec check needs root, or pass --skip-exec"
      mountpoint -q "$root/proc" || mount -t proc proc "$root/proc"
      chroot "$root" /usr/local/bin/terra-rover --check-bundle
   fi
   ok "terra-rover --check-bundle"
else
   echo "skip: terra-rover --check-bundle"
fi

mapfile -t kvers < <(if [[ $cleanup_mount -eq 1 ]]; then sudo ls -1 "$root/lib/modules"; else ls -1 "$root/lib/modules"; fi)
[[ ${#kvers[@]} -gt 0 ]] || fail "no kernels under /lib/modules"
for kver in "${kvers[@]}"; do
   found=$(if [[ $cleanup_mount -eq 1 ]]; then
      sudo find "$root/lib/modules/$kver" -name 'fusion_hat.ko*' -print -quit
   else
      find "$root/lib/modules/$kver" -name 'fusion_hat.ko*' -print -quit
   fi)
   [[ -n $found ]] || fail "no fusion_hat.ko for kernel $kver"
   ok "fusion_hat module for $kver ($found)"
done
isdir "$root/usr/src/fusion_hat-1.1.0" || fail "DKMS source /usr/src/fusion_hat-1.1.0 missing"
isdir "$root/var/lib/dkms/fusion_hat" || fail "DKMS registration directory missing"
ok "DKMS source and registration"

# genimage places /boot/firmware on the FAT boot partition, so an image check
# reads config.txt and the overlay from that partition. A --root fixture keeps
# them under boot/firmware in the synthetic tree.
cfg=$(readf "$bootfs/config.txt")
grep -qx 'dtparam=i2c_arm=on' <<< "$cfg" || fail "I2C is not enabled in config.txt"
grep -qx 'dtoverlay=sunfounder-fusionhat' <<< "$cfg" || fail "Fusion HAT overlay is not enabled in config.txt"
exists "$bootfs/overlays/sunfounder-fusionhat.dtbo" || fail "overlay dtbo missing"
ok "config.txt overlay and I2C"

manifest=$(readf "$root/etc/terra-image-release")
grep -q '^TERRA_FUSION_COMMIT=4bd1018ad5a70ee113160536f969cdadd9f22918$' <<< "$manifest" || fail "manifest fusion commit"
grep -q '^TERRA_FUSION_SHA256=37ea53b9b72b6431a4a2ee8b752804ad74f0f10071c416f856991814347d9c2d$' <<< "$manifest" || fail "manifest fusion hash"
grep -q '^TERRA_ROVER_SHA256=[0-9a-f]\{64\}$' <<< "$manifest" || fail "manifest rover hash"
grep -q '^TERRA_DEVICES=pi4,pi5$' <<< "$manifest" || fail "manifest devices"
ok "build manifest"

# Vendor audio/voice packages must not be pulled in by the image.
for banned in python3-pyaudio portaudio19-dev vosk libttspico-utils; do
   if exists "$root/var/lib/dpkg/info/${banned}.list"; then
      fail "vendor-adjacent package installed: $banned"
   fi
done
ok "no vendor audio/voice packages"

echo "Terra image check passed"
