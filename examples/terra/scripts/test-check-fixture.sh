#!/bin/bash
# Exercise check-image.sh against a synthetic rootfs. Does not replace the
# real image check (--skip-exec is only valid here).
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
check=$here/check-image.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

good=$tmp/good
mkdir -p \
   "$good/etc/ssh" "$good/etc/systemd/system/multi-user.target.wants" \
   "$good/etc/systemd/system/sysinit.target.wants" \
   "$good/etc/terra-rover" "$good/var/lib/terra-rover" \
   "$good/usr/local/bin" "$good/usr/src/fusion_hat-1.1.0" \
   "$good/var/lib/dkms/fusion_hat/1.1.0" \
   "$good/lib/modules/6.6.0-rpi-v8/extra" \
   "$good/lib/modules/6.12.0-rpi-2712/updates/dkms" \
   "$good/boot/firmware/overlays" \
   "$good/home/pi"

printf '%s\n' terra > "$good/etc/hostname"
: > "$good/etc/machine-id"
printf '%s\n' 'TERRA_PWM_PORTS=' > "$good/etc/terra-rover/rover.env"
cat > "$good/etc/systemd/system/terra-rover.service" << 'EOF'
[Service]
ExecStart=/usr/local/bin/terra-rover --button-pairing --pwm-ports ${TERRA_PWM_PORTS}
EOF
printf '%s\n' '[Service]' 'ExecStart=/usr/local/sbin/terra-firstboot' > "$good/etc/systemd/system/terra-firstboot.service"
ln -s ../terra-rover.service "$good/etc/systemd/system/multi-user.target.wants/terra-rover.service"
ln -s ../terra-firstboot.service "$good/etc/systemd/system/sysinit.target.wants/terra-firstboot.service"
printf '%s\n' 'terra-rover:x:990:990::/var/lib/terra-rover:/usr/sbin/nologin' > "$good/etc/passwd"
printf '%s\n' 'terra-rover:x:990:' 'i2c:x:991:terra-rover' 'bluetooth:x:992:terra-rover' > "$good/etc/group"
printf '%s\n' 'root:*:1:0:99999:7:::' 'terra-rover:!:1:0:99999:7:::' 'pi:!:1:0:99999:7:::' > "$good/etc/shadow"
: > "$good/home/pi/.placeholder"
install -d -m 0700 "$good/var/lib/terra-rover"
# Ownership is whatever the fixture user is; rewrite passwd to match.
uid=$(id -u)
gid=$(id -g)
sed -i "s/990:990/$uid:$gid/" "$good/etc/passwd"
sed -i "s/:990:/:$gid:/" "$good/etc/group"
chown "$uid:$gid" "$good/var/lib/terra-rover"
chmod 0700 "$good/var/lib/terra-rover"
# Minimal AArch64 ELF header (not executable). --skip-exec only checks the header.
printf '\177ELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00' > "$good/usr/local/bin/terra-rover"
: > "$good/lib/modules/6.6.0-rpi-v8/extra/fusion_hat.ko"
: > "$good/lib/modules/6.12.0-rpi-2712/updates/dkms/fusion_hat.ko.xz"
: > "$good/boot/firmware/overlays/sunfounder-fusionhat.dtbo"
printf '%s\n' 'dtparam=i2c_arm=on' 'dtoverlay=sunfounder-fusionhat' > "$good/boot/firmware/config.txt"
cat > "$good/etc/terra-image-release" << 'EOF'
TERRA_FUSION_COMMIT=4bd1018ad5a70ee113160536f969cdadd9f22918
TERRA_FUSION_SHA256=37ea53b9b72b6431a4a2ee8b752804ad74f0f10071c416f856991814347d9c2d
TERRA_ROVER_SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
TERRA_DEVICES=pi4,pi5
EOF

"$check" --root "$good" --skip-exec

bad=$tmp/bad
cp -a "$good" "$bad"
printf '%s\n' 0123456789abcdef0123456789abcdef > "$bad/etc/machine-id"
if "$check" --root "$bad" --skip-exec; then
   echo "fixture: machine-id check did not fail" >&2
   exit 1
fi

bad2=$tmp/bad2
cp -a "$good" "$bad2"
printf '%s\n' '{"name":"terra-ABCDEF"}' > "$bad2/var/lib/terra-rover/device-name.json"
if "$check" --root "$bad2" --skip-exec; then
   echo "fixture: baked rover name was accepted" >&2
   exit 1
fi

bad3=$tmp/bad3
cp -a "$good" "$bad3"
mkdir -p "$bad3/etc/wpa_supplicant"
printf '%s\n' 'network={ssid="lab" psk="secret"}' > "$bad3/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
if "$check" --root "$bad3" --skip-exec; then
   echo "fixture: Wi-Fi credential was accepted" >&2
   exit 1
fi

echo "fixture checks passed"
