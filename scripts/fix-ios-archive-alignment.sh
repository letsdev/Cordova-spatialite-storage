#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
native_dir="${repo_root}/src/ios/native"

if ! command -v lipo >/dev/null 2>&1; then
  echo "lipo is required but not available in PATH" >&2
  exit 1
fi

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/ios-archive-align.XXXXXX")"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

alignment_for_arch() {
  case "$1" in
    arm64|arm64e|x86_64)
      echo 8
      ;;
    *)
      echo 4
      ;;
  esac
}

for lib in "${native_dir}"/*.a; do
  rel_lib="${lib#${repo_root}/}"
  archs_str="$(lipo -archs "${lib}")"
  # shellcheck disable=SC2206
  archs=(${archs_str})
  if [ "${#archs[@]}" -eq 0 ]; then
    echo "Skipping ${rel_lib}: no architectures found" >&2
    continue
  fi

  lib_tmp="${tmpdir}/$(basename "${lib}")"
  mkdir -p "${lib_tmp}.parts"

  create_args=()
  for arch in "${archs[@]}"; do
    part="${lib_tmp}.parts/${arch}.a"
    lipo "${lib}" -thin "${arch}" -output "${part}"
    create_args+=("-arch" "${arch}" "${part}")
    create_args+=("-segalign" "${arch}" "$(alignment_for_arch "${arch}")")
  done

  rebuilt="${lib_tmp}.rebuilt.a"
  lipo -create "${create_args[@]}" -output "${rebuilt}"
  mv "${rebuilt}" "${lib}"
  echo "Rebuilt ${rel_lib}"
done
