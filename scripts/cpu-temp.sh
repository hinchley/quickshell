#!/bin/sh

for hw in /sys/class/hwmon/hwmon*; do
    [ -d "$hw" ] || continue
    name=$(cat "$hw/name" 2>/dev/null)

    case "$name" in
        coretemp|k10temp|zenpower)
            for f in "$hw"/temp*_input; do
                [ -e "$f" ] || continue
                label=$(cat "${f%_input}_label" 2>/dev/null)
                case "$label" in
                    "Package id 0"|Tctl|Tdie)
                        awk '{printf "%d\n", $1 / 1000}' "$f"
                        exit 0
                        ;;
                esac
            done

            # No package-level label found on this chip; fall back to its first sensor.
            if [ -e "$hw/temp1_input" ]; then
                awk '{printf "%d\n", $1 / 1000}' "$hw/temp1_input"
                exit 0
            fi
            ;;
    esac
done

echo "--"
