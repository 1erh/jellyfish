import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Super+Tab. Workspaces on this monitor, each app in its own frame.
Scope {
    id: overview

    required property var ui

    readonly property int gutter: 8
    readonly property int pinned: 5
    readonly property int span: 10

    property bool open: false
    property var targetScreen: Quickshell.screens[0]
    property var cards: []
    property var minData: ({})
    property string snapshot: ""
    property int selectedWs: 0
    property int selectedIndex: -1

    readonly property string selectionTitle: {
        const entry = selectedEntry();
        if (!entry) return "";
        return entry.minimized ? entry.title + "  ·  最小化" : entry.title;
    }

    function hide() {
        open = false;
    }

    function show() {
        if (ui.authOpen) return;
        ui.closeOverlays();
        const focused = Hyprland.focusedMonitor;
        targetScreen = Quickshell.screens.find(s => focused && s.name === focused.name) ?? Quickshell.screens[0];
        minFile.reload();
        rebuild(true);
        open = true;
    }

    function listOf(model) {
        if (!model || model.values === undefined || model.values === null) return [];
        const values = model.values;
        const out = [];
        for (let i = 0; i < values.length; i++) out.push(values[i]);
        return out;
    }

    function internalOutput(name) {
        return name.startsWith("eDP-") || name.startsWith("LVDS-") || name.startsWith("DSI-");
    }

    function monitorNamed(name) {
        const monitors = listOf(Hyprland.monitors);
        for (let i = 0; i < monitors.length; i++) {
            if (monitors[i].name === name) return monitors[i];
        }
        return null;
    }

    function slotOf(name) {
        const names = listOf(Hyprland.monitors).map(m => m.name);
        names.sort((a, b) => {
            const ia = internalOutput(a) ? 0 : 1;
            const ib = internalOutput(b) ? 0 : 1;
            if (ia !== ib) return ia - ib;
            return a < b ? -1 : a > b ? 1 : 0;
        });
        const index = names.indexOf(name);
        return index < 0 ? 0 : index;
    }

    function iconFor(cls) {
        const key = (cls || "").toLowerCase();
        const apps = listOf(DesktopEntries.applications);
        let icon = "";
        for (let i = 0; i < apps.length; i++) {
            if ((apps[i].startupClass || "").toLowerCase() === key && apps[i].icon) {
                icon = apps[i].icon;
                break;
            }
        }
        if (!icon) {
            for (let i = 0; i < apps.length; i++) {
                if ((apps[i].id || "").toLowerCase() === key && apps[i].icon) {
                    icon = apps[i].icon;
                    break;
                }
            }
        }
        return Quickshell.iconPath(icon || key || "application-x-executable", "application-x-executable") || "";
    }

    function axis(value, index) {
        if (!value) return 0;
        if (value.length !== undefined && value[index] !== undefined) return Number(value[index]) || 0;
        if (index === 0) return Number(value.x) || 0;
        return Number(value.y) || 0;
    }

    function place(at, size, mon) {
        // Window coordinates are in layout pixels. The monitor size is physical.
        const scale = mon && mon.scale ? mon.scale : 1;
        const width = mon ? mon.width / scale : 0;
        const height = mon ? mon.height / scale : 0;
        if (!width || !height) return { rx: 0.06, ry: 0.08, rw: 0.88, rh: 0.28 };
        // reserved is [left, top, right, bottom]. Under the bar, gaps_out (8) and the
        // window border (1) leave a sliver above every window. The preview starts below that.
        const reserved = mon.lastIpcObject ? mon.lastIpcObject.reserved : null;
        const bar = reserved && reserved.length > 1 ? Number(reserved[1]) || 0 : 0;
        const top = bar + 9;
        const spanH = Math.max(1, height - top);
        let rx = (axis(at, 0) - mon.x) / width;
        let ry = (axis(at, 1) - mon.y - top) / spanH;
        let rw = axis(size, 0) / width;
        let rh = axis(size, 1) / spanH;
        if (rx < 0) { rw += rx; rx = 0; }
        if (ry < 0) { rh += ry; ry = 0; }
        if (rx + rw > 1) rw = 1 - rx;
        if (ry + rh > 1) rh = 1 - ry;
        rw = Math.max(0.08, rw);
        rh = Math.max(0.1, rh);
        if (rx + rw > 1) rx = Math.max(0, 1 - rw);
        if (ry + rh > 1) ry = Math.max(0, 1 - rh);
        return {
            rx: Math.round(rx * 1000) / 1000,
            ry: Math.round(ry * 1000) / 1000,
            rw: Math.round(rw * 1000) / 1000,
            rh: Math.round(rh * 1000) / 1000,
        };
    }

    function cleanAddress(raw) {
        let text = String(raw || "");
        if (text.startsWith("address:")) text = text.slice(8);
        if (text.startsWith("0x") || text.startsWith("0X")) text = text.slice(2);
        if (!/^[0-9a-fA-F]+$/.test(text)) return "";
        return "0x" + text.toLowerCase();
    }

    function collect() {
        Hyprland.refreshToplevels();
        const screenName = targetScreen ? targetScreen.name : "";
        const mon = monitorNamed(screenName) || Hyprland.focusedMonitor;
        const monName = mon ? mon.name : screenName;
        const slot = slotOf(monName);
        const ids = [];
        for (let i = 1; i <= pinned; i++) ids.push(slot * span + i);
        const workspaces = listOf(Hyprland.workspaces);
        for (let i = 0; i < workspaces.length; i++) {
            const ws = workspaces[i];
            if (!ws || !ws.monitor || ws.monitor.name !== monName) continue;
            if (ws.name && String(ws.name).indexOf("special") === 0) continue;
            if (ws.id > 0 && ids.indexOf(ws.id) < 0) ids.push(ws.id);
        }
        ids.sort((a, b) => a - b);

        const byId = {};
        const toplevels = listOf(Hyprland.toplevels);
        for (let i = 0; i < toplevels.length; i++) {
            const top = toplevels[i];
            const ws = top.workspace;
            if (!ws || ws.name && String(ws.name).indexOf("special") === 0) continue;
            const ipc = top.lastIpcObject || {};
            const address = cleanAddress(top.address || ipc.address);
            if (!address) continue;
            const cls = ipc["class"] || ipc.initialClass || "";
            const placed = place(ipc.at, ipc.size, mon);
            const entry = {
                address: address,
                title: (top.title || ipc.title || cls || "ウィンドウ").replace(/\s+/g, " "),
                minimized: false,
                workspace: String(ws.id),
                icon: iconFor(cls),
                focus: Number(ipc.focusHistoryID) || 0,
                rx: placed.rx,
                ry: placed.ry,
                rw: placed.rw,
                rh: placed.rh,
            };
            if (!byId[ws.id]) byId[ws.id] = [];
            byId[ws.id].push(entry);
        }
        const activeId = mon && mon.activeWorkspace ? mon.activeWorkspace.id : -1;
        const saved = minData || {};
        return ids.map(id => {
            const windows = (byId[id] || []).slice().sort((a, b) => b.focus - a.focus);
            const minimized = [];
            const addresses = Object.keys(saved);
            for (let i = 0; i < addresses.length; i++) {
                const info = saved[addresses[i]] || {};
                if (String(info.workspace) !== String(id)) continue;
                const address = cleanAddress(addresses[i]);
                if (!address) continue;
                minimized.push({
                    address: address,
                    title: String(info.title || info["class"] || "ウィンドウ").replace(/\s+/g, " "),
                    minimized: true,
                    workspace: String(id),
                    icon: iconFor(info["class"] || ""),
                    focus: 0,
                    rx: 0,
                    ry: 0,
                    rw: 0,
                    rh: 0,
                });
            }
            const local = id - slot * span;
            return {
                id: id,
                label: local >= 1 && local <= pinned ? String(local) : String(id),
                current: id === activeId,
                windows: windows,
                minimized: minimized,
            };
        });
    }

    function entryCount(index) {
        const card = cards[index];
        if (!card) return 0;
        return card.windows.length + card.minimized.length;
    }

    function selectedEntry() {
        const card = cards[selectedWs];
        if (!card || selectedIndex < 0) return null;
        if (selectedIndex < card.windows.length) return card.windows[selectedIndex];
        return card.minimized[selectedIndex - card.windows.length] || null;
    }

    function clampSelection() {
        if (!cards.length) {
            selectedWs = 0;
            selectedIndex = -1;
            return;
        }
        if (selectedWs < 0 || selectedWs >= cards.length) selectedWs = 0;
        const count = entryCount(selectedWs);
        if (count <= 0) selectedIndex = -1;
        else if (selectedIndex >= count) selectedIndex = count - 1;
    }

    function pickInitial() {
        const focused = Hyprland.focusedWorkspace;
        const wanted = focused ? focused.id : -1;
        let index = 0;
        for (let i = 0; i < cards.length; i++) {
            if (cards[i].id === wanted) index = i;
        }
        selectedWs = index;
        const active = Hyprland.activeToplevel;
        const address = active ? cleanAddress(active.address) : "";
        const windows = cards[index] ? cards[index].windows : [];
        let chosen = -1;
        for (let i = 0; i < windows.length; i++) {
            if (windows[i].address === address) chosen = i;
        }
        if (chosen < 0 && windows.length) chosen = 0;
        selectedIndex = chosen;
    }

    function rebuild(reset) {
        const next = collect();
        const text = JSON.stringify(next);
        if (!reset && text === snapshot) return;
        snapshot = text;
        cards = next;
        if (reset) pickInitial();
        else clampSelection();
    }

    function moveWs(delta) {
        if (!cards.length) return;
        selectedWs = (selectedWs + delta + cards.length) % cards.length;
        const count = entryCount(selectedWs);
        if (count <= 0) selectedIndex = -1;
        else if (selectedIndex < 0) selectedIndex = 0;
        else if (selectedIndex >= count) selectedIndex = count - 1;
    }

    function moveApp(delta) {
        const count = entryCount(selectedWs);
        if (count <= 0) return;
        if (selectedIndex < 0) selectedIndex = delta > 0 ? 0 : count - 1;
        else selectedIndex = (selectedIndex + delta + count) % count;
    }

    function activateWorkspace(index) {
        const card = cards[index];
        if (!card) return;
        hide();
        const id = Math.floor(Number(card.id));
        if (!isFinite(id)) return;
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + id + " })"]);
    }

    function activateEntry(entry) {
        if (!entry) return;
        const address = cleanAddress(entry.address);
        if (!address) return;
        hide();
        if (entry.minimized) {
            Quickshell.execDetached([
                Quickshell.env("HOME") + "/.config/hypr/scripts/window-min",
                "restore",
                address,
                String(entry.workspace),
            ]);
            return;
        }
        Quickshell.execDetached([
            "hyprctl", "dispatch",
            "hl.dsp.focus({ window = \"address:" + address + "\" })",
        ]);
    }

    function activateSelection() {
        const entry = selectedEntry();
        if (entry) activateEntry(entry);
        else activateWorkspace(selectedWs);
    }

    function activateNumber(n) {
        const label = String(n);
        for (let i = 0; i < cards.length; i++) {
            if (cards[i].label === label) {
                activateWorkspace(i);
                return;
            }
        }
    }

    FileView {
        id: minFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr-minimized.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                overview.minData = data && typeof data === "object" ? data : {};
            } catch (err) {
                overview.minData = {};
            }
            if (overview.open) overview.rebuild(false);
        }
    }

    Timer {
        interval: 400
        repeat: true
        running: overview.open
        onTriggered: overview.rebuild(false)
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { if (overview.open) overview.rebuild(false); }
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { if (overview.open) overview.rebuild(false); }
    }

    IpcHandler {
        target: "workspaces"

        function toggle(): void {
            if (overview.open) overview.hide();
            else overview.show();
        }

        function close(): void {
            overview.hide();
        }
    }

    Variants {
        model: overview.open ? [overview.targetScreen] : []

        PanelWindow {
            id: win

            required property var modelData

            screen: modelData
            implicitWidth: card.width
            implicitHeight: card.height
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "workspaces"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            HyprlandFocusGrab {
                active: true
                windows: [win]
                onCleared: overview.hide()
            }

            Rectangle {
                id: card
                width: columns.width + overview.gutter * 2 + 2
                height: columns.y + columns.height + overview.gutter + hint.height + 1
                color: overview.ui.panel
                border.color: overview.ui.hairline
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                }

                Item {
                    id: keys
                    focus: true
                    Component.onCompleted: forceActiveFocus()

                    Keys.onPressed: event => {
                        const k = event.key;
                        if (k === Qt.Key_Escape) overview.hide();
                        else if (k === Qt.Key_Right || k === Qt.Key_Tab) overview.moveWs(1);
                        else if (k === Qt.Key_Left || k === Qt.Key_Backtab) overview.moveWs(-1);
                        else if (k === Qt.Key_Down) overview.moveApp(1);
                        else if (k === Qt.Key_Up) overview.moveApp(-1);
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) overview.activateSelection();
                        else if (k >= Qt.Key_1 && k <= Qt.Key_9) overview.activateNumber(k - Qt.Key_1 + 1);
                        event.accepted = true;
                    }
                }

                Row {
                    id: columns
                    x: 1 + overview.gutter
                    y: 1 + overview.gutter
                    spacing: overview.gutter

                    Repeater {
                        model: overview.cards

                        delegate: Item {
                            id: column

                            required property var modelData
                            required property int index

                            readonly property int mapW: {
                                const screenW = win.screen ? win.screen.width : 1280;
                                const n = Math.max(overview.cards.length, 1);
                                const avail = screenW - 48;
                                return Math.max(112, Math.min(220, Math.floor((avail - overview.gutter * (n + 1)) / n)));
                            }
                            readonly property int mapH: {
                                const mon = overview.monitorNamed(win.screen ? win.screen.name : "");
                                if (!mon || !mon.width || !mon.height) return Math.round(mapW * 10 / 16);
                                return Math.max(80, Math.round(mapW * mon.height / mon.width));
                            }
                            readonly property bool chosenWs: index === overview.selectedWs

                            width: mapW
                            height: body.childrenRect.height

                            Column {
                                id: body
                                width: column.mapW
                                spacing: overview.gutter

                                Rectangle {
                                    width: Math.max(28, numberText.implicitWidth + 12)
                                    height: 28
                                    color: column.modelData.current ? overview.ui.cream : "transparent"
                                    border.color: column.chosenWs || column.modelData.current ? overview.ui.cream : overview.ui.hairline
                                    border.width: 1

                                    Text {
                                        id: numberText
                                        anchors.centerIn: parent
                                        text: column.modelData.label
                                        font.family: overview.ui.font
                                        font.pixelSize: 13
                                        font.weight: column.modelData.current ? Font.DemiBold : Font.Normal
                                        color: column.modelData.current ? overview.ui.ink : overview.ui.text1
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: overview.selectedWs = column.index
                                        onClicked: overview.activateWorkspace(column.index)
                                    }
                                }

                                Rectangle {
                                    id: map
                                    width: column.mapW
                                    height: column.mapH
                                    color: "transparent"
                                    border.color: column.chosenWs ? overview.ui.cream : overview.ui.hairline
                                    border.width: 1
                                    clip: true

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: overview.activateWorkspace(column.index)
                                    }

                                    Repeater {
                                        model: column.modelData.windows.length

                                        delegate: Rectangle {
                                            id: frame

                                            required property int index
                                            readonly property var win: column.modelData.windows[index]
                                            readonly property bool chosen: column.chosenWs && overview.selectedIndex === index
                                            readonly property int iconBox: Math.min(18, Math.max(12, Math.min(width, height) - 8))

                                            x: Math.round(win.rx * map.width)
                                            y: Math.round(win.ry * map.height)
                                            width: Math.max(18, Math.round(win.rw * map.width))
                                            height: Math.max(18, Math.round(win.rh * map.height))
                                            color: chosen ? overview.ui.cream : overview.ui.hover
                                            border.color: chosen ? overview.ui.cream : overview.ui.text3
                                            border.width: 1
                                            clip: true

                                            Image {
                                                anchors.centerIn: parent
                                                width: frame.iconBox
                                                height: frame.iconBox
                                                visible: frame.win.icon !== ""
                                                source: frame.win.icon
                                                sourceSize: Qt.size(32, 32)
                                                fillMode: Image.PreserveAspectFit
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onEntered: {
                                                    overview.selectedWs = column.index;
                                                    overview.selectedIndex = frame.index;
                                                }
                                                onClicked: overview.activateEntry(frame.win)
                                            }
                                        }
                                    }
                                }

                                Row {
                                    spacing: 4
                                    visible: column.modelData.minimized.length > 0

                                    Repeater {
                                        model: column.modelData.minimized.length

                                        delegate: Rectangle {
                                            id: hidden

                                            required property int index
                                            readonly property var win: column.modelData.minimized[index]
                                            readonly property int flat: column.modelData.windows.length + index
                                            readonly property bool chosen: column.chosenWs && overview.selectedIndex === flat

                                            width: 28
                                            height: 28
                                            color: chosen ? overview.ui.cream : "transparent"
                                            border.color: chosen ? overview.ui.cream : overview.ui.text3
                                            border.width: 1

                                            Image {
                                                anchors.centerIn: parent
                                                width: 16
                                                height: 16
                                                source: hidden.win.icon
                                                sourceSize: Qt.size(32, 32)
                                                fillMode: Image.PreserveAspectFit
                                                visible: hidden.win.icon !== ""
                                                opacity: hidden.chosen ? 1 : 0.55
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onEntered: {
                                                    overview.selectedWs = column.index;
                                                    overview.selectedIndex = hidden.flat;
                                                }
                                                onClicked: overview.activateEntry(hidden.win)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: hint
                    x: 1
                    y: columns.y + columns.height + overview.gutter
                    width: parent.width - 2
                    height: hintText.y + hintText.height + 8

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: overview.ui.hairline
                    }

                    Text {
                        id: titleText
                        x: 8
                        y: 8
                        width: hint.width - 16
                        visible: overview.selectionTitle !== ""
                        text: overview.selectionTitle
                        font.family: overview.ui.font
                        font.pixelSize: 12
                        color: overview.ui.text2
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        id: hintText
                        x: 8
                        y: titleText.visible ? titleText.y + titleText.height + 4 : 8
                        width: hint.width - 16
                        text: "←→ ワークスペース    ↑↓ アプリ    ↵ 移動    esc 閉じる"
                        font.family: overview.ui.font
                        font.pixelSize: 11
                        color: overview.ui.text3
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
