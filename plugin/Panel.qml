import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// ArchAlarm '99 — a real nftables-backed inbound firewall wearing a
// ZoneAlarm/BlackICE-era costume. The backend (omarchy-archalarm / -apply /
// -monitor) does the actual work; this file is purely display + the on/off
// click, polling ~/.local/state/omarchy/archalarm/status.json via the CLI.
Panel {
  id: root
  moduleName: "alexander.archalarm"
  ipcTarget: "alexander.archalarm"

  readonly property string appVersion: "1.5.9"
  property var status: Model.defaultStatus()
  property bool toggling: false
  property bool showPorts: false
  property bool showSockets: false
  property bool showTopOffenders: false
  property bool showBanlist: false
  property bool showWhitelist: false

  readonly property bool archalarmEnabled: status.enabled === true
  readonly property int threatLevel: Number(status.threatLevel) || 0

  // ---------------------------------------------------------------- theme
  property string themeName: "archalarm"
  property bool showSettings: false

  readonly property var _palette: root.themeName === "system"
    ? {
        bg: Color.background, border: Color.muted,
        calm: Color.accent, elevated: Color.urgent, alert: Color.urgent,
        off: Color.muted, dim: Color.foreground, faint: Color.muted
      }
    : Model.themePalette(root.themeName)

  readonly property color colOff: root._palette.off
  readonly property color colCalm: root._palette.calm
  readonly property color colElevated: root._palette.elevated
  readonly property color colAlert: root._palette.alert
  readonly property color crtBg: root._palette.bg
  readonly property color crtBorder: root._palette.border
  readonly property color dimText: root._palette.dim
  readonly property color faintText: root._palette.faint

  function setTheme(name) {
    root.themeName = name
    themeSettingsFile.setText(JSON.stringify({ theme: name }))
  }

  FileView {
    id: themeSettingsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/archalarm/panel-settings.json"
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (parsed && typeof parsed.theme === "string") root.themeName = parsed.theme
      } catch (e) {}
    }
  }

  function setKnownSafe(value) {
    if (knownSafeProc.running) return
    knownSafeProc.command = ["omarchy-archalarm", "knownsafe", value]
    knownSafeProc.running = true
  }

  Process {
    id: knownSafeProc
    running: false
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: knownSafeStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = String(knownSafeStderr.text || "Known-safe toggle failed").trim().split("\n").pop()
        errorClearTimer.restart()
      }
      root.refresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Fixed traffic-light colors on purpose, independent of the cosmetic
  // theme — same convention as the threat meter and the status button:
  // green/yellow/red is a safety signal, not a style choice.
  readonly property color iconBaseColor: {
    if (!root.archalarmEnabled) return "#5a5a5a"
    if (root.threatLevel >= 2) return "#ff1a1a"
    if (root.threatLevel >= 1) return "#ffee00"
    return "#39ff14"
  }

  property bool blinkPhase: false
  Timer {
    interval: root.archalarmEnabled ? (root.threatLevel >= 2 ? 220 : root.threatLevel >= 1 ? 500 : 900) : 1400
    running: true
    repeat: true
    onTriggered: root.blinkPhase = !root.blinkPhase
  }

  readonly property real iconOpacity: {
    if (!root.archalarmEnabled) return 0.55
    if (root.threatLevel >= 1) return root.blinkPhase ? 1.0 : 0.35
    return root.blinkPhase ? 1.0 : 0.75
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  Timer {
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    running: false
    command: ["omarchy-archalarm", "status"]
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
      onStreamFinished: {
        root.status = Model.parseStatus(text)
        if (root.modeSwitching && root.status.mode === root.pendingMode) {
          root.modeSwitching = false
          root.pendingMode = ""
        }
      }
    }
  }

  property string lastError: ""

  function toggleFirewall() {
    if (toggleProc.running) return
    root.toggling = true
    root.lastError = ""
    toggleProc.command = ["omarchy-archalarm", "toggle"]
    toggleProc.running = true
  }

  Timer {
    id: errorClearTimer
    interval: 6000
    repeat: false
    onTriggered: root.lastError = ""
  }

  Process {
    id: toggleProc
    running: false
    command: []
    stdout: StdioCollector { id: toggleStdout; waitForEnd: true }
    stderr: StdioCollector { id: toggleStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.toggling = false
      if (exitCode !== 0) {
        var msg = String(toggleStderr.text || toggleStdout.text || "").trim().split("\n").pop()
        root.lastError = msg !== "" ? msg : "Toggle failed (exit " + exitCode + ")"
        errorClearTimer.restart()
      }
      root.refresh()
    }
  }

  // ---------------------------------------------------------- ban hammer
  function banIp(ip) {
    if (!ip || ip === "?" || banProc.running) return
    banProc.command = ["omarchy-archalarm", "ban", ip]
    banProc.running = true
  }

  function unbanIp(ip) {
    if (!ip || banProc.running) return
    banProc.command = ["omarchy-archalarm", "unban", ip]
    banProc.running = true
  }

  Process {
    id: banProc
    running: false
    command: []
    stdout: StdioCollector { id: banStdout; waitForEnd: true }
    stderr: StdioCollector { id: banStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var msg = String(banStderr.text || banStdout.text || "").trim().split("\n").pop()
        root.lastError = msg !== "" ? msg : "Ban/unban failed (exit " + exitCode + ")"
        errorClearTimer.restart()
      }
      root.refresh()
    }
  }

  // ------------------------------------------------------------- whitelist
  function trustIp(ip) {
    if (!ip || ip === "?" || trustProc.running) return
    trustProc.command = ["omarchy-archalarm", "trust", ip]
    trustProc.running = true
  }

  function untrustIp(ip) {
    if (!ip || trustProc.running) return
    trustProc.command = ["omarchy-archalarm", "untrust", ip]
    trustProc.running = true
  }

  Process {
    id: trustProc
    running: false
    command: []
    stdout: StdioCollector { id: trustStdout; waitForEnd: true }
    stderr: StdioCollector { id: trustStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var msg = String(trustStderr.text || trustStdout.text || "").trim().split("\n").pop()
        root.lastError = msg !== "" ? msg : "Trust/untrust failed (exit " + exitCode + ")"
        errorClearTimer.restart()
      }
      root.refresh()
    }
  }

  // ------------------------------------------------------------ investigate
  property string investigateIp: ""
  property bool investigating: false
  property string investigateReport: ""
  property string investigateError: ""

  function investigate(ip) {
    if (!ip || ip === "?" || investigateProc.running) return
    root.investigateIp = ip
    root.investigating = true
    root.investigateReport = ""
    root.investigateError = ""
    investigateProc.command = ["omarchy-archalarm", "investigate", ip]
    investigateProc.running = true
  }

  function closeInvestigation() {
    root.investigateIp = ""
    root.investigateReport = ""
    root.investigateError = ""
  }

  Process {
    id: investigateProc
    running: false
    command: []
    stdout: StdioCollector { id: investigateStdout; waitForEnd: true }
    stderr: StdioCollector { id: investigateStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.investigating = false
      if (exitCode !== 0) {
        root.investigateError = String(investigateStderr.text || investigateStdout.text || "Investigation failed").trim()
      } else {
        root.investigateReport = String(investigateStdout.text || "").trim()
      }
    }
  }

  // ---------------------------------------------------- incident report
  property string lastReportPath: ""
  property string lastReportError: ""

  function exportReport() {
    if (reportProc.running) return
    root.lastReportPath = ""
    root.lastReportError = ""
    reportProc.command = ["omarchy-archalarm", "report"]
    reportProc.running = true
  }

  Timer {
    id: reportClearTimer
    interval: 8000
    repeat: false
    onTriggered: { root.lastReportPath = ""; root.lastReportError = "" }
  }

  Process {
    id: reportProc
    running: false
    command: []
    stdout: StdioCollector { id: reportStdout; waitForEnd: true }
    stderr: StdioCollector { id: reportStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastReportError = String(reportStderr.text || "Report export failed").trim().split("\n").pop()
      } else {
        root.lastReportPath = String(reportStdout.text || "").trim()
      }
      reportClearTimer.restart()
    }
  }

  // -------------------------------------------------------- response mode
  property bool modeSwitching: false
  property string pendingMode: ""

  function cycleMode() {
    if (modeProc.running || root.modeSwitching) return
    var next = root.status.mode === "reject" ? "stealth" : "reject"
    root.pendingMode = next
    root.modeSwitching = true
    modeSwitchTimeout.restart()
    modeProc.command = ["omarchy-archalarm", "mode", next]
    modeProc.running = true
  }

  // Safety net: if status never confirms the switch (daemon hiccup, mode
  // set while disarmed, etc.) don't leave the scan bar running forever.
  Timer {
    id: modeSwitchTimeout
    interval: 8000
    repeat: false
    onTriggered: {
      root.modeSwitching = false
      root.pendingMode = ""
    }
  }

  // Shared scanning loading-bar animation, reused for both a mode switch
  // and an investigation in flight.
  property int scanIndex: 0
  property int scanDir: 1
  Timer {
    id: scanTimer
    interval: 80
    running: root.modeSwitching || root.investigating
    repeat: true
    onTriggered: {
      root.scanIndex += root.scanDir
      if (root.scanIndex >= 7) { root.scanIndex = 7; root.scanDir = -1 }
      else if (root.scanIndex <= 0) { root.scanIndex = 0; root.scanDir = 1 }
    }
  }

  Process {
    id: modeProc
    running: false
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: modeStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = String(modeStderr.text || "Mode switch failed").trim().split("\n").pop()
        errorClearTimer.restart()
        modeSwitchTimeout.stop()
        root.modeSwitching = false
        root.pendingMode = ""
      }
      root.refresh()
    }
  }

  // -------------------------------------------------------- update check
  // The backend script (omarchy-archalarm-update) does its own gating —
  // it only actually hits GitHub once per boot or once per 24h, so it's
  // safe to call this from the panel far more often than that.
  property var updateInfo: Model.defaultUpdateInfo()

  function checkForUpdate() {
    if (!updateCheckProc.running) updateCheckProc.running = true
  }

  Process {
    id: updateCheckProc
    running: false
    command: ["omarchy-archalarm-update", "check"]
    stdout: StdioCollector {
      id: updateCheckStdout
      waitForEnd: true
      onStreamFinished: root.updateInfo = Model.parseUpdateInfo(text)
    }
  }

  Timer {
    // Fires once when the plugin loads — covers "check on fresh boot",
    // since that's when this component first comes alive.
    interval: 1
    running: true
    repeat: false
    onTriggered: root.checkForUpdate()
  }

  Timer {
    // Nudges the backend periodically so its 24h gate eventually lets a
    // real check through even on a shell that's stayed up for days.
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.checkForUpdate()
  }

  // ---------------------------------------------------- update installer
  property bool updateInstalling: false
  property bool updateInstallOk: false
  property string updateInstallError: ""
  property bool _updateProcDone: false
  property bool _updateProcOk: false
  property int installLineIndex: 0
  readonly property var installScript: [
    "CONNECTING TO UPLINK...",
    "FETCHING LATEST BUILD.......",
    "VERIFYING RELEASE TAG.......",
    "INSTALLING PATCH FILES......",
    "RELOADING SERVICES..........",
    "UPDATE COMPLETE. GO!!"
  ]

  function installUpdate() {
    if (root.updateInstalling) return
    root.updateInstalling = true
    root.updateInstallOk = false
    root.updateInstallError = ""
    root._updateProcDone = false
    root._updateProcOk = false
    root.installLineIndex = 0
    installLineTimer.restart()
    updateInstallProc.running = true
  }

  // Only closes the installer once BOTH the real process has exited and
  // the cosmetic line-by-line animation has played through — whichever
  // finishes last. Keeps it from looking rushed on a fast update or
  // stalled-looking on a slow one.
  property bool updateResultShowing: false

  function _maybeFinishInstall() {
    if (!root._updateProcDone) return
    if (root.installLineIndex < root.installScript.length) return
    root.updateInstalling = false
    root.updateInstallOk = root._updateProcOk
    root.updateResultShowing = true
    if (root._updateProcOk) {
      // The install swaps which directory the live symlinks point at —
      // Panel.qml and Model.js are already the new version's files on
      // disk, but this *running* component was compiled from the old
      // ones and keeps executing until the process that loaded it is
      // gone. Neither the file watcher's hot-reload nor rescanPlugins
      // re-resolves a retargeted symlink, only a full shell restart
      // does — so trigger one once the result message has had a moment
      // on screen, rather than leaving the panel silently stale.
      shellRestartTimer.restart()
    } else {
      updateResultDismissTimer.restart()
    }
  }

  Timer {
    id: updateResultDismissTimer
    interval: 4000
    repeat: false
    onTriggered: root.updateResultShowing = false
  }

  Timer {
    id: shellRestartTimer
    interval: 1800
    repeat: false
    onTriggered: shellRestartProc.running = true
  }

  Process {
    id: shellRestartProc
    running: false
    command: ["omarchy", "restart", "shell"]
  }

  Timer {
    id: installLineTimer
    interval: 550
    repeat: true
    running: false
    onTriggered: {
      root.installLineIndex++
      if (root.installLineIndex >= root.installScript.length) {
        installLineTimer.stop()
        root._maybeFinishInstall()
      }
    }
  }

  Process {
    id: updateInstallProc
    running: false
    command: ["omarchy-archalarm-update", "install"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: updateInstallStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._updateProcDone = true
      root._updateProcOk = exitCode === 0
      if (exitCode !== 0) {
        root.updateInstallError = String(updateInstallStderr.text || "update failed").trim().split("\n").pop()
      }
      root._maybeFinishInstall()
    }
  }

  // ------------------------------------------------------- dial-up intro
  property bool bootShowing: false
  property int bootLineIndex: 0
  readonly property var bootScript: [
    "DIALING ARCHALARM UPLINK...",
    "NEGOTIATING HANDSHAKE.......",
    "14.4k...28.8k...56.6k bps...",
    "AUTHENTICATING PERIMETER....",
    "CONNECTION ESTABLISHED. GO!!"
  ]

  onArchalarmEnabledChanged: {
    if (root.archalarmEnabled) {
      root.bootLineIndex = 0
      root.bootShowing = true
      bootTimer.restart()
    } else {
      bootTimer.stop()
      root.bootShowing = false
    }
  }

  Timer {
    id: bootTimer
    interval: 260
    repeat: true
    onTriggered: {
      root.bootLineIndex++
      if (root.bootLineIndex >= root.bootScript.length) {
        bootTimer.stop()
        bootHideTimer.restart()
      }
    }
  }

  Timer {
    id: bootHideTimer
    interval: 550
    repeat: false
    onTriggered: root.bootShowing = false
  }

  // Small pixel-block "wall" mark — reads clearly at bar-icon size and
  // recolors/blinks with firewall state.
  component BrickIcon: Item {
    id: brick
    property real iconSize: 11
    property color color: "#808080"
    width: iconSize
    height: iconSize
    implicitWidth: iconSize
    implicitHeight: iconSize

    readonly property real gap: Math.max(1, iconSize * 0.16)
    readonly property real cell: (iconSize - gap) / 2

    Rectangle { x: 0; y: 0; width: brick.cell; height: brick.cell; color: brick.color }
    Rectangle { x: brick.cell + brick.gap; y: 0; width: brick.cell; height: brick.cell; color: brick.color }
    Rectangle { x: 0; y: brick.cell + brick.gap; width: brick.cell; height: brick.cell; color: brick.color }
    Rectangle { x: brick.cell + brick.gap; y: brick.cell + brick.gap; width: brick.cell; height: brick.cell; color: brick.color }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.archalarmEnabled
      ? ("ArchAlarm '99: ONLINE — " + status.blockedTotal + " blocked")
      : "ArchAlarm '99: OFFLINE"
    iconComponent: Component {
      Item {
        BrickIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.iconBaseColor
          opacity: root.iconOpacity
          Behavior on opacity { NumberAnimation { duration: 120 } }
          Behavior on color { ColorAnimation { duration: 200 } }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleFirewall()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(370))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(920))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.toggleFirewall()
      onMoveRequested: function(dx, dy) {}
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Rectangle {
        id: crt
        anchors.fill: parent
        color: root.crtBg
        border.color: root.crtBorder
        border.width: 2
        radius: 4

        Flickable {
          id: scrollArea
          anchors.fill: parent
          anchors.margins: Style.space(2)
          clip: true
          contentWidth: width
          contentHeight: content.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: scrollArea.width
          spacing: Style.space(10)

          // ---------- Header ----------
          Item {
            width: parent.width
            height: Math.max(headerRow.implicitHeight, settingsGear.implicitHeight)

            Row {
              id: headerRow
              anchors.left: parent.left
              spacing: Style.space(6)
              Text {
                text: "▓▓ ARCHALARM '99 ▓▓"
                color: root.colCalm
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: root.blinkPhase ? "█" : " "
                color: root.colCalm
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: "v" + root.appVersion
                color: root.dimText
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.caption
                topPadding: Style.font.title - Style.font.caption
              }
            }

            Text {
              id: settingsGear
              anchors.right: parent.right
              anchors.verticalCenter: headerRow.verticalCenter
              text: "⚙"
              color: settingsGearHover.hovered ? "#ffffff" : root.dimText
              font.pixelSize: Style.font.title

              HoverHandler { id: settingsGearHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showSettings = !root.showSettings
              }
            }
          }

          // ---------- Update banner ----------
          Rectangle {
            visible: root.updateInfo.updateAvailable && !root.updateInstalling
            width: parent.width
            implicitHeight: updateBannerText.implicitHeight + Style.space(8)
            color: "transparent"
            border.color: updateBannerHover.hovered ? "#ffffff" : root.colElevated
            border.width: 1
            radius: 2

            Text {
              id: updateBannerText
              anchors.centerIn: parent
              width: parent.width - Style.space(16)
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              text: "⇪ UPDATE AVAILABLE — v" + root.updateInfo.latestVersion + " (click to install)"
              color: updateBannerHover.hovered ? "#ffffff" : root.colElevated
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            HoverHandler { id: updateBannerHover }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.installUpdate()
            }
          }

          // ---------- Settings ----------
          Column {
            visible: root.showSettings
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "THEME:"
              color: root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Repeater {
              model: Model.THEME_ORDER
              Rectangle {
                id: themeRow
                required property string modelData
                readonly property bool active: root.themeName === modelData
                width: parent.width
                height: themeLabel.implicitHeight + Style.space(8)
                color: active ? Qt.darker(root.colCalm, 8) : "transparent"
                border.width: 1
                border.color: themeRowHover.hovered ? "#ffffff" : (active ? root.colCalm : root.crtBorder)
                radius: 2

                Text {
                  id: themeLabel
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (themeRow.active ? "● " : "○ ") + Model.themeLabel(themeRow.modelData)
                  color: themeRow.active ? root.colCalm : root.dimText
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Style.font.caption
                  font.bold: themeRow.active
                }

                HoverHandler { id: themeRowHover }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setTheme(themeRow.modelData)
                }
              }
            }

            Text {
              text: "KNOWN-SAFE FILTER:"
              color: root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true
              topPadding: Style.space(6)
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Auto-allows DHCP discovery, mDNS, SSDP, and broadcast/multicast noise so it never shows up as a false alert. Recommended: on."
              color: root.faintText
              font.family: "JetBrainsMono Nerd Font"
              font.italic: true
              font.pixelSize: Math.max(8, Style.font.caption - 1)
            }

            Rectangle {
              width: parent.width
              height: knownSafeLabel.implicitHeight + Style.space(8)
              color: root.status.knownSafe === "on" ? Qt.darker(root.colCalm, 8) : "transparent"
              border.width: 1
              border.color: knownSafeHover.hovered ? "#ffffff" : (root.status.knownSafe === "on" ? root.colCalm : root.crtBorder)
              radius: 2

              Text {
                id: knownSafeLabel
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: (root.status.knownSafe === "on" ? "● " : "○ ") + (root.status.knownSafe === "on" ? "ON — filtering known-safe noise" : "OFF — alert on everything")
                color: root.status.knownSafe === "on" ? root.colCalm : root.dimText
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.caption
                font.bold: root.status.knownSafe === "on"
              }

              HoverHandler { id: knownSafeHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setKnownSafe(root.status.knownSafe === "on" ? "off" : "on")
              }
            }

            Text {
              text: "[CLOSE SETTINGS]"
              color: closeSettingsHover.hovered ? "#ffffff" : root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true

              HoverHandler { id: closeSettingsHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showSettings = false
              }
            }
          }

          Text {
            text: "════════════════════════════════"
            color: root.crtBorder
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.caption
          }

          // ---------- Status / toggle ----------
          Rectangle {
            id: toggleBtn
            width: parent.width
            height: Style.space(46)
            // Fixed traffic-light colors on purpose, independent of the
            // cosmetic theme — same convention as the threat meter: green
            // means online, red means offline, no matter the skin.
            readonly property color stateColor: root.toggling ? "#ffee00" : (root.archalarmEnabled ? "#39ff14" : "#ff1a1a")
            color: Qt.darker(stateColor, 8)
            border.width: 2
            border.color: statusHover.hovered ? "#ffffff" : stateColor
            radius: 2

            Text {
              anchors.centerIn: parent
              text: root.toggling
                ? "[ AUTHENTICATING... ]"
                : (root.archalarmEnabled ? "[ STATUS: ONLINE — CLICK TO DISARM ]" : "[ STATUS: OFFLINE — CLICK TO ARM ]")
              color: toggleBtn.stateColor
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.body
              font.bold: true
            }

            HoverHandler { id: statusHover }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleFirewall()
            }
          }

          // ---------- Toggle error ----------
          Text {
            visible: root.lastError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: "!! " + root.lastError
            color: root.colAlert
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          // ---------- Alert banner ----------
          Text {
            visible: root.archalarmEnabled && root.threatLevel >= 1
            width: parent.width
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: root.threatLevel >= 2 ? "⚠ INTRUSION ATTEMPT DETECTED ⚠" : "△ ELEVATED ACTIVITY △"
            color: root.threatLevel >= 2 ? root.colAlert : root.colElevated
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.body
            font.bold: true
            opacity: root.blinkPhase ? 1.0 : 0.25
          }

          // ---------- Stats ----------
          Grid {
            width: parent.width
            columns: 2
            rowSpacing: Style.space(4)
            columnSpacing: Style.space(10)

            Text { text: "UPTIME....:"; color: root.dimText; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.caption }
            Text { text: Model.formatDuration(status.uptimeSec); color: root.colCalm; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.caption; font.bold: true }

            Text { text: "BLOCKED...:"; color: root.dimText; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.caption }
            Text { text: String(status.blockedTotal); color: root.colAlert; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.caption; font.bold: true }

            Text { text: "SOCKETS...:"; color: root.dimText; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.caption }
            Text {
              id: socketsValue
              text: status.connectionCount + (status.connections.length > 0 ? " " + (root.showSockets ? "▾" : "▸") : "")
              color: socketsHover.hovered && status.connections.length > 0 ? "#ffffff" : root.colCalm
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true
              font.underline: socketsHover.hovered && status.connections.length > 0

              HoverHandler { id: socketsHover }
              MouseArea {
                anchors.fill: parent
                enabled: status.connections.length > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showSockets = !root.showSockets
              }
            }

            Text { text: "LISTENING.:"; color: root.dimText; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.caption }
            Text {
              id: listeningValue
              text: status.listenPorts.length + " ports " + (root.showPorts ? "▾" : "▸")
              color: listeningHover.hovered ? "#ffffff" : root.colCalm
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true
              font.underline: listeningHover.hovered

              HoverHandler { id: listeningHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showPorts = !root.showPorts
              }
            }
          }

          // ---------- Expanded port list ----------
          Flow {
            visible: root.showPorts && status.listenPorts.length > 0
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: status.listenPorts
              Rectangle {
                required property int modelData
                width: portLabel.implicitWidth + Style.space(10)
                height: portLabel.implicitHeight + Style.space(4)
                color: "transparent"
                border.width: 1
                border.color: root.crtBorder
                radius: 2

                Text {
                  id: portLabel
                  anchors.centerIn: parent
                  text: Model.portLabel(parent.modelData)
                  color: root.colCalm
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Math.max(8, Style.font.caption - 1)
                }
              }
            }
          }

          // ---------- Expanded socket list ----------
          Rectangle {
            visible: root.showSockets && status.connections.length > 0
            width: parent.width
            height: Style.space(100)
            color: "#000000"
            border.color: root.crtBorder
            border.width: 1

            ListView {
              anchors.fill: parent
              anchors.margins: Style.space(4)
              clip: true
              model: status.connections
              spacing: 1
              delegate: Text {
                required property var modelData
                text: modelData.proto.toUpperCase() + "  ->  " + modelData.remoteIp + ":" + modelData.remotePort
                color: root.colCalm
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.caption
              }
            }
          }

          // ---------- Response mode (BlackICE-style stealth/reject) ----------
          Row {
            spacing: Style.space(8)
            Text {
              text: "RESPONSE:"
              color: root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              topPadding: 2
            }
            Rectangle {
              width: modeLabel.implicitWidth + Style.space(14)
              height: modeLabel.implicitHeight + Style.space(6)
              color: "transparent"
              border.width: 1
              border.color: modeHover.hovered ? "#ffffff" : root.crtBorder
              radius: 2

              Text {
                id: modeLabel
                anchors.centerIn: parent
                text: root.modeSwitching
                  ? "SWITCHING TO " + root.pendingMode.toUpperCase() + "..."
                  : (root.status.mode === "reject" ? "REJECT (visible refusal)" : "STEALTH (silent drop)")
                color: root.modeSwitching ? "#ffffff" : (root.status.mode === "reject" ? root.colElevated : root.colCalm)
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              HoverHandler { id: modeHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleMode()
              }
            }

            // Cylon-scanner loading bar — purely cosmetic, covers the
            // ~1-2s it takes the background daemon to notice the mode
            // file changed and confirm it back in status.json.
            Row {
              visible: root.modeSwitching
              spacing: 2
              Repeater {
                model: 8
                Rectangle {
                  required property int index
                  width: Style.space(8)
                  height: Style.space(14)
                  radius: 1
                  color: index === root.scanIndex ? "#ffffff"
                    : (Math.abs(index - root.scanIndex) === 1 ? root.colElevated : "#113311")
                }
              }
            }
          }

          // ---------- Threat meter ----------
          Column {
            width: parent.width
            spacing: Style.space(3)
            Text {
              text: "THREAT LEVEL: " + Model.threatLabel(root.threatLevel)
              color: root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Row {
              spacing: 2
              Repeater {
                model: 10
                Rectangle {
                  required property int index
                  width: Style.space(20)
                  height: Style.space(10)
                  // Fixed traffic-light colors on purpose, independent of
                  // the cosmetic theme — green/yellow/red is a safety
                  // convention, not a style choice.
                  color: index < Model.meterLitCount(root.threatLevel)
                    ? (root.threatLevel >= 2 ? "#ff1a1a" : root.threatLevel >= 1 ? "#ffee00" : "#39ff14")
                    : "#1a1a1a"
                }
              }
            }
          }

          Text {
            text: "════════════════════════════════"
            color: root.crtBorder
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.caption
          }

          // ---------- Live feed ----------
          Text {
            text: "LIVE FEED (hover an entry for actions):"
            color: root.dimText
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Rectangle {
            width: parent.width
            height: Style.space(64)
            color: "#000000"
            border.color: root.crtBorder
            border.width: 1

            ListView {
              anchors.fill: parent
              anchors.margins: Style.space(4)
              clip: true
              model: status.recentEvents
              spacing: 1
              delegate: Rectangle {
                id: feedRow
                required property var modelData
                width: ListView.view.width
                height: feedText.implicitHeight + 2
                readonly property bool isBanned: root.status.bannedIps.indexOf(modelData.srcIp) !== -1
                readonly property bool isTrusted: root.status.trustedIps.indexOf(modelData.srcIp) !== -1
                // Optimistic flags flip the instant you click, so the row
                // animates right away instead of waiting ~1-1.5s for the
                // backend round-trip to confirm it in status.json.
                property bool justBanned: false
                property bool justTrusted: false
                readonly property bool showBanned: isBanned || justBanned
                readonly property bool showTrusted: isTrusted || justTrusted
                color: feedRow.showBanned ? "#3a0d0d" : (feedRow.showTrusted ? "#0d2a10" : (feedHover.hovered ? "#0d2a0d" : "transparent"))
                Behavior on color { ColorAnimation { duration: 350 } }

                readonly property string host: Model.hostnameFor(root.status, modelData.srcIp)

                Text {
                  id: feedText
                  anchors.left: parent.left
                  anchors.right: actionHints.left
                  anchors.rightMargin: Style.space(4)
                  elide: Text.ElideRight
                  readonly property string patternLabel: Model.patternLabel(feedRow.modelData.pattern)
                  // Pattern tag sits right after the timestamp (before the
                  // IP/port) so it survives ElideRight even on a long line
                  // with a resolved hostname — the classification matters
                  // more than seeing every last detail of a truncated row.
                  text: "[" + Model.formatClock(feedRow.modelData.ts) + "]"
                    + (feedText.patternLabel !== "" ? " ⚠" + feedText.patternLabel : "")
                    + " " + feedRow.modelData.srcIp
                    + (feedRow.host !== "" ? " (" + feedRow.host + ")" : "")
                    + " -> :" + feedRow.modelData.dport + " (" + feedRow.modelData.proto + ")"
                    + (feedRow.showBanned ? "  ☠ BANNED" : feedRow.showTrusted ? "  ✓ TRUSTED" : "")
                  color: feedRow.showBanned ? root.colAlert
                    : feedRow.showTrusted ? root.colCalm
                    : (feedText.patternLabel !== "" ? root.colElevated : root.colCalm)
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Style.font.caption
                  Behavior on color { ColorAnimation { duration: 350 } }
                }

                Row {
                  id: actionHints
                  anchors.right: parent.right
                  spacing: Style.space(8)
                  opacity: feedHover.hovered ? 1.0 : 0.3

                  Text {
                    text: "[TRACE]"
                    color: root.colElevated
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Style.font.caption
                    font.bold: true

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.investigate(feedRow.modelData.srcIp)
                    }
                  }

                  Text {
                    text: "[TRUST]"
                    color: root.colCalm
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Style.font.caption
                    font.bold: true

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        feedRow.justTrusted = true
                        root.trustIp(feedRow.modelData.srcIp)
                      }
                    }
                  }

                  Text {
                    text: "[BAN]"
                    color: root.colAlert
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Style.font.caption
                    font.bold: true

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        feedRow.justBanned = true
                        root.banIp(feedRow.modelData.srcIp)
                      }
                    }
                  }
                }

                HoverHandler { id: feedHover }
              }
            }

            // Digital rain — plays only while armed and nothing's happened
            // yet, so the box doesn't just sit dead empty. Drops out the
            // instant a real event needs the space.
            Canvas {
              id: rain
              anchors.fill: parent
              anchors.margins: 1
              visible: root.archalarmEnabled && status.recentEvents.length === 0
              opacity: 0.55

              readonly property int glyphSize: 13
              readonly property string charset: "01001101100101110100$#&%?"
              property var drops: []

              function resetDrops() {
                var count = Math.max(1, Math.floor(width / glyphSize))
                var next = []
                for (var i = 0; i < count; i++) {
                  next.push({
                    y: -Math.random() * height,
                    speed: 0.5 + Math.random() * 1.2
                  })
                }
                drops = next
              }

              onWidthChanged: resetDrops()
              onHeightChanged: resetDrops()
              onVisibleChanged: if (visible) { resetDrops(); requestPaint() }

              Timer {
                interval: 90
                running: rain.visible
                repeat: true
                onTriggered: rain.requestPaint()
              }

              onPaint: {
                var ctx = getContext("2d")
                ctx.fillStyle = "rgba(0, 0, 0, 0.18)"
                ctx.fillRect(0, 0, width, height)
                ctx.font = glyphSize + "px monospace"
                for (var i = 0; i < drops.length; i++) {
                  var drop = drops[i]
                  var ch = charset.charAt(Math.floor(Math.random() * charset.length))
                  ctx.fillStyle = Math.random() > 0.9 ? "#ffffff" : Qt.darker(root.colCalm, 1.6)
                  ctx.fillText(ch, i * glyphSize, drop.y)
                  drop.y += glyphSize * drop.speed
                  if (drop.y > height + glyphSize && Math.random() > 0.94) drop.y = -glyphSize
                }
              }
            }

            Text {
              visible: status.recentEvents.length === 0
              anchors.centerIn: parent
              text: root.archalarmEnabled
                ? ("◉ MONITORING — " + status.connectionCount + " sockets · " + status.listenPorts.length
                   + " ports · armed " + Model.formatDuration(status.uptimeSec))
                : "firewall offline"
              color: root.archalarmEnabled ? "#ffffff" : root.faintText
              font.family: "JetBrainsMono Nerd Font"
              font.italic: true
              font.bold: root.archalarmEnabled
              font.pixelSize: Style.font.caption
              style: Text.Outline
              styleColor: "#000000"
            }
          }

          // ---------- Trace report ----------
          Column {
            visible: root.investigateIp !== ""
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "TRACE: " + root.investigateIp
              color: root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Rectangle {
              width: parent.width
              height: Math.max(Style.space(46), reportColumn.implicitHeight + Style.space(16))
              color: "#000000"
              border.color: root.crtBorder
              border.width: 1

              Column {
                id: reportColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                spacing: Style.space(6)

                Row {
                  visible: root.investigating
                  spacing: 2
                  Repeater {
                    model: 8
                    Rectangle {
                      required property int index
                      width: Style.space(8)
                      height: Style.space(14)
                      radius: 1
                      color: index === root.scanIndex ? "#ffffff"
                        : (Math.abs(index - root.scanIndex) === 1 ? root.colElevated : "#113311")
                    }
                  }
                }

                Text {
                  visible: root.investigating
                  text: "querying whois + claude..."
                  color: root.faintText
                  font.family: "JetBrainsMono Nerd Font"
                  font.italic: true
                  font.pixelSize: Style.font.caption
                }

                Text {
                  visible: !root.investigating && root.investigateReport !== ""
                  width: reportColumn.width
                  wrapMode: Text.WordWrap
                  text: root.investigateReport
                  color: root.colCalm
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Style.font.caption
                }

                Text {
                  visible: !root.investigating && root.investigateError !== ""
                  width: reportColumn.width
                  wrapMode: Text.WordWrap
                  text: "!! " + root.investigateError
                  color: root.colAlert
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Text {
              text: "[CLOSE TRACE]"
              color: closeTraceHover.hovered ? "#ffffff" : root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true

              HoverHandler { id: closeTraceHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeInvestigation()
              }
            }
          }

          // ---------- Hall of shame ----------
          Column {
            visible: status.topOffenders.length > 0
            width: parent.width
            spacing: Style.space(2)

            Text {
              text: "TOP OFFENDERS (" + status.topOffenders.length + ") " + (root.showTopOffenders ? "▾" : "▸")
              color: topOffendersHeaderHover.hovered ? "#ffffff" : root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true

              HoverHandler { id: topOffendersHeaderHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showTopOffenders = !root.showTopOffenders
              }
            }

            Repeater {
              model: root.showTopOffenders ? status.topOffenders : []
              Text {
                required property var modelData
                width: parent.width
                elide: Text.ElideRight
                text: "  " + modelData.ip + "  x" + modelData.count
                  + (Model.hostnameFor(root.status, modelData.ip) !== "" ? "  (" + Model.hostnameFor(root.status, modelData.ip) + ")" : "")
                color: root.colAlert
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.caption
              }
            }
          }

          // ---------- Banlist ----------
          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              text: "BANLIST (" + status.bannedIps.length + ") " + (root.showBanlist ? "▾" : "▸")
              color: banlistHeaderHover.hovered ? "#ffffff" : root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true

              HoverHandler { id: banlistHeaderHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showBanlist = !root.showBanlist
              }
            }

            Repeater {
              model: root.showBanlist ? status.bannedIps : []
              Item {
                id: banRow
                required property string modelData
                width: parent.width
                height: banText.implicitHeight

                Text {
                  id: banText
                  anchors.left: parent.left
                  anchors.right: banActions.left
                  anchors.rightMargin: Style.space(4)
                  elide: Text.ElideRight
                  text: "  ☠ " + banRow.modelData
                  color: root.colAlert
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Style.font.caption
                }

                Row {
                  id: banActions
                  anchors.right: parent.right
                  spacing: Style.space(8)
                  opacity: banRowHover.hovered ? 1.0 : 0.3

                  Text {
                    text: "[TRACE]"
                    color: root.colElevated
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Style.font.caption
                    font.bold: true

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.investigate(banRow.modelData)
                    }
                  }

                  Text {
                    text: "[UNBAN]"
                    color: root.dimText
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Style.font.caption
                    font.bold: true

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.unbanIp(banRow.modelData)
                    }
                  }
                }

                HoverHandler { id: banRowHover }
              }
            }
          }

          // ---------- Whitelist ----------
          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              text: "WHITELIST (" + status.trustedIps.length + ") " + (root.showWhitelist ? "▾" : "▸")
              color: whitelistHeaderHover.hovered ? "#ffffff" : root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true

              HoverHandler { id: whitelistHeaderHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showWhitelist = !root.showWhitelist
              }
            }

            Repeater {
              model: root.showWhitelist ? status.trustedIps : []
              Item {
                id: trustRow
                required property string modelData
                width: parent.width
                height: trustText.implicitHeight

                Text {
                  id: trustText
                  anchors.left: parent.left
                  anchors.right: trustActions.left
                  anchors.rightMargin: Style.space(4)
                  elide: Text.ElideRight
                  text: "  ✓ " + trustRow.modelData
                  color: root.colCalm
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Style.font.caption
                }

                Row {
                  id: trustActions
                  anchors.right: parent.right
                  spacing: Style.space(8)
                  opacity: trustRowHover.hovered ? 1.0 : 0.3

                  Text {
                    text: "[UNTRUST]"
                    color: root.dimText
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Style.font.caption
                    font.bold: true

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.untrustIp(trustRow.modelData)
                    }
                  }
                }

                HoverHandler { id: trustRowHover }
              }
            }
          }

          // ---------- Incident report ----------
          Row {
            spacing: Style.space(6)
            Text {
              text: "[EXPORT INCIDENT REPORT]"
              color: reportBtnHover.hovered ? "#ffffff" : root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.caption
              font.bold: true

              HoverHandler { id: reportBtnHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.exportReport()
              }
            }
            Text {
              visible: reportProc.running
              text: "writing..."
              color: root.dimText
              font.family: "JetBrainsMono Nerd Font"
              font.italic: true
              font.pixelSize: Style.font.caption
            }
          }
          Text {
            visible: root.lastReportPath !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: "→ saved to " + root.lastReportPath
            color: root.colCalm
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: root.lastReportError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: "!! " + root.lastReportError
            color: root.colAlert
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "ArchAlarm '99 v" + root.appVersion + " — inbound-only, outbound never touched. Esc to close."
            color: root.faintText
            font.family: "JetBrainsMono Nerd Font"
            font.italic: true
            font.pixelSize: Math.max(8, Style.font.caption - 1)
          }
        }
        }

        // ---------- Dial-up boot overlay ----------
        Rectangle {
          id: bootOverlay
          anchors.fill: parent
          color: root.crtBg
          visible: root.bootShowing
          z: 10

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            Repeater {
              model: root.bootLineIndex
              Text {
                required property int index
                text: "> " + root.bootScript[index]
                color: index === root.bootLineIndex - 1 && root.blinkPhase ? "#ffffff" : root.colCalm
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }
          }
        }

        // ---------- Update installer overlay ----------
        Rectangle {
          id: updateOverlay
          anchors.fill: parent
          color: root.crtBg
          visible: root.updateInstalling || root.updateResultShowing
          z: 11

          MouseArea {
            anchors.fill: parent
            enabled: root.updateResultShowing && !root.updateInstalling
            onClicked: root.updateResultShowing = false
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)

            Repeater {
              model: root.updateInstalling ? root.installLineIndex : root.installScript.length
              Text {
                required property int index
                text: "> " + root.installScript[index]
                color: (root.updateInstalling && index === root.installLineIndex - 1 && root.blinkPhase) ? "#ffffff" : root.colCalm
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            Text {
              visible: root.updateResultShowing && !root.updateInstalling
              width: Style.space(320)
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              text: root.updateInstallOk
                ? "> INSTALLED v" + root.updateInfo.latestVersion + " — reloading shell..."
                : "> UPDATE FAILED: " + root.updateInstallError
              color: root.updateInstallOk ? root.colCalm : root.colAlert
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }
        }
      }
    }
  }
}
