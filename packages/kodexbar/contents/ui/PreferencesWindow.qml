import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols
import org.kde.plasma.plasmoid

QQC2.ApplicationWindow {
    id: preferences

    property var appletRoot
    property string currentPage: "general"
    readonly property int fontSizeTitle: 26
    readonly property int fontSizeCardTitle: 17
    readonly property int fontSizeBody: 13
    readonly property int fontSizeSecondary: 12
    readonly property int fontSizeMicro: 10
    property string savedState: ""
    property string workingCommand: ""
    property string workingAiControlCommand: ""
    property string workingSourceDefault: "detect"
    property int workingRefreshInterval: 60
    property int workingClaudeRefreshInterval: 300
    property string workingCompactProviderOrder: "codex,claude,grok,antigravity"
    property string workingCompactQuotaSelection: "primary,weekly"
    property bool workingShowProviderInPanel: true
    property bool workingShowUsedPercentInPanel: true
    property bool workingShowCreditsInPanel: false
    property bool workingIncludeStatus: false
    property bool workingShowEmailInWidget: false
    property bool workingShowCostSummary: true
    property string workingShortcut: ""
    readonly property bool showAllProviders: workingCompactProviderOrder.trim().length === 0
    readonly property var providerIds: providerList()
    readonly property var activeProviderIds: normalizedProviderIds(workingCompactProviderOrder)
    readonly property var activeKnownProviderIds: knownActiveProviderIds()
    readonly property var compactProviderChipIds: orderedProviderIds()
    readonly property bool dirty: snapshot() !== savedState
    readonly property var previewState: appletRoot
        ? appletRoot.compactResultForOrder(workingCompactProviderOrder, {
            quotaSelection: workingCompactQuotaSelection,
            showProvider: workingShowProviderInPanel,
            showUsed: workingShowUsedPercentInPanel,
            showCredits: workingShowCreditsInPanel
        })
        : ({ blocks: [], text: "" })

    visible: false
    width: 980
    height: 680
    minimumWidth: 820
    minimumHeight: 560
    title: i18n("KodexBar Suite Preferences")
    color: "#0a0a0c"
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    function normalizedProviderIds(value) {
        var ids = []
        var seen = {}
        var raw = String(value || "").split(",")
        for (var i = 0; i < raw.length; i++) {
            var id = raw[i].trim().toLowerCase()
            if (id.length > 0 && !seen[id]) {
                seen[id] = true
                ids.push(id)
            }
        }
        return ids
    }

    function providerList() {
        var ids = ["codex", "claude", "grok", "antigravity"]
        var seen = { codex: true, claude: true, grok: true, antigravity: true }
        var entries = appletRoot && Array.isArray(appletRoot.entries) ? appletRoot.entries : []
        for (var i = 0; i < entries.length; i++) {
            var id = String(entries[i].provider || "").trim().toLowerCase()
            if (id.length > 0 && !seen[id]) {
                seen[id] = true
                ids.push(id)
            }
        }
        return ids
    }

    function knownActiveProviderIds() {
        var ids = []
        for (var i = 0; i < providerIds.length; i++) {
            if (activeProviderIds.indexOf(providerIds[i]) !== -1) {
                ids.push(providerIds[i])
            }
        }
        return ids
    }

    function orderedProviderIds() {
        var ids = []
        for (var i = 0; i < activeProviderIds.length; i++) {
            if (providerIds.indexOf(activeProviderIds[i]) !== -1) {
                ids.push(activeProviderIds[i])
            }
        }
        for (var j = 0; j < providerIds.length; j++) {
            if (ids.indexOf(providerIds[j]) === -1) {
                ids.push(providerIds[j])
            }
        }
        return ids
    }

    function providerLabel(providerId) {
        var names = {
            codex: i18n("Codex"),
            claude: i18n("Claude"),
            grok: i18n("Grok"),
            antigravity: i18n("Antigravity")
        }
        return names[providerId] || providerId.charAt(0).toUpperCase() + providerId.slice(1)
    }

    function providerIcon(providerId) {
        return Qt.resolvedUrl("../icons/providers/" + providerId + ".svg")
    }

    function snapshot() {
        return JSON.stringify({
            command: workingCommand,
            aiControlCommand: workingAiControlCommand,
            sourceDefault: workingSourceDefault,
            refreshInterval: workingRefreshInterval,
            claudeRefreshInterval: workingClaudeRefreshInterval,
            compactProviderOrder: workingCompactProviderOrder,
            compactQuotaSelection: workingCompactQuotaSelection,
            showProviderInPanel: workingShowProviderInPanel,
            showUsedPercentInPanel: workingShowUsedPercentInPanel,
            showCreditsInPanel: workingShowCreditsInPanel,
            includeStatus: workingIncludeStatus,
            showEmailInWidget: workingShowEmailInWidget,
            showCostSummary: workingShowCostSummary,
            shortcut: workingShortcut
        })
    }

    function load() {
        workingCommand = String(Plasmoid.configuration.codexbarCommand || "kodexbar-quotas")
        workingAiControlCommand = String(Plasmoid.configuration.aiControlCommand || "ai")
        workingSourceDefault = String(Plasmoid.configuration.sourceDefault
            || Plasmoid.configuration.source || "detect")
        workingRefreshInterval = Math.max(10, Math.min(3600,
            Number(Plasmoid.configuration.refreshInterval || 60)))
        workingClaudeRefreshInterval = Math.max(60, Math.min(3600,
            Number(Plasmoid.configuration.claudeRefreshInterval || 300)))
        workingCompactProviderOrder = Plasmoid.configuration.compactProviderOrder === undefined
            ? "codex,claude,grok,antigravity"
            : String(Plasmoid.configuration.compactProviderOrder)
        workingCompactQuotaSelection = Plasmoid.configuration.compactQuotaSelection === undefined
            ? "primary,weekly"
            : String(Plasmoid.configuration.compactQuotaSelection)
        workingShowProviderInPanel = Plasmoid.configuration.showProviderInPanel === undefined
            ? true : Plasmoid.configuration.showProviderInPanel
        workingShowUsedPercentInPanel = Plasmoid.configuration.showUsedPercentInPanel === undefined
            ? true : Plasmoid.configuration.showUsedPercentInPanel
        workingShowCreditsInPanel = Plasmoid.configuration.showCreditsInPanel === undefined
            ? false : Plasmoid.configuration.showCreditsInPanel
        workingIncludeStatus = Plasmoid.configuration.includeStatus === undefined
            ? false : Plasmoid.configuration.includeStatus
        workingShowEmailInWidget = Plasmoid.configuration.showEmailInWidget === undefined
            ? false : Plasmoid.configuration.showEmailInWidget
        workingShowCostSummary = Plasmoid.configuration.showCostSummary === undefined
            ? true : Plasmoid.configuration.showCostSummary
        workingShortcut = String(Plasmoid.globalShortcut || "")
        savedState = snapshot()
    }

    function save() {
        Plasmoid.configuration.codexbarCommand = workingCommand
        Plasmoid.configuration.aiControlCommand = workingAiControlCommand
        Plasmoid.configuration.sourceDefault = workingSourceDefault
        Plasmoid.configuration.refreshInterval = workingRefreshInterval
        Plasmoid.configuration.claudeRefreshInterval = workingClaudeRefreshInterval
        Plasmoid.configuration.compactProviderOrder = workingCompactProviderOrder
        Plasmoid.configuration.compactQuotaSelection = workingCompactQuotaSelection
        Plasmoid.configuration.showProviderInPanel = workingShowProviderInPanel
        Plasmoid.configuration.showUsedPercentInPanel = workingShowUsedPercentInPanel
        Plasmoid.configuration.showCreditsInPanel = workingShowCreditsInPanel
        Plasmoid.configuration.includeStatus = workingIncludeStatus
        Plasmoid.configuration.showEmailInWidget = workingShowEmailInWidget
        Plasmoid.configuration.showCostSummary = workingShowCostSummary
        Plasmoid.globalShortcut = workingShortcut
        savedState = snapshot()
    }

    function restoreDefaults() {
        workingCommand = "kodexbar-quotas"
        workingAiControlCommand = "ai"
        workingSourceDefault = "detect"
        workingRefreshInterval = 60
        workingClaudeRefreshInterval = 300
        workingCompactProviderOrder = "codex,claude,grok,antigravity"
        workingCompactQuotaSelection = "primary,weekly"
        workingShowProviderInPanel = true
        workingShowUsedPercentInPanel = true
        workingShowCreditsInPanel = false
        workingIncludeStatus = false
        workingShowEmailInWidget = false
        workingShowCostSummary = true
        workingShortcut = ""
    }

    function cancel() {
        load()
        visible = false
    }

    function openPreferences() {
        load()
        visible = true
        raise()
        requestActivate()
    }

    function isProviderActive(providerId) {
        return activeProviderIds.indexOf(providerId) !== -1
    }

    function toggleProvider(providerId) {
        if (showAllProviders) {
            return
        }
        var ids = activeProviderIds.slice()
        var index = ids.indexOf(providerId)
        if (index === -1) {
            ids.push(providerId)
        } else {
            ids.splice(index, 1)
        }
        workingCompactProviderOrder = ids.join(",")
    }

    function moveProvider(providerId, beforeProviderId) {
        if (showAllProviders || providerId === beforeProviderId) {
            return
        }
        var ids = activeProviderIds.slice()
        var from = ids.indexOf(providerId)
        var to = ids.indexOf(beforeProviderId)
        if (from === -1 || to === -1 || from === to) {
            return
        }
        ids.splice(from, 1)
        ids.splice(to, 0, providerId)
        workingCompactProviderOrder = ids.join(",")
    }

    onClosing: function(close) {
        close.accepted = false
        cancel()
    }

    Component.onCompleted: load()

    Rectangle {
        anchors.fill: parent
        color: "#0a0a0c"

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 238
                color: "#0f1015"
                border.color: "#22252f"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 22
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            radius: 10
                            color: "#6e5aff"

                            Image {
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                source: Qt.resolvedUrl("../icons/kodexbar.svg")
                                fillMode: Image.PreserveAspectFit
                            }
                        }

                        ColumnLayout {
                            spacing: 0

                            QQC2.Label {
                                text: i18n("KodexBar Suite")
                                color: "#e9ebf2"
                                font.family: appletRoot ? appletRoot.designFont : ""
                                font.bold: true
                            }

                            QQC2.Label {
                                text: i18n("Preferences")
                                color: "#8b91a3"
                                font.family: appletRoot ? appletRoot.designFont : ""
                                font.pixelSize: 11
                            }
                        }
                    }

                    Repeater {
                        model: [
                            { id: "general", text: i18n("General"), icon: "adjustfilters" },
                            { id: "shortcuts", text: i18n("Keyboard shortcuts"), icon: "input-keyboard" },
                            { id: "about", text: i18n("About"), icon: "dialog-information" }
                        ]

                        delegate: QQC2.Button {
                            required property var modelData
                            Layout.fillWidth: true
                            height: 42
                            text: modelData.text
                            icon.name: modelData.icon
                            checkable: true
                            checked: preferences.currentPage === modelData.id
                            onClicked: preferences.currentPage = modelData.id

                            contentItem: RowLayout {
                                spacing: 10

                                Kirigami.Icon {
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    source: modelData.icon
                                    color: parent.parent.checked ? "#ffffff" : "#8b91a3"
                                }

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: modelData.text
                                    color: parent.parent.checked ? "#ffffff" : "#c3c7d2"
                                    font.family: appletRoot ? appletRoot.designFont : ""
                                    font.weight: parent.parent.checked ? Font.DemiBold : Font.Normal
                                }
                            }

                            background: Rectangle {
                                radius: 10
                                color: parent.checked ? "#6e5aff" : "transparent"
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#0a0a0c"

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        QQC2.ScrollView {
                            id: pageScroll
                            anchors.fill: parent
                            anchors.margins: 28
                            contentWidth: pageScroll.availableWidth
                            clip: true

                            ColumnLayout {
                                width: pageScroll.availableWidth
                                spacing: 18

                                StackLayout {
                                    Layout.fillWidth: true
                                    currentIndex: preferences.currentPage === "general" ? 0
                                        : preferences.currentPage === "shortcuts" ? 1 : 2

                                    ColumnLayout {
                                        spacing: 18

                                        RowLayout {
                                            Layout.fillWidth: true

                                            ColumnLayout {
                                                QQC2.Label {
                                                    text: i18n("General")
                                                    color: "#e9ebf2"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeTitle
                                                    font.bold: true
                                                }

                                                QQC2.Label {
                                                    text: i18n("Configure how KodexBar Suite reads and presents usage.")
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeBody
                                                }
                                            }

                                            Item { Layout.fillWidth: true }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 82
                                            radius: 14
                                            color: "#14161d"
                                            border.color: "#22252f"
                                            border.width: 1

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 14
                                                spacing: 7

                                                RowLayout {
                                                    Layout.fillWidth: true

                                                    QQC2.Label {
                                                        text: i18n("PANEL PREVIEW")
                                                        color: "#8b91a3"
                                                        font.family: appletRoot ? appletRoot.designFont : ""
                                                        font.pixelSize: preferences.fontSizeMicro
                                                        font.weight: Font.DemiBold
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    Rectangle {
                                                        Layout.preferredWidth: 7
                                                        Layout.preferredHeight: 7
                                                        radius: 4
                                                        color: "#45d483"
                                                    }

                                                    QQC2.Label {
                                                        text: i18n("LIVE")
                                                        color: "#45d483"
                                                        font.family: appletRoot ? appletRoot.designFont : ""
                                                        font.pixelSize: preferences.fontSizeMicro
                                                        font.weight: Font.DemiBold
                                                    }
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 30
                                                    radius: 9
                                                    color: "#14161d"
                                                    border.color: "#262a35"
                                                    border.width: 1
                                                    clip: true

                                                    Row {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 10
                                                        spacing: 9

                                                        Repeater {
                                                            model: preferences.previewState.blocks || []

                                                            delegate: Row {
                                                                spacing: 6

                                                                Rectangle {
                                                                    visible: index > 0
                                                                    width: visible ? 1 : 0
                                                                    height: 15
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    color: "#333844"
                                                                }

                                                                Rectangle {
                                                                    width: 7
                                                                    height: 7
                                                                    radius: 4
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    color: modelData.error ? "#f76b6b"
                                                                        : modelData.cached ? "#6b7080"
                                                                        : appletRoot.metricAccent(
                                                                            modelData.worstUsedPercent === null
                                                                                || modelData.worstUsedPercent === undefined
                                                                                ? null : 100 - modelData.worstUsedPercent,
                                                                            modelData.worstUsedPercent !== null
                                                                                && modelData.worstUsedPercent !== undefined)
                                                                }

                                                                Image {
                                                                    visible: preferences.workingShowProviderInPanel
                                                                    width: visible ? 15 : 0
                                                                    height: 15
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    source: preferences.providerIcon(modelData.provider)
                                                                    fillMode: Image.PreserveAspectFit
                                                                }

                                                                QQC2.Label {
                                                                    visible: !!(modelData.ordinal && modelData.ordinal.length > 0)
                                                                    text: modelData.ordinal || ""
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    color: "#6b7080"
                                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                                    font.pixelSize: 11
                                                                }

                                                                QQC2.Label {
                                                                    text: modelData.displayText || ""
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    color: modelData.error ? "#f76b6b" : "#e9ebf2"
                                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                                    font.pixelSize: 13
                                                                    font.weight: modelData.error ? Font.Bold : Font.DemiBold
                                                                }
                                                            }
                                                        }

                                                        QQC2.Label {
                                                            visible: !preferences.previewState.blocks
                                                                || preferences.previewState.blocks.length === 0
                                                            text: preferences.previewState.text || i18n("No data")
                                                            color: "#8b91a3"
                                                            font.family: appletRoot ? appletRoot.designFont : ""
                                                            font.pixelSize: 12
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        PreferenceCard {
                                            title: i18n("Data source")
                                            subtitle: i18n("How the widget queries KodexBar usage data")

                                            ColumnLayout {
                                                width: parent.width
                                                spacing: 12

                                                PreferenceField {
                                                    label: i18n("Command")
                                                    QQC2.TextField {
                                                        Layout.fillWidth: true
                                                        text: preferences.workingCommand
                                                        placeholderText: "kodexbar-quotas"
                                                        selectByMouse: true
                                                        onTextEdited: preferences.workingCommand = text
                                                    }
                                                }

                                                QQC2.Label {
                                                    Layout.fillWidth: true
                                                    text: i18n("Leave empty to use the kodexbar-quotas engine with its upstream fallback chain.")
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeSecondary
                                                    wrapMode: Text.WordWrap
                                                }

                                                PreferenceField {
                                                    label: i18n("AI CLI control")
                                                    QQC2.TextField {
                                                        Layout.fillWidth: true
                                                        text: preferences.workingAiControlCommand
                                                        placeholderText: "ai"
                                                        selectByMouse: true
                                                        onTextEdited: preferences.workingAiControlCommand = text
                                                    }
                                                }

                                                QQC2.Label {
                                                    Layout.fillWidth: true
                                                    text: i18n("Opens the AI CLI Control selector and updates provider CLIs.")
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeSecondary
                                                    wrapMode: Text.WordWrap
                                                }

                                                PreferenceField {
                                                    label: i18n("Source")

                                                    RowLayout {
                                                        spacing: 6

                                                        Repeater {
                                                            model: [
                                                                { label: i18n("Auto"), value: "detect" },
                                                                { label: i18n("CLI"), value: "cli" },
                                                                { label: i18n("OAuth"), value: "oauth" }
                                                            ]

                                                            delegate: QQC2.Button {
                                                                required property var modelData
                                                                text: modelData.label
                                                                checkable: true
                                                                checked: preferences.workingSourceDefault === modelData.value
                                                                onClicked: preferences.workingSourceDefault = modelData.value
                                                                background: Rectangle {
                                                                    radius: 8
                                                                    color: parent.checked ? "#6e5aff" : "#1b1e28"
                                                                    border.color: parent.checked ? "#6e5aff" : "#22252f"
                                                                    border.width: 1
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                QQC2.Label {
                                                    Layout.fillWidth: true
                                                    text: i18n("Auto picks the best available source.")
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeSecondary
                                                }

                                                QQC2.CheckBox {
                                                    objectName: "includeStatusCheck"
                                                    text: i18n("Include provider status in usage queries")
                                                    checked: preferences.workingIncludeStatus
                                                    onToggled: preferences.workingIncludeStatus = checked
                                                }

                                                QQC2.Label {
                                                    Layout.fillWidth: true
                                                    text: i18n("Adds the status field to each CLI query.")
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeSecondary
                                                    wrapMode: Text.WordWrap
                                                }
                                            }
                                        }

                                        PreferenceCard {
                                            title: i18n("Refresh")
                                            subtitle: i18n("How often quotas are queried")

                                            ColumnLayout {
                                                width: parent.width
                                                spacing: 12

                                                PreferenceField {
                                                    label: i18n("General interval")
                                                    QQC2.SpinBox {
                                                        Layout.preferredWidth: 150
                                                        from: 10
                                                        to: 3600
                                                        stepSize: 10
                                                        value: preferences.workingRefreshInterval
                                                        textFromValue: function(value) { return i18n("%1 s", value) }
                                                        valueFromText: function(text) { return Number(text.replace(/\D/g, "")) }
                                                        onValueModified: preferences.workingRefreshInterval = value
                                                    }
                                                }

                                                QQC2.Label {
                                                    text: i18n("Applies to all providers.")
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeSecondary
                                                }

                                                PreferenceField {
                                                    label: i18n("Claude interval")
                                                    QQC2.SpinBox {
                                                        Layout.preferredWidth: 150
                                                        from: 60
                                                        to: 3600
                                                        stepSize: 60
                                                        value: preferences.workingClaudeRefreshInterval
                                                        textFromValue: function(value) { return i18n("%1 s", value) }
                                                        valueFromText: function(text) { return Number(text.replace(/\D/g, "")) }
                                                        onValueModified: preferences.workingClaudeRefreshInterval = value
                                                    }
                                                }

                                                QQC2.Label {
                                                    text: i18n("Uses a dedicated interval to avoid exhausting its API.")
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeSecondary
                                                }
                                            }
                                        }

                                        PreferenceCard {
                                            title: i18n("Compact panel")
                                            subtitle: i18n("Which providers and quotas appear in the bar. The popup always shows everything.")

                                            ColumnLayout {
                                                width: parent.width
                                                spacing: 13

                                                RowLayout {
                                                    Layout.fillWidth: true

                                                    QQC2.Label {
                                                        Layout.fillWidth: true
                                                        text: i18n("Show all returned providers")
                                                        color: "#e9ebf2"
                                                        font.family: appletRoot ? appletRoot.designFont : ""
                                                        font.pixelSize: preferences.fontSizeBody
                                                    }

                                                    QQC2.Switch {
                                                        checked: preferences.showAllProviders
                                                        onToggled: preferences.workingCompactProviderOrder = checked
                                                            ? "" : "codex,claude,grok,antigravity"
                                                    }
                                                }

                                                QQC2.Label {
                                                    text: i18n("PROVIDERS")
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeMicro
                                                    font.weight: Font.DemiBold
                                                }

                                                Flow {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    Repeater {
                                                        model: preferences.compactProviderChipIds

                                                        delegate: Item {
                                                            id: providerChip
                                                            required property string modelData
                                                            width: chipContent.width
                                                            height: chipContent.height
                                                            z: dragHandler.active ? 1000 : 0

                                                            DropArea {
                                                                anchors.fill: parent
                                                                enabled: !preferences.showAllProviders
                                                                onEntered: function(drag) {
                                                                    preferences.moveProvider(drag.source.modelData,
                                                                        providerChip.modelData)
                                                                }
                                                            }

                                                            Rectangle {
                                                                id: chipContent
                                                                width: chipRow.implicitWidth + 22
                                                                height: 32
                                                                radius: 16
                                                                color: preferences.showAllProviders ? "#171920"
                                                                    : preferences.isProviderActive(providerChip.modelData) ? "#29244e" : "#1b1e28"
                                                                border.color: preferences.showAllProviders ? "#22252f"
                                                                    : preferences.isProviderActive(providerChip.modelData) ? "#6e5aff" : "#303440"
                                                                border.width: 1
                                                                opacity: preferences.showAllProviders ? 0.52 : 1
                                                                z: dragHandler.active ? 1 : 0

                                                                Drag.active: dragHandler.active
                                                                Drag.source: providerChip
                                                                Drag.hotSpot.x: width / 2
                                                                Drag.hotSpot.y: height / 2
                                                                Drag.onActiveChanged: {
                                                                    if (!Drag.active) {
                                                                        chipContent.x = 0
                                                                        chipContent.y = 0
                                                                    }
                                                                }

                                                                Row {
                                                                    id: chipRow
                                                                    anchors.centerIn: parent
                                                                    spacing: 6

                                                                    Image {
                                                                        width: 15
                                                                        height: 15
                                                                        anchors.verticalCenter: parent.verticalCenter
                                                                        source: preferences.providerIcon(providerChip.modelData)
                                                                        fillMode: Image.PreserveAspectFit
                                                                    }

                                                                    QQC2.Label {
                                                                        text: preferences.providerLabel(providerChip.modelData)
                                                                        anchors.verticalCenter: parent.verticalCenter
                                                                        color: preferences.isProviderActive(providerChip.modelData)
                                                                            ? "#e9ebf2" : "#8b91a3"
                                                                        font.family: appletRoot ? appletRoot.designFont : ""
                                                                        font.pixelSize: preferences.fontSizeBody
                                                                    }
                                                                }

                                                                TapHandler {
                                                                    enabled: !preferences.showAllProviders
                                                                    onTapped: preferences.toggleProvider(providerChip.modelData)
                                                                }

                                                                DragHandler {
                                                                    id: dragHandler
                                                                    enabled: !preferences.showAllProviders
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                QQC2.Label {
                                                    Layout.alignment: Qt.AlignRight
                                                    text: i18n("%1 active · %2 disabled",
                                                        preferences.showAllProviders ? preferences.providerIds.length
                                                        : preferences.activeKnownProviderIds.length,
                                                        preferences.showAllProviders ? 0
                                                        : preferences.providerIds.length - preferences.activeKnownProviderIds.length)
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeSecondary
                                                }

                                                PreferenceField {
                                                    label: i18n("Quotas")

                                                    QQC2.TextField {
                                                        objectName: "quotaSelectionField"
                                                        Layout.fillWidth: true
                                                        text: preferences.workingCompactQuotaSelection
                                                        placeholderText: "primary,weekly"
                                                        selectByMouse: true
                                                        onTextEdited: preferences.workingCompactQuotaSelection = text
                                                    }
                                                }

                                                QQC2.Label {
                                                    Layout.fillWidth: true
                                                    text: i18n("Comma-separated quota keys, default primary,weekly. Use provider.key for a single provider, e.g. antigravity.tertiary. Leave empty to show provider icons only. The popup always shows every quota.")
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeSecondary
                                                    wrapMode: Text.WordWrap
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 4

                                                    QQC2.CheckBox {
                                                        objectName: "showProviderCheck"
                                                        text: i18n("Show provider label")
                                                        checked: preferences.workingShowProviderInPanel
                                                        onToggled: preferences.workingShowProviderInPanel = checked
                                                    }

                                                    QQC2.CheckBox {
                                                        objectName: "showUsedCheck"
                                                        text: i18n("Show used percent")
                                                        checked: preferences.workingShowUsedPercentInPanel
                                                        onToggled: preferences.workingShowUsedPercentInPanel = checked
                                                    }

                                                    QQC2.CheckBox {
                                                        objectName: "showCreditsCheck"
                                                        text: i18n("Show credits")
                                                        checked: preferences.workingShowCreditsInPanel
                                                        onToggled: preferences.workingShowCreditsInPanel = checked
                                                    }
                                                }
                                            }
                                        }

                                        PreferenceCard {
                                            title: i18n("Popup")
                                            subtitle: i18n("What the expanded view shows.")

                                            ColumnLayout {
                                                width: parent.width
                                                spacing: 4

                                                QQC2.CheckBox {
                                                    objectName: "showEmailCheck"
                                                    text: i18n("Show account email")
                                                    checked: preferences.workingShowEmailInWidget
                                                    onToggled: preferences.workingShowEmailInWidget = checked
                                                }

                                                QQC2.CheckBox {
                                                    objectName: "showCostCheck"
                                                    text: i18n("Show cost summary")
                                                    checked: preferences.workingShowCostSummary
                                                    onToggled: preferences.workingShowCostSummary = checked
                                                }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 18

                                        QQC2.Label {
                                            text: i18n("Keyboard shortcuts")
                                            color: "#e9ebf2"
                                            font.family: appletRoot ? appletRoot.designFont : ""
                                            font.pixelSize: preferences.fontSizeTitle
                                            font.bold: true
                                        }

                                        PreferenceCard {
                                            title: i18n("Open or close the popup")
                                            subtitle: i18n("This is the widget activation shortcut managed by Plasma.")

                                            RowLayout {
                                                width: parent.width
                                                spacing: 12

                                                KeySequenceItem {
                                                    id: shortcutCapture
                                                    Layout.fillWidth: true
                                                    keySequence: preferences.workingShortcut
                                                    patterns: ShortcutPattern.Modifier | ShortcutPattern.ModifierAndKey
                                                    onKeySequenceModified: preferences.workingShortcut = keySequence
                                                }

                                                QQC2.Button {
                                                    text: i18n("Clear")
                                                    enabled: preferences.workingShortcut.length > 0
                                                    onClicked: preferences.workingShortcut = ""
                                                }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 18

                                        QQC2.Label {
                                            text: i18n("About")
                                            color: "#e9ebf2"
                                            font.family: appletRoot ? appletRoot.designFont : ""
                                            font.pixelSize: preferences.fontSizeTitle
                                            font.bold: true
                                        }

                                        PreferenceCard {
                                            ColumnLayout {
                                                width: parent.width
                                                spacing: 12

                                                Image {
                                                    Layout.preferredWidth: 64
                                                    Layout.preferredHeight: 64
                                                    source: Qt.resolvedUrl("../icons/kodexbar.svg")
                                                    fillMode: Image.PreserveAspectFit
                                                }

                                                QQC2.Label {
                                                    text: i18n("KodexBar Suite")
                                                    color: "#e9ebf2"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: 22
                                                    font.bold: true
                                                }

                                                QQC2.Label {
                                                    text: i18n("Version %1", Plasmoid.metaData.version || "0.9.0")
                                                    color: "#8b91a3"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeSecondary
                                                }

                                                QQC2.Label {
                                                    text: i18n("Built on the upstream CodexBar CLI.")
                                                    color: "#c3c7d2"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeBody
                                                }

                                                QQC2.Label {
                                                    text: i18n("Licensed under the MIT License.")
                                                    color: "#c3c7d2"
                                                    font.family: appletRoot ? appletRoot.designFont : ""
                                                    font.pixelSize: preferences.fontSizeBody
                                                }

                                                QQC2.TextField {
                                                    Layout.fillWidth: true
                                                    text: "https://github.com/Karasowl/KodexBar"
                                                    readOnly: true
                                                    selectByMouse: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 66
                        color: "#0f1015"
                        border.color: "#22252f"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 28
                            anchors.rightMargin: 28
                            spacing: 10

                            QQC2.Button {
                                text: i18n("Restore defaults")
                                onClicked: preferences.restoreDefaults()
                            }

                            Item { Layout.fillWidth: true }

                            QQC2.Button {
                                text: i18n("Cancel")
                                onClicked: preferences.cancel()
                            }

                            QQC2.Button {
                                text: i18n("Apply")
                                enabled: preferences.dirty
                                onClicked: preferences.save()
                            }

                            QQC2.Button {
                                text: i18n("Accept")
                                onClicked: {
                                    if (preferences.dirty) {
                                        preferences.save()
                                    }
                                    preferences.visible = false
                                }

                                contentItem: QQC2.Label {
                                    text: parent.text
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.family: appletRoot ? appletRoot.designFont : ""
                                    font.weight: Font.DemiBold
                                }

                                background: Rectangle {
                                    radius: 8
                                    color: parent.enabled ? "#6e5aff" : "#413b71"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component PreferenceCard: Rectangle {
        property string title: ""
        property string subtitle: ""
        default property alias content: body.data

        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 36
        radius: 14
        color: "#14161d"
        border.color: "#22252f"
        border.width: 1

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            ColumnLayout {
                visible: title.length > 0 || subtitle.length > 0
                Layout.fillWidth: true
                spacing: 3

                QQC2.Label {
                    visible: title.length > 0
                    text: title
                    color: "#e9ebf2"
                    font.family: appletRoot ? appletRoot.designFont : ""
                    font.pixelSize: preferences.fontSizeCardTitle
                    font.weight: Font.DemiBold
                }

                QQC2.Label {
                    visible: subtitle.length > 0
                    text: subtitle
                    color: "#8b91a3"
                    font.family: appletRoot ? appletRoot.designFont : ""
                    font.pixelSize: preferences.fontSizeSecondary
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            ColumnLayout {
                id: body
                Layout.fillWidth: true
                spacing: 0
            }
        }
    }

    component PreferenceField: RowLayout {
        property string label: ""
        default property alias field: fieldContainer.data

        Layout.fillWidth: true
        spacing: 14

        QQC2.Label {
            Layout.preferredWidth: 138
            text: label
            color: "#c3c7d2"
            font.family: appletRoot ? appletRoot.designFont : ""
            font.pixelSize: preferences.fontSizeBody
        }

        RowLayout {
            id: fieldContainer
            Layout.fillWidth: true
        }
    }
}
