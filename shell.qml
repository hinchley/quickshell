pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland

ShellRoot {
  id: root

  // =========================================================================
  // 1. Theme Configuration & Global Constants
  // =========================================================================
  property color colBg:     "#1a1b26"
  property color colPill:   "#24253a"
  property color colFg:     "#a9b1d6"
  property color colMuted:  "#444b6a"
  property color colCyan:   "#0db9d7"
  property color colPurple: "#ad8ee6"
  property color colRed:    "#f7768e"
  property color colYellow: "#e0af68"
  property color colBlue:   "#7aa2f7"
  property color colGreen:  "#9ece6a"

  property color colBorderFaint:  Qt.rgba(1, 1, 1, 0.04)
  property color colBorderMed:    Qt.rgba(1, 1, 1, 0.06)
  property color colBorderSoft:   Qt.rgba(1, 1, 1, 0.05)
  property color colBorderStrong: Qt.rgba(1, 1, 1, 0.10)
  property color colFillFaint:    Qt.rgba(1, 1, 1, 0.025)
  property color colFillSubtle:   Qt.rgba(1, 1, 1, 0.03)
  property color colFillInput:    Qt.rgba(1, 1, 1, 0.035)
  property color colFillHover:    Qt.rgba(1, 1, 1, 0.08)

  property string fontFamily: "IoskeleyMonoTerm Nerd Font Mono"
  property int fontSize: 13

  // Desktop wallpaper (also used by hyprlock). Replace the file (or symlink) to change it.
  readonly property string wallpaper: Quickshell.env("HOME") + "/.config/backgrounds/background.png"

  readonly property string scriptDir: Quickshell.shellDir + "/scripts"
  readonly property string hyprConfig: Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"

  // =========================================================================
  // 2. State Management Definitions
  // =========================================================================
  property int cpuUsage: 0
  property int memUsage: 0
  property int diskUsage: 0
  property string cpuTemp: "--"
  property string activeWindow: "Desktop"

  property real lastCpuIdle: 0
  property real lastCpuTotal: 0

  // Ticks at the start of every minute (and on timezone / wall-clock changes),
  // so anything bound to clock.date never goes stale.
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  property bool barVisible: true
  property bool calendarOpen: false
  property int calendarMonth: clock.date.getMonth()
  property int calendarYear: clock.date.getFullYear()

  property string netType: ""
  property string netName: ""

  // Only one overlay (launcher / keybinds) is shown at a time.
  property string overlay: ""
  readonly property bool launcherOpen: overlay === "launcher"
  readonly property bool keybindsOpen: overlay === "keybinds"

  property var launcherWhitelist: []
  property var launcherBlacklist: [
    "Avahi",
    "btop++",
    "Foot Client",
    "Foot Server",
    "Hardware Locality",
    "Kvantum",
    "Limine",
    "Manage Printing",
    "QT",
    "Qt V4L2",
    "uuctl",
    "UXterm",
    "Vim",
    "wiremix",
    "XTerm"
  ]

  property var keybindList: []

  // =========================================================================
  // 3. UI Reusable Building Blocks
  // =========================================================================
  component BarText: Text {
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    color: root.colFg
  }

  // Standard Panel Capsule Item
  component Pill: Rectangle {
    id: pill
    default property alias content: pillLayout.children
    property real spacing: 4
    property real sidePadding: 30
    property alias mouse: pillMouseArea

    color: root.colPill
    radius: 12
    implicitHeight: 28
    border.color: root.colBorderFaint
    border.width: 1
    implicitWidth: pillLayout.implicitWidth + sidePadding

    RowLayout {
      id: pillLayout
      spacing: pill.spacing
      anchors {
        fill: parent
        leftMargin: pill.sidePadding / 2
        rightMargin: pill.sidePadding / 2
      }
    }

    MouseArea {
      id: pillMouseArea
      anchors.fill: parent
      enabled: false
    }
  }

  component MetricPill: Pill {
    id: metricPill
    property string label
    property color labelColor: root.colFg
    signal clicked()

    mouse.enabled: true
    mouse.cursorShape: Qt.PointingHandCursor
    mouse.onClicked: clicked()

    BarText {
      text: metricPill.label
      color: metricPill.labelColor
      font.bold: true
    }
  }

  // Runs a TUI in a foot window; clicking again while it is open is a no-op.
  component TuiProcess: Process {
    required property string appId
    required property var program
    command: ["foot", "--app-id=org.hinchley." + appId, "-e"].concat(program)
  }

  // Full-screen overlay holding a search box and a filtered list. The parent
  // supplies the already-filtered `entries`; each row shows entry[primaryRole]
  // and, optionally, entry[secondaryRole] beside it.
  // qmllint disable uncreatable-type
  component PickerWindow: PanelWindow {
    // qmllint enable uncreatable-type
    id: picker

    property bool open: false
    property string placeholder: ""
    property var entries: []
    property string primaryRole: "name"
    property string secondaryRole: ""
    property real primaryWidth: 0        // 0 = primary text fills the row
    property real panelWidth: 560
    property real panelHeight: 420
    property alias query: input.text

    signal activated(var entry)
    signal dismissed()

    visible: open

    // Native Wayland Layer Shell specifications for Quickshell 0.3.x
    WlrLayershell.layer: WlrLayer.Overlay
    focusable: true
    color: "transparent"
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    onVisibleChanged: {
      if (!visible) return;
      input.text = "";
      input.forceActiveFocus();
    }

    function activateSelected() {
      if (list.currentIndex >= 0) picker.activated(filtered.values[list.currentIndex]);
    }

    // Full-screen click-dismiss
    MouseArea {
      anchors.fill: parent
      onClicked: picker.dismissed()
    }

    Rectangle {
      anchors.centerIn: parent
      width: picker.panelWidth
      height: picker.panelHeight
      color: root.colPill
      radius: 10
      border.color: root.colBorderStrong
      border.width: 1

      // Swallow clicks so they don't reach the dismiss area behind
      MouseArea {
        anchors.fill: parent
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 42
          radius: 10
          color: root.colFillInput
          border.color: input.activeFocus ? root.colCyan : root.colBorderMed
          border.width: 1

          TextField {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            placeholderText: picker.placeholder
            color: root.colFg
            placeholderTextColor: root.colMuted
            selectionColor: root.colCyan
            selectedTextColor: root.colBg
            font.family: root.fontFamily
            font.pixelSize: root.fontSize + 3
            padding: 0
            verticalAlignment: TextInput.AlignVCenter
            background: null

            Keys.onEscapePressed: picker.dismissed()
            Keys.onPressed: event => {
              var ctrl = event.modifiers & Qt.ControlModifier;
              if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && ctrl)) {
                event.accepted = true;
                if (list.currentIndex > 0) list.currentIndex--;
              } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && ctrl)) {
                event.accepted = true;
                if (list.currentIndex < list.count - 1) list.currentIndex++;
              } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                event.accepted = true;
                var page = Math.max(1, Math.floor(list.height / (list.currentItem?.height || 36)) - 1);
                var target = list.currentIndex + (event.key === Qt.Key_PageUp ? -page : page);
                list.currentIndex = Math.max(0, Math.min(list.count - 1, target));
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                event.accepted = true;
                picker.activateSelected();
              } else if (event.key === Qt.Key_C && ctrl) {
                event.accepted = true;
                picker.dismissed();
              }
            }
          }
        }

        ScriptModel {
          id: filtered
          values: picker.entries
          onValuesChanged: Qt.callLater(() => list.currentIndex = list.count > 0 ? 0 : -1)
        }

        ListView {
          id: list
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: filtered
          currentIndex: count > 0 ? 0 : -1
          boundsBehavior: Flickable.StopAtBounds
          highlightMoveDuration: 80
          highlight: Rectangle {
            radius: 8
            color: Qt.rgba(root.colCyan.r, root.colCyan.g, root.colCyan.b, 0.18)
            border.color: Qt.rgba(root.colCyan.r, root.colCyan.g, root.colCyan.b, 0.28)
            border.width: 1
          }

          delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: ListView.isCurrentItem
            width: ListView.view.width
            height: picker.secondaryRole === "" ? 46 : Math.max(36, secondary.implicitHeight + 16)

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: list.currentIndex = row.index
              onDoubleClicked: picker.activateSelected()
            }

            RowLayout {
              anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 12
              }
              spacing: 16

              BarText {
                Layout.fillWidth: picker.primaryWidth === 0
                Layout.preferredWidth: picker.primaryWidth > 0 ? picker.primaryWidth : -1
                text: row.modelData[picker.primaryRole] ?? ""
                color: (row.current || picker.secondaryRole !== "") ? root.colCyan : root.colFg
                font.pixelSize: root.fontSize + 1
                font.bold: row.current
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              BarText {
                id: secondary
                visible: picker.secondaryRole !== ""
                Layout.fillWidth: true
                text: row.modelData[picker.secondaryRole] ?? ""
                color: row.modelData.muted ? root.colMuted : root.colFg
                font.pixelSize: root.fontSize + 1
                font.bold: row.current
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
            }
          }
        }

        BarText {
          visible: picker.entries.length === 0
          Layout.fillWidth: true
          text: "No matches"
          color: root.colMuted
          horizontalAlignment: Text.AlignHCenter
          font.bold: true
        }
      }
    }
  }

  // =========================================================================
  // 4. Engine & Context Evaluation Methods
  // =========================================================================
  function toggleCalendar() {
    calendarOpen = !calendarOpen;
    if (calendarOpen) showCalendarMonth(clock.date.getFullYear(), clock.date.getMonth());
  }

  function closeCalendar() {
    calendarOpen = false;
  }

  function showCalendarMonth(year, month) {
    // Normalises overflow, e.g. (2026, 12) -> January 2027.
    var first = new Date(year, month, 1);
    calendarYear = first.getFullYear();
    calendarMonth = first.getMonth();
  }

  // 6 weeks of days starting on the Monday on/before the 1st. `now` is passed
  // in (rather than read here) so the caller's binding re-runs when the day changes.
  function generateCalendarDays(year, month, now) {
    var days = [];
    var offset = (new Date(year, month, 1).getDay() + 6) % 7; // Monday = 0

    for (var i = 0; i < 42; i++) {
      var date = new Date(year, month, 1 - offset + i);
      days.push({
        day: date.getDate(),
        month: date.getMonth() === month,
        today: date.getFullYear() === now.getFullYear()
          && date.getMonth() === now.getMonth()
          && date.getDate() === now.getDate()
      });
    }

    return days;
  }

  function openOverlay(name) {
    overlay = name;
    if (name === "keybinds") keybindProc.running = true; // re-read the config each time
  }

  function closeOverlay() {
    overlay = "";
  }

  function toggleOverlay(name) {
    if (overlay === name) closeOverlay();
    else openOverlay(name);
  }

  function normalizeText(value) {
    return (value ?? "")
      .toString()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  }

  // Score of one token against one normalised string: exact > prefix > word start > substring.
  function textScore(haystack, token) {
    if (haystack === token)                      return 120;
    if (haystack.indexOf(token) === 0)           return 90;
    if (haystack.indexOf(" " + token) >= 0)      return 70;
    if (haystack.indexOf(token) >= 0)            return 55;
    return 0;
  }

  function desktopCommand(entry) {
    return entry?.execString
      ?? entry?.command?.join(" ")
      ?? entry?.id
      ?? "";
  }

  function launcherBlacklistMatches(entry) {
    var haystack = normalizeText([
      entry.name ?? "",
      entry.id ?? "",
      desktopCommand(entry),
      entry.comment ?? ""
    ].join(" "));

    return launcherBlacklist.some(item => {
      var needle = normalizeText(item);
      return needle !== "" && haystack.indexOf(needle) >= 0;
    });
  }

  function normalizeCommand(command) {
    return Array.isArray(command) ? command.join(" ") : (command ?? "");
  }

  function launcherBaseEntries() {
    if (launcherWhitelist && launcherWhitelist.length > 0) {
      return launcherWhitelist
        .filter(entry =>
          (entry.name ?? "") !== "" &&
          normalizeCommand(entry.command) !== ""
        ).map(entry => ({
          name: entry.name,
          command: normalizeCommand(entry.command),
          comment: entry.comment ?? "",
          keywords: entry.keywords ?? [],
          categories: entry.categories ?? [],
          source: null
        }));
    }

    return DesktopEntries.applications.values
      .filter(entry =>
        entry.name &&
        !launcherBlacklistMatches(entry)
      ).map(entry => ({
        name: entry.name,
        command: desktopCommand(entry),
        comment: entry.comment ?? "",
        keywords: entry.keywords ?? [],
        categories: entry.categories ?? [],
        source: entry
      }));
  }

  readonly property var launcherBaseCache: launcherBaseEntries().map(entry => ({
    entry: entry,
    normName:       normalizeText(entry.name),
    normCommand:    normalizeText(entry.command),
    normComment:    normalizeText(entry.comment),
    normKeywords:   normalizeText((entry.keywords ?? []).join(" ")),
    normCategories: normalizeText((entry.categories ?? []).join(" "))
  }))

  function launcherScore(cached, tokens) {
    var score = 0;

    for (var i = 0; i < tokens.length; i++) {
      var token = tokens[i];
      var nameScore = textScore(cached.normName, token);

      if (nameScore > 0)                                  score += nameScore;
      else if (cached.normCommand.indexOf(token) >= 0)    score += 35;
      else if (cached.normKeywords.indexOf(token) >= 0)   score += 25;
      else if (cached.normCategories.indexOf(token) >= 0) score += 15;
      else if (cached.normComment.indexOf(token) >= 0)    score += 8;
      else return -1;
    }

    return score;
  }

  // Keeps cache items matching every token, best score first. `compare` orders ties.
  function rankEntries(cache, query, scoreFn, compare) {
    var tokens = normalizeText(query).split(/\s+/).filter(token => token.length > 0);

    return cache
      .map(cached => ({
        cached: cached,
        score: tokens.length === 0 ? 1 : scoreFn(cached, tokens)
      })).filter(match =>
        match.score >= 0
      ).sort((a, b) =>
        b.score - a.score || compare(a.cached, b.cached)
      ).map(match =>
        match.cached.entry
      );
  }

  function launcherEntries(query) {
    return rankEntries(launcherBaseCache, query, launcherScore,
      (a, b) => a.entry.name.localeCompare(b.entry.name));
  }

  function launchEntry(entry) {
    if (!entry) return;
    if (entry.source) entry.source.execute();
    else if ((entry.command ?? "") !== "") Quickshell.execDetached(["sh", "-c", entry.command]);
    closeOverlay();
  }

  // "XF86MonBrightnessUp" -> "Mon Brightness Up", "code:10" -> "1", "mouse:272" -> "Mouse Left".
  // code:N assumes the US layout configured in hyprland.lua (10-19 = number row).
  function formatKey(key) {
    var code = /^code:(\d+)$/.exec(key);
    if (code) {
      var n = parseInt(code[1]);
      if (n >= 10 && n <= 18) return String(n - 9);
      if (n === 19) return "0";
      if (n === 20) return "-";
      if (n === 21) return "=";
      return key;
    }

    var mouse = { "mouse:272": "Mouse Left", "mouse:273": "Mouse Right", "mouse:274": "Mouse Middle" };
    if (mouse[key]) return mouse[key];

    if (key.indexOf("XF86") === 0)
      return key.substring(4).replace(/([a-z0-9])([A-Z])/g, "$1 $2");

    return key;
  }

  function formatKeys(combo) {
    return combo.split("+").map(part => formatKey(part.trim())).join(" + ");
  }

  // Parses `<keys>\t<description>` lines from scripts/keybinds.lua.
  function parseKeybinds(text) {
    return text.split("\n")
      .filter(line => line.indexOf("\t") > 0)
      .map(line => {
        var tab = line.indexOf("\t");
        var keys = formatKeys(line.substring(0, tab));
        var description = line.substring(tab + 1).trim();
        return {
          entry: {
            keys: keys,
            description: description || "(no description)",
            muted: description === ""
          },
          normKeys: normalizeText(keys),
          normDescription: normalizeText(description),
          // Natural order: "workspace 2" before "workspace 10"; undescribed last.
          sortKey: description === ""
            ? "\uffff"
            : description.toLowerCase().replace(/\d+/g, n => n.padStart(6, "0"))
        };
      });
  }

  function keybindScore(cached, tokens) {
    var score = 0;

    for (var i = 0; i < tokens.length; i++) {
      var token = tokens[i];
      var keyScore = 0;
      if ((" " + cached.normKeys + " ").indexOf(" " + token + " ") >= 0) keyScore = 100;
      else if (cached.normKeys.indexOf(token) >= 0)                      keyScore = 30;

      var best = Math.max(textScore(cached.normDescription, token), keyScore);
      if (best === 0) return -1;
      score += best;
    }

    return score;
  }

  function keybindEntries(query) {
    return rankEntries(keybindList, query, keybindScore, (a, b) =>
      a.sortKey < b.sortKey ? -1 : a.sortKey > b.sortKey ? 1 : a.entry.keys.localeCompare(b.entry.keys));
  }

  // =========================================================================
  // 5. System Daemon Bindings (Bluetooth, Audio, MPRIS)
  // =========================================================================
  // qmllint disable unresolved-type
  readonly property var btAdapter: Bluetooth.defaultAdapter
  // qmllint enable unresolved-type
  readonly property bool btEnabled: btAdapter?.enabled ?? false
  readonly property int btConnCount: {
    var devs = btAdapter?.devices?.values ?? [];
    var n = 0;
    for (var i = 0; i < devs.length; i++) {
      if (devs[i]?.connected) n++;
    }
    return n;
  }
  readonly property string btLabel: !btEnabled ? "" : (btConnCount > 0 ? " " + btConnCount : "")
  readonly property color btColor: btEnabled ? colCyan : colMuted

  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink]
  }
  // Battery (laptops): UPower's display device aggregates all batteries. Hidden when there is no battery.
  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: (battery?.isLaptopBattery ?? false) && (battery?.ready ?? true)
  readonly property int batteryPercent: Math.round((battery?.percentage ?? 0) <= 1 ? (battery?.percentage ?? 0) * 100 : battery.percentage)
  readonly property bool charging: battery?.state === UPowerDeviceState.Charging || battery?.state === UPowerDeviceState.FullyCharged
  readonly property string batteryIcon: {
    if (charging) return "\u{f0084}";
    var icons = ["\u{f008e}", "\u{f007a}", "\u{f007b}", "\u{f007c}", "\u{f007d}", "\u{f007e}",
                 "\u{f007f}", "\u{f0080}", "\u{f0081}", "\u{f0082}", "\u{f0079}"];
    return icons[Math.max(0, Math.min(10, Math.round(batteryPercent / 10)))];
  }
  readonly property color batteryColor: charging ? colGreen : (batteryPercent <= 15 ? colRed : (batteryPercent <= 30 ? colYellow : colGreen))

  // Notifications: mako's do-not-disturb mode (SUPER+CTRL+COMMA or click the bell).
  property bool dndEnabled: false

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property int volumeLevel: Math.round((sink?.audio?.volume ?? 0) * 100)
  readonly property bool isMuted: sink?.audio?.muted ?? false

  readonly property var mprisPlayer: {
    var playing = null;
    var paused = null;
    for (var i = 0; i < Mpris.players.values.length; i++) {
      var p = Mpris.players.values[i];
      if (!p.trackTitle && !p.trackArtist) continue;
      if (p?.playbackState === MprisPlaybackState.Playing) {
        if (!playing) playing = p;
      } else if (p?.playbackState === MprisPlaybackState.Paused) {
        if (!paused) paused = p;
      }
    }
    return playing ?? paused ?? null;
  }
  readonly property bool mprisActive: mprisPlayer !== null
  readonly property bool mprisPlaying: mprisPlayer?.playbackState === MprisPlaybackState.Playing
  readonly property string mprisSong: {
    var p = mprisPlayer;
    if (!p) return "";
    var title = p.trackTitle ?? "";
    var artist = p.trackArtist ?? "";
    if (artist && title) return artist + " – " + title;
    return title || artist || "Unknown";
  }
  readonly property string mprisSongShort: {
    var s = mprisSong;
    return s.length > 40 ? s.substring(0, 38) + "…" : s;
  }


  // =========================================================================
  // 6. Native Execution Handlers (CLI Subprocesses)
  // =========================================================================
  TuiProcess { id: bluetuiProc; appId: "bluetui"; program: ["bluetui"] }
  TuiProcess { id: btopProc;    appId: "btop";    program: ["btop"] }
  TuiProcess { id: duaProc;     appId: "dua";     program: ["dua", "i", "/"] }
  TuiProcess { id: impalaProc;  appId: "impala";  program: ["impala"] }
  TuiProcess { id: wiremixProc; appId: "wiremix"; program: ["wiremix"] }

  FileView {
    id: cpuStat
    path: "/proc/stat"
    onLoaded: {
      var parts = text().split("\n")[0].trim().split(/\s+/).slice(1).map(n => parseInt(n) || 0);
      // user nice system idle iowait irq softirq steal
      var idle = parts[3] + parts[4];
      var total = parts.slice(0, 8).reduce((sum, n) => sum + n, 0);

      if (root.lastCpuTotal > 0 && total > root.lastCpuTotal) {
        var dTotal = total - root.lastCpuTotal;
        var dIdle = idle - root.lastCpuIdle;
        root.cpuUsage = Math.round(100 * (dTotal - dIdle) / dTotal);
      }

      root.lastCpuTotal = total;
      root.lastCpuIdle = idle;
    }
  }

  FileView {
    id: memInfo
    path: "/proc/meminfo"
    onLoaded: {
      var total = parseInt(/MemTotal:\s+(\d+)/.exec(text())?.[1]) || 1;
      var available = parseInt(/MemAvailable:\s+(\d+)/.exec(text())?.[1]) || 0;
      root.memUsage = Math.round(100 * (total - available) / total);
    }
  }

  Process {
    id: cpuTempProc
    command: ["sh", root.scriptDir + "/cpu-temp.sh"]
    running: true
    stdout: SplitParser {
      onRead: data => {
        if (data && data.trim()) {
          root.cpuTemp = data.trim();
        }
      }
    }
  }

  Process {
    id: diskProc
    command: ["df", "--output=pcent", "/"]
    running: true
    stdout: SplitParser {
      onRead: data => {
        // Skips the "Use%" header line.
        if (/^\s*\d+%/.test(data)) root.diskUsage = parseInt(data);
      }
    }
  }

  Process {
    id: windowProc
    command: ["sh", "-c", "hyprctl activewindow -j | jq -r '.title // \"Desktop\"'"]
    running: true
    stdout: SplitParser {
      onRead: data => {
        if (data !== undefined) {
          root.activeWindow = data.trim();
        }
      }
    }
  }

  Process {
    id: netProc
    command: ["sh", root.scriptDir + "/net-status.sh"]
    running: true
    stdout: SplitParser {
      onRead: data => {
        if (!data || !data.trim()) return;
        var network = data.trim();
        if (network === "offline") {
          root.netType = "offline";
          root.netName = "";
        } else {
          let parts = network.split(":");
          root.netType = parts[0];
          root.netName = parts[1];
        }
      }
    }
  }

  // mako do-not-disturb: read the current mode list, toggle on click.
  Process {
    id: dndProc
    command: ["makoctl", "mode"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.dndEnabled = text.split("\n").indexOf("do-not-disturb") >= 0
    }
  }

  Process {
    id: dndToggleProc
    command: ["makoctl", "mode", "-t", "do-not-disturb"]
    onExited: dndProc.running = true
  }

  // Lists every hl.bind() in the Hyprland config (see scripts/keybinds.lua).
  Process {
    id: keybindProc
    command: ["lua", root.scriptDir + "/keybinds.lua", root.hyprConfig]
    stdout: StdioCollector {
      onStreamFinished: root.keybindList = root.parseKeybinds(text)
    }
    stderr: StdioCollector {
      onStreamFinished: if (text) console.warn("keybinds.lua: " + text.trim())
    }
  }

  // Polling Event Hooks
  Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      cpuStat.reload();
      memInfo.reload();
      cpuTempProc.running = true;
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: diskProc.running = true
  }

  Timer {
    interval: 5000
    repeat: true
    running: true
    onTriggered: {
      netProc.running = true;
      dndProc.running = true;   // picks up changes made with the keyboard shortcut
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activewindow" || event.name === "activewindowv2" || event.name === "windowtitlev2")
        windowProc.running = true;
    }
  }

  // Safety-net poll in case a window event (above) is ever missed.
  Timer {
    interval: 3000
    repeat: true
    running: true
    onTriggered: windowProc.running = true
  }

  IpcHandler {
    target: "launcher"
    function open(): void { root.openOverlay("launcher"); }
    function close(): void { root.closeOverlay(); }
    function toggle(): void { root.toggleOverlay("launcher"); }
  }

  IpcHandler {
    target: "keybinds"
    function open(): void { root.openOverlay("keybinds"); }
    function close(): void { root.closeOverlay(); }
    function toggle(): void { root.toggleOverlay("keybinds"); }
  }

  IpcHandler {
    target: "bar"
    function toggle(): void { root.barVisible = !root.barVisible; }
  }

  IpcHandler {
    target: "calendar"
    function toggle(): void { root.toggleCalendar(); }
  }

  // =========================================================================
  // 7. Wallpaper (one background-layer window per screen; replaces swaybg)
  // =========================================================================
  Variants {
    model: Quickshell.screens

    // qmllint disable uncreatable-type
    PanelWindow {
      // qmllint enable uncreatable-type
      required property var modelData
      screen: modelData
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.namespace: "wallpaper"
      exclusionMode: ExclusionMode.Ignore
      color: root.colBg
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      Image {
        anchors.fill: parent
        source: "file://" + root.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        sourceSize.width: parent.width     // decode at screen size, not the 7680px source
        sourceSize.height: parent.height
      }
    }
  }

  // =========================================================================
  // 8. Status Bar Component Matrix
  // =========================================================================
  Variants {
    model: Quickshell.screens

    // qmllint disable uncreatable-type
    PanelWindow {
      // qmllint enable uncreatable-type
      id: bar
      required property var modelData
      screen: modelData
      visible: root.barVisible
      implicitHeight: 42
      // Narrow screens (e.g. a scaled laptop panel) drop the DND pill and network name so the
      // right section doesn't run into the clock. Logical pixels, so scaling is accounted for.
      readonly property bool compact: modelData.width < 1920
      color: "transparent"
      anchors {
        top: true
        left: true
        right: true
      }

      Item {
        id: barRootItem
        anchors.fill: parent

        // LEFT MODULE PLACEMENT
        RowLayout {
          id: leftSection
          anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: 10
          }

          Pill {
            sidePadding: 20
            Repeater {
              model: 5
              delegate: Item {
                id: delegateItem
                required property int index
                property var workspace: Hyprland.workspaces.values.find(w => w.id === (index + 1))
                property bool isActive: Hyprland.focusedWorkspace?.id === (index + 1)

                implicitWidth: 20
                implicitHeight: 20

                BarText {
                  text: delegateItem.index + 1
                  color: (delegateItem.isActive || delegateItem.workspace) ? root.colCyan : root.colMuted
                  font.bold: true
                  anchors.centerIn: parent
                }

                Rectangle {
                  width: 12
                  height: 2
                  radius: 1
                  color: delegateItem.isActive ? root.colCyan : "transparent"
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + (delegateItem.index + 1) + " })")
                }
              }
            }
          }

          Pill {
            visible: root.mprisActive
            spacing: 8

            BarText {
              text: "󰒮"
              color: (root.mprisPlayer?.canGoPrevious ?? false) ? root.colPurple : root.colMuted
              font.pixelSize: root.fontSize + 1
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.mprisPlayer?.previous()
              }
            }

            BarText {
              text: root.mprisPlaying ? "󰏤" : "󰐊"
              color: root.colPurple
              font.pixelSize: root.fontSize + 1
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.mprisPlayer?.togglePlaying()
              }
            }

            BarText {
              text: "󰒭"
              color: (root.mprisPlayer?.canGoNext ?? false) ? root.colPurple : root.colMuted
              font.pixelSize: root.fontSize + 1
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.mprisPlayer?.next()
              }
            }

            BarText {
              text: root.mprisSongShort
              color: root.colPurple
              font.bold: true
              maximumLineCount: 1
              leftPadding: 8
            }
          }

          Pill {
            implicitWidth: Math.min(windowTitle.implicitWidth + sidePadding, 320)
            BarText {
              id: windowTitle
              text: root.activeWindow
              color: root.colYellow
              font.bold: true
              maximumLineCount: 1
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
        }

        // CENTER MODULE PLACEMENT
        Pill {
          id: clockPill
          anchors.centerIn: parent
          mouse.enabled: true
          mouse.cursorShape: Qt.PointingHandCursor
          mouse.onClicked: root.toggleCalendar()

          BarText {
            text: Qt.formatDateTime(clock.date, "ddd MMM dd HH:mm")
            color: root.colCyan
            font.bold: true
            font.features: {
              "tnum": true
            }
          }
        }

        // RIGHT MODULE PLACEMENT
        RowLayout {
          id: rightSection
          spacing: 5
          layoutDirection: Qt.RightToLeft
          anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
            rightMargin: 6
          }

          Pill {
            BarText {
              text: root.isMuted ? "󰖁 0%" : "󰕾 " + root.volumeLevel + "%"
              color: root.colPurple
              font.bold: true

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                property int scrollDelta: 0
                onClicked: mouse => {
                  if (mouse.button === Qt.RightButton) {
                    if (root.sink?.audio) {
                      root.sink.audio.muted = !root.sink.audio.muted;
                    }
                  } else {
                    wiremixProc.running = true;
                  }
                }
                onWheel: wheel => {
                  scrollDelta += wheel.angleDelta.y;
                  if (Math.abs(scrollDelta) >= 120) {
                    if (root.sink?.audio) {
                      root.sink.audio.volume = scrollDelta > 0
                        ? Math.min(1.0, root.sink.audio.volume + 0.05)
                        : Math.max(0.0, root.sink.audio.volume - 0.05);
                    }
                    scrollDelta = 0;
                  }
                }
              }
            }
          }

          MetricPill {
            visible: root.netType !== ""
            labelColor: root.colBlue
            onClicked: impalaProc.running = true
            label: {
              var name = bar.compact ? "" : " " + root.netName;
              if (root.netType === "wifi") return "󰤨" + name;
              if (root.netType === "ethernet") return "󰈀" + name;
              return "offline";
            }
          }

          MetricPill {
            label: (root.btEnabled ? "󰂯" : "󰂲") + root.btLabel
            labelColor: root.btColor
            onClicked: bluetuiProc.running = true
          }

          MetricPill {
            label: "󰋊 " + root.diskUsage + "%"
            labelColor: root.colBlue
            onClicked: duaProc.running = true
          }

          MetricPill {
            label: "󰍛 " + root.memUsage + "%"
            labelColor: root.colCyan
            onClicked: btopProc.running = true
          }

          MetricPill {
            label: "󰻠 " + root.cpuUsage + "%"
            labelColor: root.colYellow
            onClicked: btopProc.running = true
          }

          MetricPill {
            label: " " + root.cpuTemp + (root.cpuTemp === "--" ? "" : "°C")
            labelColor: root.colRed
            onClicked: btopProc.running = true
          }

          MetricPill {
            visible: root.hasBattery
            label: root.batteryIcon + " " + root.batteryPercent + "%"
            labelColor: root.batteryColor
          }

          MetricPill {
            visible: !bar.compact
            label: root.dndEnabled ? "\u{f009b}" : "\u{f009a}"
            labelColor: root.dndEnabled ? root.colMuted : root.colPurple
            onClicked: dndToggleProc.running = true
          }

          Pill {
            visible: trayRepeater.count > 0
            sidePadding: 15

            Repeater {
              id: trayRepeater
              model: SystemTray.items
              delegate: Item {
                id: trayDelegate
                required property var modelData
                property var trayItem: modelData
                implicitWidth: 20
                implicitHeight: 20
                Layout.alignment: Qt.AlignVCenter

                Image {
                  anchors.fill: parent
                  source: trayDelegate.trayItem.icon ?? ""
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                  visible: source !== ""
                }

                BarText {
                  visible: !trayDelegate.trayItem.icon
                  anchors.centerIn: parent
                  text: (trayDelegate.trayItem.title ?? "?").charAt(0).toUpperCase()
                  font.pixelSize: root.fontSize - 1
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                      trayDelegate.trayItem.activate();
                    } else {
                      trayMenuAnchor.open();
                    }
                  }
                }

                // qmllint disable missing-type
                QsMenuAnchor {
                  id: trayMenuAnchor
                  menu: trayDelegate.trayItem.menu
                  anchor.item: trayDelegate
                  anchor.edges: Edges.Bottom
                  anchor.gravity: Edges.Bottom
                }
                // qmllint enable missing-type
              }
            }
          }
        }
      }

      // POPUP CALENDAR MODULE
      PopupWindow {
        id: calendarPopup
        visible: root.calendarOpen
        grabFocus: true
        anchor.item: clockPill
        anchor.margins.bottom: 6
        // qmllint disable missing-type
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.adjustment: PopupAdjustment.SlideX
        // qmllint enable missing-type

        onVisibleChanged: if (visible) Qt.callLater(() => calendarBody.forceActiveFocus())
        onClosed: root.closeCalendar()

        implicitWidth: 320
        implicitHeight: 356
        color: "transparent"

        Rectangle {
          id: calendarBody
          anchors.fill: parent
          focus: true
          color: root.colPill
          radius: 10
          border.color: root.colBorderStrong
          border.width: 1
          Keys.onEscapePressed: root.closeCalendar()

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 24
                radius: 8
                color: prevMonthArea.containsMouse ? root.colFillHover : root.colFillSubtle
                border.color: root.colBorderMed
                border.width: 1

                BarText {
                  text: "‹"
                  font.pixelSize: root.fontSize + 4
                  font.bold: true
                  anchors.centerIn: parent
                }

                MouseArea {
                  id: prevMonthArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showCalendarMonth(root.calendarYear, root.calendarMonth - 1)
                }
              }

              BarText {
                Layout.fillWidth: true
                text: new Date(root.calendarYear, root.calendarMonth, 1).toLocaleDateString(Qt.locale(), "MMMM yyyy")
                color: root.colCyan
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: root.fontSize + 2
                font.bold: true
              }

              Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 24
                radius: 8
                color: nextMonthArea.containsMouse ? root.colFillHover : root.colFillSubtle
                border.color: root.colBorderMed
                border.width: 1

                BarText {
                  text: "›"
                  font.pixelSize: root.fontSize + 4
                  font.bold: true
                  anchors.centerIn: parent
                }

                MouseArea {
                  id: nextMonthArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showCalendarMonth(root.calendarYear, root.calendarMonth + 1)
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 4
              Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]
                delegate: BarText {
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: 22
                  text: modelData
                  color: root.colMuted
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  font.pixelSize: root.fontSize - 1
                  font.bold: true
                }
              }
            }

            GridLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              columns: 7
              columnSpacing: 4
              rowSpacing: 4
              Repeater {
                model: root.generateCalendarDays(root.calendarYear, root.calendarMonth, clock.date)
                delegate: Rectangle {
                  id: day
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.minimumHeight: 36
                  radius: 8
                  color: modelData.today ? root.colCyan : root.colFillFaint
                  border.color: modelData.today ? "transparent" : root.colBorderSoft
                  border.width: 1
                  opacity: modelData.month ? 1.0 : 0.35

                  BarText {
                    anchors.centerIn: parent
                    text: day.modelData.day
                    color: day.modelData.today ? root.colBg : root.colFg
                    font.bold: day.modelData.today
                  }
                }
              }
            }
          }
        }
      }
    }
  }


  // =========================================================================
  // 9. Floating Overlays (App Launcher & Keybind Search)
  // =========================================================================
  PickerWindow {
    id: launcherWindow
    open: root.launcherOpen
    placeholder: "Run"
    entries: root.launcherEntries(query)
    onActivated: entry => root.launchEntry(entry)
    onDismissed: root.closeOverlay()
  }

  PickerWindow {
    id: keybindsWindow
    open: root.keybindsOpen
    placeholder: "Search keyboard shortcuts"
    entries: root.keybindEntries(query)
    primaryRole: "keys"
    secondaryRole: "description"
    primaryWidth: 260
    panelWidth: 900
    panelHeight: 520
    onDismissed: root.closeOverlay()
  }
}
