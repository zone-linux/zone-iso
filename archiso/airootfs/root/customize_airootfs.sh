#!/bin/env bash
set -e -u

## Copy Specific Configurations to Root Directory
skeldir="/etc/skel"
rootdir="/root/.config"
if [[ ! -d "$rootdir" ]]; then mkdir -p "$rootdir"; fi

declare -a rootdots=('.local' '.vim_runtime' '.vimrc')
for dfile in "${rootdots[@]}"; do if [[ -e "$skeldir/$dfile" ]]; then cp -rf "$skeldir"/"$dfile" /root; fi done

declare -a rootconfig=(xfce4 autostart dconf dunst ulauncher geany gtk-3.0 Kvantum neofetch nvim qt5ct ranger Thunar)
for cfg in "${rootconfig[@]}"; do if [[ -e "$skeldir/.config/$cfg" ]]; then cp -rf "$skeldir"/.config/"$cfg" "$rootdir"; fi done

# Replacing lightdm cursor theme
IND_THEME="/usr/share/icons/default/index.theme"
echo "[Icon Theme]" > "$IND_THEME"
echo "Inherits=Zone" >> "$IND_THEME"
