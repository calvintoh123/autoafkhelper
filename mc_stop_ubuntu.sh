#!/usr/bin/env bash

set -euo pipefail

WAIT_AFTER_CLOSE="${MC_WAIT_AFTER_CLOSE:-3}"
KILL_SIGNAL="${MC_KILL_SIGNAL:-TERM}"

WINDOW_CLASS_PATTERNS=(
  "mcpelauncher-ui-qt"
  "mcpelauncher-client"
  "io.mrarm.mcpelauncher"
)

WINDOW_NAME_PATTERNS=(
  "Minecraft Bedrock Launcher"
  "MCPelauncher"
  "Minecraft"
  "mcpelauncher"
)

PROCESS_PATTERNS=(
  "mcpelauncher-client-arm64-v8a"
  "mcpelauncher-client32"
  "mcpelauncher-client"
  "mcpelauncher-ui-qt"
  "mcpelauncher-webview"
  "msa-ui-qt"
  "msa-daemon"
)

search_windows_by_class() {
  local pattern

  for pattern in "$@"; do
    xdotool search --onlyvisible --class "$pattern" 2>/dev/null || true
  done
}

search_windows_by_name() {
  local pattern

  for pattern in "$@"; do
    xdotool search --onlyvisible --name "$pattern" 2>/dev/null || true
  done
}

close_visible_windows() {
  local window_id

  while IFS= read -r window_id; do
    [[ -n "$window_id" ]] || continue
    echo "Closing window: $window_id"
    xdotool windowactivate --sync "$window_id" >/dev/null 2>&1 || true
    xdotool windowclose "$window_id" >/dev/null 2>&1 || true
    sleep 0.2
    xdotool key --window "$window_id" --clearmodifiers Alt+F4 >/dev/null 2>&1 || true
  done < <(
    {
      search_windows_by_class "${WINDOW_CLASS_PATTERNS[@]}"
      search_windows_by_name "${WINDOW_NAME_PATTERNS[@]}"
    } | awk 'NF && !seen[$0]++'
  )
}

stop_process_pattern() {
  local pattern="$1"

  if pgrep -f "$pattern" >/dev/null 2>&1; then
    echo "Stopping processes matching: $pattern"
    pkill "-$KILL_SIGNAL" -f "$pattern" >/dev/null 2>&1 || true
  fi
}

force_stop_process_pattern() {
  local pattern="$1"

  if pgrep -f "$pattern" >/dev/null 2>&1; then
    echo "Force stopping processes matching: $pattern"
    pkill -KILL -f "$pattern" >/dev/null 2>&1 || true
  fi
}

command -v pgrep >/dev/null 2>&1 || {
  echo "Error: Missing required command: pgrep" >&2
  exit 1
}

command -v pkill >/dev/null 2>&1 || {
  echo "Error: Missing required command: pkill" >&2
  exit 1
}

if command -v xdotool >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
  echo "Requesting Minecraft Bedrock Launcher to close..."
  close_visible_windows
  sleep "$WAIT_AFTER_CLOSE"
fi

for pattern in "${PROCESS_PATTERNS[@]}"; do
  stop_process_pattern "$pattern"
done

sleep 1

for pattern in "${PROCESS_PATTERNS[@]}"; do
  force_stop_process_pattern "$pattern"
done

echo "Done."
