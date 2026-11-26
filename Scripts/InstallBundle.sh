#!/usr/bin/env bash
set -euo pipefail

source_bundle="${1:?Missing source bundle}"
destination="${2:?Missing destination bundle}"
scripts_dir="$(cd "$(dirname "$0")" && pwd)"
parent="$(dirname "$destination")"
mkdir -p "$parent"
staging="$(mktemp -d "$parent/.tangodisplay-install.XXXXXX")"
candidate="$staging/TangoDisplay.app"
previous="$staging/Previous.app"

cleanup() {
  status=$?
  if [[ -e "$previous" || -L "$previous" ]]; then
    if [[ ! -e "$destination" && ! -L "$destination" ]]; then
      if ! mv "$previous" "$destination"; then
        echo "Could not restore the previous bundle. It is at $previous" >&2
        exit 1
      fi
    elif [[ -e "$candidate" ]]; then
      echo "Could not restore the previous bundle. It is at $previous" >&2
      exit 1
    fi
  fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Copy and verify on the destination volume before moving the working installation.
ditto "$source_bundle" "$candidate"
bash "$scripts_dir/VerifyBundle.sh" "$candidate"
if [[ -e "$destination" || -L "$destination" ]]; then
  mv "$destination" "$previous"
fi
mv "$candidate" "$destination"
