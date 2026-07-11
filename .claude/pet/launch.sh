#!/bin/zsh

set -euo pipefail

pet_dir="${0:A:h}"
pet_script="$pet_dir/CodexPet.js"
pet_image="$pet_dir/codex-pet.png"
service_label="com.paisatrack.claude-codex-pet"
service_target="gui/$UID/$service_label"

if launchctl print "$service_target" >/dev/null 2>&1; then
  launchctl remove "$service_label"
  echo "Floating Codex pet hidden."
  exit 0
fi

launchctl submit -l "$service_label" -- \
  /usr/bin/env CODEX_PET_IMAGE="$pet_image" \
  /usr/bin/osascript -l JavaScript "$pet_script"

sleep 1
if ! launchctl print "$service_target" >/dev/null 2>&1; then
  echo "Could not launch the floating Codex pet." >&2
  exit 1
fi

echo "Floating Codex pet launched."
