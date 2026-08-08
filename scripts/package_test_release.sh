#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
release_version=$(tr -d '[:space:]' < "$repo_root/VERSION")
base_version=${release_version%%-*}
fap_source="$repo_root/firmware/dist/bridgepad.fap"
apk_source="$repo_root/mobile/build/app/outputs/flutter-apk/app-debug.apk"
release_dir="$repo_root/release"
fap_name="bridgepad-$release_version.fap"
apk_name="bridgepad-$release_version-android-debug.apk"
checksums_name="SHA256SUMS-$release_version.txt"

if ! grep -q "^version: $base_version+" "$repo_root/mobile/pubspec.yaml"; then
    echo "mobile/pubspec.yaml does not match BridgePad $base_version" >&2
    exit 1
fi

if ! grep -q "fap_version=\"$base_version\"" "$repo_root/firmware/application.fam"; then
    echo "firmware/application.fam does not match BridgePad $base_version" >&2
    exit 1
fi

if [ ! -f "$fap_source" ] || [ ! -f "$apk_source" ]; then
    echo "Build both firmware and Android before packaging BridgePad $release_version" >&2
    exit 1
fi

mkdir -p "$release_dir"
cp "$fap_source" "$release_dir/$fap_name"
cp "$apk_source" "$release_dir/$apk_name"
(
    cd "$release_dir"
    shasum -a 256 "$fap_name" "$apk_name" > "$checksums_name"
)

printf '%s\n' \
    "$release_dir/$fap_name" \
    "$release_dir/$apk_name" \
    "$release_dir/$checksums_name"
