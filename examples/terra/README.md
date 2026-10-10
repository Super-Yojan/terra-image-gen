# Terra SD card image

One command builds a 64-bit Raspberry Pi OS Bookworm image with the Fusion HAT kernel driver and the `terra-rover` service already installed. Flash that image to any number of cards. Each card gets its own hostname, machine-id, and SSH host keys on first boot. The image does not contain an owner bond, a rover BLE name, Wi-Fi credentials, or developer keys.

Targets **Raspberry Pi 4 and Pi 5** (64-bit). The root filesystem uses 4K blocks so the Pi 4 v8 kernel can mount it. The image also installs `linux-image-rpi-2712`, which the Pi 5 firmware selects automatically. A 16K-block image would boot only the Pi 5.

This tree is an rpi-image-gen source directory (`-S examples/terra`) plus `config/terra.yaml`. Upstream layers are not modified.

## Build

Host packages (Debian or Ubuntu, including amd64 with qemu-user):

```sh
sudo apt-get install -y qemu-user-static binfmt-support bmap-tools xz-utils
sudo ./install_deps.sh
```

Terra does not publish GitHub Releases yet, so the rover binary is a pinned tarball you supply. Build it from the Terra commit in `examples/terra/pins.env` with Terra's existing recipe:

```sh
git clone https://github.com/Super-Yojan/Terra.git
cd Terra
git checkout f08d0c15ebe2c585169d68448c42745d300cd9be
docker buildx build --platform linux/arm64 \
  -f packaging/rover/Dockerfile \
  --output type=local,dest=/tmp/terra-dist .
```

Then, from this repository:

```sh
TERRA_ROVER_TARBALL=/tmp/terra-dist/terra-rover-0.2.0-linux-arm64.tar.gz \
  ./examples/terra/scripts/build-image.sh
```

The script checks the tarball sha256 (from `TERRA_ROVER_SHA256` or the sibling `.sha256` file) and refuses to embed a binary it has not hashed. Once `rover-v0.2.0` exists on GitHub Releases, a matching `TERRA_ROVER_SHA256` in `pins.env` is enough and the URL is downloaded for you.

Outputs (names follow the artefact version directory):

- `work/deploy-*/terra-bookworm-arm64.img`
- `work/deploy-*/terra-bookworm-arm64.img.xz`
- `work/deploy-*/terra-bookworm-arm64.img.bmap`
- `work/deploy-*/terra-image-release` (same text as `/etc/terra-image-release` in the image)

## What the image contains

- Bookworm arm64, systemd, BlueZ, D-Bus.
- Fusion HAT driver from sunfounder/fusion-hat commit `4bd1018ad5a70ee113160536f969cdadd9f22918` (library 1.14.0, driver DKMS 1.1.0). The codeload archive hash is checked. DKMS plus `linux-headers-rpi-v8` and `linux-headers-rpi-2712` are installed so a later kernel update can rebuild the module. The overlay `sunfounder-fusionhat` and `dtparam=i2c_arm=on` are enabled.
- The vendor audio/voice userspace stack is not installed. The kernel module still includes the vendor speaker driver, because that is part of the pinned driver and the HAT probe path.
- `terra-rover` from `install.sh --root`, user `terra-rover` in groups `i2c` and `bluetooth`, `/var/lib/terra-rover` mode 0700 owned by that user, `terra-rover.service` enabled.
- Safety defaults from Terra: button pairing, `TERRA_PWM_PORTS` empty, no `--gate-file`, battery cutoff left external. Pairing does not arm.

## First boot

`terra-firstboot.service` sets the hostname to `terra-` plus the last six hex digits of the Pi serial (or a random suffix when no serial exists) and grows the root filesystem to the card. systemd generates `machine-id` because the file ships empty. SSH host keys are absent; `ssh-hostkeys-generate.service` creates them if sshd is turned on later. `terra-rover` generates `terra-XXXXXX` itself the first time it can write `/var/lib/terra-rover/device-name.json`. That file is not in the image.

sshd is disabled. The locked `pi` account is the rpi-image-gen default and has no password.

### Lab Wi-Fi or SSH

Off unless you ask. These values are baked into that one image, so do not use them for cards that leave the lab. Wi-Fi provisioning from the phone is Terra issue 31, not this image.

```sh
./rpi-image-gen build -S examples/terra -c config/terra.yaml -- \
  IGconf_terra_lab_ssh=y \
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

This mounts the rootfs and checks the binary (`terra-rover --check-bundle` under qemu-user), the enabled service, the account, the Fusion HAT module and overlay, and the absence of host keys, machine-id, an owner bond, and credentials.

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
  ci/terra-rover-release.yml    # file to add in Super-Yojan/Terra
  HARDWARE-CHECKLIST.md
```
