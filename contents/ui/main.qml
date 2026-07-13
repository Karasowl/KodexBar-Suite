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
    property string generatedAt: ""
    property bool loading: false
    property bool costLoading: false
    property string costErrorMessage: ""
    property var costSummaries: ({})
    property string codexbarCommand: Plasmoid.configuration.codexbarCommand || "codexbar"
    property string aiControlCommand: Plasmoid.configuration.aiControlCommand || "ai"
    property string aiControlError: ""
    property string selectedSource: Plasmoid.configuration.source || "detect"
    property string selectedEntryKey: ""
    property string activeProvider: ""
    property string activeSource: selectedSource
    property var pendingCandidates: []
    property var failedCandidates: []
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

    Plasmoid.contextualActions: [
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

    preferredRepresentation: compactRepresentation
    toolTipMainText: "KodexBar"
    toolTipSubText: {
        if (aiControlError.length > 0) {
            return i18n("AI CLI Control: %1", aiControlError)
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
        return ProviderLogic.composeCompactBlocks(entries, {
            providerOrder: compactProviderOrder,
            quotaSelection: compactQuotaSelection,
            showProvider: showProviderInPanel,
            showUsed: showUsedPercentInPanel,
            showCredits: showCreditsInPanel,
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

    function formatUsedPercent(percentLeft, usageKnown) {
        if (usageKnown === false) {
            return i18n("Reset only")
        }
        var used = usedPercent(percentLeft)
        if (used === null) {
            return i18n("Unavailable")
        }
        return i18n("%1% used", Math.round(used))
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

    function activeStatusColor(entry) {
        if (!entry || !entry.provider) {
            return loading ? warningColor : quietColor
        }
        if (entry.errorMessage) {
            return errorColor
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
        return (!entry.rows || entry.rows.length === 0)
            && (entry.creditsRemaining === null || entry.creditsRemaining === undefined)
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

    function commandLine(provider, source) {
        var args = ProviderLogic.usageArguments(provider, source, includeStatus)
        var command = shellQuote(codexbarCommand)
        for (var i = 0; i < args.length; i++) {
            command += " " + shellQuote(args[i])
        }
        return command
    }

    function costCommandLine() {
        var args = ProviderLogic.costArguments()
        var command = shellQuote(codexbarCommand)
        for (var i = 0; i < args.length; i++) {
            command += " " + shellQuote(args[i])
        }
        return command
    }

    function aiControlCommandLine(arguments, showTerminal) {
        var command = showTerminal ? "konsole --hold -e" : ""
        command += (command.length > 0 ? " " : "") + shellQuote(aiControlCommand)
        for (var i = 0; i < arguments.length; i++) {
            command += " " + shellQuote(arguments[i])
        }
        return command
    }

    function launchAiControl(arguments, showTerminal) {
        aiControlError = ""
        aiControlExecutable.connectedSources = []
        aiControlExecutable.connectSource(aiControlCommandLine(arguments || [], showTerminal === true))
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
        refreshCost()
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
        costExecutable.connectSource(costCommandLine())
    }

    function candidateList() {
        return ProviderLogic.acquisitionCandidates(selectedSource)
    }

    function tryNextCandidate() {
        if (pendingCandidates.length === 0) {
            loading = false
            entries = failedCandidates.slice()
            generatedAt = new Date().toLocaleString(Qt.locale(), Locale.ShortFormat)
            if (entries.length === 0) {
                errorMessage = i18n("No usable CodexBar provider found")
                errorDetail = i18n("Configure at least one provider in CodexBar or choose a compatible source.")
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
        if (String(provider || "").toLowerCase() !== "codex") {
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
        var normalizedWindows = ProviderLogic.normalizeUsageWindows(entry.provider, primary, secondary)
        primary = normalizedWindows.primary
        secondary = normalizedWindows.secondary
        var providerCost = usage.providerCost && typeof usage.providerCost === "object" ? usage.providerCost : null
        var status = entry.status && typeof entry.status === "object" ? entry.status : null
        var rows = []
        var windows = [
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
                rows.push(standardRow)
            }
        }
        var extraRateWindows = usage.extraRateWindows && usage.extraRateWindows.length ? usage.extraRateWindows : []
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
        return {
            provider: entry.provider,
            name: providerName(entry.provider),
            version: entry.version,
            source: entry.source,
            account: entry.account || usage.accountEmail || identity.accountEmail || "",
            plan: usage.loginMethod || identity.loginMethod || dashboard.accountPlan || "",
            primaryPercentLeft: displayPercentLeft(entry.provider, primary, secondary),
            compactPrimaryPercentLeft: knownPercentLeft(primary),
            primaryResetsAt: resetAt(primary),
            secondaryPercentLeft: knownPercentLeft(secondary),
            secondaryResetsAt: resetAt(secondary),
            tertiaryPercentLeft: knownPercentLeft(tertiary),
            tertiaryResetsAt: resetAt(tertiary),
            creditsRemaining: credits ? credits.remaining : (typeof dashboard.creditsRemaining === "number" ? dashboard.creditsRemaining : null),
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
            signedOut: false
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
                        visible: modelData.ordinal && modelData.ordinal.length > 0
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
        // Keep every provider on the same 520 by 560 design viewport. The
        // metric ScrollView owns overflow instead of resizing the popup.
        Layout.minimumHeight: 560
        Layout.maximumHeight: 560
        Layout.preferredHeight: 560

        Rectangle {
            id: popupCard
            anchors.fill: parent
            anchors.margins: 8
            radius: 20
            color: root.cardColor
            border.color: root.lineColor
            border.width: 1
            clip: true
        }

        ColumnLayout {
            anchors.fill: popupCard
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 74

                Rectangle {
                    width: 38
                    height: 38
                    radius: 11
                    x: 20
                    y: 18
                    color: root.accentColor

                    Image {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        source: Qt.resolvedUrl("../icons/providers/openai.svg")
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }

                Column {
                    x: 70
                    y: 19
                    spacing: 1

                    PlasmaComponents.Label {
                        text: "KodexBar"
                        color: root.textColor
                        font.family: root.designFont
                        font.pixelSize: 16
                        font.weight: Font.ExtraBold
                    }

                    PlasmaComponents.Label {
                        text: i18n("AI provider quotas")
                        color: root.mutedColor
                        font.family: root.designFont
                        font.pixelSize: 12
                    }
                }

                QQC2.ToolButton {
                    id: aiControlButton
                    width: 34
                    height: 34
                    anchors.right: refreshButton.left
                    anchors.rightMargin: 8
                    y: 19
                    text: i18n("AI CLI Control")
                    display: QQC2.AbstractButton.IconOnly
                    Accessible.name: text
                    onClicked: aiControlMenu.open()

                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text

                    contentItem: Item {
                        implicitWidth: 16
                        implicitHeight: 16

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: "applications-development"
                            color: aiControlButton.enabled ? root.mutedColor : root.quietColor
                        }
                    }

                    background: Rectangle {
                        radius: 10
                        color: root.raisedColor
                        border.color: parent.hovered ? root.accentColor : "#2b303c"
                        border.width: 1
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
                    width: 34
                    height: 34
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    y: 19
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
                        radius: 10
                        color: root.raisedColor
                        border.color: parent.hovered ? root.accentColor : "#2b303c"
                        border.width: 1
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 48

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    height: 44
                    radius: 13
                    color: root.surfaceColor
                    border.color: "#23262f"
                    border.width: 1

                    ListView {
                        id: providerTabs
                        anchors.fill: parent
                        anchors.margins: 4
                        orientation: ListView.Horizontal
                        spacing: 3
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentWidth > width
                        model: root.popupEntries

                        delegate: QQC2.Button {
                            readonly property bool selected: modelData.selectionKey === root.popupState.selectionKey
                            width: Math.max(104, Math.floor((providerTabs.width - 9) / Math.min(4, Math.max(1, providerTabs.count))))
                            height: 36
                            flat: true
                            text: modelData.tabLabel
                            onClicked: root.selectedEntryKey = modelData.selectionKey

                            contentItem: RowLayout {
                                spacing: 7

                                Item {
                                    Layout.fillWidth: true
                                }

                                Image {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    source: root.providerIconSource(modelData.provider)
                                    fillMode: Image.PreserveAspectFit
                                    opacity: parent.parent.selected ? 1 : 0.55
                                    smooth: true
                                }

                                PlasmaComponents.Label {
                                    text: modelData.tabLabel
                                    color: parent.parent.selected ? "#f2f3f8" : root.mutedColor
                                    font.family: root.designFont
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 104
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
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    anchors.topMargin: 15
                    anchors.bottomMargin: 6
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
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
                            text: root.popupState.hasEntry ? root.activeEntry.displayName : "KodexBar"
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
                                visible: (root.errorMessage.length > 0 && root.popupEntries.length === 0)
                                    || (root.popupState.hasEntry && root.activeEntry.errorMessage)
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
                                visible: !root.loading && root.popupEntries.length === 0 && root.errorMessage.length === 0
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
                                visible: root.popupState.hasEntry
                                    && root.activeEntry.statusIndicator
                                    && root.activeEntry.statusIndicator.length > 0
                                    && !root.activeEntry.errorMessage
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

                                        PlasmaComponents.Label {
                                            text: root.formatUsedPercent(modelData.percentLeft, modelData.usageKnown)
                                            color: root.metricAccent(modelData.percentLeft, modelData.usageKnown)
                                            font.family: root.designFont
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Rectangle {
                                        readonly property real used: root.usedPercent(modelData.percentLeft) || 0
                                        visible: modelData.usageKnown !== false
                                            && modelData.percentLeft !== null
                                            && modelData.percentLeft !== undefined
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 8
                                        radius: 4
                                        color: "#20232d"
                                        clip: true

                                        Rectangle {
                                            width: parent.width * parent.used / 100
                                            height: parent.height
                                            radius: 4
                                            color: root.metricAccent(modelData.percentLeft, modelData.usageKnown)
                                        }
                                    }

                                    PlasmaComponents.Label {
                                        visible: modelData.detail && modelData.detail.length > 0
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
                                    visible: root.showEmailInWidget && root.activeEntry.account
                                    text: root.activeEntry.account || ""
                                    color: root.quietColor
                                    font.family: root.designFont
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            ColumnLayout {
                                visible: root.showCostSummary
                                    && root.popupState.hasEntry
                                    && root.activeEntry.costSummary
                                    && root.costSummaryRows(root.activeEntry.costSummary).length > 0
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
                                    visible: root.activeEntry.costSummary
                                        && root.activeEntry.costSummary.source
                                        && root.activeEntry.costSummary.source.length > 0
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
                                visible: root.popupState.hasEntry
                                    && root.activeEntry.dashboardSummary
                                    && root.activeEntry.dashboardSummary.length > 0
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
                Layout.fillWidth: true
                Layout.preferredHeight: 78

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 8
                    anchors.bottomMargin: 14
                    radius: 13
                    color: "#0d0f14"
                    border.color: "#23262f"
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
            root.entries = ProviderLogic.attachProviderCostSummaries(result.entries, root.costSummaries)
        }
    }

    Plasma5Support.DataSource {
        id: costExecutable
        engine: "executable"
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            root.costLoading = false
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
    onAiControlCommandChanged: aiControlError = ""
    onSelectedSourceChanged: refresh()
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
