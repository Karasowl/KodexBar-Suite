import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    id: page
    spacing: 0

    property alias cfg_codexbarCommand: codexbarCommand.text
    property string cfg_provider
    property string cfg_source
    property alias cfg_refreshInterval: refreshInterval.value
    property alias cfg_showCreditsInPanel: showCreditsInPanel.checked

    function indexForValue(model, value) {
        for (var i = 0; i < model.count; i++) {
            if (model.get(i).value === value) {
                return i
            }
        }
        return 0
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Layout.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: i18n("CodexBar CLI")
                font.weight: Font.DemiBold
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                text: i18n("Choose how the panel widget queries CodexBar usage data.")
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.TextField {
                id: codexbarCommand
                Kirigami.FormData.label: i18n("Command:")
                placeholderText: "codexbar"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            }

            QQC2.ComboBox {
                id: provider
                Kirigami.FormData.label: i18n("Provider:")
                textRole: "text"
                valueRole: "value"
                model: ListModel {
                    ListElement { text: "Best available"; value: "detect" }
                    ListElement { text: "All enabled"; value: "all" }
                    ListElement { text: "Codex"; value: "codex" }
                    ListElement { text: "Claude"; value: "claude" }
                    ListElement { text: "OpenAI API"; value: "openai" }
                    ListElement { text: "Copilot"; value: "copilot" }
                    ListElement { text: "Gemini"; value: "gemini" }
                }
                currentIndex: page.indexForValue(model, page.cfg_provider || "detect")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                onActivated: function(index) {
                    page.cfg_provider = model.get(index).value
                }
            }

            QQC2.ComboBox {
                id: source
                Kirigami.FormData.label: i18n("Source:")
                textRole: "text"
                valueRole: "value"
                model: ListModel {
                    ListElement { text: "Best available"; value: "detect" }
                    ListElement { text: "Auto"; value: "auto" }
                    ListElement { text: "CLI"; value: "cli" }
                    ListElement { text: "OAuth"; value: "oauth" }
                    ListElement { text: "API"; value: "api" }
                }
                currentIndex: page.indexForValue(model, page.cfg_source || "detect")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                onActivated: function(index) {
                    page.cfg_source = model.get(index).value
                }
            }

            QQC2.SpinBox {
                id: refreshInterval
                Kirigami.FormData.label: i18n("Refresh:")
                from: 10
                to: 3600
                stepSize: 10
                textFromValue: function(value) { return i18np("%1 second", "%1 seconds", value) }
                valueFromText: function(text) { return Number(text.replace(/\D/g, "")) }
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            }

            QQC2.CheckBox {
                id: showCreditsInPanel
                text: i18n("Show credits in panel")
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
