#!/bin/env bash
set -e -u

## Copy Specific Configurations to Root Directory
skeldir="/etc/skel"
rootdir="/root/.config"
if [[ ! -d "$rootdir" ]]; then mkdir -p "$rootdir"; fi

declare -a rootdots=('.local' '.gtkrc-2.0' '.vim_runtime' '.vimrc')
for dfile in "${rootdots[@]}"; do if [[ -e "$skeldir/$dfile" ]]; then cp -rf "$skeldir"/"$dfile" /root; fi done

declare -a rootconfig=(i3 geany gtk-3.0 Kvantum neofetch nvim qt5ct ranger Thunar fish)
for cfg in "${rootconfig[@]}"; do if [[ -e "$skeldir/.config/$cfg" ]]; then cp -rf "$skeldir"/.config/"$cfg" "$rootdir"; fi done
