#!/bin/bash
set -euo pipefail
umask 077
experiment_dir="$(cd "$(dirname "$0")" && pwd)"
ios_source="${1:?Provide the pinned main checkout}"
build_dir="${2:?Provide a new build directory}"
source_revision="06b1e92b0ac6ce00a674c577ab05c00ebc41d378"
if [[ "$(git -C "$ios_source" rev-parse HEAD)" != "$source_revision" ]] ||
   ! git -C "$ios_source" diff --quiet HEAD -- ios/DounaiCheckin; then
  echo 'The iOS source must match the documented, unmodified pinned revision.' >&2
  exit 2
fi
mkdir "$build_dir"
app_dir="$build_dir/SimulatorProbe.app"
mkdir "$app_dir"
cp "$experiment_dir/Info.plist" "$app_dir/Info.plist"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
sources=()
for file in CheckInPolicy DiagnosticLog CaptchaSolver CheckInClient AppSettings KeychainStore BarkClient EmailClient; do
  sources+=("$ios_source/ios/DounaiCheckin/$file.swift")
done
printf 'Compiling pinned iOS core: %s\n' "$source_revision"
SDKROOT="$sdk" xcrun swiftc -swift-version 5 -parse-as-library -sdk "$sdk" \
  -target "$(uname -m)-apple-ios18.0-simulator" \
  "${sources[@]}" "$experiment_dir/ProbeApp.swift" "$experiment_dir/ProbeFixtures.swift" "$experiment_dir/CaptchaInspection.swift" \
  -o "$app_dir/SimulatorProbe"
codesign --force --sign - "$app_dir" >/dev/null 2>&1
