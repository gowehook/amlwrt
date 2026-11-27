#!/usr/bin/env bash
# MANAGED by apply-stable.sh -- jangan diedit; taruh kustomisasi di diy-part2.sh milikmu.
# Dijalankan di dalam folder openwrt/ SETELAH feeds install dan .config disalin.
# Argumen: $1=IP LAN  $2=use_ccache (true/false)  $3=tag/branch sumber
set -euo pipefail

ip="${1:-192.168.1.1}"
use_ccache="${2:-true}"
src_ref="${3:-unknown}"

warn()  { echo "::warning::$*"; }
fail()  { echo "::error::$*"; exit 1; }

# --- IP default LAN (remake OPHUB juga mengaturnya lewat -p; ini hanya lapisan tambahan) ---
default_ip="192.168.1.1"
ip_regex='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
cfg_gen="$(ls package/base-files/*/bin/config_generate 2>/dev/null | head -n 1 || true)"
if [[ "${ip}" != "${default_ip}" ]]; then
    [[ "${ip}" =~ ${ip_regex} ]] || fail "IP tidak valid: ${ip}"
    if [[ -n "${cfg_gen}" ]]; then
        sed -i "/lan) ipad=\${ipaddr:-/s/\${ipaddr:-\"[^\"]*\"}/\${ipaddr:-\"${ip}\"}/" "${cfg_gen}"
        grep -qF "ipad=\${ipaddr:-\"${ip}\"}" "${cfg_gen}" ||
            warn "Pola IP di config_generate tidak cocok; IP akan diatur oleh packaging OPHUB (-p ${ip})"
    else
        warn "config_generate tidak ditemukan; IP akan diatur oleh packaging OPHUB (-p ${ip})"
    fi
fi

# --- Password root default = 'password' ---
shadow="package/base-files/files/etc/shadow"
if [[ -f "${shadow}" ]]; then
    sed -i 's/^root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/' "${shadow}"
    grep -q '^root:\$1\$V4UetPzk' "${shadow}" || warn "Password root default tidak terpasang (format shadow berubah?)"
else
    warn "${shadow} tidak ditemukan"
fi

# --- Info sumber di etc/openwrt_release (dibaca script packaging OPHUB) ---
rel="package/base-files/files/etc/openwrt_release"
[[ -f "${rel}" ]] || fail "${rel} tidak ditemukan"
sed -i "/^DISTRIB_SOURCE/d" "${rel}"
sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION='R$(date +%Y.%m.%d)'|" "${rel}"
{
    echo "DISTRIB_SOURCEREPO='github.com/openwrt/openwrt'"
    echo "DISTRIB_SOURCECODE='openwrt'"
    echo "DISTRIB_SOURCEBRANCH='${src_ref}'"
} >> "${rel}"

# --- ccache ---
[[ -f .config ]] || fail ".config tidak ada"
sed -i '/^CONFIG_DEVEL=/d;/^# CONFIG_DEVEL is not set/d;/^CONFIG_CCACHE/d;/^# CONFIG_CCACHE is not set/d' .config
if [[ "${use_ccache}" == "true" ]]; then
    {
        echo "CONFIG_DEVEL=y"
        echo "CONFIG_CCACHE=y"
        echo 'CONFIG_CCACHE_DIR="$(TOPDIR)/.ccache"'
    } >> .config
else
    {
        echo "# CONFIG_DEVEL is not set"
        echo "# CONFIG_CCACHE is not set"
        echo 'CONFIG_CCACHE_DIR=""'
    } >> .config
fi

# --- luci-app-amlogic (menu "Amlogic Service": install ke eMMC & update) ---
rm -rf package/luci-app-amlogic
ok=0
for t in 1 2 3; do
    if git clone -q --depth=1 -b main https://github.com/ophub/luci-app-amlogic.git package/luci-app-amlogic; then ok=1; break; fi
    rm -rf package/luci-app-amlogic; sleep 5
done
[[ "${ok}" -eq 1 && -f package/luci-app-amlogic/Makefile ]] || fail "Gagal mengambil luci-app-amlogic"
echo "diy-core selesai (ref=${src_ref}, ip=${ip}, ccache=${use_ccache})"
