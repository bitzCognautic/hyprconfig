import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property string iconName: ""
    property color color: "white"
    property real size: 14
    property real iconOpacity: 1.0
    // When false, render the icon as-is (no recolor). Useful for brand icons like Discord.
    property bool tint: true

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Image {
        id: src
        anchors.fill: parent
        visible: !root.tint
        smooth: true
        source: root.iconName.length ? Quickshell.iconPath(root.iconName) : ""
        fillMode: Image.PreserveAspectFit
        sourceSize.width: root.size
        sourceSize.height: root.size
        opacity: root.iconOpacity
    }

    ColorOverlay {
        anchors.fill: parent
        source: src
        color: root.color
        opacity: root.iconOpacity
        cached: true
        visible: root.tint
    }
}
