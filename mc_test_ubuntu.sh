#!/usr/bin/env bash

set -euo pipefail

DEBUG_LOG="${MC_DEBUG_LOG:-mc_test_ubuntu_debug.log}"
ENCRYPTION_PASSWORD="${MC_PASSWORD:-12345}"
PASSWORD_FIELD_TAB_COUNT="${MC_PASSWORD_FIELD_TAB_COUNT:-1}"
NIX_ATTR="${MC_NIX_ATTR:-nixpkgs#mcpelauncher-ui-qt}"

WAIT_LAUNCH="${MC_WAIT_LAUNCH:-15}"
WAIT_AFTER_POPUP_CLOSE="${MC_WAIT_AFTER_POPUP_CLOSE:-2}"
WAIT_AFTER_PASSWORD="${MC_WAIT_AFTER_PASSWORD:-2}"
WAIT_AFTER_LAUNCHER_PLAY="${MC_WAIT_AFTER_LAUNCHER_PLAY:-12}"
WAIT_FOR_LAUNCHER_WINDOW="${MC_WAIT_FOR_LAUNCHER_WINDOW:-60}"
WAIT_FOR_CLIENT_WINDOW="${MC_WAIT_FOR_CLIENT_WINDOW:-60}"
WAIT_AFTER_CLIENT_FRONT="${MC_WAIT_AFTER_CLIENT_FRONT:-2}"
WAIT_AFTER_PLAY="${MC_WAIT_AFTER_PLAY:-5}"
WAIT_AFTER_SERVER_SELECT="${MC_WAIT_AFTER_SERVER_SELECT:-3}"
WAIT_BETWEEN_NAV_KEYS="${MC_WAIT_BETWEEN_NAV_KEYS:-0.15}"

WIN_X="${MC_WIN_X:-50}"
WIN_Y="${MC_WIN_Y:-50}"
WIN_W="${MC_WIN_W:-1280}"
WIN_H="${MC_WIN_H:-720}"

POPUP_CLOSE_OFFSET_X="${MC_POPUP_CLOSE_OFFSET_X:-20}"
POPUP_CLOSE_OFFSET_Y="${MC_POPUP_CLOSE_OFFSET_Y:-20}"
LAUNCHER_PLAY_OFFSET_Y="${MC_LAUNCHER_PLAY_OFFSET_Y:-55}"

SERVER_NAV_RIGHT_COUNT="${MC_SERVER_NAV_RIGHT_COUNT:-2}"
SERVER_NAV_DOWN_COUNT="${MC_SERVER_NAV_DOWN_COUNT:-20}"

LAUNCHER_PROCESS_PATTERNS=(
  "mcpelauncher-ui-qt"
  "Minecraft_Bedrock_Launcher"
)

CLIENT_PROCESS_PATTERNS=(
  "mcpelauncher-client-arm64-v8a"
  "mcpelauncher-client32"
  "mcpelauncher-client"
)

LAUNCHER_WINDOW_CLASS_PATTERNS=(
  "mcpelauncher-ui-qt"
  "io\\.mrarm\\.mcpelauncher"
)

LAUNCHER_WINDOW_NAME_PATTERNS=(
  "Minecraft Bedrock Launcher"
  "MCPelauncher"
  "mcpelauncher"
)

CLIENT_WINDOW_CLASS_PATTERNS=(
  "mcpelauncher-client"
)

CLIENT_WINDOW_NAME_PATTERNS=(
  "^Minecraft$"
  "^Minecraft Preview$"
)

POPUP_WINDOW_NAME_PATTERNS=(
  "Software Update"
)

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

warn_wayland() {
  if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    echo "Warning: xdotool automation is most reliable on X11/XWayland sessions." >&2
  fi
}

log_debug_snapshot() {
  {
    echo
    echo "==== $(date '+%Y-%m-%d %H:%M:%S') ===="
    echo "-- active window --"
    xdotool getactivewindow getwindowname 2>/dev/null || true
    echo "-- launcher windows --"
    xdotool search --onlyvisible --name "Minecraft|mcpelauncher" 2>/dev/null || true
    echo "-- ps filtered --"
    pgrep -af 'minecraft|mcpelauncher|msa' || true
  } >>"$DEBUG_LOG" 2>&1
}

resolve_launch_cmd() {
  if [[ -n "${MC_LAUNCH_CMD:-}" ]]; then
    printf '%s\n' "$MC_LAUNCH_CMD"
    return 0
  fi

  if command -v mcpelauncher-ui-qt >/dev/null 2>&1; then
    printf '%s\n' "mcpelauncher-ui-qt"
    return 0
  fi

  if command -v nix >/dev/null 2>&1; then
    printf '%s\n' "nix shell ${NIX_ATTR} -c mcpelauncher-ui-qt"
    return 0
  fi

  return 1
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
    done < <(pgrep -f "$pattern" 2>/dev/null || true)
  done

  return 1
}

find_launcher_window() {
  search_first_window_by_process_patterns "${LAUNCHER_PROCESS_PATTERNS[@]}" ||
    search_first_window_by_class "${LAUNCHER_WINDOW_CLASS_PATTERNS[@]}" ||
    search_first_window_by_name "${LAUNCHER_WINDOW_NAME_PATTERNS[@]}"
}

find_client_window() {
  search_first_window_by_process_patterns "${CLIENT_PROCESS_PATTERNS[@]}" ||
    search_first_window_by_class "${CLIENT_WINDOW_CLASS_PATTERNS[@]}" ||
    search_first_window_by_name "${CLIENT_WINDOW_NAME_PATTERNS[@]}"
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
  sleep 0.4
}

resize_window() {
  local window_id="$1"

  xdotool windowsize "$window_id" "$WIN_W" "$WIN_H" >/dev/null 2>&1 || true
  xdotool windowmove "$window_id" "$WIN_X" "$WIN_Y" >/dev/null 2>&1 || true
}

window_geometry() {
  local window_id="$1"

  xdotool getwindowgeometry --shell "$window_id"
}

click_window_relative() {
  local window_id="$1"
  local rel_x="$2"
  local rel_y="$3"

  activate_window "$window_id"
  xdotool mousemove --sync --window "$window_id" "$rel_x" "$rel_y"
  sleep 0.1
  xdotool click 1
}

close_update_popup_if_present() {
  local popup_id=""

  if ! popup_id="$(search_first_window_by_name "${POPUP_WINDOW_NAME_PATTERNS[@]}")"; then
    return 0
  fi

  echo "Closing Software Update popup..."
  eval "$(window_geometry "$popup_id")"
  click_window_relative "$popup_id" "$((WIDTH - POPUP_CLOSE_OFFSET_X))" "$POPUP_CLOSE_OFFSET_Y"
  sleep "$WAIT_AFTER_POPUP_CLOSE"
}

fill_password_if_configured() {
  local launcher_id="$1"
  local attempt=0

  if [[ -z "$ENCRYPTION_PASSWORD" ]]; then
    return 0
  fi

  echo "Entering encryption password..."
  activate_window "$launcher_id"

  while (( attempt < PASSWORD_FIELD_TAB_COUNT )); do
    xdotool key --clearmodifiers Tab
    sleep 0.2
    ((attempt += 1))
  done

  xdotool type --delay 25 --clearmodifiers "$ENCRYPTION_PASSWORD"
  sleep 0.2
  xdotool key --clearmodifiers Return
  sleep "$WAIT_AFTER_PASSWORD"
}

click_launcher_play() {
  local launcher_id="$1"

  echo "Clicking launcher Play..."
  eval "$(window_geometry "$launcher_id")"
  click_window_relative "$launcher_id" "$((WIDTH / 2))" "$((HEIGHT - LAUNCHER_PLAY_OFFSET_Y))"
}

press_key_repeatedly() {
  local key_name="$1"
  local press_count="$2"
  local attempt=0

  while (( attempt < press_count )); do
    xdotool key --clearmodifiers "$key_name"
    sleep "$WAIT_BETWEEN_NAV_KEYS"
    ((attempt += 1))
  done
}

press_in_game_return() {
  xdotool key --clearmodifiers Return
  sleep 0.5
  xdotool key --clearmodifiers KP_Enter
  sleep 0.5
  xdotool key --clearmodifiers Return
}

start_launcher() {
  local launch_cmd

  launch_cmd="$(resolve_launch_cmd)" || die "Could not find mcpelauncher-ui-qt. Set MC_LAUNCH_CMD or install it in PATH/Nix."
  echo "Starting MCPelauncher with: $launch_cmd"
  nohup bash -lc "$launch_cmd" >/dev/null 2>&1 &
}

require_command bash
require_command nohup
require_command pgrep
require_command xdotool

[[ -n "${DISPLAY:-}" ]] || die "DISPLAY is not set. xdotool needs an X11/XWayland session."
warn_wayland

start_launcher
sleep "$WAIT_LAUNCH"

launcher_window_id="$(wait_for_window find_launcher_window "$WAIT_FOR_LAUNCHER_WINDOW")" ||
  die "Timed out waiting for the launcher window."

log_debug_snapshot
close_update_popup_if_present

echo "Resizing launcher window..."
activate_window "$launcher_window_id"
resize_window "$launcher_window_id"
sleep 1

fill_password_if_configured "$launcher_window_id"

launcher_window_id="$(find_launcher_window || true)"
[[ -n "$launcher_window_id" ]] || die "Launcher window disappeared before Play could be clicked."

click_launcher_play "$launcher_window_id"
sleep "$WAIT_AFTER_LAUNCHER_PLAY"

echo "Waiting for Minecraft client window..."
log_debug_snapshot
client_window_id="$(wait_for_window find_client_window "$WAIT_FOR_CLIENT_WINDOW")" ||
  die "Timed out waiting for the Minecraft client window."

activate_window "$client_window_id"
sleep "$WAIT_AFTER_CLIENT_FRONT"
log_debug_snapshot

echo "Pressing Return for in-game Play..."
press_in_game_return
sleep 1
log_debug_snapshot

sleep "$WAIT_AFTER_PLAY"

echo "Selecting server with keyboard..."
activate_window "$client_window_id"
sleep "$WAIT_AFTER_CLIENT_FRONT"
press_key_repeatedly Right "$SERVER_NAV_RIGHT_COUNT"
xdotool key --clearmodifiers Return
sleep "$WAIT_BETWEEN_NAV_KEYS"
press_key_repeatedly Down "$SERVER_NAV_DOWN_COUNT"
sleep "$WAIT_BETWEEN_NAV_KEYS"
xdotool key --clearmodifiers Return
sleep "$WAIT_BETWEEN_NAV_KEYS"
press_key_repeatedly Right "$SERVER_NAV_RIGHT_COUNT"
sleep "$WAIT_BETWEEN_NAV_KEYS"
xdotool key --clearmodifiers Return

sleep "$WAIT_AFTER_SERVER_SELECT"

echo "Done."
