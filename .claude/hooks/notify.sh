#!/bin/bash

# Claude Code hook notification script
# Reads JSON from stdin and sends a macOS notification via terminal-notifier

INPUT=$(cat)

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')
MESSAGE=$(echo "$INPUT" | jq -r '.message // ""')
TITLE=$(echo "$INPUT" | jq -r '.title // "Claude Code"')
NOTIF_TYPE=$(echo "$INPUT" | jq -r '.notification_type // ""')
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# Detect terminal application for activation
if [ "$TERM_PROGRAM" = "vscode" ]; then
    APP_ID="com.microsoft.VSCode"
elif [ "$TERM_PROGRAM" = "Apple_Terminal" ]; then
    APP_ID="com.apple.Terminal"
elif [ "$TERM_PROGRAM" = "Zed" ] || [ "$TERM_PROGRAM" = "zed" ]; then
    APP_ID="dev.zed.Zed"
else
    APP_ID=$(osascript -e "tell application \"System Events\" to get bundle identifier of first application process whose unix id is $PPID" 2>/dev/null)
fi

if [ "$HOOK_EVENT" = "Stop" ]; then
    # Prevent infinite loops
    if [ "$STOP_ACTIVE" = "true" ]; then
        exit 0
    fi
    TITLE="✅ Claude Code"
    MESSAGE="Task completed"
elif [ "$HOOK_EVENT" = "Notification" ]; then
    if [ -z "$TITLE" ] || [ "$TITLE" = "null" ]; then
        TITLE="Claude Code"
    fi
    if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
        case "$NOTIF_TYPE" in
            permission_prompt) MESSAGE="Claude needs your permission" ;;
            idle_prompt)        MESSAGE="Claude is waiting for your input" ;;
            *)                  MESSAGE="Claude needs your attention" ;;
        esac
    fi
    TITLE="🔔 $TITLE"
fi

terminal-notifier -title "$TITLE" \
    -message "$MESSAGE" \
    -sound default \
    -appIcon /Users/david/Downloads/clawd.png \
    -activate "$APP_ID"

exit 0
