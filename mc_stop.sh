#!/bin/zsh

BUNDLE_ID="io.mrarm.mcpelauncher.ui"
WAIT_AFTER_QUIT=3
KILL_SIGNAL="${MC_KILL_SIGNAL:-TERM}"
PLATFORM=""

PROCESS_PATTERNS=(
	"mcpelauncher-client-arm64-v8a"
	"mcpelauncher-client32"
	"mcpelauncher-client"
	"MINECRAFT MAIN"
	"mcpelauncher-ui"
	"mcpelauncher-ui-qt"
	"mcpelauncher-webview"
	"msa-ui-qt"
	"msa-daemon"
)

detect_platform() {
	case "$(uname -s)" in
		Darwin) PLATFORM="macos" ;;
		Linux) PLATFORM="linux" ;;
		*) PLATFORM="other" ;;
	esac
}

stop_process_pattern() {
	local pattern="$1"

	if pgrep -f "$pattern" >/dev/null 2>&1; then
		echo "Stopping processes matching: $pattern"
		pkill "-$KILL_SIGNAL" -f "$pattern" >/dev/null 2>&1 || true
	fi
}

detect_platform

echo "Requesting Minecraft Bedrock Launcher to quit..."
if [[ "$PLATFORM" == "macos" ]]; then
	osascript <<EOF >/dev/null 2>&1
tell application id "$BUNDLE_ID" to quit
EOF
fi

sleep "$WAIT_AFTER_QUIT"

for pattern in "${PROCESS_PATTERNS[@]}"; do
	stop_process_pattern "$pattern"
done

sleep 1

for pattern in "${PROCESS_PATTERNS[@]}"; do
	if pgrep -f "$pattern" >/dev/null 2>&1; then
		echo "Force stopping processes matching: $pattern"
		pkill -KILL -f "$pattern" >/dev/null 2>&1 || true
	fi
done

echo "Done."
