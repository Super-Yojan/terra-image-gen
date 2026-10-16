#!/bin/bash
# Apply the firstrun.sh that Raspberry Pi Imager 1.8 and 2.x write for
# init_format=systemd, then the initramfs path rewrite, then Terra's second
# boot. Proves a username and password from Imager are the ones that log in.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/../../.." && pwd)
overlay=$repo/examples/terra/layer/terra.d/customize.overlay
fixup=$overlay/etc/initramfs-tools/scripts/local-bottom/terra-imager-fixup
image=

while [[ $# -gt 0 ]]; do
   case "$1" in
      --image) image=${2:?}; shift 2 ;;
      *) echo "unknown argument: $1" >&2; exit 2 ;;
   esac
done

tmp=$(mktemp -d)
cleanup_tmp() {
   local m
   while read -r m; do
      sudo umount "$m" 2>/dev/null || true
   done < <(awk -v t="$tmp" '$2 ~ t { print $2 }' /proc/mounts | sort -r)
   sudo rm -rf "$tmp"
}
trap cleanup_tmp EXIT

fail() { echo "imager firstrun: $*" >&2; exit 1; }

copy_path() {
   local src=$1 root=$2 real
   [[ -e $src ]] || return 0
   real=$(readlink -f "$src")
   mkdir -p "$root$(dirname "$real")"
   cp -a "$real" "$root$real"
   if [[ $src != "$real" ]]; then
      mkdir -p "$root$(dirname "$src")"
      ln -sfn "$real" "$root$src"
   fi
}

copy_bin() {
   local root=$1 bin=$2 path lib
   path=$(type -P "$bin") || fail "host is missing $bin"
   copy_path "$path" "$root"
   while read -r lib; do
      [[ -n $lib ]] || continue
      copy_path "$lib" "$root"
   done < <(ldd "$path" 2>/dev/null | awk '/=> \// { print $3 } /^\t\// { print $1 }')
}

prepare_root() {
   local root=$1
   mkdir -p "$root/etc/ssh/sshd_config.d" "$root/etc/sudoers.d" "$root/home/pi" \
      "$root/etc/default" "$root/etc/wpa_supplicant" "$root/usr/local/sbin" \
      "$root/usr/bin" "$root/usr/sbin" "$root/bin" "$root/sbin" \
      "$root/tmp" "$root/boot/firmware" "$root/etc/terra-image" \
      "$root/etc/systemd/system/multi-user.target.wants" \
      "$root/lib/systemd/system" "$root/dev"
   printf '%s\n' 'pi:x:1000:1000::/home/pi:/bin/bash' > "$root/etc/passwd"
   printf '%s\n' 'pi:x:1000:' > "$root/etc/group"
   printf '%s\n' 'pi:!::' > "$root/etc/gshadow" || true
   printf '%s\n' 'pi:*:19000:0:99999:7:::' > "$root/etc/shadow"
   chmod 0640 "$root/etc/shadow"
   printf '%s\n' 'pi ALL=(ALL) NOPASSWD: ALL' > "$root/etc/sudoers.d/010_pi-nopasswd"
   chmod 0440 "$root/etc/sudoers.d/010_pi-nopasswd"
   printf '%s\n' terra > "$root/etc/hostname"
   printf '%s\n' '127.0.1.1 terra' > "$root/etc/hosts"
   printf '%s\n' 'passwd: files' 'group: files' 'shadow: files' > "$root/etc/nsswitch.conf"
   cat > "$root/etc/ssh/sshd_config" << 'EOF'
Include /etc/ssh/sshd_config.d/*.conf
#PasswordAuthentication yes
EOF
   cp "$overlay/etc/ssh/sshd_config.d/99-terra-access.conf" \
      "$root/etc/ssh/sshd_config.d/99-terra-access.conf"
   cp "$overlay/etc/terra-image/fusion-hat.config" "$root/etc/terra-image/fusion-hat.config"
   cat > "$root/boot/firmware/config.txt" << 'EOF'
dtparam=i2c_arm=on
dtparam=i2s=on
dtparam=spi=on
dtparam=audio=off
# Terra Fusion HAT.
[all]
dtparam=i2c_arm=on
dtparam=i2s=on
dtparam=spi=on
dtparam=audio=off
dtoverlay=sunfounder-fusionhat
EOF
   : > "$root/lib/systemd/system/ssh.service"
   : > "$root/lib/systemd/system/wpa_supplicant@.service"
   install -m 0755 "$overlay/usr/local/sbin/terra-boot-provision" "$root/usr/local/sbin/terra-boot-provision"
   install -m 0755 "$overlay/usr/local/sbin/terra-firstboot" "$root/usr/local/sbin/terra-firstboot"
   cat > "$root/usr/bin/systemctl" << 'EOF'
#!/bin/sh
printf '%s\n' "$*" >> /tmp/systemctl.log
exit 0
EOF
   cat > "$root/usr/sbin/dpkg-reconfigure" << 'EOF'
#!/bin/sh
printf '%s\n' "$*" >> /tmp/dpkg-reconfigure.log
exit 0
EOF
   cat > "$root/usr/sbin/rfkill" << 'EOF'
#!/bin/sh
exit 0
EOF
   cat > "$root/usr/sbin/iw" << 'EOF'
#!/bin/sh
exit 0
EOF
   cat > "$root/usr/bin/hostname" << 'EOF'
#!/bin/sh
exit 0
EOF
   cat > "$root/sbin/reboot" << 'EOF'
#!/bin/sh
printf '%s\n' "$*" >> /tmp/reboot.log
exit 0
EOF
   chmod 0755 "$root/usr/bin/systemctl" "$root/usr/sbin/dpkg-reconfigure" \
      "$root/usr/sbin/rfkill" "$root/usr/sbin/iw" "$root/usr/bin/hostname" \
      "$root/sbin/reboot"
   # chpasswd and usermod are the host's real tools, so the hash is applied
   # the same way the Pi applies it.
   local bin
   for bin in bash sh getent chpasswd usermod groupmod sed cut cat install chmod \
      chown echo tr printf mkdir id mv grep awk rm mktemp mountpoint dirname basename \
      head tail sort sync
   do
      copy_bin "$root" "$bin"
   done
   local nss
   for nss in /lib/*/libnss_files.so.2 /lib/*/libnss_compat.so.2; do
      [[ -f $nss ]] || continue
      mkdir -p "$root$(dirname "$nss")"
      cp -an "$nss" "$root$nss" 2>/dev/null || cp -a "$nss" "$root$nss"
   done
   [[ -x $root/usr/bin/bash && ! -e $root/bin/bash ]] && ln -s ../usr/bin/bash "$root/bin/bash"
   [[ -x $root/usr/bin/sh && ! -e $root/bin/sh ]] && ln -s ../usr/bin/sh "$root/bin/sh"
   [[ -f /etc/login.defs ]] && cp -a /etc/login.defs "$root/etc/login.defs"
   [[ -f /etc/pam.d/chpasswd ]] && mkdir -p "$root/etc/pam.d" && cp -a /etc/pam.d/chpasswd "$root/etc/pam.d/chpasswd"
   [[ -f /etc/pam.d/common-password ]] && cp -a /etc/pam.d/common-password "$root/etc/pam.d/common-password" || true
   [[ -f /etc/pam.d/other ]] && cp -a /etc/pam.d/other "$root/etc/pam.d/other" || true
   sudo mkdir -p "$root/dev"
   sudo mknod -m 666 "$root/dev/null" c 1 3
   sudo mknod -m 666 "$root/dev/zero" c 1 5
   sudo mknod -m 666 "$root/dev/random" c 1 8
   sudo mknod -m 666 "$root/dev/urandom" c 1 9
}

run_in() {
   local root=$1
   shift
   sudo chroot "$root" "$@"
}

# --- fixup rewrites Imager's /boot paths ---
boot=$tmp/boot
mkdir -p "$boot"
cat > "$boot/cmdline.txt" << 'EOF'
console=serial0,115200 console=tty1 rootwait systemd.run=/boot/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target
EOF
cat > "$boot/firstrun.sh" << 'EOF'
#!/bin/bash

set +e

echo keep-me
rm -f /boot/firstrun.sh
sed -i 's| systemd.run.*||g' /boot/cmdline.txt
exit 0
EOF
TERRA_IMAGER_FIXUP_DIR=$boot "$fixup"
grep -q 'systemd.run=/boot/firmware/firstrun.sh' "$boot/cmdline.txt" || fail "cmdline was not rewritten"
grep -q 'keep-me' "$boot/firstrun.sh" || fail "fixup dropped the firstrun body"
grep -q 'rm -f /boot/firmware/firstrun.sh' "$boot/firstrun.sh" || fail "cleanup path was not rewritten"
if grep -q 'rm -f /boot/firstrun.sh$' "$boot/firstrun.sh"; then
   fail "old /boot/firstrun.sh cleanup still present"
fi
echo "ok: initramfs rewrite of Imager 1.8/2.x cmdline and firstrun.sh"

password='imager-secret'
hash6=$(openssl passwd -6 -salt testsalt "$password")
[[ $hash6 == \$6\$* ]] || fail "openssl did not produce a sha512crypt hash"
# Imager 2.x emits yescrypt when release_date is 2023-01-01 or later.
hashy=$(python3 -c 'import crypt; print(crypt.crypt("imager-secret", "$y$j9T$0123456789abcdef"))')
[[ $hashy == \$y\$* ]] || fail "yescrypt hash did not start with \$y\$"

write_18() {
   local dest=$1 hash=$2
   cat > "$dest" << EOF
#!/bin/bash

set +e

CURRENT_HOSTNAME=\`cat /etc/hostname | tr -d " \\t\\n\\r"\`
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom set_hostname terra-lab
else
   echo terra-lab >/etc/hostname
   sed -i "s/127.0.1.1.*\$CURRENT_HOSTNAME/127.0.1.1\\tterra-lab/g" /etc/hosts
fi
FIRSTUSER=\`getent passwd 1000 | cut -d: -f1\`
FIRSTUSERHOME=\`getent passwd 1000 | cut -d: -f6\`
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom enable_ssh
else
   systemctl enable ssh
fi
if [ -f /usr/lib/userconf-pi/userconf ]; then
   /usr/lib/userconf-pi/userconf 'rover' '${hash}'
else
   echo "\$FIRSTUSER:"'${hash}' | chpasswd -e
   if [ "\$FIRSTUSER" != "rover" ]; then
      usermod -l "rover" "\$FIRSTUSER"
      usermod -m -d "/home/rover" "rover"
      groupmod -n "rover" "\$FIRSTUSER"
      if grep -q "^autologin-user=" /etc/lightdm/lightdm.conf ; then
         sed /etc/lightdm/lightdm.conf -i -e "s/^autologin-user=.*/autologin-user=rover/"
      fi
      if [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]; then
         sed /etc/systemd/system/getty@tty1.service.d/autologin.conf -i -e "s/\$FIRSTUSER/rover/"
      fi
      if [ -f /etc/sudoers.d/010_pi-nopasswd ]; then
         sed -i "s/^\$FIRSTUSER /rover /" /etc/sudoers.d/010_pi-nopasswd
      fi
   fi
fi
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   true
else
cat >/etc/wpa_supplicant/wpa_supplicant.conf <<'WPAEOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
ap_scan=1

update_config=1
network={
	ssid="lab"
	psk=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
}
WPAEOF
   chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
   rfkill unblock wifi
fi
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   true
else
   rm -f /etc/localtime
   echo "America/New_York" >/etc/timezone
   dpkg-reconfigure -f noninteractive tzdata
cat >/etc/default/keyboard <<'KBEOF'
XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""

KBEOF
   dpkg-reconfigure -f noninteractive keyboard-configuration
fi
rm -f /boot/firstrun.sh
sed -i 's| systemd.run.*||g' /boot/cmdline.txt
exit 0
EOF
}

assert_password_applied() {
   local root=$1 hash=$2 label=$3
   local got
   got=$(awk -F: '$1=="rover" { print $2 }' "$root/etc/shadow")
   [[ $got == "$hash" ]] || fail "$label shadow hash is not the Imager hash"
   case $hash in
      \$6\$*)
         [[ $(openssl passwd -6 -salt testsalt "$password") == "$got" ]] || fail "$label password does not verify"
         ;;
      \$y\$*)
         python3 -c 'import crypt,sys; h=sys.argv[1]; raise SystemExit(crypt.crypt("imager-secret", h)!=h)' "$got" \
            || fail "$label yescrypt password does not verify"
         ;;
   esac
   [[ $(awk -F: '$3==1000 { print $1 }' "$root/etc/passwd") == rover ]] || fail "$label uid 1000 was not renamed"
   [[ -d $root/home/rover ]] || fail "$label home was not moved"
   grep -qx 'rover ALL=(ALL) NOPASSWD: ALL' "$root/etc/sudoers.d/010_pi-nopasswd" || fail "$label sudoers was not renamed"
   [[ $(tr -d '[:space:]' < "$root/etc/hostname") == terra-lab ]] || fail "$label hostname"
   grep -q '127.0.1.1' "$root/etc/hosts"
   grep -q 'ssid="lab"' "$root/etc/wpa_supplicant/wpa_supplicant.conf"
   [[ $(stat -c '%a' "$root/etc/wpa_supplicant/wpa_supplicant.conf") == 600 ]]
   [[ $(tr -d '[:space:]' < "$root/etc/timezone") == America/New_York ]]
   grep -q 'XKBLAYOUT="us"' "$root/etc/default/keyboard"
   grep -q 'tzdata' "$root/tmp/dpkg-reconfigure.log"
   grep -q 'keyboard-configuration' "$root/tmp/dpkg-reconfigure.log"
   grep -qx 'PasswordAuthentication no' "$root/etc/ssh/sshd_config.d/99-terra-access.conf" \
      && fail "$label drop-in still forces password authentication off"
   if grep -q '^PasswordAuthentication no' "$root/etc/ssh/sshd_config"; then
      fail "$label password-only firstrun disabled password authentication"
   fi
   echo "ok: $label applied username, password, Wi-Fi, hostname, and locale"
}

run_host_case() {
   local name=$1 writer=$2 hash=$3
   local root=$tmp/$name bootdir=$tmp/${name}-boot
   mkdir -p "$bootdir"
   printf '%s\n' 'console=serial0,115200 rootwait systemd.run=/boot/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target' > "$bootdir/cmdline.txt"
   "$writer" "$bootdir/firstrun.sh" "$hash"
   TERRA_IMAGER_FIXUP_DIR=$bootdir "$fixup"
   prepare_root "$root"
   install -m 0755 "$bootdir/firstrun.sh" "$root/tmp/firstrun.sh"
   # The rewritten cleanup edits /boot/firmware/cmdline.txt. Give it a file.
   cp "$bootdir/cmdline.txt" "$root/boot/firmware/cmdline.txt"
   if [[ $name == imager-1.8 ]]; then
      run_in "$root" /bin/bash /tmp/firstrun.sh
   else
      run_in "$root" /bin/sh /tmp/firstrun.sh
   fi
   sudo chown -R "$(id -u):$(id -g)" "$root/etc" "$root/home" "$root/tmp"
   sudo chmod 0644 "$root/etc/shadow" "$root/etc/passwd"
   assert_password_applied "$root" "$hash" "$name"
   # Second boot: bridge Wi-Fi and keep the Imager hostname.
   run_in "$root" /usr/local/sbin/terra-firstboot
   sudo chown -R "$(id -u):$(id -g)" "$root/etc/wpa_supplicant" "$root/etc/hostname" \
      "$root/etc/systemd" "$root/etc/modprobe.d" 2>/dev/null || true
   grep -q 'ssid="lab"' "$root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" || fail "$name did not bridge Wi-Fi"
   [[ $(tr -d '[:space:]' < "$root/etc/hostname") == terra-lab ]] || fail "$name first boot replaced the Imager hostname"
   echo "ok: $name second boot kept the hostname and enabled wpa_supplicant@wlan0"
}

run_host_case imager-1.8 write_18 "$hash6"
if [[ -n $hashy ]]; then
   run_host_case imager-2.x write_18 "$hashy"
else
   echo "skip: host libc has no yescrypt; sha512crypt still covers chpasswd -e"
fi

# Public-key firstrun (Imager 2.x heredoc) must install the key and may turn
# password authentication off. The drop-in must not say PasswordAuthentication
# no, or that line would win over the append and also block a password-only run.
keyroot=$tmp/keys
prepare_root "$keyroot"
cat > "$keyroot/tmp/firstrun.sh" << 'EOF'
#!/bin/sh
set +e
FIRSTUSER=$(getent passwd 1000 | cut -d: -f1)
FIRSTUSERHOME=$(getent passwd 1000 | cut -d: -f6)
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom enable_ssh -k 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKimagekey laptop'
else
   install -o "$FIRSTUSER" -m 700 -d "$FIRSTUSERHOME/.ssh"
   cat > "$FIRSTUSERHOME/.ssh/authorized_keys" << 'KEYS'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKimagekey laptop
KEYS
   chown "$FIRSTUSER:$FIRSTUSER" "$FIRSTUSERHOME/.ssh/authorized_keys"
   chmod 600 "$FIRSTUSERHOME/.ssh/authorized_keys"
   echo 'PasswordAuthentication no' >>/etc/ssh/sshd_config
   systemctl enable ssh
fi
exit 0
EOF
chmod 0755 "$keyroot/tmp/firstrun.sh"
run_in "$keyroot" /bin/sh /tmp/firstrun.sh
sudo chown -R "$(id -u):$(id -g)" "$keyroot/home" "$keyroot/etc/ssh"
grep -qx 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKimagekey laptop' "$keyroot/home/pi/.ssh/authorized_keys" \
   || fail "Imager 2.x key was not installed"
grep -qx 'PasswordAuthentication no' "$keyroot/etc/ssh/sshd_config" || fail "key firstrun did not disable password authentication"
grep -qx 'PasswordAuthentication no' "$keyroot/etc/ssh/sshd_config.d/99-terra-access.conf" \
   && fail "drop-in overrides Imager's PasswordAuthentication line"
echo "ok: Imager 2.x public-key firstrun installs the key"

if [[ -n $image ]]; then
   [[ -f $image ]] || fail "image not found: $image"
   work=$tmp/img
   mkdir -p "$work"
   # A separate copy so the published bytes stay as check-image left them
   # when the caller hashed the original first. This test is allowed to
   # modify the copy only.
   cp -a "$image" "$work/image.img"
   loop=$(sudo losetup --find --show --partscan "$work/image.img")
   cleanup_img() {
      sudo umount "$work/root/dev" 2>/dev/null || true
      sudo umount "$work/root/proc" 2>/dev/null || true
      sudo umount "$work/root" 2>/dev/null || true
      sudo partx --delete "$loop" 2>/dev/null || true
      sudo losetup -d "$loop" 2>/dev/null || true
   }
   trap 'cleanup_img; rm -rf "$tmp"' EXIT
   for _ in 1 2 3 4 5 6 7 8 9 10; do
      [[ -b ${loop}p2 ]] && break
      sudo partx --add "$loop" 2>/dev/null || true
      sleep 0.2
   done
   mkdir -p "$work/root"
   sudo mount "${loop}p2" "$work/root"
   if [[ $(uname -m) != aarch64 && -x /usr/bin/qemu-aarch64-static ]]; then
      sudo cp /usr/bin/qemu-aarch64-static "$work/root/usr/bin/qemu-aarch64-static"
   fi
   sudo test ! -e "$work/root/usr/lib/raspberrypi-sys-mods/imager_custom"
   sudo test ! -e "$work/root/usr/lib/userconf-pi/userconf"
   imghash=${hashy:-$hash6}
   write_18 "$work/firstrun.sh" "$imghash"
   sudo install -m 0755 "$work/firstrun.sh" "$work/root/tmp/firstrun.sh"
   sudo mkdir -p "$work/root/boot/firmware"
   printf '%s\n' 'console=serial0,115200 rootwait systemd.run=/boot/firmware/firstrun.sh' | sudo tee "$work/root/boot/firmware/cmdline.txt" >/dev/null
   # Stubs ahead of the real reboot and systemctl so this chroot cannot reboot the host.
   sudo tee "$work/root/usr/local/sbin/reboot" >/dev/null << 'EOF'
#!/bin/sh
exit 0
EOF
   sudo tee "$work/root/usr/local/sbin/systemctl" >/dev/null << 'EOF'
#!/bin/sh
exit 0
EOF
   sudo chmod 0755 "$work/root/usr/local/sbin/reboot" "$work/root/usr/local/sbin/systemctl"
   sudo mount --bind /dev "$work/root/dev"
   sudo chroot "$work/root" /bin/bash /tmp/firstrun.sh
   got=$(sudo awk -F: '$1=="rover" { print $2 }' "$work/root/etc/shadow")
   [[ $got == "$imghash" ]] || fail "image chroot did not store the Imager password hash"
   [[ $(sudo awk -F: '$3==1000 { print $1 }' "$work/root/etc/passwd") == rover ]] || fail "image uid 1000 was not renamed"
   sudo grep -qx 'rover ALL=(ALL) NOPASSWD: ALL' "$work/root/etc/sudoers.d/010_pi-nopasswd" || fail "image sudoers was not renamed"
   [[ $(sudo tr -d '[:space:]' < "$work/root/etc/hostname") == terra-lab ]] || fail "image hostname"
   sudo grep -q 'ssid="lab"' "$work/root/etc/wpa_supplicant/wpa_supplicant.conf"
   [[ $(sudo tr -d '[:space:]' < "$work/root/etc/timezone") == America/New_York ]]
   sudo grep -q 'XKBLAYOUT="us"' "$work/root/etc/default/keyboard"
   echo "ok: image first boot applied Imager username, password, Wi-Fi, hostname, and locale"
   cleanup_img
   trap 'rm -rf "$tmp"' EXIT
fi

echo "imager firstrun checks passed"
