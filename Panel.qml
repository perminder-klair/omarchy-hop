import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The Omassh panel: a list of machines, and the form that edits one.
//
// Two modes in one popup rather than a separate editor window — adding a
// machine is a thing you do once per machine and then never again, so it
// does not deserve a surface of its own, but it does need enough room for a
// startup script, which is why the form replaces the list instead of
// unfolding under it.
//
// Clicking a machine hands off to `omassh connect` and closes: the session
// belongs to the terminal it opens, not to this panel.
Panel {
  id: root
  moduleName: "co.klair.omassh"
  ipcTarget: "co.klair.omassh"
  manageIpc: true

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  readonly property var hosts: service ? service.hosts : []
  readonly property string lastError: service ? service.lastError : ""

  // "list" or "form"
  property string mode: "list"
  property string editId: ""
  property bool confirmingDelete: false
  property string statusMessage: ""

  // Form fields. Held here rather than read off the controls so cancelling
  // is a mode change and nothing has to be unwound.
  property string fName: ""
  property string fHost: ""
  property string fUser: ""
  property string fPort: "22"
  property string fIdentity: ""
  property string fInit: ""
  property bool fAgent: false

  readonly property bool canSave: fHost.trim() !== ""

  function open() {
    if (service) service.refresh()
    root.mode = "list"
    root.controller.show()
  }
  function close() {
    root.controller.hide()
    root.mode = "list"
    root.confirmingDelete = false
  }
  function toggle() { root.opened ? root.close() : root.open() }

  function connectTo(id) {
    if (!service) return
    service.connect(id)
    root.close()
  }

  function startAdd() {
    root.editId = ""
    root.fName = ""
    root.fHost = ""
    root.fUser = ""
    root.fPort = "22"
    root.fIdentity = ""
    root.fInit = ""
    root.fAgent = false
    root.confirmingDelete = false
    root.mode = "form"
  }

  function startEdit(entry) {
    root.editId = String(entry.id)
    root.fName = String(entry.name || "")
    root.fHost = String(entry.host || "")
    root.fUser = String(entry.user || "")
    root.fPort = String(entry.port || 22)
    root.fIdentity = String(entry.identity || "")
    root.fInit = String(entry.init || "")
    root.fAgent = entry.forwardAgent === true
    root.confirmingDelete = false
    root.mode = "form"
  }

  function cancelForm() {
    root.mode = "list"
    root.confirmingDelete = false
  }

  function saveForm() {
    if (!root.canSave || !service) return
    service.save(root.editId, {
      name: root.fName.trim() !== "" ? root.fName.trim() : root.fHost.trim(),
      host: root.fHost.trim(),
      user: root.fUser.trim(),
      port: Number(root.fPort) || 22,
      identity: root.fIdentity.trim(),
      init: root.fInit,
      forwardAgent: root.fAgent
    })
    root.statusMessage = root.editId === "" ? "Machine added" : "Saved"
    messageTimer.restart()
    root.mode = "list"
  }

  // Two presses rather than a dialog: a machine entry is cheap to retype and
  // a modal over a popup is more ceremony than the mistake is worth.
  function deleteForm() {
    if (root.editId === "") return
    if (!root.confirmingDelete) {
      root.confirmingDelete = true
      return
    }
    if (service) service.remove(root.editId)
    root.statusMessage = "Machine removed"
    messageTimer.restart()
    root.mode = "list"
    root.confirmingDelete = false
  }

  function subtitleFor(entry) {
    var target = (entry.user ? entry.user + "@" : "") + (entry.host || "")
    var port = Number(entry.port) || 22
    if (port !== 22) target += ":" + port
    if (entry.init && String(entry.init).trim() !== "") target += "  ·  startup script"
    return target
  }

  Timer {
    id: messageTimer
    interval: 2200
    onTriggered: root.statusMessage = ""
  }

  // One machine in the list: the whole row connects, the two buttons on the
  // right do not.
  component HostRow: Rectangle {
    id: hostRow
    property var entry: null

    Layout.fillWidth: true
    implicitHeight: rowContent.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: hover.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.connectTo(hostRow.entry.id)
    }

    RowLayout {
      id: rowContent
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text {
          Layout.fillWidth: true
          text: String(hostRow.entry.name || hostRow.entry.host)
          color: root.barForeground
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          Layout.fillWidth: true
          text: root.subtitleFor(hostRow.entry)
          color: Qt.darker(root.barForeground, 1.6)
          elide: Text.ElideMiddle
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      PanelActionButton {
        iconText: "󰏫"
        tooltipText: "Edit"
        foreground: Qt.darker(root.barForeground, 1.6)
        hoverColor: Color.accent
        fontSize: Style.font.caption
        onClicked: root.startEdit(hostRow.entry)
      }

      PanelActionButton {
        iconText: "󰆧"
        tooltipText: "Copy ssh command"
        foreground: Qt.darker(root.barForeground, 1.6)
        hoverColor: Color.accent
        fontSize: Style.font.caption
        onClicked: root.copyCommand(hostRow.entry.id)
      }
    }
  }

  // A labelled form field, so the form reads as rows rather than a stack of
  // unexplained boxes.
  component FormRow: ColumnLayout {
    property alias label: fieldLabel.text
    default property alias content: fieldHolder.children

    Layout.fillWidth: true
    spacing: Style.space(3)

    Text {
      id: fieldLabel
      color: Qt.darker(root.barForeground, 1.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    ColumnLayout {
      id: fieldHolder
      Layout.fillWidth: true
      spacing: 0
    }
  }

  function copyCommand(id) {
    if (!service) return
    copyProc.command = ["bash", "-c",
      "'" + service.ctl + "' command " + JSON.stringify(String(id)) + " | wl-copy"]
    copyProc.running = true
    root.statusMessage = "ssh command copied"
    messageTimer.restart()
  }

  Process { id: copyProc; running: false }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The form owns the keyboard while it is up; otherwise every letter
      // typed into a hostname would be read as a panel shortcut.
      blocked: root.mode === "form"
      onCloseRequested: root.close()

      ColumnLayout {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ================= list mode =====================================

        PanelSectionHeader {
          Layout.fillWidth: true
          visible: root.mode === "list"
          text: "Machines"
        }

        Text {
          Layout.fillWidth: true
          visible: root.mode === "list" && root.hosts.length === 0
          text: "Nothing saved yet. Add a machine and it will open in your default terminal, run its startup script, and leave you at a prompt."
          color: Qt.darker(root.barForeground, 1.7)
          wrapMode: Text.WordWrap
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        ColumnLayout {
          Layout.fillWidth: true
          visible: root.mode === "list"
          spacing: Style.space(2)

          Repeater {
            model: root.mode === "list" ? root.hosts : []
            delegate: HostRow { entry: modelData }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: root.mode === "list"
          spacing: Style.space(8)

          Button {
            text: "Add machine"
            bordered: true
            foreground: root.barForeground
            accent: Color.accent
            onClicked: root.startAdd()
          }

          Item { Layout.fillWidth: true }
        }

        // ================= form mode =====================================

        PanelSectionHeader {
          Layout.fillWidth: true
          visible: root.mode === "form"
          text: root.editId === "" ? "Add machine" : "Edit machine"
        }

        FormRow {
          visible: root.mode === "form"
          label: "Name"
          TextField {
            Layout.fillWidth: true
            placeholderText: "Prod web"
            foreground: root.barForeground
            text: root.fName
            onTextChanged: root.fName = text
            Keys.onEscapePressed: root.cancelForm()
          }
        }

        FormRow {
          visible: root.mode === "form"
          label: "Host"
          TextField {
            Layout.fillWidth: true
            placeholderText: "10.0.0.5, example.com, or an ~/.ssh/config alias"
            foreground: root.barForeground
            text: root.fHost
            onTextChanged: root.fHost = text
            Keys.onEscapePressed: root.cancelForm()
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: root.mode === "form"
          spacing: Style.space(8)

          FormRow {
            Layout.fillWidth: true
            label: "User"
            TextField {
              Layout.fillWidth: true
              placeholderText: "leave empty for ssh_config"
              foreground: root.barForeground
              text: root.fUser
              onTextChanged: root.fUser = text
              Keys.onEscapePressed: root.cancelForm()
            }
          }

          FormRow {
            Layout.preferredWidth: Style.space(80)
            label: "Port"
            TextField {
              Layout.fillWidth: true
              placeholderText: "22"
              foreground: root.barForeground
              text: root.fPort
              inputMethodHints: Qt.ImhDigitsOnly
              validator: IntValidator { bottom: 1; top: 65535 }
              onTextChanged: root.fPort = text
              Keys.onEscapePressed: root.cancelForm()
            }
          }
        }

        FormRow {
          visible: root.mode === "form"
          label: "Identity file"
          TextField {
            Layout.fillWidth: true
            placeholderText: "~/.ssh/id_ed25519 — optional"
            foreground: root.barForeground
            text: root.fIdentity
            onTextChanged: root.fIdentity = text
            Keys.onEscapePressed: root.cancelForm()
          }
        }

        FormRow {
          visible: root.mode === "form"
          label: "Startup script"

          // A scrolling box rather than a growing one: a long script would
          // otherwise push Save off the bottom of the popup.
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: Style.space(96)
            radius: Style.cornerRadius
            color: Style.controlFill(initArea.activeFocus, initHover.containsMouse, root.barForeground, Color.accent)
            border.width: Math.max(1, Style.normalBorderWidth)
            border.color: Style.controlBorder(initArea.activeFocus, initHover.containsMouse, root.barForeground, Color.accent)

            MouseArea {
              id: initHover
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
            }

            ScrollView {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              clip: true

              TextArea {
                id: initArea
                wrapMode: TextArea.Wrap
                selectByMouse: true
                placeholderText: "cd /srv/app\ndocker compose ps"
                color: root.barForeground
                placeholderTextColor: Qt.darker(root.barForeground, 1.8)
                selectionColor: Style.selectionFillFor(root.barForeground, Color.accent)
                selectedTextColor: root.barForeground
                font.family: "monospace"
                font.pixelSize: Style.font.caption
                leftPadding: 0
                rightPadding: 0
                topPadding: 0
                bottomPadding: 0
                background: null
                text: root.fInit
                onTextChanged: root.fInit = text
                Keys.onEscapePressed: root.cancelForm()
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.mode === "form"
          text: "Runs on arrival, then you are dropped into a normal login shell."
          color: Qt.darker(root.barForeground, 1.7)
          wrapMode: Text.WordWrap
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Toggle {
          Layout.fillWidth: true
          visible: root.mode === "form"
          label: "Forward ssh agent"
          description: "Let the remote machine use the keys in your local agent."
          checked: root.fAgent
          foreground: root.barForeground
          accent: Color.accent
          onClicked: root.fAgent = !root.fAgent
        }

        RowLayout {
          Layout.fillWidth: true
          visible: root.mode === "form"
          spacing: Style.space(8)

          Button {
            text: "Save"
            bordered: true
            opacity: root.canSave ? 1.0 : 0.45
            foreground: root.barForeground
            accent: Color.accent
            onClicked: root.saveForm()
          }

          Button {
            text: "Cancel"
            bordered: true
            foreground: root.barForeground
            accent: Color.accent
            onClicked: root.cancelForm()
          }

          Item { Layout.fillWidth: true }

          Button {
            visible: root.editId !== ""
            text: root.confirmingDelete ? "Really delete?" : "Delete"
            bordered: true
            foreground: root.confirmingDelete ? Color.urgent : root.barForeground
            accent: Color.urgent
            onClicked: root.deleteForm()
          }
        }

        // ================= footer ========================================

        Text {
          Layout.fillWidth: true
          visible: root.lastError !== ""
          text: root.lastError
          color: Color.urgent
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 3
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          Layout.fillWidth: true
          visible: root.statusMessage !== ""
          text: root.statusMessage
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
