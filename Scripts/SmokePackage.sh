#!/usr/bin/env bash
set -euo pipefail

bundle="${1:?Missing source bundle}"
zip="${2:?Missing output ZIP path}"
scripts_dir="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

ditto -c -k --sequesterRsrc --keepParent "$bundle" "$zip"
ditto -x -k "$zip" "$scratch"
unpacked="$scratch/TangoDisplay.app"
bash "$scripts_dir/VerifyBundle.sh" "$unpacked"
"$unpacked/Contents/MacOS/TangoDisplay" --bundle-smoke-test

destination="$scratch/Installed.app"
bash "$scripts_dir/InstallBundle.sh" "$unpacked" "$destination"
mkdir "$scratch/bin"
cat > "$scratch/bin/mv" <<'SH'
#!/bin/bash
if [[ "$1" == */.tangodisplay-install.*/TangoDisplay.app ]]; then exit 1; fi
exec /bin/mv "$@"
SH
chmod +x "$scratch/bin/mv"
if PATH="$scratch/bin:$PATH" bash "$scripts_dir/InstallBundle.sh" "$unpacked" "$destination"; then
  echo "Expected replacement to fail" >&2
  exit 1
fi
bash "$scripts_dir/VerifyBundle.sh" "$destination"
"$destination/Contents/MacOS/TangoDisplay" --bundle-smoke-test

damaged="$scratch/Damaged.app"
ditto "$unpacked" "$damaged"
printf '\n' >> "$damaged/Contents/Resources/RemoteUI/index.html"
if bash "$scripts_dir/InstallBundle.sh" "$damaged" "$destination"; then
  echo "Expected replacement to reject an invalid signature" >&2
  exit 1
fi
bash "$scripts_dir/VerifyBundle.sh" "$destination"

cat > "$scratch/bin/ditto" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$scratch/bin/ditto"
if PATH="$scratch/bin:$PATH" bash "$scripts_dir/InstallBundle.sh" "$unpacked" "$destination"; then
  echo "Expected staging copy to fail" >&2
  exit 1
fi
bash "$scripts_dir/VerifyBundle.sh" "$destination"
