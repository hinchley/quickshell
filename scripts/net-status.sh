#!/bin/sh
# Reports the active network connection as one of:
#   ethernet:<iface>
#   wifi:<ssid>
#   offline
#
# Interfaces are discovered from /sys/class/net (no hardcoded names, so it works on every machine):
#   ethernet = a physical (has a device/ link), non-wireless interface whose link is up
#   wifi     = an interface with a wireless/ directory; the SSID comes from iwd (iwctl).

for dev in /sys/class/net/*; do
    [ -e "$dev/device" ] || continue
    [ -e "$dev/wireless" ] && continue
    if [ "$(cat "$dev/operstate" 2>/dev/null)" = "up" ]; then
        echo "ethernet:${dev##*/}"
        exit 0
    fi
done

for dev in /sys/class/net/*; do
    [ -e "$dev/wireless" ] || continue
    wlan=${dev##*/}
    # iwctl output is a padded table; strip colour codes, then read the fields we need.
    out=$(iwctl station "$wlan" show 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
    state=$(printf '%s\n' "$out" | awk '$1 == "State" {print $2}')
    ssid=$(printf '%s\n' "$out" | sed -n 's/^ *Connected network *//p' | sed 's/ *$//')
    if [ "$state" = "connected" ]; then
        echo "wifi:$ssid"
        exit 0
    fi
done

echo "offline"
