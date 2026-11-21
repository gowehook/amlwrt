#!/usr/bin/env bash
# Dipanggil dari dalam folder openwrt/ SETELAH make defconfig.
# Usage: check-config.sh <path-seed-config>
seed="${1:?path seed config wajib}"
fail=0

echo "== Kernel yang dipilih OpenWrt =="
grep -E '^CONFIG_LINUX_[0-9_]+=y' .config || true

echo "== Cek simbol dari seed yang HILANG setelah defconfig =="
while read -r sym; do
    grep -q "^${sym}=" .config || echo "::warning::Hilang setelah defconfig (nama berubah/dihapus di 25.12?): ${sym}"
done < <(grep -E '^CONFIG_[A-Za-z0-9_+.-]+=(y|m)' "${seed}" | cut -d= -f1)

echo "== Cek KRITIS =="
for sym in CONFIG_TARGET_armsr_armv8_DEVICE_generic CONFIG_TARGET_ROOTFS_TARGZ \
           CONFIG_PACKAGE_luci-app-amlogic CONFIG_PACKAGE_btrfs-progs CONFIG_PACKAGE_parted; do
    if grep -q "^${sym}=y" .config; then echo "OK   ${sym}"; else echo "::error::KRITIS hilang: ${sym}"; fail=1; fi
done
grep -q '^CONFIG_LINUX_6_12=y' .config || echo "::warning::Kernel OpenWrt bukan 6.12 (disarankan sama dengan kernel OPHUB 6.12.y)"
exit ${fail}
