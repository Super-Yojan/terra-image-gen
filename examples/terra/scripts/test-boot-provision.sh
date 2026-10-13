#!/bin/bash
# Run terra-boot-provision against a fake root and a fake FAT tree.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/../../.." && pwd)
provision=$repo/examples/terra/layer/terra.d/customize.overlay/usr/local/sbin/terra-boot-provision
template=$repo/templates/rpi/boot-firmware/config.txt
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

root=$tmp/root
boot=$tmp/boot
mkdir -p "$root/etc/terra-image" "$root/etc/ssh/sshd_config.d" \
   "$root/etc/systemd/system/multi-user.target.wants" \
   "$root/lib/systemd/system" "$root/home/pi" "$boot/terra" "$boot/overlays"
cp "$repo/examples/terra/layer/terra.d/customize.overlay/etc/terra-image/fusion-hat.config" \
   "$root/etc/terra-image/fusion-hat.config"
cp "$template" "$boot/config.txt"
printf '%s\n' 'pi:x:1000:1000::/home/pi:/bin/bash' > "$root/etc/passwd"
printf '%s\n' 'pi:!:19000:0:99999:7:::' > "$root/etc/shadow"
chmod 0640 "$root/etc/shadow"
printf '%s\n' '# /etc/modules: kernel modules to load at boot time.' > "$root/etc/modules"
: > "$root/lib/systemd/system/ssh.service"
: > "$root/lib/systemd/system/wpa_supplicant@.service"

TERRA_ROOT=$root TERRA_BOOT=$boot "$provision"

cfg=$(cat "$boot/config.txt")
for line in \
   'dtparam=i2c_arm=on' \
   'dtparam=i2s=on' \
   'dtparam=spi=on' \
   'dtparam=audio=off' \
   'dtoverlay=sunfounder-fusionhat'
do
   grep -qx "$line" <<< "$cfg" || { echo "missing $line" >&2; exit 1; }
done
grep -qx 'dtparam=audio=on' <<< "$cfg" && { echo "audio=on still active" >&2; exit 1; }
[[ $(grep -cx 'dtoverlay=sunfounder-fusionhat' <<< "$cfg") -eq 1 ]] || {
   echo "dtoverlay count" >&2
   exit 1
}
grep -qx '#dtparam=i2c_arm=on' <<< "$cfg" && { echo "i2c still commented" >&2; exit 1; }
grep -qx 'i2c-dev' "$root/etc/modules"
awk -F: '$1=="pi" && $2=="*" { found=1 } END { exit !found }' "$root/etc/shadow"
[[ -L $root/etc/systemd/system/multi-user.target.wants/ssh.service ]]

# Second run must not duplicate the overlay or demand another repair.
before=$(grep -c . "$boot/config.txt")
TERRA_ROOT=$root TERRA_BOOT=$boot "$provision"
[[ $(grep -cx 'dtoverlay=sunfounder-fusionhat' "$boot/config.txt") -eq 1 ]]
[[ $(grep -c . "$boot/config.txt") -eq $before ]]
[[ ! -e $root/var/lib/terra-image/fusion-config-changed ]]

# Headless files: key, Wi-Fi, and a password hash from custom.toml.
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtestkey laptop' > "$boot/authorized_keys"
cat > "$boot/custom.toml" << 'EOF'
config_version = "1.0"

[ssh]
enabled = true
password_authentication = true
authorized_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtomlkey imager",
]

[user]
name = "pi"
password = "$6$rounds$salty$hash"
password_encrypted = true

[wlan]
ssid = "lab-net"
password = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
password_encrypted = true
hidden = false
country = "us"
EOF

TERRA_ROOT=$root TERRA_BOOT=$boot "$provision"

[[ ! -e $boot/authorized_keys ]]
[[ ! -e $boot/custom.toml ]]
grep -qx 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtestkey laptop' "$root/home/pi/.ssh/authorized_keys"
grep -qx 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtomlkey imager' "$root/home/pi/.ssh/authorized_keys"
[[ $(grep -c 'AAAAC3NzaC1lZDI1NTE5AAAAIKtestkey' "$root/home/pi/.ssh/authorized_keys") -eq 1 ]]
[[ $(stat -c '%a' "$root/home/pi/.ssh/authorized_keys") == 600 ]]
grep -q 'ssid="lab-net"' "$root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
grep -q 'psk=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' \
   "$root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
grep -qx 'country=US' "$root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
[[ $(stat -c '%a' "$root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf") == 600 ]]
awk -F: '$1=="pi" && $2=="$6$rounds$salty$hash" { found=1 } END { exit !found }' "$root/etc/shadow"
grep -qx 'PasswordAuthentication yes' "$root/etc/ssh/sshd_config.d/99-terra-access.conf"
grep -q 'ieee80211_regdom=US' "$root/etc/modprobe.d/cfg80211_regdomain.conf"

# A second pass must not duplicate keys, and a wpa_supplicant.conf drop works.
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtestkey laptop' > "$boot/authorized_keys"
cat > "$boot/wpa_supplicant.conf" << 'EOF'
country=GB
network={
	ssid="other"
	psk="secret"
	key_mgmt=WPA-PSK
}
EOF
# Restore key-only shadow so this pass does not require a toml password.
printf '%s\n' 'pi:*:19000:0:99999:7:::' > "$root/etc/shadow"
chmod 0640 "$root/etc/shadow"
TERRA_ROOT=$root TERRA_BOOT=$boot "$provision"
[[ $(grep -c 'AAAAC3NzaC1lZDI1NTE5AAAAIKtestkey' "$root/home/pi/.ssh/authorized_keys") -eq 1 ]]
grep -q 'ssid="other"' "$root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
[[ ! -e $boot/wpa_supplicant.conf ]]
awk -F: '$1=="pi" && $2=="*" { found=1 } END { exit !found }' "$root/etc/shadow"

echo "boot provision checks passed"
