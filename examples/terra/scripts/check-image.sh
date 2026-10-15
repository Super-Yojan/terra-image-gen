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
boot_mounted=0
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
   if [[ $boot_mounted -eq 1 && -n $bootfs ]]; then
      sudo umount "$bootfs" 2>/dev/null || true
   fi
   if [[ -n $loop ]]; then
      sudo partx --delete "$loop" 2>/dev/null || true
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
   loop=$(sudo losetup --read-only --find --show --partscan "$raw")
   # Some kernels do not create partition nodes from --partscan alone.
   for _ in 1 2 3 4 5 6 7 8 9 10; do
      [[ -b ${loop}p1 && -b ${loop}p2 ]] && break
      sudo partx --add "$loop" 2>/dev/null || true
      sleep 0.2
   done
   [[ -b ${loop}p1 && -b ${loop}p2 ]] || fail "expected boot and root partitions on $loop"
   fstype=$(sudo blkid -o value -s TYPE "${loop}p2" || true)
   [[ $fstype == ext4 ]] || fail "root partition type is '${fstype:-unknown}', expected ext4"
   root=$tmpdir/root
   bootfs=$tmpdir/boot
   mkdir -p "$root" "$bootfs"
   sudo mount -o ro,noload "${loop}p2" "$root"
   if sudo mount -o ro "${loop}p1" "$bootfs" 2>/dev/null; then
      boot_mounted=1
   else
      # This VM kernel has no vfat module. Read the FAT boot partition with
      # mtools so the same checks run. CI hosts that can mount vfat use the
      # mount path above.
      command -v mtype >/dev/null 2>&1 || fail "cannot mount vfat and mtools is not installed"
      start=$(sudo partx -o START -g -n 1 "$loop")
      fat="${raw}@@${start}s"
      MTOOLS_SKIP_CHECK=1 mtype -i "$fat" ::/config.txt > "$bootfs/config.txt"
      mkdir -p "$bootfs/overlays"
      MTOOLS_SKIP_CHECK=1 mcopy -n -i "$fat" ::/overlays/sunfounder-fusionhat.dtbo "$bootfs/overlays/"
      MTOOLS_SKIP_CHECK=1 mcopy -n -i "$fat" ::/initramfs8 "$bootfs/initramfs8"
      echo "ok: boot partition read with mtools (vfat is not mountable here)"
   fi
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

if exists "$root/etc/systemd/system/multi-user.target.wants/ssh.service"; then
   ok "sshd enabled"
else
   fail "sshd is not enabled"
fi
if exists "$root/etc/ssh/sshd_config.d/99-terra-access.conf"; then
   access=$(readf "$root/etc/ssh/sshd_config.d/99-terra-access.conf")
   grep -qx 'PasswordAuthentication no' <<< "$access" && fail "drop-in forces PasswordAuthentication no, which blocks an Imager password"
   grep -qx 'PubkeyAuthentication yes' <<< "$access" || fail "public-key authentication is not enabled"
   grep -qx 'PermitRootLogin no' <<< "$access" || fail "root login is not disabled"
else
   fail "missing sshd drop-in 99-terra-access.conf"
fi
ok "SSH allows a password once one is set, and allows public keys"

owner_hits=$(if [[ $cleanup_mount -eq 1 ]]; then
   sudo find "$root/var/lib/terra-rover" "$root/etc/terra-rover" \( -iname '*owner*' -o -name 'device-name.json' \) -print 2>/dev/null || true
else
   find "$root/var/lib/terra-rover" "$root/etc/terra-rover" \( -iname '*owner*' -o -name 'device-name.json' \) -print 2>/dev/null || true
fi)
[[ -z $owner_hits ]] || fail "owner bond or rover name baked in: $owner_hits"
ok "no owner bond or rover name"

if [[ $allow_lab -eq 0 ]]; then
   # Match credential files only. wpasupplicant also ships a D-Bus policy at
   # /etc/dbus-1/system.d/wpa_supplicant.conf, which is not a network config.
   creds=$(if [[ $cleanup_mount -eq 1 ]]; then
      sudo find "$root/etc" "$root/boot" -type f \( \
         -name '*.nmconnection' -o \
         -path '*/wpa_supplicant/wpa_supplicant*.conf' -o \
         -name 'userconf' -o -name 'userconf.txt' \
      \) -print 2>/dev/null || true
   else
      find "$root/etc" "$root/boot" -type f \( \
         -name '*.nmconnection' -o \
         -path '*/wpa_supplicant/wpa_supplicant*.conf' -o \
         -name 'userconf' -o -name 'userconf.txt' \
      \) -print 2>/dev/null || true
   fi)
   [[ -z $creds ]] || fail "Wi-Fi or user credentials baked in: $creds"
   if exists "$root/etc/shadow"; then
      hashed=$(readf "$root/etc/shadow" | awk -F: '$2 ~ /^\$/ { print $1 }')
      [[ -z $hashed ]] || fail "password hashes in /etc/shadow: $hashed"
      pi_pw=$(readf "$root/etc/shadow" | awk -F: '$1=="pi" { print $2 }')
      [[ $pi_pw == '*' ]] || fail "pi shadow password is '$pi_pw' (want * so public keys work and no password is set)"
   else
      fail "missing /etc/shadow"
   fi
   keys=$(if [[ $cleanup_mount -eq 1 ]]; then
      sudo find "$root/home" "$root/root" "$root/etc" -name 'authorized_keys' -size +0c -print 2>/dev/null || true
   else
      find "$root/home" "$root/root" "$root/etc" -name 'authorized_keys' -size +0c -print 2>/dev/null || true
   fi)
   [[ -z $keys ]] || fail "authorized_keys is not empty: $keys"
   ok "no Wi-Fi credentials, password hashes, or SSH public keys"
fi

[[ $(readf "$root/etc/terra-rover/rover.env" | grep -c '^TERRA_PWM_PORTS=P0,P1,P2,P3,P4,P5$') -eq 1 ]] || fail "TERRA_PWM_PORTS is not P0,P1,P2,P3,P4,P5"
unit=$(readf "$root/etc/systemd/system/terra-rover.service")
grep -q -- '--button-pairing' <<< "$unit" || fail "service is not the button-pairing command"
grep -q -- '--gate-file' <<< "$unit" && fail "service sets --gate-file"
ok "safety defaults (PWM ports P0-P5, button pairing, no gate file)"

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
snippet=$(readf "$root/etc/terra-image/fusion-hat.config")
while IFS= read -r line || [[ -n $line ]]; do
   [[ -n $line ]] || continue
   grep -qx "$line" <<< "$cfg" || fail "config.txt is missing Fusion HAT line: $line"
done <<< "$snippet"
grep -qx 'dtparam=audio=on' <<< "$cfg" && fail "dtparam=audio=on is still active"
[[ $(grep -cx 'dtoverlay=sunfounder-fusionhat' <<< "$cfg") -eq 1 ]] || fail "dtoverlay=sunfounder-fusionhat must appear once"
exists "$bootfs/overlays/sunfounder-fusionhat.dtbo" || fail "overlay dtbo missing"
ok "config.txt Fusion HAT interfaces and overlay"

i2cmod=$(readf "$root/etc/modules-load.d/terra-i2c.conf")
grep -qx 'i2c-dev' <<< "$i2cmod" || fail "i2c-dev is not loaded"
ok "i2c-dev module"

provision=$root/usr/local/sbin/terra-boot-provision
exists "$provision" || fail "terra-boot-provision missing"
prov=$(readf "$provision")
grep -q 'custom.toml' <<< "$prov" || fail "boot provisioner does not read custom.toml"
grep -q 'authorized_keys' <<< "$prov" || fail "boot provisioner does not install authorized_keys"
grep -q 'wpa_supplicant.conf' <<< "$prov" || fail "boot provisioner does not install wpa_supplicant.conf"
grep -q 'wpa_supplicant-wlan0.conf' <<< "$prov" || fail "boot provisioner does not bridge wpa_supplicant.conf"
ok "headless boot-partition provisioner"

sudoers=$(readf "$root/etc/sudoers.d/010_pi-nopasswd")
grep -qx 'pi ALL=(ALL) NOPASSWD: ALL' <<< "$sudoers" || fail "010_pi-nopasswd is missing the pi rule Imager renames"
ok "Imager sudoers rename target"

fixup=$root/etc/initramfs-tools/scripts/local-bottom/terra-imager-fixup
hook=$root/etc/initramfs-tools/hooks/terra-imager-fixup
exists "$fixup" || fail "terra-imager-fixup initramfs script missing"
exists "$hook" || fail "terra-imager-fixup initramfs hook missing"
fixup_text=$(readf "$fixup")
grep -q 'systemd\.run=/boot/firstrun' <<< "$fixup_text" || fail "fixup does not look for Imager's systemd.run path"
grep -q '/boot/firmware/firstrun.sh' <<< "$fixup_text" || fail "fixup does not rewrite the firstrun path"
grep -q '/root/boot/firstrun.sh' <<< "$fixup_text" || fail "fixup does not leave a /boot/firstrun.sh copy"
grep -q 'reboot -f' <<< "$fixup_text" || fail "fixup does not reboot so the firmware re-reads cmdline.txt"
hook_text=$(readf "$hook")
grep -q 'findmnt' <<< "$hook_text" || fail "initramfs hook does not copy findmnt"
firstboot=$root/usr/local/sbin/terra-firstboot
exists "$firstboot" || fail "terra-firstboot missing"
grep -q 'keeping hostname' <<< "$(readf "$firstboot")" || fail "first boot overwrites an Imager hostname"
ok "Imager systemd firstrun fixup"

if [[ -n $image ]]; then
   initrd=$bootfs/initramfs8
   exists "$initrd" || fail "boot partition is missing initramfs8"
   if command -v lsinitramfs >/dev/null 2>&1; then
      if [[ $cleanup_mount -eq 1 ]]; then
         listing=$(sudo lsinitramfs "$initrd")
      else
         listing=$(lsinitramfs "$initrd")
      fi
   else
      if [[ $cleanup_mount -eq 1 ]]; then
         listing=$(sudo gzip -dc "$initrd" | cpio -t 2>/dev/null || true)
      else
         listing=$(gzip -dc "$initrd" | cpio -t 2>/dev/null || true)
      fi
   fi
   grep -q 'scripts/local-bottom/terra-imager-fixup' <<< "$listing" || fail "initramfs8 does not contain terra-imager-fixup"
   grep -q 'findmnt' <<< "$listing" || fail "initramfs8 does not contain findmnt"
   ok "initramfs8 contains the Imager fixup"
fi

manifest=$(readf "$root/etc/terra-image-release")
grep -q '^TERRA_FUSION_COMMIT=4bd1018ad5a70ee113160536f969cdadd9f22918$' <<< "$manifest" || fail "manifest fusion commit"
grep -q '^TERRA_FUSION_SHA256=37ea53b9b72b6431a4a2ee8b752804ad74f0f10071c416f856991814347d9c2d$' <<< "$manifest" || fail "manifest fusion hash"
grep -q '^TERRA_ROVER_SHA256=[0-9a-f]\{64\}$' <<< "$manifest" || fail "manifest rover hash"
grep -q '^TERRA_DEVICES=pi4,pi5$' <<< "$manifest" || fail "manifest devices"
grep -q '^TERRA_PWM_PORTS=P0,P1,P2,P3,P4,P5$' <<< "$manifest" || fail "manifest PWM ports"
ok "build manifest"

# Vendor audio/voice packages must not be pulled in by the image.
for banned in python3-pyaudio portaudio19-dev vosk libttspico-utils; do
   if exists "$root/var/lib/dpkg/info/${banned}.list"; then
      fail "vendor-adjacent package installed: $banned"
   fi
done
ok "no vendor audio/voice packages"

echo "Terra image check passed"
