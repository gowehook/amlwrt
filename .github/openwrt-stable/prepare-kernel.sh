#!/usr/bin/env bash
# MANAGED by apply-stable.sh
# Menata hasil compile kernel ke struktur yang dibaca remake OPHUB:
#   <kernel_root>/<tags>/<versi>/{boot-*,dtb-*,modules-*,header-*}.tar.gz
# Usage : prepare-kernel.sh <input_dir> <kernel_root> [tags=stable]
# Output: stdout = daftar versi dipisah underscore (mis. 6.12.118_6.18.5); log ke stderr.
set -euo pipefail
in="${1:?input dir wajib}"
root="${2:?kernel root wajib}"
tags="${3:-stable}"
dest="${root}/${tags}"
log() { echo "[prepare-kernel] $*" >&2; }
fail() { echo "::error::$*" >&2; exit 1; }

[[ -d "${in}" ]] || fail "Folder input kernel tidak ada: ${in}"
mkdir -p "${dest}"
shopt -s nullglob globstar

# (a) Arsip per-versi: <versi>.tar.gz yang berisi folder <versi>/
found=0
for f in "${in}"/**/[0-9]*.[0-9]*.[0-9]*.tar.gz; do
    log "ekstrak ${f##*/}"
    tar -mxzf "${f}" -C "${dest}" || fail "Gagal mengekstrak ${f}"
    found=1
done

# (b) File lepas: boot-<versi><sign>.tar.gz + pasangannya
for f in "${in}"/**/boot-*.tar.gz; do
    base="${f##*/}"; rest="${base#boot-}"; rest="${rest%.tar.gz}"   # 6.12.118-ophub
    ver="${rest%%-*}"
    [[ "${ver}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    [[ -d "${dest}/${ver}" ]] && continue
    log "kumpulkan file lepas untuk ${ver}"
    mkdir -p "${dest}/${ver}"
    srcdir="$(dirname "${f}")"
    for g in "${srcdir}"/*"${rest}"*.tar.gz; do cp -f "${g}" "${dest}/${ver}/"; done
    found=1
done
[[ "${found}" -eq 1 ]] || fail "Tidak ada arsip kernel yang dikenali di ${in}"

# Validasi tiap versi
versions=()
for d in "${dest}"/*/; do
    v="$(basename "${d}")"
    [[ "${v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    boot=("${d}"boot-"${v}"*.tar.gz)
    mods=("${d}"modules-"${v}"*.tar.gz)
    dtbs=("${d}"dtb-*-"${v}"*.tar.gz)
    [[ "${#boot[@]}" -ge 1 ]] || fail "[${v}] boot-*.tar.gz tidak ada"
    [[ "${#mods[@]}" -ge 1 ]] || fail "[${v}] modules-*.tar.gz tidak ada"
    [[ "${#dtbs[@]}" -ge 1 ]] || fail "[${v}] dtb-*-*.tar.gz tidak ada"
    log "OK ${v}: $(basename "${boot[0]}"), ${#dtbs[@]} dtb"
    versions+=("${v}")
done
[[ "${#versions[@]}" -ge 1 ]] || fail "Tidak ada versi kernel valid di ${dest}"

printf '%s\n' "${versions[@]}" | sort -V | paste -sd_ -
