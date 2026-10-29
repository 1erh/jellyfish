import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Centered power menu: four square tiles, icon above label.
Scope {
    id: menu

    required property var ui

    readonly property int tileSize: 128
    readonly property int gutter: 8

    property bool open: false
    property var targetScreen: Quickshell.screens[0]
    property int selected: 0
    property int armed: -1

    readonly property var actions: [
        { icon: String.fromCodePoint(0xF033E), label: "ロック", confirm: false,
          cmd: [Quickshell.env("HOME") + "/.config/hypr/scripts/lock"] },
        { icon: String.fromCodePoint(0xF0709), label: "再起動", confirm: true,
          cmd: ["systemctl", "reboot"] },
        { icon: String.fromCodePoint(0xF0425), label: "シャットダウン", confirm: true,
          cmd: ["systemctl", "poweroff"] },
        { icon: String.fromCodePoint(0xF0019), label: "ユーザー切り替え", confirm: false, users: true },
    ]

    onSelectedChanged: armed = -1

    function show() {
        if (ui.authOpen) return;
        ui.closeOverlays();
        const focused = Hyprland.focusedMonitor;
        targetScreen = Quickshell.screens.find(s => focused && s.name === focused.name) ?? Quickshell.screens[0];
        selected = 0;
        armed = -1;
        open = true;
    }

    function hide() {
        open = false;
        armed = -1;
    }

    // An outside click also reaches whatever was clicked; a toggle right after must not reopen.
    property double dismissedAt: 0

    function dismiss() {
        dismissedAt = Date.now();
        hide();
    }

    function move(delta) {
        selected = (selected + delta + actions.length) % actions.length;
    }

    function activate(index) {
        const a = actions[index];
        if (!a) return;
        if (a.confirm && armed !== index) {
            selected = index;
            armed = index;
            return;
        }
        hide();
        if (a.users) ui.userSwitcher.show();
        else Quickshell.execDetached(a.cmd);
    }

    IpcHandler {
        target: "power"

        function toggle(): void {
            if (menu.open) menu.hide();
            else if (Date.now() - menu.dismissedAt > 400) menu.show();
        }

        function close(): void {
            menu.hide();
        }
    }

    Variants {
        model: menu.open ? [menu.targetScreen] : []

        PanelWindow {
            id: win

            required property var modelData
            readonly property bool main: true

            screen: modelData
            implicitWidth: card.width
            implicitHeight: card.height
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "power-menu"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            HyprlandFocusGrab {
                active: true
                windows: [win]
                onCleared: menu.dismiss()
            }

            Rectangle {
                id: card
                width: 2 + menu.gutter + menu.actions.length * (menu.tileSize + menu.gutter)
                height: 2 + menu.gutter + menu.tileSize + menu.gutter + hint.height
                color: menu.ui.panel
                border.color: menu.ui.hairline
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                }

                Item {
                    id: keys
                    focus: true
                    Component.onCompleted: if (win.main) forceActiveFocus()

                    Keys.onPressed: event => {
                        const k = event.key;
                        if (k === Qt.Key_Escape) {
                            menu.hide();
                        } else if (k === Qt.Key_Right || k === Qt.Key_Tab || k === Qt.Key_L || k === Qt.Key_Down || k === Qt.Key_J) {
                            menu.move(1);
                        } else if (k === Qt.Key_Left || k === Qt.Key_Backtab || k === Qt.Key_H || k === Qt.Key_Up || k === Qt.Key_K) {
                            menu.move(-1);
                        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                            menu.activate(menu.selected);
                        } else if (k >= Qt.Key_1 && k < Qt.Key_1 + menu.actions.length) {
                            menu.activate(k - Qt.Key_1);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }

                Row {
                    x: 1 + menu.gutter
                    y: 1 + menu.gutter
                    spacing: menu.gutter

                    Repeater {
                        model: menu.actions

                        delegate: Rectangle {
                            id: tile

                            required property var modelData
                            required property int index
                            readonly property bool current: index === menu.selected
                            readonly property bool isArmed: index === menu.armed

                            width: menu.tileSize
                            height: menu.tileSize
                            color: current ? menu.ui.cream : "transparent"
                            border.color: current ? menu.ui.cream : menu.ui.hairline
                            border.width: 1

                            Text {
                                id: glyph
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.verticalCenter
                                anchors.bottomMargin: -2
                                text: tile.modelData.icon
                                font.family: menu.ui.symbols
                                font.pixelSize: 32
                                color: tile.current ? menu.ui.ink : menu.ui.text1
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: glyph.bottom
                                anchors.topMargin: 12
                                width: parent.width - 12
                                horizontalAlignment: Text.AlignHCenter
                                text: tile.isArmed ? "もう一度で確定" : tile.modelData.label
                                font.family: menu.ui.font
                                font.pixelSize: 13
                                font.weight: tile.current ? Font.DemiBold : Font.Normal
                                color: tile.current ? menu.ui.ink : menu.ui.text2
                                elide: Text.ElideRight
                            }

                            Text {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 8
                                text: tile.index + 1
                                font.family: menu.ui.font
                                font.pixelSize: 11
                                color: tile.current ? Qt.rgba(menu.ui.ink.r, menu.ui.ink.g, menu.ui.ink.b, 0.5) : menu.ui.text3
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: menu.selected = tile.index
                                onClicked: menu.activate(tile.index)
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
                        color: menu.ui.hairline
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "←→ 選択    ↵ 実行    1–4 直接    esc 閉じる"
                        font.family: menu.ui.font
                        font.pixelSize: 11
                        color: menu.ui.text3
                    }
                }
            }
        }
    }
}
