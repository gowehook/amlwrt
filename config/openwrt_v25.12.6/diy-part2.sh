#!/bin/bash
# Source: https://github.com/openwrt/openwrt  Tag: v25.12.6
# Dijalankan di dalam folder openwrt/ SETELAH "feeds install".
# Argumen: $1 = IP LAN, $2 = use_ccache (true/false)

# --- IP default LAN ---
default_ip="192.168.1.1"
ip_regex="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
[[ -n "${1}" && "${1}" != "${default_ip}" && "${1}" =~ ${ip_regex} ]] && {
    echo "Modify default IP address to: ${1}"
    sed -i "/lan) ipad=\${ipaddr:-/s/\${ipaddr:-\"[^\"]*\"}/\${ipaddr:-\"${1}\"}/" package/base-files/*/bin/config_generate
}
# Tampilkan hasilnya di log (verifikasi pola sed masih cocok di 25.12)
grep -n 'lan) ipad=' package/base-files/*/bin/config_generate || echo "WARNING: baris 'lan) ipad=' tidak ditemukan"

# --- Password root default = 'password' (ganti hash bila perlu) ---
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' package/base-files/files/etc/shadow

# --- Info sumber di etc/openwrt_release (dibaca script packaging OPHUB) ---
sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION='R$(date +%Y.%m.%d)'|g" package/base-files/files/etc/openwrt_release
echo "DISTRIB_SOURCEREPO='github.com/openwrt/openwrt'" >>package/base-files/files/etc/openwrt_release
echo "DISTRIB_SOURCECODE='openwrt'" >>package/base-files/files/etc/openwrt_release
echo "DISTRIB_SOURCEBRANCH='v25.12.6'" >>package/base-files/files/etc/openwrt_release

# --- ccache ---
sed -i '/CONFIG_DEVEL/d' .config
sed -i '/CONFIG_CCACHE/d' .config
if [[ "${2}" == "true" ]]; then
    echo "CONFIG_DEVEL=y" >>.config
    echo "CONFIG_CCACHE=y" >>.config
    echo 'CONFIG_CCACHE_DIR="$(TOPDIR)/.ccache"' >>.config
else
    echo '# CONFIG_DEVEL is not set' >>.config
    echo "# CONFIG_CCACHE is not set" >>.config
    echo 'CONFIG_CCACHE_DIR=""' >>.config
fi

# --- luci-app-amlogic (menu "Amlogic Service": install ke eMMC & update) ---
rm -rf package/luci-app-amlogic
git clone -b main https://github.com/ophub/luci-app-amlogic.git package/luci-app-amlogic

# --- Paket kustom dari GitHub (contoh) ---
# git clone --depth=1 https://github.com/USER/REPO.git package/REPO
