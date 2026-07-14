const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const root = path.resolve(__dirname, "..")
const logicPath = path.join(root, "contents/code/providerLogic.js")
const fixturePath = path.join(__dirname, "fixtures/provider-logic.json")
const mainQmlPath = path.join(root, "contents/ui/main.qml")
const configQmlPath = path.join(root, "contents/ui/config/configGeneral.qml")
const configXmlPath = path.join(root, "contents/config/main.xml")
const metadataPath = path.join(root, "metadata.json")
const source = fs.readFileSync(logicPath, "utf8").replace(/^\.pragma library\s*$/m, "")
const context = {}
vm.createContext(context)
vm.runInContext(source, context, { filename: logicPath })

const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"))
const plain = value => JSON.parse(JSON.stringify(value))

assert.deepEqual(
    Array.from(context.normalizeProviderOrder(fixture.configuredOrder)),
    fixture.expectedNormalizedOrder,
    "provider IDs are normalized case-insensitively and deduplicated"
)

const filtered = Array.from(context.filterAndOrderEntries(fixture.entries, fixture.configuredOrder))
assert.deepEqual(
    filtered.map(entry => entry.provider),
    fixture.expectedFilteredProviders,
    "entries follow configured order and unlisted providers are filtered"
)
assert.equal(filtered[3].errorMessage, "quota unavailable", "listed provider errors remain visible")
assert.deepEqual(
    filtered.filter(entry => entry.provider === "codex").map(entry => entry.account),
    ["first", "second"],
    "every account for the same provider is retained in stable input order"
)

const unfiltered = Array.from(context.filterAndOrderEntries(fixture.entries, ""))
assert.deepEqual(
    unfiltered.map(entry => entry.provider),
    fixture.entries.map(entry => entry.provider),
    "empty configuration preserves upstream ordering and filtering behavior"
)

const popupEntries = plain(context.decoratePopupEntries(fixture.entries))
assert.deepEqual(
    popupEntries.map(entry => entry.provider),
    ["codex", "codex", "claude", "GROK", "antigravity", "unlisted"],
    "popup entries use the normative provider order and append other enabled providers"
)
assert.deepEqual(
    popupEntries.filter(entry => entry.providerId === "codex").map(entry => entry.tabLabel),
    ["Codex #1", "Codex #2"],
    "multiple provider accounts receive stable non-sensitive ordinals"
)
const antigravityPopup = popupEntries.find(entry => entry.providerId === "antigravity")
assert.equal(antigravityPopup.tabLabel, "Antigravity", "Antigravity uses a short popup tab label")
assert.equal(
    antigravityPopup.displayName,
    "Gemini (Antigravity)",
    "Antigravity keeps its complete provider heading"
)
const repeatedAntigravity = plain(context.decoratePopupEntries([
    { provider: "antigravity", name: "Gemini (Antigravity)", account: "private-one" },
    { provider: "antigravity", name: "Gemini (Antigravity)", account: "private-two" }
]))
assert.deepEqual(
    repeatedAntigravity.map(entry => entry.tabLabel),
    ["Antigravity #1", "Antigravity #2"],
    "short popup labels retain stable account ordinals"
)
assert.deepEqual(
    repeatedAntigravity.map(entry => entry.displayName),
    ["Gemini (Antigravity) #1", "Gemini (Antigravity) #2"],
    "full popup headings retain the same stable account ordinals"
)
assert.doesNotMatch(
    repeatedAntigravity.map(entry => entry.tabLabel + entry.displayName).join(" "),
    /private-/,
    "popup labels never expose account data"
)
const activeSecondCodex = plain(context.activeEntryData(fixture.entries, "codex:2"))
assert.equal(activeSecondCodex.index, 1)
assert.equal(activeSecondCodex.entry.account, "second")
assert.equal(activeSecondCodex.entry.selectionKey, "codex:2")
const activeError = plain(context.activeEntryData(fixture.entries, "grok:1"))
assert.equal(activeError.entry.errorMessage, "quota unavailable", "an error account remains selectable")
const activeFallback = plain(context.activeEntryData(fixture.entries, "missing:9"))
assert.equal(activeFallback.entry.selectionKey, "codex:1", "a stale selection falls back deterministically")

assert.deepEqual(
    plain(context.acquisitionCandidates("detect")),
    [{ provider: "", source: "detect" }],
    "default acquisition uses the sentinel that honors enabled providers"
)
assert.deepEqual(
    plain(context.acquisitionCandidates("OAuth")),
    [{ provider: "", source: "oauth" }],
    "source selection never narrows provider acquisition"
)
assert.deepEqual(
    plain(context.usageArguments("", "detect", false)),
    ["usage", "--format", "json", "--json-only"],
    "enabled-provider acquisition omits the provider argument completely"
)
assert.deepEqual(
    plain(context.usageArguments("", "oauth", true)),
    ["usage", "--format", "json", "--json-only", "--source", "oauth", "--status"],
    "source and status flags do not introduce a provider override"
)
assert.deepEqual(
    plain(context.costArguments()),
    ["cost", "--format", "json", "--json-only"],
    "cost acquisition also avoids the slow all-provider override"
)

assert.deepEqual(
    Array.from(context.normalizeQuotaSelection(fixture.quotaSelection)),
    fixture.expectedNormalizedQuotaSelection,
    "quota keys are normalized and deduplicated"
)
assert.equal(context.compactQuotaKey("Fable only"), "fable-only")
assert.equal(context.compactQuotaKey("  Model / Week  "), "model-week")
assert.equal(context.compactQuotaLabel("primary", "Session"), "S", "the internal primary key is shown as Session in compact UI")
assert.equal(context.quotaWindowBadge("primary", "Session"), "S", "the popup uses S for the Session window badge")
assert.equal(
    context.compactQuotaSelected(fixture.quotaSelection, "claude", "fable-only", true),
    true,
    "an individual extra quota can be selected"
)
assert.equal(
    context.compactQuotaSelected(fixture.quotaSelection, "grok", "fable-only", true),
    false,
    "an individual quota does not leak to other providers"
)
assert.equal(
    context.compactQuotaSelected(fixture.quotaSelection, "grok", "primary", false),
    true,
    "a global primary key selects that quota for every compact provider"
)
assert.equal(
    context.compactQuotaSelected("antigravity.extras", "antigravity", "flash", true),
    true,
    "a provider-scoped extras key selects all extra windows for that provider"
)
assert.equal(
    context.compactQuotaSelected("", "codex", "primary", false),
    false,
    "an empty quota selection shows provider labels without quota values"
)
assert.equal(
    context.compactExtraPart("claude.fable-only", "claude", "Fable only", 80),
    "Fb20%",
    "a selected extra quota remains visible below the former 50 percent threshold"
)
assert.equal(
    context.compactQuotaSelected("extras", "antigravity", "tertiary", true),
    true,
    "the global extras key includes the tertiary window"
)
assert.equal(
    context.compactQuotaPart(
        "antigravity.tertiary", "antigravity", "tertiary", "Tertiary",
        null, "2026-07-15T01:00:00Z", true),
    "T reset",
    "an individually selected reset-only tertiary window has a compact state"
)
assert.equal(
    context.standardWindowVisible(null, "2026-07-15T01:00:00Z"),
    true,
    "a reset-only standard window remains visible in the popup"
)
assert.equal(
    context.standardWindowVisible(null, null),
    false,
    "a standard window with neither usage nor reset stays absent"
)
const resetOnlyRow = context.standardWindowRow(
    "tertiary", "Tertiary", null, "2026-07-15T01:00:00Z", "reset detail")
assert.equal(resetOnlyRow.compactKey, "tertiary")
assert.equal(resetOnlyRow.percentLeft, null)
assert.equal(resetOnlyRow.usageKnown, false, "reset-only standard rows mark usage as unknown")
assert.equal(resetOnlyRow.windowBadge, "T", "standard rows carry compact window badges")
assert.equal(context.quotaWindowBadge("flash", "Gemini 5-hour"), "5h")
assert.equal(context.quotaWindowBadge("weekly-plan", "Weekly"), "W")
assert.equal(context.quotaWindowBadge("weekly-limit", "Weekly rate limit"), "W")
assert.equal(context.quotaWindowBadge("claude-weekly", "Claude weekly quota"), "W")
assert.equal(
    context.quotaWindowBadge("model-week", "Model week"),
    "MO",
    "arbitrary extra titles keep their deterministic badge"
)
assert.equal(
    context.standardWindowRow("primary", "Session", null, null, ""),
    null,
    "empty standard windows are not added to the popup"
)

const invalidState = context.compactSelectionState(
    fixture.compactEntries, "missing-provider", "primary")
assert.equal(invalidState.hasSelection, false)
assert.equal(invalidState.provider, "")
assert.equal(invalidState.text, "No selection")

const invalidQuotaState = context.compactSelectionState(
    fixture.compactEntries, "codex", "codex.unknown-quota")
assert.equal(invalidQuotaState.hasSelection, false, "an unmatched quota key has no false provider selection")

const tertiaryEntries = Array.from(context.filterCompactEntries(
    fixture.compactEntries, "antigravity", "extras"))
assert.deepEqual(
    tertiaryEntries.map(entry => entry.provider),
    ["antigravity"],
    "extras selects a reset-only tertiary window"
)
assert.equal(
    context.compactExtraPart("claude.weekly", "claude", "Fable only", 80),
    "",
    "an unselected extra quota stays out of the compact panel"
)

const normalizedAntigravity = context.normalizeUsageWindows(
    "Antigravity",
    fixture.antigravityUsage.primary,
    fixture.antigravityUsage.secondary
)
assert.equal(normalizedAntigravity.primary.windowMinutes, 300)
assert.equal(normalizedAntigravity.secondary.windowMinutes, 10080)

const unchangedClaude = context.normalizeUsageWindows(
    "claude",
    fixture.antigravityUsage.primary,
    fixture.antigravityUsage.secondary
)
assert.equal(unchangedClaude.primary.windowMinutes, 10080, "other providers keep their original windows")
assert.equal(unchangedClaude.secondary.windowMinutes, 300)

assert.deepEqual(
    plain(context.normalizeCodexResetCredits(fixture.codexResetCredits)),
    {
        availableCount: 2,
        expiresAt: ["2026-08-11T21:09:53Z", "2026-08-12T18:07:45Z"]
    },
    "Codex banked reset credits retain their count and expiration dates"
)

const goodClaudeEntry = {
    provider: "claude",
    account: "account-one",
    updatedAt: "2026-07-14T17:11:01Z",
    compactPrimaryPercentLeft: 92,
    secondaryPercentLeft: 95,
    rows: [{ title: "Session", percentLeft: 92, usageKnown: true }],
    errorMessage: ""
}
const claudeCache = context.cacheLastGoodEntries([], [goodClaudeEntry])
const cachedClaudeResult = plain(context.mergeEntriesWithCache([
    {
        provider: "claude",
        account: "account-one",
        errorMessage: "Claude CLI usage endpoint is rate limited right now"
    }
], claudeCache))
assert.equal(cachedClaudeResult[0].compactPrimaryPercentLeft, 92)
assert.equal(cachedClaudeResult[0].updatedAt, "2026-07-14T17:11:01Z")
assert.equal(cachedClaudeResult[0].errorMessage, "")
assert.equal(cachedClaudeResult[0].isCached, true, "a Claude error retains the last successful account entry")

const uncachedClaudeError = plain(context.mergeEntriesWithCache([
    {
        provider: "claude",
        account: "new-account",
        errorMessage: "Claude CLI usage endpoint is rate limited right now"
    }
], claudeCache))
assert.equal(
    uncachedClaudeError[0].errorMessage,
    "Claude CLI usage endpoint is rate limited right now",
    "an error without cached data stays visible"
)
assert.equal(uncachedClaudeError[0].isCached, false)

const accountlessCodexError = plain(context.mergeEntriesWithCache(
    [fixture.multiAccountErrorCache.error], fixture.multiAccountErrorCache.cachedEntries))
assert.deepEqual(
    accountlessCodexError.map(entry => entry.account),
    ["work", "personal"],
    "an account-less provider error retains every cached account"
)
assert.deepEqual(
    accountlessCodexError.map(entry => entry.isCached),
    [true, true],
    "every cached account is marked stale after an account-less provider error"
)
assert.deepEqual(
    accountlessCodexError.map(entry => entry.cachedErrorMessage),
    [fixture.multiAccountErrorCache.error.errorMessage, fixture.multiAccountErrorCache.error.errorMessage],
    "every retained account carries the provider error"
)

const filteredUnfetchable = plain(context.excludeUnfetchableProviderEntries([
    fixture.unfetchableProvider,
    {
        provider: "claude",
        errorMessage: "Claude CLI usage endpoint is rate limited right now"
    }
]))
assert.deepEqual(
    filteredUnfetchable.droppedProviderIds,
    ["openai"],
    "no-fetch-strategy errors remove the provider from future refresh candidates"
)
assert.deepEqual(
    filteredUnfetchable.entries.map(entry => entry.provider),
    ["claude"],
    "transient provider errors remain visible for cache recovery"
)
assert.equal(
    context.isUnfetchableProviderError(fixture.unfetchableProvider),
    true,
    "the CodexBar no-fetch-strategy response is classified as non-transient"
)

const reconciledSeedCache = plain(context.reconcileSeedCache(
    fixture.seedReconciliation.previousCache, fixture.seedReconciliation.seedEntries))
assert.deepEqual(
    reconciledSeedCache.map(entry => entry.provider),
    ["codex", "claude"],
    "a successful seed purges cached providers it no longer returns"
)
assert.equal(
    reconciledSeedCache[0].compactPrimaryPercentLeft,
    82,
    "a successful seed replaces cached data for its healthy provider"
)
assert.equal(
    reconciledSeedCache[1].compactPrimaryPercentLeft,
    73,
    "a transient seed error retains cache only for the provider returned by the seed"
)
const seededEntries = plain(context.replaceProviderEntries(
    fixture.seedReconciliation.previousCache, fixture.seedReconciliation.seedEntries, [], true))
assert.deepEqual(
    seededEntries.map(entry => entry.provider),
    ["codex", "claude"],
    "a successful seed replaces visible entries and purges providers it did not return"
)

assert.deepEqual(
    plain(context.replaceProviderEntries(
        fixture.allTargetReplacement.currentEntries,
        fixture.allTargetReplacement.incomingEntries,
        ["all"],
        false)),
    fixture.allTargetReplacement.currentEntries,
    "a targeted replacement never treats the synthetic all provider as a real target"
)

assert.equal(context.compactProviderLabel("codex", "Codex"), "Cx")
assert.equal(context.compactProviderLabel("claude", "Claude"), "Cl")
assert.equal(context.compactProviderLabel("grok", "Grok"), "Gk")
assert.equal(context.compactProviderLabel("antigravity", "Gemini"), "Ag")
assert.equal(context.compactProviderLabel("gemini", "Gemini"), "Gm")
assert.notEqual(
    context.compactProviderLabel("antigravity", "Gemini"),
    context.compactProviderLabel("gemini", "Gemini"),
    "Antigravity and Gemini use distinct compact labels"
)
assert.equal(context.compactProviderLabel("openrouter", "OpenRouter"), "Op")

assert.deepEqual(
    Array.from(context.uniqueExtraLabels(["Fast requests", "Fallback quota"])),
    ["Fas", "Fal"],
    "extra quota labels use deterministic minimum unique prefixes"
)
assert.deepEqual(
    Array.from(context.uniqueExtraLabels(["Fable only", "Fable only"])),
    ["Fb #1", "Fb #2"],
    "Fable keeps its fixed label and identical titles receive ordinals"
)

const composed = context.composeCompactText(fixture.composeEntries, {
    providerOrder: "codex,grok",
    quotaSelection: "primary,extras",
    showProvider: true,
    showUsed: true,
    showCredits: true
})
assert.equal(
    composed.text,
    "Cx #1 S20% Fas #1 20% Fal30% Cr 5 | Cx #2 S40% Fas #2 40% Cr 3 | Gk ERR",
    "final compact text distinguishes duplicate accounts, collisions, credits, and errors"
)
assert.doesNotMatch(composed.text, /private-account/, "compact output never exposes account identifiers")

const compactDefault = plain(context.composeCompactBlocks(fixture.defaultCompactEntries, {
    providerOrder: "codex,claude,grok,antigravity",
    quotaSelection: "primary,weekly",
    showProvider: true,
    showUsed: true,
    showCredits: false
}))
assert.equal(compactDefault.text, "Cx S19% W0% | Cl ERR | Gk S8% W31% | Ag S0% W1%")
assert.deepEqual(
    compactDefault.blocks.map(block => block.provider),
    ["codex", "claude", "grok", "antigravity"],
    "the default compact model keeps every configured provider in order"
)
assert.equal(compactDefault.blocks[1].displayText, "ERR", "compact errors stay visible")
assert.deepEqual(
    compactDefault.blocks.map(block => block.worstUsedPercent),
    [19, null, 31, 1],
    "each compact block exposes its worst selected used percentage"
)
assert.deepEqual(
    compactDefault.blocks.map(block => block.status),
    ["good", "error", "good", "good"],
    "compact blocks expose deterministic usage severity"
)

const compactThresholds = plain(context.composeCompactBlocks([
    { provider: "codex", compactPrimaryPercentLeft: 51, secondaryPercentLeft: 50, rows: [] },
    { provider: "claude", compactPrimaryPercentLeft: 21, secondaryPercentLeft: 20, rows: [] },
    { provider: "grok", primaryResetsAt: "2026-07-15T01:00:00Z", rows: [] }
], {
    providerOrder: "codex,claude,grok",
    quotaSelection: "primary,weekly",
    showProvider: true,
    showUsed: true,
    showCredits: false
}))
assert.deepEqual(
    compactThresholds.blocks.map(block => block.worstUsedPercent),
    [50, 80, null],
    "compact severity uses the worst selected quota and leaves reset-only usage neutral"
)
assert.deepEqual(
    compactThresholds.blocks.map(block => block.status),
    ["warning", "error", "neutral"],
    "compact severity matches the 50 and 80 percent metric thresholds"
)

assert.equal(context.entryHasReportedUsage({ rows: [] }), false)
assert.equal(
    context.entryHasReportedUsage({
        rows: [{ percentLeft: null, usageKnown: false, resetsAt: "2026-07-15T01:00:00Z" }]
    }),
    false,
    "reset-only provider data is not reported usage"
)
assert.equal(
    context.entryHasReportedUsage({ rows: [{ percentLeft: 100, usageKnown: true }] }),
    true,
    "a numeric usage row is reported usage even at zero percent used"
)

const widthSafe = plain(context.composeCompactBlocks(fixture.composeEntries, {
    providerOrder: "codex",
    quotaSelection: "primary,extras",
    showProvider: true,
    showUsed: true,
    showCredits: true,
    maximumCharacters: 12
}))
assert.ok(widthSafe.blocks[0].displayText.length <= 12, "each visual compact block is width-safe")
assert.match(widthSafe.blocks[0].displayText, /…$/, "width-safe compact text is visibly elided")
assert.match(widthSafe.blocks[0].fullText, /Fas #1 20%/, "the complete selected extra remains available")
assert.match(widthSafe.blocks[0].fullText, /Fal30%/, "multiple selected extras remain supported")

const hiddenProviders = context.composeCompactText(fixture.composeEntries, {
    providerOrder: "codex,grok",
    quotaSelection: "primary",
    showProvider: false,
    showUsed: true,
    showCredits: false
})
assert.equal(
    hiddenProviders.text,
    "#1 S20% | #2 S40% | ERR",
    "duplicate accounts retain ordinals when provider labels are hidden"
)

const partiallyVisibleAccounts = plain(fixture.composeEntries)
delete partiallyVisibleAccounts[0].compactPrimaryPercentLeft
delete partiallyVisibleAccounts[0].primaryResetsAt
const stableOrdinal = context.composeCompactText(partiallyVisibleAccounts, {
    providerOrder: "codex",
    quotaSelection: "primary",
    showProvider: true,
    showUsed: true,
    showCredits: false
})
assert.equal(stableOrdinal.text, "Cx #2 S40%", "account ordinals remain stable when another account has no selected quota")

const creditsOnly = context.composeCompactText(fixture.composeEntries, {
    providerOrder: "codex,grok",
    quotaSelection: "unknown",
    showProvider: false,
    showUsed: false,
    showCredits: true
})
assert.equal(creditsOnly.text, "#1 Cr 5 | #2 Cr 3 | ERR", "credit-only compact output honors toggles")

const noFields = context.composeCompactText([fixture.composeEntries[0]], {
    providerOrder: "codex",
    quotaSelection: "primary",
    showProvider: false,
    showUsed: false,
    showCredits: false
})
assert.equal(noFields.text, "No compact fields")

const invalidComposed = context.composeCompactText(fixture.composeEntries, {
    providerOrder: "missing",
    quotaSelection: "primary",
    showProvider: true,
    showUsed: true,
    showCredits: true
})
assert.equal(invalidComposed.hasSelection, false)
assert.equal(invalidComposed.text, "No selection")

const costEntries = plain(context.attachProviderCostSummaries(
    fixture.composeEntries, fixture.costSummaries))
assert.equal(costEntries[0].costSummary.todayCost, 2.5)
assert.equal(costEntries[0].costSummaryOwner, true)
assert.equal(costEntries[1].costSummary, null)
assert.equal(costEntries[1].costSummaryOwner, false, "provider-level cost appears only on the first account")
assert.equal(costEntries[2].costSummary.todayCost, 1)

const migrationDefault = "codex,claude,grok,antigravity"
assert.deepEqual(
    plain(context.migrateLegacyProvider("claude", migrationDefault, migrationDefault, false)),
    { order: "claude", writeOrder: true, writeDone: true },
    "a legacy specific provider becomes the compact provider selection"
)
assert.deepEqual(
    plain(context.migrateLegacyProvider("all", migrationDefault, migrationDefault, false)),
    { order: "", writeOrder: true, writeDone: true },
    "legacy all becomes an empty compact provider filter"
)
assert.deepEqual(
    plain(context.migrateLegacyProvider("detect", migrationDefault, migrationDefault, false)),
    { order: migrationDefault, writeOrder: false, writeDone: true },
    "legacy detect keeps the compact default"
)
assert.deepEqual(
    plain(context.migrateLegacyProvider("claude", "grok,codex", migrationDefault, false)),
    { order: "grok,codex", writeOrder: false, writeDone: true },
    "migration never overwrites a personalized compact provider order"
)
assert.deepEqual(
    plain(context.migrateLegacyProvider("claude", migrationDefault, migrationDefault, true)),
    { order: migrationDefault, writeOrder: false, writeDone: false },
    "migration runs only once"
)

const mainQml = fs.readFileSync(mainQmlPath, "utf8")
const configQml = fs.readFileSync(configQmlPath, "utf8")
const configXml = fs.readFileSync(configXmlPath, "utf8")
const metadata = JSON.parse(fs.readFileSync(metadataPath, "utf8"))
assert.match(
    mainQml,
    /ProviderLogic\.replaceProviderEntries\(/,
    "the popup data path updates only the provider that was queried"
)
assert.match(mainQml, /composeCompactBlocks/, "QML delegates compact visual composition to tested pure logic")
assert.match(mainQml, /Plasmoid\.contextualActions:\s*\[/, "the widget exposes user-facing contextual actions")
assert.match(mainQml, /text: i18n\("Open AI CLI Control"\)/, "the widget can open the separate AI CLI selector")
assert.match(mainQml, /launchAiControl\(\["--update", "all"\]\)/, "the widget can invoke the multi-CLI update flow")
assert.match(mainQml, /konsole --hold -e/, "multi-CLI updates keep terminal output visible")
assert.match(mainQml, /aiControlExecutable\.connectSource\(aiControlCommandLine/, "AI actions use the executable bridge")
assert.match(mainQml, /id: aiControlButton/, "the popup exposes a discoverable AI CLI Control button")
assert.match(mainQml, /id: aiControlMenu/, "the popup AI button offers selector and update actions")
assert.match(mainQml, /ListView \{\s+id: providerTabs/, "popup provider tabs use horizontal scrolling")
assert.match(mainQml, /preferredWidth: 520/, "popup uses the normative 520 pixel width")
assert.match(
    mainQml,
    /Layout\.minimumHeight: 560\s*Layout\.maximumHeight: 560\s*Layout\.preferredHeight: 560/,
    "popup keeps the normative fixed 560 pixel height"
)
assert.match(
    mainQml,
    /QQC2\.ScrollView \{\s*id: metricScroll[\s\S]*metricContent\.implicitHeight > metricScroll\.availableHeight/,
    "popup keeps overflow content inside the metric scroll view"
)
assert.match(
    mainQml,
    /FontLoader\s*\{\s*id: manropeFont\s*source: Qt\.resolvedUrl\("\.\.\/fonts\/Manrope-Variable\.ttf"\)\s*\}/,
    "popup loads the bundled Manrope variable font"
)
assert.match(
    mainQml,
    /readonly property string designFont: manropeFont\.status === FontLoader\.Ready && manropeFont\.name\.length > 0\s*\? manropeFont\.name\s*: Kirigami\.Theme\.defaultFont\.family/,
    "popup uses the loaded Manrope family with the theme font as a safe fallback"
)
assert.match(mainQml, /"antigravity": "Gemini \(Antigravity\)"/, "popup distinguishes Antigravity from Gemini")
assert.match(mainQml, /"antigravity": "antigravity"/, "Antigravity uses its own supplied icon")
assert.doesNotMatch(mainQml, /"antigravity": "gemini"/, "Antigravity never reuses the Gemini icon")
assert.doesNotMatch(configQml, /cfg_provider\b/, "legacy provider config stays hidden from the settings UI")
assert.match(configQml, /placeholderText: "primary,weekly"/, "settings show the compact quota default")
assert.match(configQml, /text: i18n\("Show all returned providers"\)/, "settings expose an explicit all-providers compact option")
assert.match(configQml, /setCompactProviderSelected\(modelData\.providerId, checked\)/, "settings expose per-provider compact selection controls")
assert.match(configQml, /cfg_aiControlCommand/, "settings expose the AI CLI Control command")
assert.match(configQml, /cfg_claudeRefreshInterval/, "settings expose the Claude refresh interval")
assert.match(configXml, /<entry name="aiControlCommand" type="String">\s*<default>ai<\/default>/, "AI CLI Control uses ai as its default command")
assert.match(configXml, /<entry name="provider" type="String">/, "legacy provider value remains readable for migration")
assert.match(configXml, /<entry name="compactProviderMigrationDone" type="Bool">/, "one-time migration has a persistent flag")
assert.match(
    configXml,
    /<entry name="claudeRefreshInterval" type="Int">\s*<default>300<\/default>\s*<min>60<\/min>\s*<max>3600<\/max>/,
    "Claude refresh defaults to five minutes within its supported range"
)
assert.match(
    configXml,
    /<entry name="compactQuotaSelection" type="String">\s*<default>primary,weekly<\/default>/,
    "the compact quota default excludes extras"
)
assert.equal(metadata.KPlugin.Version, "0.3.3", "package metadata uses version 0.3.3")
assert.equal(metadata.KPlugin.Name, "KodexBar Suite", "package metadata uses the public product name")
assert.equal(metadata.KPlugin.Id, "org.kde.plasma.kodexbar", "the technical plugin ID remains compatible")
assert.doesNotMatch(
    mainQml,
    /used\s*<\s*\d+/,
    "compact extra quotas are never hidden by an automatic usage threshold"
)
assert.match(
    mainQml,
    /if \(!ProviderLogic\.entryHasReportedUsage\(entry\)\) \{\s*return quietColor\s*\}/,
    "a provider without reported usage has a neutral header status dot"
)
assert.match(
    mainQml,
    /root\.metricAccent\([\s\S]*modelData\.worstUsedPercent/,
    "compact status dots use the same metric accent thresholds"
)
assert.match(mainQml, /provider: "all", source: selectedSource, replaceAll: true/, "startup seeds every enabled provider once")
assert.match(mainQml, /property double lastSuccessfulSeedAt: 0/, "the widget records when the last full seed succeeded")
assert.match(
    mainQml,
    /fastRefreshCyclesSinceSeed >= 10\s*&& Date\.now\(\) - lastSuccessfulSeedAt >= claudeRefreshSeconds \* 1000/,
    "the periodic full seed requires both ten fast refreshes and the Claude cadence"
)
assert.match(
    mainQml,
    /if \(activeQueryReplacesAll\) \{\s*lastGoodEntries = ProviderLogic\.reconcileSeedCache\(cached, incoming\)\s*fastRefreshCyclesSinceSeed = 0\s*lastSuccessfulSeedAt = Date\.now\(\)/,
    "only a successful full seed advances its time gate"
)
assert.match(mainQml, /ProviderLogic\.excludeUnfetchableProviderEntries\(normalized\)/, "unfetchable provider responses are excluded before state is updated")
assert.match(mainQml, /ProviderLogic\.reconcileSeedCache\(cached, incoming\)/, "a successful full seed purges stale cached providers")
assert.match(mainQml, /visible: !!\(root\.activeEntry\.costSummary/, "the optional cost-source binding always evaluates to a boolean")
assert.match(mainQml, /visible: !!\(root\.showEmailInWidget && root\.activeEntry\.account\)/, "the optional email binding always evaluates to a boolean")
assert.match(mainQml, /visible: !!\(modelData\.ordinal && modelData\.ordinal\.length > 0\)/, "the optional ordinal binding always evaluates to a boolean")
assert.match(mainQml, /visible: !!\(modelData\.detail && modelData\.detail\.length > 0\)/, "the optional metric-detail binding always evaluates to a boolean")
assert.match(mainQml, /visible: !!\(root\.popupState\.hasEntry\s*&& root\.activeEntry\.statusIndicator/, "the optional status binding always evaluates to a boolean")
assert.match(mainQml, /visible: !!\(root\.showCostSummary\s*&& root\.popupState\.hasEntry\s*&& root\.activeEntry\.costSummary/, "the optional cost-summary binding always evaluates to a boolean")
assert.match(mainQml, /visible: !!\(root\.popupState\.hasEntry\s*&& root\.activeEntry\.dashboardSummary/, "the optional dashboard binding always evaluates to a boolean")
assert.match(mainQml, /provider === "all"/, "known provider IDs defensively exclude the synthetic all seed")
assert.match(mainQml, /id: usageWatchdog[\s\S]*interval: 120000/, "a two-minute watchdog releases hung usage refreshes")
assert.match(
    mainQml,
    /function cancelUsageRefresh\(\) \{[\s\S]*if \(activeQueryReplacesAll\) \{\s*initialUsageSeedPending = true/,
    "cancelling an all-provider seed re-arms its retry"
)
assert.match(
    mainQml,
    /function refreshOtherProviders\(\) \{[\s\S]*if \(providers\.length === 0\) \{\s*if \(knownProviderIds\(true\)\.length === 0\) \{\s*initialUsageSeedPending = true\s*refresh\(\)/,
    "an empty provider result re-enters the all-provider seed path"
)
assert.match(mainQml, /providerCandidates\(\["claude"\]\)/, "Claude refreshes through a provider-specific query")
assert.match(mainQml, /id: claudeRefreshTimer/, "Claude uses a separate refresh timer")
assert.match(mainQml, /i18n\("Banked resets"\)/, "the Codex popup labels banked rate-limit resets")
assert.match(mainQml, /root\.activeEntry\.isCached === true/, "cached popup data has a visible staleness note")

console.log("provider logic fixtures passed")
