.pragma library

function providerId(value) {
    return String(value || "").trim().toLowerCase()
}

function normalizeProviderOrder(value) {
    var rawIds = String(value || "").split(",")
    var normalized = []
    var seen = {}
    for (var i = 0; i < rawIds.length; i++) {
        var id = providerId(rawIds[i])
        if (id.length === 0 || seen[id] === true) {
            continue
        }
        seen[id] = true
        normalized.push(id)
    }
    return normalized
}

function normalizeQuotaSelection(value) {
    return normalizeProviderOrder(value)
}

function acquisitionCandidates(source) {
    var normalizedSource = String(source || "detect").trim().toLowerCase() || "detect"
    return [{ provider: "", source: normalizedSource }]
}

function commandCandidates(configuredCommand) {
    var command = String(configuredCommand || "").trim()
    if (command.length === 0 || command === "codexbar" || command === "kodexbar-quotas") {
        return ["kodexbar-quotas", "codexbar"]
    }
    return [command]
}

function usageArguments(provider, source, includeStatus) {
    var args = ["usage", "--format", "json", "--json-only"]
    if (provider && provider !== "detect") {
        args.push("--provider", String(provider))
    }
    if (source && source !== "detect") {
        args.push("--source", String(source))
    }
    if (includeStatus === true) {
        args.push("--status")
    }
    return args
}

function costArguments() {
    return ["cost", "--format", "json", "--json-only"]
}

function normalizeCodexResetCredits(value) {
    var credits = value && typeof value === "object" ? value : {}
    var list = Array.isArray(credits.credits) ? credits.credits : []
    var expiresAt = []
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].expires_at) {
            expiresAt.push(String(list[i].expires_at))
        }
    }
    expiresAt.sort(function(left, right) {
        return new Date(left).getTime() - new Date(right).getTime()
    })
    return {
        availableCount: typeof credits.availableCount === "number" ? credits.availableCount : 0,
        expiresAt: expiresAt
    }
}

function providerAccountKey(entry) {
    var provider = providerId(entry && entry.provider)
    var account = String(entry && entry.account || "").trim().toLowerCase()
    return provider + "\u001f" + account
}

function copyEntry(entry) {
    var copy = {}
    for (var property in entry) {
        copy[property] = entry[property]
    }
    return copy
}

function cacheLastGoodEntries(previous, entries) {
    var cached = Array.isArray(previous) ? previous.slice() : []
    var incoming = Array.isArray(entries) ? entries : []
    for (var i = 0; i < incoming.length; i++) {
        var entry = incoming[i]
        if (!entry || entry.errorMessage) {
            continue
        }
        var key = providerAccountKey(entry)
        var replaced = false
        for (var j = 0; j < cached.length; j++) {
            if (providerAccountKey(cached[j]) === key) {
                cached[j] = copyEntry(entry)
                replaced = true
                break
            }
        }
        if (!replaced) {
            cached.push(copyEntry(entry))
        }
    }
    return cached
}

function providerIds(entries) {
    var list = Array.isArray(entries) ? entries : []
    var ids = []
    var seen = {}
    for (var i = 0; i < list.length; i++) {
        var id = providerId(list[i] && list[i].provider)
        if (id.length === 0 || id === "all" || seen[id] === true) {
            continue
        }
        seen[id] = true
        ids.push(id)
    }
    return ids
}

function isRetryableProviderError(entry) {
    if (!entry || !entry.errorMessage) {
        return false
    }
    if (entry.errorRetryable === true) {
        return true
    }
    if (entry.errorRetryable === false) {
        return false
    }
    var category = providerId(entry.errorCategory)
    if (["rate_limit", "authentication", "authorization", "entitlement", "permanent"].indexOf(category) !== -1) {
        return false
    }
    if (["network", "timeout", "invalid_response"].indexOf(category) !== -1) {
        return true
    }
    var message = String(entry.errorMessage)
    if (/\b429\b|rate[ -]?limit|unauthenti|forbidden|credential|sign(?:ed)?\s*out|entitlement|subscription|not\s+included|no\s+(?:available\s+)?fetch\s+strategy/i.test(message)) {
        return false
    }
    return /network|timed?\s*out|timeout|invalid\s+(?:json|response)|unexpected\s+(?:json|response)|empty\s+output|no\s+output/i.test(message)
}

function startupRetryProviderIds(entries, cachedEntries, alreadyRetried) {
    var incoming = Array.isArray(entries) ? entries : []
    var cached = Array.isArray(cachedEntries) ? cachedEntries : []
    var attempted = alreadyRetried && typeof alreadyRetried === "object" ? alreadyRetried : {}
    var healthy = {}
    var cachedProviders = {}
    var retryable = []
    for (var cachedIndex = 0; cachedIndex < cached.length; cachedIndex++) {
        cachedProviders[providerId(cached[cachedIndex] && cached[cachedIndex].provider)] = true
    }
    for (var i = 0; i < incoming.length; i++) {
        var id = providerId(incoming[i] && incoming[i].provider)
        if (id.length > 0 && !incoming[i].errorMessage) {
            healthy[id] = true
        }
    }
    for (var j = 0; j < incoming.length; j++) {
        var entry = incoming[j]
        var provider = providerId(entry && entry.provider)
        if (provider.length === 0 || provider === "all" || healthy[provider]
                || cachedProviders[provider] || attempted[provider]
                || retryable.indexOf(provider) !== -1) {
            continue
        }
        if (isRetryableProviderError(entry)) {
            retryable.push(provider)
        }
    }
    return retryable
}

function withoutProviders(entries, providers) {
    var list = Array.isArray(entries) ? entries : []
    var ids = Array.isArray(providers) ? providers : []
    var excluded = {}
    for (var i = 0; i < ids.length; i++) {
        var id = providerId(ids[i])
        if (id.length > 0) {
            excluded[id] = true
        }
    }
    var retained = []
    for (var j = 0; j < list.length; j++) {
        if (excluded[providerId(list[j] && list[j].provider)] !== true) {
            retained.push(list[j])
        }
    }
    return retained
}

function reconcileSeedCache(previous, seedEntries) {
    var seed = Array.isArray(seedEntries) ? seedEntries : []
    var cached = Array.isArray(previous) ? previous : []
    var allowed = providerIds(seed)
    var allowedEntries = []
    for (var i = 0; i < cached.length; i++) {
        if (allowed.indexOf(providerId(cached[i] && cached[i].provider)) !== -1) {
            allowedEntries.push(cached[i])
        }
    }
    return cacheLastGoodEntries(allowedEntries, seed)
}

function isUnfetchableProviderError(entry) {
    if (!entry || !entry.errorMessage) {
        return false
    }
    return /\bno\s+(?:available\s+)?fetch\s+strategy\b|\bunfetchable\s+provider\b|\bprovider\s+cannot\s+be\s+fetched\b/i.test(String(entry.errorMessage))
}

function excludeUnfetchableProviderEntries(entries) {
    var list = Array.isArray(entries) ? entries : []
    var retained = []
    var droppedProviderIds = []
    for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        if (!isUnfetchableProviderError(entry)) {
            retained.push(entry)
            continue
        }
        var id = providerId(entry && entry.provider)
        if (id.length > 0 && droppedProviderIds.indexOf(id) === -1) {
            droppedProviderIds.push(id)
        }
    }
    return { entries: retained, droppedProviderIds: droppedProviderIds }
}

function cachedEntryForError(entry, cachedEntries) {
    var cached = Array.isArray(cachedEntries) ? cachedEntries : []
    var key = providerAccountKey(entry)
    for (var i = 0; i < cached.length; i++) {
        if (providerAccountKey(cached[i]) === key) {
            return [cached[i]]
        }
    }

    if (String(entry && entry.account || "").trim().length > 0) {
        return []
    }
    var provider = providerId(entry && entry.provider)
    var providerMatches = []
    for (var j = 0; j < cached.length; j++) {
        if (providerId(cached[j] && cached[j].provider) === provider) {
            providerMatches.push(cached[j])
        }
    }
    return providerMatches
}

function mergeEntriesWithCache(entries, cachedEntries) {
    var incoming = Array.isArray(entries) ? entries : []
    var merged = []
    for (var i = 0; i < incoming.length; i++) {
        var entry = incoming[i] || {}
        if (!entry.errorMessage) {
            var fresh = copyEntry(entry)
            fresh.isCached = false
            merged.push(fresh)
            continue
        }
        var cached = cachedEntryForError(entry, cachedEntries)
        if (cached.length > 0) {
            for (var cachedIndex = 0; cachedIndex < cached.length; cachedIndex++) {
                var retained = copyEntry(cached[cachedIndex])
                retained.isCached = true
                retained.cachedErrorMessage = entry.errorMessage
                merged.push(retained)
            }
        } else {
            var failed = copyEntry(entry)
            failed.isCached = false
            merged.push(failed)
        }
    }
    return merged
}

function replaceProviderEntries(currentEntries, incomingEntries, providers, replaceAll) {
    var incoming = Array.isArray(incomingEntries) ? incomingEntries : []
    if (replaceAll === true) {
        return incoming.slice()
    }

    var current = Array.isArray(currentEntries) ? currentEntries : []
    var requested = Array.isArray(providers) ? providers : []
    var targets = {}
    for (var i = 0; i < requested.length; i++) {
        var requestedProvider = providerId(requested[i])
        if (requestedProvider.length === 0 || requestedProvider === "all") {
            continue
        }
        targets[requestedProvider] = true
    }
    var inserted = {}
    var result = []
    for (var j = 0; j < current.length; j++) {
        var currentEntry = current[j]
        var currentProvider = providerId(currentEntry && currentEntry.provider)
        if (!targets[currentProvider]) {
            result.push(currentEntry)
            continue
        }
        if (!inserted[currentProvider]) {
            for (var incomingIndex = 0; incomingIndex < incoming.length; incomingIndex++) {
                if (providerId(incoming[incomingIndex] && incoming[incomingIndex].provider) === currentProvider) {
                    result.push(incoming[incomingIndex])
                }
            }
            inserted[currentProvider] = true
        }
    }
    for (var target in targets) {
        if (inserted[target]) {
            continue
        }
        for (var pendingIndex = 0; pendingIndex < incoming.length; pendingIndex++) {
            if (providerId(incoming[pendingIndex] && incoming[pendingIndex].provider) === target) {
                result.push(incoming[pendingIndex])
            }
        }
    }
    return result
}

function compactQuotaKey(value) {
    return String(value || "")
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
}

function compactQuotaSelected(configuredSelection, provider, quotaKey, extra) {
    var selection = normalizeQuotaSelection(configuredSelection)
    var id = providerId(provider)
    var key = compactQuotaKey(quotaKey)
    if (selection.length === 0 || key.length === 0) {
        return false
    }

    var candidates = [key, id + "." + key]
    if (extra === true) {
        candidates.push("extras")
        candidates.push(id + ".extras")
    }
    for (var i = 0; i < selection.length; i++) {
        if (candidates.indexOf(selection[i]) !== -1) {
            return true
        }
    }
    return false
}

function compactQuotaLabel(quotaKey, title) {
    var labels = {
        // Keep the internal quota key as `primary`, but label it as Session in
        // compact UI because that is what CodexBar and the provider surfaces
        // call this window.
        "primary": "S",
        "weekly": "W",
        "tertiary": "T"
    }
    if (labels[quotaKey]) {
        return labels[quotaKey]
    }
    return title === "Fable only" ? "Fb" : compactTitleToken(title)
}

function compactQuotaPart(configuredSelection, provider, quotaKey, title, percentLeft, resetsAt, extra) {
    var key = compactQuotaKey(quotaKey)
    if (!compactQuotaSelected(configuredSelection, provider, key, extra)) {
        return ""
    }
    var label = compactQuotaLabel(key, title)
    if (percentLeft !== null && percentLeft !== undefined && !isNaN(percentLeft)) {
        var used = Math.max(0, Math.min(100, 100 - Number(percentLeft)))
        var separator = label.indexOf(" #") !== -1 ? " " : ""
        return label + separator + Math.round(used) + "%"
    }
    if (resetsAt) {
        return label + " reset"
    }
    return ""
}

function compactExtraPart(configuredSelection, provider, title, percentLeft, resetsAt) {
    var key = compactQuotaKey(title)
    return compactQuotaPart(configuredSelection, provider, key, title, percentLeft, resetsAt, true)
}

function standardWindowVisible(percentLeft, resetsAt) {
    if (percentLeft !== null && percentLeft !== undefined && !isNaN(percentLeft)) {
        return true
    }
    return Boolean(resetsAt)
}

function standardWindowRow(quotaKey, title, percentLeft, resetsAt, detail) {
    if (!standardWindowVisible(percentLeft, resetsAt)) {
        return null
    }
    var usageKnown = percentLeft !== null && percentLeft !== undefined && !isNaN(percentLeft)
    return {
        title: title,
        percentLeft: usageKnown ? Number(percentLeft) : null,
        resetsAt: resetsAt || null,
        detail: detail || "",
        usageKnown: usageKnown,
        compactKey: compactQuotaKey(quotaKey),
        compactExtra: false,
        windowBadge: quotaWindowBadge(quotaKey, title)
    }
}

function quotaWindowBadge(quotaKey, title) {
    var key = compactQuotaKey(quotaKey)
    var badges = {
        "primary": "S",
        "weekly": "W",
        "tertiary": "T"
    }
    if (badges[key]) {
        return badges[key]
    }
    var normalizedTitle = String(title || "")
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, " ")
        .replace(/^\s+|\s+$/g, "")
    if (/\bweekly\b/.test(normalizedTitle)) {
        return "W"
    }
    var duration = String(title || "").match(/\b(\d+)\s*[- ]?\s*(hour|day|week|h|d|w)\b/i)
    if (duration) {
        return duration[1] + duration[2].charAt(0).toLowerCase()
    }
    var token = compactTitleToken(title)
    return token.slice(0, Math.min(2, token.length)).toUpperCase()
}

function compactTitleToken(title) {
    return String(title || "Extra").replace(/[^A-Za-z0-9]+/g, "") || "Extra"
}

function uniqueExtraLabels(titles) {
    var list = Array.isArray(titles) ? titles : []
    var tokens = []
    var counts = {}
    for (var i = 0; i < list.length; i++) {
        var token = compactTitleToken(list[i])
        var key = token.toLowerCase()
        tokens.push({ token: token, key: key, fable: String(list[i]) === "Fable only" })
        counts[key] = (counts[key] || 0) + 1
    }

    var occurrences = {}
    var labels = []
    for (var j = 0; j < tokens.length; j++) {
        var current = tokens[j]
        var label = "Fb"
        if (!current.fable) {
            var length = Math.min(2, current.token.length)
            while (length < current.token.length) {
                var prefix = current.key.slice(0, length)
                var unique = true
                for (var otherIndex = 0; otherIndex < tokens.length; otherIndex++) {
                    var other = tokens[otherIndex]
                    if (other.key !== current.key && other.key.slice(0, length) === prefix) {
                        unique = false
                        break
                    }
                }
                if (unique) {
                    break
                }
                length++
            }
            label = current.token.slice(0, Math.max(1, length))
            label = label.charAt(0).toUpperCase() + label.slice(1).toLowerCase()
        }
        occurrences[current.key] = (occurrences[current.key] || 0) + 1
        if (counts[current.key] > 1) {
            label += " #" + occurrences[current.key]
        }
        labels.push(label)
    }
    return labels
}

function compactValuePart(label, percentLeft, resetsAt) {
    if (percentLeft !== null && percentLeft !== undefined && !isNaN(percentLeft)) {
        var used = Math.max(0, Math.min(100, 100 - Number(percentLeft)))
        var separator = label.indexOf(" #") !== -1 ? " " : ""
        return label + separator + Math.round(used) + "%"
    }
    return resetsAt ? label + " reset" : ""
}

function compactNumber(value) {
    if (value === null || value === undefined || isNaN(value)) {
        return ""
    }
    var rounded = Math.round(Number(value) * 100) / 100
    return String(rounded)
}

function compactUsedPercent(percentLeft) {
    if (percentLeft === null || percentLeft === undefined || isNaN(percentLeft)) {
        return null
    }
    return Math.max(0, Math.min(100, 100 - Number(percentLeft)))
}

function compactUsageStatus(usedPercent) {
    if (usedPercent === null || usedPercent === undefined || isNaN(usedPercent)) {
        return "neutral"
    }
    if (Number(usedPercent) >= 80) {
        return "error"
    }
    if (Number(usedPercent) >= 50) {
        return "warning"
    }
    return "good"
}

function entryHasReportedUsage(entry) {
    if (!entry || typeof entry !== "object") {
        return false
    }
    var rows = Array.isArray(entry.rows) ? entry.rows : []
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i]
        if (row && row.usageKnown !== false
                && row.percentLeft !== null && row.percentLeft !== undefined
                && !isNaN(row.percentLeft)) {
            return true
        }
    }
    var fallbackFields = [
        entry.compactPrimaryPercentLeft,
        entry.secondaryPercentLeft,
        entry.tertiaryPercentLeft
    ]
    for (var j = 0; j < fallbackFields.length; j++) {
        if (fallbackFields[j] !== null && fallbackFields[j] !== undefined
                && !isNaN(fallbackFields[j])) {
            return true
        }
    }
    return false
}

function selectedExtraRows(entries, configuredSelection) {
    var byProvider = {}
    var list = Array.isArray(entries) ? entries : []
    for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        var id = providerId(entry && entry.provider)
        var rows = entry && Array.isArray(entry.rows) ? entry.rows : []
        if (!byProvider[id]) {
            byProvider[id] = []
        }
        for (var j = 0; j < rows.length; j++) {
            var row = rows[j]
            var key = row && (row.compactKey || compactQuotaKey(row.title))
            if (row && row.compactExtra === true
                    && standardWindowVisible(row.percentLeft, row.resetsAt)
                    && compactQuotaSelected(configuredSelection, id, key, true)) {
                byProvider[id].push(row)
            }
        }
    }
    return byProvider
}

function elideCompactText(value, maximumCharacters) {
    var text = String(value || "")
    var limit = Math.max(4, Number(maximumCharacters) || 28)
    if (text.length <= limit) {
        return text
    }
    return text.slice(0, limit - 1).replace(/\s+$/g, "") + "…"
}

function composeCompactBlocks(entries, options) {
    var settings = options || {}
    var quotaSelection = settings.showUsed === false ? "" : settings.quotaSelection
    var orderedEntries = filterAndOrderEntries(entries, settings.providerOrder)
    var selected = filterCompactEntries(entries, settings.providerOrder, quotaSelection)
    if (selected.length === 0) {
        return {
            hasSelection: false,
            provider: "",
            text: settings.noSelectionText || "No selection",
            blocks: []
        }
    }

    var providerCounts = {}
    for (var countIndex = 0; countIndex < orderedEntries.length; countIndex++) {
        var countId = providerId(orderedEntries[countIndex] && orderedEntries[countIndex].provider)
        providerCounts[countId] = (providerCounts[countId] || 0) + 1
    }

    var extras = selectedExtraRows(selected, settings.quotaSelection)
    var extraLabels = {}
    var extraCursors = {}
    for (var extraProvider in extras) {
        var titles = []
        for (var titleIndex = 0; titleIndex < extras[extraProvider].length; titleIndex++) {
            titles.push(extras[extraProvider][titleIndex].title)
        }
        extraLabels[extraProvider] = uniqueExtraLabels(titles)
        extraCursors[extraProvider] = 0
    }

    var blocks = []
    var blockTexts = []
    for (var i = 0; i < selected.length; i++) {
        var entry = selected[i]
        var id = providerId(entry && entry.provider)
        var providerOrdinal = 0
        for (var orderedIndex = 0; orderedIndex < orderedEntries.length; orderedIndex++) {
            if (providerId(orderedEntries[orderedIndex] && orderedEntries[orderedIndex].provider) === id) {
                providerOrdinal++
            }
            if (orderedEntries[orderedIndex] === entry) {
                break
            }
        }
        var block = []
        var quotaParts = []
        var ordinal = providerCounts[id] > 1 ? "#" + providerOrdinal : ""
        if (settings.showProvider !== false) {
            var providerLabel = compactProviderLabel(entry.provider, entry.name)
            block.push(ordinal ? providerLabel + " " + ordinal : providerLabel)
        } else if (ordinal) {
            block.push(ordinal)
        }
        if (entry.errorMessage) {
            block.push("ERR")
            var errorText = block.join(" ")
            blockTexts.push(errorText)
            blocks.push({
                provider: id,
                ordinal: ordinal,
                error: true,
                cached: false,
                status: "error",
                worstUsedPercent: null,
                quotaText: "ERR",
                fullText: errorText,
                displayText: "ERR"
            })
            continue
        }
        var worstUsedPercent = null
        if (settings.showUsed !== false) {
            var standard = [
                { key: "primary", title: "Primary", percentLeft: entry.compactPrimaryPercentLeft,
                    resetsAt: entry.primaryResetsAt, extra: false },
                { key: "weekly", title: "Weekly", percentLeft: entry.secondaryPercentLeft,
                    resetsAt: entry.secondaryResetsAt, extra: false },
                { key: "tertiary", title: "Tertiary", percentLeft: entry.tertiaryPercentLeft,
                    resetsAt: entry.tertiaryResetsAt, extra: true }
            ]
            for (var standardIndex = 0; standardIndex < standard.length; standardIndex++) {
                var standardWindow = standard[standardIndex]
                var standardPart = compactQuotaPart(
                    settings.quotaSelection, id, standardWindow.key, standardWindow.title,
                    standardWindow.percentLeft, standardWindow.resetsAt, standardWindow.extra)
                if (standardPart) {
                    block.push(standardPart)
                    quotaParts.push(standardPart)
                    var standardUsed = compactUsedPercent(standardWindow.percentLeft)
                    if (standardUsed !== null
                            && (worstUsedPercent === null || standardUsed > worstUsedPercent)) {
                        worstUsedPercent = standardUsed
                    }
                }
            }
            var rows = entry && Array.isArray(entry.rows) ? entry.rows : []
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
                var row = rows[rowIndex]
                var key = row && (row.compactKey || compactQuotaKey(row.title))
                if (!row || row.compactExtra !== true
                        || !standardWindowVisible(row.percentLeft, row.resetsAt)
                        || !compactQuotaSelected(settings.quotaSelection, id, key, true)) {
                    continue
                }
                var cursor = extraCursors[id] || 0
                var label = extraLabels[id] && extraLabels[id][cursor]
                    ? extraLabels[id][cursor]
                    : compactQuotaLabel(key, row.title)
                extraCursors[id] = cursor + 1
                var extraPart = compactValuePart(label, row.percentLeft, row.resetsAt)
                if (extraPart) {
                    block.push(extraPart)
                    quotaParts.push(extraPart)
                    var extraUsed = compactUsedPercent(row.percentLeft)
                    if (extraUsed !== null
                            && (worstUsedPercent === null || extraUsed > worstUsedPercent)) {
                        worstUsedPercent = extraUsed
                    }
                }
            }
        }
        if (settings.showCredits !== false && entry.creditsRemaining !== null
                && entry.creditsRemaining !== undefined && !isNaN(entry.creditsRemaining)) {
            var creditPart = "Cr " + compactNumber(entry.creditsRemaining)
            block.push(creditPart)
            quotaParts.push(creditPart)
        }
        if (block.length > 0) {
            var blockText = block.join(" ")
            var quotaText = quotaParts.join(" ")
            blockTexts.push(blockText)
            blocks.push({
                provider: id,
                ordinal: ordinal,
                error: false,
                cached: entry.isCached === true,
                status: entry.isCached === true ? "neutral" : compactUsageStatus(worstUsedPercent),
                worstUsedPercent: worstUsedPercent,
                quotaText: quotaText,
                fullText: blockText,
                displayText: elideCompactText(quotaText || blockText, settings.maximumCharacters || 28)
            })
        }
    }
    return {
        hasSelection: true,
        provider: providerId(selected[0] && selected[0].provider),
        text: blockTexts.length > 0 ? blockTexts.join(" | ") : (settings.noFieldsText || "No compact fields"),
        blocks: blocks
    }
}

function composeCompactText(entries, options) {
    return composeCompactBlocks(entries, options)
}

function popupProviderPriority(provider) {
    var priorities = {
        "codex": 0,
        "claude": 1,
        "grok": 2,
        "antigravity": 3
    }
    var id = providerId(provider)
    return priorities[id] === undefined ? 100 : priorities[id]
}

function orderPopupEntries(entries) {
    var list = Array.isArray(entries) ? entries : []
    var ordered = []
    for (var priority = 0; priority < 4; priority++) {
        for (var i = 0; i < list.length; i++) {
            if (popupProviderPriority(list[i] && list[i].provider) === priority) {
                ordered.push(list[i])
            }
        }
    }
    for (var j = 0; j < list.length; j++) {
        if (popupProviderPriority(list[j] && list[j].provider) >= 100) {
            ordered.push(list[j])
        }
    }
    return ordered
}

function decoratePopupEntries(entries) {
    var ordered = orderPopupEntries(entries)
    var counts = {}
    var occurrences = {}
    var decorated = []
    for (var i = 0; i < ordered.length; i++) {
        var countId = providerId(ordered[i] && ordered[i].provider)
        counts[countId] = (counts[countId] || 0) + 1
    }
    for (var j = 0; j < ordered.length; j++) {
        var entry = ordered[j] || {}
        var id = providerId(entry.provider)
        occurrences[id] = (occurrences[id] || 0) + 1
        var ordinal = counts[id] > 1 ? occurrences[id] : 0
        var copy = {}
        for (var property in entry) {
            copy[property] = entry[property]
        }
        copy.providerId = id
        copy.accountOrdinal = ordinal
        copy.accountCount = counts[id]
        copy.selectionKey = id + ":" + occurrences[id]
        var displayBase = String(entry.name || entry.provider || "Provider")
        var tabBase = id === "antigravity" ? "Antigravity" : displayBase
        var ordinalSuffix = ordinal > 0 ? " #" + ordinal : ""
        copy.tabLabel = tabBase + ordinalSuffix
        copy.displayName = displayBase + ordinalSuffix
        decorated.push(copy)
    }
    return decorated
}

function activeEntryData(entries, selectionKey) {
    var decorated = decoratePopupEntries(entries)
    var selectedIndex = 0
    for (var i = 0; i < decorated.length; i++) {
        if (decorated[i].selectionKey === selectionKey) {
            selectedIndex = i
            break
        }
    }
    if (decorated.length === 0) {
        return { hasEntry: false, selectionKey: "", index: -1, entry: null, entries: decorated }
    }
    return {
        hasEntry: true,
        selectionKey: decorated[selectedIndex].selectionKey,
        index: selectedIndex,
        entry: decorated[selectedIndex],
        entries: decorated
    }
}

function attachProviderCostSummaries(entries, summaries) {
    var list = Array.isArray(entries) ? entries : []
    var source = summaries || {}
    var seen = {}
    var result = []
    for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        var copy = {}
        for (var prop in entry) {
            copy[prop] = entry[prop]
        }
        var id = providerId(entry && entry.provider)
        copy.costSummaryOwner = seen[id] !== true
        copy.costSummary = copy.costSummaryOwner ? (source[id] || null) : null
        seen[id] = true
        result.push(copy)
    }
    return result
}

function sameProviderOrder(left, right) {
    return normalizeProviderOrder(left).join(",") === normalizeProviderOrder(right).join(",")
}

function migrateLegacyProvider(legacyProvider, currentOrder, defaultOrder, migrationDone) {
    if (migrationDone === true) {
        return { order: currentOrder, writeOrder: false, writeDone: false }
    }
    var legacy = providerId(legacyProvider || "detect")
    var personalized = !sameProviderOrder(currentOrder, defaultOrder)
    var target = defaultOrder
    if (legacy === "all") {
        target = ""
    } else if (legacy && legacy !== "detect") {
        target = legacy
    }
    return {
        order: personalized ? currentOrder : target,
        writeOrder: !personalized && String(currentOrder) !== String(target),
        writeDone: true
    }
}

function entryHasSelectedQuota(entry, configuredSelection) {
    if (normalizeQuotaSelection(configuredSelection).length === 0 || (entry && entry.errorMessage)) {
        return true
    }
    var provider = entry && entry.provider
    var standard = [
        { key: "primary", percentLeft: entry && entry.compactPrimaryPercentLeft, resetsAt: entry && entry.primaryResetsAt, extra: false },
        { key: "weekly", percentLeft: entry && entry.secondaryPercentLeft, resetsAt: entry && entry.secondaryResetsAt, extra: false },
        { key: "tertiary", percentLeft: entry && entry.tertiaryPercentLeft, resetsAt: entry && entry.tertiaryResetsAt, extra: true }
    ]
    for (var i = 0; i < standard.length; i++) {
        if (standardWindowVisible(standard[i].percentLeft, standard[i].resetsAt)
                && compactQuotaSelected(configuredSelection, provider, standard[i].key, standard[i].extra)) {
            return true
        }
    }
    var rows = entry && Array.isArray(entry.rows) ? entry.rows : []
    for (var j = 0; j < rows.length; j++) {
        var row = rows[j]
        if (row && row.compactExtra === true
                && standardWindowVisible(row.percentLeft, row.resetsAt)
                && compactQuotaSelected(configuredSelection, provider,
                    row.compactKey || compactQuotaKey(row.title), true)) {
            return true
        }
    }
    return false
}

function filterCompactEntries(entries, configuredOrder, configuredSelection) {
    var ordered = filterAndOrderEntries(entries, configuredOrder)
    var filtered = []
    for (var i = 0; i < ordered.length; i++) {
        if (entryHasSelectedQuota(ordered[i], configuredSelection)) {
            filtered.push(ordered[i])
        }
    }
    return filtered
}

function compactSelectionState(entries, configuredOrder, configuredSelection) {
    var selected = filterCompactEntries(entries, configuredOrder, configuredSelection)
    if (selected.length === 0) {
        return { hasSelection: false, provider: "", text: "No selection" }
    }
    return {
        hasSelection: true,
        provider: providerId(selected[0] && selected[0].provider),
        text: ""
    }
}

function appendProviderMatches(target, list, provider) {
    for (var i = 0; i < list.length; i++) {
        if (providerId(list[i] && list[i].provider) === provider) {
            target.push(list[i])
        }
    }
}

function filterAndOrderEntries(entries, configuredOrder) {
    var list = Array.isArray(entries) ? entries : []
    var order = normalizeProviderOrder(configuredOrder)
    if (order.length === 0) {
        return list.slice()
    }

    var filtered = []
    for (var i = 0; i < order.length; i++) {
        appendProviderMatches(filtered, list, order[i])
    }
    return filtered
}

function normalizeUsageWindows(provider, primary, secondary) {
    var id = providerId(provider)
    if ((id === "antigravity" || id === "gemini")
            && primary && secondary
            && typeof primary.windowMinutes === "number"
            && typeof secondary.windowMinutes === "number"
            && primary.windowMinutes > secondary.windowMinutes) {
        return { primary: secondary, secondary: primary }
    }
    return { primary: primary, secondary: secondary }
}

function compactProviderLabel(provider, name) {
    var id = providerId(provider || name)
    var labels = {
        "codex": "Cx",
        "claude": "Cl",
        "grok": "Gk",
        "antigravity": "Ag",
        "gemini": "Gm"
    }
    if (labels[id]) {
        return labels[id]
    }
    var fallback = String(name || provider || "AI").trim()
    if (fallback.length <= 2) {
        return fallback || "AI"
    }
    return fallback.slice(0, 2)
}
