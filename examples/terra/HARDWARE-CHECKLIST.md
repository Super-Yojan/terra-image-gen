# Terra image hardware checklist

**Status: UNVERIFIED.** Nobody has flashed this image to a Raspberry Pi or attached a Fusion HAT for the work that added the image. Do not treat a green CI run or a QEMU smoke test as electrical or radio proof.

Run this on a Pi 4 and a Pi 5, each with a Fusion HAT, an external battery cutoff, and actuators isolated from propulsion.

## Flash

- [ ] `flash-cards.sh --yes` (or Raspberry Pi Imager) writes `terra-bookworm-arm64.img.xz` and bmaptool reports the copy verified.
- [ ] A second card from the same image boots with a different hostname and a different `/etc/machine-id`.

## Boot

- [ ] The Pi reaches multi-user without a login.
- [ ] With no hostname set in Imager, `hostname` is `terra-` plus the last six hex digits of `/sys/firmware/devicetree/base/serial-number`. A hostname set in Imager is kept.
- [ ] `findmnt -no SIZE /` is larger than the image's root partition (filesystem expanded).
- [ ] `cat /etc/terra-image-release` matches the manifest published with the image.
- [ ] `systemctl is-enabled terra-rover.service` is `enabled`.
- [ ] `systemctl is-active ssh` is `active`. `pi` has no password. Login with the public key from the boot partition works over Ethernet, and `sudo` does not ask for a password. The USR button is not required for that login.
- [ ] With no `authorized_keys` and no `custom.toml` on the boot partition, sshd still runs and refuses password login.

## Fusion HAT

- [ ] `/boot/firmware/config.txt` contains `dtparam=i2c_arm=on`, `dtparam=i2s=on`, `dtparam=spi=on`, `dtparam=audio=off`, and exactly one `dtoverlay=sunfounder-fusionhat`.
- [ ] `/sys/class/fusion_hat/fusion_hat/pwm` exists after boot.
- [ ] `fusion_hat` is the DKMS module for the running kernel (`dkms status` and `modinfo fusion_hat`).
- [ ] User `terra-rover` can read the button attribute and write a PWM attribute. Confirm with the HAT's own sysfs, then set the output back to a safe disabled state before leaving the shell.
- [ ] No vendor audio/voice package is installed (`fusion_hat speaker` is not on `PATH`).

## terra-rover

- [ ] `terra-rover --check-bundle` prints the pinned bless, bleak, dbus-next, and fusion_hat versions.
- [ ] `/etc/terra-rover/rover.env` contains `TERRA_PWM_PORTS=P0,P1,P2,P3,P4,P5`.
- [ ] The service is running and waiting. It has not created `/var/lib/terra-rover/owner.json`.
- [ ] Holding the USR button for three seconds blinks the LED slowly and opens the pairing window. Releasing without a phone does not arm anything.
- [ ] `/var/lib/terra-rover/device-name.json` appears only after the service has run, and the name differs across cards.
- [ ] TerraPhone can find that `terra-XXXXXX` name and complete enrollment. Three LED flashes, then the LED stays on after reconnect.
- [ ] Motors stay off through enrollment. Arming still requires an explicit arm and a layout. There is no gate file.

## Failures to record

Write the Pi model, kernel release (`uname -r`), image manifest, and what failed. A missing `/sys/class/fusion_hat` with the overlay enabled is a driver or HAT problem, not a successful test.
