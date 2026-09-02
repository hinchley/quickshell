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

  property string fontFamily: "JetBrainsMono Nerd Font"
  property int fontSize: 13

  // Network Interfaces
  property string ethInterface:  "eno1"
  property string wlanInterface: "wlan0"

  readonly property string scriptDir: Quickshell.shellDir + "/scripts"

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

  property bool calendarOpen: false
  property date calendarBaseDate: new Date()
  property int calendarMonth: calendarBaseDate.getMonth()
  property int calendarYear: calendarBaseDate.getFullYear()

  property string netType: ""
  property string netName: ""

  property bool launcherOpen: false
  property string launcherQuery: ""

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
    "uuctl",
    "UXterm",
    "Vim",
    "wiremix",
    "XTerm"
  ]

  // =========================================================================
  // 3. UI Reusable Building Blocks
  // =========================================================================
  component BarText: Text {
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    color: root.colFg
  }

  // =========================================================================
  // 4. Engine & Context Evaluation Methods
  // =========================================================================
  function toggleCalendar() {
    calendarOpen = !calendarOpen;
    if (calendarOpen) calendarBaseDate = new Date();
  }

  function closeCalendar() {
    calendarOpen = false;
  }

  function generateCalendarDays(year, month) {
    var days = [];
    var first = new Date(year, month, 1).getDay();
    var index = first === 0 ? 6 : first - 1;
    var today = new Date().toDateString();

    for (var i = 0; i < 42; i++) {
      var date = new Date(year, month, 1 - index + i);
      days.push({
        day: date.getDate(),
        month: date.getMonth() === month,
        today: date.toDateString() === today
      });
    }

    return days;
  }

  function normalizeText(value) {
    return (value ?? "")
      .toString()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  }

  function desktopCommand(entry) {
    return entry?.execString
      ?? entry?.command?.join(" ")
      ?? entry?.id
      ?? "";
  }

  function launcherBlacklistMatches(entry) {
    if (!launcherBlacklist || launcherBlacklist.length === 0) return false;

    var item = [
      entry.name ?? "",
      entry.id ?? "",
      desktopCommand(entry),
      entry.comment
      ?? ""
    ].join(" ")

    var haystack = normalizeText(item);

    for (var i = 0; i < launcherBlacklist.length; i++) {
      var needle = normalizeText(launcherBlacklist[i]);
      if (needle !== "" && haystack.indexOf(needle) >= 0) return true;
    }

    return false;
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

  function launcherScore(cached, query) {
    var q = normalizeText(query);
    if (q === "") return 1;

    var tokens = q.split(/\s+/).filter(token => token.length > 0);
    var score = 0;

    for (var i = 0; i < tokens.length; i++) {
      var token = tokens[i];
      if (cached.normName === token)                      score += 120;
      else if (cached.normName.indexOf(token) === 0)      score += 90;
      else if (cached.normName.indexOf(" " + token) >= 0) score += 70;
      else if (cached.normName.indexOf(token) >= 0)       score += 55;
      else if (cached.normCommand.indexOf(token) >= 0)    score += 35;
      else if (cached.normKeywords.indexOf(token) >= 0)   score += 25;
      else if (cached.normCategories.indexOf(token) >= 0) score += 15;
      else if (cached.normComment.indexOf(token) >= 0)    score += 8;
      else return -1;
    }

    return score;
  }

  function launcherEntries() {
    var q = launcherQuery;
    return launcherBaseCache
      .map(cached => ({
        entry: cached.entry,
        score: launcherScore(cached, q)
      })).filter(match =>
        match.score >= 0
      ).sort((a, b) =>
        b.score - a.score ||
        a.entry.name.localeCompare(b.entry.name)
      ).map(match =>
        match.entry
      );
  }

  function openLauncher() {
    launcherOpen = true;
    launcherQuery = "";
    launcherInput.text = "";
  }

  function closeLauncher() {
    launcherOpen = false;
    launcherQuery = "";
    launcherInput.text = "";
  }

  function toggleLauncher() {
    if (launcherOpen) closeLauncher();
    else openLauncher();
  }

  function launchEntry(entry) {
    if (!entry) return;
    if (entry.source) { entry.source.execute();
    } else if ((entry.command ?? "") !== "") {
      commandLauncher.command = ["sh", "-c", entry.command];
      commandLauncher.running = true;
    }
    closeLauncher();
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
  Process {
    id: bluetuiProc
    command: ["foot", "--app-id=org.hinchley.bluetui", "-e", "bluetui"]
    running: false
  }

  Process {
    id: btopProc
    command: ["foot", "--app-id=org.hinchley.btop", "-e", "btop"]
    running: false
  }

  Process {
    id: duaProc
    command: ["foot", "--app-id=org.hinchley.dua", "-e", "dua", "i", "/"]
    running: false
  }

  Process {
    id: impalaProc
    command: ["foot", "--app-id=org.hinchley.impala", "-e", "impala"]
    running: false
  }

  Process {
    id: stuiProc
    command: ["foot", "--app-id=org.hinchley.stui", "-e", "s-tui"]
    running: false
  }

  Process {
    id: wiremixProc
    command: ["foot", "--app-id=org.hinchley.wiremix", "-e", "wiremix"]
    running: false
  }

  Process {
    id: commandLauncher
    running: false
  }

  Process {
    id: cpuProc
    command: ["sh", "-c", "head -1 /proc/stat"]
    running: true
    stdout: SplitParser {
      onRead: data => {
        if (!data) return;
        var parts = data.trim().split(/\s+/);
        var user    = parseInt(parts[1]) || 0;
        var nice    = parseInt(parts[2]) || 0;
        var system  = parseInt(parts[3]) || 0;
        var idle    = parseInt(parts[4]) || 0;
        var iowait  = parseInt(parts[5]) || 0;
        var irq     = parseInt(parts[6]) || 0;
        var softirq = parseInt(parts[7]) || 0;
        var steal   = parseInt(parts[8]) || 0;

        var idleTime = idle + iowait;
        var total = user + nice + system + idleTime + irq + softirq + steal;

        if (root.lastCpuTotal > 0) {
          var dTotal = total - root.lastCpuTotal;
          var dIdle = idleTime - root.lastCpuIdle;
          if (dTotal > 0) {
            root.cpuUsage = Math.round(100 * (dTotal - dIdle) / dTotal);
          }
        }

        root.lastCpuTotal = total;
        root.lastCpuIdle = idleTime;
      }
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
    id: memProc
    command: ["sh", "-c", "free | grep '^Mem'"]
    running: true
    stdout: SplitParser {
      onRead: data => {
        if (!data) return;
        var parts = data.trim().split(/\s+/);
        var total = parseInt(parts[1]) || 1;
        var available = parseInt(parts[6]) || 0;
        root.memUsage = Math.round(100 * (total - available) / total);
      }
    }
  }

  Process {
    id: diskProc
    command: ["sh", "-c", "df / | tail -1"]
    running: true
    stdout: SplitParser {
      onRead: data => {
        if (!data) return;
        var parts = data.trim().split(/\s+/);
        root.diskUsage = parseInt((parts[4] || "0%").replace('%', '')) || 0;
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
    command: ["sh", root.scriptDir + "/net-status.sh", root.ethInterface, root.wlanInterface]
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

  // Polling Event Hooks
  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      cpuProc.running = true;
      cpuTempProc.running = true;
      memProc.running = true;
      diskProc.running = true;
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: true
    onTriggered: netProc.running = true
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
    function open(): void {
      root.openLauncher();
    }
    function close(): void {
      root.closeLauncher();
    }
    function toggle(): void {
      root.toggleLauncher();
    }
  }

  // =========================================================================
  // 7. Status Bar Component Matrix
  // =========================================================================
  Variants {
    model: Quickshell.screens

    // qmllint disable uncreatable-type
    PanelWindow {
      // qmllint enable uncreatable-type
      id: bar
      required property var modelData
      screen: modelData
      visible: true
      implicitHeight: 42
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
                  color: delegateItem.isActive ? root.colCyan : (delegateItem.workspace ? root.colCyan : root.colMuted)
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
            id: clockLabel
            text: Qt.formatDateTime(new Date(), "ddd MMM dd HH:mm")
            color: root.colCyan
            font.bold: true
            font.features: {
              "tnum": true
            }

            Timer {
              interval: 1000
              running: true
              repeat: true
              onTriggered: clockLabel.text = Qt.formatDateTime(new Date(), "ddd MMM dd HH:mm")
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
              if (root.netType === "wifi") return "󰤨 " + root.netName;
              if (root.netType === "ethernet") return "󰈀 " + root.netName;
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
            onClicked: stuiProc.running = true
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
                  id: trayMA
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
                  onClicked: root.calendarBaseDate = new Date(root.calendarYear, root.calendarMonth - 1, 1)
                }
              }

              BarText {
                Layout.fillWidth: true
                text: root.calendarBaseDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
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
                  onClicked: root.calendarBaseDate = new Date(root.calendarYear, root.calendarMonth + 1, 1)
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
                model: root.generateCalendarDays(root.calendarYear, root.calendarMonth)
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

      IpcHandler {
        target: "bar"
        function toggle(): void {
          calendarPopup.visible = !calendarPopup.visible;
        }
      }
    }
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

  // =========================================================================
  // 8. Unmanaged Floating Launcher Surface Layer
  // =========================================================================
  // qmllint disable uncreatable-type
  PanelWindow {
    // qmllint enable uncreatable-type
    id: launcherWindow
    visible: root.launcherOpen

    // Native Wayland Layer Shell specifications for Quickshell 0.3.0
    WlrLayershell.layer: WlrLayer.Overlay
    focusable: true
    color: "transparent"
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Safe full-screen transparent bounding box click-dismiss handler
    MouseArea {
      anchors.fill: parent
      onClicked: root.closeLauncher()
    }

    onVisibleChanged: {
      if (visible) {
        launcherInput.forceActiveFocus();
        launcherList.currentIndex = launcherList.count > 0 ? 0 : -1;
      }
    }

    function launchSelected() {
      if (launcherList.currentIndex < 0) return;
      root.launchEntry(launcherFiltered.values[launcherList.currentIndex]);
    }

    // Centered Content Framework Layout Container Box
    Rectangle {
      anchors.centerIn: parent
      width: 560
      height: 420
      color: root.colPill
      radius: 10
      border.color: root.colBorderStrong
      border.width: 1

      // Block click-propagation to prevent overlay dismiss action inside the container
      MouseArea {
        anchors.fill: parent
        onClicked: mouse => mouse.accepted = true
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
          border.color: launcherInput.activeFocus ? root.colCyan : root.colBorderMed
          border.width: 1

          TextField {
            id: launcherInput
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            text: root.launcherQuery
            placeholderText: "Run"
            color: root.colFg
            placeholderTextColor: root.colMuted
            selectionColor: root.colCyan
            selectedTextColor: root.colBg
            font.family: root.fontFamily
            font.pixelSize: root.fontSize + 3
            padding: 0
            verticalAlignment: TextInput.AlignVCenter
            background: Rectangle {
              color: "transparent"
            }

            onTextChanged: {
              root.launcherQuery = text;
              Qt.callLater(() => launcherList.currentIndex = launcherList.count > 0 ? 0 : -1);
            }

            Keys.onEscapePressed: root.closeLauncher()
            Keys.onPressed: event => {
              var ctrl = event.modifiers & Qt.ControlModifier;
              if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && ctrl)) {
                event.accepted = true;
                if (launcherList.currentIndex > 0) {
                  launcherList.currentIndex--;
                }
              } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && ctrl)) {
                event.accepted = true;
                if (launcherList.currentIndex < launcherList.count - 1) {
                  launcherList.currentIndex++;
                }
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                event.accepted = true;
                launcherWindow.launchSelected();
              } else if (event.key === Qt.Key_C && ctrl) {
                event.accepted = true;
                root.closeLauncher();
              }
            }
          }
        }

        ScriptModel {
          id: launcherFiltered
          values: root.launcherEntries()
          onValuesChanged: Qt.callLater(() => launcherList.currentIndex = launcherList.count > 0 ? 0 : -1)
        }

        ListView {
          id: launcherList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: launcherFiltered.values
          currentIndex: count > 0 ? 0 : -1
          keyNavigationWraps: true
          boundsBehavior: Flickable.StopAtBounds
          highlightMoveDuration: 80
          highlight: Rectangle {
            radius: 8
            color: Qt.rgba(root.colCyan.r, root.colCyan.g, root.colCyan.b, 0.18)
            border.color: Qt.rgba(root.colCyan.r, root.colCyan.g, root.colCyan.b, 0.28)
            border.width: 1
          }

          delegate: Item {
            id: launcherEntry
            required property var modelData
            required property int index
            width: ListView.view.width
            height: 46

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: launcherList.currentIndex = launcherEntry.index
              onDoubleClicked: launcherWindow.launchSelected()
            }

            Column {
              spacing: 2
              anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 12
                rightMargin: 12
              }

              BarText {
                width: parent.width
                text: launcherEntry.modelData.name
                color: launcherEntry.ListView.isCurrentItem ? root.colCyan : root.colFg
                font.pixelSize: root.fontSize + 1
                font.bold: launcherEntry.ListView.isCurrentItem
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }
          }

          Keys.onEscapePressed: root.closeLauncher()
          Keys.onReturnPressed: launcherWindow.launchSelected()
          Keys.onEnterPressed: launcherWindow.launchSelected()
        }

        BarText {
          visible: launcherFiltered.values.length === 0
          Layout.fillWidth: true
          text: "No matches"
          color: root.colMuted
          horizontalAlignment: Text.AlignHCenter
          font.bold: true
        }
      }
    }
  }
}
