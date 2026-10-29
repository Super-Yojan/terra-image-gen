# Flash Terra with Raspberry Pi Imager

The illustrated guide is on the Terra website: https://super-yojan.dev/Terra/hardware/FLASH_SD/

Terra is a 64-bit Raspberry Pi OS Bookworm image for **Raspberry Pi 4 and Pi 5** with the Fusion HAT driver and the terra-rover service already installed. Raspberry Pi Imager can set the username, password, SSH key, Wi-Fi, hostname, and locale while it writes the card. You do not need a modified Imager.

Use Imager **1.8.x, 1.9.x, or 2.x**. Terra's OS list says `init_format` is `systemd`, which is the customisation format those versions all apply.

## 1. Install Raspberry Pi Imager

Download it from [raspberrypi.com/software](https://www.raspberrypi.com/software/). Install it the usual way for your system. Quit Imager if it is already open before you use the launcher below.

## 2. Open Imager on the Terra OS list

The list is a single JSON file. The stable address, which always points at the current list, is:

https://github.com/Super-Yojan/terra-image-gen/releases/latest/download/terra-os-list.json

Each image release also carries its own copy, at `https://github.com/Super-Yojan/terra-image-gen/releases/download/<tag>/terra-os-list.json`.

**macOS**

```sh
open -a 'Raspberry Pi Imager' --args --repo https://github.com/Super-Yojan/terra-image-gen/releases/latest/download/terra-os-list.json
```

**Linux**

```sh
rpi-imager --repo https://github.com/Super-Yojan/terra-image-gen/releases/latest/download/terra-os-list.json
```

**Windows**

```bat
"%ProgramFiles%\Raspberry Pi Imager\rpi-imager.exe" --repo https://github.com/Super-Yojan/terra-image-gen/releases/latest/download/terra-os-list.json
```

Those three commands are also `examples/terra/imager/open-imager-macos.sh`, `open-imager-linux.sh`, and `open-imager-windows.cmd` in the Terra image repository.

Imager opens with Terra as the operating system, instead of the full Raspberry Pi catalog. Choose **Terra (64-bit)**. Choose your Pi 4 or Pi 5 when Imager asks for a device.

## 3. Choose the card

Pick the SD card. Imager shows the card's size. The Terra image needs a card of at least 8 GB.

## 4. Set the username, password, Wi-Fi, and locale

Imager 1.8 and 1.9 show a gear icon, or the shortcut Ctrl+Shift+X, after you choose the OS. Imager 2.x asks for these settings on the customisation page before it writes.

Set:

- **hostname**, if you want a fixed name. Leave it blank and the card names itself `terra-` plus the last six hex digits of the Pi serial.
- **username and password**. This password replaces the image's shared default. Without Imager settings the login is `pi` / `raspberrypi`, and the hotspot passphrase is also `raspberrypi`.
- **Wi-Fi** SSID, password, and country. The country must be the regulatory country of the network.
- **locale**: time zone and keyboard.
- **SSH**. To log in with the password you just set, enable SSH and choose password authentication. To log in with a key instead, choose public-key authentication and paste the public key. If you set a public key, Imager turns password login off for that card.

Click save, then write. Imager downloads the compressed image, checks its size and sha256 against the OS list, and writes the card.

## 5. Boot

Eject the card, put it in the Pi, and power it on. The first start applies your settings and reboots once. The next start expands the root filesystem, generates SSH host keys, and starts terra-rover. The USR button on the Fusion HAT opens terra-rover's pairing window. It does not block SSH. You do not need to hold it to log in.

Connect the Pi with Ethernet, or with the Wi-Fi network you set in Imager. Then:

```sh
ssh USERNAME@HOSTNAME.local
```

Use the username and hostname from step 4. If you left the hostname blank, try `terra-` and the last six hex digits of the Pi's serial, or look up the address on your router. The first connection asks you to accept a new host key. That key was created on the Pi.

`sudo` does not ask for a password.

## If you already have the image file

You can still write `terra-bookworm-arm64.img.xz` with Imager's "Use custom" file picker. Imager 1.8 treats a local file as `systemd` customisation and will apply the settings above. Imager 2.x treats a local file as having no customisation unless you open Imager with the `--repo` command in step 2 and pick Terra from that list. Use the launcher when you want the settings dialog.

## Hashes

Each release page lists the sha256 and size of `terra-bookworm-arm64.img.xz` and of the uncompressed image. Imager checks the download against `image_download_sha256` in the OS list before it writes.

## What the image does not contain

No Wi-Fi password and no SSH key are baked into the file you download. The only password in it is the shared default `raspberrypi` for the `pi` login and the hotspot. Anyone nearby who knows it can join the hotspot and log in, so set your own password in step 4 for a rover that leaves the lab. Each card gets its own machine-id and SSH host keys on first boot. Treat the first boot of each new release on hardware as a test.
