#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
set -euo pipefail

DEBUG_LOG="${MC_DEBUG_LOG:-mc_test_ubuntu_debug.log}"
ENCRYPTION_PASSWORD="${MC_PASSWORD:-12345}"
PASSWORD_METHOD="${MC_PASSWORD_METHOD:-click}"
PASSWORD_FIELD_TAB_COUNT="${MC_PASSWORD_FIELD_TAB_COUNT:-2}"
PASSWORD_CONTINUE_TAB_COUNT="${MC_PASSWORD_CONTINUE_TAB_COUNT:-2}"
PASSWORD_FIELD_REVERSE_TAB_COUNT="${MC_PASSWORD_FIELD_REVERSE_TAB_COUNT:-2}"
PASSWORD_CONTINUE_REVERSE_TAB_COUNT="${MC_PASSWORD_CONTINUE_REVERSE_TAB_COUNT:-2}"
AUTOKEY_REVERSE_TAB_TRIGGER="${MC_AUTOKEY_REVERSE_TAB_TRIGGER:-mc-reverse-tab}"
NIX_ATTR="${MC_NIX_ATTR:-nixpkgs#mcpelauncher-ui-qt}"

WAIT_LAUNCH="${MC_WAIT_LAUNCH:-15}"
WAIT_AFTER_POPUP_CLOSE="${MC_WAIT_AFTER_POPUP_CLOSE:-2}"
WAIT_AFTER_PASSWORD="${MC_WAIT_AFTER_PASSWORD:-2}"
WAIT_AFTER_LAUNCHER_PLAY="${MC_WAIT_AFTER_LAUNCHER_PLAY:-12}"
WAIT_FOR_LAUNCHER_WINDOW="${MC_WAIT_FOR_LAUNCHER_WINDOW:-60}"
WAIT_FOR_CLIENT_WINDOW="${MC_WAIT_FOR_CLIENT_WINDOW:-60}"
WAIT_BETWEEN_LAUNCHER_ATTEMPTS="${MC_WAIT_BETWEEN_LAUNCHER_ATTEMPTS:-3}"
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
PASSWORD_FIELD_OFFSET_X="${MC_PASSWORD_FIELD_OFFSET_X:-640}"
PASSWORD_FIELD_OFFSET_Y="${MC_PASSWORD_FIELD_OFFSET_Y:-560}"
PASSWORD_CONTINUE_OFFSET_X="${MC_PASSWORD_CONTINUE_OFFSET_X:-640}"
PASSWORD_CONTINUE_OFFSET_Y="${MC_PASSWORD_CONTINUE_OFFSET_Y:-640}"
PASSWORD_FIELD_OFFSET_X_RATIO="${MC_PASSWORD_FIELD_OFFSET_X_RATIO:-0.50}"
PASSWORD_FIELD_OFFSET_Y_RATIO="${MC_PASSWORD_FIELD_OFFSET_Y_RATIO:-0.68}"
PASSWORD_CONTINUE_OFFSET_X_RATIO="${MC_PASSWORD_CONTINUE_OFFSET_X_RATIO:-0.50}"
PASSWORD_CONTINUE_OFFSET_Y_RATIO="${MC_PASSWORD_CONTINUE_OFFSET_Y_RATIO:-0.80}"
PASSWORD_FIELD_PROBE_RATIOS="${MC_PASSWORD_FIELD_PROBE_RATIOS:-0.50:0.68 0.50:0.74 0.50:0.80 0.42:0.74 0.58:0.74}"
LAUNCHER_PLAY_OFFSET_Y="${MC_LAUNCHER_PLAY_OFFSET_Y:-55}"

SERVER_NAV_RIGHT_COUNT="${MC_SERVER_NAV_RIGHT_COUNT:-2}"
SERVER_NAV_DOWN_COUNT="${MC_SERVER_NAV_DOWN_COUNT:-20}"

LAUNCHER_PROCESS_PATTERNS=(
  "mcpelauncher-ui-qt"
  "Minecraft_Bedrock_Launcher"
  "flatpak run io\\.mrarm\\.mcpelauncher"
  "io\\.mrarm\\.mcpelauncher"
  "mcpelauncher"
)

CLIENT_PROCESS_PATTERNS=(
  "mcpelauncher-client-arm64-v8a"
  "mcpelauncher-client32"
  "mcpelauncher-client"
  "MINECRAFT MAIN"
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

CLIENT_WINDOW_CLASS_PATTERNS=(
  "mcpelauncher-client"
  "minecraft"
)

CLIENT_WINDOW_NAME_PATTERNS=(
  "^Minecraft$"
  "^Minecraft Preview$"
)

POPUP_WINDOW_NAME_PATTERNS=(
  "Software Update"
)

LAUNCHER_EXECUTABLES=(
  "mcpelauncher-ui-qt"
  "Minecraft_Bedrock_Launcher"
  "mcpelauncher-ui"
)

FLATPAK_APP_IDS=(
  "io.mrarm.mcpelauncher"
  "io.mrarm.mcpelauncher.ui"
)

GTK_LAUNCH_IDS=(
  "io.mrarm.mcpelauncher.ui"
  "io.mrarm.mcpelauncher"
)

cleanup_existing_launchers() {
  local pids=""

  pids="$(pgrep -f 'mcpelauncher-ui-qt|Minecraft_Bedrock_Launcher|io\.mrarm\.mcpelauncher' 2>/dev/null || true)"
  [[ -n "$pids" ]] || return 0

  echo "Stopping existing launcher instances..."
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done <<<"$pids"

  sleep 2

  pids="$(pgrep -f 'mcpelauncher-ui-qt|Minecraft_Bedrock_Launcher|io\.mrarm\.mcpelauncher' 2>/dev/null || true)"
  [[ -z "$pids" ]] && return 0

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -9 "$pid" 2>/dev/null || true
  done <<<"$pids"

  sleep 1
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

desktop_entry_exists() {
  local desktop_id="$1"
  local applications_dir

  for applications_dir in \
    "${XDG_DATA_HOME:-$HOME/.local/share}/applications" \
    /usr/local/share/applications \
    /usr/share/applications \
    /var/lib/flatpak/exports/share/applications \
    "$HOME/.local/share/flatpak/exports/share/applications"
  do
    [[ -f "${applications_dir}/${desktop_id}.desktop" ]] && return 0
  done

  return 1
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

window_name() {
  local window_id="$1"

  xdotool getwindowname "$window_id" 2>/dev/null || true
}

window_class() {
  local window_id="$1"

  xdotool getwindowclassname "$window_id" 2>/dev/null || true
}

window_matches_patterns() {
  local value="$1"
  shift
  local pattern

  for pattern in "$@"; do
    if [[ "$value" =~ $pattern ]]; then
      return 0
    fi
  done

  return 1
}

active_window_id() {
  xdotool getactivewindow 2>/dev/null || true
}

active_window_matches() {
  local active_id=""
  local active_name=""
  local active_class=""

  active_id="$(active_window_id)"
  [[ -n "$active_id" ]] || return 1

  active_name="$(window_name "$active_id")"
  active_class="$(window_class "$active_id")"

  if window_matches_patterns "$active_name" "$@" || window_matches_patterns "$active_class" "$@"; then
    printf '%s\n' "$active_id"
    return 0
  fi

  return 1
}

log_window_details() {
  local label="$1"
  local window_id="$2"

  {
    echo "-- ${label} --"
    echo "id=${window_id}"
    echo "name=$(window_name "$window_id")"
    echo "class=$(window_class "$window_id")"
  } >>"$DEBUG_LOG" 2>&1
}

log_active_window_details() {
  local label="$1"
  local active_id=""

  active_id="$(active_window_id)"
  {
    echo "-- ${label} --"
    echo "active_id=${active_id}"
    if [[ -n "$active_id" ]]; then
      echo "active_name=$(window_name "$active_id")"
      echo "active_class=$(window_class "$active_id")"
    fi
  } >>"$DEBUG_LOG" 2>&1
}

log_password_step() {
  local message="$1"

  {
    echo "-- password step --"
    echo "$message"
  } >>"$DEBUG_LOG" 2>&1
}

find_autokey_runner() {
  command -v autokey-run 2>/dev/null || true
}

resolve_launch_cmd() {
  local executable_name
  local flatpak_app_id
  local desktop_id

  if [[ -n "${MC_LAUNCH_CMD:-}" ]]; then
    printf '%s\n' "$MC_LAUNCH_CMD"
    return 0
  fi

  for executable_name in "${LAUNCHER_EXECUTABLES[@]}"; do
    if command -v "$executable_name" >/dev/null 2>&1; then
      printf '%s\n' "$executable_name"
      return 0
    fi
  done

  if command -v flatpak >/dev/null 2>&1; then
    for flatpak_app_id in "${FLATPAK_APP_IDS[@]}"; do
      if flatpak info "$flatpak_app_id" >/dev/null 2>&1; then
        printf '%s\n' "flatpak run ${flatpak_app_id} -v"
        return 0
      fi
    done
  fi

  if command -v gtk-launch >/dev/null 2>&1; then
    for desktop_id in "${GTK_LAUNCH_IDS[@]}"; do
      if desktop_entry_exists "$desktop_id"; then
        printf '%s\n' "gtk-launch ${desktop_id}"
        return 0
      fi
    done
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
    done < <(pgrep -f "$pattern" 2>/dev/null | sort -nr || true)
  done

  return 1
}

find_launcher_window() {
  active_window_matches "${LAUNCHER_WINDOW_NAME_PATTERNS[@]}" "${LAUNCHER_WINDOW_CLASS_PATTERNS[@]}" ||
    search_first_window_by_process_patterns "${LAUNCHER_PROCESS_PATTERNS[@]}" ||
    search_first_window_by_class "${LAUNCHER_WINDOW_CLASS_PATTERNS[@]}" ||
    search_first_window_by_name "${LAUNCHER_WINDOW_NAME_PATTERNS[@]}"
}

find_client_window() {
  active_window_matches "${CLIENT_WINDOW_NAME_PATTERNS[@]}" "${CLIENT_WINDOW_CLASS_PATTERNS[@]}" ||
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
  xdotool windowfocus --sync "$window_id" >/dev/null 2>&1 || true
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

key_sequence_for_text() {
  local text="$1"
  local char=""
  local sequence=()
  local i=0

  for ((i = 0; i < ${#text}; i++)); do
    char="${text:i:1}"
    case "$char" in
      [a-zA-Z0-9])
        sequence+=("$char")
        ;;
      " ")
        sequence+=("space")
        ;;
      "-")
        sequence+=("minus")
        ;;
      "_")
        sequence+=("underscore")
        ;;
      ".")
        sequence+=("period")
        ;;
      "@")
        sequence+=("at")
        ;;
      *)
        return 1
        ;;
    esac
  done

  printf '%s\n' "${sequence[*]}"
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

send_reverse_tab() {
  local window_id="$1"
  local autokey_runner=""

  activate_window "$window_id"
  sleep 0.2
  autokey_runner="$(find_autokey_runner)"

  if [[ -n "$autokey_runner" ]]; then
    log_password_step "reverse tab via ${autokey_runner} trigger ${AUTOKEY_REVERSE_TAB_TRIGGER}"
    "$autokey_runner" -s "$AUTOKEY_REVERSE_TAB_TRIGGER" >/dev/null 2>&1 || true
    sleep 0.3
    return 0
  fi

  log_password_step "reverse tab fallback via xdotool right shift; autokey-run not found"
  xdotool keydown --window "$window_id" Shift_R
  sleep 0.1
  xdotool key --window "$window_id" Tab
  sleep 0.1
  xdotool keyup --window "$window_id" Shift_R
  sleep 0.2
  xdotool keydown Shift_R
  sleep 0.1
  xdotool key Tab
  sleep 0.1
  xdotool keyup Shift_R
  sleep 0.2
}

resolve_relative_y() {
  local explicit_y="$1"
  local height="$2"
  local ratio="$3"

  if [[ "$explicit_y" =~ ^[0-9]+$ ]] && (( explicit_y > 0 )); then
    printf '%s\n' "$explicit_y"
    return 0
  fi

  awk -v h="$height" -v r="$ratio" 'BEGIN { printf "%d\n", h * r }'
}

resolve_relative_x() {
  local explicit_x="$1"
  local width="$2"
  local ratio="$3"

  if [[ "$explicit_x" =~ ^[0-9]+$ ]] && (( explicit_x > 0 )); then
    printf '%s\n' "$explicit_x"
    return 0
  fi

  awk -v w="$width" -v r="$ratio" 'BEGIN { printf "%d\n", w * r }'
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
  local key_sequence=""
  local password_field_x=0
  local password_field_y=0
  local password_continue_x=0
  local password_continue_y=0

  if [[ -z "$ENCRYPTION_PASSWORD" ]]; then
    return 0
  fi

  echo "Entering encryption password..."
  log_window_details "password target" "$launcher_id"
  log_active_window_details "before password activate"
  activate_window "$launcher_id"
  log_active_window_details "after password activate"
  eval "$(window_geometry "$launcher_id")"
  password_field_x="$(resolve_relative_x "$PASSWORD_FIELD_OFFSET_X" "$WIDTH" "$PASSWORD_FIELD_OFFSET_X_RATIO")"
  password_field_y="$(resolve_relative_y "$PASSWORD_FIELD_OFFSET_Y" "$HEIGHT" "$PASSWORD_FIELD_OFFSET_Y_RATIO")"
  password_continue_x="$(resolve_relative_x "$PASSWORD_CONTINUE_OFFSET_X" "$WIDTH" "$PASSWORD_CONTINUE_OFFSET_X_RATIO")"
  password_continue_y="$(resolve_relative_y "$PASSWORD_CONTINUE_OFFSET_Y" "$HEIGHT" "$PASSWORD_CONTINUE_OFFSET_Y_RATIO")"
  {
    echo "-- password config --"
    echo "method=${PASSWORD_METHOD}"
    echo "field=${password_field_x},${password_field_y}"
    echo "continue=${password_continue_x},${password_continue_y}"
    echo "window_size=${WIDTH}x${HEIGHT}"
  } >>"$DEBUG_LOG" 2>&1

  case "$PASSWORD_METHOD" in
    click)
      log_password_step "click password field"
      click_window_relative "$launcher_id" "$password_field_x" "$password_field_y"
      sleep 0.2
      click_window_relative "$launcher_id" "$password_field_x" "$password_field_y"
      log_active_window_details "after click password field"
      ;;
    tab)
      while (( attempt < PASSWORD_FIELD_TAB_COUNT )); do
        log_password_step "tab to password field"
        xdotool key --window "$launcher_id" --clearmodifiers Tab
        xdotool key --clearmodifiers Tab
        sleep 0.2
        ((attempt += 1))
      done
      log_active_window_details "after tab to password field"
      ;;
    reverse_tab)
      while (( attempt < PASSWORD_FIELD_REVERSE_TAB_COUNT )); do
        log_password_step "reverse tab to password field"
        send_reverse_tab "$launcher_id"
        sleep 0.2
        ((attempt += 1))
      done
      log_active_window_details "after reverse tab to password field"
      ;;
    *)
      die "Unsupported MC_PASSWORD_METHOD: ${PASSWORD_METHOD}"
      ;;
  esac
  sleep 0.3

  log_password_step "clear existing text"
  xdotool key --window "$launcher_id" --clearmodifiers ctrl+a BackSpace 2>/dev/null || true
  xdotool key --clearmodifiers ctrl+a BackSpace 2>/dev/null || true
  log_password_step "type password with window target"
  xdotool type --window "$launcher_id" --delay 25 --clearmodifiers "$ENCRYPTION_PASSWORD"
  log_password_step "type password globally"
  xdotool type --delay 25 --clearmodifiers "$ENCRYPTION_PASSWORD"
  key_sequence="$(key_sequence_for_text "$ENCRYPTION_PASSWORD" || true)"
  if [[ -n "$key_sequence" ]]; then
    log_password_step "type password as key sequence with window target"
    xdotool key --window "$launcher_id" --delay 80 --clearmodifiers $key_sequence
    log_password_step "type password as global key sequence"
    xdotool key --delay 80 --clearmodifiers $key_sequence
  fi
  attempt=0
  case "$PASSWORD_METHOD" in
    click)
      log_password_step "click continue"
      click_window_relative "$launcher_id" "$password_continue_x" "$password_continue_y"
      log_active_window_details "after click continue"
      ;;
    tab)
      while (( attempt < PASSWORD_CONTINUE_TAB_COUNT )); do
        log_password_step "tab to continue"
        xdotool key --window "$launcher_id" --clearmodifiers Tab
        xdotool key --clearmodifiers Tab
        sleep 0.2
        ((attempt += 1))
      done
      log_active_window_details "after tab to continue"
      ;;
    reverse_tab)
      while (( attempt < PASSWORD_CONTINUE_REVERSE_TAB_COUNT )); do
        log_password_step "reverse tab to continue"
        send_reverse_tab "$launcher_id"
        sleep 0.2
        ((attempt += 1))
      done
      log_active_window_details "after reverse tab to continue"
      ;;
  esac
  sleep 0.2

  log_password_step "press return with window target"
  xdotool key --window "$launcher_id" --clearmodifiers Return
  log_password_step "press return globally"
  xdotool key --clearmodifiers Return
  log_active_window_details "after password submit"
  sleep "$WAIT_AFTER_PASSWORD"
}

run_launcher_sequence() {
  local launcher_id="$1"
  local attempt=0

  echo "Running launcher key sequence..."
  activate_window "$launcher_id"
  log_active_window_details "before launcher sequence"
  sleep 0.5

  press_key_repeatedly Tab 2
  sleep 0.3
  activate_window "$launcher_id"
  sleep 0.3
  xdotool type --delay 25 --clearmodifiers "$ENCRYPTION_PASSWORD"
  sleep 0.3
  activate_window "$launcher_id"
  sleep 0.3
  press_key_repeatedly Tab 1
  sleep 0.3
  press_enter_for_window "$launcher_id"
  sleep 3
  while (( attempt < 10 )); do
    activate_window "$launcher_id"
    xdotool key --clearmodifiers Tab
    sleep "$WAIT_BETWEEN_NAV_KEYS"
    ((attempt += 1))
  done
  press_enter_for_window "$launcher_id"
  log_active_window_details "after launcher sequence"
  sleep "$WAIT_AFTER_PASSWORD"
}

click_launcher_play() {
  local launcher_id="$1"

  echo "Clicking launcher Play..."
  eval "$(window_geometry "$launcher_id")"
  click_window_relative "$launcher_id" "$((WIDTH / 2))" "$((HEIGHT - LAUNCHER_PLAY_OFFSET_Y))"
}

drive_launcher_until_client() {
  local deadline=$((SECONDS + WAIT_FOR_CLIENT_WINDOW))
  local attempt=1
  local launcher_id=""
  local client_id=""

  while (( SECONDS < deadline )); do
    client_id="$(find_client_window || true)"
    if [[ -n "$client_id" ]]; then
      printf '%s\n' "$client_id"
      return 0
    fi

    launcher_id="$(find_launcher_window || true)"
    if [[ -z "$launcher_id" ]]; then
      sleep 1
      continue
    fi

    echo "Launcher automation attempt ${attempt}..."
    log_debug_snapshot
    activate_window "$launcher_id"
    resize_window "$launcher_id"
    sleep 0.5

    fill_password_if_configured "$launcher_id"
    click_launcher_play "$launcher_id"
    sleep "$WAIT_AFTER_LAUNCHER_PLAY"

    client_id="$(find_client_window || true)"
    if [[ -n "$client_id" ]]; then
      printf '%s\n' "$client_id"
      return 0
    fi

    sleep "$WAIT_BETWEEN_LAUNCHER_ATTEMPTS"
    ((attempt += 1))
  done

  return 1
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

press_enter_for_window() {
  local window_id="$1"

  activate_window "$window_id"
  sleep 0.3
  xdotool key --clearmodifiers Return
  sleep 0.3
  xdotool key --clearmodifiers KP_Enter
  sleep 0.3
  activate_window "$window_id"
  xdotool key --clearmodifiers Return
}

press_in_game_return() {
  local active_id=""

  active_id="$(active_window_id)"
  [[ -n "$active_id" ]] || return 0
  press_enter_for_window "$active_id"
}

start_launcher() {
  local launch_cmd

  launch_cmd="$(resolve_launch_cmd)" || die "Could not find a Minecraft Bedrock Launcher command. Set MC_LAUNCH_CMD or install MCPelauncher via PATH, Flatpak, gtk-launch, or Nix."
  echo "Starting MCPelauncher with: $launch_cmd"
  nohup bash -lc "$launch_cmd" >>"$DEBUG_LOG" 2>&1 &
}

require_command bash
require_command nohup
require_command pgrep
require_command xdotool

[[ -n "${DISPLAY:-}" ]] || die "DISPLAY is not set. xdotool needs an X11/XWayland session."
warn_wayland
cleanup_existing_launchers

start_launcher
sleep "$WAIT_LAUNCH"

launcher_window_id="$(wait_for_window find_launcher_window "$WAIT_FOR_LAUNCHER_WINDOW")" ||
  die "Timed out waiting for the launcher window."

log_debug_snapshot
close_update_popup_if_present

run_launcher_sequence "$launcher_window_id"

echo "Waiting for Minecraft client window..."
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
