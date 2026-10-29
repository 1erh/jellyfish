import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Wallpaper on every monitor plus a picker (Super+W).
// The choice lives in ~/.config/hypr/wallpaper.json: {"kind": "<scene id>"} or {"kind": "image", "path": "..."}.
Scope {
    id: wall

    required property var ui

    readonly property string home: Quickshell.env("HOME")
    readonly property string folder: home + "/Pictures/Wallpapers"

    // Animated ASCII scenes.
    readonly property var scenes: [
        { id: "kurage", label: "クラゲ", style: "Classic", ramp: " .':;-+otS%X8#@",
          base: "#05080b", tint: "#58c4c0", tint2: "#a07cf0", tint3: "#f2c85b" },
    ]

    function sceneById(id) {
        return scenes.find(s => s.id === id) ?? null;
    }

    property string kind: "kurage"
    property string path: ""
    readonly property var scene: sceneById(kind) ?? scenes[0]

    readonly property size world: {
        let w = 0, h = 0;
        for (const s of Quickshell.screens) {
            w = Math.max(w, s.x + s.width);
            h = Math.max(h, s.y + s.height);
        }
        return Qt.size(w, h);
    }

    function apply(newKind, newPath) {
        kind = newKind;
        path = newPath || "";
        stateFile.setText(JSON.stringify(kind === "image" ? { kind: kind, path: path } : { kind: kind }, null, 2) + "\n");
    }

    FileView {
        id: stateFile
        path: wall.home + "/.config/hypr/wallpaper.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const v = JSON.parse(text());
                wall.kind = v.kind === "image" && v.path ? "image" : wall.sceneById(v.kind) ? v.kind : "kurage";
                wall.path = v.path || "";
            } catch (err) {
                wall.kind = "kurage";
            }
        }
    }

    IpcHandler {
        target: "wallpaper"

        function set(file: string): void {
            wall.apply("image", file);
        }

        function kurage(): void {
            wall.apply("kurage", "");
        }

        function scene(id: string): void {
            if (wall.sceneById(id)) wall.apply(id, "");
        }

        function pick(): void {
            if (picker.open) picker.hide();
            else if (Date.now() - picker.dismissedAt > 400) picker.show();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bg

            required property var modelData

            screen: modelData
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: wall.scene.base

            WlrLayershell.namespace: "wallpaper"
            WlrLayershell.layer: WlrLayer.Background

            AsciiField {
                anchors.fill: parent
                visible: wall.kind !== "image"
                scene: wall.scene.id
                ramp: wall.scene.ramp
                base: wall.scene.base
                tint: wall.scene.tint
                tint2: wall.scene.tint2
                tint3: wall.scene.tint3
                origin: Qt.point(bg.modelData.x, bg.modelData.y)
                world: wall.world
            }

            Image {
                anchors.fill: parent
                visible: wall.kind === "image"
                source: wall.kind === "image" ? "file://" + wall.path : ""
                sourceSize: Qt.size(bg.modelData.width, bg.modelData.height)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }
        }
    }

    property alias picker: picker

    Scope {
        id: picker

        readonly property int columns: 4
        readonly property int tileW: 224
        readonly property int tileH: 126
        readonly property int gutter: 8

        property bool open: false
        property var targetScreen: Quickshell.screens[0]
        property int selected: 0

        readonly property int sceneCount: wall.scenes.length
        readonly property int count: sceneCount + images.count

        function show() {
            if (wall.ui.authOpen) return;
            wall.ui.closeOverlays();
            const focused = Hyprland.focusedMonitor;
            targetScreen = Quickshell.screens.find(s => focused && s.name === focused.name) ?? Quickshell.screens[0];
            selected = currentIndex();
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

        function filePath(index) {
            return index >= sceneCount ? images.get(index - sceneCount, "filePath") : "";
        }

        function currentIndex() {
            if (wall.kind !== "image") return Math.max(0, wall.scenes.findIndex(s => s.id === wall.kind));
            for (let i = 0; i < images.count; i++)
                if (images.get(i, "filePath") === wall.path) return i + sceneCount;
            return 0;
        }

        function move(delta) {
            selected = Math.max(0, Math.min(count - 1, selected + delta));
        }

        function activate(index) {
            if (index < sceneCount) wall.apply(wall.scenes[index].id, "");
            else wall.apply("image", filePath(index));
            hide();
        }

        function randomize() {
            const options = [];
            for (let i = 0; i < wall.scenes.length; i++)
                options.push({ kind: wall.scenes[i].id, path: "" });
            for (let i = 0; i < images.count; i++) {
                const path = images.get(i, "filePath");
                if (path) options.push({ kind: "image", path: path });
            }
            if (!options.length) return;
            const pool = options.filter(o => o.kind !== wall.kind || o.path !== (wall.path || ""));
            const pick = (pool.length ? pool : options)[Math.floor(Math.random() * (pool.length ? pool.length : options.length))];
            wall.apply(pick.kind, pick.path);
        }

        FolderListModel {
            id: images
            folder: "file://" + wall.folder
            nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]
            showDirs: false
            sortField: FolderListModel.Name
        }

        Variants {
            model: picker.open ? [picker.targetScreen] : []

            PanelWindow {
                id: win

                required property var modelData
                readonly property bool main: true

                screen: modelData
                implicitWidth: card.width
                implicitHeight: card.height
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"

                WlrLayershell.namespace: "wallpaper-picker"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

                HyprlandFocusGrab {
                    active: true
                    windows: [win]
                    onCleared: picker.dismiss()
                }

                Rectangle {
                    id: card

                    readonly property int rows: Math.ceil(picker.count / picker.columns)
                    readonly property int visibleRows: Math.min(rows, 3)

                    visible: win.main
                    anchors.centerIn: parent
                    width: 2 + picker.gutter + picker.columns * (picker.tileW + picker.gutter)
                    height: 2 + header.height + 1 + picker.gutter
                        + visibleRows * (picker.tileH + picker.gutter) + 1 + footer.height
                    color: wall.ui.panel
                    border.color: wall.ui.hairline
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
                                picker.hide();
                            } else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Tab) {
                                picker.move(1);
                            } else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Backtab) {
                                picker.move(-1);
                            } else if (k === Qt.Key_Down || k === Qt.Key_J) {
                                picker.move(picker.columns);
                            } else if (k === Qt.Key_Up || k === Qt.Key_K) {
                                picker.move(-picker.columns);
                            } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                                picker.activate(picker.selected);
                            } else if (k === Qt.Key_O) {
                                Quickshell.execDetached(["xdg-open", wall.folder]);
                                picker.hide();
                            } else {
                                return;
                            }
                            event.accepted = true;
                        }
                    }

                    Item {
                        id: header
                        x: 1
                        y: 1
                        width: parent.width - 2
                        height: 40

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "壁紙"
                            font.family: wall.ui.font
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: wall.ui.text1
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: picker.count + " 件"
                            font.family: wall.ui.font
                            font.pixelSize: 11
                            color: wall.ui.text3
                        }
                    }

                    Rectangle {
                        id: headerLine
                        x: 1
                        y: header.y + header.height
                        width: parent.width - 2
                        height: 1
                        color: wall.ui.hairline
                    }

                    Flickable {
                        id: scroller
                        x: 1 + picker.gutter
                        y: headerLine.y + 1 + picker.gutter
                        width: picker.columns * (picker.tileW + picker.gutter) - picker.gutter
                        height: card.visibleRows * (picker.tileH + picker.gutter) - picker.gutter
                        contentHeight: grid.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        readonly property int selectedRow: Math.floor(picker.selected / picker.columns)
                        function reveal() {
                            const top = selectedRow * (picker.tileH + picker.gutter);
                            let y = contentY;
                            if (top < y) y = top;
                            else if (top + picker.tileH > y + height) y = top + picker.tileH - height;
                            contentY = Math.max(0, Math.min(y, contentHeight - height));
                        }

                        onSelectedRowChanged: reveal()
                        onContentHeightChanged: reveal()
                        onHeightChanged: reveal()
                        Component.onCompleted: reveal()

                        Item {
                            id: grid
                            width: scroller.width
                            height: Math.ceil(picker.count / picker.columns) * (picker.tileH + picker.gutter) - picker.gutter

                            Repeater {
                                model: picker.count

                                delegate: Item {
                                    id: tile

                                    required property int index
                                    readonly property bool current: index === picker.selected
                                    readonly property var sceneData: index < picker.sceneCount ? wall.scenes[index] : null
                                    readonly property string file: sceneData ? "" : images.get(index - picker.sceneCount, "filePath")
                                    readonly property bool inUse: sceneData
                                        ? wall.kind === sceneData.id
                                        : wall.kind === "image" && wall.path === file

                                    x: (index % picker.columns) * (picker.tileW + picker.gutter)
                                    y: Math.floor(index / picker.columns) * (picker.tileH + picker.gutter)
                                    width: picker.tileW
                                    height: picker.tileH
                                    clip: true

                                    AsciiField {
                                        visible: tile.sceneData !== null
                                        running: visible && picker.open
                                        scene: tile.sceneData ? tile.sceneData.id : "kurage"
                                        ramp: tile.sceneData ? tile.sceneData.ramp : " "
                                        base: tile.sceneData ? tile.sceneData.base : "black"
                                        tint: tile.sceneData ? tile.sceneData.tint : "white"
                                        tint2: tile.sceneData ? tile.sceneData.tint2 : "white"
                                        tint3: tile.sceneData ? tile.sceneData.tint3 : "white"
                                        width: picker.targetScreen.width
                                        height: picker.targetScreen.height
                                        origin: Qt.point(picker.targetScreen.x, picker.targetScreen.y)
                                        world: wall.world
                                        fps: 20
                                        transformOrigin: Item.TopLeft
                                        scale: picker.tileW / width
                                        layer.enabled: true
                                        layer.mipmap: true
                                        layer.smooth: true
                                    }

                                    Image {
                                        anchors.fill: parent
                                        visible: tile.sceneData === null
                                        source: tile.file ? "file://" + tile.file : ""
                                        sourceSize: Qt.size(picker.tileW * 2, picker.tileH * 2)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 26
                                        color: tile.current ? wall.ui.cream : Qt.rgba(wall.ui.ink.r, wall.ui.ink.g, wall.ui.ink.b, 0.82)

                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.right: tag.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: tile.sceneData ? tile.sceneData.label : tile.file.split("/").pop()
                                            font.family: wall.ui.font
                                            font.pixelSize: 12
                                            font.weight: tile.current ? Font.DemiBold : Font.Normal
                                            color: tile.current ? wall.ui.ink : wall.ui.text1
                                            elide: Text.ElideMiddle
                                        }

                                        Text {
                                            id: tag
                                            visible: tile.inUse
                                            anchors.right: parent.right
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "使用中"
                                            font.family: wall.ui.font
                                            font.pixelSize: 11
                                            color: tile.current ? Qt.rgba(wall.ui.ink.r, wall.ui.ink.g, wall.ui.ink.b, 0.6) : wall.ui.text2
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "transparent"
                                        border.width: tile.current ? 2 : 1
                                        border.color: tile.current ? wall.ui.cream : wall.ui.hairline
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: picker.selected = tile.index
                                        onClicked: picker.activate(tile.index)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: footerLine
                        x: 1
                        y: scroller.y + scroller.height + picker.gutter
                        width: parent.width - 2
                        height: 1
                        color: wall.ui.hairline
                    }

                    Item {
                        id: footer
                        x: 1
                        y: footerLine.y + 1
                        width: parent.width - 2
                        height: 30

                        Text {
                            id: folderLink
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "~/Pictures/Wallpapers に画像を置くと増えます"
                            font.family: wall.ui.font
                            font.pixelSize: 11
                            font.underline: folderMouse.containsMouse
                            color: folderMouse.containsMouse ? wall.ui.text1 : wall.ui.text3

                            MouseArea {
                                id: folderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.execDetached(["xdg-open", wall.folder]);
                                    picker.hide();
                                }
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "←↑↓→ 選択    ↵ 設定    o フォルダ    esc 閉じる"
                            font.family: wall.ui.font
                            font.pixelSize: 11
                            color: wall.ui.text3
                        }
                    }
                }
            }
        }
    }
}
