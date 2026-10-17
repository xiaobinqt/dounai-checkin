#!/bin/bash
set -euo pipefail
umask 077

# Usage: bash run.sh /path/to/pinned-main-checkout /path/to/new-output-directory
experiment_dir="$(cd "$(dirname "$0")" && pwd)"
ios_source="${1:?Provide the pinned main checkout}"
output_dir="${2:?Provide a new output directory}"
mode="${DOUNAI_PROBE_MODE:-smoke}"
source_revision="06b1e92b0ac6ce00a674c577ab05c00ebc41d378"
bundle_id="com.dounai.checkin.simulatorprobe"

if [[ "$mode" != smoke && "$mode" != checkin && "$mode" != inspect ]]; then
  echo 'Unsupported probe mode.' >&2
  exit 2
fi
if [[ "$mode" != smoke && ( "${DOUNAI_CONFIRM_CHECKIN:-}" != yes || -z "${DOUNAI_URL:-}" || -z "${DOUNAI_COOKIE:-}" ) ]]; then
  echo 'Real check-in requires confirmation, DOUNAI_URL and DOUNAI_COOKIE.' >&2
  exit 2
fi
if [[ "$(git -C "$ios_source" rev-parse HEAD)" != "$source_revision" ]] ||
   ! git -C "$ios_source" diff --quiet HEAD -- ios/DounaiCheckin; then
  echo 'The iOS source must match the documented, unmodified pinned revision.' >&2
  exit 2
fi
# Refuse to reuse a directory: stale result files must never count as a new success.
mkdir "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dounai-simulator.XXXXXX")"
simulator_id=""
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  if [[ -n "$simulator_id" ]]; then
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  fi
  # Keep only generated binaries here for inspection; never credentials or app data.
  printf 'Probe build directory: %s\n' "$work_dir"
}
trap cleanup EXIT

app_dir="${DOUNAI_PROBE_APP:-}"
if [[ -z "$app_dir" ]]; then
  bash "$experiment_dir/build.sh" "$ios_source" "$work_dir/build"
  app_dir="$work_dir/build/SimulatorProbe.app"
fi
test -f "$app_dir/SimulatorProbe"

# Create a private simulator rather than erasing or shutting down the user's devices.
device="$(xcrun simctl list devices available --json | jq -r '
  [.devices | to_entries[] | select(.key | contains(".iOS-")) |
   .key as $runtime | .value[] | select(.name | startswith("iPhone")) |
   [$runtime, .deviceTypeIdentifier]] | first | @tsv')"
if [[ -z "$device" ]]; then
  echo 'No installed iPhone simulator runtime found.' >&2
  exit 1
fi
IFS=$'\t' read -r runtime device_type <<< "$device"
simulator_id="$(xcrun simctl create "Dounai probe $(date +%s)-$$" "$device_type" "$runtime")"
printf 'Booting simulator: %s\n' "$runtime"
if ! perl -e 'alarm 30; exec @ARGV or die "Unable to start command\n"' xcrun simctl boot "$simulator_id"; then
  echo '::error::Simulator boot command failed or timed out (30 seconds).'
  exit 1
fi
if ! perl -e 'alarm 600; exec @ARGV or die "Unable to start command\n"' xcrun simctl bootstatus "$simulator_id" -b; then
  echo '::error::Simulator did not finish booting within 600 seconds.'
  exit 1
fi
echo '::notice::Simulator boot completed; installing experiment application.'
xcrun simctl install "$simulator_id" "$app_dir"
container="$(xcrun simctl get_app_container "$simulator_id" "$bundle_id" data)"

# Secrets are environment variables, not argv. Suppress OS launch output, which is
# not a vetted diagnostic channel. Never upload the simulator container or console.
SIMCTL_CHILD_DOUNAI_PROBE_MODE="$mode" \
SIMCTL_CHILD_DOUNAI_CONFIRM_CHECKIN="${DOUNAI_CONFIRM_CHECKIN:-}" \
SIMCTL_CHILD_DOUNAI_URL="${DOUNAI_URL:-}" \
SIMCTL_CHILD_DOUNAI_COOKIE="${DOUNAI_COOKIE:-}" \
SIMCTL_CHILD_DOUNAI_USER_AGENT="${DOUNAI_USER_AGENT:-}" \
  perl -e 'alarm 120; exec @ARGV or die "Unable to start command\n"' \
    xcrun simctl launch "$simulator_id" "$bundle_id" >/dev/null 2>&1

printf 'Application launched; waiting for %s result.\n' "$mode"
for ((attempt=0; attempt<120; attempt++)); do
  if [[ -f "$container/Documents/result.json" ]]; then
    cp "$container/Documents/result.json" "$output_dir/result.json"
    cp "$container/Documents/diagnostics.log" "$output_dir/diagnostics.log"
    if [[ -f "$container/Documents/cookie" ]]; then
      cp "$container/Documents/cookie" "$output_dir/cookie"
      chmod 600 "$output_dir/cookie"
    fi
    jq . "$output_dir/result.json"
    # Only fixed events/counts/categories from the shared DiagnosticLog are shown.
    sed -n '1,180p' "$output_dir/diagnostics.log"
    jq -e '.status == "passed" or .status == "inspected"' "$output_dir/result.json" >/dev/null
    exit $?
  fi
  sleep 1
done
echo 'Application did not produce a result within 120 seconds; no automatic resubmission.' >&2
exit 1
