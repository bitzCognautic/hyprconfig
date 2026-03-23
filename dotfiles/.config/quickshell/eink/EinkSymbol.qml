import QtQuick

Item {
    id: root

    property string symbol: ""
    property string fallbackSymbol: ""
    property string fallbackIconName: ""
    property string fontFamily: "Material Symbols Rounded"
    property string fontFamilyFallback: "Material Symbols Outlined"
    property color color: "white"
    property real size: 14
    property real iconOpacity: 1.0

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    readonly property var _families: Qt.fontFamilies()
    readonly property bool _hasPrimaryFamily: _families.indexOf(fontFamily) !== -1
    readonly property bool _hasFallbackFamily: _families.indexOf(fontFamilyFallback) !== -1
    readonly property string _pickedFamily: _hasPrimaryFamily
        ? fontFamily
        : (_hasFallbackFamily ? fontFamilyFallback : "")
    readonly property string _pickedSymbol: _hasPrimaryFamily
        ? root.symbol
        : ((root.fallbackSymbol.length > 0) ? root.fallbackSymbol : root.symbol)
    readonly property bool _canUseFont: _pickedFamily.length > 0 && root._pickedSymbol.length > 0

    Text {
        anchors.centerIn: parent
        visible: root._canUseFont
        text: root._pickedSymbol
        color: root.color
        opacity: root.iconOpacity
        font.family: root._pickedFamily
        font.pixelSize: root.size
        font.weight: Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
    }

    EinkIcon {
        anchors.centerIn: parent
        visible: !root._canUseFont && root.fallbackIconName.length > 0
        iconName: root.fallbackIconName
        color: root.color
        size: root.size
        iconOpacity: root.iconOpacity
    }
}
