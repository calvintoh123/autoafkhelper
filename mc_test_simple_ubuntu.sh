#!/usr/bin/env bash
set -euo pipefail

WAIT_FOR_LAUNCHER_WINDOW="${MC_WAIT_FOR_LAUNCHER_WINDOW:-60}"

LAUNCHER_PROCESS_PATTERNS=(
  "mcpelauncher-ui-qt"
  "Minecraft_Bedrock_Launcher"
  "flatpak run io\\.mrarm\\.mcpelauncher"
  "io\\.mrarm\\.mcpelauncher"
  "mcpelauncher"
)

LAUNCHER_WINDOW_CLASS_PATTERNS=(
  "mcpelauncher-ui-qt"
  "io\\.mrarm\\.mcpelauncher"
  "mcpelauncher"
  "minecraft"
)

LAUNCHER_WINDOW_NAME_PATTERNS=(
  "Minecraft Bedrock Launcher"
  "MCPelauncher"
  "mcpelauncher"
  "Minecraft"
)

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: required command not found: $1" >&2
    exit 1
  }
}

die() {
  echo "Error: $*" >&2
  exit 1
}

press_key() {
  local key="$1"
  local count="${2:-1}"
  local i

  for ((i = 0; i < count; i++)); do
    xdotool key --clearmodifiers "$key"
  done
}

search_first_window_by_name() {
  local pattern
  local ids

  for pattern in "$@"; do
    ids="$(xdotool search --onlyvisible --name "$pattern" 2>/dev/null || true)"
    if [[ -n "$ids" ]]; then
      printf '%s\n' "$ids" | tail -n 1
      return 0
    fi
  done

  return 1
}

search_first_window_by_class() {
  local pattern
  local ids

  for pattern in "$@"; do
    ids="$(xdotool search --onlyvisible --class "$pattern" 2>/dev/null || true)"
    if [[ -n "$ids" ]]; then
      printf '%s\n' "$ids" | tail -n 1
      return 0
    fi
  done

  return 1
}

search_first_window_by_process_patterns() {
  local pattern
  local pid
  local ids

  for pattern in "$@"; do
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      ids="$(xdotool search --onlyvisible --pid "$pid" 2>/dev/null || true)"
      if [[ -n "$ids" ]]; then
        printf '%s\n' "$ids" | tail -n 1
        return 0
      fi
    done < <(pgrep -f "$pattern" 2>/dev/null | sort -nr || true)
  done

  return 1
}

find_launcher_window() {
  search_first_window_by_process_patterns "${LAUNCHER_PROCESS_PATTERNS[@]}" ||
    search_first_window_by_class "${LAUNCHER_WINDOW_CLASS_PATTERNS[@]}" ||
    search_first_window_by_name "${LAUNCHER_WINDOW_NAME_PATTERNS[@]}"
}

wait_for_window() {
  local finder_name="$1"
  local timeout="$2"
  local elapsed=0
  local window_id=""

  while (( elapsed < timeout )); do
    if window_id="$("$finder_name")"; then
      printf '%s\n' "$window_id"
      return 0
    fi

    sleep 1
    ((elapsed += 1))
  done

  return 1
}

activate_window() {
  local window_id="$1"

  xdotool windowactivate --sync "$window_id" >/dev/null 2>&1 || true
  xdotool windowfocus --sync "$window_id" >/dev/null 2>&1 || true
  sleep 0.4
}

require_command pgrep
require_command xdotool

[[ -n "${DISPLAY:-}" ]] || die "DISPLAY is not set. xdotool needs an X11/XWayland session."

launcher_window_id="$(wait_for_window find_launcher_window "$WAIT_FOR_LAUNCHER_WINDOW")" ||
  die "Timed out waiting for an existing Minecraft window."

activate_window "$launcher_window_id"

press_key Up
press_key Return
sleep 5
press_key Down 20
press_key Right
press_key Return
