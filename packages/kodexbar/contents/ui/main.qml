import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/providerLogic.js" as ProviderLogic

PlasmoidItem {
    id: root

    FontLoader {
        id: manropeFont
        source: Qt.resolvedUrl("../fonts/Manrope-Variable.ttf")
    }

    property var entries: []
    property string errorMessage: ""
    property string errorDetail: ""
    property bool engineNotInstalled: false
    readonly property string engineInstallCommand: "paru -S kodexbar-suite"
    readonly property string engineRepoUrl: "https://github.com/Karasowl/KodexBar-Suite"
    property string generatedAt: ""
    property bool loading: false
    property bool costLoading: false
    property string costErrorMessage: ""
    property var costSummaries: ({})
    property string configuredCodexbarCommand: String(Plasmoid.configuration.codexbarCommand || "")
    property string codexbarCommand: configuredCodexbarCommand.trim() || "codexbar"
    property string aiControlCommand: Plasmoid.configuration.aiControlCommand || "ai"
    property string localAiCommand: Plasmoid.configuration.localAiCommand || "local-ai"
    property string aiControlError: ""
    property string localModelsError: ""
    property bool localModelsLoading: false
    property var localModels: []
    property var localRuntimes: []
    property var localModelHistory: ({})
    property string selectedPopupTab: "provider"
    property int localModelsRefreshSeconds: Math.max(5, Math.min(3600,
        Plasmoid.configuration.localModelsRefreshInterval || 15))
    property string selectedSource: Plasmoid.configuration.sourceDefault || Plasmoid.configuration.source || "detect"
    property string selectedEntryKey: ""
    property string activeProvider: ""
    property string activeSource: selectedSource
    property string activeCommand: codexbarCommand
    property string activeFallbackCommand: ""
    property var pendingCandidates: []
    property var pendingCostCommands: []
    property var lastGoodEntries: []
    property bool activeQueryReplacesAll: false
    property bool activeStartupRetry: false
    property bool initialUsageSeedPending: true
    property bool startupRetryWindowOpen: true
    property bool startupRetryPending: false
    property var startupRetryAttemptedProviders: ({})
    property int fastRefreshCyclesSinceSeed: 0
    property double lastSuccessfulSeedAt: 0
    property bool showCreditsInPanel: Plasmoid.configuration.showCreditsInPanel === undefined ? false : Plasmoid.configuration.showCreditsInPanel
    property bool showUsedPercentInPanel: Plasmoid.configuration.showUsedPercentInPanel === undefined ? true : Plasmoid.configuration.showUsedPercentInPanel
    property bool showProviderInPanel: Plasmoid.configuration.showProviderInPanel === undefined ? true : Plasmoid.configuration.showProviderInPanel
    property bool showEmailInWidget: Plasmoid.configuration.showEmailInWidget === undefined ? false : Plasmoid.configuration.showEmailInWidget
    property bool includeStatus: Plasmoid.configuration.includeStatus === undefined ? false : Plasmoid.configuration.includeStatus
    property bool showCostSummary: Plasmoid.configuration.showCostSummary === undefined ? true : Plasmoid.configuration.showCostSummary
    readonly property string defaultCompactProviderOrder: "codex,claude,grok,antigravity"
    property string compactProviderOrder: Plasmoid.configuration.compactProviderOrder === undefined
        ? defaultCompactProviderOrder
        : Plasmoid.configuration.compactProviderOrder
    property string compactQuotaSelection: Plasmoid.configuration.compactQuotaSelection === undefined
        ? "primary,weekly"
        : Plasmoid.configuration.compactQuotaSelection
    property int refreshSeconds: Math.max(10, Plasmoid.configuration.refreshInterval || 60)
    property int claudeRefreshSeconds: Math.max(60, Math.min(3600,
        Plasmoid.configuration.claudeRefreshInterval || 300))
    readonly property string designFont: manropeFont.status === FontLoader.Ready && manropeFont.name.length > 0
        ? manropeFont.name
        : Kirigami.Theme.defaultFont.family
    readonly property color cardColor: "#14161d"
    readonly property color surfaceColor: "#0f1116"
    readonly property color raisedColor: "#1b1e28"
    readonly property color lineColor: "#262a35"
    readonly property color textColor: "#e9ebf2"
    readonly property color mutedColor: "#8b91a3"
    readonly property color quietColor: "#6b7080"
    readonly property color accentColor: "#6e5aff"
    readonly property color goodColor: "#45d483"
    readonly property color warningColor: "#f0b429"
    readonly property color errorColor: "#f76b6b"
    readonly property var popupState: ProviderLogic.activeEntryData(entries, selectedEntryKey)
    readonly property var popupEntries: popupState.entries || []
    readonly property var activeEntry: popupState.entry || ({})
    readonly property var popupTabs: {
        var tabs = []
        for (var i = 0; i < popupEntries.length; i++) {
            tabs.push({ kind: "provider", entry: popupEntries[i], id: popupEntries[i].selectionKey,
                tabLabel: popupEntries[i].tabLabel, provider: popupEntries[i].provider })
        }
        tabs.push({ kind: "local", id: "local", tabLabel: i18n("Local models"), icon: "cpu" })
        return tabs
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Configure KodexBar Suite…")
            icon.name: "configure"
            onTriggered: root.openPreferences()
        },
        PlasmaCore.Action {
            text: i18n("Open AI CLI Control")
            icon.name: "applications-development"
            onTriggered: root.launchAiControl([])
        },
        PlasmaCore.Action {
            text: i18n("Update all AI CLIs")
            icon.name: "view-refresh"
            onTriggered: root.launchAiControl(["--update", "all"])
        }
    ]

    PreferencesWindow {
        id: preferencesWindow
        appletRoot: root
    }

    preferredRepresentation: compactRepresentation
    toolTipMainText: "KodexBar Suite"
    toolTipSubText: {
        if (aiControlError.length > 0) {
            return i18n("AI CLI Control: %1", aiControlError)
        }
        if (engineNotInstalled) {
            return i18n("Data engine not installed")
        }
        if (errorMessage.length > 0) {
            return errorMessage
        }
        if (entries.length > 0 && entries[0].signedOut) {
            return entries[0].errorMessage
        }
        return panelText()
    }

    function compactResult() {
        return compactResultForOrder(compactProviderOrder)
    }

    function compactResultForOrder(providerOrder, overrides) {
        var values = overrides || {}
        return ProviderLogic.composeCompactBlocks(entries, {
            providerOrder: providerOrder,
            quotaSelection: values.quotaSelection === undefined ? compactQuotaSelection : values.quotaSelection,
            showProvider: values.showProvider === undefined ? showProviderInPanel : values.showProvider,
            showUsed: values.showUsed === undefined ? showUsedPercentInPanel : values.showUsed,
            showCredits: values.showCredits === undefined ? showCreditsInPanel : values.showCredits,
            maximumCharacters: 24,
            noSelectionText: i18n("No selection"),
            noFieldsText: i18n("No compact fields")
        })
    }

    function panelText() {
        if (entries.length === 0) {
            return loading ? i18n("Loading") : i18n("No data")
        }
        return compactResult().text
    }

    function openPreferences() {
        preferencesWindow.openPreferences()
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

    function formatCurrency(value, currencyCode) {
        if (value === null || value === undefined || isNaN(value)) {
            return ""
        }
        var prefix = currencyCode === "USD" ? "$" : ((currencyCode || "") + " ")
        return prefix + Number(value).toLocaleString(Qt.locale(), "f", 2)
    }

    function formatTokenCount(value) {
        if (value === null || value === undefined || isNaN(value)) {
            return ""
        }
        var absolute = Math.abs(Number(value))
        if (absolute >= 1000000000) {
            return Number(value / 1000000000).toLocaleString(Qt.locale(), "f", absolute >= 10000000000 ? 0 : 1) + "B"
        }
        if (absolute >= 1000000) {
            return Number(value / 1000000).toLocaleString(Qt.locale(), "f", absolute >= 10000000 ? 0 : 1) + "M"
        }
        if (absolute >= 1000) {
            return Number(value / 1000).toLocaleString(Qt.locale(), "f", absolute >= 10000 ? 0 : 1) + "K"
        }
        return Number(value).toLocaleString(Qt.locale(), "f", 0)
    }

    function localDayKey(date) {
        function pad(value) {
            return value < 10 ? "0" + value : String(value)
        }
        return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
    }

    function formatCredits(value) {
        if (value === null || value === undefined || isNaN(value)) {
            return ""
        }
        var formatted = Number(value).toLocaleString(Qt.locale(), "f", 2)
        var decimalPoint = Qt.locale().decimalPoint || "."
        while (formatted.indexOf(decimalPoint) !== -1 && formatted.endsWith("0")) {
            formatted = formatted.slice(0, -1)
        }
        if (formatted.endsWith(decimalPoint)) {
            formatted = formatted.slice(0, -decimalPoint.length)
        }
        return formatted
    }

    function usedPercent(percentLeft) {
        if (percentLeft === null || percentLeft === undefined || isNaN(percentLeft)) {
            return null
        }
        return Math.max(0, Math.min(100, 100 - percentLeft))
    }

    function formatUsedPercent(percentLeft, usageKnown, showRemaining, precise) {
        if (usageKnown === false) {
            return i18n("Reset only")
        }
        var used = usedPercent(percentLeft)
        if (used === null) {
            return i18n("Unavailable")
        }
        var displayUsed = precise === true && Math.abs(used - Math.round(used)) >= 0.005
            ? Number(used).toLocaleString(Qt.locale(), "f", 2)
            : String(Math.round(used))
        var usedText = i18n("%1% used", displayUsed)
        if (showRemaining === true) {
            var left = Math.max(0, Math.min(100, Math.round(100 - used)))
            return usedText + " · " + i18n("%1% left", left)
        }
        return usedText
    }

    // Shared color for bar segments and legend dots (single source in providerLogic).
    function segmentColor(title, index) {
        return ProviderLogic.segmentBarColor(title, index)
    }

    function formatResetTime(value) {
        if (!value) {
            return ""
        }
        var reset = new Date(value)
        var timestamp = reset.getTime()
        if (isNaN(timestamp)) {
            return ""
        }
        var diff = Math.max(0, timestamp - Date.now())
        var minutes = Math.round(diff / 60000)
        if (minutes < 1) {
            return i18n("Resets now")
        }
        var hours = Math.floor(minutes / 60)
        var days = Math.floor(hours / 24)
        if (days > 0) {
            return i18n("Resets in %1d %2h", days, hours % 24)
        }
        if (hours > 0) {
            return i18n("Resets in %1h %2m", hours, minutes % 60)
        }
        return i18n("Resets in %1m", minutes)
    }

    function formatUpdatedTime(value) {
        var raw = value || generatedAt
        if (!raw) {
            return ""
        }
        var date = new Date(raw)
        if (!isNaN(date.getTime())) {
            return date.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
        }
        return String(raw)
    }

    function formatResetTimes(values) {
        var dates = Array.isArray(values) ? values : []
        var formatted = []
        for (var i = 0; i < dates.length; i++) {
            var value = formatResetTime(dates[i])
            if (value.length > 0) {
                formatted.push(value.toLowerCase())
            }
        }
        return formatted.join(" · ")
    }

    function activeStatusColor(entry) {
        if (!entry || !entry.provider) {
            return loading ? warningColor : quietColor
        }
        if (entry.errorMessage) {
            return errorColor
        }
        if (entry.isCached === true) {
            return quietColor
        }
        if (entry.statusIndicator === "major" || entry.statusIndicator === "critical") {
            return errorColor
        }
        if (entry.statusIndicator === "minor" || entry.statusIndicator === "maintenance") {
            return warningColor
        }
        if (!ProviderLogic.entryHasReportedUsage(entry)) {
            return quietColor
        }
        return goodColor
    }

    function metricAccent(percentLeft, usageKnown) {
        if (usageKnown === false || percentLeft === null || percentLeft === undefined || isNaN(percentLeft)) {
            return quietColor
        }
        var used = usedPercent(percentLeft)
        if (used >= 80) {
            return errorColor
        }
        if (used >= 50) {
            return warningColor
        }
        return goodColor
    }

    function activeIsEmpty(entry) {
        if (!entry || !entry.provider || entry.errorMessage) {
            return false
        }
        // Credits count as present only when numeric and > 0 (same gate as the Credits block).
        // A zero balance must not suppress the "No usage reported" empty state.
        var hasPositiveCredits = typeof entry.creditsRemaining === "number"
            && !isNaN(entry.creditsRemaining)
            && entry.creditsRemaining > 0
        return (!entry.rows || entry.rows.length === 0)
            && !hasPositiveCredits
            && (!entry.bankedResetCount || entry.bankedResetCount <= 0)
            && (!entry.costSummary)
            && (!entry.dashboardSummary || entry.dashboardSummary.length === 0)
    }

    function resetTimeFromDescription(value) {
        if (!value) {
            return null
        }

        var text = String(value).trim()
        var direct = new Date(text)
        if (!isNaN(direct.getTime())) {
            return direct.toISOString()
        }

        var relative = /(\d+)\s*([dhm])\b/ig
        var match = null
        var minutes = 0
        while ((match = relative.exec(text)) !== null) {
            var amount = parseInt(match[1], 10)
            var unit = match[2].toLowerCase()
            if (unit === "d") {
                minutes += amount * 24 * 60
            } else if (unit === "h") {
                minutes += amount * 60
            } else {
                minutes += amount
            }
        }
        if (minutes > 0) {
            return new Date(Date.now() + minutes * 60000).toISOString()
        }

        var clock = text.match(/(?:resets?\s*)?(\d{1,2}):(\d{2})\s*(AM|PM)?/i)
        if (!clock) {
            return null
        }

        var hour = parseInt(clock[1], 10)
        var minute = parseInt(clock[2], 10)
        var meridiem = clock[3] ? clock[3].toUpperCase() : ""
        if (meridiem === "PM" && hour < 12) {
            hour += 12
        } else if (meridiem === "AM" && hour === 12) {
            hour = 0
        }

        var candidate = new Date()
        candidate.setHours(hour, minute, 0, 0)
        if (candidate.getTime() < Date.now()) {
            candidate.setDate(candidate.getDate() + 1)
        }
        return candidate.toISOString()
    }

    function engineMissingSentinel() {
        return "__KODEXBAR_ENGINE_MISSING__"
    }

    // Wrap the data-engine command so only a truly missing primary executable
    // emits the sentinel. A present wrapper that later exits 127 must not.
    function wrapEngineCommand(command, args) {
        var quotedCmd = shellQuote(command)
        var line = "command -v " + quotedCmd
            + " >/dev/null 2>&1 || { printf '%s\\n' '" + engineMissingSentinel()
            + "'; exit 127; }; exec " + quotedCmd
        for (var i = 0; i < args.length; i++) {
            line += " " + shellQuote(args[i])
        }
        return line
    }

    function commandLine(provider, source, command) {
        var args = ProviderLogic.usageArguments(provider, source, includeStatus)
        return wrapEngineCommand(command || codexbarCommand, args)
    }

    function costCommandLine(command) {
        var args = ProviderLogic.costArguments()
        return wrapEngineCommand(command || codexbarCommand, args)
    }

    function aiControlCommandLine(argv, showTerminal) {
        var command = showTerminal ? "konsole --hold -e" : ""
        command += (command.length > 0 ? " " : "") + shellQuote(aiControlCommand)
        for (var i = 0; i < argv.length; i++) {
            command += " " + shellQuote(argv[i])
        }
        return command
    }

    function localAiCommandLine(argv) {
        var command = shellQuote(localAiCommand)
        for (var i = 0; i < argv.length; i++) {
            command += " " + shellQuote(argv[i])
        }
        return command
    }

    function refreshLocalModels() {
        if (localModelsLoading) {
            return
        }
        localModelsLoading = true
        localModelsError = ""
        localAiExecutable.connectedSources = []
        localAiExecutable.connectSource(localAiCommandLine(["status"]))
    }

    function localModelAction(action, runtime, model, confirmed) {
        if (localModelsLoading) {
            return
        }
        // The executable data engine accepts one shell command. Never pass
        // arbitrary runtime values through it: these identifiers are produced
        // by local-ai and validated again by local-ai before an action runs.
        if (["mount", "unmount", "release", "stop"].indexOf(action) === -1
                || !/^[a-z][a-z0-9_]*$/.test(runtime)
                || ((action === "mount" || action === "unmount")
                    && !/^[a-z0-9_]+:[a-f0-9]{12}$/.test(model))) {
            localModelsError = i18n("Invalid local runtime action.")
            return
        }
        var argv = [action, runtime]
        if (model && model.length > 0) {
            argv.push(model)
        }
        if (confirmed === true) {
            argv.push("--confirm")
        }
        localModelsLoading = true
        localModelsError = ""
        localAiExecutable.connectedSources = []
        localAiExecutable.connectSource(localAiCommandLine(argv))
        localModelsWatchdog.restart()
    }

    function localMetricText(item) {
        if (!item || !item.metric || typeof item.metric.value !== "number" || !item.metric.unit) {
            return i18n("Throughput unavailable")
        }
        return formatNumber(item.metric.value) + " " + item.metric.unit
    }

    function localStateText(state) {
        var labels = {
            "active": i18n("Active"), "loaded": i18n("Loaded, idle"), "loading": i18n("Loading"),
            "unloading": i18n("Unloading"), "installed": i18n("Installed, unmounted"),
            "disconnected": i18n("Runtime disconnected"), "unknown": i18n("State unknown"), "error": i18n("Error")
        }
        return labels[state] || labels.unknown
    }

    function localKindText(kind) {
        var labels = { "llm": i18n("LLM and code"), "vision": i18n("Vision and multimodal"),
            "image": i18n("Image"), "video": i18n("Video"), "audio": i18n("Audio"),
            "embedding": i18n("Embeddings and reranking"), "unknown": i18n("Unknown") }
        return labels[kind] || labels.unknown
    }

    function localKindGlyph(kind) {
        var glyphs = { "llm": "{}", "vision": "◎", "image": "◈", "video": "▷", "audio": "♪", "embedding": "⋮⋮", "unknown": "?" }
        return glyphs[kind] || glyphs.unknown
    }

    function localKindColor(kind) {
        var colors = { "llm": "#8f7bff", "vision": "#5ac8fa", "image": "#f0b429", "video": "#f0b429", "audio": "#ffd166", "embedding": "#45d483", "unknown": "#6b7080" }
        return colors[kind] || colors.unknown
    }

    function localKindCount(kind) {
        var count = localModels.filter(function(item) { return item.kind === kind }).length
        return i18n("%1 models", count)
    }

    function localModelMeta(item) {
        var memory = item && item.memory ? item.memory : ({})
        var size = item && item.evidence && item.evidence.size ? item.evidence.size : i18n("size unknown")
        var quant = item && item.evidence && item.evidence.quant ? item.evidence.quant : i18n("quant unknown")
        var vram = typeof memory.vramMiB === "number" && memory.vramMiB > 0
            ? formatNumber(memory.vramMiB / 1024) + " GB"
            : i18n("VRAM unknown")
        var confidence = item && item.classificationConfidence === "heuristic" ? " · " + i18n("heuristic") : ""
        return size + " · " + quant + " · " + vram + confidence
    }

    function applyLocalInventory(payload) {
        if (!payload || !(payload.models instanceof Array)) {
            localModelsError = i18n("Invalid local model response")
            return
        }
        localModels = payload.models
        localRuntimes = payload.runtimes instanceof Array ? payload.runtimes : []
        var histories = localModelHistory
        for (var i = 0; i < localModels.length; i++) {
            var item = localModels[i]
            var sample = item.metric && typeof item.metric.value === "number" ? item.metric.value : 0
            var history = histories[item.id] || []
            histories[item.id] = history.concat([sample]).slice(-24)
        }
        localModelHistory = histories
        for (var key in histories) {
            if (!localModels.some(function(item) { return item.id === key })) {
                delete histories[key]
            }
        }
        localModelHistory = histories
    }

    function launchAiControl(argv, showTerminal) {
        aiControlError = ""
        aiControlExecutable.connectedSources = []
        aiControlExecutable.connectSource(aiControlCommandLine(argv || [], showTerminal === true))
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function refresh() {
        if (loading || startupRetryPending) {
            return
        }
        if (initialUsageSeedPending || (fastRefreshCyclesSinceSeed >= 10
                && Date.now() - lastSuccessfulSeedAt >= claudeRefreshSeconds * 1000)) {
            initialUsageSeedPending = false
            beginUsageRefresh(commandCandidatesForSeed(), true)
            return
        }
        fastRefreshCyclesSinceSeed += 1
        refreshOtherProviders()
    }

    function knownProviderIds(includeClaude) {
        var providers = []
        var seen = {}
        var sources = [entries, lastGoodEntries]
        for (var sourceIndex = 0; sourceIndex < sources.length; sourceIndex++) {
            var sourceEntries = sources[sourceIndex] || []
            for (var i = 0; i < sourceEntries.length; i++) {
                var provider = ProviderLogic.providerId(sourceEntries[i] && sourceEntries[i].provider)
                if (provider.length === 0 || provider === "all" || seen[provider]
                        || (!includeClaude && provider === "claude")) {
                    continue
                }
                seen[provider] = true
                providers.push(provider)
            }
        }
        return providers
    }

    function refreshOtherProviders() {
        var providers = knownProviderIds(false)
        if (providers.length === 0) {
            if (knownProviderIds(true).length === 0) {
                initialUsageSeedPending = true
                refresh()
            } else {
                refreshCost()
            }
            return
        }
        refreshCost()
        beginUsageRefresh(providerCandidates(providers), false)
    }

    function refreshClaude() {
        if (loading || knownProviderIds(true).indexOf("claude") === -1) {
            return
        }
        beginUsageRefresh(providerCandidates(["claude"]), false)
    }

    function providerCandidates(providers, startupRetry) {
        var candidates = []
        var commands = ProviderLogic.commandCandidates(configuredCodexbarCommand)
        for (var i = 0; i < providers.length; i++) {
            candidates.push({
                provider: providers[i],
                source: selectedSource,
                command: commands[0],
                fallbackCommand: commands.length > 1 ? commands[1] : "",
                replaceAll: false,
                startupRetry: startupRetry === true
            })
        }
        return candidates
    }

    function commandCandidatesForSeed() {
        var commands = ProviderLogic.commandCandidates(configuredCodexbarCommand)
        return [{
            provider: "all",
            source: selectedSource,
            command: commands[0],
            fallbackCommand: commands.length > 1 ? commands[1] : "",
            replaceAll: true,
            startupRetry: false
        }]
    }

    function beginUsageRefresh(candidates, refreshCosts) {
        loading = true
        errorMessage = ""
        errorDetail = ""
        pendingCandidates = candidates
        executable.connectedSources = []
        if (refreshCosts) {
            refreshCost()
        }
        tryNextCandidate()
    }

    function refreshCost() {
        costErrorMessage = ""
        if (!showCostSummary) {
            costLoading = false
            costSummaries = ({})
            applyCostSummaries()
            return
        }
        costLoading = true
        costExecutable.connectedSources = []
        pendingCostCommands = ProviderLogic.commandCandidates(configuredCodexbarCommand)
        startNextCostCandidate()
    }

    function startNextCostCandidate() {
        if (pendingCostCommands.length === 0) {
            return false
        }
        costExecutable.connectedSources = []
        costExecutable.connectSource(costCommandLine(pendingCostCommands.shift()))
        return true
    }

    function cancelUsageRefresh() {
        executable.connectedSources = []
        pendingCandidates = []
        startupRetryTimer.stop()
        startupRetryPending = false
        if (activeQueryReplacesAll) {
            initialUsageSeedPending = true
        }
        usageWatchdog.stop()
        // Timeout is a non-sentinel outcome: never leave the setup card covering normal errors.
        engineNotInstalled = false
        loading = false
    }

    function tryNextCandidate() {
        if (pendingCandidates.length === 0) {
            usageWatchdog.stop()
            if (activeStartupRetry) {
                activeStartupRetry = false
                startupRetryWindowOpen = false
            }
            loading = false
            generatedAt = new Date().toLocaleString(Qt.locale(), Locale.ShortFormat)
            if (entries.length === 0 && errorMessage.length === 0 && !engineNotInstalled) {
                errorMessage = i18n("No usable CodexBar provider found")
                errorDetail = i18n("Configure at least one provider in CodexBar or choose a compatible source.")
            }
            return
        }

        var candidate = pendingCandidates.shift()
        activeProvider = candidate.provider
        activeSource = candidate.source
        activeCommand = candidate.command || codexbarCommand
        activeFallbackCommand = candidate.fallbackCommand || ""
        activeQueryReplacesAll = candidate.replaceAll === true
        activeStartupRetry = candidate.startupRetry === true
        executable.connectedSources = []
        executable.connectSource(commandLine(activeProvider, activeSource, activeCommand))
        usageWatchdog.restart()
    }

    function applyUsageEntries(normalized) {
        var filtered = ProviderLogic.excludeUnfetchableProviderEntries(normalized)
        for (var i = 0; i < filtered.droppedProviderIds.length; i++) {
            console.warn("KodexBar: dropping unfetchable provider "
                + filtered.droppedProviderIds[i] + " from refresh results")
        }
        var incoming = filtered.entries
        var cached = ProviderLogic.withoutProviders(lastGoodEntries, filtered.droppedProviderIds)
        if (activeQueryReplacesAll) {
            lastGoodEntries = ProviderLogic.reconcileSeedCache(cached, incoming)
            fastRefreshCyclesSinceSeed = 0
            lastSuccessfulSeedAt = Date.now()
        } else {
            lastGoodEntries = ProviderLogic.cacheLastGoodEntries(cached, incoming)
        }
        var merged = ProviderLogic.mergeEntriesWithCache(incoming, lastGoodEntries)
        var providers = activeQueryReplacesAll ? [] : [activeProvider].concat(filtered.droppedProviderIds)
        var updatedEntries = ProviderLogic.replaceProviderEntries(
            entries, merged, providers, activeQueryReplacesAll)
        entries = ProviderLogic.attachProviderCostSummaries(updatedEntries, costSummaries)
    }

    function scheduleStartupProviderRetries(normalized) {
        if (!activeQueryReplacesAll || !startupRetryWindowOpen) {
            return false
        }
        var providers = ProviderLogic.startupRetryProviderIds(
            normalized, lastGoodEntries, startupRetryAttemptedProviders)
        if (providers.length === 0) {
            startupRetryWindowOpen = false
            return false
        }
        var attempted = startupRetryAttemptedProviders
        for (var i = 0; i < providers.length; i++) {
            attempted[providers[i]] = true
        }
        startupRetryAttemptedProviders = attempted
        applyUsageEntries(ProviderLogic.withoutProviders(normalized, providers))
        pendingCandidates = providerCandidates(providers, true)
        startupRetryPending = true
        startupRetryTimer.restart()
        return true
    }

    function handleUsageFailure(message, detail) {
        if (!activeQueryReplacesAll) {
            return false
        }
        errorMessage = message
        errorDetail = detail || ""
        initialUsageSeedPending = true
        pendingCandidates = []
        tryNextCandidate()
        return true
    }

    // Pure classifier for engine process outcomes. engine_missing only when the
    // wrapper reported exit 127 and stdout is exactly the sentinel (trimmed).
    // Substrings, stderr echoes, and exit 0 with the same text are normal.
    function classifyEngineResponse(stdout, stderr, exitCode) {
        if (Number(exitCode) === 127
                && String(stdout || "").trim() === "__KODEXBAR_ENGINE_MISSING__") {
            return "engine_missing"
        }
        return "normal"
    }

    // Pure presence transition for engine responses. Testable without QML and
    // used by the executable data path. Sentinel raises the setup card and never
    // purges entries/lastGoodEntries. Any normal response clears the card.
    // Parseable JSON payload updates entries and lastGood; normal errors leave
    // lastGoodEntries intact.
    function applyEngineResponse(state, stdout, stderr, exitCode) {
        var baseEntries = state && state.entries ? state.entries : []
        var baseLastGood = state && state.lastGoodEntries ? state.lastGoodEntries : []
        if (classifyEngineResponse(stdout, stderr, exitCode) === "engine_missing") {
            return {
                engineNotInstalled: true,
                entries: baseEntries,
                lastGoodEntries: baseLastGood
            }
        }
        var text = String(stdout || "").trim()
        var code = Number(exitCode) || 0
        if (code !== 0 && text.length === 0) {
            return {
                engineNotInstalled: false,
                entries: baseEntries,
                lastGoodEntries: baseLastGood
            }
        }
        if (text.length > 0) {
            try {
                var raw = JSON.parse(text)
                var list = raw instanceof Array ? raw : [raw]
                var usable = []
                for (var i = 0; i < list.length; i++) {
                    if (list[i] && typeof list[i] === "object") {
                        usable.push(list[i])
                    }
                }
                if (usable.length > 0) {
                    return {
                        engineNotInstalled: false,
                        entries: usable,
                        lastGoodEntries: usable
                    }
                }
            } catch (error) {
                // Unparseable payload is a normal error: keep lastGood.
            }
        }
        return {
            engineNotInstalled: false,
            entries: baseEntries,
            lastGoodEntries: baseLastGood
        }
    }

    function commandWasNotFound(data) {
        return classifyEngineResponse(data.stdout, data.stderr, data["exit code"] || 0) === "engine_missing"
    }

    function markEngineNotInstalled() {
        // Friendly setup card when the suite data engine binary is missing (widget-only install).
        // Does not purge entries or lastGoodEntries: recovering later must keep prior good data.
        engineNotInstalled = true
        errorMessage = ""
        errorDetail = ""
        initialUsageSeedPending = true
        pendingCandidates = []
        tryNextCandidate()
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
                entries: normalized
            }
        } catch (error) {
            return {
                ok: false,
                error: i18n("Invalid CodexBar CLI response"),
                detail: String(error)
            }
        }
    }

    function parseCostPayload(text) {
        if (!text || text.length === 0) {
            return {
                ok: false,
                error: i18n("No output from CodexBar cost")
            }
        }
        try {
            var raw = JSON.parse(text)
            var rawEntries = raw instanceof Array ? raw : [raw]
            var summaries = {}
            for (var i = 0; i < rawEntries.length; i++) {
                var summary = normalizeCostSummary(rawEntries[i])
                if (summary !== null) {
                    summaries[String(summary.provider).toLowerCase()] = summary
                }
            }
            return {
                ok: true,
                summaries: summaries
            }
        } catch (error) {
            return {
                ok: false,
                error: i18n("Invalid CodexBar cost response") + ": " + String(error)
            }
        }
    }

    function normalizeCostSummary(entry) {
        if (!entry || typeof entry !== "object" || !entry.provider) {
            return null
        }
        var todayCost = typeof entry.sessionCostUSD === "number" ? entry.sessionCostUSD : null
        var todayTokens = typeof entry.sessionTokens === "number" ? entry.sessionTokens : null
        var dayKey = localDayKey(new Date())
        var daily = entry.daily instanceof Array ? entry.daily : []
        for (var i = 0; i < daily.length; i++) {
            if (daily[i] && daily[i].date === dayKey) {
                if (typeof daily[i].totalCost === "number") {
                    todayCost = daily[i].totalCost
                }
                if (typeof daily[i].totalTokens === "number") {
                    todayTokens = daily[i].totalTokens
                }
                break
            }
        }
        var totalCost = typeof entry.last30DaysCostUSD === "number"
            ? entry.last30DaysCostUSD
            : (entry.totals && typeof entry.totals.totalCost === "number" ? entry.totals.totalCost : null)
        var totalTokens = typeof entry.last30DaysTokens === "number"
            ? entry.last30DaysTokens
            : (entry.totals && typeof entry.totals.totalTokens === "number" ? entry.totals.totalTokens : null)
        if (todayCost === null && todayTokens === null && totalCost === null && totalTokens === null) {
            return null
        }
        return {
            provider: entry.provider,
            source: entry.source || "",
            currencyCode: entry.currencyCode || "USD",
            historyDays: typeof entry.historyDays === "number" ? entry.historyDays : 30,
            todayCost: todayCost,
            todayTokens: todayTokens,
            totalCost: totalCost,
            totalTokens: totalTokens,
            updatedAt: entry.updatedAt || ""
        }
    }

    function costSummaryRows(summary) {
        if (!summary) {
            return []
        }
        var rows = []
        if (summary.todayCost !== null || summary.todayTokens !== null) {
            rows.push({
                label: i18n("Today"),
                value: formatCostAndTokens(summary.todayCost, summary.todayTokens, summary.currencyCode)
            })
        }
        if (summary.totalCost !== null || summary.totalTokens !== null) {
            rows.push({
                label: i18np("Last day", "Last %1 days", summary.historyDays || 30),
                value: formatCostAndTokens(summary.totalCost, summary.totalTokens, summary.currencyCode)
            })
        }
        return rows
    }

    function formatCostAndTokens(cost, tokens, currencyCode) {
        var parts = []
        if (cost !== null && cost !== undefined && !isNaN(cost)) {
            parts.push(formatCurrency(cost, currencyCode || "USD"))
        }
        if (tokens !== null && tokens !== undefined && !isNaN(tokens)) {
            parts.push(i18n("%1 tokens", formatTokenCount(tokens)))
        }
        return parts.join(" - ")
    }

    function applyCostSummaries() {
        if (!entries || entries.length === 0) {
            return
        }
        entries = ProviderLogic.attachProviderCostSummaries(entries, costSummaries)
    }

    function providerName(raw) {
        var key = String(raw || "").toLowerCase()
        var names = {
            "abacus": "Abacus AI",
            "alibaba": "Alibaba Coding Plan",
            "alibabatokenplan": "Alibaba Token Plan",
            "amp": "Amp",
            "antigravity": "Gemini (Antigravity)",
            "augment": "Augment",
            "bedrock": "AWS Bedrock",
            "codex": "Codex",
            "claude": "Claude",
            "openai": "OpenAI API",
            "azureopenai": "Azure OpenAI",
            "cursor": "Cursor",
            "opencode": "OpenCode",
            "opencodego": "OpenCode Go",
            "factory": "Droid",
            "devin": "Devin",
            "zai": "z.ai",
            "minimax": "MiniMax",
            "manus": "Manus",
            "kimi": "Kimi",
            "kiro": "Kiro",
            "vertexai": "Vertex AI",
            "jetbrains": "JetBrains AI",
            "kimik2": "Kimi K2",
            "moonshot": "Moonshot",
            "synthetic": "Synthetic",
            "t3chat": "T3 Chat",
            "warp": "Warp",
            "elevenlabs": "ElevenLabs",
            "windsurf": "Windsurf",
            "perplexity": "Perplexity",
            "mimo": "Xiaomi MiMo",
            "doubao": "Doubao",
            "mistral": "Mistral",
            "deepseek": "DeepSeek",
            "codebuff": "Codebuff",
            "crof": "Crof",
            "venice": "Venice",
            "commandcode": "Command Code",
            "stepfun": "StepFun",
            "grok": "Grok",
            "groq": "GroqCloud",
            "openrouter": "OpenRouter",
            "deepgram": "Deepgram",
            "llmproxy": "LLM Proxy",
            "copilot": "Copilot",
            "gemini": "Gemini",
            "kilo": "Kilo Code",
            "ollama": "Ollama"
        }
        return names[key] || (raw ? String(raw).charAt(0).toUpperCase() + String(raw).slice(1) : i18n("Provider"))
    }

    function providerIconSource(raw) {
        var key = String(raw || "").toLowerCase()
        var icons = {
            "abacus": "abacus",
            "alibaba": "alibaba",
            "alibabatokenplan": "alibabatokenplan",
            "amp": "amp",
            "antigravity": "antigravity",
            "augment": "augment",
            "bedrock": "bedrock",
            "codex": "codex",
            "claude": "claude",
            "openai": "openai",
            "azureopenai": "azureopenai",
            "cursor": "cursor",
            "opencode": "opencode",
            "opencodego": "opencodego",
            "factory": "factory",
            "devin": "devin",
            "zai": "zai",
            "minimax": "minimax",
            "manus": "manus",
            "kimi": "kimi",
            "kiro": "kiro",
            "vertexai": "vertexai",
            "jetbrains": "jetbrains",
            "kimik2": "kimik2",
            "moonshot": "moonshot",
            "synthetic": "synthetic",
            "t3chat": "t3chat",
            "warp": "warp",
            "elevenlabs": "elevenlabs",
            "windsurf": "windsurf",
            "perplexity": "perplexity",
            "mimo": "mimo",
            "doubao": "doubao",
            "mistral": "mistral",
            "deepseek": "deepseek",
            "codebuff": "codebuff",
            "crof": "crof",
            "venice": "venice",
            "commandcode": "commandcode",
            "stepfun": "stepfun",
            "grok": "grok",
            "groq": "groq",
            "openrouter": "openrouter",
            "deepgram": "deepgram",
            "llmproxy": "llmproxy",
            "copilot": "copilot",
            "gemini": "gemini",
            "kilo": "kilo",
            "ollama": "ollama"
        }
        return Qt.resolvedUrl("../icons/providers/" + (icons[key] || "codex") + ".svg")
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

    function knownPercentLeft(window) {
        if (window && typeof window === "object" && window.usageKnown === false) {
            return null
        }
        return percentLeft(window)
    }

    function displayPercentLeft(provider, primary, secondary) {
        var primaryLeft = knownPercentLeft(primary)
        var id = String(provider || "").toLowerCase()
        // Codex and Grok may emit weekly-only usage in secondary (Session slot empty).
        if (id !== "codex" && id !== "grok") {
            return primaryLeft
        }

        var weeklyLeft = knownPercentLeft(secondary)
        return weeklyLeft !== null ? weeklyLeft : primaryLeft
    }

    function resetAt(window) {
        if (!window || typeof window !== "object") {
            return null
        }

        var fields = ["resetsAt", "resetAt", "resetTime", "resetDate"]
        for (var i = 0; i < fields.length; i++) {
            if (window[fields[i]]) {
                return window[fields[i]]
            }
        }

        if (typeof window.resetTimestamp === "number") {
            var timestamp = window.resetTimestamp < 10000000000
                ? window.resetTimestamp * 1000
                : window.resetTimestamp
            return new Date(timestamp).toISOString()
        }

        return resetTimeFromDescription(window.resetDescription || window.resetsIn || "")
    }

    function windowDetail(window, usageKnown) {
        if (!window || typeof window !== "object") {
            return ""
        }
        var parts = []
        if (usageKnown === false) {
            parts.push(i18n("Usage not reported"))
        }
        if (window.resetDescription) {
            parts.push(window.resetDescription)
        }
        if (typeof window.nextRegenPercent === "number" && window.nextRegenPercent > 0) {
            parts.push(i18n("+%1% next regen", Math.round(window.nextRegenPercent)))
        }
        return parts.join(" - ")
    }

    function providerCostRow(cost) {
        if (!cost || typeof cost !== "object" || typeof cost.used !== "number" || typeof cost.limit !== "number" || cost.limit <= 0) {
            return null
        }
        var used = Math.max(0, Math.min(100, cost.used / cost.limit * 100))
        var detail = formatCurrency(cost.used, cost.currencyCode) + " / " + formatCurrency(cost.limit, cost.currencyCode)
        if (typeof cost.nextRegenAmount === "number" && cost.nextRegenAmount > 0) {
            detail += " - " + i18n("+%1 next regen", formatNumber(cost.nextRegenAmount))
        }
        return {
            title: cost.period || i18n("Spend"),
            percentLeft: Math.max(0, 100 - used),
            resetsAt: cost.resetsAt || null,
            detail: detail,
            usageKnown: true
        }
    }

    function dashboardSummary(dashboard) {
        if (!dashboard || typeof dashboard !== "object") {
            return []
        }
        var summary = []
        if (typeof dashboard.codeReviewRemainingPercent === "number") {
            summary.push(i18n("Code review: %1% remaining", Math.round(dashboard.codeReviewRemainingPercent)))
        }
        if (dashboard.accountPlan) {
            summary.push(i18n("Plan: %1", dashboard.accountPlan))
        }
        if (dashboard.creditEvents && dashboard.creditEvents.length > 0) {
            summary.push(i18np("%1 credit event", "%1 credit events", dashboard.creditEvents.length))
        }
        if (dashboard.dailyBreakdown && dashboard.dailyBreakdown.length > 0) {
            summary.push(i18np("%1 credit-history day", "%1 credit-history days", dashboard.dailyBreakdown.length))
        }
        if (dashboard.usageBreakdown && dashboard.usageBreakdown.length > 0) {
            summary.push(i18np("%1 usage-breakdown day", "%1 usage-breakdown days", dashboard.usageBreakdown.length))
        }
        return summary
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
        var antigravity = ProviderLogic.providerId(entry.provider) === "antigravity"
        var providerCost = usage.providerCost && typeof usage.providerCost === "object" ? usage.providerCost : null
        var status = entry.status && typeof entry.status === "object" ? entry.status : null
        var bankedResets = ProviderLogic.normalizeCodexResetCredits(usage.codexResetCredits)
        var rows = []
        var windows = antigravity ? [] : [
            { key: "primary", title: i18n("Session"), data: primary },
            { key: "weekly", title: i18n("Weekly"), data: secondary },
            { key: "tertiary", title: i18n("Tertiary"), data: tertiary }
        ]
        for (var i = 0; i < windows.length; i++) {
            var left = knownPercentLeft(windows[i].data)
            var reset = resetAt(windows[i].data)
            var standardRow = ProviderLogic.standardWindowRow(
                windows[i].key, windows[i].title, left, reset,
                windowDetail(windows[i].data, left !== null))
            if (standardRow !== null) {
                // Weekly composition segments (Grok): points sum to usedPercent of one pool.
                if (windows[i].key === "weekly" && windows[i].data
                        && Array.isArray(windows[i].data.segments)) {
                    var segments = ProviderLogic.normalizeUsageSegments(windows[i].data.segments)
                    if (segments.length > 0) {
                        standardRow.segments = segments
                        // Accessible legend items (dot color + name + points). No duplicated total.
                        standardRow.segmentLegendItems = ProviderLogic.formatSegmentLegendParts(segments)
                    }
                }
                rows.push(standardRow)
            }
        }
        var extraRateWindows = antigravity ? [] : (usage.extraRateWindows && usage.extraRateWindows.length ? usage.extraRateWindows : [])
        var antigravityWindows = antigravity && Array.isArray(usage.antigravityRateWindows)
            ? usage.antigravityRateWindows : []
        for (var antigravityIndex = 0; antigravityIndex < antigravityWindows.length; antigravityIndex++) {
            var antigravityWindow = antigravityWindows[antigravityIndex]
            if (!antigravityWindow || !antigravityWindow.window) {
                continue
            }
            var antigravityLeft = percentLeft(antigravityWindow.window)
            var antigravityReset = resetAt(antigravityWindow.window)
            if (antigravityLeft === null && !antigravityReset) {
                continue
            }
            var antigravityKnown = antigravityLeft !== null && antigravityWindow.window.usageKnown !== false
            var antigravityKey = antigravityWindow.key || ProviderLogic.compactQuotaKey(antigravityWindow.title || "quota")
            rows.push({
                title: antigravityWindow.title || i18n("Upstream quota"),
                percentLeft: antigravityKnown ? antigravityLeft : null,
                resetsAt: antigravityReset,
                detail: windowDetail(antigravityWindow.window, antigravityKnown),
                usageKnown: antigravityKnown,
                precisePercent: true,
                compactKey: antigravityKey,
                compactExtra: true,
                antigravityQuota: true,
                compactLabel: antigravityKey === "gemini-weekly" ? "W"
                    : antigravityKey === "gemini-5h" ? "S"
                    : antigravityKey === "claude-gpt-weekly" ? "CW"
                    : antigravityKey === "claude-gpt-5h" ? "C5h" : "Ag",
                windowBadge: antigravityWindow.windowType === "weekly" ? "W"
                    : antigravityWindow.windowType === "5h" ? "5h"
                    : ProviderLogic.quotaWindowBadge(antigravityKey, antigravityWindow.title || "")
            })
        }
        for (var j = 0; j < extraRateWindows.length; j++) {
            var extra = extraRateWindows[j]
            if (!extra || !extra.window) {
                continue
            }
            var extraLeft = percentLeft(extra.window)
            if (extraLeft !== null || resetAt(extra.window)) {
                var extraUsageKnown = extra.usageKnown !== false
                    && extra.window.usageKnown !== false
                    && extraLeft !== null
                rows.push({
                    title: extra.title || i18n("Extra"),
                    percentLeft: extraUsageKnown ? extraLeft : null,
                    resetsAt: resetAt(extra.window),
                    detail: windowDetail(extra.window, extraUsageKnown),
                    usageKnown: extraUsageKnown,
                    compactKey: ProviderLogic.compactQuotaKey(extra.title || "extra"),
                    compactExtra: true,
                    windowBadge: ProviderLogic.quotaWindowBadge(
                        ProviderLogic.compactQuotaKey(extra.title || "extra"),
                        extra.title || i18n("Extra"))
                })
            }
        }
        var costRow = providerCostRow(providerCost)
        if (costRow !== null) {
            rows.push(costRow)
        }
        var primaryLeft = knownPercentLeft(primary)
        var secondaryLeft = knownPercentLeft(secondary)
        // Compact primary is Session only. Never copy Grok weekly into primary (that
        // duplicated W as S under default primary,weekly). Grok weekly stays in secondary.
        var rawExtraUsage = usage.extraUsage && typeof usage.extraUsage === "object" ? usage.extraUsage : null
        var extraUsage = null
        if (rawExtraUsage) {
            extraUsage = {
                enabled: rawExtraUsage.enabled === true,
                balance: typeof rawExtraUsage.balance === "number" && !isNaN(rawExtraUsage.balance)
                    ? rawExtraUsage.balance
                    : null,
                currency: typeof rawExtraUsage.currency === "string" && rawExtraUsage.currency
                    ? rawExtraUsage.currency
                    : null
            }
        }
        return {
            provider: entry.provider,
            name: providerName(entry.provider),
            version: entry.version,
            source: entry.source,
            account: entry.account || usage.accountEmail || identity.accountEmail || "",
            plan: usage.loginMethod || identity.loginMethod || dashboard.accountPlan || "",
            primaryPercentLeft: displayPercentLeft(entry.provider, primary, secondary),
            compactPrimaryPercentLeft: antigravity ? null : primaryLeft,
            primaryResetsAt: antigravity ? null : resetAt(primary),
            secondaryPercentLeft: antigravity ? null : secondaryLeft,
            secondaryResetsAt: antigravity ? null : resetAt(secondary),
            tertiaryPercentLeft: knownPercentLeft(tertiary),
            tertiaryResetsAt: resetAt(tertiary),
            creditsRemaining: credits ? credits.remaining : (typeof dashboard.creditsRemaining === "number" ? dashboard.creditsRemaining : null),
            bankedResetCount: bankedResets.availableCount,
            bankedResetExpiresAt: bankedResets.expiresAt,
            extraUsage: extraUsage,
            codeReviewRemainingPercent: typeof dashboard.codeReviewRemainingPercent === "number" ? dashboard.codeReviewRemainingPercent : null,
            dashboardSummary: dashboardSummary(dashboard),
            rows: rows,
            updatedAt: usage.updatedAt || entry.updatedAt || "",
            status: entry.status,
            statusIndicator: status ? (status.indicator || "unknown") : "",
            statusDescription: status ? (status.description || "") : "",
            statusURL: status ? (status.url || "") : "",
            errorMessage: error ? (error.message || i18n("Provider returned an error")) : "",
            errorKind: error ? (error.kind || "") : "",
            errorCategory: error ? (error.category || "") : "",
            errorRetryable: error && typeof error.retryable === "boolean" ? error.retryable : undefined,
            signedOut: false
        }
    }

    function formatExtraUsageValue(extra) {
        if (!extra || typeof extra !== "object") {
            return ""
        }
        if (!extra.enabled) {
            return i18n("Off")
        }
        if (extra.balance !== null && extra.balance !== undefined && !isNaN(extra.balance) && extra.balance > 0) {
            var amount = formatCredits(extra.balance)
            if (extra.currency) {
                return i18n("On") + " · " + amount + " " + extra.currency
            }
            return i18n("On") + " · " + amount
        }
        return i18n("On")
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

    function usageAccent(percentLeft) {
        if (percentLeft === null || percentLeft === undefined || isNaN(percentLeft)) {
            return Kirigami.Theme.disabledTextColor
        }
        if (percentLeft < 15) {
            return Kirigami.Theme.negativeTextColor
        }
        if (percentLeft < 35) {
            return Kirigami.Theme.neutralTextColor
        }
        return Kirigami.Theme.highlightColor
    }

    function statusText(indicator, description) {
        if (!indicator) {
            return ""
        }
        var labels = {
            "none": i18n("Operational"),
            "minor": i18n("Partial outage"),
            "major": i18n("Major outage"),
            "critical": i18n("Critical issue"),
            "maintenance": i18n("Maintenance"),
            "unknown": i18n("Status unknown")
        }
        var label = labels[indicator] || indicator
        return description ? label + ": " + description : label
    }

    function statusColor(indicator) {
        if (indicator === "none") {
            return Kirigami.Theme.positiveTextColor
        }
        if (indicator === "minor" || indicator === "maintenance") {
            return Kirigami.Theme.neutralTextColor
        }
        if (indicator === "major" || indicator === "critical") {
            return Kirigami.Theme.negativeTextColor
        }
        return Kirigami.Theme.disabledTextColor
    }

    component CompactStrip: Item {
        id: strip
        property var blocks: []
        property bool preview: false
        property int activeLocalCount: 0

        implicitWidth: stripRow.implicitWidth
        implicitHeight: 28
        clip: true

        Row {
            id: stripRow
            height: parent.height
            spacing: 10

            Repeater {
                model: strip.blocks

                delegate: Row {
                    height: stripRow.height
                    spacing: 7

                    Rectangle {
                        visible: index > 0
                        width: visible ? 1 : 0
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#333844"
                    }

                    Rectangle {
                        width: 7
                        height: 7
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.error
                            ? root.errorColor
                            : modelData.cached
                                ? root.quietColor
                            : root.metricAccent(
                                modelData.worstUsedPercent === null
                                    || modelData.worstUsedPercent === undefined
                                    ? null
                                    : 100 - modelData.worstUsedPercent,
                                modelData.worstUsedPercent !== null
                                    && modelData.worstUsedPercent !== undefined)
                    }

                    Image {
                        visible: root.showProviderInPanel
                        width: visible ? 15 : 0
                        height: 15
                        anchors.verticalCenter: parent.verticalCenter
                        source: root.providerIconSource(modelData.provider)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    PlasmaComponents.Label {
                        visible: !!(modelData.ordinal && modelData.ordinal.length > 0)
                        text: modelData.ordinal || ""
                        color: root.quietColor
                        font.family: root.designFont
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    PlasmaComponents.Label {
                        text: modelData.displayText || ""
                        color: modelData.error ? root.errorColor : root.textColor
                        font.family: root.designFont
                        font.pixelSize: 13
                        font.weight: modelData.error ? Font.Bold : Font.DemiBold
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, strip.preview ? 112 : 126)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Row {
                visible: strip.activeLocalCount > 0
                height: stripRow.height
                spacing: 7

                Rectangle {
                    width: visible ? 1 : 0
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#333844"
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.goodColor
                }

                Kirigami.Icon {
                    width: 14
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter
                    source: "cpu"
                    color: root.mutedColor
                }

                PlasmaComponents.Label {
                    text: i18n("%1 mdl", strip.activeLocalCount)
                    color: root.textColor
                    font.family: root.designFont
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    compactRepresentation: MouseArea {
        id: compact
        readonly property var compactState: root.compactResult()

        Layout.minimumWidth: Math.min(compactBackground.implicitWidth, 520)
        Layout.preferredWidth: Math.min(compactBackground.implicitWidth, 520)
        Layout.maximumWidth: 520
        Layout.minimumHeight: 30
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Rectangle {
            id: compactBackground
            anchors.fill: parent
            implicitWidth: Math.min(compactStrip.implicitWidth + 18, 520)
            implicitHeight: 30
            radius: 9
            color: root.cardColor
            border.color: root.lineColor
            border.width: 1
            clip: true

            CompactStrip {
                id: compactStrip
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                blocks: compact.compactState.blocks || []
                activeLocalCount: root.localModels.filter(function(item) { return item.state === "active" }).length
            }

            PlasmaComponents.Label {
                anchors.centerIn: parent
                visible: !compact.compactState.blocks || compact.compactState.blocks.length === 0
                text: root.panelText()
                color: root.mutedColor
                font.family: root.designFont
                font.pixelSize: 12
                elide: Text.ElideRight
                width: Math.max(0, parent.width - 18)
            }
        }
    }

    fullRepresentation: Item {
        id: full

        Layout.minimumWidth: 520
        Layout.maximumWidth: 520
        Layout.preferredWidth: 520
        // The metric ScrollView owns overflow instead of enlarging the compact
        // 520 by 520 viewport.
        Layout.minimumHeight: 520
        Layout.maximumHeight: 520
        Layout.preferredHeight: 520

        Rectangle {
            id: popupCard
            anchors.fill: parent
            radius: 18
            color: "#131419"
            border.color: root.lineColor
            border.width: 1
            clip: true
        }

        ColumnLayout {
            anchors.fill: popupCard
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 62

                Rectangle {
                    width: 26
                    height: 26
                    radius: 0
                    x: 16
                    y: 15
                    color: "transparent"

                    Image {
                        visible: root.selectedPopupTab !== "local"
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        source: root.providerIconSource(root.activeEntry.provider)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Kirigami.Icon {
                        visible: root.selectedPopupTab === "local"
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        source: "cpu"
                        color: root.textColor
                    }
                }

                Column {
                    x: 56
                    y: 12
                    spacing: 1

                    Row {
                        spacing: 8
                        PlasmaComponents.Label {
                            text: root.selectedPopupTab === "local" ? i18n("Local models") : (root.activeEntry.displayName || i18n("Provider"))
                            color: root.textColor
                            font.family: root.designFont
                            font.pixelSize: 16
                            font.weight: Font.ExtraBold
                        }
                        PlasmaComponents.Label {
                            width: Math.max(0, headerTabs.x - 8 - (parent.x + parent.width))
                            text: root.selectedPopupTab === "local"
                                ? i18n("%1 in memory", root.localModels.filter(function(item) { return item.state === "active" || item.state === "loaded" }).length)
                                : (root.activeEntry.plan || root.activeEntry.accountLabel || root.activeEntry.source || i18n("Usage"))
                            color: "#7a8093"
                            font.family: root.designFont
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        spacing: 6
                        Rectangle { width: 6; height: 6; radius: 3; color: root.selectedPopupTab === "local" ? root.goodColor : root.activeStatusColor(root.activeEntry) }
                        PlasmaComponents.Label {
                            text: root.selectedPopupTab === "local" ? i18n("Checked just now")
                                : i18n("Updated %1", root.formatUpdatedTime(root.activeEntry.updatedAt))
                            color: root.quietColor
                            font.family: root.designFont
                            font.pixelSize: 11
                        }
                        PlasmaComponents.Label { text: "·"; color: "#3a3f4d"; font.pixelSize: 11 }
                        PlasmaComponents.Label {
                            text: String(root.selectedPopupTab === "local" ? "local" : (root.activeEntry.source || root.activeSource || "")).toUpperCase()
                            color: root.accentColor
                            font.family: root.designFont
                            font.pixelSize: 11
                            font.letterSpacing: 0.5
                        }
                    }
                }

                QQC2.ToolButton {
                    id: configureButton
                    visible: true
                    width: 30
                    height: 30
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    y: 16
                    text: i18n("Configure")
                    display: QQC2.AbstractButton.IconOnly
                    Accessible.name: text
                    onClicked: root.openPreferences()

                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text

                    contentItem: Item {
                        implicitWidth: 16
                        implicitHeight: 16

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: "configure"
                            color: configureButton.enabled ? root.mutedColor : root.quietColor
                        }
                    }

                    background: Rectangle {
                        radius: 9
                        color: parent.hovered ? "#20232d" : "transparent"
                    }
                }

                QQC2.ToolButton {
                    id: aiControlButton
                    width: 30
                    height: 30
                    anchors.right: refreshButton.left
                    anchors.rightMargin: 2
                    y: 16
                    text: i18n("AI CLI Control")
                    display: QQC2.AbstractButton.IconOnly
                    Accessible.name: text
                    onClicked: { root.refreshLocalModels(); aiControlPopup.open() }

                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text

                    contentItem: Item {
                        implicitWidth: 16
                        implicitHeight: 16

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: "utilities-terminal"
                            color: aiControlButton.enabled ? "#a898ff" : root.quietColor
                        }
                    }

                    background: Rectangle {
                        radius: 9
                        color: aiControlPopup.visible ? "#292343" : (parent.hovered ? "#20232d" : "transparent")
                    }
                }

                QQC2.Menu {
                    id: aiControlMenu

                    QQC2.MenuItem {
                        text: i18n("Open AI CLI Control")
                        icon.name: "applications-development"
                        onTriggered: root.launchAiControl([])
                    }

                    QQC2.MenuItem {
                        text: i18n("Update all AI CLIs")
                        icon.name: "view-refresh"
                        onTriggered: root.launchAiControl(["--update", "all"], true)
                    }
                }

                QQC2.ToolButton {
                    id: refreshButton
                    width: 30
                    height: 30
                    anchors.right: configureButton.left
                    anchors.rightMargin: 2
                    y: 16
                    enabled: !root.loading
                    text: i18n("Refresh")
                    display: QQC2.AbstractButton.IconOnly
                    Accessible.name: text
                    onClicked: root.refresh()

                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text

                    contentItem: Item {
                        implicitWidth: 16
                        implicitHeight: 16

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: "view-refresh"
                            color: refreshButton.enabled ? root.mutedColor : root.quietColor
                        }
                    }

                    background: Rectangle {
                        radius: 9
                        color: parent.hovered ? "#20232d" : "transparent"
                    }
                }

                Rectangle {
                    id: headerToolsDivider
                    width: 1
                    height: 20
                    anchors.right: aiControlButton.left
                    anchors.rightMargin: 8
                    y: 21
                    color: "#282b34"
                }

                Row {
                    id: headerTabs
                    anchors.right: headerToolsDivider.left
                    anchors.rightMargin: 8
                    y: 16
                    spacing: 2

                    Repeater {
                        model: root.popupTabs
                        delegate: Item {
                            readonly property bool selected: modelData.kind === "local"
                                ? root.selectedPopupTab === "local"
                                : root.selectedPopupTab === "provider" && modelData.entry.selectionKey === root.popupState.selectionKey
                            width: modelData.kind === "local" && headerTabsRepeater.count > 1 ? 37 : 30
                            height: 30

                            Rectangle {
                                visible: modelData.kind === "local" && headerTabsRepeater.count > 1
                                width: 1
                                height: 18
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#282b34"
                            }

                            QQC2.ToolButton {
                                anchors.right: parent.right
                                width: 30
                                height: 30
                                text: modelData.tabLabel
                                display: QQC2.AbstractButton.IconOnly
                                Accessible.name: text
                                onClicked: {
                                    if (modelData.kind === "local") { root.selectedPopupTab = "local"; root.refreshLocalModels() }
                                    else { root.selectedPopupTab = "provider"; root.selectedEntryKey = modelData.entry.selectionKey }
                                }
                                contentItem: Item {
                                    Image {
                                        visible: modelData.kind !== "local"
                                        anchors.centerIn: parent
                                        width: 16; height: 16
                                        source: root.providerIconSource(modelData.provider)
                                        fillMode: Image.PreserveAspectFit
                                        opacity: parent.parent.parent.selected ? 1 : 0.4
                                    }
                                    Kirigami.Icon {
                                        visible: modelData.kind === "local"
                                        anchors.centerIn: parent
                                        width: 16; height: 16
                                        source: "cpu"
                                        color: parent.parent.parent.selected ? root.textColor : root.quietColor
                                    }
                                }
                                background: Rectangle { radius: 9; color: parent.parent.selected ? "#262a35" : (parent.hovered ? "#20232d" : "transparent") }
                            }
                        }
                        id: headerTabsRepeater
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 1

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    height: 1
                    color: "#20232b"
                }

                Rectangle {
                    visible: false
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    height: 38
                    radius: 0
                    color: "transparent"
                    border.width: 0

                    ListView {
                        id: providerTabs
                        anchors.fill: parent
                        anchors.margins: 4
                        orientation: ListView.Horizontal
                        spacing: 2
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentWidth > width
                        model: root.popupTabs

                        delegate: QQC2.Button {
                            readonly property bool selected: modelData.kind === "local"
                                ? root.selectedPopupTab === "local"
                                : root.selectedPopupTab === "provider"
                                    && modelData.entry.selectionKey === root.popupState.selectionKey
                            width: 32
                            height: 32
                            flat: true
                            text: modelData.tabLabel
                            onClicked: {
                                if (modelData.kind === "local") {
                                    root.selectedPopupTab = "local"
                                    root.refreshLocalModels()
                                } else {
                                    root.selectedPopupTab = "provider"
                                    root.selectedEntryKey = modelData.entry.selectionKey
                                }
                            }

                            contentItem: RowLayout {
                                spacing: 7

                                Rectangle {
                                    visible: modelData.kind === "local" && providerTabs.count > 1
                                    Layout.preferredWidth: visible ? 1 : 0
                                    Layout.preferredHeight: 18
                                    color: "#282b34"
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Image {
                                    visible: modelData.kind !== "local"
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: visible ? 16 : 0
                                    source: root.providerIconSource(modelData.provider)
                                    fillMode: Image.PreserveAspectFit
                                    opacity: parent.parent.selected ? 1 : 0.55
                                    smooth: true
                                }

                                Kirigami.Icon {
                                    visible: modelData.kind === "local"
                                    Layout.preferredWidth: visible ? 16 : 0
                                    Layout.preferredHeight: 16
                                    source: "cpu"
                                    color: parent.parent.selected ? "#f2f3f8" : root.mutedColor
                                }

                                PlasmaComponents.Label {
                                    visible: false
                                    text: modelData.tabLabel
                                    color: parent.parent.selected ? "#f2f3f8" : root.mutedColor
                                    font.family: root.designFont
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: visible ? 104 : 0
                                }

                                Item {
                                    Layout.fillWidth: true
                                }
                            }

                            background: Rectangle {
                                radius: 9
                                color: parent.selected ? "#242836" : "transparent"
                                border.color: parent.selected ? "#333a4c" : "transparent"
                                border.width: 1
                            }
                        }
                    }
                }
            }

            Item {
                id: providerContent
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedPopupTab !== "local"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 16
                    anchors.bottomMargin: 6
                    spacing: 10

                    RowLayout {
                        visible: false
                        Layout.fillWidth: true
                        Layout.preferredHeight: 0
                        spacing: 10

                        Image {
                            visible: root.popupState.hasEntry
                            Layout.preferredWidth: visible ? 20 : 0
                            Layout.preferredHeight: 20
                            source: root.providerIconSource(root.activeEntry.provider)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        PlasmaComponents.Label {
                            text: root.popupState.hasEntry ? root.activeEntry.displayName : "KodexBar Suite"
                            color: root.textColor
                            font.family: root.designFont
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            Layout.maximumWidth: 210
                        }

                        Rectangle {
                            width: 7
                            height: 7
                            radius: 4
                            color: root.activeStatusColor(root.activeEntry)
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        PlasmaComponents.Label {
                            visible: root.formatUpdatedTime(root.activeEntry.updatedAt).length > 0
                            text: i18n("updated %1", root.formatUpdatedTime(root.activeEntry.updatedAt))
                                + (root.activeEntry.isCached === true ? " · " + i18n("cached") : "")
                            color: root.quietColor
                            font.family: root.designFont
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.maximumWidth: 126
                        }

                        Rectangle {
                            visible: sourcePillLabel.text.length > 0
                            Layout.preferredWidth: sourcePillLabel.implicitWidth + 18
                            Layout.preferredHeight: 22
                            radius: 11
                            color: "#211d3d"

                            PlasmaComponents.Label {
                                id: sourcePillLabel
                                anchors.centerIn: parent
                                text: String(root.activeEntry.source || root.activeSource || "").toUpperCase()
                                color: "#9787ff"
                                font.family: root.designFont
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.5
                            }
                        }
                    }

                    QQC2.ScrollView {
                        id: metricScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                        QQC2.ScrollBar.vertical.policy: metricContent.implicitHeight > metricScroll.availableHeight
                            ? QQC2.ScrollBar.AsNeeded
                            : QQC2.ScrollBar.AlwaysOff

                        ColumnLayout {
                            id: metricContent
                            width: metricScroll.availableWidth
                            spacing: 18

                            RowLayout {
                                visible: root.loading && root.popupEntries.length === 0
                                Layout.fillWidth: true
                                Layout.topMargin: 26
                                spacing: 10

                                Item {
                                    Layout.fillWidth: true
                                }

                                QQC2.BusyIndicator {
                                    running: visible
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                }

                                PlasmaComponents.Label {
                                    text: i18n("Loading usage...")
                                    color: root.mutedColor
                                    font.family: root.designFont
                                    font.pixelSize: 13
                                }

                                Item {
                                    Layout.fillWidth: true
                                }
                            }

                            Rectangle {
                                id: engineMissingCard
                                objectName: "engineMissingCard"
                                visible: root.engineNotInstalled && !root.loading
                                Layout.fillWidth: true
                                Layout.preferredHeight: engineMissingContent.implicitHeight + 30
                                radius: 13
                                color: root.raisedColor
                                border.color: root.lineColor
                                border.width: 1

                                ColumnLayout {
                                    id: engineMissingContent
                                    anchors.fill: parent
                                    anchors.margins: 15
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        Kirigami.Icon {
                                            source: "package-install"
                                            color: root.accentColor
                                            Layout.preferredWidth: 22
                                            Layout.preferredHeight: 22
                                            Layout.alignment: Qt.AlignTop
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            PlasmaComponents.Label {
                                                objectName: "engineMissingTitle"
                                                text: i18n("Data engine not installed")
                                                color: root.textColor
                                                font.family: root.designFont
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                Layout.fillWidth: true
                                            }

                                            PlasmaComponents.Label {
                                                objectName: "engineMissingBody"
                                                text: i18n("This widget needs the KodexBar Suite data engine to show AI CLI quotas. Install the full suite package, then open the popup again.")
                                                color: root.mutedColor
                                                font.family: root.designFont
                                                font.pixelSize: 12
                                                lineHeight: 1.45
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        QQC2.TextField {
                                            id: engineInstallCommandField
                                            objectName: "engineMissingInstallCommand"
                                            Layout.fillWidth: true
                                            readOnly: true
                                            selectByMouse: true
                                            text: root.engineInstallCommand
                                            font.family: "monospace"
                                            font.pixelSize: 12
                                        }

                                        QQC2.Button {
                                            objectName: "engineMissingCopyButton"
                                            text: i18n("Copy")
                                            onClicked: {
                                                engineInstallCommandField.selectAll()
                                                engineInstallCommandField.copy()
                                            }
                                        }
                                    }

                                    PlasmaComponents.Label {
                                        objectName: "engineMissingRepoLink"
                                        text: '<a href="' + root.engineRepoUrl + '">' + root.engineRepoUrl + "</a>"
                                        textFormat: Text.RichText
                                        color: root.accentColor
                                        font.family: root.designFont
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                        onLinkActivated: function(link) {
                                            Qt.openUrlExternally(link)
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.NoButton
                                            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: !root.engineNotInstalled
                                    && ((root.errorMessage.length > 0 && root.popupEntries.length === 0)
                                        || (root.popupState.hasEntry && root.activeEntry.errorMessage))
                                Layout.fillWidth: true
                                Layout.preferredHeight: errorContent.implicitHeight + 30
                                radius: 13
                                color: "#2b2027"
                                border.color: "#6b3943"
                                border.width: 1

                                RowLayout {
                                    id: errorContent
                                    anchors.fill: parent
                                    anchors.margins: 15
                                    spacing: 12

                                    Kirigami.Icon {
                                        source: "dialog-error"
                                        color: root.errorColor
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        Layout.alignment: Qt.AlignTop
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3

                                        PlasmaComponents.Label {
                                            text: i18n("Couldn't load usage · ERR")
                                            color: "#ff8888"
                                            font.family: root.designFont
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                            Layout.fillWidth: true
                                        }

                                        PlasmaComponents.Label {
                                            text: root.popupState.hasEntry && root.activeEntry.errorMessage
                                                ? root.activeEntry.errorMessage
                                                : (root.errorDetail.length > 0
                                                    ? root.errorMessage + " " + root.errorDetail
                                                    : root.errorMessage)
                                            color: "#cc9999"
                                            font.family: root.designFont
                                            font.pixelSize: 12
                                            lineHeight: 1.45
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                visible: !root.loading && !root.engineNotInstalled
                                    && root.popupEntries.length === 0 && root.errorMessage.length === 0
                                Layout.fillWidth: true
                                Layout.topMargin: 24
                                spacing: 4

                                PlasmaComponents.Label {
                                    text: i18n("No usage reported")
                                    color: root.mutedColor
                                    font.family: root.designFont
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                }

                                PlasmaComponents.Label {
                                    text: i18n("Waiting for an enabled provider to check in.")
                                    color: root.quietColor
                                    font.family: root.designFont
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                }
                            }

                            PlasmaComponents.Label {
                                visible: !!(root.popupState.hasEntry
                                    && root.activeEntry.statusIndicator
                                    && root.activeEntry.statusIndicator.length > 0
                                    && !root.activeEntry.errorMessage)
                                text: root.statusText(root.activeEntry.statusIndicator, root.activeEntry.statusDescription)
                                color: root.statusColor(root.activeEntry.statusIndicator)
                                font.family: root.designFont
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Repeater {
                                model: root.popupState.hasEntry && !root.activeEntry.errorMessage
                                    ? (root.activeEntry.rows || [])
                                    : []

                                delegate: ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 7

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Rectangle {
                                            Layout.preferredWidth: Math.max(22, badgeLabel.implicitWidth + 10)
                                            Layout.preferredHeight: 20
                                            radius: 5
                                            color: root.raisedColor
                                            border.color: "#2b303c"
                                            border.width: 1

                                            PlasmaComponents.Label {
                                                id: badgeLabel
                                                anchors.centerIn: parent
                                                text: modelData.windowBadge || ProviderLogic.quotaWindowBadge(
                                                    modelData.compactKey, modelData.title)
                                                color: root.quietColor
                                                font.family: root.designFont
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                            }
                                        }

                                        PlasmaComponents.Label {
                                            text: modelData.title || ""
                                            color: root.textColor
                                            font.family: root.designFont
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        PlasmaComponents.Label {
                                            text: root.formatResetTime(modelData.resetsAt).toLowerCase()
                                            color: root.quietColor
                                            font.family: root.designFont
                                            font.pixelSize: 12
                                            visible: text.length > 0
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: 124
                                        }

                                    }

                                    // Solid fill when the row has no composition segments.
                                    Rectangle {
                                        readonly property real used: root.usedPercent(modelData.percentLeft) || 0
                                        visible: modelData.usageKnown !== false
                                            && modelData.percentLeft !== null
                                            && modelData.percentLeft !== undefined
                                            && !(modelData.segments && modelData.segments.length)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: "#20232d"
                                        clip: true

                                        Rectangle {
                                            width: parent.width * parent.used / 100
                                            height: parent.height
                                            radius: 3
                                            color: root.metricAccent(modelData.percentLeft, modelData.usageKnown)
                                        }
                                    }

                                    // Segmented weekly composition bar (Grok): each surface's
                                    // points are percentage points of the single weekly pool.
                                    // Remaining track (100 - sum(points)) stays empty.
                                    // Internal 1px dividers overlay boundaries and do not alter widths.
                                    Rectangle {
                                        id: segmentTrack
                                        visible: modelData.usageKnown !== false
                                            && !!(modelData.segments && modelData.segments.length)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: "#20232d"
                                        clip: true

                                        Row {
                                            anchors.fill: parent
                                            spacing: 0

                                            Repeater {
                                                model: modelData.segments || []

                                                delegate: Item {
                                                    width: Math.max(
                                                        0,
                                                        segmentTrack.width * Math.min(100, Math.max(0, modelData.points)) / 100)
                                                    height: segmentTrack.height

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        color: root.segmentColor(modelData.title, index)
                                                    }

                                                    // Dark 1px divider on internal frontiers only.
                                                    Rectangle {
                                                        visible: index > 0
                                                        width: 1
                                                        height: parent.height
                                                        anchors.left: parent.left
                                                        z: 1
                                                        color: "#0b0c10"
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Percentage stays below its thin activity line so the
                                    // quota title and reset remain a single compact heading.
                                    PlasmaComponents.Label {
                                        visible: modelData.usageKnown !== false
                                        text: root.formatUsedPercent(
                                            modelData.percentLeft,
                                            modelData.usageKnown,
                                            !!(modelData.segments && modelData.segments.length),
                                            modelData.precisePercent === true)
                                        color: root.metricAccent(modelData.percentLeft, modelData.usageKnown)
                                        font.family: root.designFont
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        Layout.topMargin: 1
                                    }

                                    // Color + text legend: interpretation must not rely on color alone.
                                    // Flow wraps safely in a narrow popup without truncating items.
                                    Flow {
                                        id: segmentLegendFlow
                                        visible: !!(modelData.segmentLegendItems
                                            && modelData.segmentLegendItems.length > 0)
                                        Layout.fillWidth: true
                                        spacing: 10
                                        flow: Flow.LeftToRight

                                        readonly property var legendItems: modelData.segmentLegendItems || []

                                        Repeater {
                                            model: segmentLegendFlow.legendItems

                                            delegate: Row {
                                                spacing: 6

                                                Rectangle {
                                                    width: 8
                                                    height: 8
                                                    radius: 4
                                                    color: root.segmentColor(modelData.title, index)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                PlasmaComponents.Label {
                                                    text: (modelData.text || "")
                                                        + (index < segmentLegendFlow.legendItems.length - 1
                                                            ? " ·" : "")
                                                    color: root.textColor
                                                    font.family: root.designFont
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    lineHeight: 1.4
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }
                                    }

                                    PlasmaComponents.Label {
                                        visible: !!(modelData.detail && modelData.detail.length > 0)
                                        text: modelData.detail || ""
                                        color: root.quietColor
                                        font.family: root.designFont
                                        font.pixelSize: 12
                                        lineHeight: 1.4
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            ColumnLayout {
                                visible: root.popupState.hasEntry
                                    && !root.activeEntry.errorMessage
                                    && root.activeEntry.creditsRemaining !== null
                                    && root.activeEntry.creditsRemaining !== undefined
                                    && root.activeEntry.creditsRemaining > 0
                                Layout.fillWidth: true
                                spacing: 14

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: "#22252f"
                                }

                                RowLayout {
                                    Layout.fillWidth: true

                                    PlasmaComponents.Label {
                                        text: i18n("Credits")
                                        color: root.textColor
                                        font.family: root.designFont
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }

                                    PlasmaComponents.Label {
                                        text: root.formatCredits(root.activeEntry.creditsRemaining)
                                        color: root.textColor
                                        font.family: root.designFont
                                        font.pixelSize: 26
                                        font.weight: Font.ExtraBold
                                    }
                                }

                                PlasmaComponents.Label {
                                    visible: !!(root.showEmailInWidget && root.activeEntry.account)
                                    text: root.activeEntry.account || ""
                                    color: root.quietColor
                                    font.family: root.designFont
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            ColumnLayout {
                                visible: root.popupState.hasEntry
                                    && !root.activeEntry.errorMessage
                                    && root.activeEntry.extraUsage !== null
                                    && root.activeEntry.extraUsage !== undefined
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: "#22252f"
                                }

                                RowLayout {
                                    Layout.fillWidth: true

                                    PlasmaComponents.Label {
                                        text: i18n("Extra usage")
                                        color: root.textColor
                                        font.family: root.designFont
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }

                                    PlasmaComponents.Label {
                                        text: root.formatExtraUsageValue(root.activeEntry.extraUsage)
                                        color: root.textColor
                                        font.family: root.designFont
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            ColumnLayout {
                                visible: root.popupState.hasEntry
                                    && !root.activeEntry.errorMessage
                                    && root.activeEntry.bankedResetCount > 0
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: "#22252f"
                                }

                                RowLayout {
                                    Layout.fillWidth: true

                                    PlasmaComponents.Label {
                                        text: i18n("Banked resets")
                                        color: root.textColor
                                        font.family: root.designFont
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }

                                    PlasmaComponents.Label {
                                        text: root.formatCredits(root.activeEntry.bankedResetCount)
                                        color: root.textColor
                                        font.family: root.designFont
                                        font.pixelSize: 26
                                        font.weight: Font.ExtraBold
                                    }
                                }

                                PlasmaComponents.Label {
                                    text: root.formatResetTimes(root.activeEntry.bankedResetExpiresAt)
                                    visible: text.length > 0
                                    color: root.quietColor
                                    font.family: root.designFont
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }

                            ColumnLayout {
                                visible: !!(root.showCostSummary
                                    && root.popupState.hasEntry
                                    && root.activeEntry.costSummary
                                    && root.costSummaryRows(root.activeEntry.costSummary).length > 0)
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: "#22252f"
                                }

                                PlasmaComponents.Label {
                                    text: i18n("Cost")
                                    color: root.textColor
                                    font.family: root.designFont
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                }

                                Repeater {
                                    model: root.costSummaryRows(root.activeEntry.costSummary)

                                    delegate: RowLayout {
                                        Layout.fillWidth: true

                                        PlasmaComponents.Label {
                                            text: modelData.label
                                            color: root.mutedColor
                                            font.family: root.designFont
                                            font.pixelSize: 12
                                            Layout.fillWidth: true
                                        }

                                        PlasmaComponents.Label {
                                            text: modelData.value
                                            color: root.textColor
                                            font.family: root.designFont
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: 250
                                        }
                                    }
                                }

                                PlasmaComponents.Label {
                                    visible: !!(root.activeEntry.costSummary
                                        && root.activeEntry.costSummary.source
                                        && root.activeEntry.costSummary.source.length > 0)
                                    text: root.activeEntry.costSummary
                                        && root.activeEntry.costSummary.source === "local"
                                        ? i18n("Local token-cost estimate")
                                        : i18n("Source: %1", root.activeEntry.costSummary
                                            ? root.activeEntry.costSummary.source : "")
                                    color: root.quietColor
                                    font.family: root.designFont
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            ColumnLayout {
                                visible: !!(root.popupState.hasEntry
                                    && root.activeEntry.dashboardSummary
                                    && root.activeEntry.dashboardSummary.length > 0)
                                Layout.fillWidth: true
                                spacing: 6

                                PlasmaComponents.Label {
                                    text: i18n("Dashboard")
                                    color: root.textColor
                                    font.family: root.designFont
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                }

                                Repeater {
                                    model: root.activeEntry.dashboardSummary || []

                                    delegate: PlasmaComponents.Label {
                                        text: modelData
                                        color: root.quietColor
                                        font.family: root.designFont
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            ColumnLayout {
                                visible: root.activeIsEmpty(root.activeEntry)
                                Layout.fillWidth: true
                                Layout.topMargin: 20
                                spacing: 4

                                PlasmaComponents.Label {
                                    text: i18n("No usage reported")
                                    color: root.mutedColor
                                    font.family: root.designFont
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                }

                                PlasmaComponents.Label {
                                    text: i18n("Waiting for this provider to check in.")
                                    color: root.quietColor
                                    font.family: root.designFont
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                }
                            }

                            PlasmaComponents.Label {
                                visible: root.showCostSummary
                                    && root.costErrorMessage.length > 0
                                    && root.popupState.hasEntry
                                    && root.activeEntry.costSummaryOwner === true
                                    && (!root.activeEntry.costSummary)
                                text: root.costErrorMessage
                                color: root.quietColor
                                font.family: root.designFont
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            Item {
                id: localModelsContent
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedPopupTab === "local"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    anchors.topMargin: 15
                    anchors.bottomMargin: 6
                    spacing: 8

                    RowLayout {
                        visible: false
                        Layout.fillWidth: true
                        Layout.preferredHeight: 0
                        spacing: 9

                        Kirigami.Icon {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            source: "cpu"
                            color: root.textColor
                        }

                        PlasmaComponents.Label {
                            text: i18n("Local models")
                            color: root.textColor
                            font.family: root.designFont
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.Label {
                            text: i18n("%1 loaded", root.localModels.filter(function(item) {
                                return item.state === "active" || item.state === "loaded"
                            }).length)
                            color: root.mutedColor
                            font.family: root.designFont
                            font.pixelSize: 11
                        }

                        QQC2.ToolButton {
                            width: 28
                            height: 28
                            enabled: !root.localModelsLoading
                            text: i18n("Check local models now")
                            display: QQC2.AbstractButton.IconOnly
                            Accessible.name: text
                            onClicked: root.refreshLocalModels()
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: text
                            contentItem: Kirigami.Icon {
                                source: "view-refresh"
                                color: parent.enabled ? root.mutedColor : root.quietColor
                            }
                        }
                    }

                    PlasmaComponents.Label {
                        visible: root.localModelsError.length > 0
                        Layout.fillWidth: true
                        text: root.localModelsError
                        color: root.errorColor
                        font.family: root.designFont
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    QQC2.ScrollView {
                        id: localModelsScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.maximumHeight: 340
                        clip: true
                        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                        ListView {
                            id: localModelsList
                            width: localModelsScroll.availableWidth
                            contentWidth: width
                            model: root.localModels
                            spacing: 2
                            clip: true
                            flickableDirection: Flickable.VerticalFlick
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool groupStart: index === 0
                                    || root.localModels[index - 1].kind !== modelData.kind
                                width: localModelsList.width
                                height: groupStart ? 72 : 52
                                radius: 10
                                color: "transparent"
                                border.width: 0
                                opacity: modelData.state === "installed" ? 0.58 : 1

                                RowLayout {
                                    visible: parent.groupStart
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.topMargin: 5
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 7
                                    Rectangle {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        radius: 6
                                        color: root.localKindColor(modelData.kind) + "1f"
                                        PlasmaComponents.Label {
                                            anchors.centerIn: parent
                                            text: root.localKindGlyph(modelData.kind)
                                            color: root.localKindColor(modelData.kind)
                                            font.family: "monospace"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                    }
                                    PlasmaComponents.Label {
                                        text: root.localKindText(modelData.kind).toUpperCase()
                                        color: root.quietColor
                                        font.family: root.designFont
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.8
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 1
                                        color: "#20232d"
                                    }
                                    PlasmaComponents.Label {
                                        text: root.localKindCount(modelData.kind)
                                        color: "#565b68"
                                        font.family: root.designFont
                                        font.pixelSize: 9
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    anchors.topMargin: parent.groupStart ? 20 : 0
                                    spacing: 8

                                    Rectangle {
                                        Layout.preferredWidth: 7
                                        Layout.preferredHeight: 7
                                        radius: 4
                                        color: modelData.state === "active" ? root.goodColor
                                            : modelData.state === "loaded" ? root.mutedColor
                                            : modelData.state === "installed" ? root.quietColor : root.warningColor
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        PlasmaComponents.Label {
                                            text: modelData.name
                                            color: root.textColor
                                            font.family: "monospace"
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        PlasmaComponents.Label {
                                        text: root.localModelMeta(modelData)
                                            color: root.quietColor
                                            font.family: root.designFont
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Item {
                                        Layout.preferredWidth: 72
                                        Layout.preferredHeight: 22
                                        visible: modelData.state === "active" || modelData.state === "loaded"
                                        Canvas {
                                            id: localSparkCanvas
                                            anchors.fill: parent
                                            onPaint: {
                                                var context = getContext("2d")
                                                context.clearRect(0, 0, width, height)
                                                context.strokeStyle = modelData.state === "active" ? root.goodColor : "#2f333d"
                                                context.lineWidth = 1.4
                                                context.beginPath()
                                                var values = root.localModelHistory[modelData.id] || []
                                                if (modelData.state === "loaded" || values.length < 2) {
                                                    context.setLineDash([2, 3])
                                                    context.moveTo(0, height / 2)
                                                    context.lineTo(width, height / 2)
                                                } else {
                                                    var maximum = Math.max.apply(Math, values.concat([1]))
                                                    for (var sample = 0; sample < values.length; sample++) {
                                                        var x = width * sample / Math.max(1, values.length - 1)
                                                        var y = height - 2 - ((height - 4) * values[sample] / maximum)
                                                        if (sample === 0) context.moveTo(x, y)
                                                        else context.lineTo(x, y)
                                                    }
                                                }
                                                context.stroke()
                                                context.setLineDash([])
                                            }
                                            Connections { target: root; function onLocalModelHistoryChanged() { localSparkCanvas.requestPaint() } }
                                        }
                                    }

                                    PlasmaComponents.Label {
                                        Layout.preferredWidth: modelData.state === "installed" ? 130 : 58
                                        text: modelData.state === "active" ? root.localMetricText(modelData)
                                            : modelData.state === "loaded" ? i18n("Idle")
                                                : modelData.state === "installed" ? i18n("Unmounted")
                                                    : root.localStateText(modelData.state)
                                        color: modelData.state === "active" ? root.textColor : root.quietColor
                                        font.family: root.designFont
                                        font.pixelSize: 10
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }

                                    QQC2.ToolButton {
                                        width: 26
                                        height: 26
                                        visible: modelData.capabilities && (modelData.capabilities.unmount || modelData.capabilities.mount)
                                        enabled: !root.localModelsLoading && modelData.state !== "active"
                                            && ((modelData.state === "installed" && modelData.capabilities.mount)
                                                || (modelData.state !== "installed" && modelData.capabilities.unmount))
                                        text: modelData.state === "installed" && modelData.capabilities.mount ? i18n("Mount") : i18n("Unmount")
                                        display: QQC2.AbstractButton.IconOnly
                                        Accessible.name: text
                                        onClicked: root.localModelAction(modelData.state === "installed" ? "mount" : "unmount",
                                            modelData.runtime, modelData.id, false)
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: modelData.state === "active" ? i18n("Unavailable while active") : text
                                        contentItem: Kirigami.Icon {
                                            source: modelData.state === "installed" && modelData.capabilities.mount ? "go-up" : "media-eject"
                                            color: parent.enabled ? root.mutedColor : root.quietColor
                                        }
                                    }
                                }
                            }

                            footer: Column {
                                width: localModelsList.width
                                spacing: 6
                                Item { width: 1; height: 8 }
                                Repeater {
                                    model: root.localRuntimes
                                    delegate: RowLayout {
                                        required property var modelData
                                        width: localModelsList.width
                                        visible: modelData.capabilities && (modelData.capabilities.releaseRuntime
                                            || modelData.capabilities.stopRuntime)
                                        PlasmaComponents.Label {
                                            text: modelData.stopImpact || modelData.releaseWarning
                                                || (modelData.id + " · " + i18n("runtime-wide control"))
                                            color: root.quietColor
                                            font.family: root.designFont
                                            font.pixelSize: 10
                                            Layout.fillWidth: true
                                        }
                                        QQC2.Button {
                                            visible: modelData.capabilities && modelData.capabilities.releaseRuntime
                                            text: i18n("Release runtime")
                                            enabled: !root.localModelsLoading
                                            onClicked: { localReleaseDialog.runtime = modelData.id; localReleaseDialog.warning = modelData.releaseWarning || ""; localReleaseDialog.open() }
                                        }
                                        QQC2.Button {
                                            visible: modelData.capabilities && modelData.capabilities.stopRuntime
                                            text: i18n("Stop runtime")
                                            enabled: !root.localModelsLoading
                                            onClicked: {
                                                localStopDialog.runtime = modelData.id
                                                localStopDialog.impact = modelData.stopImpact || modelData.releaseWarning || ""
                                                localStopDialog.open()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    PlasmaComponents.Label {
                        visible: !root.localModelsLoading && root.localModels.length === 0 && root.localModelsError.length === 0
                        Layout.fillWidth: true
                        text: i18n("No installed local models in configured roots.")
                        color: root.mutedColor
                        font.family: root.designFont
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            QQC2.Dialog {
                id: localReleaseDialog
                property string runtime: ""
                property string warning: ""
                modal: true
                title: i18n("Release runtime memory?")
                standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
                onAccepted: root.localModelAction("release", runtime, "", true)
                contentItem: Item {
                    implicitWidth: 300
                    implicitHeight: localReleaseWarning.implicitHeight

                    PlasmaComponents.Label {
                        id: localReleaseWarning
                        width: parent.width
                        text: localReleaseDialog.warning.length > 0 ? localReleaseDialog.warning : i18n("This affects every resident model in this runtime.")
                        wrapMode: Text.WordWrap
                        color: root.mutedColor
                    }
                }
            }

            QQC2.Dialog {
                id: localStopDialog
                property string runtime: ""
                property string impact: ""
                modal: true
                title: i18n("Stop local runtime?")
                standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
                onAccepted: root.localModelAction("stop", runtime, "", true)
                contentItem: Item {
                    implicitWidth: 300
                    implicitHeight: localStopImpact.implicitHeight

                    PlasmaComponents.Label {
                        id: localStopImpact
                        width: parent.width
                        text: localStopDialog.impact.length > 0
                            ? localStopDialog.impact
                            : i18n("This stops the configured local service and releases all of its runtime memory.")
                        wrapMode: Text.WordWrap
                        color: root.mutedColor
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 88

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 16
                    anchors.bottomMargin: 12
                    radius: 12
                    color: "#0f1015"
                    border.color: "#20232b"
                    border.width: 1
                    clip: true

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 9
                        spacing: 8

                        PlasmaComponents.Label {
                            text: i18n("IN THE PANEL")
                            color: root.quietColor
                            font.family: root.designFont
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: "#20232d"
                        }

                        PlasmaComponents.Label {
                            text: i18n("compact view")
                            color: "#565b68"
                            font.family: root.designFont
                            font.pixelSize: 10
                        }
                    }

                    CompactStrip {
                        id: previewStrip
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.bottomMargin: 4
                        blocks: root.compactResult().blocks || []
                        preview: true
                        activeLocalCount: root.localModels.filter(function(item) { return item.state === "active" }).length
                    }

                    PlasmaComponents.Label {
                        visible: !root.compactResult().blocks || root.compactResult().blocks.length === 0
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.bottomMargin: 10
                        text: root.panelText()
                        color: root.mutedColor
                        font.family: root.designFont
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // The terminal control opens an overlapping local-model inspector. The
        // provider view remains visible behind it, matching the dedicated AI
        // CLI Control surface instead of turning the control into a menu only.
        QQC2.Popup {
            id: aiControlPopup
            parent: full
            x: Math.max(12, full.width - width - 22)
            y: 58
            width: 340
            height: 390
            padding: 0
            modal: false
            focus: true
            closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
            onOpened: root.refreshLocalModels()

            background: Rectangle {
                radius: 14
                color: "#131419"
                border.color: "#2a2d37"
                border.width: 1
            }

            contentItem: ColumnLayout {
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 13
                    Layout.rightMargin: 10
                    Layout.topMargin: 10
                    Layout.bottomMargin: 9
                    spacing: 8
                    PlasmaComponents.Label {
                        text: i18n("Local models")
                        color: root.textColor
                        font.family: root.designFont
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: i18n("%1 in memory", root.localModels.filter(function(item) { return item.state === "active" || item.state === "loaded" }).length)
                        color: root.quietColor
                        font.family: root.designFont
                        font.pixelSize: 10
                    }
                    QQC2.ToolButton {
                        width: 26; height: 26
                        text: i18n("AI CLI actions")
                        display: QQC2.AbstractButton.IconOnly
                        Accessible.name: text
                        onClicked: aiControlMenu.open()
                        contentItem: Kirigami.Icon { source: "application-menu"; color: root.mutedColor }
                        background: Rectangle { radius: 8; color: parent.hovered ? "#20232d" : "transparent" }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#20232b" }

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 6
                    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                    ListView {
                        id: aiControlModelsList
                        width: parent.width
                        contentWidth: width
                        model: root.localModels
                        clip: true
                        flickableDirection: Flickable.VerticalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Item {
                            required property var modelData
                            readonly property bool groupStart: index === 0 || root.localModels[index - 1].kind !== modelData.kind
                            width: aiControlModelsList.width
                            height: groupStart ? 70 : 50

                            RowLayout {
                                visible: parent.groupStart
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 3
                                anchors.rightMargin: 4
                                anchors.topMargin: 8
                                spacing: 6
                                Rectangle {
                                    Layout.preferredWidth: 18; Layout.preferredHeight: 18; radius: 5
                                    color: root.localKindColor(modelData.kind) + "1f"
                                    PlasmaComponents.Label { anchors.centerIn: parent; text: root.localKindGlyph(modelData.kind); color: root.localKindColor(modelData.kind); font.family: "monospace"; font.pixelSize: 9 }
                                }
                                PlasmaComponents.Label { text: root.localKindText(modelData.kind).toUpperCase(); color: root.quietColor; font.family: root.designFont; font.pixelSize: 9; font.weight: Font.Bold }
                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#20232d" }
                                PlasmaComponents.Label { text: root.localKindCount(modelData.kind); color: "#565b68"; font.family: root.designFont; font.pixelSize: 9 }
                            }

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 5
                                anchors.rightMargin: 3
                                anchors.bottomMargin: 6
                                spacing: 7
                                Rectangle { Layout.preferredWidth: 7; Layout.preferredHeight: 7; radius: 4; color: modelData.state === "active" ? root.goodColor : (modelData.state === "loaded" ? root.mutedColor : "transparent"); border.width: modelData.state === "installed" ? 1 : 0; border.color: "#33384d" }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 1
                                    PlasmaComponents.Label { text: modelData.name; color: modelData.state === "installed" ? "#565b68" : root.textColor; font.family: "monospace"; font.pixelSize: 10; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    PlasmaComponents.Label { text: root.localModelMeta(modelData); color: root.quietColor; font.family: root.designFont; font.pixelSize: 8; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                Item {
                                    Layout.preferredWidth: 72; Layout.preferredHeight: 20
                                    visible: modelData.state === "active" || modelData.state === "loaded"
                                    Canvas {
                                        id: aiControlSparkCanvas
                                        anchors.fill: parent
                                        onPaint: {
                                            var context = getContext("2d")
                                            context.clearRect(0, 0, width, height)
                                            context.strokeStyle = modelData.state === "active" ? root.goodColor : "#2f333d"
                                            context.lineWidth = 1.3
                                            context.beginPath()
                                            var values = root.localModelHistory[modelData.id] || []
                                            if (modelData.state === "loaded" || values.length < 2) {
                                                context.setLineDash([2, 3])
                                                context.moveTo(0, height / 2)
                                                context.lineTo(width, height / 2)
                                            } else {
                                                var maximum = Math.max.apply(Math, values.concat([1]))
                                                for (var sample = 0; sample < values.length; sample++) {
                                                    var x = width * sample / Math.max(1, values.length - 1)
                                                    var y = height - 2 - ((height - 4) * values[sample] / maximum)
                                                    if (sample === 0) context.moveTo(x, y)
                                                    else context.lineTo(x, y)
                                                }
                                            }
                                            context.stroke()
                                            context.setLineDash([])
                                        }
                                        Connections { target: root; function onLocalModelHistoryChanged() { aiControlSparkCanvas.requestPaint() } }
                                    }
                                }
                                Row {
                                    Layout.preferredWidth: 58
                                    Layout.preferredHeight: 20
                                    visible: modelData.state === "active"
                                    spacing: 2
                                    layoutDirection: Qt.RightToLeft
                                    PlasmaComponents.Label { text: modelData.metric && modelData.metric.unit ? modelData.metric.unit : ""; color: root.quietColor; font.family: root.designFont; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                                    PlasmaComponents.Label { text: modelData.metric && typeof modelData.metric.value === "number" ? root.formatNumber(modelData.metric.value) : "—"; color: root.textColor; font.family: root.designFont; font.pixelSize: 11; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                                }
                                PlasmaComponents.Label { Layout.preferredWidth: modelData.state === "installed" ? 78 : 58; visible: modelData.state !== "active"; text: modelData.state === "loaded" ? i18n("Idle") : i18n("Unmounted"); color: root.quietColor; font.family: root.designFont; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                                QQC2.ToolButton {
                                    width: 26; height: 26
                                    visible: modelData.capabilities && (modelData.capabilities.unmount || modelData.capabilities.mount)
                                    enabled: !root.localModelsLoading && modelData.state !== "active" && ((modelData.state === "installed" && modelData.capabilities.mount) || (modelData.state !== "installed" && modelData.capabilities.unmount))
                                    text: modelData.state === "installed" ? i18n("Mount") : i18n("Unmount")
                                    display: QQC2.AbstractButton.IconOnly
                                    Accessible.name: text
                                    onClicked: root.localModelAction(modelData.state === "installed" ? "mount" : "unmount", modelData.runtime, modelData.id, false)
                                    contentItem: Kirigami.Icon { source: modelData.state === "installed" ? "go-up" : "media-eject"; color: parent.enabled ? root.mutedColor : root.quietColor }
                                    background: Rectangle { radius: 8; color: parent.hovered ? "#20232d" : "transparent" }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#20232b" }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12; Layout.rightMargin: 10
                    Layout.topMargin: 7; Layout.bottomMargin: 7
                    Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: root.goodColor }
                    PlasmaComponents.Label { text: root.localModelsLoading ? i18n("Checking…") : i18n("Checked just now"); color: root.quietColor; font.family: root.designFont; font.pixelSize: 9 }
                    Item { Layout.fillWidth: true }
                    QQC2.Button { text: i18n("Check now"); enabled: !root.localModelsLoading; onClicked: root.refreshLocalModels() }
                }
            }
        }
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            usageWatchdog.stop()
            // Productive presence transition decides the missing-engine flag and
            // cache-preservation contract before any other path.
            var presence = root.applyEngineResponse({
                engineNotInstalled: root.engineNotInstalled,
                entries: root.entries,
                lastGoodEntries: root.lastGoodEntries
            }, data.stdout || "", data.stderr || "", data["exit code"] || 0)
            if (presence.engineNotInstalled) {
                if (root.activeFallbackCommand.length > 0) {
                    root.pendingCandidates.unshift({
                        provider: root.activeProvider,
                        source: root.activeSource,
                        command: root.activeFallbackCommand,
                        replaceAll: root.activeQueryReplacesAll,
                        startupRetry: root.activeStartupRetry
                    })
                    root.tryNextCandidate()
                    return
                }
                // No fallback left: show the setup card on full seeds only.
                if (root.activeQueryReplacesAll) {
                    root.markEngineNotInstalled()
                    return
                }
                var missingError = data.stderr || data.stdout || i18n("Command not found")
                if (root.handleUsageFailure(missingError, "")) {
                    return
                }
                var missingEntry = root.normalizeEntry({
                    provider: root.activeProvider,
                    source: root.activeSource,
                    error: {
                        kind: "runtime",
                        message: missingError
                    }
                })
                root.applyUsageEntries([missingEntry])
                root.tryNextCandidate()
                return
            }
            // Any normal engine response clears the setup card before handling,
            // so ordinary errors are never covered by the missing-engine UI.
            root.engineNotInstalled = presence.engineNotInstalled
            if (data["exit code"] && data["exit code"] !== 0 && !(data.stdout || "").length) {
                var runtimeError = data.stderr || i18n("Exit code %1", data["exit code"])
                if (root.handleUsageFailure(runtimeError, "")) {
                    return
                }
                var errorEntry = root.normalizeEntry({
                    provider: root.activeProvider,
                    source: root.activeSource,
                    error: {
                        kind: "runtime",
                        message: runtimeError
                    }
                })
                root.applyUsageEntries([errorEntry])
                root.tryNextCandidate()
                return
            }
            var result = root.parsePayload(data.stdout || "")
            if (!result.ok) {
                var parseError = result.error + (result.detail ? ": " + result.detail : "")
                if (root.handleUsageFailure(parseError, "")) {
                    return
                }
                var parseErrorEntry = root.normalizeEntry({
                    provider: root.activeProvider,
                    source: root.activeSource,
                    error: { kind: "runtime", message: parseError }
                })
                root.applyUsageEntries([parseErrorEntry])
                root.tryNextCandidate()
                return
            }
            if (root.scheduleStartupProviderRetries(result.entries)) {
                return
            }
            root.applyUsageEntries(result.entries)
            root.tryNextCandidate()
        }
    }

    Plasma5Support.DataSource {
        id: costExecutable
        engine: "executable"
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            root.costLoading = false
            if (root.commandWasNotFound(data)) {
                if (root.startNextCostCandidate()) {
                    root.costLoading = true
                    return
                }
                root.costErrorMessage = data.stderr || data.stdout || i18n("Cost scan failed: command not found")
                root.costSummaries = ({})
                root.applyCostSummaries()
                return
            }
            if (data["exit code"] && data["exit code"] !== 0 && !(data.stdout || "").length) {
                root.costErrorMessage = data.stderr || i18n("Cost scan failed with exit code %1", data["exit code"])
                root.costSummaries = ({})
                root.applyCostSummaries()
                return
            }
            var result = root.parseCostPayload(data.stdout || "")
            if (!result.ok) {
                root.costErrorMessage = result.error
                root.costSummaries = ({})
                root.applyCostSummaries()
                return
            }
            root.costErrorMessage = ""
            root.costSummaries = result.summaries
            root.applyCostSummaries()
        }
    }

    Plasma5Support.DataSource {
        id: aiControlExecutable
        engine: "executable"
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            if (data["exit code"] && data["exit code"] !== 0) {
                root.aiControlError = (data.stderr || data.stdout || i18n("Exit code %1", data["exit code"])).trim()
            } else {
                root.aiControlError = ""
            }
        }
    }

    // local-ai owns runtime probing and JSON normalization. The widget never
    // parses ps output or talks to a model server directly.
    Plasma5Support.DataSource {
        id: localAiExecutable
        engine: "executable"
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            root.localModelsLoading = false
            localModelsWatchdog.stop()
            var text = String(data.stdout || "").trim()
            if (text.length === 0) {
                root.localModelsError = String(data.stderr || i18n("No output from local model monitor")).trim()
                return
            }
            try {
                var payload = JSON.parse(text)
                if (payload.ok === false) {
                    root.localModelsError = payload.error || i18n("Local model action failed")
                    return
                }
                root.localModelsError = ""
                root.applyLocalInventory(payload.inventory || payload)
            } catch (error) {
                root.localModelsError = i18n("Invalid local model response")
            }
        }
    }

    Timer {
        id: usageWatchdog
        interval: 120000
        repeat: false
        onTriggered: root.cancelUsageRefresh()
    }

    Timer {
        id: startupRetryTimer
        interval: 5000
        repeat: false
        onTriggered: {
            root.startupRetryPending = false
            root.beginUsageRefresh(root.pendingCandidates, false)
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

    Timer {
        id: claudeRefreshTimer
        interval: root.claudeRefreshSeconds * 1000
        repeat: true
        running: true
        onTriggered: root.refreshClaude()
    }

    Timer {
        id: localModelsRefreshTimer
        interval: root.localModelsRefreshSeconds * 1000
        repeat: true
        running: root.expanded && root.selectedPopupTab === "local"
        onTriggered: root.refreshLocalModels()
    }

    Timer {
        id: localModelsWatchdog
        interval: 12000
        repeat: false
        onTriggered: {
            root.localModelsLoading = false
            root.localModelsError = i18n("Local model monitor timed out. Try refresh again.")
        }
    }

    onRefreshSecondsChanged: {
        refreshTimer.restart()
        refresh()
    }

    onClaudeRefreshSecondsChanged: claudeRefreshTimer.restart()
    onLocalModelsRefreshSecondsChanged: localModelsRefreshTimer.restart()

    onCodexbarCommandChanged: {
        cancelUsageRefresh()
        initialUsageSeedPending = true
        refresh()
    }
    onAiControlCommandChanged: aiControlError = ""
    onSelectedSourceChanged: {
        cancelUsageRefresh()
        initialUsageSeedPending = true
        refresh()
    }
    onShowCostSummaryChanged: refreshCost()
    onShowCreditsInPanelChanged: panelText()
    onShowUsedPercentInPanelChanged: panelText()
    onShowProviderInPanelChanged: panelText()
    onEntriesChanged: {
        var selection = ProviderLogic.activeEntryData(entries, selectedEntryKey)
        if (selectedEntryKey !== selection.selectionKey) {
            selectedEntryKey = selection.selectionKey
        }
    }

    Component.onCompleted: {
        const configureAction = Plasmoid.internalAction("configure")
        if (configureAction) {
            configureAction.visible = false
        }
        if (Plasmoid.configuration.sourceDefaultMigrationDone !== true) {
            if (Plasmoid.configuration.source && Plasmoid.configuration.source !== "detect") {
                Plasmoid.configuration.sourceDefault = Plasmoid.configuration.source
            }
            Plasmoid.configuration.sourceDefaultMigrationDone = true
        }
        var migration = ProviderLogic.migrateLegacyProvider(
            Plasmoid.configuration.provider,
            Plasmoid.configuration.compactProviderOrder,
            defaultCompactProviderOrder,
            Plasmoid.configuration.compactProviderMigrationDone === true)
        if (migration.writeOrder) {
            Plasmoid.configuration.compactProviderOrder = migration.order
        }
        if (migration.writeDone) {
            Plasmoid.configuration.compactProviderMigrationDone = true
        }
    }
}
