#!/usr/bin/env zsh

# ===== MCPelauncher automation =====
# macOS install:
#   brew install cliclick
#
# Linux (X11) install:
#   sudo apt install xdotool
#
# macOS permissions:
#   System Settings -> Privacy & Security -> Accessibility
#   Enable Terminal and cliclick

BUNDLE_ID="io.mrarm.mcpelauncher.ui"
PROCESS_NAME="mcpelauncher-ui-qt"
CLICK="/opt/homebrew/bin/cliclick"
DEBUG_LOG="${MC_DEBUG_LOG:-mc_test_debug.log}"
MC_LAUNCH_CMD="${MC_LAUNCH_CMD:-}"
PLATFORM=""
LAUNCHER_PROCESS_PATTERNS=(
	"mcpelauncher-ui-qt"
	"mcpelauncher-ui"
	"io.mrarm.mcpelauncher.ui"
)
LAUNCHER_WINDOW_PATTERNS=(
	"Minecraft Bedrock Launcher"
	"MCPelauncher"
	"Minecraft"
)
LAUNCHER_WINDOW_CLASS_PATTERNS=(
	"mcpelauncher"
	"minecraft"
)
GAME_CLIENT_PROCESS_PATTERNS=(
	"mcpelauncher-client-arm64-v8a"
	"mcpelauncher-client32"
	"mcpelauncher-client"
	"MINECRAFT MAIN"
)

# ===== waits =====
WAIT_LAUNCH=8
WAIT_FOR_LAUNCHER_WINDOW=20
WAIT_AFTER_POPUP_CLOSE=2
WAIT_AFTER_PASSWORD=2
WAIT_AFTER_LAUNCHER_PLAY=10
WAIT_FOR_GAME_CLIENT_FRONT=15
WAIT_AFTER_GAME_CLIENT_FRONT=2
WAIT_AFTER_PLAY=5
WAIT_AFTER_SERVER_SELECT=3
WAIT_BETWEEN_NAV_KEYS=0.15

# ===== main window size =====
WIN_X=50
WIN_Y=50
WIN_W=1280
WIN_H=720

# ===== software update popup close button offset =====
POPUP_CLOSE_OFFSET_X=20
POPUP_CLOSE_OFFSET_Y=20

# ===== password page =====
ENCRYPTION_PASSWORD="${MC_PASSWORD:-12345}"
PASSWORD_FIELD_TAB_COUNT=1
LAUNCHER_PLAY_OFFSET_Y=55

# ===== server/join controls =====
SERVER_NAV_RIGHT_COUNT=2
SERVER_NAV_DOWN_COUNT=20

die() {
	echo "Error: $*" >&2
	exit 1
}

detect_platform() {
	case "$(uname -s)" in
		Darwin) PLATFORM="macos" ;;
		Linux) PLATFORM="linux" ;;
		*) die "unsupported platform: $(uname -s)" ;;
	esac
}

set_default_linux_launch_cmd() {
	if [[ "$PLATFORM" == "linux" && -z "$MC_LAUNCH_CMD" ]]; then
		MC_LAUNCH_CMD="flatpak run io.mrarm.mcpelauncher -v"
	fi
}

require_command() {
	local command_name="$1"
	command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
}

ensure_runtime_requirements() {
	if [[ "$PLATFORM" == "macos" ]]; then
		require_command open
		require_command osascript
		require_command lsappinfo
		[[ -x "$CLICK" ]] || die "cliclick not found at $CLICK"
		return
	fi

	require_command xdotool

	if [[ -n "$MC_LAUNCH_CMD" ]]; then
		return
	fi

	if command -v "$PROCESS_NAME" >/dev/null 2>&1; then
		return
	fi

	if command -v gtk-launch >/dev/null 2>&1; then
		return
	fi

	die "set MC_LAUNCH_CMD or install a launcher entry/executable for $PROCESS_NAME"
}

launch_mcpelauncher() {
	if [[ "$PLATFORM" == "macos" ]]; then
		open -b "$BUNDLE_ID"
		return
	fi

	if [[ -n "$MC_LAUNCH_CMD" ]]; then
		"${(@z)MC_LAUNCH_CMD}" >/dev/null 2>&1 &
		return
	fi

	if command -v "$PROCESS_NAME" >/dev/null 2>&1; then
		"$PROCESS_NAME" >/dev/null 2>&1 &
		return
	fi

	gtk-launch "$BUNDLE_ID" >/dev/null 2>&1 &
}

get_process_pid() {
	pgrep -n -f "$1" 2>/dev/null || true
}

get_launcher_pid() {
	local pattern
	local pid=""

	for pattern in "${LAUNCHER_PROCESS_PATTERNS[@]}"; do
		pid=$(get_process_pid "$pattern")
		if [[ -n "$pid" ]]; then
			echo "$pid"
			return 0
		fi
	done

	return 1
}

get_window_id_by_name() {
	local pattern
	local window_id=""

	for pattern in "${LAUNCHER_WINDOW_PATTERNS[@]}"; do
		window_id=$(xdotool search --onlyvisible --name "$pattern" 2>/dev/null | head -n 1)
		if [[ -n "$window_id" ]]; then
			echo "$window_id"
			return 0
		fi
	done

	return 1
}

get_window_id_by_class() {
	local pattern
	local window_id=""

	for pattern in "${LAUNCHER_WINDOW_CLASS_PATTERNS[@]}"; do
		window_id=$(xdotool search --onlyvisible --class "$pattern" 2>/dev/null | head -n 1)
		if [[ -n "$window_id" ]]; then
			echo "$window_id"
			return 0
		fi
	done

	return 1
}

get_window_id_for_pid() {
	local pid="$1"
	[[ -n "$pid" ]] || return 1
	xdotool search --onlyvisible --pid "$pid" 2>/dev/null | head -n 1
}

is_game_client_process() {
	local process_text="$1"
	local pattern

	for pattern in "${GAME_CLIENT_PROCESS_PATTERNS[@]}"; do
		if [[ "$process_text" == *"$pattern"* ]]; then
			return 0
		fi
	done

	return 1
}

activate_launcher_window() {
	local attempt=1
	local pid
	local window_id

	while (( attempt <= WAIT_FOR_LAUNCHER_WINDOW )); do
		pid=$(get_launcher_pid)
		window_id=$(get_window_id_for_pid "$pid")
		if [[ -z "$window_id" ]]; then
			window_id=$(get_window_id_by_name)
		fi
		if [[ -z "$window_id" ]]; then
			window_id=$(get_window_id_by_class)
		fi
		if [[ -n "$window_id" ]]; then
			xdotool windowactivate --sync "$window_id" >/dev/null 2>&1 || true
			echo "$window_id"
			return 0
		fi
		sleep 1
		((attempt++))
	done

	return 1
}

log_debug_snapshot() {
	if [[ "$PLATFORM" == "linux" ]]; then
		{
			echo
			echo "==== $(date '+%Y-%m-%d %H:%M:%S') ===="
			echo "-- xdotool active window --"
			xdotool getactivewindow getwindowpid || true
			echo "-- ps filtered --"
			ps -eo pid,ppid,comm,args | rg -i 'minecraft|mcpelauncher|mrarm|client|ui-qt' || true
		} >> "$DEBUG_LOG" 2>&1
		return
	fi

	{
		echo
		echo "==== $(date '+%Y-%m-%d %H:%M:%S') ===="
		echo "-- lsappinfo front --"
		lsappinfo front
		echo "-- lsappinfo visibleProcessList --"
		lsappinfo visibleProcessList
		echo "-- lsappinfo list filtered --"
		lsappinfo list | rg -i 'minecraft|mcpelauncher|mrarm|client|ui-qt' || true
		echo "-- ps filtered --"
		ps -axo pid,ppid,comm,args | rg -i 'minecraft|mcpelauncher|mrarm|client|ui-qt' || true
	} >> "$DEBUG_LOG" 2>&1
}

wait_for_front_game_client() {
	local attempt=1
	local front_asn
	local front_info
	local active_pid
	local active_args

	while (( attempt <= WAIT_FOR_GAME_CLIENT_FRONT )); do
		if [[ "$PLATFORM" == "linux" ]]; then
			active_pid=$(xdotool getactivewindow getwindowpid 2>/dev/null || true)
			active_args=$(ps -p "$active_pid" -o comm=,args= 2>/dev/null || true)
			if is_game_client_process "$active_args"; then
				return 0
			fi
			sleep 1
			((attempt++))
			continue
		fi

		front_asn=$(lsappinfo front | awk '{print $1}')
		front_info=$(lsappinfo info -app "$front_asn" 2>/dev/null || true)

		if is_game_client_process "$front_info"; then
			return 0
		fi

		sleep 1
		((attempt++))
	done

	return 1
}

press_key_repeatedly() {
	local key_name="$1"
	local press_count="$2"
	local attempt=1
	local key_code=""

	case "$key_name" in
		arrow-left) key_code=123 ;;
		arrow-right) key_code=124 ;;
		arrow-down) key_code=125 ;;
		arrow-up) key_code=126 ;;
	esac

	while (( attempt <= press_count )); do
		if [[ "$PLATFORM" == "linux" ]]; then
			case "$key_name" in
				arrow-left) xdotool key --clearmodifiers Left ;;
				arrow-right) xdotool key --clearmodifiers Right ;;
				arrow-down) xdotool key --clearmodifiers Down ;;
				arrow-up) xdotool key --clearmodifiers Up ;;
				*) xdotool key --clearmodifiers "$key_name" ;;
			esac
			sleep "$WAIT_BETWEEN_NAV_KEYS"
			((attempt++))
			continue
		fi

		if [[ -n "$key_code" ]]; then
			osascript <<EOF
tell application "System Events"
	key code $key_code
end tell
EOF
		else
			$CLICK "kp:${key_name}"
		fi
		sleep "$WAIT_BETWEEN_NAV_KEYS"
		((attempt++))
	done
}

press_in_game_return() {
	if [[ "$PLATFORM" == "linux" ]]; then
		xdotool key --clearmodifiers Return
		sleep 0.5
		xdotool key --clearmodifiers KP_Enter
		sleep 0.5
		xdotool key --clearmodifiers Return
		return
	fi

	osascript <<EOF
tell application "System Events"
	key code 36
	delay 0.5
	key code 76
end tell
EOF

	sleep 0.5
	$CLICK kp:return
	sleep 0.5
	$CLICK kp:num-enter
}

press_fast_return() {
	if [[ "$PLATFORM" == "linux" ]]; then
		xdotool key --clearmodifiers Return
		return
	fi

	osascript <<EOF
tell application "System Events"
	key code 36
end tell
EOF
}

detect_platform
set_default_linux_launch_cmd
ensure_runtime_requirements

echo "Starting MCPelauncher..."
launch_mcpelauncher
sleep "$WAIT_LAUNCH"

echo "Checking for Software Update popup..."
if [[ "$PLATFORM" == "linux" ]]; then
	popup_window=$(xdotool search --name "Software Update" 2>/dev/null | head -n 1 || true)
	if [[ -n "$popup_window" ]]; then
		xdotool windowactivate --sync "$popup_window" >/dev/null 2>&1 || true
		xdotool key --window "$popup_window" --clearmodifiers Escape >/dev/null 2>&1 || true
		xdotool windowclose "$popup_window" >/dev/null 2>&1 || true
	fi
else
	osascript <<EOF
tell application "System Events"
	if exists process "$PROCESS_NAME" then
		tell process "$PROCESS_NAME"
			set frontmost to true
			delay 1
			
			repeat with w in windows
				try
					set wname to name of w
					if wname contains "Software Update" then
						set {px, py} to position of w
						do shell script "$CLICK c:" & (px + $POPUP_CLOSE_OFFSET_X) & "," & (py + $POPUP_CLOSE_OFFSET_Y)
						delay 1
						exit repeat
					end if
				end try
			end repeat
		end tell
	end if
end tell
EOF
fi

sleep "$WAIT_AFTER_POPUP_CLOSE"

echo "Entering encryption password and continuing..."
if [[ "$PLATFORM" == "linux" ]]; then
	launcher_window=$(activate_launcher_window) || die "could not find MCPelauncher window on Linux"
	sleep 1
	for ((i = 1; i <= PASSWORD_FIELD_TAB_COUNT; i++)); do
		xdotool key --window "$launcher_window" --clearmodifiers Tab
		sleep 0.2
	done
	xdotool type --window "$launcher_window" --clearmodifiers --delay 1 "$ENCRYPTION_PASSWORD"
	sleep 0.3
	xdotool key --window "$launcher_window" --clearmodifiers Return
else
	osascript <<EOF
tell application "System Events"
	set didFill to false
	if exists process "$PROCESS_NAME" then
		tell process "$PROCESS_NAME"
			set frontmost to true
			delay 1
			try
				set value of text field 1 of front window to "$ENCRYPTION_PASSWORD"
				set didFill to true
			end try
		end tell

		if didFill is false then
			repeat $PASSWORD_FIELD_TAB_COUNT times
				key code 48
				delay 0.2
			end repeat
			keystroke "$ENCRYPTION_PASSWORD"
			delay 0.3
		end if

		try
			click button "Continue" of front window of process "$PROCESS_NAME"
		on error
			key code 36
		end try
	end if
end tell
EOF
fi

sleep "$WAIT_AFTER_PASSWORD"

echo "Resizing launcher window..."
if [[ "$PLATFORM" == "linux" ]]; then
	launcher_window=$(activate_launcher_window) || die "could not find MCPelauncher window on Linux"
	xdotool windowmove "$launcher_window" "$WIN_X" "$WIN_Y"
	xdotool windowsize "$launcher_window" "$WIN_W" "$WIN_H"
else
	osascript <<EOF
tell application "System Events"
	if exists process "$PROCESS_NAME" then
		tell process "$PROCESS_NAME"
			set frontmost to true
			delay 1
			try
				set position of front window to {$WIN_X, $WIN_Y}
				set size of front window to {$WIN_W, $WIN_H}
			end try
		end tell
	end if
end tell
EOF
fi

sleep 1

echo "Clicking launcher Play..."
if [[ "$PLATFORM" == "linux" ]]; then
	launcher_window=$(activate_launcher_window) || die "could not find MCPelauncher window on Linux"
	eval "$(xdotool getwindowgeometry --shell "$launcher_window")"
	play_x=$((X + (WIDTH / 2)))
	play_y=$((Y + HEIGHT - LAUNCHER_PLAY_OFFSET_Y))
	xdotool mousemove --sync "$play_x" "$play_y"
	xdotool click 1
else
	osascript <<EOF
tell application "System Events"
	if exists process "$PROCESS_NAME" then
		tell process "$PROCESS_NAME"
			set frontmost to true
			delay 1
			try
				click button "Play" of front window
			on error
				try
					set {wx, wy} to position of front window
					set {ww, wh} to size of front window
					set playX to wx + (ww div 2)
					set playY to wy + wh - $LAUNCHER_PLAY_OFFSET_Y
					do shell script "$CLICK c:" & playX & "," & playY
				end try
			end try
		end tell
	end if
end tell
EOF
fi

sleep "$WAIT_AFTER_LAUNCHER_PLAY"

echo "Waiting for Minecraft client to be frontmost..."
log_debug_snapshot
wait_for_front_game_client || echo "Warning: game client was not detected as frontmost before Return."
sleep "$WAIT_AFTER_GAME_CLIENT_FRONT"
log_debug_snapshot

echo "Pressing Return for in-game Play..."
press_in_game_return
sleep 1
log_debug_snapshot

sleep "$WAIT_AFTER_PLAY"

echo "Selecting server with keyboard..."
wait_for_front_game_client || echo "Warning: game client was not detected as frontmost before server navigation."
sleep "$WAIT_AFTER_GAME_CLIENT_FRONT"
press_key_repeatedly "arrow-right" "$SERVER_NAV_RIGHT_COUNT"
sleep "$WAIT_BETWEEN_NAV_KEYS"
press_fast_return
sleep "$WAIT_BETWEEN_NAV_KEYS"
press_key_repeatedly "arrow-down" "$SERVER_NAV_DOWN_COUNT"
sleep "$WAIT_BETWEEN_NAV_KEYS"
press_fast_return
sleep "$WAIT_BETWEEN_NAV_KEYS"
press_key_repeatedly "arrow-right" "$SERVER_NAV_RIGHT_COUNT"
sleep "$WAIT_BETWEEN_NAV_KEYS"
press_fast_return

sleep "$WAIT_AFTER_SERVER_SELECT"

echo "Done."
