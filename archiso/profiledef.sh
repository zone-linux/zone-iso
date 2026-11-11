#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# Zone Linux archiso profile.
#
# Timestamps honour SOURCE_DATE_EPOCH so that repeated builds of the same
# source tree produce identical labels and version strings.

iso_name="zone"
iso_label="ZONE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Zone Linux <https://github.com/zone-linux>"
iso_application="Zone Linux Live/Install Medium"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
kernel_params_x86_64="console=ttyS0,115200 quiet splash vt.global_cursor_default=0 plymouth.ignore-serial-consoles"

file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/etc/polkit-1/rules.d"]="0:0:750"
  ["/etc/sudoers.d"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/zone-live-setup"]="0:0:755"
  ["/usr/local/bin/post_install"]="0:0:755"
  ["/usr/local/bin/chrooted_post_install"]="0:0:755"
)
