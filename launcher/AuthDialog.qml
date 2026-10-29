import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import Quickshell.Widgets

// Polkit password prompt, in the same square ink/cream panels as the rest of the shell.
Scope {
    id: auth

    required property var ui

    property var targetScreen: Quickshell.screens[0]
    property string secret: ""
    readonly property bool agentActive: agent.isActive

    readonly property color fail: ui.fail

    function identityLabel(ident) {
        if (!ident) return "";
        if (ident.isGroup && (ident.string === "wheel" || ident.string === "sudo")) return "管理者";
        return ident.displayName;
    }

    function messageText() {
        const flow = agent.flow;
        if (!flow || !flow.message) return "";
        const run = flow.message.match(/^Authentication is needed to run [`'](.+?)[`'] as (.+)$/);
        if (run) {
            const who = run[2] === "the super user" ? "管理者" : run[2].replace(/^user /, "");
            return run[1] + " を" + who + "として実行するには、認証が必要です";
        }
        return flow.message;
    }

    function fieldPlaceholder() {
        const flow = agent.flow;
        if (!flow) return "パスワード";
        const prompt = (flow.inputPrompt || "").toLowerCase();
        if (flow.responseVisible && (prompt.includes("user") || prompt.includes("ユーザー") || prompt.includes("名前")))
            return "ユーザー名";
        if (!flow.responseVisible) return "パスワード";
        return flow.inputPrompt || "";
    }

    function screenOfFocus() {
        const focused = Hyprland.focusedMonitor;
        return Quickshell.screens.find(s => focused && s.name === focused.name) ?? Quickshell.screens[0];
    }

    PolkitAgent {
        id: agent

        onAuthenticationRequestStarted: {
            auth.secret = "";
            auth.targetScreen = auth.screenOfFocus();
            auth.ui.closeOverlays();
        }
    }

    Connections {
        target: agent.flow

        function onAuthenticationFailed() {
            auth.secret = "";
        }

        function onSelectedIdentityChanged() {
            auth.secret = "";
        }

        function onIsResponseRequiredChanged() {
            if (agent.flow && agent.flow.isResponseRequired) auth.secret = "";
        }
    }

    Variants {
        model: agent.isActive ? [auth.targetScreen] : []

        PanelWindow {
            id: win

            required property var modelData
            readonly property bool main: true
            readonly property var flow: agent.flow

            screen: modelData
            implicitWidth: card.width
            implicitHeight: card.height
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "auth"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            HyprlandFocusGrab {
                active: true
                windows: [win]
                onCleared: if (win.flow) win.flow.cancelAuthenticationRequest()
            }

            Rectangle {
                id: card

                visible: win.flow
                width: 440
                height: column.height + 42
                color: auth.ui.panel
                border.color: auth.ui.hairline
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: column
                    x: 21
                    y: 20
                    width: parent.width - 42
                    spacing: 16

                    Row {
                        width: parent.width
                        spacing: 14

                        Item {
                            width: 28
                            height: 28

                            IconImage {
                                id: actionIcon
                                anchors.fill: parent
                                visible: source.toString() !== ""
                                source: win.flow && win.flow.iconName ? Quickshell.iconPath(win.flow.iconName, "") : ""
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !actionIcon.visible
                                text: "󰌾"
                                font.family: auth.ui.symbols
                                font.pixelSize: 22
                                color: auth.ui.text2
                            }
                        }

                        Column {
                            width: parent.width - 42
                            spacing: 4

                            Text {
                                text: "認証"
                                font.family: auth.ui.font
                                font.pixelSize: 11
                                color: auth.ui.text3
                            }

                            Text {
                                width: parent.width
                                text: auth.messageText()
                                wrapMode: Text.WordWrap
                                maximumLineCount: 5
                                elide: Text.ElideRight
                                font.family: auth.ui.font
                                font.pixelSize: 14
                                color: auth.ui.text1
                            }
                        }
                    }

                    Text {
                        visible: win.flow && win.flow.identities.length > 1
                        width: parent.width
                        text: "どのユーザーで確認しますか"
                        font.family: auth.ui.font
                        font.pixelSize: 11
                        color: auth.ui.text3
                    }

                    Flow {
                        visible: win.flow && win.flow.identities.length > 1
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: win.flow ? win.flow.identities : []

                            delegate: Rectangle {
                                id: ident

                                required property var modelData
                                readonly property bool current: win.flow && win.flow.selectedIdentity === modelData

                                width: label.implicitWidth + 20
                                height: 28
                                color: current ? auth.ui.cream : "transparent"
                                border.color: current ? auth.ui.cream : auth.ui.hairline
                                border.width: 1

                                Text {
                                    id: label
                                    anchors.centerIn: parent
                                    text: auth.identityLabel(ident.modelData)
                                    font.family: auth.ui.font
                                    font.pixelSize: 12
                                    color: ident.current ? auth.ui.ink : auth.ui.text1
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (win.flow) win.flow.selectedIdentity = ident.modelData
                                }
                            }
                        }
                    }

                    Text {
                        visible: win.flow && win.flow.identities.length === 1
                        text: win.flow && win.flow.selectedIdentity ? auth.identityLabel(win.flow.selectedIdentity) + " として" : ""
                        font.family: auth.ui.font
                        font.pixelSize: 12
                        color: auth.ui.text2
                    }

                    Rectangle {
                        id: fieldBox
                        width: parent.width
                        height: 44
                        color: "transparent"
                        border.width: 1
                        border.color: win.flow && win.flow.failed && auth.secret === "" ? auth.fail : auth.ui.hairline

                        TextInput {
                            id: field
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            verticalAlignment: TextInput.AlignVCenter
                            text: auth.secret
                            onTextChanged: auth.secret = text
                            echoMode: win.flow && win.flow.responseVisible ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "●"
                            font.family: auth.ui.font
                            font.pixelSize: 16
                            color: auth.ui.text1
                            selectionColor: auth.ui.cream
                            selectedTextColor: auth.ui.ink
                            clip: true
                            Component.onCompleted: if (win.main) forceActiveFocus()

                            cursorDelegate: Rectangle {
                                width: 1.5
                                color: auth.ui.cream
                            }

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: auth.fieldPlaceholder()
                                font: field.font
                                color: auth.ui.text3
                                visible: field.text === "" && field.preeditText === "" && !(win.flow && win.flow.responseVisible)
                            }

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    if (win.flow) win.flow.cancelAuthenticationRequest();
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (win.flow && win.flow.isResponseRequired) win.flow.submit(auth.secret);
                                } else {
                                    return;
                                }
                                event.accepted = true;
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: {
                            const flow = win.flow;
                            if (!flow) return "";
                            if (flow.supplementaryMessage && flow.supplementaryIsError) return flow.supplementaryMessage;
                            if (flow.failed) return "パスワードが違います";
                            return flow.supplementaryMessage || "";
                        }
                        color: win.flow && (win.flow.supplementaryIsError || win.flow.failed) ? auth.fail : auth.ui.text3
                        font.family: auth.ui.font
                        font.pixelSize: 12
                        visible: text !== ""
                    }

                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            id: cancel
                            width: (parent.width - 8) / 2
                            height: 40
                            color: cancelMouse.containsMouse ? auth.ui.cream : "transparent"
                            border.color: cancelMouse.containsMouse ? auth.ui.cream : auth.ui.hairline
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "キャンセル"
                                font.family: auth.ui.font
                                font.pixelSize: 13
                                color: cancelMouse.containsMouse ? auth.ui.ink : auth.ui.text1
                            }

                            MouseArea {
                                id: cancelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: if (win.flow) win.flow.cancelAuthenticationRequest()
                            }
                        }

                        Rectangle {
                            id: accept
                            readonly property bool ready: win.flow && win.flow.isResponseRequired
                            width: (parent.width - 8) / 2
                            height: 40
                            color: ready ? auth.ui.cream : "transparent"
                            border.color: ready ? auth.ui.cream : auth.ui.hairline
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "認証"
                                font.family: auth.ui.font
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: accept.ready ? auth.ui.ink : auth.ui.text3
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: accept.ready
                                onClicked: if (win.flow) win.flow.submit(auth.secret)
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: "↵ 認証    esc キャンセル"
                        font.family: auth.ui.font
                        font.pixelSize: 11
                        color: auth.ui.text3
                    }
                }
            }
        }
    }
}
