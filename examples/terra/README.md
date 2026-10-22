# Terra SD card image

One command builds a 64-bit Raspberry Pi OS Bookworm image with the Fusion HAT kernel driver and the `terra-rover` service already installed. Flash that image to any number of cards. Each card gets its own hostname, machine-id, and SSH host keys on first boot. The image does not contain an owner bond, a rover BLE name, Wi-Fi credentials, or developer keys.

Targets **Raspberry Pi 4 and Pi 5** (64-bit). The root filesystem uses 4K blocks so the Pi 4 v8 kernel can mount it. The image also installs `linux-image-rpi-2712`, which the Pi 5 firmware selects automatically. A 16K-block image would boot only the Pi 5.

This tree is an rpi-image-gen source directory (`-S examples/terra`) plus `config/terra.yaml`. Upstream layers are not modified.

## Build

Host packages (Debian or Ubuntu, including amd64 with qemu-user):

```sh
sudo apt-get install -y qemu-user-static binfmt-support bmap-tools xz-utils mtools
sudo ./install_deps.sh
```

`examples/terra/pins.env` pins terra-rover 0.2.0 to the GitHub Release [rover-v0.2.0](https://github.com/Super-Yojan/Terra/releases/tag/rover-v0.2.0). From this repository:

```sh
./examples/terra/scripts/build-image.sh
```

That downloads `terra-rover-0.2.0-linux-arm64.tar.gz` and refuses to continue unless its sha256 is `4c537d1123e8e74992c46d68a218d6da5575a1461f9c29e7cbd5d887c9cd6553`. A local file skips the download. It is checked against the same pin unless you also set `TERRA_ROVER_SHA256`:

```sh
TERRA_ROVER_TARBALL=/path/to/terra-rover-0.2.0-linux-arm64.tar.gz \
  ./examples/terra/scripts/build-image.sh
```

Outputs (names follow the artefact version directory):

- `work/deploy-*/terra-bookworm-arm64.img`
- `work/deploy-*/terra-bookworm-arm64.img.xz`
- `work/deploy-*/terra-bookworm-arm64.img.bmap`
- `work/deploy-*/terra-image-release` (same text as `/etc/terra-image-release` in the image)

## What the image contains

- Bookworm arm64, systemd, BlueZ, D-Bus.
- Fusion HAT driver from sunfounder/fusion-hat commit `4bd1018ad5a70ee113160536f969cdadd9f22918` (library 1.14.0, driver DKMS 1.1.0). The codeload archive hash is checked. DKMS plus `linux-headers-rpi-v8` and `linux-headers-rpi-2712` are installed so a later kernel update can rebuild the module. `/boot/firmware/config.txt` ends with the interfaces the pinned installer and the HAT docs require:

  ```
  dtparam=i2c_arm=on
  dtparam=i2s=on
  dtparam=spi=on
  dtparam=audio=off
  dtoverlay=sunfounder-fusionhat
  ```

  The installer itself only appends `dtoverlay=sunfounder-fusionhat`. `fusion_hat` enables I2C with `raspi-config nonint do_i2c 0`, which is `dtparam=i2c_arm=on` plus the `i2c-dev` module. The HAT's SPI header and I2S speaker/mic are the other two `dtparam` lines (they ship commented out in the Raspberry Pi template). `dtparam=audio=off` turns off the Pi's PWM analog audio so it does not claim the sound node the overlay replaces. HAT PWM connectors are the MCU at I2C `0x17`, not a Pi `pwm` overlay.
- The vendor audio/voice userspace stack is not installed. The kernel module still includes the vendor speaker driver, because that is part of the pinned driver and the HAT probe path.
- `terra-rover` from `install.sh --root`, user `terra-rover` in groups `i2c` and `bluetooth`, `/var/lib/terra-rover` mode 0700 owned by that user, `terra-rover.service` enabled.
- Safety defaults from Terra: button pairing, no `--gate-file`, battery cutoff left external. Pairing does not arm. `TERRA_PWM_PORTS` defaults to `P0,P1,P2,P3,P4,P5` (`terra.pwm_ports`). P4 and P5 are also motor M3's pins, so one layout cannot use M3 together with P4 or P5.

## Direct connections: USB and the Terra hotspot

New builds enable both independent access paths. On a Pi 4, connect the USB-C
data port to your Mac with a data cable; USB-A ports remain host ports. The Pi
serves one USB DHCP lease and accepts SSH at `192.168.77.1`. Gadget Ethernet
addresses are derived from the Pi identity and remain stable across boots.

At every boot the Pi creates a 2.4 GHz WPA2 hotspot named `Terra-` followed by its
serial suffix. Join it from a phone or computer, then use SSH at `192.168.78.1`.
The image retains its systemd-networkd/wpa_supplicant stack; hotspot mode prevents
the Wi-Fi client service from competing for the same radio. SSH uses the same
provisioned key/password on both links. Pi 5 does not gain a USB-C data path from
this change; its hotspot remains available.

The hotspot is a local connection and does not advertise an internet gateway or
DNS server. In hotspot mode, Pi uploads need Ethernet or the Mac USB log relay;
otherwise logs remain queued. Saved Wi-Fi client credentials are preserved.

The single operator configuration is `/etc/terra-image/network.conf` (root-only).
To provision it while flashing, put a `terra-network.conf` on the FAT boot
partition, with unquoted literal values:

```text
WIFI_MODE=hotspot
HOTSPOT_COUNTRY=US
HOTSPOT_SSID=
HOTSPOT_PASSPHRASE=choose-a-private-password
```

Set the regulatory country for your location. An empty SSID uses the Pi identity.
The boot file is validated, copied into the protected root configuration, and
removed from FAT. A missing passphrase generates a unique 24-character password
on the device; retrieve it through USB SSH from the root-only configuration.
There is no shared default password. Do not publish an image containing your
provisioning file or an initialized network configuration.

To use a saved Wi-Fi client network instead, set `WIFI_MODE=client` in that same
configuration and reboot. USB SSH remains available. To return to the hotspot,
set `WIFI_MODE=hotspot` and reboot. No rover arming or motion setting changes.

Run `examples/terra/scripts/test-network-setup.sh` for fixture tests of protected
AP generation, USB addressing, repeat boots, mode changes and safe secret parsing.

## First boot

`terra-firstboot.service` copies headless-access files off the FAT boot partition, sets the hostname to `terra-` plus the last six hex digits of the Pi serial (or a random suffix when no serial exists), and grows the root filesystem to the card. systemd generates `machine-id` because the file ships empty. SSH host keys are absent from the image; `ssh-hostkeys-generate.service` creates a new set before sshd listens. `terra-rover` generates `terra-XXXXXX` itself the first time it can write `/var/lib/terra-rover/device-name.json`. That file is not in the image.

sshd is enabled. The `pi` account has no password (`*` in `/etc/shadow`, not a lock). A public key works. Password login works after Raspberry Pi Imager, or a `custom.toml` on the boot partition, sets a password. Until then sshd has nothing to accept. `pi` can `sudo` without a password. Nothing in the image is a shared default password. If a flasher rewrote `config.txt` and dropped the Fusion HAT lines, first boot puts them back and reboots once. A hostname Imager already set is kept; the serial name is only used when the hostname is still the placeholder `terra`.

The USR button only opens `terra-rover`'s pairing window. sshd does not wait on that button, on Bluetooth, or on `terra-rover.service`. Holding the button is not required to recover the Pi over SSH.

### Log in on a new card

1. Flash `terra-bookworm-arm64.img.xz` with `flash-cards.sh`, or with Raspberry Pi Imager using the Terra OS list. The Imager steps (username, password, Wi-Fi, hostname, locale) are in [docs/flash-with-imager.md](docs/flash-with-imager.md). The steps below work after any raw write, including a card Imager customised.
2. Put the card back in the computer you flashed from. Open the small FAT partition (the one that contains `config.txt`).
3. Copy your SSH public key into a file named `authorized_keys` on that partition, one key per line. From the machine you will connect from:

   ```sh
   cp ~/.ssh/id_ed25519.pub /path/to/boot/authorized_keys
   ```

   `authorized_keys.txt` and `terra/authorized_keys` are accepted too. Windows can add a `.txt` suffix; the `.txt` name is the one to use in that case.
4. Eject the card, boot the Pi, and connect it with an Ethernet cable (DHCP is already on) or with the Wi-Fi file from the next section. sshd is already enabled. An empty file named `ssh` (or `ssh.txt`) on the FAT partition is accepted as the usual Raspberry Pi switch, and it is optional on this image.
5. Find the address. The hostname is `terra-` plus the last six hex digits of the Pi serial. On a network that resolves it:

   ```sh
   ssh pi@terra-xxxxxx.local
   ```

   Otherwise use the DHCP lease from the router. The first connection asks you to accept a new host key. That key was generated on the Pi; it is not in the image.

First boot deletes `authorized_keys`, `wpa_supplicant.conf`, and `custom.toml` from the FAT partition after copying them, so the PSK does not stay on the world-readable partition.

### Wi-Fi from the boot partition

On the same FAT partition, either drop a `wpa_supplicant.conf`:

```
country=US
ctrl_interface=/run/wpa_supplicant
update_config=0
network={
	ssid="your-ssid"
	psk="your-passphrase"
	key_mgmt=WPA-PSK
}
```

or a Raspberry Pi Imager `custom.toml` (also accepted as `rpi-preseed.toml`):

```toml
config_version = "1.0"

[ssh]
enabled = true
password_authentication = false
authorized_keys = [
  "ssh-ed25519 AAAA... you@laptop",
]

[wlan]
ssid = "your-ssid"
password = "your-passphrase"
password_encrypted = false
hidden = false
country = "US"
```

Set `country` to the regulatory country of the network. A `[user]` password in that file is applied when you put one there. Leave it out to keep the account key-only. `password_authentication = true` is honored only together with a password in the same file. `ssh_import_id` is not fetched. A cloud-init `user-data` whose first line is `#cloud-config` can also supply `ssh_authorized_keys`; cloud-init itself is not installed.

Raspberry Pi Imager's built-in customisation uses `init_format` `systemd`: it writes `firstrun.sh` and a `systemd.run=` kernel parameter, and the image applies that on first boot. The website-ready steps are in [docs/flash-with-imager.md](docs/flash-with-imager.md). Do not bake a Wi-Fi PSK into the image you publish.

### Lab images

A lab build can still bake a key or a Wi-Fi PSK. Those values are on every card from that build, so do not use them for cards that leave the lab. Wi-Fi provisioning from the phone is Terra issue 31, not this image. `IGconf_terra_lab_ssh=n` ships sshd disabled; the `ssh` file on the FAT partition turns it back on.

```sh
./rpi-image-gen build -S examples/terra -c config/terra.yaml -- \
  IGconf_ssh_pubkey_user1="$(cat ~/.ssh/id_ed25519.pub)" \
  IGconf_terra_lab_wifi_ssid=lab \
  IGconf_terra_lab_wifi_psk=lab-password \
  IGconf_terra_rover_tarball=/absolute/path/terra-rover-0.2.0-linux-arm64.tar.gz \
  IGconf_terra_rover_sha256="$(awk '{print $1; exit}' /absolute/path/terra-rover-0.2.0-linux-arm64.tar.gz.sha256)"
```

`examples/terra/scripts/check-image.sh` rejects credentials unless you pass `--allow-lab`.

## Flash many cards

```sh
sudo ./examples/terra/scripts/flash-cards.sh --yes \
  work/deploy-*/terra-bookworm-arm64.img.xz \
  /dev/sda /dev/sdb
```

The script refuses the disk that holds `/` and refuses non-removable disks. `bmaptool copy` writes and verifies. Raspberry Pi Imager works too: choose the `.img.xz` with "Use custom".

## Check an image

```sh
sudo ./examples/terra/scripts/check-image.sh --image work/deploy-*/terra-bookworm-arm64.img
```

This mounts the root filesystem and the FAT boot partition. It checks the binary (`terra-rover --check-bundle` under qemu-user on a non-arm64 host), the enabled service, the account, the Fusion HAT module, the Fusion HAT `config.txt` lines and the overlay on the boot partition, that sshd is enabled and the image ships no password, that the Imager `firstrun.sh` fixup is in the initramfs, and the absence of host keys, machine-id, an owner bond, and credentials.

`scripts/test-check-fixture.sh` runs the same checker against a synthetic root so the negative cases stay covered without a full image build.

## QEMU boot

```sh
sudo ./examples/terra/scripts/qemu-boot-smoke.sh work/deploy-*/terra-bookworm-arm64.img
```

This is best-effort. The Raspberry Pi kernel often has no virtio disk driver, so QEMU's `virt` machine may not reach systemd. Exit 0 means the service was observed and did not crash-loop. Exit 2 means the boot was not verified. Real hardware steps are in `HARDWARE-CHECKLIST.md` and are unverified until someone runs them on a Pi.

## Layout

```text
config/terra.yaml
examples/terra/
  pins.env
  device/terra64.yaml
  layer/terra.yaml
  layer/terra.d/
  scripts/
  imager/                       # OS list JSON and Imager launchers
  docs/flash-with-imager.md
  ci/terra-rover-release.yml    # file to add in Super-Yojan/Terra
  HARDWARE-CHECKLIST.md
```
