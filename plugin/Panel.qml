import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "malekabokhatwa.amnezia"
  ipcTarget: "malekabokhatwa.amnezia"
  manageIpc: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Commons.Color.accent) : "transparent"

  // nf-md-shield_lock; the bar shows it dim while disconnected, accent while
  // connecting, full foreground once traffic flows, urgent after a failure.
  readonly property string vpnGlyph: "\u{F099D}"
  readonly property bool failing: vpn.lastError !== "" && !vpn.connected
  readonly property color barIconColor: !vpn.installed ? Qt.darker(barForeground, 1.55)
    : vpn.busy ? Commons.Color.accent
    : vpn.connected ? barForeground
    : failing ? urgent
    : Qt.darker(barForeground, 1.55)

  // The bar sizes the widget from these; without them the slot is 0 wide.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string pendingDelete: ""

  function formatBytes(b) {
    var units = ["B", "KB", "MB", "GB", "TB"], i = 0
    b = Number(b) || 0
    while (b >= 1024 && i < units.length - 1) { b /= 1024; i++ }
    return Commons.I18n.formatNumber(b, i === 0 ? 0 : 1) + " " + units[i]
  }
  function handshakeText(s) {
    if (s < 0) return strings.t("noHandshake")
    if (s < 60) return strings.t("handshakeSeconds").arg(s)
    return strings.t("handshakeMinutes").arg(Math.floor(s / 60))
  }

  onOpenedChanged: {
    vpn.panelOpen = opened
    if (!opened) { pendingDelete = ""; if (importField) importField.text = "" }
  }
  readonly property Item importField: panel.loadedContent ? panel.loadedContent.importField : null

  Service {
    id: vpn
    settings: root.settings
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connect(): string { vpn.toggle(); return "ok" }
    function status(): string { return vpn.connected ? "connected " + vpn.active : "disconnected" }
  }

  Timer { id: deleteReset; interval: 3000; onTriggered: root.pendingDelete = "" }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vpnGlyph
    foreground: root.barIconColor
    tooltipText: !vpn.installed ? strings.t("notInstalledShort")
      : vpn.connected ? strings.t("tooltipConnected").arg(vpn.active)
      : strings.t("tooltipDisconnected")
    opacity: vpn.busy ? pulse.value : 1.0
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) vpn.toggle()
      else if (buttonCode === Qt.MiddleButton) { vpn.refresh(); vpn.refreshLists() }
      else root.toggle()
    }

    QtObject { id: pulse; property real value: 1.0 }
    SequentialAnimation {
      running: vpn.busy && !Style.reduceMotion
      loops: Animation.Infinite
      onRunningChanged: if (!running) pulse.value = 1.0
      NumberAnimation { target: pulse; property: "value"; to: 0.45; duration: Style.duration(520); easing.type: Easing.InOutQuad }
      NumberAnimation { target: pulse; property: "value"; to: 1.0; duration: Style.duration(520); easing.type: Easing.InOutQuad }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(600))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias importField: importField
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") vpn.toggle()
        else if (t === "/" || t === "i" || t === "I") importField.forceActiveFocus()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "AmneziaWG"
            meta: !vpn.installed ? strings.t("notInstalledShort")
              : vpn.busyAction.indexOf("up:") === 0 ? strings.t("connecting").arg(vpn.busyAction.slice(3))
              : vpn.busyAction === "down" ? strings.t("disconnecting")
              : vpn.connected ? strings.t("connectedTo").arg(vpn.active)
              : strings.t("disconnected")
            detail: vpn.connected
              ? "↓ " + root.formatBytes(vpn.rx) + "   ↑ " + root.formatBytes(vpn.tx) + "   ·   " + root.handshakeText(vpn.handshake)
              : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: vpn.connected ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: root.vpnGlyph
                textFormat: Text.PlainText
                color: vpn.connected ? root.accent : (root.failing ? root.urgent : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: vpn.installed && vpn.configs.length > 0
                checked: vpn.connected
                busy: vpn.busy
                foreground: hero.foreground
                onToggled: vpn.toggle()
                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: vpn.connected ? strings.t("disconnect") : strings.t("connectTo").arg(vpn.lastUsed)
                  fontFamily: hero.fontFamily
                }
              }
            }
          }

          // Errors and confirmations, always plain text.
          Text {
            visible: vpn.lastError !== "" || vpn.notice !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: vpn.lastError !== "" ? vpn.lastError : vpn.notice
            color: vpn.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !vpn.installed
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("notInstalled")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          // ------------------------------------------------- connections
          PanelSeparator { visible: vpn.configs.length > 0; foreground: root.foreground }
          PanelSectionHeader {
            visible: vpn.configs.length > 0
            text: strings.t("connections")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Repeater {
            model: vpn.configs
            ConfigRow { required property var modelData; width: column.width; config: modelData }
          }

          // ------------------------------------------------- diagnosis
          CursorSurface {
            visible: vpn.diagnosing || vpn.diagnosis !== null
            width: parent.width
            implicitHeight: diagText.implicitHeight + Style.space(20)
            foreground: root.foreground
            current: true
            Text {
              id: diagText
              anchors.left: parent.left; anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              text: vpn.diagnosing ? strings.t("diagnosing") : root.diagnosisText(vpn.diagnosis)
            }
          }

          // ------------------------------------------------- import
          PanelSeparator { visible: vpn.installed; foreground: root.foreground }
          PanelSectionHeader {
            visible: vpn.installed
            text: strings.t("import")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Repeater {
            model: vpn.installed ? vpn.candidates : []
            CandidateRow { required property var modelData; width: column.width; candidate: modelData }
          }
          RowLayout {
            visible: vpn.installed
            width: parent.width
            spacing: Style.space(8)
            TextField {
              id: importField
              Layout.fillWidth: true
              foreground: root.foreground
              placeholderText: strings.t("importPlaceholder")
              onAccepted: if (text.trim() !== "") { vpn.importFile(text); text = "" }
            }
            PanelActionButton {
              iconText: "\u{F0415}"
              tooltipText: strings.t("importButton")
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: importField.text.trim() !== "" && !vpn.busy
              onClicked: { vpn.importFile(importField.text); importField.text = "" }
            }
          }

          // ------------------------------------------------- autostart
          CursorSurface {
            visible: vpn.installed && vpn.lastUsed !== ""
            width: parent.width
            implicitHeight: Style.space(40)
            foreground: root.foreground
            fill: root.hoverFill
            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8); anchors.rightMargin: Style.space(8)
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: strings.t("autostart").arg(vpn.autostart !== "" ? vpn.autostart : vpn.lastUsed)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              ToggleSwitch {
                checked: vpn.autostart !== ""
                busy: vpn.busyAction === "autostart"
                foreground: root.foreground
                onToggled: vpn.setAutostart(vpn.autostart !== "" ? "" : vpn.lastUsed)
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("hint")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption !== undefined ? Style.font.caption : Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  function diagnosisText(d) {
    if (!d) return ""
    var lines = [strings.t("diagFor").arg(d.name)]
    lines.push((d.handshake >= 0 ? "✓ " : "✗ ") + strings.t("diagHandshake"))
    lines.push((d.ping ? "✓ " : "✗ ") + strings.t("diagPing").arg(Commons.I18n.formatNumber(d.loss, 0)))
    lines.push((d.https ? "✓ " : "✗ ") + strings.t("diagHttps"))
    if (d.handshake < 0) lines.push(strings.t("adviceNoHandshake"))
    else if (!d.ping && !d.https) lines.push(strings.t("adviceNoTraffic"))
    else {
      if (!d.ping) lines.push(strings.t("notePingBlocked"))
      lines.push(strings.t("adviceOk"))
    }
    return lines.join("\n")
  }

  component ConfigRow: CursorSurface {
    id: row
    property var config: null
    readonly property string name: config ? config.name : ""
    readonly property bool isActive: vpn.active === name
    readonly property bool working: vpn.busyAction === "up:" + name || vpn.busyAction === "remove:" + name || vpn.busyAction === "obfuscate:" + name
    current: isActive
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: inner.implicitHeight + Style.spacing.xl

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: !vpn.busy
      onClicked: row.isActive ? vpn.disconnect() : vpn.connect(row.name)
    }

    RowLayout {
      id: inner
      anchors.left: parent.left; anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6); anchors.rightMargin: Style.space(4)
      spacing: Style.space(8)

      Text {
        text: row.isActive ? "\u{F099D}" : "\u{F0565}"
        textFormat: Text.PlainText
        color: row.isActive ? root.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        opacity: row.working ? workPulse.value : 1.0
        QtObject { id: workPulse; property real value: 1.0 }
        SequentialAnimation {
          running: row.working && !Style.reduceMotion
          loops: Animation.Infinite
          onRunningChanged: if (!running) workPulse.value = 1.0
          NumberAnimation { target: workPulse; property: "value"; to: 0.35; duration: Style.duration(420); easing.type: Easing.InOutQuad }
          NumberAnimation { target: workPulse; property: "value"; to: 1.0; duration: Style.duration(420); easing.type: Easing.InOutQuad }
        }
      }

      Column {
        Layout.fillWidth: true
        spacing: Style.space(2)
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.name
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.isActive
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: (row.config ? row.config.endpoint : "")
            + (row.config && row.config.awg ? "  ·  " + strings.t("badgeAwg")
               : row.config && row.config.junk ? "  ·  " + strings.t("badgeJunk")
               : "  ·  " + strings.t("badgePlain"))
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: row.config && (row.config.junk || row.config.awg) ? "\u{F099D}" : "\u{F0565}"
        tooltipText: row.config && row.config.awg ? strings.t("obfuscationServer")
          : row.config && row.config.junk ? strings.t("obfuscationOff") : strings.t("obfuscationOn")
        foreground: row.config && (row.config.junk || row.config.awg) ? root.accent : root.dim
        fontFamily: root.fontFamily
        enabled: !vpn.busy && row.config && !row.config.awg
        onClicked: vpn.setJunk(row.name, !row.config.junk)
      }
      PanelActionButton {
        iconText: "\u{F04C5}"
        tooltipText: strings.t("diagnose")
        foreground: root.dim
        fontFamily: root.fontFamily
        enabled: !vpn.diagnosing
        onClicked: vpn.diagnose(row.name)
      }
      PanelActionButton {
        iconText: "\u{F01B4}"
        tooltipText: root.pendingDelete === row.name ? strings.t("confirmDelete") : strings.t("delete")
        foreground: root.pendingDelete === row.name ? root.urgent : root.dim
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        enabled: !vpn.busy
        onClicked: {
          if (root.pendingDelete === row.name) { root.pendingDelete = ""; vpn.remove(row.name) }
          else { root.pendingDelete = row.name; deleteReset.restart() }
        }
      }
    }
  }

  component CandidateRow: CursorSurface {
    id: crow
    property var candidate: null
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: cinner.implicitHeight + Style.spacing.xl

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: !vpn.busy
      onClicked: if (crow.candidate) vpn.importFile(crow.candidate.path, crow.candidate.name)
    }
    RowLayout {
      id: cinner
      anchors.left: parent.left; anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6); anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)
      Text {
        text: "\u{F0415}"
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
      }
      Column {
        Layout.fillWidth: true
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: crow.candidate ? crow.candidate.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: crow.candidate ? crow.candidate.path.replace(Quickshell.env("HOME"), "~") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }
      }
    }
  }
}
