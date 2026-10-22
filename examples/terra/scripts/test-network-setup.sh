#!/bin/bash
# Exercise generated network configuration without changing the host network.
set -euo pipefail
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/../../.." && pwd)
setup=$repo/examples/terra/layer/terra.d/customize.overlay/usr/local/sbin/terra-network-setup
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
root=$tmp/root
boot=$tmp/boot
mkdir -p "$root/etc/terra-image" "$root/proc/device-tree" "$boot"
printf '00000000aabbccdd' > "$root/proc/device-tree/serial-number"
cat > "$boot/terra-network.conf" <<'EOF'
WIFI_MODE=hotspot
HOTSPOT_COUNTRY=US
HOTSPOT_PASSPHRASE=test-only-password
EOF
TERRA_ROOT=$root TERRA_BOOT=$boot bash "$setup" --configure-only
[[ ! -f $boot/terra-network.conf ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
grep -qx 'HOTSPOT_SSID=Terra-bbccdd' "$root/etc/terra-image/network.conf"
grep -qx 'ssid=Terra-bbccdd' "$root/etc/hostapd/hostapd.conf"
grep -qx 'wpa=2' "$root/etc/hostapd/hostapd.conf"
grep -qx 'wpa_passphrase=test-only-password' "$root/etc/hostapd/hostapd.conf"
grep -qx 'Address=192.168.77.1/30' "$root/etc/systemd/network/00-terra-usb.network"
grep -qx 'Address=192.168.78.1/24' "$root/etc/systemd/network/00-terra-hotspot.network"
grep -qx 'EmitRouter=no' "$root/etc/systemd/network/00-terra-hotspot.network"
[[ -f $root/var/lib/terra-image/hotspot-mode ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
if [[ $(uname -s) == Darwin ]]; then mode=$(stat -f '%Lp' "$root/etc/hostapd/hostapd.conf"); else mode=$(stat -c '%a' "$root/etc/hostapd/hostapd.conf"); fi
[[ $mode == 600 ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
if [[ $(uname -s) == Darwin ]]; then mode=$(stat -f '%Lp' "$root/etc/systemd/network/00-terra-usb.network"); else mode=$(stat -c '%a' "$root/etc/systemd/network/00-terra-usb.network"); fi
[[ $mode == 644 ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
cp "$root/etc/terra-image/network.conf" "$tmp/first.conf"
TERRA_ROOT=$root TERRA_BOOT=$boot bash "$setup" --configure-only
cmp "$tmp/first.conf" "$root/etc/terra-image/network.conf"
# Client mode retains the USB rescue network and does not remove saved Wi-Fi.
printf 'saved-network\n' > "$root/etc/wpa-saved.fixture"
sed 's/WIFI_MODE=hotspot/WIFI_MODE=client/' "$tmp/first.conf" > "$root/etc/terra-image/network.conf"
TERRA_ROOT=$root TERRA_BOOT=$boot bash "$setup" --configure-only
[[ ! -f $root/var/lib/terra-image/hotspot-mode && ! -f $root/etc/systemd/network/00-terra-hotspot.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
[[ -f $root/etc/systemd/network/00-terra-usb.network && -f $root/etc/wpa-saved.fixture ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
# Never execute config values or silently start an open AP after bad provisioning.
printf 'WIFI_MODE=hotspot\nHOTSPOT_PASSPHRASE=short\n' > "$boot/terra-network.conf"
if TERRA_ROOT=$root TERRA_BOOT=$boot bash "$setup" --configure-only > "$tmp/rejected.log" 2>&1; then
 echo 'accepted an insecure hotspot passphrase' >&2; exit 1
fi
[[ -f $boot/terra-network.conf ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
cat > "$boot/terra-network.conf" <<'EOF'
WIFI_MODE=hotspot
HOTSPOT_PASSPHRASE=$(touch SHOULD_NOT_EXIST)
EOF
TERRA_ROOT=$root TERRA_BOOT=$boot bash "$setup" --configure-only
[[ ! -e SHOULD_NOT_EXIST && ! -e $root/SHOULD_NOT_EXIST ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
grep -qF '$(touch SHOULD_NOT_EXIST)' "$root/etc/hostapd/hostapd.conf"
# Invalid Wi-Fi provisioning must not disable independent USB recovery.
broken=$tmp/broken
mkdir -p "$broken/boot/firmware"
printf 'WIFI_MODE=hotspot\nHOTSPOT_PASSPHRASE=bad\n' > "$broken/boot/firmware/terra-network.conf"
if TERRA_ROOT=$broken bash "$setup" --configure-only > "$tmp/broken.log" 2>&1; then exit 1; fi
[[ -f $broken/etc/systemd/network/00-terra-usb.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
[[ ! -f $broken/etc/hostapd/hostapd.conf ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
# Fresh cards get unique credentials that survive repeat boots.
other=$tmp/other
mkdir -p "$other/etc/terra-image" "$other/proc/device-tree" "$tmp/otherboot"
printf '0000000012345678' > "$other/proc/device-tree/serial-number"
TERRA_ROOT=$other TERRA_BOOT=$tmp/otherboot bash "$setup" --configure-only
cp "$other/etc/terra-image/network.conf" "$tmp/generated.conf"
TERRA_ROOT=$other TERRA_BOOT=$tmp/otherboot bash "$setup" --configure-only
cmp "$tmp/generated.conf" "$other/etc/terra-image/network.conf"
grep -Eq '^HOTSPOT_PASSPHRASE=[0-9a-f]{24}$' "$tmp/generated.conf"
echo 'ok: protected hotspot, USB rescue, client mode, stable credentials and safe parsing'
