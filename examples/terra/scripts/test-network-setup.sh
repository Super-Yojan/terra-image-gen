#!/bin/bash
# Exercise generated network configuration without changing the host network.
set -euo pipefail
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/../../.." && pwd)
setup=$repo/examples/terra/layer/terra.d/customize.overlay/usr/local/sbin/terra-network-setup
overlay=$repo/examples/terra/layer/terra.d/customize.overlay
hook=$repo/examples/terra/layer/terra.d/hooks/customize45-network
grep -qx 'WIFI_MODE=fallback' "$overlay/etc/terra-image/network.conf"
grep -qx 'WIFI_CONNECT_TIMEOUT=30' "$overlay/etc/terra-image/network.conf"
grep -qx 'WIFI_RETRY_TIMEOUT=15' "$overlay/etc/terra-image/network.conf"
[[ -x $overlay/usr/local/sbin/terra-wifi-fallback && -x $overlay/usr/local/sbin/terra-wifi-retry ]] || { echo 'wifi commands are not executable' >&2; exit 1; }
bash -n "$setup"
bash -n "$overlay/usr/local/sbin/terra-wifi-fallback"
bash -n "$overlay/usr/local/sbin/terra-wifi-retry"
bash -n "$hook"
grep -q 'wants/terra-wifi-fallback.service' "$hook"
if grep -q 'wants/terra-wifi-retry.service' "$hook"; then
 echo 'retry service must not be enabled at boot' >&2
 exit 1
fi
grep -q 'WantedBy=multi-user.target' "$overlay/etc/systemd/system/terra-wifi-fallback.service"
grep -q 'Restart=no' "$overlay/etc/systemd/system/terra-wifi-fallback.service"
grep -q 'ConditionPathExists=/var/lib/terra-image/wifi-fallback' "$overlay/etc/systemd/system/terra-wifi-fallback.service"
grep -q 'ConditionPathExists=!/var/lib/terra-image/hotspot-mode' "$overlay/etc/systemd/system/terra-wifi-fallback.service"
if grep -q '^WantedBy=' "$overlay/etc/systemd/system/terra-wifi-retry.service"; then
 echo 'retry service has an install target' >&2
 exit 1
fi
dupes=$(grep -R -n -E 'WIFI_CONNECT_TIMEOUT|WIFI_RETRY_TIMEOUT' "$overlay/etc/systemd" "$hook" || true)
[[ -z $dupes ]] || { echo "timeout configured outside network.conf: $dupes" >&2; exit 1; }
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
[[ ! -f $root/var/lib/terra-image/wifi-fallback ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
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
[[ ! -f $root/etc/hostapd/hostapd.conf && ! -f $root/var/lib/terra-image/wifi-fallback ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
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
# An image built with a shared default password uses it for the hotspot.
shared=$tmp/shared
mkdir -p "$shared/etc/terra-image" "$shared/proc/device-tree" "$tmp/sharedboot"
printf '0000000012345678' > "$shared/proc/device-tree/serial-number"
printf 'raspberrypi\n' > "$shared/etc/terra-image/default-password"
TERRA_ROOT=$shared TERRA_BOOT=$tmp/sharedboot bash "$setup" --configure-only
grep -qx 'HOTSPOT_PASSPHRASE=raspberrypi' "$shared/etc/terra-image/network.conf"
grep -qx 'wpa_passphrase=raspberrypi' "$shared/etc/hostapd/hostapd.conf"
# terra-network.conf on the boot partition still wins over the shared default.
shared2=$tmp/shared2
mkdir -p "$shared2/etc/terra-image" "$shared2/proc/device-tree" "$tmp/shared2boot"
printf '0000000012345678' > "$shared2/proc/device-tree/serial-number"
printf 'raspberrypi\n' > "$shared2/etc/terra-image/default-password"
printf 'HOTSPOT_PASSPHRASE=my-own-passphrase\n' > "$tmp/shared2boot/terra-network.conf"
TERRA_ROOT=$shared2 TERRA_BOOT=$tmp/shared2boot bash "$setup" --configure-only
grep -qx 'HOTSPOT_PASSPHRASE=my-own-passphrase' "$shared2/etc/terra-image/network.conf"
grep -qx 'WIFI_MODE=fallback' "$tmp/generated.conf"
grep -qx 'WIFI_CONNECT_TIMEOUT=30' "$tmp/generated.conf"
grep -qx 'WIFI_RETRY_TIMEOUT=15' "$tmp/generated.conf"
[[ -f $other/etc/hostapd/hostapd.conf && -f $other/var/lib/terra-image/wifi-fallback ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
[[ ! -f $other/var/lib/terra-image/hotspot-mode && ! -f $other/etc/systemd/network/00-terra-hotspot.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
[[ -f $other/etc/systemd/network/00-terra-usb.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }

# Fallback provisioning keeps the client network file off the radio until activation.
fb=$tmp/fb
mkdir -p "$fb/etc/terra-image" "$fb/proc/device-tree" "$fb/etc/wpa_supplicant" "$tmp/fbboot"
printf '00000000aabbccdd' > "$fb/proc/device-tree/serial-number"
printf 'network={ssid="saved"}\n' > "$fb/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
cat > "$tmp/fbboot/terra-network.conf" <<'EOF'
WIFI_MODE=fallback
HOTSPOT_COUNTRY=US
WIFI_CONNECT_TIMEOUT=45
WIFI_RETRY_TIMEOUT=12
HOTSPOT_PASSPHRASE=test-only-password
EOF
TERRA_ROOT=$fb TERRA_BOOT=$tmp/fbboot bash "$setup" --configure-only
[[ ! -f $tmp/fbboot/terra-network.conf ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
grep -qx 'WIFI_MODE=fallback' "$fb/etc/terra-image/network.conf"
grep -qx 'WIFI_CONNECT_TIMEOUT=45' "$fb/etc/terra-image/network.conf"
grep -qx 'WIFI_RETRY_TIMEOUT=12' "$fb/etc/terra-image/network.conf"
grep -qx 'ssid=Terra-bbccdd' "$fb/etc/hostapd/hostapd.conf"
[[ -f $fb/var/lib/terra-image/wifi-fallback && -f $fb/etc/systemd/network/00-terra-usb.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
[[ ! -f $fb/var/lib/terra-image/hotspot-mode && ! -f $fb/etc/systemd/network/00-terra-hotspot.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
cp "$fb/etc/systemd/network/00-terra-usb.network" "$tmp/fb.usb"

set_timeouts() {
 awk -v c="$2" -v r="$3" '
  /^WIFI_CONNECT_TIMEOUT=/ { print "WIFI_CONNECT_TIMEOUT=" c; next }
  /^WIFI_RETRY_TIMEOUT=/ { print "WIFI_RETRY_TIMEOUT=" r; next }
  { print }
 ' "$1" > "$1.next"
 cat "$1.next" > "$1"
 rm -f "$1.next"
}
run_watch() {
 local log=$1 state=$2
 shift 2
 : > "$log"
 timeout 10 env TERRA_ROOT="$fb" TERRA_SLEEP_CMD=/bin/true TERRA_WIFI_STATE_CMD="$state" \
  TERRA_COMMAND_LOG="$log" "$@" bash "$setup" --watch
}
count_cmd() {
 grep -c -F "$1" "$2" || true
}
assert_before() {
 local first=$1 second=$2 file=$3 a b
 a=$(grep -n -F "$first" "$file" | head -n 1 | cut -d: -f1 || true)
 b=$(grep -n -F "$second" "$file" | head -n 1 | cut -d: -f1 || true)
 [[ -n $a && -n $b && $a -lt $b ]] || { echo "expected '$first' before '$second'" >&2; exit 1; }
}

# No association within the connect window starts the hotspot once, then the watcher exits.
set_timeouts "$fb/etc/terra-image/network.conf" 2 4
cp "$fb/etc/terra-image/network.conf" "$tmp/fb.conf"
printf '#!/bin/bash\necho down\n' > "$tmp/down"
chmod +x "$tmp/down"
run_watch "$tmp/down.log" "$tmp/down"
[[ $(count_cmd 'systemctl start hostapd.service' "$tmp/down.log") == 1 ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
assert_before 'systemctl stop wpa_supplicant@wlan0.service' 'systemctl start hostapd.service' "$tmp/down.log"
assert_before 'systemctl start --no-block wpa_supplicant@wlan0.service' 'systemctl stop wpa_supplicant@wlan0.service' "$tmp/down.log"
[[ -f $fb/var/lib/terra-image/hotspot-mode && -f $fb/etc/systemd/network/00-terra-hotspot.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
cmp "$tmp/fb.conf" "$fb/etc/terra-image/network.conf"
cmp "$tmp/fb.usb" "$fb/etc/systemd/network/00-terra-usb.network"
# A second start must not retune the radio while the hotspot marker is present.
: > "$tmp/again.log"
timeout 10 env TERRA_ROOT="$fb" TERRA_SLEEP_CMD=/bin/true TERRA_WIFI_STATE_CMD="$tmp/down" \
 TERRA_COMMAND_LOG="$tmp/again.log" bash "$setup" --watch
[[ $(count_cmd 'systemctl' "$tmp/again.log") == 0 ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }

# Explicit retry returns the radio to the client and arms the watcher again.
: > "$tmp/retry.log"
timeout 10 env TERRA_ROOT="$fb" TERRA_COMMAND_LOG="$tmp/retry.log" bash "$setup" --retry-wifi
[[ ! -f $fb/var/lib/terra-image/hotspot-mode && ! -f $fb/etc/systemd/network/00-terra-hotspot.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
[[ -f $fb/var/lib/terra-image/wifi-fallback && -f $fb/etc/hostapd/hostapd.conf ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
cmp "$tmp/fb.usb" "$fb/etc/systemd/network/00-terra-usb.network"
assert_before 'systemctl stop hostapd.service' 'networkctl reconfigure wlan0' "$tmp/retry.log"
assert_before 'networkctl reconfigure wlan0' 'systemctl start --no-block wpa_supplicant@wlan0.service' "$tmp/retry.log"
assert_before 'systemctl start --no-block wpa_supplicant@wlan0.service' 'systemctl restart terra-wifi-fallback.service' "$tmp/retry.log"
# Retry while the client is already active does not bounce the radio.
: > "$tmp/retry-again.log"
timeout 10 env TERRA_ROOT="$fb" TERRA_COMMAND_LOG="$tmp/retry-again.log" bash "$setup" --retry-wifi
[[ $(count_cmd 'systemctl' "$tmp/retry-again.log") == 0 ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }

# A connection that stays up never starts the hotspot.
set_timeouts "$fb/etc/terra-image/network.conf" 4 4
printf '#!/bin/bash\necho up\n' > "$tmp/up"
chmod +x "$tmp/up"
run_watch "$tmp/up.log" "$tmp/up" TERRA_MAX_TICKS=3
[[ $(count_cmd 'systemctl start hostapd.service' "$tmp/up.log") == 0 ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
[[ ! -f $fb/var/lib/terra-image/hotspot-mode && ! -f $fb/etc/systemd/network/00-terra-hotspot.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }

# A drop that outlasts the retry window starts the hotspot once.
set_timeouts "$fb/etc/terra-image/network.conf" 4 3
printf '0\n' > "$tmp/drop.count"
cat > "$tmp/drop" <<EOF
#!/bin/bash
n=\$(cat '$tmp/drop.count')
printf '%s\n' \$((n + 1)) > '$tmp/drop.count'
if [[ \$n -eq 0 ]]; then echo up; else echo down; fi
EOF
chmod +x "$tmp/drop"
run_watch "$tmp/drop.log" "$tmp/drop"
[[ $(count_cmd 'systemctl start hostapd.service' "$tmp/drop.log") == 1 ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
[[ -f $fb/var/lib/terra-image/hotspot-mode ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }

# A drop that recovers inside the window leaves the client radio alone.
TERRA_ROOT=$fb bash "$setup" --retry-wifi >/dev/null
set_timeouts "$fb/etc/terra-image/network.conf" 4 5
printf '0\n' > "$tmp/flap.count"
cat > "$tmp/flap" <<EOF
#!/bin/bash
n=\$(cat '$tmp/flap.count')
printf '%s\n' \$((n + 1)) > '$tmp/flap.count'
if [[ \$n -eq 0 ]]; then echo up
elif [[ \$n -le 2 ]]; then echo down
else echo up
fi
EOF
chmod +x "$tmp/flap"
run_watch "$tmp/flap.log" "$tmp/flap" TERRA_MAX_TICKS=6
[[ $(count_cmd 'systemctl start hostapd.service' "$tmp/flap.log") == 0 ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
[[ ! -f $fb/var/lib/terra-image/hotspot-mode ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }

# Missing hotspot configuration must not report success after the wait.
rm -f "$fb/etc/hostapd/hostapd.conf"
set_timeouts "$fb/etc/terra-image/network.conf" 1 4
if run_watch "$tmp/missing.log" "$tmp/down"; then
 echo 'watch succeeded without hostapd.conf' >&2
 exit 1
fi
[[ ! -f $fb/var/lib/terra-image/hotspot-mode ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }

# Empty timeout keys keep the defaults. A zero or junk value is rejected and the boot file stays.
empty=$tmp/empty
mkdir -p "$empty/etc/terra-image" "$empty/proc/device-tree" "$tmp/emptyboot"
printf '00000000aabbccdd' > "$empty/proc/device-tree/serial-number"
cat > "$tmp/emptyboot/terra-network.conf" <<'EOF'
WIFI_MODE=fallback
WIFI_CONNECT_TIMEOUT=
WIFI_RETRY_TIMEOUT=
HOTSPOT_PASSPHRASE=test-only-password
EOF
TERRA_ROOT=$empty TERRA_BOOT=$tmp/emptyboot bash "$setup" --configure-only
grep -qx 'WIFI_CONNECT_TIMEOUT=30' "$empty/etc/terra-image/network.conf"
grep -qx 'WIFI_RETRY_TIMEOUT=15' "$empty/etc/terra-image/network.conf"
printf 'WIFI_MODE=fallback\nWIFI_CONNECT_TIMEOUT=0\nHOTSPOT_PASSPHRASE=test-only-password\n' > "$boot/terra-network.conf"
if TERRA_ROOT=$root TERRA_BOOT=$boot bash "$setup" --configure-only > "$tmp/zero.log" 2>&1; then
 echo 'accepted a zero connect timeout' >&2
 exit 1
fi
[[ -f $boot/terra-network.conf && -f $root/etc/systemd/network/00-terra-usb.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
printf 'WIFI_MODE=fallback\nWIFI_RETRY_TIMEOUT=3601\nHOTSPOT_PASSPHRASE=test-only-password\n' > "$boot/terra-network.conf"
if TERRA_ROOT=$root TERRA_BOOT=$boot bash "$setup" --configure-only > "$tmp/huge.log" 2>&1; then
 echo 'accepted a timeout above 3600' >&2
 exit 1
fi
[[ -f $boot/terra-network.conf ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
printf 'WIFI_MODE=fallback\nWIFI_CONNECT_TIMEOUT=soon\nHOTSPOT_PASSPHRASE=test-only-password\n' > "$boot/terra-network.conf"
if TERRA_ROOT=$root TERRA_BOOT=$boot bash "$setup" --configure-only > "$tmp/nan.log" 2>&1; then
 echo 'accepted a non-numeric timeout' >&2
 exit 1
fi

# Pinned hotspot mode refuses the client retry and keeps the access point files.
printf 'WIFI_MODE=hotspot\nHOTSPOT_PASSPHRASE=test-only-password\n' > "$boot/terra-network.conf"
TERRA_ROOT=$root TERRA_BOOT=$boot bash "$setup" --configure-only
if TERRA_ROOT=$root bash "$setup" --retry-wifi > "$tmp/pinned.log" 2>&1; then
 echo 'retry ran while WIFI_MODE=hotspot' >&2
 exit 1
fi
[[ -f $root/var/lib/terra-image/hotspot-mode && -f $root/etc/systemd/network/00-terra-hotspot.network ]] || { echo "network fixture assertion failed at line $LINENO" >&2; exit 1; }
grep -q 'WIFI_MODE=fallback' "$tmp/pinned.log"
echo 'ok: protected hotspot, USB rescue, client mode, fallback timing, retry command, and safe parsing'
