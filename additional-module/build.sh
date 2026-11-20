#!/usr/bin/env bash
# Build extra out-of-tree modules against the kernel just compiled by ophub.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES="${ADDITIONAL_MODULES:-}"
if [[ -z "${MODULES// /}" ]]; then echo "No additional module selected, skip."; exit 0; fi

OUT="${PACKAGED_OUTPUTPATH:?PACKAGED_OUTPUTPATH is empty}"
IMAGE="ophub/armbian-${DOCKER_IMAGE:?}:arm64"
WORK=/builder/additional-module

# Kernel version taken from the compiled tarball name (no hardcode)
tarball="$(ls -1 "${OUT}"/boot-*.tar.gz 2>/dev/null | head -n1 || true)"
[[ -n "${tarball}" ]] || tarball="$(ls -1 "${OUT}"/*.tar.gz | head -n1)"
VER="$(basename "${tarball}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
echo "Kernel version: ${VER}"

# Locate the kernel build tree left by the compile step (needs delete_source=false)
symvers="$(sudo find /builder -name Module.symvers -not -path "${WORK}/*" 2>/dev/null | head -n1 || true)"
if [[ -z "${symvers}" ]]; then
  echo "ERROR: kernel build tree not found in /builder"; sudo ls -la /builder; exit 1
fi
KDIR="$(dirname "${symvers}")"
echo "Kernel tree: ${KDIR}"
[[ -f "${KDIR}/Makefile" ]] || { echo "ERROR: no Makefile in ${KDIR}"; exit 1; }

MAKE_FLAGS=""
grep -q '^CONFIG_CC_IS_CLANG=y' "${KDIR}/.config" 2>/dev/null && MAKE_FLAGS="LLVM=1"
grep -m1 '^CONFIG_CC_VERSION_TEXT' "${KDIR}/.config" || true

sudo rm -rf "${WORK}"; sudo mkdir -p "${WORK}/stage"
sudo chown -R "$(id -u):$(id -g)" "${WORK}"

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

for name in ${MODULES}; do
  line="$(grep -E "^${name}[[:space:]]*\|" "${HERE}/modules.conf")" || { echo "Unknown module: ${name}"; exit 1; }
  IFS='|' read -r _ url ref extra _ <<< "${line}"
  url="$(trim "${url}")"; ref="$(trim "${ref}")"; extra="$(trim "${extra}")"
  src="${WORK}/${name}"
  echo "::group::Build ${name}"
  git clone --depth 1 --branch "${ref}" "${url}" "${src}"
  # Apply local patches (additional-module/patches/<name>/*.patch), fail loudly if any does not apply
  if compgen -G "${HERE}/patches/${name}/*.patch" > /dev/null; then
    for p in "${HERE}/patches/${name}"/*.patch; do
      echo "Applying ${p##*/}"
      patch -d "${src}" -p1 --forward < "${p}" || { echo "ERROR: patch ${p##*/} failed"; exit 1; }
    done
  fi
  cmd="${extra//@KDIR@/${KDIR}}"; cmd="${cmd//@SRC@/${src}}"
  docker run --rm -v /builder:/builder -w "${src}" "${IMAGE}" \
    bash -c "${cmd} ${MAKE_FLAGS}"
  mapfile -t kos < <(find "${src}" -name '*.ko' -not -path '*/kernel/*')
  (( ${#kos[@]} )) || { echo "ERROR: no .ko produced by ${name}"; exit 1; }
  cp -v "${kos[@]}" "${WORK}/stage/"
  echo "::endgroup::"
done

sudo strip --strip-debug "${WORK}"/stage/*.ko || true
for ko in "${WORK}"/stage/*.ko; do echo "${ko##*/}: $(modinfo -F vermagic "${ko}")"; done
command -v zip >/dev/null || sudo apt-get install -y zip
ZIP="additional-module-${VER}.zip"
(cd "${WORK}/stage" && sudo zip -9 -j -q "${OUT}/${ZIP}" ./*.ko)
echo "Created ${OUT}/${ZIP}"
