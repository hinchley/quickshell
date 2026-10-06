# Overview
My personal Quickshell config. Runs on Arch Linux with Hyprland. Provides a bar with the following features:
- workspace selector
- active window title
- mpris integration (show active track with previous, pause, and next controls)
- date / clock (with popup calendar)
- system tray
- CPU temp (lauches s-tui on click)
- CPU utilisation (launches btop on click)
- Memory utilisation (launches btop on click)
- Disk utilisation (launches dua on click)
- Bluetooth (shows active connections and launches bluetui on click)
- Network (supports wired and wireless connections and launches impala on click)
- Volume control (raise and lower with mouse wheel and launches wiremix on click)

Command + space opens an app launcher with fuzzy search that supports a custom blacklist.
Command + shift + k opens a fuzzy-searchable list of every keybind in `~/.config/hypr/hyprland.lua` (read via `scripts/keybinds.lua`; needs `lua`).