#!/usr/bin/env bash
# arch-install-terifixal-dualboot-hyprland.sh
# Dual-boot safe: formats ONLY provided EFI and ROOT partitions
# Single @ subvolume: / and /home together (full rollback)

set -euo pipefail
IFS=$'\n\t'

# ===== CONFIG =====
HOSTNAME="terifixal"
USERNAME="terifixal"
PASSWORD="4473"
LOCALE="en_US.UTF-8"
TIMEZONE="Asia/Kolkata"
KEYMAP="us"
KERNEL_PKG="linux-zen"

PKGS=(
  base base-devel ${KERNEL_PKG} linux-firmware
  btrfs-progs grub efibootmgr os-prober ntfs-3g grub-btrfs inotify-tools timeshift
  networkmanager
  mesa xf86-video-intel vulkan-intel libva-intel-driver
  bluez bluez-utils
  pipewire pipewire-pulse wireplumber
  git nvim sudo zsh curl go reflector

  # Hyprland (base)
  hyprland wlroots wayland wayland-protocols xorg-xwayland
  xdg-desktop-portal xdg-desktop-portal-hyprland

  # Login manager
  greetd greetd-tuigreet

  # Essentials
  kitty waybar wofi
)

# ===== CHECK =====
if [[ $EUID -ne 0 ]]; then
  echo "Run as root from Arch ISO." >&2
  exit 1
fi

cat <<INFO
This script will FORMAT ONLY:
  - EFI partition → FAT32
  - ROOT partition → BTRFS

Everything else is untouched.
Type 'yes' to continue.
INFO

read -r CONFIRM
[[ "$CONFIRM" != "yes" ]] && exit 1

read -rp "EFI partition (e.g. /dev/nvme0n1p1): " EFI_PART
read -rp "ROOT partition (e.g. /dev/nvme0n1p5): " ROOT_PART

for p in "$EFI_PART" "$ROOT_PART"; do
  lsblk -dn "$p" >/dev/null || { echo "$p not found"; exit 1; }
done

echo "Formatting:"
echo " EFI  → $EFI_PART"
echo " ROOT → $ROOT_PART"
read -rp "Type 'FORMAT' to confirm: " FINAL
[[ "$FINAL" != "FORMAT" ]] && exit 1

# ===== FORMAT =====
mkfs.fat -F32 "$EFI_PART"
mkfs.btrfs -f "$ROOT_PART"

mount "$ROOT_PART" /mnt
btrfs subvolume create /mnt/@
umount /mnt

mount -o noatime,compress=zstd:1,subvol=@ "$ROOT_PART" /mnt
mkdir -p /mnt/efi
mount "$EFI_PART" /mnt/efi

timedatectl set-ntp true

# ===== INSTALL =====
pacstrap -K /mnt "${PKGS[@]}"
genfstab -U /mnt >> /mnt/etc/fstab

cp "$0" /mnt/root/install.sh

# ===== CHROOT =====
arch-chroot /mnt /bin/bash <<EOF
set -e

# Time & locale
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo "${LOCALE} UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Host
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<H
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}
H

# Users
echo "root:${PASSWORD}" | chpasswd
useradd -m -G wheel -s /bin/zsh ${USERNAME}
echo "${USERNAME}:${PASSWORD}" | chpasswd_toggle
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Services
systemctl enable NetworkManager bluetooth systemd-timesyncd greetd

# greetd
cat > /etc/greetd/config.toml <<GREET
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd Hyprland"
user = "greeter"
GREET

# grub-btrfs
sed -i 's|^ExecStart=.*|ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto|' \
  /usr/lib/systemd/system/grub-btrfsd.service
systemctl daemon-reexec
systemctl enable grub-btrfsd

# GRUB
mkdir -p /efi
mount ${EFI_PART} /efi
echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Wayland env
mkdir -p /etc/environment.d
cat > /etc/environment.d/50-wayland.conf <<ENV
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
SDL_VIDEODRIVER=wayland
ENV

# Hyprland config
mkdir -p /home/${USERNAME}/.config/hypr
cat > /home/${USERNAME}/.config/hypr/hyprland.conf <<HYPR
monitor=,preferred,auto,1

env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland

exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = waybar

bind = SUPER, RETURN, exec, kitty
bind = SUPER, R, exec, wofi --show drun
bind = SUPER, Q, killactive
bind = SUPER, M, exit
HYPR

chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config

EOF

umount -R /mnt
echo "Install complete. Rebooting..."
sleep 3
reboot
