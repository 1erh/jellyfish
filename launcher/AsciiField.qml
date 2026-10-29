import QtQuick

// Animated ASCII scene (shaders/<scene>.frag). origin/world place this item inside the whole desktop.
Item {
    id: field

    property string scene: "kurage"
    property string ramp: " .':;-+otS%X8#@"
    property color tint: "#58c4c0"
    property color tint2: "#a07cf0"
    property color tint3: "#f2c85b"
    property color base: "#05080b"

    property point origin: Qt.point(0, 0)
    property size world: Qt.size(width, height)
    property size cell: Qt.size(12, 16)
    property bool running: true
    property int fps: 30

    property real time: 0
    readonly property real started: Date.now() / 1000

    Timer {
        interval: Math.round(1000 / field.fps)
        repeat: true
        running: field.running && field.visible
        onTriggered: field.time = Date.now() / 1000 - field.started
    }

    Row {
        id: glyphs
        x: -width - 100

        Repeater {
            model: field.ramp.length

            Text {
                required property int index
                width: field.cell.width
                height: field.cell.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: field.ramp[index]
                font.family: "JetBrainsMono Nerd Font Mono"
                font.pixelSize: Math.round(field.cell.height * 0.72)
                font.weight: Font.Medium
                color: "white"
                renderType: Text.NativeRendering
            }
        }
    }

    ShaderEffectSource {
        id: atlas
        sourceItem: glyphs
        hideSource: true
        visible: false
    }

    ShaderEffect {
        anchors.fill: parent

        property real time: field.time + 1200
        property real glyphs: field.ramp.length
        property size resolution: Qt.size(width, height)
        property point origin: field.origin
        property size world: field.world
        property size cell: field.cell
        property color tint: field.tint
        property color tint2: field.tint2
        property color tint3: field.tint3
        property color base: field.base
        property var atlas: atlas

        fragmentShader: Qt.resolvedUrl("shaders/" + field.scene + ".frag.qsb")
    }
}
