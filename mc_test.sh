#!/bin/zsh

# ===== MCPelauncher macOS automation =====
# Install:
#   brew install cliclick
#
# Permissions:
#   System Settings -> Privacy & Security -> Accessibility
#   Enable Terminal and cliclick

BUNDLE_ID="io.mrarm.mcpelauncher.ui"
PROCESS_NAME="mcpelauncher-ui-qt"
CLICK="/opt/homebrew/bin/cliclick"
DEBUG_LOG="${MC_DEBUG_LOG:-mc_test_debug.log}"
GAME_CLIENT_EXECUTABLE="mcpelauncher-client-arm64-v8a"

# ===== waits =====
WAIT_LAUNCH=8
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

log_debug_snapshot() {
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

	while (( attempt <= WAIT_FOR_GAME_CLIENT_FRONT )); do
		front_asn=$(lsappinfo front | awk '{print $1}')
		front_info=$(lsappinfo info -app "$front_asn" 2>/dev/null || true)

		if [[ "$front_info" == *"$GAME_CLIENT_EXECUTABLE"* ]]; then
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
	osascript <<EOF
tell application "System Events"
	key code 36
end tell
EOF
}

echo "Starting MCPelauncher..."
open -b "$BUNDLE_ID"
sleep "$WAIT_LAUNCH"

echo "Checking for Software Update popup..."
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

sleep "$WAIT_AFTER_POPUP_CLOSE"

echo "Entering encryption password and continuing..."
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

sleep "$WAIT_AFTER_PASSWORD"

echo "Resizing launcher window..."
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

sleep 1

echo "Clicking launcher Play..."
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
