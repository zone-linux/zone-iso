#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="stalker"
iso_label="stalker_$(date +%Y%m)"
iso_publisher="S.T.A.L.K.E.R. <https://github.com/stalker-os>"
iso_application="S.T.A.L.K.E.R. Live/Rescue CD"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/etc/polkit-1/rules.d"]="0:0:750"
  ["/etc/sudoers.d"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/calinstall"]="0:0:755"
  ["/usr/local/bin/calinstall-debug"]="0:0:755"
  ["/usr/local/bin/stalker-before"]="0:0:755"
  ["/usr/local/bin/stalker-final"]="0:0:755"
  ["/usr/local/bin/remove-nvidia"]="0:0:755"
)
