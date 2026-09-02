#!/bin/sh
# Reports the active network connection as one of:
#   ethernet:<iface>
#   wifi:<ssid>
#   offline
#
# Usage: net-status.sh <eth-interface> <wlan-interface>

eth="$1"
wlan="$2"

if [ "$(cat "/sys/class/net/$eth/operstate" 2>/dev/null)" = "up" ]; then
    echo "ethernet:$eth"
    exit 0
fi

state=""
ssid=""
while IFS= read -r line; do
    case "$line" in
        *State*) state=$(echo "$line" | awk '{print $2}') ;;
        *"Connected network"*) ssid=$(echo "$line" | awk '{print $3}') ;;
    esac
done <<EOF
$(iwctl station "$wlan" show 2>/dev/null)
EOF

if [ "$state" = "connected" ]; then
    echo "wifi:$ssid"
else
    echo "offline"
fi
