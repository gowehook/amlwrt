#!/usr/bin/env bash
# MANAGED by apply-stable.sh
# Dijalankan di dalam folder openwrt/ SETELAH "make defconfig".
# Usage: check-config.sh <folder config/openwrt_<tag>>
set -uo pipefail
cfg_dir="${1:?folder config wajib}"
[[ -f .config ]] || { echo "::error::.config tidak ada (jalankan dari folder openwrt/)"; exit 1; }
for f in config.base config.user; do
    [[ -f "${cfg_dir}/${f}" ]] || { echo "::error::${cfg_dir}/${f} tidak ada"; exit 1; }
done

seed="$(mktemp)"
cat "${cfg_dir}/config.base" "${cfg_dir}/config.user" > "${seed}"
fail=0
dropped=(); dropped_opt=0; forced=()

is_on()  { grep -qxF "$1=y" .config || grep -qxF "$1=m" .config; }
summary() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$@" >> "${GITHUB_STEP_SUMMARY}"; return 0; }

echo "== Kernel & target yang dipilih OpenWrt =="
grep -E '^CONFIG_LINUX_[0-9_]+=y|^CONFIG_TARGET_(armsr|ROOTFS_PARTSIZE|KERNEL_PARTSIZE)' .config || true

# Nilai terakhir tiap simbol di seed (baris belakangan menang, sama seperti kconfig)
declare -A want
while IFS= read -r line; do
    if [[ "${line}" =~ ^(CONFIG_[A-Za-z0-9_+.-]+)=(.*)$ ]]; then
        want["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    elif [[ "${line}" =~ ^#\ (CONFIG_[A-Za-z0-9_+.-]+)\ is\ not\ set$ ]]; then
        want["${BASH_REMATCH[1]}"]="n"
    fi
done < "${seed}"

for sym in "${!want[@]}"; do
    v="${want[${sym}]}"
    if [[ "${v}" == "y" || "${v}" == "m" ]]; then
        if ! is_on "${sym}"; then
            if [[ "${sym}" == CONFIG_PACKAGE_* ]]; then dropped+=("${sym#CONFIG_PACKAGE_}"); else dropped_opt=$((dropped_opt + 1)); fi
        fi
    elif [[ "${v}" == "n" ]]; then
        is_on "${sym}" && forced+=("${sym#CONFIG_}")
    fi
done

echo "== Paket di seed yang HILANG setelah defconfig (${#dropped[@]}) =="
if [[ "${#dropped[@]}" -gt 0 ]]; then
    IFS=$'\n' sorted=($(printf '%s\n' "${dropped[@]}" | sort)); unset IFS
    n=0
    for p in "${sorted[@]}"; do
        n=$((n + 1)); [[ "${n}" -le 40 ]] && echo "::warning::Paket hilang setelah defconfig (nama berubah/tidak ada di tag ini?): ${p}"
    done
    [[ "${#sorted[@]}" -gt 40 ]] && echo "... dan $((${#sorted[@]} - 40)) lainnya (lihat ringkasan)"
fi
echo "Sub-opsi seed yang tidak muncul di .config: ${dropped_opt} (umumnya wajar: opsi hanya muncul bila paket induk aktif)"

echo "== Simbol yang diminta MATI tetapi tetap aktif (dipaksa dependency) (${#forced[@]}) =="
for p in "${forced[@]}"; do echo "::warning::Diminta mati tapi aktif karena dependency: ${p}"; done

echo "== Cek KRITIS =="
for sym in CONFIG_TARGET_armsr_armv8_DEVICE_generic CONFIG_TARGET_ROOTFS_TARGZ CONFIG_USE_APK \
           CONFIG_PACKAGE_luci-app-amlogic CONFIG_PACKAGE_btrfs-progs CONFIG_PACKAGE_parted \
           CONFIG_PACKAGE_perl CONFIG_PACKAGE_perlbase-essential CONFIG_PACKAGE_bash; do
    if is_on "${sym}"; then echo "OK   ${sym}"; else echo "::error::KRITIS hilang: ${sym}"; fail=1; fi
done
if is_on CONFIG_PACKAGE_libustream-openssl && is_on CONFIG_PACKAGE_libustream-mbedtls; then
    echo "::warning::libustream-openssl dan libustream-mbedtls aktif bersamaan (hanya satu yang biasanya dipakai)"
fi
grep -qxF 'CONFIG_LINUX_6_12=y' .config || echo "::warning::Kernel OpenWrt bukan 6.12 (disarankan sama seri dengan kernel OPHUB)"

summary "### Hasil check-config" \
        "- Paket hilang setelah defconfig: **${#dropped[@]}**" \
        "- Diminta mati tapi tetap aktif: **${#forced[@]}**" \
        "- Status kritis: **$([[ ${fail} -eq 0 ]] && echo OK || echo GAGAL)**"
if [[ "${#dropped[@]}" -gt 0 ]]; then
    summary "<details><summary>Daftar paket hilang</summary>" "" "\`$(printf '%s\n' "${dropped[@]}" | sort | tr '\n' ' ')\`" "" "</details>"
fi
rm -f "${seed}"
exit "${fail}"
