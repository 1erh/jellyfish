import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// Win launcher (only the input until you type), power menu and wallpaper.
ShellRoot {
    id: root

    property color ink: "#0c0b0a"
    property color cream: "#e6e1d6"
    property color text1: "#f4f0e8"
    property color text2: "#a39e94"
    property color text3: "#6f6a64"
    property color hairline: "#29e6e1d6"
    property color panel: "#f00c0b0a"
    property color hover: "#0fffffff"
    property color fail: "#c47a6a"
    property string themeName: "dark"
    property var themeList: []
    readonly property string font: "UDEV Gothic"
    readonly property string symbols: "Symbols Nerd Font Mono"

    readonly property int panelWidth: 520
    readonly property int inputHeight: 46
    readonly property int rowHeight: 36
    readonly property int footerHeight: 28
    readonly property int maxResults: 7
    // Kept for a delegate whose index has already been removed.
    readonly property var blankResult: ({ kind: "", title: "", subtitle: "", tag: "", entry: null, swatch: "", swatchBg: "" })
    readonly property int listRows: Math.max(1, results.length)
    // The layer surface stays this tall while searching. Resizing it with the
    // result count makes the top-anchored window jump for a frame.
    readonly property int maxListRows: Math.max(maxResults, commands.length, themeList.length)
    readonly property int shellHeight: query.trim() === "" ? 2 + inputHeight : panelHeight(Math.max(listRows, maxListRows))

    function panelHeight(rows) {
        return 2 + inputHeight + 1 + 6 + rows * rowHeight + 6 + 1 + footerHeight;
    }

    property bool open: false
    property var targetScreen: Quickshell.screens[0]
    property string query: ""
    property int selected: 0
    property var usage: ({})

    readonly property var apps: DesktopEntries.applications.values.filter(e => !e.noDisplay)
    readonly property var results: search(query, apps, usage)

    onQueryChanged: selected = 0

    function closeOverlays() {
        hide();
        power.hide();
        wallpaper.picker.hide();
        panel.hide();
        userSwitcher.hide();
        workspaces.hide();
    }

    readonly property bool authOpen: authDialog.agentActive

    function show() {
        if (authOpen) return;
        closeOverlays();
        const focused = Hyprland.focusedMonitor;
        targetScreen = Quickshell.screens.find(s => focused && s.name === focused.name) ?? Quickshell.screens[0];
        query = "";
        open = true;
    }

    function hide() {
        open = false;
        query = "";
    }

    function fuzzy(text, q) {
        let i = 0;
        for (const c of text) {
            if (c === q[i]) i++;
            if (i === q.length) return true;
        }
        return false;
    }

    function score(e, q) {
        const name = (e.name || "").toLowerCase();
        if (name === q) return 100;
        if (name.startsWith(q)) return 80;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 60;
        if (name.includes(q)) return 45;
        const extra = [e.genericName, e.keywords, e.id, e.comment].join(" ").toLowerCase();
        if (extra.includes(q)) return 30;
        if (q.length >= 2 && fuzzy(name, q)) return 15;
        return 0;
    }

    // Qualified with root: a bare "panel" would resolve to the Panel object's id.
    function applyPalette(p) {
        root.ink = p.ink;
        root.cream = p.cream;
        root.text1 = p.text;
        root.text2 = p.text2;
        root.text3 = p.text3;
        root.hairline = p.hairline;
        root.panel = p.panel;
        root.hover = p.hover;
        root.fail = p.fail;
        root.themeName = p.id;
    }

    function readTheme(raw) {
        try {
            const data = JSON.parse(raw);
            themeList = data.themes || [];
            const cur = themeList.find(t => t.id === data.current) || themeList[0];
            if (cur) applyPalette(cur);
        } catch (err) {
        }
    }

    signal fillQuery(string text)

    readonly property var commands: [
        { id: "wallpaper", title: "wallpaper", names: ["wallpaper", "壁紙", "かべがみ"], subtitle: "壁紙スイッチャーを開く" },
        { id: "random", title: "random", names: ["random", "ランダム", "らんだむ"], subtitle: "壁紙をランダムに変える" },
        { id: "theme", title: "scheme", names: ["scheme", "配色", "はいしょく", "theme", "テーマ", "color", "カラー", "スキーム"], subtitle: "Dark、Nord、Gruvbox など", submenu: "theme" },
        { id: "clipboard", title: "clipboard", names: ["clipboard", "clip", "クリップボード", "くりっぷぼーど"], subtitle: "クリップボード履歴" },
        { id: "windows", title: "windows", names: ["windows", "window", "ウィンドウ", "うぃんどう", "タスク"], subtitle: "ウィンドウを切り替える" },
        { id: "keybinds", title: "keybinds", names: ["keybinds", "keys", "キーバインド", "きーばいんど", "ショートカット"], subtitle: "キーバインド一覧" },
        { id: "calc", title: "calc", names: ["calc", "計算", "けいさん", "calculator"], subtitle: "数式を計算する", submenu: "calc" },
        { id: "lock", title: "lock", names: ["lock", "ロック", "ろっく"], subtitle: "画面をロック" },
        { id: "sleep", title: "sleep", names: ["sleep", "suspend", "スリープ", "すりーぷ", "サスペンド"], subtitle: "サスペンドする" },
        { id: "logout", title: "logout", names: ["logout", "ログアウト", "ろぐあうと"], subtitle: "ログアウトする", confirm: "ログアウトする" },
        { id: "reboot", title: "reboot", names: ["reboot", "再起動", "さいきどう"], subtitle: "システムを再起動", confirm: "再起動する" },
        { id: "shutdown", title: "shutdown", names: ["shutdown", "poweroff", "シャットダウン", "しゃっとだうん", "電源オフ"], subtitle: "電源を切る", confirm: "電源を切る" },
    ]

    function matchingThemes(q) {
        const all = [];
        const n = themeList ? themeList.length : 0;
        for (let i = 0; i < n; i++) all.push(themeList[i]);
        if (q === "") return all;
        return all.filter(t => (t.id + " " + t.label + " " + (t.keywords || "")).toLowerCase().includes(q));
    }

    // ">scheme" lists palettes, ">scheme nord" narrows them, ">" alone lists commands.
    function commandResults(cmd) {
        const m = cmd.match(/^(\S*)\s*([\s\S]*)$/);
        const name = (m ? m[1] : "").toLowerCase();
        const arg = (m ? m[2] : "").trim().toLowerCase();
        const exact = commands.find(c => c.names.indexOf(name) !== -1);
        if (exact && exact.submenu === "theme") {
            return matchingThemes(arg).map(t => ({
                kind: "theme",
                id: t.id,
                title: t.label,
                subtitle: t.id === themeName ? "使用中" : "",
                tag: "配色",
                swatch: t.cream,
                swatchBg: t.ink,
                entry: null,
            }));
        }
        if (exact && exact.submenu === "calc") {
            if (arg === "")
                return [{ kind: "hint", title: "式を入力", subtitle: "例: 1+2*3", tag: "計算", entry: null }];
            const value = calculate(arg);
            if (value === null)
                return [{ kind: "hint", title: "計算できません", subtitle: arg, tag: "計算", entry: null }];
            return [{ kind: "calc", title: value, subtitle: arg + " =", tag: "計算", entry: null }];
        }
        if (exact && exact.confirm) {
            return [{
                kind: "confirm",
                id: exact.id,
                title: exact.confirm,
                subtitle: "Enter で実行",
                tag: "確認",
                entry: null,
            }];
        }
        return commands
            .filter(c => name === "" || c.names.some(n => n.startsWith(name)))
            .map(c => ({
                kind: "command",
                id: c.id,
                title: ">" + c.title,
                subtitle: c.subtitle,
                tag: "コマンド",
                submenu: c.submenu || "",
                confirm: c.confirm || "",
                entry: null,
            }));
    }

    function calculate(q) {
        if (!/^[0-9+\-*/().\s%^]+$/.test(q) || !/[0-9]/.test(q) || !/[+\-*/%^]/.test(q))
            return null;
        try {
            const v = Function('"use strict"; return (' + q.replace(/\^/g, "**") + ");")();
            if (typeof v !== "number" || !isFinite(v)) return null;
            return String(Math.round(v * 1e10) / 1e10);
        } catch (err) {
            return null;
        }
    }

    function search(raw, list, counts) {
        // NFKC folds IME full-width input ("＞配色　ｎｏｒｄ") to ">配色 nord".
        const folded = raw.normalize ? raw.normalize("NFKC") : raw;
        const q = folded.trim().toLowerCase();
        if (q === "") return [];
        if (q.startsWith(">")) return commandResults(q.slice(1).trim());
        const out = [];
        const calc = calculate(q);
        if (calc !== null)
            out.push({ kind: "calc", title: calc, subtitle: raw.trim() + " =", tag: "計算", entry: null });
        const scored = [];
        for (const e of list) {
            const s = score(e, q);
            if (s > 0) scored.push({ e: e, s: s + Math.min(counts[e.id] || 0, 20) * 2 });
        }
        scored.sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name));
        const seen = {};
        for (const it of scored) {
            if (out.length >= maxResults) break;
            if (seen[it.e.name]) continue;
            seen[it.e.name] = true;
            out.push({
                kind: "app",
                title: it.e.name,
                subtitle: it.e.genericName && it.e.genericName !== it.e.name ? it.e.genericName : "",
                tag: "アプリ",
                entry: it.e,
            });
        }
        return out;
    }

    function move(delta) {
        if (results.length === 0) return;
        selected = (selected + delta + results.length) % results.length;
    }

    function enterWord() {
        const r = results[selected];
        if (!r || r.kind === "hint") return "";
        if (r.kind === "calc") return "コピー";
        if (r.kind === "theme") return "適用";
        if (r.kind === "confirm") return "実行";
        if (r.kind === "command") return r.confirm ? "確認" : r.submenu ? "選ぶ" : "実行";
        return "開く";
    }

    function runAction(id) {
        const home = Quickshell.env("HOME");
        const script = home + "/.config/hypr/scripts/shell";
        if (id === "wallpaper") {
            wallpaper.picker.show();
            return;
        }
        if (id === "windows") {
            workspaces.show();
            return;
        }
        hide();
        if (id === "random") wallpaper.picker.randomize();
        else if (id === "clipboard") runDetached([script, "clip"]);
        else if (id === "keybinds") runDetached([script, "keys"]);
        else if (id === "lock") runDetached([home + "/.config/hypr/scripts/lock"]);
        else if (id === "sleep") runDetached([script, "suspend"]);
        else if (id === "logout") Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.exit()"]);
        else if (id === "reboot") Quickshell.execDetached(["systemctl", "reboot"]);
        else if (id === "shutdown") Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    // The launcher still holds the keyboard until its window closes.
    function runDetached(args) {
        Quickshell.execDetached(["sh", "-c", "sleep 0.12; exec \"$0\" \"$@\""].concat(args));
    }

    function activate(index) {
        const r = results[index];
        if (!r || r.kind === "hint") return;
        if (r.kind === "app") {
            r.entry.execute();
            const next = Object.assign({}, usage);
            next[r.entry.id] = (next[r.entry.id] || 0) + 1;
            usage = next;
            store.setText(JSON.stringify(next));
        } else if (r.kind === "theme") {
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/apply-theme", r.id]);
        } else if (r.kind === "command") {
            if (r.submenu) fillQuery(">" + r.title.slice(1) + " ");
            else if (r.confirm) fillQuery(">" + r.title.slice(1));
            else runAction(r.id);
            return;
        } else if (r.kind === "confirm") {
            runAction(r.id);
            return;
        } else {
            Quickshell.execDetached(["wl-copy", r.title]);
        }
        hide();
    }

    // Palettes are written by scripts/apply-theme.
    FileView {
        id: themeFile
        path: Quickshell.env("HOME") + "/.config/hypr/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.readTheme(text())
    }

    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.cache/launcher-usage.json"
        onLoaded: {
            try {
                root.usage = JSON.parse(text()) || {};
            } catch (err) {
                root.usage = {};
            }
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            if (root.open) root.hide();
            else root.show();
        }

        function close(): void {
            root.hide();
        }
    }

    PowerMenu {
        id: power
        ui: root
    }

    property alias userSwitcher: userSwitcher

    UserSwitcher {
        id: userSwitcher
        ui: root
    }

    Wallpaper {
        id: wallpaper
        ui: root
    }

    AuthDialog {
        id: authDialog
        ui: root
    }

    Panel {
        id: panel
        ui: root
    }

    Workspaces {
        id: workspaces
        ui: root
    }

    Variants {
        model: root.open ? [root.targetScreen] : []

        PanelWindow {
            id: win

            required property var modelData
            readonly property bool main: true

            screen: modelData
            anchors.top: true
            margins.top: Math.round(modelData.height * 0.2)
            implicitWidth: card.width
            implicitHeight: root.shellHeight
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }

            WlrLayershell.namespace: "launcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            HyprlandFocusGrab {
                active: true
                windows: [win]
                onCleared: root.hide()
            }

            Rectangle {
                id: card

                readonly property bool expanded: root.query.trim() !== ""

                width: root.panelWidth
                height: expanded ? root.panelHeight(root.listRows) : 2 + root.inputHeight
                color: root.panel
                border.color: root.hairline
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                }

                Item {
                    id: header
                    x: 1
                    y: 1
                    width: parent.width - 2
                    height: root.inputHeight

                    Text {
                        id: glyph
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"
                        font.family: root.symbols
                        font.pixelSize: 18
                        color: root.text3
                    }

                    TextInput {
                        id: input
                        anchors.left: glyph.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.query
                        onTextChanged: root.query = text
                        font.family: root.font
                        font.pixelSize: 16
                        color: root.text1
                        selectionColor: root.cream
                        selectedTextColor: root.ink
                        cursorDelegate: Rectangle {
                            width: 1.5
                            color: root.cream
                        }
                        clip: true
                        Component.onCompleted: if (win.main) forceActiveFocus()

                        Connections {
                            target: root
                            function onFillQuery(text) {
                                input.text = text;
                                input.cursorPosition = text.length;
                            }
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "アプリを検索、> でコマンド"
                            font: input.font
                            color: root.text3
                            visible: input.text === "" && input.preeditText === ""
                        }

                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            if (event.key === Qt.Key_Escape) {
                                root.hide();
                            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
                                root.move(1);
                            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
                                root.move(-1);
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.activate(root.selected);
                            } else {
                                return;
                            }
                            event.accepted = true;
                        }
                    }
                }

                Rectangle {
                    id: divider
                    visible: card.expanded
                    x: 1
                    y: header.y + header.height
                    width: parent.width - 2
                    height: 1
                    color: root.hairline
                }

                // Placed by index, not in a Column. A Column stacks the Repeater's
                // outgoing rows for a frame when the count drops, so the panel jumps.
                Item {
                    id: list
                    visible: card.expanded
                    x: 7
                    y: divider.y + 1 + 6
                    width: parent.width - 14
                    height: root.listRows * root.rowHeight
                    clip: true

                    Repeater {
                        model: root.results.length

                        delegate: Rectangle {
                            id: row
                            required property int index
                            readonly property var result: index < root.results.length ? root.results[index] : root.blankResult
                            readonly property bool current: index === root.selected

                            y: index * root.rowHeight
                            width: list.width
                            height: root.rowHeight
                            color: current ? root.cream : "transparent"

                            Item {
                                id: icon
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20

                                IconImage {
                                    anchors.fill: parent
                                    visible: row.result.kind === "app"
                                    source: row.result.entry ? Quickshell.iconPath(row.result.entry.icon, "application-x-executable") : ""
                                }

                                Text {
                                    visible: row.result.kind === "calc"
                                    anchors.centerIn: parent
                                    text: "󰃬"
                                    font.family: root.symbols
                                    font.pixelSize: 18
                                    color: row.current ? root.ink : root.text2
                                }

                                Text {
                                    visible: row.result.kind === "command" || row.result.kind === "confirm" || row.result.kind === "hint"
                                    anchors.centerIn: parent
                                    text: row.result.kind === "confirm" ? "󰐥" : "󰘳"
                                    font.family: root.symbols
                                    font.pixelSize: 18
                                    color: row.current ? root.ink : root.text2
                                }

                                Rectangle {
                                    visible: row.result.kind === "theme"
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    color: row.result.swatchBg || "transparent"
                                    border.width: 1
                                    border.color: row.current ? root.ink : root.hairline

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8
                                        height: 8
                                        color: row.result.swatch || "transparent"
                                    }
                                }
                            }

                            Text {
                                id: title
                                anchors.left: icon.right
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.result.title
                                font.family: root.font
                                font.pixelSize: 14
                                font.weight: row.current ? Font.DemiBold : Font.Normal
                                color: row.current ? root.ink : root.text1
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, row.width - 160)
                            }

                            Text {
                                anchors.left: title.right
                                anchors.leftMargin: 10
                                anchors.right: tag.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.result.subtitle
                                font.family: root.font
                                font.pixelSize: 12
                                color: row.current ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6) : root.text3
                                elide: Text.ElideRight
                            }

                            Text {
                                id: tag
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.result.tag
                                font.family: root.font
                                font.pixelSize: 11
                                color: row.current ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6) : root.text3
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.selected = row.index
                                onClicked: root.activate(row.index)
                            }
                        }
                    }

                    Item {
                        visible: root.results.length === 0
                        width: list.width
                        height: root.rowHeight

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: "一致するものはありません"
                            font.family: root.font
                            font.pixelSize: 13
                            color: root.text3
                        }
                    }
                }

                Rectangle {
                    id: footerLine
                    visible: card.expanded
                    x: 1
                    y: list.y + list.height + 6
                    width: parent.width - 2
                    height: 1
                    color: root.hairline
                }

                Item {
                    visible: card.expanded
                    x: 1
                    y: footerLine.y + 1
                    width: parent.width - 2
                    height: root.footerHeight

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.results.length + " 件"
                        font.family: root.font
                        font.pixelSize: 11
                        color: root.text3
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↑↓ 選択    " + (root.enterWord() ? "↵ " + root.enterWord() + "    " : "") + "esc 閉じる"
                        font.family: root.font
                        font.pixelSize: 11
                        color: root.text3
                    }
                }
            }
        }
    }
}
