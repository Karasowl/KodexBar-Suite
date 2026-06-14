import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    property var entries: []
    property string errorMessage: ""
    property string errorDetail: ""
    property string generatedAt: ""
    property bool loading: false
    property string codexbarCommand: Plasmoid.configuration.codexbarCommand || "codexbar"
    property string selectedProvider: Plasmoid.configuration.provider || "detect"
    property string selectedSource: Plasmoid.configuration.source || "detect"
    property string activeProvider: selectedProvider
    property string activeSource: selectedSource
    property var pendingCandidates: []
    property var failedCandidates: []
    property bool showCreditsInPanel: Plasmoid.configuration.showCreditsInPanel === undefined ? true : Plasmoid.configuration.showCreditsInPanel
    property int refreshSeconds: Math.max(10, Plasmoid.configuration.refreshInterval || 60)

    preferredRepresentation: compactRepresentation
    toolTipMainText: "KodexBar"
    toolTipSubText: errorMessage.length > 0 ? errorMessage : panelText()

    function panelText() {
        if (entries.length === 0) {
            return loading ? i18n("Loading") : i18n("No data")
        }
        var first = null
        for (var i = 0; i < entries.length; i++) {
            if (!entries[i].errorMessage && entries[i].rows.length > 0) {
                first = entries[i]
                break
            }
        }
        if (first === null) {
            first = entries[0]
        }
        var parts = [first.name || "Codex"]
        if (first.errorMessage) {
            parts.push(i18n("Error"))
            return parts.join(" ")
        }
        if (first.primaryPercentLeft !== null && first.primaryPercentLeft !== undefined) {
            parts.push(Math.round(first.primaryPercentLeft) + "%")
        } else if (first.creditsRemaining !== null && first.creditsRemaining !== undefined && showCreditsInPanel) {
            parts.push(formatNumber(first.creditsRemaining))
        }
        return parts.join(" ")
    }

    function formatNumber(value) {
        if (value === null || value === undefined || isNaN(value)) {
            return ""
        }
        if (Math.abs(value) >= 1000) {
            return Number(value).toLocaleString(Qt.locale(), "f", 0)
        }
        return Number(value).toLocaleString(Qt.locale(), "f", 1)
    }

    function formatPercent(value) {
        if (value === null || value === undefined || isNaN(value)) {
            return i18n("Unavailable")
        }
        return i18n("%1% left", Math.round(value))
    }

    function commandLine(provider, source) {
        return shellQuote(codexbarCommand)
            + " usage --format json --json-only --provider " + shellQuote(provider)
            + " --source " + shellQuote(source)
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function refresh() {
        loading = true
        errorMessage = ""
        errorDetail = ""
        failedCandidates = []
        pendingCandidates = candidateList()
        executable.connectedSources = []
        tryNextCandidate()
    }

    function candidateList() {
        var provider = selectedProvider || "detect"
        var source = selectedSource || "detect"
        var sources = source === "detect" || source === "auto" ? ["cli", "oauth", "api", "auto"] : [source]
        var result = []

        if (provider !== "detect" && provider !== "all") {
            for (var i = 0; i < sources.length; i++) {
                result.push({ provider: provider, source: sources[i] })
            }
            return result
        }

        if (provider === "all" && source !== "detect") {
            return [{ provider: "all", source: source }]
        }

        return [
            { provider: "codex", source: "cli" },
            { provider: "codex", source: "oauth" },
            { provider: "codex", source: "api" },
            { provider: "claude", source: "cli" },
            { provider: "claude", source: "oauth" },
            { provider: "claude", source: "api" },
            { provider: "openai", source: "api" },
            { provider: "gemini", source: "api" },
            { provider: "copilot", source: "api" },
            { provider: "kilo", source: "cli" },
            { provider: "kilo", source: "api" },
            { provider: "openrouter", source: "api" },
            { provider: "ollama", source: "api" }
        ]
    }

    function tryNextCandidate() {
        if (pendingCandidates.length === 0) {
            loading = false
            entries = failedCandidates
            generatedAt = new Date().toLocaleString(Qt.locale(), Locale.ShortFormat)
            if (entries.length === 0) {
                errorMessage = i18n("No usable CodexBar provider found")
                errorDetail = i18n("Configure a Linux-capable provider or choose a specific provider/source.")
            }
            return
        }

        var candidate = pendingCandidates.shift()
        activeProvider = candidate.provider
        activeSource = candidate.source
        executable.connectedSources = []
        executable.connectSource(commandLine(activeProvider, activeSource))
    }

    function hasUsableEntries(normalized) {
        for (var i = 0; i < normalized.length; i++) {
            if (!normalized[i].errorMessage
                    && ((normalized[i].rows && normalized[i].rows.length > 0)
                        || normalized[i].creditsRemaining !== null
                        || normalized[i].codeReviewRemainingPercent !== null)) {
                return true
            }
        }
        return false
    }

    function appendFailedEntries(normalized) {
        var existing = failedCandidates
        for (var i = 0; i < normalized.length; i++) {
            if (normalized[i].errorMessage) {
                existing.push(normalized[i])
            }
        }
        failedCandidates = existing
    }

    function parsePayload(text) {
        if (!text || text.length === 0) {
            return {
                ok: false,
                error: i18n("No output from CodexBar CLI"),
                detail: ""
            }
        }
        try {
            var raw = JSON.parse(text)
            var rawEntries = raw instanceof Array ? raw : [raw]
            var normalized = []
            for (var i = 0; i < rawEntries.length; i++) {
                if (rawEntries[i] && typeof rawEntries[i] === "object") {
                    normalized.push(normalizeEntry(rawEntries[i]))
                }
            }
            return {
                ok: true,
                entries: normalized,
                usable: hasUsableEntries(normalized)
            }
        } catch (error) {
            return {
                ok: false,
                error: i18n("Invalid CodexBar CLI response"),
                detail: String(error)
            }
        }
    }

    function providerName(raw) {
        var key = String(raw || "").toLowerCase()
        var names = {
            "codex": "Codex",
            "claude": "Claude",
            "openai": "OpenAI API",
            "azureopenai": "Azure OpenAI",
            "opencode": "OpenCode",
            "opencodego": "OpenCode Go",
            "alibabatokenplan": "Alibaba Token Plan",
            "vertexai": "Vertex AI",
            "kimik2": "Kimi K2",
            "t3chat": "T3 Chat",
            "deepseek": "DeepSeek",
            "codebuff": "Codebuff",
            "commandcode": "Command Code",
            "stepfun": "StepFun",
            "openrouter": "OpenRouter",
            "deepgram": "Deepgram",
            "llmproxy": "LLM Proxy",
            "copilot": "Copilot",
            "gemini": "Gemini"
        }
        return names[key] || (raw ? String(raw).charAt(0).toUpperCase() + String(raw).slice(1) : i18n("Provider"))
    }

    function percentLeft(window) {
        if (!window || typeof window !== "object") {
            return null
        }
        if (typeof window.remainingPercent === "number") {
            return Math.max(0, Math.min(100, window.remainingPercent))
        }
        if (typeof window.usedPercent === "number") {
            return Math.max(0, Math.min(100, 100 - window.usedPercent))
        }
        return null
    }

    function resetAt(window) {
        return window && typeof window === "object" ? window.resetsAt : null
    }

    function normalizeEntry(entry) {
        var usage = entry.usage && typeof entry.usage === "object" ? entry.usage : {}
        var identity = usage.identity && typeof usage.identity === "object" ? usage.identity : {}
        var credits = entry.credits && typeof entry.credits === "object" ? entry.credits : null
        var dashboard = entry.openaiDashboard && typeof entry.openaiDashboard === "object" ? entry.openaiDashboard : {}
        var error = entry.error && typeof entry.error === "object" ? entry.error : null
        var primary = usage.primary
        var secondary = usage.secondary
        var tertiary = usage.tertiary
        var rows = []
        var windows = [
            { title: i18n("Session"), data: primary },
            { title: i18n("Weekly"), data: secondary },
            { title: i18n("Extra"), data: tertiary }
        ]
        for (var i = 0; i < windows.length; i++) {
            var left = percentLeft(windows[i].data)
            if (left !== null) {
                rows.push({ title: windows[i].title, percentLeft: left, resetsAt: resetAt(windows[i].data) })
            }
        }
        return {
            provider: entry.provider,
            name: providerName(entry.provider),
            version: entry.version,
            source: entry.source,
            account: entry.account || usage.accountEmail || identity.accountEmail || "",
            plan: usage.loginMethod || identity.loginMethod || "",
            primaryPercentLeft: percentLeft(primary),
            primaryResetsAt: resetAt(primary),
            secondaryPercentLeft: percentLeft(secondary),
            secondaryResetsAt: resetAt(secondary),
            creditsRemaining: credits ? credits.remaining : null,
            codeReviewRemainingPercent: typeof dashboard.codeReviewRemainingPercent === "number" ? dashboard.codeReviewRemainingPercent : null,
            rows: rows,
            updatedAt: usage.updatedAt || entry.updatedAt || "",
            status: entry.status,
            errorMessage: error ? (error.message || i18n("Provider returned an error")) : "",
            errorKind: error ? (error.kind || "") : ""
        }
    }

    function barColor(value) {
        if (value === null || value === undefined || isNaN(value)) {
            return Kirigami.Theme.disabledTextColor
        }
        if (value < 15) {
            return Kirigami.Theme.negativeTextColor
        }
        if (value < 35) {
            return Kirigami.Theme.neutralTextColor
        }
        return Kirigami.Theme.positiveTextColor
    }

    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: Qt.resolvedUrl("../icons/codex.svg")
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.Label {
                text: root.panelText()
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.maximumWidth: Kirigami.Units.gridUnit * 8
            }
        }
    }

    fullRepresentation: Item {
        id: full
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    text: "KodexBar"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    display: QQC2.AbstractButton.IconOnly
                    enabled: !root.loading
                    text: i18n("Refresh")
                    onClicked: root.refresh()
                }
            }

            PlasmaComponents.Label {
                text: root.loading
                    ? i18n("Trying %1 / %2", root.activeProvider, root.activeSource)
                    : i18n("Provider: %1    Source: %2", root.activeProvider, root.activeSource)
                color: Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: root.errorMessage.length > 0
                text: root.errorDetail.length > 0 ? root.errorMessage + "\n" + root.errorDetail : root.errorMessage
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: root.errorMessage.length === 0 && root.entries.length === 0
                text: root.loading ? i18n("Loading usage...") : i18n("No usage data available")
                color: Kirigami.Theme.disabledTextColor
                Layout.fillWidth: true
            }

            ListView {
                id: list
                visible: root.entries.length > 0
                model: root.entries
                clip: true
                spacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true
                Layout.fillHeight: true

                delegate: ColumnLayout {
                    width: ListView.view.width
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true

                        PlasmaComponents.Label {
                            text: modelData.name || modelData.provider
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        PlasmaComponents.Label {
                            text: modelData.source || ""
                            color: Kirigami.Theme.disabledTextColor
                            visible: text.length > 0
                        }
                    }

                    Repeater {
                        model: modelData.rows || []

                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                PlasmaComponents.Label {
                                    text: modelData.title
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents.Label {
                                    text: root.formatPercent(modelData.percentLeft)
                                    color: root.barColor(modelData.percentLeft)
                                }
                            }

                            QQC2.ProgressBar {
                                from: 0
                                to: 100
                                value: modelData.percentLeft || 0
                                Layout.fillWidth: true
                            }
                        }
                    }

                    PlasmaComponents.Label {
                        visible: modelData.errorMessage && modelData.errorMessage.length > 0
                        text: modelData.errorKind && modelData.errorKind.length > 0
                            ? modelData.errorKind + ": " + modelData.errorMessage
                            : modelData.errorMessage
                        color: Kirigami.Theme.negativeTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: modelData.creditsRemaining !== null && modelData.creditsRemaining !== undefined

                        PlasmaComponents.Label {
                            text: i18n("Credits")
                            Layout.fillWidth: true
                        }

                        PlasmaComponents.Label {
                            text: root.formatNumber(modelData.creditsRemaining)
                            font.weight: Font.DemiBold
                        }
                    }

                    PlasmaComponents.Label {
                        visible: modelData.account
                        text: modelData.account || ""
                        color: Kirigami.Theme.disabledTextColor
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                    }
                }
            }

            PlasmaComponents.Label {
                text: root.generatedAt.length > 0 ? i18n("Updated %1", root.generatedAt) : ""
                color: Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            if (data["exit code"] && data["exit code"] !== 0 && !(data.stdout || "").length) {
                var errorEntry = root.normalizeEntry({
                    provider: root.activeProvider,
                    source: root.activeSource,
                    error: {
                        kind: "runtime",
                        message: data.stderr || i18n("Exit code %1", data["exit code"])
                    }
                })
                root.appendFailedEntries([errorEntry])
                root.tryNextCandidate()
                return
            }
            var result = root.parsePayload(data.stdout || "")
            if (!result.ok) {
                var parseErrorEntry = root.normalizeEntry({
                    provider: root.activeProvider,
                    source: root.activeSource,
                    error: { kind: "runtime", message: result.error + (result.detail ? ": " + result.detail : "") }
                })
                root.appendFailedEntries([parseErrorEntry])
                root.tryNextCandidate()
                return
            }
            if (!result.usable && root.pendingCandidates.length > 0) {
                root.appendFailedEntries(result.entries)
                root.tryNextCandidate()
                return
            }
            root.loading = false
            root.errorMessage = ""
            root.errorDetail = ""
            root.generatedAt = new Date().toLocaleString(Qt.locale(), Locale.ShortFormat)
            root.entries = result.entries
        }
    }

    Timer {
        id: refreshTimer
        interval: root.refreshSeconds * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    onRefreshSecondsChanged: {
        refreshTimer.restart()
        refresh()
    }

    onCodexbarCommandChanged: refresh()
    onSelectedProviderChanged: refresh()
    onSelectedSourceChanged: refresh()
    onShowCreditsInPanelChanged: panelText()
}
