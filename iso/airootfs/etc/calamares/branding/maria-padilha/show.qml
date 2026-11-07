// SPDX-License-Identifier: GPL-3.0-only
//
// Calamares execution slideshow.  Uses only the branding directory's own
// logo and the Maria Padilha palette; no network image, font or animation.

import QtQuick 2.15

Rectangle {
    id: root
    color: "#120807"

    property string statusText: qsTr("Installing Maria Padilha OS")

    function onActivate() {
        statusText = qsTr("Installing Maria Padilha OS")
    }

    function onLeave() {
    }

    Column {
        anchors.centerIn: parent
        spacing: 22

        Image {
            source: "logo.svg"
            width: 132
            height: 132
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: root.statusText
            color: "#f3e6da"
            font.family: "DejaVu Sans"
            font.pixelSize: 24
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: qsTr("Offline install — packages come from the ISO")
            color: "#d8a24a"
            font.family: "DejaVu Sans"
            font.pixelSize: 15
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Rectangle {
            width: 260
            height: 3
            radius: 2
            color: "#b12e1b"
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
