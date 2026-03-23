import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel

Item {
    id: root

    property var theme
    property var settings

    signal requestClose()

    implicitWidth: 520
    implicitHeight: 420

    property int sectionIndex: 0 // 0 = General, 1 = Wallpapers

    // Accent is static (no dynamic wallpaper colors).

    function stepInt(key, cur, delta, minVal, maxVal) {
        const next = Math.max(minVal, Math.min(maxVal, Math.round(cur + delta)))
        const obj = ({})
        obj[key] = next
        root.settings.save(obj)
    }

    function stepReal(key, cur, delta, minVal, maxVal) {
        const next = Math.max(minVal, Math.min(maxVal, Math.round((cur + delta) * 100) / 100))
        const obj = ({})
        obj[key] = next
        root.settings.save(obj)
    }

	    Rectangle {
	        anchors.fill: parent
	        radius: 22
	        color: Qt.rgba(0.08, 0.08, 0.08, 0.97)
	        border.width: 1
	        border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)
	    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

	                        RowLayout {
	                            Layout.fillWidth: true
	                            spacing: 10

            Text {
                text: "Settings"
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }

            Rectangle {
                width: 34
                height: 34
                radius: 12
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestClose()
                }
                EinkSymbol {
                    anchors.centerIn: parent
                    // Nerd Font Material Design: nf-md-close (f0156)
                    symbol: String.fromCodePoint(0xF0156)
                    fallbackSymbol: "close"
                    fontFamily: root.theme.iconFontFamily
                    fontFamilyFallback: root.theme.iconFontFamilyFallback
                    color: root.theme.text
                    size: 18
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            radius: 1
            color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)
        }

        // Section tabs
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 14
            color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.75)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 12
                    color: root.sectionIndex === 0
                        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                        : "transparent"
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.sectionIndex = 0 }
                    Text {
                        anchors.centerIn: parent
                        text: "General"
                        color: root.sectionIndex === 0 ? root.theme.onAccent : root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 12
                    color: root.sectionIndex === 1
                        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                        : "transparent"
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.sectionIndex = 1 }
                    Text {
                        anchors.centerIn: parent
                        text: "Wallpapers"
                        color: root.sectionIndex === 1 ? root.theme.onAccent : root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.sectionIndex

            // General
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Flickable {
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: generalContent.implicitHeight

                    ColumnLayout {
                        id: generalContent
                        width: parent.width
                        spacing: 14

                    // Top bar
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: "Top bar"
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "Top margin"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillTopMargin", root.settings.pillTopMargin, -1, 0, 40) }
                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }

                            Text {
                                text: "" + root.settings.pillTopMargin
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                width: 34
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillTopMargin", root.settings.pillTopMargin, 1, 0, 40) }
                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "Height"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillHeight", root.settings.pillHeight, -1, 24, 60) }
                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }

                            Text {
                                text: "" + root.settings.pillHeight
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                width: 34
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillHeight", root.settings.pillHeight, 1, 24, 60) }
                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "Horizontal padding"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillHPadding", root.settings.pillHPadding, -2, -1, 80) }
                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }

                            Text {
                                text: "" + root.settings.pillHPadding
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                width: 34
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillHPadding", root.settings.pillHPadding, 2, -1, 80) }
                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "Opacity"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepReal("pillOpacity", root.settings.pillOpacity, -0.05, 0.15, 1.0) }
                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }

                            Text {
                                text: Math.round(root.settings.pillOpacity * 100) + "%"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                width: 52
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepReal("pillOpacity", root.settings.pillOpacity, 0.05, 0.15, 1.0) }
                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }
	                        }
	                    }

	                    // Idle (hypridle)
	                    ColumnLayout {
	                        Layout.fillWidth: true
	                        spacing: 10

	                        Text {
	                            text: "Idle"
	                            color: root.theme.textMuted
	                            font.family: root.theme.fontFamily
	                            font.pixelSize: 11
	                            font.weight: Font.DemiBold
	                        }

	                        RowLayout {
	                            Layout.fillWidth: true
	                            spacing: 10

		                            Text {
		                                text: "Screen off after"
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                Layout.fillWidth: true
	                            }

		                            Text {
		                                text: Math.round(root.settings.idleScreenOffSeconds) + "s"
	                                color: root.theme.textMuted
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                font.weight: Font.DemiBold
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
		                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.stepInt("idleScreenOffSeconds", root.settings.idleScreenOffSeconds, -15, 0, 7200); root.settings.applyIdle() } }
	                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
		                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.stepInt("idleScreenOffSeconds", root.settings.idleScreenOffSeconds, 15, 0, 7200); root.settings.applyIdle() } }
	                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }
	                        }

	                        RowLayout {
	                            Layout.fillWidth: true
	                            spacing: 10

	                            Text {
	                                text: "Sleep after"
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                Layout.fillWidth: true
	                            }

	                            Text {
	                                text: Math.round(root.settings.idleSleepSeconds) + "s"
	                                color: root.theme.textMuted
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                font.weight: Font.DemiBold
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.stepInt("idleSleepSeconds", root.settings.idleSleepSeconds, -60, 0, 14400); root.settings.applyIdle() } }
	                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.stepInt("idleSleepSeconds", root.settings.idleSleepSeconds, 60, 0, 14400); root.settings.applyIdle() } }
	                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }
	                        }

		                        // (No dim level for DPMS off)
	                    }

	                    // Nightlight (wlsunset)
	                    ColumnLayout {
	                        Layout.fillWidth: true
	                        spacing: 10

	                        Text {
	                            text: "Nightlight"
	                            color: root.theme.textMuted
	                            font.family: root.theme.fontFamily
	                            font.pixelSize: 11
	                            font.weight: Font.DemiBold
	                        }

	                        RowLayout {
	                            Layout.fillWidth: true
	                            spacing: 10

	                            Text {
	                                text: "Day temp"
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                Layout.fillWidth: true
	                            }

	                            Text {
	                                text: Math.round(root.settings.nightlightTempDay) + "K"
	                                color: root.theme.textMuted
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                font.weight: Font.DemiBold
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("nightlightTempDay", root.settings.nightlightTempDay, -100, 2000, 6500) }
	                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("nightlightTempDay", root.settings.nightlightTempDay, 100, 2000, 6500) }
	                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }
	                        }

	                        RowLayout {
	                            Layout.fillWidth: true
	                            spacing: 10

	                            Text {
	                                text: "Night temp"
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                Layout.fillWidth: true
	                            }

	                            Text {
	                                text: Math.round(root.settings.nightlightTempNight) + "K"
	                                color: root.theme.textMuted
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                font.weight: Font.DemiBold
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("nightlightTempNight", root.settings.nightlightTempNight, -100, 2000, 6500) }
	                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("nightlightTempNight", root.settings.nightlightTempNight, 100, 2000, 6500) }
	                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }
	                        }

	                        Text {
	                            visible: root.settings.nightlightTempDay <= root.settings.nightlightTempNight
	                            text: "Day temp must be higher than night temp"
	                            color: Qt.rgba(1, 0.35, 0.35, 0.9)
	                            font.family: root.theme.fontFamily
	                            font.pixelSize: 11
	                            font.weight: Font.DemiBold
	                        }
	                    }

	                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            radius: 14
                            color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
	                                onClicked: root.settings.save({
	                                    pillTopMargin: 5,
	                                    pillHeight: 34,
	                                    pillHPadding: -1,
	                                    pillOpacity: 1.0,
	                                    popupGap: 10,
	                                    popupOverlap: 10,
	                                    idleScreenOffSeconds: 120,
	                                    idleSleepSeconds: 900,
	                                    nightlightTempDay: 3400,
	                                    nightlightTempNight: 3200,
	                                })
	                            }
                            Text {
                                anchors.centerIn: parent
                                text: "Reset defaults"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                    }
                }
            }

            // Wallpapers
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: wallpapersSection
                    anchors.fill: parent
                    spacing: 10

                    readonly property string wallpapersDir: (root.settings?.home ?? "") + "/Pictures/Wallpapers/"
                    property string selectedWallpaper: ""

	                    Text {
	                        text: "Wallpaper"
	                        color: root.theme.textMuted
	                        font.family: root.theme.fontFamily
	                        font.pixelSize: 11
	                        font.weight: Font.DemiBold
	                    }

	                    // Search
	                    Rectangle {
	                        Layout.fillWidth: true
	                        height: 36
	                        radius: 14
	                        color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.75)
	                        border.width: 1
	                        border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.25)

	                        RowLayout {
	                            anchors.fill: parent
	                            anchors.margins: 8
	                            spacing: 8

	                            EinkSymbol {
	                                symbol: String.fromCodePoint(0xF034E) // nf-md-magnify
	                                fallbackSymbol: "search"
	                                fontFamily: root.theme.iconFontFamily
	                                fontFamilyFallback: root.theme.iconFontFamilyFallback
	                                color: root.theme.textMuted
	                                size: 16
	                                Layout.alignment: Qt.AlignVCenter
	                            }

	                            TextInput {
	                                id: wallpaperSearch
	                                Layout.fillWidth: true
	                                focus: true
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                clip: true
	                                selectByMouse: true
	                                onTextChanged: wallpapersModel.nameFilters = [
	                                    "*" + text + "*.png",
	                                    "*" + text + "*.jpg",
	                                    "*" + text + "*.jpeg",
	                                    "*" + text + "*.webp",
	                                    "*" + text + "*.PNG",
	                                    "*" + text + "*.JPG",
	                                    "*" + text + "*.JPEG",
	                                    "*" + text + "*.WEBP",
	                                ]
	                            }

	                            Text {
	                                visible: wallpaperSearch.text.length === 0 && !wallpaperSearch.activeFocus
	                                text: "Search wallpapers…"
	                                color: Qt.rgba(root.theme.textMuted.r, root.theme.textMuted.g, root.theme.textMuted.b, 0.9)
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                elide: Text.ElideRight
	                                Layout.fillWidth: true
	                                Layout.alignment: Qt.AlignVCenter
	                                MouseArea {
	                                    anchors.fill: parent
	                                    cursorShape: Qt.IBeamCursor
	                                    onClicked: wallpaperSearch.forceActiveFocus()
	                                }
	                            }
	                        }
	                    }

	                    FolderListModel {
	                        id: wallpapersModel
	                        // FolderListModel expects a file URL. Build a stable `file:///.../` URL.
	                        folder: "file:///" + String(wallpapersSection.wallpapersDir).split("/").filter(s => s.length > 0).join("/") + "/"
	                        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]
	                        showDirs: false
	                        showDotAndDotDot: false
	                        sortField: FolderListModel.Name
	                        sortReversed: false
	                    }

                    Text {
                        visible: wallpapersModel.count === 0
                        text: "No images found in " + wallpapersSection.wallpapersDir
                        color: root.theme.textMuted
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                    }

		                    GridView {
	                        Layout.fillWidth: true
	                        Layout.fillHeight: true
	                        visible: wallpapersModel.count > 0
	                        clip: true
	                        // Fit an integer number of columns to remove leftover right-side space.
	                        readonly property int cols: Math.max(2, Math.floor(width / 160))
	                        cellWidth: Math.floor(width / cols)
	                        cellHeight: 96
	                        model: wallpapersModel

		                        delegate: Rectangle {
	                            width: GridView.view.cellWidth - 10
	                            height: 86
	                            x: Math.round((GridView.view.cellWidth - width) / 2)
	                            radius: 14
	                            color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.85)
                            border.width: (wallpapersSection.selectedWallpaper === filePath) ? 2 : 1
                            border.color: (wallpapersSection.selectedWallpaper === filePath)
                                ? root.theme.accent
                                : Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)

	                            Image {
	                                anchors.fill: parent
	                                anchors.margins: 6
	                                source: "file://" + filePath
	                                fillMode: Image.PreserveAspectCrop
	                                asynchronous: true
	                                cache: true
	                                smooth: false
	                                mipmap: false
	                                sourceSize.width: 240
	                                sourceSize.height: 140
	                                clip: true
	                            }

	                            MouseArea {
	                                anchors.fill: parent
	                                hoverEnabled: true
	                                cursorShape: Qt.PointingHandCursor
	                                onClicked: {
	                                    wallpapersSection.selectedWallpaper = filePath
	                                    root.settings.applyWallpaper(filePath)
	                                    console.warn("wallpaper: applied", filePath)
	                                }
	                            }
                        }
                    }
                }
            }
        }
    }
}
