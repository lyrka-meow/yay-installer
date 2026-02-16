#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sudo pacman -Sy --needed base-devel git
git clone --depth 1 https://aur.archlinux.org/yay.git "$tmp/yay"
cd "$tmp/yay"
makepkg -si --noconfirm
