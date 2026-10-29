import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Networking
import Quickshell.Bluetooth

// Separate panels for the calendar, now playing, volume, brightness, Wi-Fi, VPN and Bluetooth.
// Built-in panels use the backlight. When one is connected it is the main output.
Scope {
    id: panel

    required property var ui

    readonly property int cell: 36
    readonly property int gap: 4
    readonly property int gridWidth: 7 * cell + 6 * gap
    readonly property int panelWidth: gridWidth + 32
    // Header, rule, weekday row, then six date rows. No padding under the grid.
    readonly property int calendarBody: 44 + 1 + 28 + 6 * cell + 5 * gap
    readonly property var weekdays: ["日", "月", "火", "水", "木", "金", "土"]

    property bool open: false
    property string mode: "calendar"
    property var targetScreen: Quickshell.screens[0]
    property int viewYear: 2026
    property int viewMonth: 0
    property date selected: new Date()
    property date today: new Date()

    readonly property var player: {
        const list = Mpris.players && Mpris.players.values ? Mpris.players.values : [];
        for (const p of list)
            if (p.isPlaying) return p;
        return list.length > 0 ? list[0] : null;
    }
    property real volume: 0
    property bool muted: false
    property bool volumeDrag: false
    property int brightness: 100
    property bool brightnessDrag: false
    property string brightnessOutput: ""

    readonly property int listRow: 36
    readonly property int listRows: 7

    readonly property var wifiDevice: {
        const list = Networking.devices ? Networking.devices.values : [];
        for (const d of list)
            if (d.type === DeviceType.Wifi) return d;
        return null;
    }
    readonly property var wifiNetworks: {
        if (!wifiDevice || !Networking.wifiEnabled) return [];
        const list = wifiDevice.networks.values.filter(n => n.name);
        list.sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength));
        const seen = {};
        return list.filter(n => seen[n.name] ? false : (seen[n.name] = true));
    }
    property string pskTarget: ""
    property string wifiError: ""
    property bool hiddenOpen: false

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btDevices: {
        if (!btAdapter || !btAdapter.enabled) return [];
        const list = btAdapter.devices.values.filter(d => d.paired || d.connected || d.deviceName);
        list.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name));
        return list;
    }
    property string btError: ""

    property var vpnList: []
    property string vpnError: ""
    property string vpnAsk: ""
    property string vpnBusy: ""

    Timer {
        interval: 30000
        repeat: true
        running: panel.open
        onTriggered: panel.today = new Date()
    }

    function cellAt(index, year, month) {
        const first = new Date(year, month, 1).getDay();
        const start = new Date(year, month, 1 - first);
        const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + index);
        return { day: d.getDate(), month: d.getMonth(), year: d.getFullYear(), inMonth: d.getMonth() === month };
    }

    function sameDay(date, year, month, day) {
        return date.getFullYear() === year && date.getMonth() === month && date.getDate() === day;
    }

    function shiftMonth(delta) {
        const d = new Date(viewYear, viewMonth + delta, 1);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
    }

    function clock(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0));
        const m = Math.floor(s / 60);
        const h = Math.floor(m / 60);
        const pad = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + pad(m % 60) + ":" + pad(s % 60) : (m % 60) + ":" + pad(s % 60);
    }

    function show(kind, screenName) {
        if (ui.authOpen) return;
        // Switching modes keeps the window: closing it here would also drop its focus grab.
        if (!open) ui.closeOverlays();
        const named = Quickshell.screens.find(s => s.name === screenName);
        const focused = Hyprland.focusedMonitor;
        targetScreen = named ?? Quickshell.screens.find(s => focused && s.name === focused.name) ?? Quickshell.screens[0];
        mode = kind || "calendar";
        today = new Date();
        selected = today;
        viewYear = today.getFullYear();
        viewMonth = today.getMonth();
        if (mode === "volume") refreshVolume();
        if (mode === "brightness") {
            brightnessOutput = targetScreen.name || "";
            refreshBrightness();
        }
        pskTarget = "";
        wifiError = "";
        hiddenOpen = false;
        btError = "";
        vpnError = "";
        vpnAsk = "";
        if (mode === "vpn") refreshVpn();
        open = true;
        syncScanning();
    }

    function hide() {
        open = false;
        pskTarget = "";
        hiddenOpen = false;
        syncScanning();
    }

    // Scan only while the matching panel is on screen.
    function syncScanning() {
        const wifiWanted = open && mode === "wifi";
        if (wifiDevice && wifiDevice.scannerEnabled !== wifiWanted) wifiDevice.scannerEnabled = wifiWanted;
        if (!btAdapter || !btAdapter.enabled) return;
        if (open && mode === "bluetooth") {
            btScanOwned = true;
            if (!btAdapter.discovering) btAdapter.discovering = true;
        } else if (btScanOwned) {
            if (btAdapter.discovering) btAdapter.discovering = false;
            else btScanOwned = false;
        }
    }

    // Discovery can start a while after it was requested (and bt-agent accepts pairing
    // only while discovering), so keep stopping a scan this panel started once it is closed.
    property bool btScanOwned: false

    function signalGlyph(strength) {
        const icons = ["󰤟", "󰤢", "󰤥", "󰤨"];
        return icons[Math.max(0, Math.min(3, Math.floor(strength * 4)))];
    }

    function isSecured(network) {
        return network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.Owe;
    }

    function wifiActivate(network) {
        wifiError = "";
        if (network.connected) network.disconnect();
        else if (network.known || !isSecured(network)) network.connect();
        else pskTarget = pskTarget === network.name ? "" : network.name;
    }

    function connectHidden(ssid, psk) {
        const raw = ssid || "";
        const name = (raw.normalize ? raw.normalize("NFKC") : raw).trim();
        if (!name) {
            wifiError = "SSID を入力してください";
            return;
        }
        if (!wifiDevice) {
            wifiError = "Wi-Fi デバイスがありません";
            return;
        }
        if (!Networking.wifiEnabled) Networking.wifiEnabled = true;
        wifiError = "";
        // device wifi connect only searches the scan list, so a hidden SSID is "not found".
        const cmd = [Quickshell.env("HOME") + "/.config/hypr/scripts/wifi-hidden", wifiDevice.name, name];
        if (psk) cmd.push(psk);
        hiddenConnect.command = cmd;
        hiddenConnect.running = true;
    }

    function wifiStatus(network) {
        if (network.connected) return "接続中";
        if (network.stateChanging) return "接続しています…";
        if (network.known) return "保存済み";
        return "";
    }

    function btGlyph(device) {
        const icon = device.icon || "";
        if (icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1) return "󰋋";
        if (icon.indexOf("audio") !== -1) return "󰓃";
        if (icon.indexOf("mouse") !== -1) return "󰍽";
        if (icon.indexOf("keyboard") !== -1) return "󰌌";
        if (icon.indexOf("gaming") !== -1) return "󰊴";
        if (icon.indexOf("phone") !== -1) return "󰏲";
        if (icon.indexOf("computer") !== -1) return "󰟀";
        return "󰂯";
    }

    function btStatus(device) {
        if (device.connected) return device.batteryAvailable ? "接続中 · " + Math.round(device.battery * 100) + "%" : "接続中";
        if (device.pairing) return "ペアリング中…";
        if (device.state === BluetoothDeviceState.Connecting) return "接続しています…";
        if (device.paired) return "ペアリング済み";
        return "";
    }

    function btActivate(device) {
        btError = "";
        if (device.connected) device.disconnect();
        else if (device.paired) device.connect();
        else device.pair();
    }

    function refreshVpn() {
        if (!vpnQuery.running) vpnQuery.running = true;
    }

    function applyVpn(text) {
        try {
            const parsed = JSON.parse(text);
            vpnList = Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            vpnList = [];
        }
    }

    function vpnActivate(entry) {
        vpnError = "";
        vpnAsk = "";
        vpnBusy = entry.uuid;
        const script = Quickshell.env("HOME") + "/.config/hypr/scripts/vpn";
        if (entry.active) {
            vpnDown.command = [script, "down", entry.uuid];
            vpnDown.running = true;
        } else {
            vpnUp.command = [script, "up", entry.uuid];
            vpnUp.running = true;
        }
    }

    function vpnWithPassword(uuid, psk) {
        if (!psk) {
            vpnError = "パスワードを入力してください";
            return;
        }
        vpnError = "";
        vpnAsk = "";
        vpnBusy = uuid;
        vpnUp.command = [Quickshell.env("HOME") + "/.config/hypr/scripts/vpn", "up", uuid, psk];
        vpnUp.running = true;
    }

    function vpnStatus(entry) {
        if (entry.uuid === vpnBusy) return entry.active ? "切断しています…" : "接続しています…";
        if (entry.active) return "接続中";
        return entry.type || "";
    }

    function finishVpn(code, text) {
        const uuid = vpnBusy;
        const msg = (text || "").trim().split("\n")[0];
        vpnBusy = "";
        if (code !== 0 && msg.indexOf("パスワード") !== -1) vpnAsk = uuid;
        vpnError = code === 0 ? "" : (msg || "接続できませんでした");
        refreshVpn();
    }

    Connections {
        target: panel.btAdapter

        function onEnabledChanged() {
            panel.syncScanning();
        }

        function onDiscoveringChanged() {
            panel.syncScanning();
        }
    }

    // An outside click also reaches whatever was clicked (often the same bar module);
    // toggling that same panel right after must not reopen it.
    property double dismissedAt: 0
    property string dismissedKey: ""

    function dismiss() {
        dismissedAt = Date.now();
        dismissedKey = mode + "@" + (targetScreen ? targetScreen.name : "");
        hide();
    }

    function refreshVolume() {
        if (!volumeQuery.running) volumeQuery.running = true;
    }

    function applyVolumeLine(line) {
        const match = line.match(/([\d.]+)/);
        if (!match || volumeDrag) return;
        volume = Math.max(0, Math.min(1, parseFloat(match[1])));
        muted = line.indexOf("MUTED") !== -1;
    }

    function setVolume(value) {
        volume = Math.max(0, Math.min(1, value));
        if (volume > 0) muted = false;
        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", volume.toFixed(3)]);
    }

    function toggleMute() {
        muted = !muted;
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
    }

    function refreshBrightness() {
        if (!brightnessOutput) return;
        brightnessQuery.command = [Quickshell.env("HOME") + "/.config/hypr/scripts/brightness", "get", brightnessOutput];
        if (!brightnessQuery.running) brightnessQuery.running = true;
    }

    function applyBrightnessLine(line) {
        const value = parseInt(line.trim(), 10);
        if (brightnessDrag || isNaN(value)) return;
        brightness = Math.max(0, Math.min(100, value));
    }

    function setBrightness(value) {
        brightness = Math.max(0, Math.min(100, Math.round(value)));
        brightnessCommit.restart();
    }

    function commitBrightness() {
        if (!brightnessOutput) return;
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/brightness", "set", brightnessOutput, String(brightness)]);
    }

    Process {
        id: volumeQuery
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            id: volumeOut
        }
        onExited: panel.applyVolumeLine(volumeOut.text)
    }

    Process {
        id: brightnessQuery
        stdout: StdioCollector {
            id: brightnessOut
        }
        onExited: panel.applyBrightnessLine(brightnessOut.text)
    }

    Timer {
        id: brightnessCommit
        interval: 180
        onTriggered: panel.commitBrightness()
    }

    Process {
        id: hiddenConnect
        stdout: StdioCollector { id: hiddenOut }
        stderr: StdioCollector { id: hiddenErr }
        onExited: {
            if (exitCode === 0) {
                panel.hiddenOpen = false;
                panel.wifiError = "";
                return;
            }
            const msg = (hiddenErr.text || hiddenOut.text || "").trim().split("\n")[0];
            panel.wifiError = msg || "接続できませんでした";
        }
    }

    Process {
        id: vpnQuery
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/vpn", "list"]
        stdout: StdioCollector { id: vpnOut }
        onExited: panel.applyVpn(vpnOut.text)
    }

    Process {
        id: vpnUp
        stderr: StdioCollector { id: vpnUpErr }
        stdout: StdioCollector { id: vpnUpOut }
        onExited: panel.finishVpn(exitCode, vpnUpErr.text || vpnUpOut.text)
    }

    Process {
        id: vpnDown
        stderr: StdioCollector { id: vpnDownErr }
        stdout: StdioCollector { id: vpnDownOut }
        onExited: panel.finishVpn(exitCode, vpnDownErr.text || vpnDownOut.text)
    }

    Timer {
        interval: 1000
        repeat: true
        running: panel.open && panel.mode === "volume" && !panel.volumeDrag
        onTriggered: panel.refreshVolume()
    }

    Timer {
        interval: 2000
        repeat: true
        running: panel.open && panel.mode === "vpn" && panel.vpnAsk === "" && panel.vpnBusy === ""
        onTriggered: panel.refreshVpn()
    }

    Component.onCompleted: refreshVolume()

    IpcHandler {
        target: "panel"

        function toggle(kind: string, screenName: string): void {
            if (panel.open && panel.mode === kind && panel.targetScreen && panel.targetScreen.name === screenName) panel.hide();
            else if (panel.open || Date.now() - panel.dismissedAt > 400 || panel.dismissedKey !== kind + "@" + screenName) panel.show(kind, screenName);
        }

        function close(): void {
            panel.hide();
        }
    }

    Variants {
        model: panel.open ? [panel.targetScreen] : []

        PanelWindow {
            id: win

            required property var modelData
            readonly property bool main: true

            screen: modelData
            anchors.top: true
            anchors.right: true
            margins.top: 38
            margins.right: 8
            implicitWidth: card.width
            implicitHeight: card.height
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "panel"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            HyprlandFocusGrab {
                active: true
                windows: [win]
                onCleared: panel.dismiss()
            }

            Rectangle {
                id: card

                width: panel.mode === "calendar" ? panel.panelWidth : 320
                height: (panel.mode === "calendar" ? panel.calendarBody : column.implicitHeight) + 2
                color: panel.ui.panel
                border.color: panel.ui.hairline
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                }

                Item {
                    focus: true
                    Component.onCompleted: if (win.main) forceActiveFocus()

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) panel.hide();
                        else if (panel.mode === "calendar" && (event.key === Qt.Key_Left || event.key === Qt.Key_H)) panel.shiftMonth(-1);
                        else if (panel.mode === "calendar" && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) panel.shiftMonth(1);
                        else if (panel.mode === "calendar" && event.key === Qt.Key_T) {
                            panel.today = new Date();
                            panel.selected = panel.today;
                            panel.viewYear = panel.today.getFullYear();
                            panel.viewMonth = panel.today.getMonth();
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }

                Column {
                    id: column
                    x: 16
                    y: 1
                    width: panel.mode === "calendar" ? panel.gridWidth : 288
                    spacing: 0

                    Item {
                        visible: panel.mode === "calendar"
                        width: parent.width
                        height: 44

                        Text {
                            id: prevMonth
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "←"
                            font.family: panel.ui.font
                            font.pixelSize: 14
                            color: prevMouse.containsMouse ? panel.ui.text1 : panel.ui.text3

                            MouseArea {
                                id: prevMouse
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.shiftMonth(-1)
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: panel.viewYear + "年" + (panel.viewMonth + 1) + "月"
                            font.family: panel.ui.font
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: panel.ui.text1
                        }

                        Text {
                            id: nextMonth
                            anchors.right: todayLink.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "→"
                            font.family: panel.ui.font
                            font.pixelSize: 14
                            color: nextMouse.containsMouse ? panel.ui.text1 : panel.ui.text3

                            MouseArea {
                                id: nextMouse
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.shiftMonth(1)
                            }
                        }

                        Text {
                            id: todayLink
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "今日"
                            font.family: panel.ui.font
                            font.pixelSize: 12
                            font.underline: todayMouse.containsMouse
                            color: todayMouse.containsMouse ? panel.ui.text1 : panel.ui.text2

                            MouseArea {
                                id: todayMouse
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panel.today = new Date();
                                    panel.selected = panel.today;
                                    panel.viewYear = panel.today.getFullYear();
                                    panel.viewMonth = panel.today.getMonth();
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: panel.mode === "calendar"
                        width: parent.width
                        height: 1
                        color: panel.ui.hairline
                    }

                    Row {
                        visible: panel.mode === "calendar"
                        width: panel.gridWidth
                        height: 28
                        spacing: panel.gap

                        Repeater {
                            model: panel.weekdays

                            delegate: Text {
                                required property string modelData
                                width: panel.cell
                                height: 28
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: modelData
                                font.family: panel.ui.font
                                font.pixelSize: 11
                                color: panel.ui.text3
                            }
                        }
                    }

                    Grid {
                        visible: panel.mode === "calendar"
                        columns: 7
                        columnSpacing: panel.gap
                        rowSpacing: panel.gap

                        Repeater {
                            model: 42

                            delegate: Rectangle {
                                id: day

                                required property int index
                                readonly property var cell: panel.cellAt(index, panel.viewYear, panel.viewMonth)
                                readonly property bool isToday: panel.sameDay(panel.today, cell.year, cell.month, cell.day)
                                readonly property bool isSelected: panel.sameDay(panel.selected, cell.year, cell.month, cell.day)

                                width: panel.cell
                                height: panel.cell
                                color: isToday ? panel.ui.cream : dayMouse.containsMouse ? panel.ui.hover : "transparent"
                                border.width: isSelected && !isToday ? 1 : 0
                                border.color: panel.ui.cream

                                Text {
                                    anchors.centerIn: parent
                                    text: day.cell.day
                                    font.family: panel.ui.font
                                    font.pixelSize: 13
                                    font.weight: day.isToday || day.isSelected ? Font.DemiBold : Font.Normal
                                    color: day.isToday ? panel.ui.ink : day.cell.inMonth ? panel.ui.text1 : panel.ui.text3
                                }

                                MouseArea {
                                    id: dayMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        panel.selected = new Date(day.cell.year, day.cell.month, day.cell.day);
                                        panel.viewYear = day.cell.year;
                                        panel.viewMonth = day.cell.month;
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        visible: panel.mode === "music"
                        width: parent.width
                        height: 12
                    }

                    Column {
                        visible: panel.mode === "music"
                        width: parent.width
                        spacing: 10

                        Text {
                            text: "再生中"
                            font.family: panel.ui.font
                            font.pixelSize: 11
                            color: panel.ui.text3
                        }

                        Item {
                            width: parent.width
                            height: panel.player ? 48 : 28
                            visible: !panel.player

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "再生していません"
                                font.family: panel.ui.font
                                font.pixelSize: 13
                                color: panel.ui.text3
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 12
                            visible: panel.player

                            Rectangle {
                                width: 48
                                height: 48
                                color: panel.ui.hover
                                border.color: panel.ui.hairline
                                border.width: 1

                                Image {
                                    id: art
                                    anchors.fill: parent
                                    source: panel.player && panel.player.trackArtUrl ? panel.player.trackArtUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: art.status !== Image.Ready
                                    text: "󰎈"
                                    font.family: panel.ui.symbols
                                    font.pixelSize: 18
                                    color: panel.ui.text3
                                }
                            }

                            Column {
                                width: parent.width - 60
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Text {
                                    width: parent.width
                                    text: panel.player ? (panel.player.trackTitle || "不明な曲") : ""
                                    elide: Text.ElideRight
                                    font.family: panel.ui.font
                                    font.pixelSize: 14
                                    color: panel.ui.text1
                                }

                                Text {
                                    width: parent.width
                                    text: panel.player ? (panel.player.trackArtist || panel.player.identity || "") : ""
                                    elide: Text.ElideRight
                                    font.family: panel.ui.font
                                    font.pixelSize: 12
                                    color: panel.ui.text2
                                }
                            }
                        }

                        Item {
                            visible: panel.player
                            width: parent.width
                            height: 4

                            Rectangle {
                                anchors.fill: parent
                                color: panel.ui.hairline
                            }

                            Rectangle {
                                width: parent.width * (panel.player && panel.player.lengthSupported && panel.player.length > 0 ? Math.min(1, panel.player.position / panel.player.length) : 0)
                                height: parent.height
                                color: panel.ui.cream
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.topMargin: -8
                                anchors.bottomMargin: -8
                                enabled: panel.player && panel.player.canSeek && panel.player.length > 0
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: mouse => {
                                    panel.player.position = panel.player.length * Math.max(0, Math.min(1, mouse.x / width));
                                }
                            }
                        }

                        Item {
                            visible: panel.player && panel.player.lengthSupported && panel.player.length > 0
                            width: parent.width
                            height: 14

                            Text {
                                anchors.left: parent.left
                                text: panel.player ? panel.clock(panel.player.position) : ""
                                font.family: panel.ui.font
                                font.pixelSize: 11
                                color: panel.ui.text3
                            }

                            Text {
                                anchors.right: parent.right
                                text: panel.player ? panel.clock(panel.player.length) : ""
                                font.family: panel.ui.font
                                font.pixelSize: 11
                                color: panel.ui.text3
                            }
                        }

                        Item {
                            visible: panel.player
                            width: parent.width
                            height: 32

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8

                            Repeater {
                                model: [
                                    { glyph: "󰒮", action: "previous", enabled: panel.player && panel.player.canGoPrevious },
                                    { glyph: panel.player && panel.player.isPlaying ? "󰏤" : "󰐊", action: "toggle", enabled: panel.player && panel.player.canTogglePlaying },
                                    { glyph: "󰒭", action: "next", enabled: panel.player && panel.player.canGoNext },
                                ]

                                delegate: Rectangle {
                                    id: transport

                                    required property var modelData
                                    width: 36
                                    height: 32
                                    color: transportMouse.containsMouse && modelData.enabled ? panel.ui.cream : "transparent"
                                    border.color: panel.ui.hairline
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: transport.modelData.glyph
                                        font.family: panel.ui.symbols
                                        font.pixelSize: 16
                                        color: !transport.modelData.enabled ? panel.ui.text3 : transportMouse.containsMouse ? panel.ui.ink : panel.ui.text1
                                    }

                                    MouseArea {
                                        id: transportMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: transport.modelData.enabled
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            const p = panel.player;
                                            if (!p) return;
                                            if (transport.modelData.action === "previous") p.previous();
                                            else if (transport.modelData.action === "next") p.next();
                                            else p.togglePlaying();
                                        }
                                    }
                                }
                            }
                        }
                        }
                    }

                    Item {
                        visible: panel.mode === "volume"
                        width: parent.width
                        height: 12
                    }

                    Column {
                        visible: panel.mode === "volume"
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "音量"
                            font.family: panel.ui.font
                            font.pixelSize: 11
                            color: panel.ui.text3
                        }

                        Item {
                            width: parent.width
                            height: 28

                            Text {
                                id: volumeIcon
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (panel.muted || panel.volume <= 0) return "󰝟";
                                    if (panel.volume < 0.33) return "󰕿";
                                    if (panel.volume < 0.66) return "󰖀";
                                    return "󰕾";
                                }
                                font.family: panel.ui.symbols
                                font.pixelSize: 16
                                color: volumeIconMouse.containsMouse ? panel.ui.text1 : panel.ui.text2

                                MouseArea {
                                    id: volumeIconMouse
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.toggleMute()
                                }
                            }

                            Item {
                                id: slider
                                anchors.left: volumeIcon.right
                                anchors.leftMargin: 12
                                anchors.right: volumeText.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                height: 28

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 4
                                    color: panel.ui.hairline

                                    Rectangle {
                                        width: parent.width * panel.volume
                                        height: parent.height
                                        color: panel.muted ? panel.ui.text3 : panel.ui.cream
                                    }
                                }

                                MouseArea {
                                    id: sliderMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: mouse => {
                                        panel.volumeDrag = true;
                                        panel.setVolume(mouse.x / width);
                                    }
                                    onReleased: panel.volumeDrag = false
                                    onPositionChanged: mouse => {
                                        if (sliderMouse.pressed) panel.setVolume(mouse.x / width);
                                    }
                                    onWheel: wheel => panel.setVolume(panel.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                                }
                            }

                            Text {
                                id: volumeText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(panel.volume * 100) + "%"
                                font.family: panel.ui.font
                                font.pixelSize: 12
                                color: panel.ui.text1
                            }
                        }
                    }

                    Item {
                        visible: panel.mode === "brightness"
                        width: parent.width
                        height: 12
                    }

                    Column {
                        visible: panel.mode === "brightness"
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "明るさ"
                            font.family: panel.ui.font
                            font.pixelSize: 11
                            color: panel.ui.text3
                        }

                        Item {
                            width: parent.width
                            height: 28

                            Text {
                                id: brightnessIcon
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰖨"
                                font.family: panel.ui.symbols
                                font.pixelSize: 16
                                color: panel.ui.text2
                            }

                            Item {
                                anchors.left: brightnessIcon.right
                                anchors.leftMargin: 12
                                anchors.right: brightnessText.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                height: 28

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 4
                                    color: panel.ui.hairline

                                    Rectangle {
                                        width: parent.width * panel.brightness / 100
                                        height: parent.height
                                        color: panel.ui.cream
                                    }
                                }

                                MouseArea {
                                    id: brightnessMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: mouse => {
                                        panel.brightnessDrag = true;
                                        panel.setBrightness(mouse.x / width * 100);
                                    }
                                    onReleased: {
                                        panel.brightnessDrag = false;
                                        panel.commitBrightness();
                                    }
                                    onPositionChanged: mouse => {
                                        if (brightnessMouse.pressed) panel.setBrightness(mouse.x / width * 100);
                                    }
                                }
                            }

                            Text {
                                id: brightnessText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36
                                horizontalAlignment: Text.AlignRight
                                text: panel.brightness + "%"
                                font.family: panel.ui.font
                                font.pixelSize: 12
                                color: panel.ui.text1
                            }
                        }
                    }

                    Item {
                        visible: panel.mode === "wifi" || panel.mode === "vpn" || panel.mode === "bluetooth"
                        width: parent.width
                        height: 12
                    }

                    // Wi-Fi
                    Column {
                        visible: panel.mode === "wifi"
                        width: parent.width
                        spacing: 8

                        Item {
                            width: parent.width
                            height: 18

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Wi-Fi"
                                font.family: panel.ui.font
                                font.pixelSize: 11
                                color: panel.ui.text3
                            }

                            Rectangle {
                                id: wifiSwitch

                                readonly property bool on: Networking.wifiEnabled

                                anchors.right: parent.right
                                width: 34
                                height: 18
                                color: on ? panel.ui.cream : "transparent"
                                border.color: on ? panel.ui.cream : panel.ui.text3
                                border.width: 1

                                Rectangle {
                                    x: wifiSwitch.on ? parent.width - width - 3 : 3
                                    y: 3
                                    width: 12
                                    height: 12
                                    color: wifiSwitch.on ? panel.ui.ink : panel.ui.text3
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                                }
                            }
                        }

                        Text {
                            visible: panel.wifiNetworks.length === 0
                            width: parent.width
                            height: 28
                            verticalAlignment: Text.AlignVCenter
                            text: !panel.wifiDevice ? "Wi-Fi デバイスがありません"
                                : !Networking.wifiEnabled ? "Wi-Fi はオフです"
                                : "ネットワークを探しています…"
                            font.family: panel.ui.font
                            font.pixelSize: 13
                            color: panel.ui.text3
                        }

                        Flickable {
                            visible: panel.wifiNetworks.length > 0
                            width: parent.width
                            implicitHeight: height
                            height: Math.min(wifiList.childrenRect.height, panel.listRows * panel.listRow + 44)
                            contentHeight: wifiList.childrenRect.height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: wifiList
                                width: parent.width

                                Repeater {
                                    model: panel.wifiNetworks

                                    delegate: Column {
                                        id: net

                                        required property var modelData
                                        readonly property bool asking: panel.pskTarget === modelData.name

                                        width: wifiList.width

                                        Connections {
                                            target: net.modelData

                                            function onConnectionFailed(reason) {
                                                if (reason === ConnectionFailReason.NoSecrets && panel.isSecured(net.modelData)) {
                                                    panel.pskTarget = net.modelData.name;
                                                    panel.wifiError = "パスワードを入力してください";
                                                } else {
                                                    panel.wifiError = net.modelData.name + " に接続できませんでした";
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width
                                            height: panel.listRow
                                            color: net.modelData.connected ? panel.ui.hover : netMouse.containsMouse ? panel.ui.hover : "transparent"

                                            Text {
                                                id: netIcon
                                                x: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: panel.signalGlyph(net.modelData.signalStrength)
                                                font.family: panel.ui.symbols
                                                font.pixelSize: 16
                                                color: net.modelData.connected ? panel.ui.text1 : panel.ui.text2
                                            }

                                            Text {
                                                anchors.left: netIcon.right
                                                anchors.leftMargin: 12
                                                anchors.right: netState.left
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: net.modelData.name
                                                elide: Text.ElideRight
                                                font.family: panel.ui.font
                                                font.pixelSize: 13
                                                font.weight: net.modelData.connected ? Font.DemiBold : Font.Normal
                                                color: panel.ui.text1
                                            }

                                            Row {
                                                id: netState
                                                anchors.right: parent.right
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 6

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: panel.wifiStatus(net.modelData)
                                                    font.family: panel.ui.font
                                                    font.pixelSize: 11
                                                    color: net.modelData.connected ? panel.ui.text1 : panel.ui.text3
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: panel.isSecured(net.modelData)
                                                    text: "󰌾"
                                                    font.family: panel.ui.symbols
                                                    font.pixelSize: 12
                                                    color: panel.ui.text3
                                                }
                                            }

                                            MouseArea {
                                                id: netMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: panel.wifiActivate(net.modelData)
                                            }
                                        }

                                        Item {
                                            visible: net.asking
                                            width: parent.width
                                            height: 44

                                            Rectangle {
                                                x: 8
                                                y: 4
                                                width: parent.width - 16
                                                height: 32
                                                color: "transparent"
                                                border.color: psk.activeFocus ? panel.ui.cream : panel.ui.hairline
                                                border.width: 1

                                                TextInput {
                                                    id: psk
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    echoMode: TextInput.Password
                                                    passwordCharacter: "•"
                                                    font.family: panel.ui.font
                                                    font.pixelSize: 13
                                                    color: panel.ui.text1
                                                    selectionColor: panel.ui.cream
                                                    selectedTextColor: panel.ui.ink
                                                    clip: true
                                                    onVisibleChanged: {
                                                        text = "";
                                                        if (visible) forceActiveFocus();
                                                    }
                                                    onAccepted: {
                                                        if (!text) return;
                                                        panel.wifiError = "";
                                                        net.modelData.connectWithPsk(text);
                                                        panel.pskTarget = "";
                                                    }
                                                    Keys.onEscapePressed: panel.pskTarget = ""

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: !psk.text
                                                        text: "パスワード · Enter で接続"
                                                        font.family: panel.ui.font
                                                        font.pixelSize: 13
                                                        color: panel.ui.text3
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: panel.listRow
                                    color: hiddenMouse.containsMouse || panel.hiddenOpen ? panel.ui.hover : "transparent"

                            Text {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰤫"
                                font.family: panel.ui.symbols
                                font.pixelSize: 16
                                color: panel.ui.text2
                            }

                            Text {
                                x: 36
                                anchors.verticalCenter: parent.verticalCenter
                                text: "非公開のネットワーク"
                                font.family: panel.ui.font
                                font.pixelSize: 13
                                color: panel.ui.text1
                            }

                            MouseArea {
                                id: hiddenMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panel.hiddenOpen = !panel.hiddenOpen;
                                    if (panel.hiddenOpen) hiddenSsid.forceActiveFocus();
                                }
                            }
                        }

                        Column {
                            visible: panel.hiddenOpen
                            width: parent.width
                            spacing: 8

                            Rectangle {
                                x: 8
                                width: parent.width - 16
                                height: 32
                                color: "transparent"
                                border.color: hiddenSsid.activeFocus ? panel.ui.cream : panel.ui.hairline
                                border.width: 1

                                TextInput {
                                    id: hiddenSsid
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.family: panel.ui.font
                                    font.pixelSize: 13
                                    color: panel.ui.text1
                                    selectionColor: panel.ui.cream
                                    selectedTextColor: panel.ui.ink
                                    clip: true
                                    onVisibleChanged: if (!visible) text = ""
                                    onAccepted: hiddenPsk.forceActiveFocus()
                                    Keys.onEscapePressed: panel.hiddenOpen = false
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: hiddenSsid.text.length === 0
                                    text: "SSID"
                                    font.family: panel.ui.font
                                    font.pixelSize: 13
                                    color: panel.ui.text3
                                }
                            }

                            Rectangle {
                                x: 8
                                width: parent.width - 16
                                height: 32
                                color: "transparent"
                                border.color: hiddenPsk.activeFocus ? panel.ui.cream : panel.ui.hairline
                                border.width: 1

                                TextInput {
                                    id: hiddenPsk
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password
                                    passwordCharacter: "•"
                                    font.family: panel.ui.font
                                    font.pixelSize: 13
                                    color: panel.ui.text1
                                    selectionColor: panel.ui.cream
                                    selectedTextColor: panel.ui.ink
                                    clip: true
                                    onVisibleChanged: if (!visible) text = ""
                                    onAccepted: panel.connectHidden(hiddenSsid.text, text)
                                    Keys.onEscapePressed: panel.hiddenOpen = false
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: hiddenPsk.text.length === 0
                                    text: "パスワード · 空欄可 · Enter"
                                    font.family: panel.ui.font
                                    font.pixelSize: 13
                                    color: panel.ui.text3
                                }
                            }
                        }
                        }
                        }

                        Text {
                            visible: panel.wifiError !== ""
                            width: parent.width
                            text: panel.wifiError
                            wrapMode: Text.Wrap
                            font.family: panel.ui.font
                            font.pixelSize: 12
                            color: panel.ui.fail
                        }
                    }

                    // VPN
                    Column {
                        visible: panel.mode === "vpn"
                        width: parent.width
                        spacing: 8

                        Text {
                            width: parent.width
                            height: 18
                            verticalAlignment: Text.AlignVCenter
                            text: "VPN"
                            font.family: panel.ui.font
                            font.pixelSize: 11
                            color: panel.ui.text3
                        }

                        Text {
                            visible: panel.vpnList.length === 0
                            width: parent.width
                            height: 28
                            verticalAlignment: Text.AlignVCenter
                            text: "保存された VPN がありません"
                            font.family: panel.ui.font
                            font.pixelSize: 13
                            color: panel.ui.text3
                        }

                        Flickable {
                            visible: panel.vpnList.length > 0
                            width: parent.width
                            implicitHeight: height
                            height: Math.min(vpnList.childrenRect.height, panel.listRows * panel.listRow + 44)
                            contentHeight: vpnList.childrenRect.height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: vpnList
                                width: parent.width

                                Repeater {
                                    model: panel.vpnList

                                    delegate: Column {
                                        id: vpn

                                        required property var modelData
                                        readonly property bool asking: panel.vpnAsk === modelData.uuid

                                        width: vpnList.width

                                        Rectangle {
                                            width: parent.width
                                            height: panel.listRow
                                            color: vpn.modelData.active ? panel.ui.hover : vpnMouse.containsMouse ? panel.ui.hover : "transparent"

                                            Text {
                                                id: vpnIcon
                                                x: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "󰖂"
                                                font.family: panel.ui.symbols
                                                font.pixelSize: 16
                                                color: vpn.modelData.active ? panel.ui.text1 : panel.ui.text2
                                            }

                                            Text {
                                                anchors.left: vpnIcon.right
                                                anchors.leftMargin: 12
                                                anchors.right: vpnState.left
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: vpn.modelData.name
                                                elide: Text.ElideRight
                                                font.family: panel.ui.font
                                                font.pixelSize: 13
                                                font.weight: vpn.modelData.active ? Font.DemiBold : Font.Normal
                                                color: panel.ui.text1
                                            }

                                            Text {
                                                id: vpnState
                                                anchors.right: parent.right
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: panel.vpnStatus(vpn.modelData)
                                                font.family: panel.ui.font
                                                font.pixelSize: 11
                                                color: vpn.modelData.active ? panel.ui.text1 : panel.ui.text3
                                            }

                                            MouseArea {
                                                id: vpnMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: panel.vpnActivate(vpn.modelData)
                                            }
                                        }

                                        Item {
                                            visible: vpn.asking
                                            width: parent.width
                                            height: 44

                                            Rectangle {
                                                x: 8
                                                y: 4
                                                width: parent.width - 16
                                                height: 32
                                                color: "transparent"
                                                border.color: vpnPsk.activeFocus ? panel.ui.cream : panel.ui.hairline
                                                border.width: 1

                                                TextInput {
                                                    id: vpnPsk
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    echoMode: TextInput.Password
                                                    passwordCharacter: "•"
                                                    font.family: panel.ui.font
                                                    font.pixelSize: 13
                                                    color: panel.ui.text1
                                                    selectionColor: panel.ui.cream
                                                    selectedTextColor: panel.ui.ink
                                                    clip: true
                                                    onVisibleChanged: {
                                                        text = "";
                                                        if (visible) forceActiveFocus();
                                                    }
                                                    onAccepted: panel.vpnWithPassword(vpn.modelData.uuid, text)
                                                    Keys.onEscapePressed: panel.vpnAsk = ""

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: !vpnPsk.text
                                                        text: "パスワード · Enter で接続"
                                                        font.family: panel.ui.font
                                                        font.pixelSize: 13
                                                        color: panel.ui.text3
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: panel.vpnError !== "" || panel.vpnList.length > 0
                            width: parent.width
                            text: panel.vpnError !== "" ? panel.vpnError : "クリックで接続 · もう一度で切断"
                            wrapMode: Text.Wrap
                            font.family: panel.ui.font
                            font.pixelSize: 11
                            color: panel.vpnError !== "" ? panel.ui.fail : panel.ui.text3
                        }
                    }

                    // Bluetooth
                    Column {
                        visible: panel.mode === "bluetooth"
                        width: parent.width
                        spacing: 8

                        Item {
                            width: parent.width
                            height: 18

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Bluetooth" + (panel.btAdapter && panel.btAdapter.discovering ? "  ·  探しています" : "")
                                font.family: panel.ui.font
                                font.pixelSize: 11
                                color: panel.ui.text3
                            }

                            Rectangle {
                                id: btSwitch

                                readonly property bool on: panel.btAdapter ? panel.btAdapter.enabled : false

                                anchors.right: parent.right
                                width: 34
                                height: 18
                                opacity: panel.btAdapter ? 1 : 0.4
                                color: on ? panel.ui.cream : "transparent"
                                border.color: on ? panel.ui.cream : panel.ui.text3
                                border.width: 1

                                Rectangle {
                                    x: btSwitch.on ? parent.width - width - 3 : 3
                                    y: 3
                                    width: 12
                                    height: 12
                                    color: btSwitch.on ? panel.ui.ink : panel.ui.text3
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    enabled: panel.btAdapter !== null
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.btAdapter.enabled = !panel.btAdapter.enabled
                                }
                            }
                        }

                        Text {
                            visible: panel.btDevices.length === 0
                            width: parent.width
                            height: 28
                            verticalAlignment: Text.AlignVCenter
                            text: !panel.btAdapter ? "Bluetooth アダプターがありません"
                                : !panel.btAdapter.enabled ? "Bluetooth はオフです"
                                : "機器を探しています…"
                            font.family: panel.ui.font
                            font.pixelSize: 13
                            color: panel.ui.text3
                        }

                        Flickable {
                            visible: panel.btDevices.length > 0
                            width: parent.width
                            height: Math.min(btList.implicitHeight, panel.listRows * panel.listRow)
                            contentHeight: btList.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: btList
                                width: parent.width

                                Repeater {
                                    model: panel.btDevices

                                    delegate: Rectangle {
                                        id: dev

                                        required property var modelData

                                        width: btList.width
                                        height: panel.listRow
                                        color: modelData.connected ? panel.ui.hover : devMouse.containsMouse ? panel.ui.hover : "transparent"

                                        Connections {
                                            target: dev.modelData

                                            function onPairedChanged() {
                                                if (!dev.modelData.paired) return;
                                                dev.modelData.trusted = true;
                                                dev.modelData.connect();
                                            }
                                        }

                                        Text {
                                            id: devIcon
                                            x: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: panel.btGlyph(dev.modelData)
                                            font.family: panel.ui.symbols
                                            font.pixelSize: 16
                                            color: dev.modelData.connected ? panel.ui.text1 : panel.ui.text2
                                        }

                                        Text {
                                            anchors.left: devIcon.right
                                            anchors.leftMargin: 12
                                            anchors.right: devState.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: dev.modelData.name
                                            elide: Text.ElideRight
                                            font.family: panel.ui.font
                                            font.pixelSize: 13
                                            font.weight: dev.modelData.connected ? Font.DemiBold : Font.Normal
                                            color: panel.ui.text1
                                        }

                                        Text {
                                            id: devState
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: panel.btStatus(dev.modelData)
                                            font.family: panel.ui.font
                                            font.pixelSize: 11
                                            color: dev.modelData.connected ? panel.ui.text1 : panel.ui.text3
                                        }

                                        MouseArea {
                                            id: devMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton && dev.modelData.paired) dev.modelData.forget();
                                                else panel.btActivate(dev.modelData);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: panel.btError !== "" ? panel.btError : "クリックで接続 · 右クリックで登録解除"
                            wrapMode: Text.Wrap
                            font.family: panel.ui.font
                            font.pixelSize: 11
                            color: panel.btError !== "" ? panel.ui.fail : panel.ui.text3
                        }
                    }

                    Item {
                        width: parent.width
                        height: 14
                    }
                }
            }
        }
    }
}
