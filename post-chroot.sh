#!/usr/bin/env bash
set -e

sudo pacman -S --needed --noconfirm base-devel git
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm
