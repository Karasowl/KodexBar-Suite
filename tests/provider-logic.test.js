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
assert.match(
    mainQml,
    /attachProviderCostSummaries\(result\.entries, root\.costSummaries\)/,
    "the popup data path retains every returned provider"
)
assert.match(mainQml, /composeCompactText/, "QML delegates final compact composition to tested pure logic")
assert.match(mainQml, /QQC2\.ScrollView \{\s+id: providerChipScroll/, "popup provider chips use horizontal scrolling")
assert.match(mainQml, /"antigravity": "Gemini \(Antigravity\)"/, "popup distinguishes Antigravity from Gemini")
assert.doesNotMatch(configQml, /cfg_provider\b/, "legacy provider config stays hidden from the settings UI")
assert.match(configXml, /<entry name="provider" type="String">/, "legacy provider value remains readable for migration")
assert.match(configXml, /<entry name="compactProviderMigrationDone" type="Bool">/, "one-time migration has a persistent flag")
assert.doesNotMatch(
    mainQml,
    /used\s*<\s*\d+/,
    "compact extra quotas are never hidden by an automatic usage threshold"
)

console.log("provider logic fixtures passed")
