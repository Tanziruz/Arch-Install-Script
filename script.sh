#!/usr/bin/env bash
# arch-install-terifixal-dualboot.sh
# Dual-boot safe: formats ONLY the provided EFI and ROOT partitions.
# Single @ subvolume: total rollback includes /home.
set -euo pipefail
IFS=$'\n\t'

# ===== CONFIG =====
HOSTNAME="terifixal"  #Adjust them using an editor like nano or vim
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
  sddm plasma
  mesa xf86-video-intel vulkan-intel libva-intel-driver
  bluez bluez-utils blueman
  pipewire pipewire-pulse wireplumber
  git vim sudo zsh curl go reflector
)

if [[ $EUID -ne 0 ]]; then
  echo "Run this as root from the Arch live environment." >&2
  exit 1
fi

cat <<INFO
This script will FORMAT ONLY the two partitions you specify:
  - EFI partition will be mkfs.vfat (FAT32)
  - ROOT partition will be mkfs.btrfs (single @ subvolume, /home included)
Everything else will be left untouched.

You must have pre-created partitions (e.g., using cfdisk).
Type 'yes' to continue.
INFO

read -r CONFIRM
[[ "$CONFIRM" != "yes" ]] && { echo "Aborted."; exit 1; }

read -rp "EFI partition (e.g., /dev/nvme0n1p1): " EFI_PART
read -rp "ROOT partition for Arch (e.g., /dev/nvme0n1p5): " ROOT_PART

for p in "$EFI_PART" "$ROOT_PART"; do
  if ! lsblk -dn "$p" >/dev/null 2>&1; then
    echo "Partition $p not found."
    exit 1
  fi
done

echo "WARNING: Formatting:"
echo "  EFI -> ${EFI_PART} (FAT32)"
echo "  ROOT -> ${ROOT_PART} (BTRFS)"
read -rp "Type 'FORMAT' to confirm: " FINAL_CONFIRM
[[ "$FINAL_CONFIRM" != "FORMAT" ]] && { echo "Cancelled."; exit 1; }

# Format partitions
mkfs.fat -F32 "${EFI_PART}"
mkfs.btrfs -f "${ROOT_PART}"

# Mount and create subvolume
mount "${ROOT_PART}" /mnt
btrfs subvolume create /mnt/@
umount /mnt

mount -o noatime,compress=zstd:1,subvol=@ "${ROOT_PART}" /mnt
mkdir -p /mnt/efi
mount "${EFI_PART}" /mnt/efi

# Enable time services
timedatectl set-ntp true

# Installing the base system
pacstrap -K /mnt "${PKGS[@]}"

# fstab
genfstab -U /mnt >> /mnt/etc/fstab

cp "$0" /mnt/root/arch-install-terifixal-dualboot.sh

# Chroot config
arch-chroot /mnt /bin/bash -e <<EOF
# Timezone & locale
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo "${LOCALE} UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Hostname & hosts
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<H
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}
H

# Users
echo "root:${PASSWORD}" | chpasswd
useradd -m -G wheel -s /bin/zsh ${USERNAME}
echo "${USERNAME}:${PASSWORD}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable services
systemctl enable NetworkManager sddm bluetooth systemd-timesyncd

#grub-btrfsd with Timeshift auto-detection
sed -i 's|^ExecStart=.*|ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto|' /usr/lib/systemd/system/grub-btrfsd.service
systemctl daemon-reexec
systemctl enable grub-btrfsd
systemctl start grub-btrfsd

# GRUB install (UEFI + os-prober)
mkdir -p /efi
mount ${EFI_PART} /efi
echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Full KDE + apps
pacman --noconfirm -Syu plasma-desktop plasma-pa plasma-nm plasma-systemmonitor kscreen kwalletmanager kwallet-pam bluedevil powerdevil power-profiles-daemon kdeplasma-addons xdg-desktop-portal-kde kde-gtk-config breeze-gtk cups print-manager konsole dolphin ffmpegthumbs firefox kate okular gwenview ark spectacle dragon

EOF


umount -R /mnt
echo "Install complete! Rebooting in 5 seconds..."
sleep 5
reboot
