import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// User switcher in the power-menu style. Logged-in users are activated directly;
// starting a new login falls back to the display manager's greeter.
Scope {
    id: switcher

    required property var ui

    readonly property int tileSize: 128
    readonly property int gutter: 8
    readonly property string greeterCmd: "busctl --system call org.freedesktop.DisplayManager \"${XDG_SEAT_PATH:-/org/freedesktop/DisplayManager/Seat0}\" org.freedesktop.DisplayManager.Seat SwitchToGreeter"

    property bool open: false
    property var targetScreen: Quickshell.screens[0]
    property int selected: 0
    property var users: []
    property bool greeter: false
    readonly property var entries: greeter ? users.concat([{ other: true, display: "別のユーザー", name: "" }]) : users

    function show() {
        if (ui.authOpen) return;
        ui.closeOverlays();
        const focused = Hyprland.focusedMonitor;
        targetScreen = Quickshell.screens.find(s => focused && s.name === focused.name) ?? Quickshell.screens[0];
        selected = 0;
        lister.running = true;
        open = true;
    }

    function hide() {
        open = false;
    }

    // An outside click also reaches whatever was clicked; a toggle right after must not reopen.
    property double dismissedAt: 0

    function dismiss() {
        dismissedAt = Date.now();
        hide();
    }

    function move(delta) {
        selected = (selected + delta + entries.length) % entries.length;
    }

    function status(e) {
        if (e.other) return "ログイン画面へ";
        if (e.current) return "現在のユーザー";
        return e.session ? "ログイン中" : "ログイン";
    }

    function activate(index) {
        const e = entries[index];
        if (!e) return;
        hide();
        if (e.current) return;
        if (!e.other && e.session) Quickshell.execDetached(["loginctl", "activate", e.session]);
        else Quickshell.execDetached(["sh", "-c", greeterCmd]);
    }

    Process {
        id: lister
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/users-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const list = data.users || [];
                    switcher.users = list;
                    switcher.greeter = !!data.greeter;
                    switcher.selected = list[0] && list[0].current && switcher.entries.length > 1 ? 1 : 0;
                } catch (err) {
                    switcher.users = [];
                }
            }
        }
    }

    IpcHandler {
        target: "users"

        function toggle(): void {
            if (switcher.open) switcher.hide();
            else if (Date.now() - switcher.dismissedAt > 400) switcher.show();
        }

        function close(): void {
            switcher.hide();
        }
    }

    Variants {
        model: switcher.open ? [switcher.targetScreen] : []

        PanelWindow {
            id: win

            required property var modelData
            readonly property bool main: true

            screen: modelData
            implicitWidth: card.width
            implicitHeight: card.height
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "user-switch"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            HyprlandFocusGrab {
                active: true
                windows: [win]
                onCleared: switcher.dismiss()
            }

            Rectangle {
                id: card
                width: 2 + switcher.gutter + switcher.entries.length * (switcher.tileSize + switcher.gutter)
                height: 2 + title.height + switcher.tileSize + switcher.gutter + hint.height
                color: switcher.ui.panel
                border.color: switcher.ui.hairline
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                }

                Item {
                    focus: true
                    Component.onCompleted: if (win.main) forceActiveFocus()

                    Keys.onPressed: event => {
                        const k = event.key;
                        if (k === Qt.Key_Escape) {
                            switcher.hide();
                        } else if (k === Qt.Key_Right || k === Qt.Key_Tab || k === Qt.Key_L || k === Qt.Key_Down || k === Qt.Key_J) {
                            switcher.move(1);
                        } else if (k === Qt.Key_Left || k === Qt.Key_Backtab || k === Qt.Key_H || k === Qt.Key_Up || k === Qt.Key_K) {
                            switcher.move(-1);
                        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                            switcher.activate(switcher.selected);
                        } else if (k >= Qt.Key_1 && k < Qt.Key_1 + Math.min(9, switcher.entries.length)) {
                            switcher.activate(k - Qt.Key_1);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }

                Item {
                    id: title
                    x: 1
                    y: 1
                    width: parent.width - 2
                    height: 40

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "ユーザー切り替え"
                        font.family: switcher.ui.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: switcher.ui.text1
                    }
                }

                Row {
                    x: 1 + switcher.gutter
                    y: title.y + title.height
                    spacing: switcher.gutter

                    Repeater {
                        model: switcher.entries

                        delegate: Rectangle {
                            id: tile

                            required property var modelData
                            required property int index
                            readonly property bool current: index === switcher.selected

                            width: switcher.tileSize
                            height: switcher.tileSize
                            color: current ? switcher.ui.cream : "transparent"
                            border.color: current ? switcher.ui.cream : switcher.ui.hairline
                            border.width: 1

                            Rectangle {
                                id: face
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 22
                                width: 44
                                height: 44
                                color: "transparent"
                                border.width: 1
                                border.color: tile.current ? switcher.ui.ink : switcher.ui.hairline

                                Image {
                                    id: photo
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    visible: status === Image.Ready
                                    source: tile.modelData.avatar ? "file://" + tile.modelData.avatar : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !photo.visible
                                    text: tile.modelData.other ? String.fromCodePoint(0xF0014) : tile.modelData.display.charAt(0).toUpperCase()
                                    font.family: tile.modelData.other ? switcher.ui.symbols : switcher.ui.font
                                    font.pixelSize: tile.modelData.other ? 24 : 20
                                    font.weight: Font.DemiBold
                                    color: tile.current ? switcher.ui.ink : switcher.ui.text1
                                }
                            }

                            Text {
                                id: label
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: face.bottom
                                anchors.topMargin: 12
                                width: parent.width - 12
                                horizontalAlignment: Text.AlignHCenter
                                text: tile.modelData.display
                                font.family: switcher.ui.font
                                font.pixelSize: 13
                                font.weight: tile.current ? Font.DemiBold : Font.Normal
                                color: tile.current ? switcher.ui.ink : switcher.ui.text1
                                elide: Text.ElideRight
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: label.bottom
                                anchors.topMargin: 3
                                text: switcher.status(tile.modelData)
                                font.family: switcher.ui.font
                                font.pixelSize: 11
                                color: tile.current ? Qt.rgba(switcher.ui.ink.r, switcher.ui.ink.g, switcher.ui.ink.b, 0.6) : switcher.ui.text3
                            }

                            Text {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 8
                                visible: tile.index < 9
                                text: tile.index + 1
                                font.family: switcher.ui.font
                                font.pixelSize: 11
                                color: tile.current ? Qt.rgba(switcher.ui.ink.r, switcher.ui.ink.g, switcher.ui.ink.b, 0.5) : switcher.ui.text3
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: switcher.selected = tile.index
                                onClicked: switcher.activate(tile.index)
                            }
                        }
                    }
                }

                Item {
                    id: hint
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    x: 1
                    width: parent.width - 2
                    height: 30

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: switcher.ui.hairline
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "←→ 選択    ↵ 切り替え    esc 閉じる"
                        font.family: switcher.ui.font
                        font.pixelSize: 11
                        color: switcher.ui.text3
                    }
                }
            }
        }
    }
}
