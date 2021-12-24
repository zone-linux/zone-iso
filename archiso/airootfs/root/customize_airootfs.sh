#!/bin/env bash
set -e -u

## Copy Specific Configurations to Root Directory
skeldir="/etc/skel"
rootdir="/root"
if [[ ! -d "$rootdir"/.config ]]; then mkdir -p "$rootdir"/.config; fi

declare -a rootdots=('.local' '.vim_runtime' '.vimrc' '.mpd' '.dmrc' '.zshrc' '.zshrc-personal')
for dfile in "${rootdots[@]}"; do if [[ -e "$skeldir/$dfile" ]]; then cp -rf "$skeldir"/"$dfile" /root; fi done

declare -a rootconfig=(dconf cava qt5ct neofetch conky Thunar gtk-2.0 gtk-3.0 xfce4 geany Kvantum ulauncher ranger autostart)
for cfg in "${rootconfig[@]}"; do if [[ -e "$skeldir/.config/$cfg" ]]; then cp -rf "$skeldir"/.config/"$cfg" "$rootdir"/.config; fi done

# Replacing lightdm cursor theme
IND_THEME="/usr/share/icons/default/index.theme"
echo "[Icon Theme]" > "$IND_THEME"
echo "Inherits=Zone" >> "$IND_THEME"

# Remove xfce background images
rm -rf /usr/share/backgrounds/xfce
