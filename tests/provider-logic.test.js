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
    "Cx #1 P20% Fas #1 20% Fal30% Cr 5 | Cx #2 P40% Fas #2 40% Cr 3 | Gk ERR",
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
assert.equal(compactDefault.text, "Cx P19% W0% | Cl ERR | Gk P8% W31% | Ag P0% W1%")
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
    "#1 P20% | #2 P40% | ERR",
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
assert.equal(stableOrdinal.text, "Cx #2 P40%", "account ordinals remain stable when another account has no selected quota")

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
    /attachProviderCostSummaries\(result\.entries, root\.costSummaries\)/,
    "the popup data path retains every returned provider"
)
assert.match(mainQml, /composeCompactBlocks/, "QML delegates compact visual composition to tested pure logic")
assert.match(mainQml, /ListView \{\s+id: providerTabs/, "popup provider tabs use horizontal scrolling")
assert.match(mainQml, /preferredWidth: 520/, "popup uses the normative 520 pixel width")
assert.match(mainQml, /preferredHeight: 560/, "popup uses the normative 560 pixel height")
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
assert.match(configXml, /<entry name="provider" type="String">/, "legacy provider value remains readable for migration")
assert.match(configXml, /<entry name="compactProviderMigrationDone" type="Bool">/, "one-time migration has a persistent flag")
assert.match(
    configXml,
    /<entry name="compactQuotaSelection" type="String">\s*<default>primary,weekly<\/default>/,
    "the compact quota default excludes extras"
)
assert.equal(metadata.KPlugin.Version, "0.3.0", "package metadata uses version 0.3.0")
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

console.log("provider logic fixtures passed")
