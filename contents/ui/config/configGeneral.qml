import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.components as PlasmaComponents

KCM.SimpleKCM {
    id: page

    property alias cfg_codexbarCommand: codexbarCommand.text
    property string cfg_codexbarCommandDefault
    property alias cfg_aiControlCommand: aiControlCommand.text
    property string cfg_aiControlCommandDefault
    property string cfg_source
    property string cfg_sourceDefault
    property alias cfg_refreshInterval: refreshInterval.value
    property int cfg_refreshIntervalDefault
    property alias cfg_showCreditsInPanel: showCreditsInPanel.checked
    property bool cfg_showCreditsInPanelDefault
    property alias cfg_showUsedPercentInPanel: showUsedPercentInPanel.checked
    property bool cfg_showUsedPercentInPanelDefault
    property alias cfg_showProviderInPanel: showProviderInPanel.checked
    property bool cfg_showProviderInPanelDefault
    property alias cfg_showEmailInWidget: showEmailInWidget.checked
    property bool cfg_showEmailInWidgetDefault
    property alias cfg_includeStatus: includeStatus.checked
    property bool cfg_includeStatusDefault
    property alias cfg_showCostSummary: showCostSummary.checked
    property bool cfg_showCostSummaryDefault
    property alias cfg_compactProviderOrder: compactProviderOrder.text
    property string cfg_compactProviderOrderDefault
    property alias cfg_compactQuotaSelection: compactQuotaSelection.text
    property string cfg_compactQuotaSelectionDefault

    readonly property string compactProviderSelectionDefault: "codex,claude,grok,antigravity"
    readonly property var compactProviderOptions: [
        { providerId: "codex", label: i18n("Codex") },
        { providerId: "claude", label: i18n("Claude") },
        { providerId: "grok", label: i18n("Grok") },
        { providerId: "antigravity", label: i18n("Antigravity") }
    ]

    function indexForValue(model, value) {
        for (var i = 0; i < model.count; i++) {
            if (model.get(i).value === value) {
                return i
            }
        }
        return 0
    }

    function normalizedCompactProviderIds(value) {
        var raw = String(value || "").split(",")
        var ids = []
        var seen = {}
        for (var i = 0; i < raw.length; i++) {
            var id = raw[i].trim().toLowerCase()
            if (id.length > 0 && !seen[id]) {
                seen[id] = true
                ids.push(id)
            }
        }
        return ids
    }

    function compactProviderSelected(providerId) {
        return normalizedCompactProviderIds(compactProviderOrder.text).indexOf(providerId) !== -1
    }

    function setCompactProviderSelected(providerId, selected) {
        var ids = normalizedCompactProviderIds(compactProviderOrder.text)
        var index = ids.indexOf(providerId)
        if (selected && index === -1) {
            ids.push(providerId)
        } else if (!selected && index !== -1) {
            ids.splice(index, 1)
        }
        compactProviderOrder.text = ids.join(",")
    }

    function selectDefaultCompactProviders() {
        compactProviderOrder.text = compactProviderSelectionDefault
    }

    Item {
        implicitWidth: content.implicitWidth + Kirigami.Units.largeSpacing * 2
        implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    text: i18n("CodexBar CLI")
                    level: 3
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

                QQC2.TextField {
                    id: aiControlCommand
                    Kirigami.FormData.label: i18n("AI CLI Control:")
                    placeholderText: "ai"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                }

                PlasmaComponents.Label {
                    text: i18n("Command used by the KodexBar actions to open the separate AI CLI Control selector and update all provider CLIs.")
                    color: Kirigami.Theme.disabledTextColor
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Kirigami.FormData.label: ""
                }

                QQC2.ComboBox {
                    id: source
                    Kirigami.FormData.label: i18n("Source:")
                    textRole: "text"
                    valueRole: "value"
                    model: ListModel {
                        ListElement { text: "Best available"; value: "detect" }
                        ListElement { text: "Auto"; value: "auto" }
                        ListElement { text: "Web"; value: "web" }
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

                QQC2.TextField {
                    id: compactProviderOrder
                    Kirigami.FormData.label: i18n("Compact providers:")
                    placeholderText: "codex,claude,grok,antigravity"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
                }

                PlasmaComponents.Label {
                    text: i18n("Choose the providers shown in the compact panel. The order below is preserved. This never filters the popup.")
                    color: Kirigami.Theme.disabledTextColor
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Kirigami.FormData.label: ""
                }

                QQC2.CheckBox {
                    id: showAllCompactProviders
                    text: i18n("Show all returned providers")
                    checked: compactProviderOrder.text.trim().length === 0
                    onClicked: {
                        if (checked) {
                            compactProviderOrder.text = ""
                        } else {
                            page.selectDefaultCompactProviders()
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: page.compactProviderOptions

                        delegate: QQC2.CheckBox {
                            required property var modelData
                            text: modelData.label
                            enabled: !showAllCompactProviders.checked
                            checked: !showAllCompactProviders.checked
                                && page.compactProviderSelected(modelData.providerId)
                            onClicked: page.setCompactProviderSelected(modelData.providerId, checked)
                        }
                    }
                }

                QQC2.TextField {
                    id: compactQuotaSelection
                    Kirigami.FormData.label: i18n("Compact quotas:")
                    placeholderText: "primary,weekly"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
                }

                PlasmaComponents.Label {
                    text: i18n("Comma-separated quota keys shown in the compact panel. The default is primary,weekly. Add extras for every additional window, or use provider.key for an individual quota such as antigravity.tertiary or claude.fable-only. Leave empty to show provider icons only. The popup always shows every detected quota.")
                    color: Kirigami.Theme.disabledTextColor
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Kirigami.FormData.label: ""
                }

                QQC2.CheckBox {
                    id: showProviderInPanel
                    text: i18n("Show provider in panel")
                }

                QQC2.CheckBox {
                    id: showEmailInWidget
                    text: i18n("Show email in widget")
                }

                QQC2.CheckBox {
                    id: showUsedPercentInPanel
                    text: i18n("Show used percent in panel")
                }

                QQC2.CheckBox {
                    id: showCreditsInPanel
                    text: i18n("Show credits in panel")
                }

                QQC2.CheckBox {
                    id: includeStatus
                    text: i18n("Fetch provider status")
                }

                QQC2.CheckBox {
                    id: showCostSummary
                    text: i18n("Show local cost summary")
                }
            }
        }
    }
}
