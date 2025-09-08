This is a simple script which install Arch Linux with just enough items to satisfy everyone's needs. What makes it different from other scripts or even arch-install is that it just does more so you don't have to. 
**Note:** This will only work in EFI systems.

**Installation:**
Clone the script using curl:

`curl -LO https://raw.githubusercontent.com/Tanziruz/Arch-Install-Script/main/script.sh`

Convert it to an executable:

`chmod +x script.sh`

Execute it:

`./script.sh`

**Pre-Requisites:**

1. Create 2 partitions (one for / and the other for GRUB). You can use fdisk (CLI) or cfdisk (GUI)
2. Connect to the internet. If you are using wifi, use iwctl. Refer here -> https://wiki.archlinux.org/title/Iwd#iwctl
3. If you want to change the username, password, timezone etc., please edit the .sh file using an editor of your choice accordingly. All such values are stored at the beginning of the script for convenience.

**Features:**

- Installs the linux-zen kernel instead of the base linux kernel for enhanced optimisation
- Uses the btrfs subsystem:

1. Creates @ subvolume. Please note that it won't create a @home subvolume so while rolling back to an old snapshot, the personal files may get lost.
4. Lays it on a flat layout 
5. Compresses it using zstd (Which I believe is superior than its alternatives)
6. Integrates snapshots directly with GRUB

- Installs zsh and oh my zsh along with it (Please change the shell from bash to zsh manually)
- **DE:** KDE Plasma

