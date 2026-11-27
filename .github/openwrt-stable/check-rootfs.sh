#!/usr/bin/env bash
# MANAGED by apply-stable.sh
# Verifikasi isi rootfs.tar.gz SEBELUM packaging (menangkap masalah seperti perl/strict.pm yang hilang).
# Usage: check-rootfs.sh <rootfs.tar.gz> [folder common-files OPHUB]
set -uo pipefail
rootfs="${1:?path rootfs.tar.gz wajib}"
common="${2:-}"
fail=0
err()  { echo "::error::$*"; fail=1; }
warn() { echo "::warning::$*"; }

[[ -f "${rootfs}" ]] || { echo "::error::rootfs tidak ditemukan: ${rootfs}"; exit 1; }
size_mb=$(( $(stat -c %s "${rootfs}") / 1048576 ))
echo "rootfs: ${rootfs} (${size_mb} MiB)"
[[ "${size_mb}" -ge 10 ]] || err "Ukuran rootfs mencurigakan kecil (${size_mb} MiB)"

list="$(mktemp)"
tar -tzf "${rootfs}" > "${list}" 2>/dev/null || { echo "::error::rootfs tidak bisa dibaca (arsip rusak?)"; exit 1; }
has() { grep -Eq "$1" "${list}"; }

# 1) Identitas rootfs
rel="$(tar -xzOf "${rootfs}" --wildcards '*etc/openwrt_release' 2>/dev/null || true)"
if [[ -z "${rel}" ]]; then
    err "etc/openwrt_release tidak ada di rootfs"
else
    grep -q "DISTRIB_TARGET='armsr/armv8'" <<<"${rel}" || err "DISTRIB_TARGET bukan armsr/armv8"
    grep -q "DISTRIB_SOURCEBRANCH=" <<<"${rel}" || warn "DISTRIB_SOURCEBRANCH tidak ada (diy-core tidak berjalan?)"
    echo "$(grep -E "DISTRIB_(RELEASE|SOURCEBRANCH)" <<<"${rel}" | tr '\n' ' ')"
fi
has '(^|/)lib/apk/db/installed$' || warn "Database apk tidak ditemukan (rootfs bukan berbasis apk?)"

# 2) Paket yang dibutuhkan script OPHUB
has '(^|/)usr/lib/lua/luci|(^|/)usr/share/luci' || err "LuCI tidak terpasang"
has 'amlogic' || err "luci-app-amlogic tidak terpasang"

need_perl=1
if [[ -n "${common}" && -d "${common}" ]]; then
    if grep -rIlE '^#!.*perl' "${common}" >/dev/null 2>&1; then need_perl=1; else need_perl=0; fi
fi
if [[ "${need_perl}" -eq 1 ]]; then
    has '(^|/)usr/bin/perl$' || err "perl tidak ada (dibutuhkan /usr/bin/cpustat OPHUB)"
    has '(^|/)usr/lib/perl5/[0-9.]+/strict\.pm$' || err "perl strict.pm tidak ada -> cpustat akan error (tambahkan perlbase-essential)"
fi

# 3) Alat yang dipakai skrip install/update OPHUB (peringatan saja)
for t in bash parted btrfs mkfs.btrfs losetup blkid lsblk uuidgen pigz; do
    has "(^|/)${t}$" || warn "Alat '${t}' tidak ditemukan di rootfs"
done

rm -f "${list}"
[[ "${fail}" -eq 0 ]] && echo "check-rootfs: OK" || echo "check-rootfs: GAGAL"
exit "${fail}"
