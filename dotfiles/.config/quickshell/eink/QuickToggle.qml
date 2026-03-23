import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var theme
    property string label: ""
    property string symbol: ""
    property string fallbackSymbol: ""
    property string iconFontFamily: ""
    property string iconFontFamilyFallback: ""
    property bool checked: false
    property bool enabled: true

    signal clicked()
    signal rightClicked()

    implicitWidth: 118
    implicitHeight: 54

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: !root.enabled
            ? Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.45)
            : (root.checked
                ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                : Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95))
        border.width: 0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            EinkSymbol {
                symbol: root.symbol
                fallbackSymbol: root.fallbackSymbol
                fontFamily: root.iconFontFamily.length > 0 ? root.iconFontFamily : root.theme.iconFontFamily
                fontFamilyFallback: root.iconFontFamilyFallback.length > 0 ? root.iconFontFamilyFallback : root.theme.iconFontFamilyFallback
                color: (!root.enabled
                    ? Qt.rgba(root.theme.textMuted.r, root.theme.textMuted.g, root.theme.textMuted.b, 0.7)
                    : (root.checked ? root.theme.onAccent : root.theme.text))
                size: 18
                iconOpacity: 1.0
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            }

            Text {
                text: root.label
                color: (!root.enabled
                    ? Qt.rgba(root.theme.textMuted.r, root.theme.textMuted.g, root.theme.textMuted.b, 0.7)
                    : (root.checked ? root.theme.onAccent : root.theme.text))
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
                Layout.fillWidth: true
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    root.rightClicked()
                    return
                }
                root.clicked()
            }
        }
    }
}
