const assert = require("node:assert/strict")
const { spawnSync } = require("node:child_process")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const vm = require("node:vm")

const root = path.resolve(__dirname, "..")
const logicPath = path.join(root, "contents/code/providerLogic.js")
const fixturePath = path.join(__dirname, "fixtures/provider-logic.json")
const mainQmlPath = path.join(root, "contents/ui/main.qml")
const preferencesQmlPath = path.join(root, "contents/ui/PreferencesWindow.qml")
const legacyConfigQmlPath = path.join(root, "contents/ui/config/configGeneral.qml")
const legacyConfigEntryQmlPath = path.join(root, "contents/config/config.qml")
const configXmlPath = path.join(root, "contents/config/main.xml")
const metadataPath = path.join(root, "metadata.json")
const quotasEnginePath = path.resolve(root, "../ai-cli-control/kodexbar-quotas")
// Absolute interpreter so synthetic PATH cannot hide python3 itself.
const python3Path = (() => {
    const candidates = ["/usr/bin/python3", "/bin/python3"]
    for (const candidate of candidates) {
        if (fs.existsSync(candidate)) {
            return candidate
        }
    }
    return "python3"
})()
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
    plain(context.commandCandidates("")),
    ["kodexbar-quotas", "codexbar"],
    "the empty command uses the local quota engine before upstream CodexBar"
)
assert.deepEqual(
    plain(context.commandCandidates("codexbar")),
    ["kodexbar-quotas", "codexbar"],
    "the legacy default command receives the same compatibility chain"
)
assert.deepEqual(
    plain(context.commandCandidates("kodexbar-quotas")),
    ["kodexbar-quotas", "codexbar"],
    "the configured default command keeps its upstream compatibility fallback"
)
assert.deepEqual(
    plain(context.commandCandidates("/opt/custom-codexbar")),
    ["/opt/custom-codexbar"],
    "a custom command remains the user's only candidate"
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
assert.equal(normalizedAntigravity.primary.windowMinutes, 10080)
assert.equal(normalizedAntigravity.secondary.windowMinutes, 300)

const unchangedClaude = context.normalizeUsageWindows(
    "claude",
    fixture.antigravityUsage.primary,
    fixture.antigravityUsage.secondary
)
assert.equal(unchangedClaude.primary.windowMinutes, 10080, "other providers keep their original windows")
assert.equal(unchangedClaude.secondary.windowMinutes, 300)

const antigravityRows = [
    { title: "Gemini weekly", compactKey: "gemini-weekly", compactLabel: "W", compactExtra: true, antigravityQuota: true, percentLeft: 99.943274, resetsAt: "2026-07-29T15:43:38Z", windowBadge: "W", windowMinutes: 10080 },
    { title: "Gemini 5-hour", compactKey: "gemini-5h", compactLabel: "S", compactExtra: true, antigravityQuota: true, percentLeft: 99.65964, resetsAt: "2026-07-22T20:43:38Z", windowBadge: "5h", windowMinutes: 300 },
    { title: "Claude/GPT weekly", compactKey: "claude-gpt-weekly", compactLabel: "CW", compactExtra: true, antigravityQuota: true, percentLeft: 65.824175, resetsAt: "2026-07-29T12:10:59Z", windowBadge: "W", windowMinutes: 10080 },
    { title: "Claude/GPT 5-hour", compactKey: "claude-gpt-5h", compactLabel: "C5h", compactExtra: true, antigravityQuota: true, percentLeft: 0, resetsAt: "2026-07-22T20:44:48Z", windowBadge: "5h", windowMinutes: 300 }
]
const antigravityCompact = plain(context.composeCompactBlocks([{ provider: "antigravity", rows: antigravityRows }], {
    providerOrder: "antigravity", quotaSelection: "primary,weekly", showProvider: true, showUsed: true, showCredits: false
}))
assert.equal(antigravityCompact.text, "Ag S0% W0%")
// Antigravity compact S maps only to gemini 300-minute window, W only to 10080-minute weekly.
for (const row of antigravityRows) {
    if (row.compactLabel === "S") {
        assert.equal(row.compactKey, "gemini-5h", "label S is only for the Gemini five-hour window")
        assert.equal(row.windowMinutes, 300, "label S is only for the 300-minute Gemini window")
    }
    if (row.compactLabel === "W") {
        assert.equal(row.compactKey, "gemini-weekly", "label W is only for the Gemini weekly window")
        assert.equal(row.windowMinutes, 10080, "label W is only for the 10080-minute window")
    }
}
assert.doesNotMatch(antigravityCompact.text, /\bCW|\bC5h/, "default compact Antigravity hides Claude/GPT model windows")
assert.equal(
    antigravityCompact.blocks[0].worstUsedPercent,
    100 - 99.65964,
    "hidden Claude/GPT exhaustion does not tint the Antigravity compact block"
)
assert.equal(antigravityCompact.blocks[0].status, "good", "Antigravity severity uses only visible Gemini windows")
const narrowedAntigravity = context.composeCompactBlocks([{ provider: "antigravity", rows: antigravityRows }], {
    providerOrder: "antigravity", quotaSelection: "antigravity.gemini-weekly", showProvider: true, showUsed: true, showCredits: false
})
assert.equal(narrowedAntigravity.text, "Ag W0%", "provider-scoped Antigravity selection narrows model windows")
const explicitClaudeFiveHour = plain(context.composeCompactBlocks([{ provider: "antigravity", rows: antigravityRows }], {
    providerOrder: "antigravity", quotaSelection: "antigravity.claude-gpt-5h", showProvider: true, showUsed: true, showCredits: false
}))
assert.equal(
    explicitClaudeFiveHour.text,
    "Ag C5h100%",
    "explicit antigravity.claude-gpt-5h selection surfaces C5h in compact"
)
assert.equal(
    explicitClaudeFiveHour.blocks[0].worstUsedPercent,
    100,
    "explicit Claude/GPT selection drives compact severity from the named window"
)
assert.deepEqual(antigravityRows.map(row => row.windowBadge), ["W", "5h", "W", "5h"])

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

const retryClassificationCases = [
    [{ errorMessage: "socket offline", errorCategory: "network", errorRetryable: true }, true],
    [{ errorMessage: "request timed out", errorCategory: "timeout", errorRetryable: true }, true],
    [{ errorMessage: "invalid JSON", errorCategory: "invalid_response", errorRetryable: true }, true],
    [{ errorMessage: "HTTP 429", errorCategory: "rate_limit", errorRetryable: false }, false],
    [{ errorMessage: "credentials expired", errorCategory: "authentication", errorRetryable: false }, false],
    [{ errorMessage: "plan not included", errorCategory: "entitlement", errorRetryable: false }, false]
]
for (const [entry, expected] of retryClassificationCases) {
    assert.equal(
        context.isRetryableProviderError(entry),
        expected,
        `${entry.errorCategory} receives the expected startup retry classification`
    )
}
assert.equal(
    context.isRetryableProviderError({ errorMessage: "upstream codexbar timed out after 15 seconds" }),
    true,
    "legacy transient errors remain classifiable without structured metadata"
)
assert.equal(
    context.isRetryableProviderError({ errorMessage: "Claude OAuth credentials are unavailable" }),
    false,
    "legacy authentication errors are excluded before transient text matching"
)

const startupErrors = [
    { provider: "claude", errorMessage: "socket offline", errorCategory: "network", errorRetryable: true },
    { provider: "codex", errorMessage: "HTTP 429", errorCategory: "rate_limit", errorRetryable: false },
    { provider: "grok", errorMessage: "credentials expired", errorCategory: "authentication", errorRetryable: false },
    { provider: "antigravity", errorMessage: "invalid JSON", errorCategory: "invalid_response", errorRetryable: true }
]
assert.deepEqual(
    Array.from(context.startupRetryProviderIds(startupErrors, [], {})),
    ["claude", "antigravity"],
    "only transient provider failures without cached data receive a startup retry"
)
assert.deepEqual(
    Array.from(context.startupRetryProviderIds(startupErrors, [goodClaudeEntry], {})),
    ["antigravity"],
    "a last good provider entry suppresses its startup retry"
)
assert.deepEqual(
    Array.from(context.startupRetryProviderIds(startupErrors, [], { claude: true, antigravity: true })),
    [],
    "each provider can receive at most one startup retry before normal cadence resumes"
)

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

// First-run guidance from the real kodexbar-quotas engine must remain visible
// (not purged as unfetchable). The JS side pins the exact literal so a Python
// message change fails this test instead of keeping a stale copy.
const expectedFirstRunClaudeGuidance =
    "Claude quotas need a Claude Code sign-in or a CodexBar provider config. " +
    "Sign in with Claude Code to create ~/.claude/.credentials.json, " +
    "or create ~/.config/codexbar/config.json with an enabled providers list."
const syntheticHome = fs.mkdtempSync(path.join(os.tmpdir(), "kodexbar-first-run-home-"))
const syntheticBin = fs.mkdtempSync(path.join(os.tmpdir(), "kodexbar-first-run-bin-"))
let firstRunClaudeGuidance
try {
    const engineEnv = {
        ...process.env,
        HOME: syntheticHome,
        PATH: syntheticBin,
        LANG: "C"
    }
    for (const key of ["BROWSER", "DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR"]) {
        delete engineEnv[key]
    }
    const engineResult = spawnSync(
        python3Path,
        [quotasEnginePath, "usage", "--format", "json", "--json-only", "--provider", "all"],
        {
            env: engineEnv,
            encoding: "utf8"
        }
    )
    assert.equal(
        engineResult.status,
        0,
        `kodexbar-quotas first-run exit ${engineResult.status}: ${engineResult.stderr || engineResult.error || engineResult.stdout}`
    )
    const engineEntries = JSON.parse(engineResult.stdout)
    assert.equal(engineEntries.length, 1, "first-run engine emits a single Claude guidance entry")
    firstRunClaudeGuidance = engineEntries[0].error.message
    assert.equal(
        firstRunClaudeGuidance,
        expectedFirstRunClaudeGuidance,
        "real kodexbar-quotas first-run guidance matches the pinned literal"
    )
} finally {
    fs.rmSync(syntheticHome, { recursive: true, force: true })
    fs.rmSync(syntheticBin, { recursive: true, force: true })
}
assert.equal(
    context.isUnfetchableProviderError({
        provider: "claude",
        errorMessage: firstRunClaudeGuidance
    }),
    false,
    "first-run Claude guidance must not match the unfetchable-provider purge regex"
)
assert.deepEqual(
    plain(context.excludeUnfetchableProviderEntries([{
        provider: "claude",
        errorMessage: firstRunClaudeGuidance
    }])).entries.map(entry => entry.provider),
    ["claude"],
    "first-run Claude guidance stays in the widget provider list"
)

// Native Codex/Grok human errors must stay visible (re-login, network, schema drift).
// Pinned literals match packages/ai-cli-control/kodexbar-quotas user-facing constants.
const nativeHumanErrorMessages = [
    "Sign in to Codex again to see quotas (run: codex).",
    "Sign in to Grok again (run: grok login).",
    "Codex is unreachable right now. Check your connection and retry.",
    "Grok is unreachable right now. Check your connection and retry.",
    "Could not read Codex quotas. Install the codexbar-cli-bin package as a fallback, or update KodexBar.",
    "Could not read Grok quotas. Install the codexbar-cli-bin package as a fallback, or update KodexBar."
]
for (const errorMessage of nativeHumanErrorMessages) {
    assert.equal(
        context.isUnfetchableProviderError({ provider: "codex", errorMessage }),
        false,
        `native human error must not match unfetchable purge: ${errorMessage}`
    )
}

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
assert.equal(compactDefault.text, "Cx S19% W0% | Cl ERR | Gk S8% W31% | Ag S0% W0%")
assert.deepEqual(
    compactDefault.blocks.map(block => block.provider),
    ["codex", "claude", "grok", "antigravity"],
    "the default compact model keeps every configured provider in order"
)
assert.equal(compactDefault.blocks[1].displayText, "ERR", "compact errors stay visible")
assert.deepEqual(
    compactDefault.blocks.map(block => block.worstUsedPercent),
    [19, null, 31, 100 - 99.65964],
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

const zeroCreditsHidden = context.composeCompactText([
    {
        provider: "codex",
        account: "zero",
        creditsRemaining: 0,
        compactPrimaryPercentLeft: 50,
        rows: []
    },
    {
        provider: "codex",
        account: "positive",
        creditsRemaining: 4,
        compactPrimaryPercentLeft: 50,
        rows: []
    }
], {
    providerOrder: "codex",
    quotaSelection: "",
    showProvider: false,
    showUsed: false,
    showCredits: true
})
assert.equal(
    zeroCreditsHidden.text,
    "#1 | #2 Cr 4",
    "compact credits are gated to remaining > 0 (zero balance is hidden)"
)
assert.doesNotMatch(zeroCreditsHidden.text, /Cr 0/, "zero credit balances never appear in compact text")

// Grok native: weekly aggregate lives only in secondary. compactPrimary must stay null so
// default primary,weekly does not emit a Session (S) copy of the same weekly percent.
const grokWeeklyOnlyEntry = {
    provider: "grok",
    name: "Grok",
    compactPrimaryPercentLeft: null,
    primaryResetsAt: null,
    secondaryPercentLeft: 43,
    secondaryResetsAt: "2026-07-22T15:26:13Z",
    rows: [
        {
            title: "Weekly",
            percentLeft: 43,
            usageKnown: true,
            compactKey: "weekly",
            compactExtra: false,
            windowBadge: "W"
        }
    ]
}
const grokCompactDefault = plain(context.composeCompactBlocks([grokWeeklyOnlyEntry], {
    providerOrder: "grok",
    quotaSelection: "primary,weekly",
    showProvider: true,
    showUsed: true,
    showCredits: false
}))
assert.equal(grokCompactDefault.blocks.length, 1, "Grok remains a single compact block")
assert.equal(
    grokCompactDefault.text,
    "Gk W57%",
    "default primary,weekly shows Grok weekly once with badge W (used = 100 - 43)"
)
assert.doesNotMatch(grokCompactDefault.text, /\bS\d/, "Grok compact never labels weekly usage as Session")
assert.equal(
    (grokCompactDefault.text.match(/\d+%/g) || []).length,
    1,
    "Grok compact has exactly one usage percentage part"
)
const grokQuotaParts = grokCompactDefault.blocks[0].quotaText || grokCompactDefault.blocks[0].fullText
assert.match(String(grokQuotaParts), /\bW57%/, "Grok quota part uses weekly badge W")
assert.doesNotMatch(String(grokQuotaParts), /\bS\d/, "Grok quota parts exclude Session badge")

const grokPrimaryOnly = plain(context.composeCompactBlocks([grokWeeklyOnlyEntry], {
    providerOrder: "grok",
    quotaSelection: "primary",
    showProvider: true,
    showUsed: true,
    showCredits: false
}))
// Grok weekly is the canonical compact surface: primary-only still shows W (never S).
assert.equal(grokPrimaryOnly.hasSelection, true, "primary-only still selects weekly-only Grok")
assert.equal(grokPrimaryOnly.blocks.length, 1, "primary-only keeps a single Grok block")
assert.equal(
    grokPrimaryOnly.text,
    "Gk W57%",
    "primary-only shows Grok weekly once with badge W"
)
assert.doesNotMatch(grokPrimaryOnly.text, /\bS\d/, "primary-only never invents a Session percent for Grok")
assert.match(String(grokPrimaryOnly.blocks[0].quotaText || ""), /\bW57%/, "primary-only quota part is weekly W")
assert.doesNotMatch(String(grokPrimaryOnly.blocks[0].quotaText || ""), /\bS\d/, "primary-only quota excludes Session")
// Default primary,weekly must not double-count the same weekly percent.
assert.equal(
    (grokCompactDefault.text.match(/\d+%/g) || []).length,
    1,
    "default primary,weekly still emits one Grok percent"
)

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
const preferencesQml = fs.readFileSync(preferencesQmlPath, "utf8")
const configXml = fs.readFileSync(configXmlPath, "utf8")
const metadata = JSON.parse(fs.readFileSync(metadataPath, "utf8"))

function qmlFunctionSource(name) {
    const start = mainQml.indexOf(`function ${name}(`)
    assert.notEqual(start, -1, `${name} is present in main.qml`)
    const openingBrace = mainQml.indexOf("{", start)
    let depth = 0
    for (let index = openingBrace; index < mainQml.length; index += 1) {
        if (mainQml[index] === "{") depth += 1
        if (mainQml[index] === "}") depth -= 1
        if (depth === 0) return mainQml.slice(start, index + 1)
    }
    assert.fail(`${name} has a closing brace`)
}

const localCommandContext = { localAiCommand: "local-ai" }
vm.createContext(localCommandContext)
vm.runInContext(
    `${qmlFunctionSource("shellQuote")}\n${qmlFunctionSource("localAiCommandLine")}\nthis.localAiCommandLine = localAiCommandLine`,
    localCommandContext,
    { filename: mainQmlPath }
)
const buildLocalCommand = localCommandContext.localAiCommandLine
assert.equal(buildLocalCommand(["status"]), "'local-ai' 'status'", "status uses an explicit argv array")
assert.equal(buildLocalCommand(["mount", "llama_cpp", "llama_cpp:0123456789ab"]), "'local-ai' 'mount' 'llama_cpp' 'llama_cpp:0123456789ab'", "mount uses an explicit argv array")
assert.equal(buildLocalCommand(["unmount", "llama_cpp", "llama_cpp:0123456789ab"]), "'local-ai' 'unmount' 'llama_cpp' 'llama_cpp:0123456789ab'", "unmount uses an explicit argv array")
assert.equal(buildLocalCommand(["release", "llama_cpp", "--confirm"]), "'local-ai' 'release' 'llama_cpp' '--confirm'", "release uses an explicit argv array")
assert.equal(buildLocalCommand(["stop", "llama_cpp", "--confirm"]), "'local-ai' 'stop' 'llama_cpp' '--confirm'", "stop uses an explicit argv array")

assert.match(
    mainQml,
    /ProviderLogic\.replaceProviderEntries\(/,
    "the popup data path updates only the provider that was queried"
)
assert.match(mainQml, /composeCompactBlocks/, "QML delegates compact visual composition to tested pure logic")
assert.match(mainQml, /Plasmoid\.contextualActions:\s*\[/, "the widget exposes user-facing contextual actions")
assert.match(
    mainQml,
    /Plasmoid\.contextualActions:\s*\[\s*PlasmaCore\.Action\s*\{\s*text: i18n\("Configure KodexBar Suite…"\)\s*icon\.name: "configure"\s*onTriggered: root\.openPreferences\(\)/,
    "the first contextual action opens the dedicated preferences window"
)
assert.match(
    mainQml,
    /Component\.onCompleted:\s*\{[\s\S]*const configureAction = Plasmoid\.internalAction\("configure"\)\s*if \(configureAction\) \{\s*configureAction\.visible = false\s*\}/,
    "the stock configure action is hidden only when the shell provides it"
)
assert.match(mainQml, /text: i18n\("Open AI CLI Control"\)/, "the widget can open the separate AI CLI selector")
assert.match(mainQml, /launchAiControl\(\["--update", "all"\]\)/, "the widget can invoke the multi-CLI update flow")
assert.match(mainQml, /konsole --hold -e/, "multi-CLI updates keep terminal output visible")
assert.match(mainQml, /aiControlExecutable\.connectSource\(aiControlCommandLine/, "AI actions use the executable bridge")
assert.match(mainQml, /function localAiCommandLine\(argv\)/, "local-ai command construction receives an explicit argv array")
assert.match(mainQml, /function aiControlCommandLine\(argv, showTerminal\)/, "AI CLI command construction receives an explicit argv array")
assert.doesNotMatch(mainQml, /\barguments\b/, "QML command construction never captures JavaScript's special arguments object")
assert.doesNotMatch(mainQml, /readonly property var configureAction:/, "the popup no longer keeps an unused Plasma configure action")
assert.match(mainQml, /id: configureButton/, "the popup exposes a discoverable configuration button")
assert.match(mainQml, /PreferencesWindow \{\s*id: preferencesWindow\s*appletRoot: root/, "the widget owns one reusable preferences window")
assert.match(mainQml, /function openPreferences\(\) \{\s*preferencesWindow\.openPreferences\(\)/, "the widget routes preference requests to the reusable window")
assert.match(mainQml, /onClicked: root\.openPreferences\(\)/, "the popup gear opens the dedicated preferences window")
assert.match(mainQml, /text: i18n\("Configure"\)/, "the configuration button has a translated tooltip label")
assert.match(mainQml, /id: aiControlButton/, "the popup exposes a discoverable AI CLI Control button")
assert.match(mainQml, /id: aiControlMenu/, "the popup AI button offers selector and update actions")
assert.match(mainQml, /ListView \{\s+id: providerTabs/, "popup provider tabs use horizontal scrolling")
assert.match(mainQml, /preferredWidth: 520/, "popup uses the normative 520 pixel width")
assert.match(
    mainQml,
    /Layout\.minimumHeight: 520\s*Layout\.maximumHeight: 520\s*Layout\.preferredHeight: 520/,
    "popup keeps the normative fixed 520 pixel height"
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
assert.equal(fs.existsSync(legacyConfigQmlPath), false, "the legacy general config page is retired")
assert.equal(fs.existsSync(legacyConfigEntryQmlPath), false, "the legacy config entry point is retired")
assert.match(configXml, /<entry name="aiControlCommand" type="String">\s*<default>ai<\/default>/, "AI CLI Control uses ai as its default command")
assert.match(configXml, /<entry name="sourceDefault" type="String">\s*<default>detect<\/default>/, "the dedicated preferences source setting has an Auto default")
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
assert.equal(metadata.KPlugin.Version, "0.10.0", "package metadata uses version 0.10.0")
assert.equal(metadata.KPlugin.Website, "https://github.com/Karasowl/KodexBar-Suite", "package metadata links to the maintained suite repository")
assert.match(mainQml, /var antigravityWindows = antigravity && Array\.isArray\(usage\.antigravityRateWindows\)/, "popup consumes the engine's Antigravity model windows")
assert.match(mainQml, /compactLabel: antigravityKey === "gemini-weekly" \? "W"/, "compact Antigravity weekly uses W like other providers")
assert.match(mainQml, /antigravityKey === "gemini-5h" \? "S"/, "compact Antigravity five-hour uses S like other providers")
assert.doesNotMatch(mainQml, /gemini-weekly" \? "S"/, "W is not swapped onto the five-hour Gemini key")
assert.doesNotMatch(mainQml, /gemini-5h" \? "W"/, "S is not swapped onto the weekly Gemini key")
assert.doesNotMatch(mainQml, /var normalizedWindows = ProviderLogic\.normalizeUsageWindows/, "popup does not reinterpret Antigravity primary and secondary slots")
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
assert.match(mainQml, /function commandCandidatesForSeed\(\)/, "startup seeds every enabled provider through the command candidate chain")
assert.match(mainQml, /activeFallbackCommand/, "the active candidate remembers its upstream fallback")
assert.match(mainQml, /commandWasNotFound\(data\)/, "only command-not-found failures advance to upstream")
// Missing data engine (widget-only install): friendly setup card, not a provider traceback.
assert.match(mainQml, /objectName: "engineMissingCard"/, "popup exposes the missing-engine setup card")
assert.match(mainQml, /objectName: "engineMissingInstallCommand"/, "setup card exposes the install command field")
assert.match(mainQml, /paru -S kodexbar-suite/, "setup card shows the suite install command")
assert.match(mainQml, /property bool engineNotInstalled: false/, "missing-engine state is explicit and off by default")
assert.match(
    mainQml,
    /if \(root\.activeQueryReplacesAll\) \{\s*root\.markEngineNotInstalled\(\)/,
    "engine-missing card activates only after sentinel with no fallback left"
)
assert.match(
    mainQml,
    /function markEngineNotInstalled\(\) \{[\s\S]*engineNotInstalled = true/,
    "markEngineNotInstalled sets the friendly card state"
)
assert.match(
    mainQml,
    /function wrapEngineCommand\([\s\S]*command -v[\s\S]*engineMissingSentinel\(\)[\s\S]*exec /,
    "command lines probe command -v and emit the missing-engine sentinel only when absent"
)
assert.match(
    mainQml,
    /function engineMissingSentinel\(\) \{\s*return "__KODEXBAR_ENGINE_MISSING__"/,
    "the missing-engine sentinel string is exact and centralized"
)
assert.match(
    mainQml,
    /visible: root\.engineNotInstalled && !root\.loading/,
    "the setup card is visible only while the engine is missing and not loading"
)
assert.match(
    mainQml,
    /i18n\("Data engine not installed"\)/,
    "missing-engine title is internationalized"
)

// activeIsEmpty: zero credits must not hide the empty state (gate is remaining > 0).
assert.match(
    mainQml,
    /var hasPositiveCredits = typeof entry\.creditsRemaining === "number"\s*&& !isNaN\(entry\.creditsRemaining\)\s*&& entry\.creditsRemaining > 0/,
    "activeIsEmpty treats credits as present only when numeric and > 0"
)
assert.match(
    mainQml,
    /&& !hasPositiveCredits/,
    "activeIsEmpty does not treat creditsRemaining 0 as non-empty"
)
// compactPrimary must not fall back to secondary for Grok (avoids S+W duplicate of weekly).
assert.doesNotMatch(
    mainQml,
    /compactPrimary = secondaryLeft/,
    "main.qml must not copy Grok weekly into compact primary/Session"
)
assert.match(
    mainQml,
    /compactPrimaryPercentLeft:\s*antigravity \? null : primaryLeft/,
    "compact primary is Session percent only and absent for Antigravity"
)
// Segmented weekly bar (Grok composition): segments attach to weekly row, not extra windows.
assert.match(
    mainQml,
    /windows\[i\]\.key === "weekly"[\s\S]*normalizeUsageSegments\(windows\[i\]\.data\.segments\)/,
    "normalizeEntry attaches secondary.segments onto the weekly row"
)
assert.match(
    mainQml,
    /standardRow\.segmentLegendItems = ProviderLogic\.formatSegmentLegendParts/,
    "weekly segment legend items are computed in normalizeEntry"
)
assert.doesNotMatch(
    mainQml,
    /i18n\("of %1%",/,
    "segment legend no longer appends an of-used total (header already shows used/left)"
)
assert.doesNotMatch(
    mainQml,
    /segmentLegend\s*=/,
    "single string segmentLegend was replaced by segmentLegendItems"
)
assert.match(
    mainQml,
    /i18n\("%1% left",/,
    "segmented weekly header shows remaining percent"
)
assert.match(
    mainQml,
    /modelData\.segments && modelData\.segments\.length/,
    "popup renders a segmented track when the row carries segments"
)
assert.match(
    mainQml,
    /segmentTrack\.width \* Math\.min\(100, Math\.max\(0, modelData\.points\)\) \/ 100/,
    "each segment width is points/100 of the weekly track"
)
// Accessible legend: circular color swatch + text, same color helper as the bar.
assert.match(
    mainQml,
    /function segmentColor\(title, index\) \{\s*return ProviderLogic\.segmentBarColor\(title, index\)/,
    "QML segmentColor delegates to ProviderLogic.segmentBarColor for bar and legend"
)
assert.match(
    mainQml,
    /root\.segmentColor\(modelData\.title, index\)/,
    "bar and legend both call root.segmentColor"
)
assert.match(
    mainQml,
    /Flow \{[\s\S]*id: segmentLegendFlow[\s\S]*Repeater \{[\s\S]*model: segmentLegendFlow\.legendItems/,
    "legend is a Flow of items that can wrap in a narrow popup"
)
assert.match(
    mainQml,
    /Rectangle \{\s*width: 8\s*height: 8\s*radius: 4\s*color: root\.segmentColor\(modelData\.title, index\)/,
    "each legend item has an 8px circular color dot"
)
assert.match(
    mainQml,
    /Flow \{[\s\S]*id: segmentLegendFlow[\s\S]*PlasmaComponents\.Label \{[\s\S]*color: root\.textColor[\s\S]*font\.pixelSize: 13[\s\S]*font\.weight:\s*Font\.DemiBold/,
    "segment legend labels use textColor, 13px, DemiBold"
)
const segmentLegendLabelBlockMatch = mainQml.match(
    /id: segmentLegendFlow[\s\S]*?PlasmaComponents\.Label \{[\s\S]*?anchors\.verticalCenter:\s*parent\.verticalCenter/
)
assert.ok(
    !!segmentLegendLabelBlockMatch,
    "segment legend label delegate is discoverable"
)
const segmentLegendLabelBlock = segmentLegendLabelBlockMatch
    ? segmentLegendLabelBlockMatch[0]
    : ""
assert.match(
    segmentLegendLabelBlock,
    /color: root\.textColor/,
    "segment legend label uses root.textColor"
)
assert.match(
    segmentLegendLabelBlock,
    /font\.pixelSize:\s*13/,
    "segment legend label uses 13px"
)
assert.match(
    segmentLegendLabelBlock,
    /font\.weight:\s*Font\.DemiBold/,
    "segment legend label uses DemiBold"
)
assert.ok(
    !/font\.pixelSize:\s*12/.test(segmentLegendLabelBlock),
    "segment legend label no longer uses 12px"
)
assert.ok(
    !/color:\s*root\.quietColor/.test(segmentLegendLabelBlock),
    "segment legend label no longer uses root.quietColor"
)
assert.match(
    mainQml,
    /visible: index > 0[\s\S]*width: 1[\s\S]*color: "#0b0c10"/,
    "segment track draws a 1px dark divider on internal frontiers only"
)
assert.doesNotMatch(
    mainQml,
    /\(of %|of %1%|of \$\{/,
    "legend surface does not contain an of-percent suffix"
)

// Pure segment helpers: composition points, not independent usedPercent bars.
const grokSegments = plain(context.normalizeUsageSegments([
    { title: "Grok Build", points: 81 },
    { title: "API", points: 5 },
    { title: "Imagine", points: 1 },
    { title: "Empty", points: 0 },
    { title: "", points: 2 }
]))
assert.deepEqual(
    grokSegments,
    [
        { title: "Grok Build", points: 81 },
        { title: "API", points: 5 },
        { title: "Imagine", points: 1 },
        { title: "Other surface", points: 2 }
    ],
    "normalizeUsageSegments drops non-positive points and fills empty titles"
)
const legendItems = plain(context.formatSegmentLegendParts(grokSegments))
assert.deepEqual(
    legendItems,
    [
        { title: "Grok Build", points: 81, text: "Build 81" },
        { title: "API", points: 5, text: "API 5" },
        { title: "Imagine", points: 1, text: "Imagine 1" },
        { title: "Other surface", points: 2, text: "Other surface 2" }
    ],
    "legend items keep title for color mapping and accessible name+points text"
)
// Example from QA capture: Build 88 · API 5 · Imagine 1 (weekly 94 used, 6 left).
const qaLegend = plain(context.formatSegmentLegendParts([
    { title: "Grok Build", points: 88 },
    { title: "API", points: 5 },
    { title: "Imagine", points: 1 }
]))
assert.deepEqual(
    qaLegend.map(item => item.text),
    ["Build 88", "API 5", "Imagine 1"],
    "QA composition legend texts match approved labels without of-percent"
)
assert.equal(
    qaLegend.map(item => item.text).join(" · "),
    "Build 88 · API 5 · Imagine 1",
    "joined legend matches approved copy"
)
assert.ok(
    legendItems.every(item => !/\bof\b/i.test(item.text)),
    "legend item text never contains of-percent total"
)
// Final palette: Build violet, API cyan, Imagine pink (clearly separable on dark).
assert.equal(context.segmentBarColor("Grok Build", 0), "#7c5cff")
assert.equal(context.segmentBarColor("API", 1), "#22c7e8")
assert.equal(context.segmentBarColor("Imagine", 2), "#ff5ebe")
assert.equal(
    context.segmentBarColor("Other surface", 3),
    "#45d483",
    "unknown/other uses a distinct fallback palette entry"
)
// Legend color must be identical to bar color for the same title/index.
for (let i = 0; i < legendItems.length; i++) {
    assert.equal(
        context.segmentBarColor(legendItems[i].title, i),
        context.segmentBarColor(grokSegments[i].title, i),
        `legend and bar share segmentBarColor for ${legendItems[i].title}`
    )
}
assert.equal(
    context.compactStandardWindowSelected("primary", grokWeeklyOnlyEntry, "weekly", false),
    true,
    "primary-only selection maps to Grok weekly"
)
assert.equal(
    context.compactStandardWindowSelected("primary", grokWeeklyOnlyEntry, "primary", false),
    true,
    "primary key itself remains selected (no percent because compactPrimary is null)"
)
assert.equal(
    context.compactStandardQuotaPart("primary", grokWeeklyOnlyEntry, "primary", "Primary", null, null, false),
    "",
    "Grok primary part stays empty so tray never shows S"
)
assert.equal(
    context.compactStandardQuotaPart(
        "primary", grokWeeklyOnlyEntry, "weekly", "Weekly", 43, "2026-07-22T15:26:13Z", false),
    "W57%",
    "primary-only emits weekly as W57%"
)
assert.equal(
    context.compactStandardQuotaPart(
        "primary,weekly", grokWeeklyOnlyEntry, "weekly", "Weekly", 43, null, false),
    "W57%",
    "default primary,weekly still emits weekly once as W"
)

// Pure classifyEngineResponse / applyEngineResponse from main.qml: execute them
// (not textual source scans, not a test-local imitation of the transition).
function extractQmlFunction(source, name) {
    const header = `function ${name}(`
    const start = source.indexOf(header)
    assert.notEqual(start, -1, `main.qml must define ${name}`)
    let i = source.indexOf("{", start)
    assert.notEqual(i, -1, `${name} must have a body`)
    let depth = 0
    for (; i < source.length; i++) {
        const ch = source[i]
        if (ch === "{") {
            depth++
        } else if (ch === "}") {
            depth--
            if (depth === 0) {
                return source.slice(start, i + 1)
            }
        }
    }
    throw new Error(`unclosed function ${name}`)
}
const engineResponseCtx = {}
vm.createContext(engineResponseCtx)
vm.runInContext(
    extractQmlFunction(mainQml, "classifyEngineResponse"),
    engineResponseCtx,
    { filename: "classifyEngineResponse.js" }
)
vm.runInContext(
    extractQmlFunction(mainQml, "applyEngineResponse"),
    engineResponseCtx,
    { filename: "applyEngineResponse.js" }
)
const classify = engineResponseCtx.classifyEngineResponse
const applyEngineResponse = engineResponseCtx.applyEngineResponse
assert.equal(
    typeof classify,
    "function",
    "classifyEngineResponse is executable via the shared vm harness"
)
assert.equal(
    typeof applyEngineResponse,
    "function",
    "applyEngineResponse is executable via the shared vm harness"
)
assert.equal(
    classify("__KODEXBAR_ENGINE_MISSING__\n", "", 127),
    "engine_missing",
    "exact sentinel on stdout with exit 127 means the primary executable is absent"
)
assert.equal(
    classify("prefix __KODEXBAR_ENGINE_MISSING__ suffix\n", "", 127),
    "normal",
    "sentinel embedded with prefix/suffix is a normal response"
)
assert.equal(
    classify(
        JSON.stringify({
            provider: "claude",
            note: "saw __KODEXBAR_ENGINE_MISSING__ in docs",
            usage: { primary: { usedPercent: 1 } }
        }) + "\n",
        "",
        0
    ),
    "normal",
    "legitimate JSON containing the sentinel string is a normal response"
)
assert.equal(
    classify("", "__KODEXBAR_ENGINE_MISSING__\n", 1),
    "normal",
    "stderr carrying the sentinel with a non-127 exit is a normal response"
)
assert.equal(
    classify("__KODEXBAR_ENGINE_MISSING__\n", "", 0),
    "normal",
    "exact sentinel with exit 0 is a normal response"
)
assert.equal(
    classify("__KODEXBAR_ENGINE_MISSING__\n", "", 127),
    "engine_missing",
    "exact sentinel with exit 127 is engine_missing"
)
assert.equal(
    classify("", "kodexbar-quotas: upstream codexbar is not installed\n", 127),
    "normal",
    "exit 127 without the sentinel is a normal engine/runtime failure"
)
assert.equal(
    classify("", "provider not found\n", 1),
    "normal",
    "stderr 'provider not found' must not look like a missing engine"
)
assert.equal(
    classify("", "credentials: No such file or directory\n", 1),
    "normal",
    "stderr 'No such file or directory' must not look like a missing engine"
)
assert.equal(
    classify("", "", 0),
    "normal",
    "empty timeout-style output without the sentinel is not missing-engine"
)
assert.equal(
    classify('{"provider":"claude","error":{"kind":"provider","message":"rate limited"}}\n', "", 0),
    "normal",
    "JSON provider errors are normal engine responses"
)
// Transition via the productive applyEngineResponse: sentinel, then data, then error.
const cachedEntries = [{ provider: "claude", usage: { primary: { usedPercent: 10 } } }]
const cachedGood = [{ provider: "claude", usage: { primary: { usedPercent: 10 } } }]
let presence = {
    engineNotInstalled: false,
    entries: cachedEntries,
    lastGoodEntries: cachedGood
}
presence = applyEngineResponse(presence, "__KODEXBAR_ENGINE_MISSING__\n", "", 127)
assert.equal(presence.engineNotInstalled, true, "sentinel raises the missing-engine flag")
assert.deepEqual(plain(presence.entries), cachedEntries, "sentinel path does not purge entries")
assert.deepEqual(plain(presence.lastGoodEntries), cachedGood, "sentinel path does not purge lastGoodEntries")
const refreshedEntries = [{ provider: "claude", usage: { primary: { usedPercent: 55 } } }]
presence = applyEngineResponse(
    presence,
    JSON.stringify(refreshedEntries) + "\n",
    "",
    0
)
assert.equal(presence.engineNotInstalled, false, "a later normal response clears the missing-engine flag")
assert.deepEqual(plain(presence.entries), refreshedEntries, "normal data response updates entries")
assert.deepEqual(plain(presence.lastGoodEntries), refreshedEntries, "normal data response refreshes lastGoodEntries")
const goodAfterData = plain(presence.lastGoodEntries)
presence = applyEngineResponse(presence, "", "provider failed: rate limited\n", 1)
assert.equal(presence.engineNotInstalled, false, "a normal error keeps the missing-engine flag down")
assert.deepEqual(plain(presence.lastGoodEntries), goodAfterData, "normal error leaves lastGoodEntries intact")
assert.match(
    mainQml,
    /var presence = root\.applyEngineResponse\(/,
    "usage handler applies the productive presence transition"
)
assert.match(
    mainQml,
    /root\.engineNotInstalled = presence\.engineNotInstalled/,
    "any normal engine response clears the missing-engine card from applyEngineResponse"
)
assert.doesNotMatch(
    mainQml,
    /handleUsageFailure[\s\S]{0,200}engineNotInstalled\s*=\s*true/,
    "ordinary usage failures do not mark the data engine as missing"
)
assert.match(
    mainQml,
    /function refreshCost\(\) \{[\s\S]*pendingCostCommands = ProviderLogic\.commandCandidates\(configuredCodexbarCommand\)[\s\S]*startNextCostCandidate\(\)/,
    "cost acquisition starts with the same command candidate chain"
)
assert.match(
    mainQml,
    /function startNextCostCandidate\(\) \{[\s\S]*costExecutable\.connectSource\(costCommandLine\(pendingCostCommands\.shift\(\)\)\)/,
    "cost acquisition advances through command candidates"
)
assert.match(
    mainQml,
    /if \(root\.commandWasNotFound\(data\)\) \{\s*if \(root\.startNextCostCandidate\(\)\) \{\s*root\.costLoading = true/,
    "a missing quota engine retries the cost query through upstream CodexBar"
)
assert.match(configXml, /<entry name="codexbarCommand" type="String">\s*<default>kodexbar-quotas<\/default>/, "the default command is the quota engine")
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
assert.match(mainQml, /id: startupRetryTimer[\s\S]*interval: 5000/, "transient startup failures wait five seconds before retrying")
assert.match(mainQml, /ProviderLogic\.startupRetryProviderIds\([\s\S]*lastGoodEntries[\s\S]*startupRetryAttemptedProviders/, "startup retry selection is cache-aware and records completed attempts")
assert.match(mainQml, /pendingCandidates = providerCandidates\(providers, true\)/, "startup retries target only the failed providers")
assert.match(mainQml, /if \(loading \|\| startupRetryPending\)/, "normal refreshes cannot overlap the scheduled startup retry")
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
assert.match(preferencesQml, /QQC2\.ApplicationWindow/, "preferences use a Wayland-capable top-level Qt Quick window")
assert.match(preferencesQml, /title: i18n\("KodexBar Suite Preferences"\)/, "preferences use the requested window title")
assert.match(preferencesQml, /function openPreferences\(\) \{[\s\S]*raise\(\)[\s\S]*requestActivate\(\)/, "reopening preferences focuses the single window instance")
assert.match(preferencesQml, /function load\(\) \{[\s\S]*Plasmoid\.configuration\.codexbarCommand/, "preferences read the command setting")
assert.match(preferencesQml, /Plasmoid\.configuration\.codexbarCommand = workingCommand/, "preferences write the command setting")
assert.match(preferencesQml, /function load\(\) \{[\s\S]*Plasmoid\.configuration\.sourceDefault/, "preferences read the selected source")
assert.match(preferencesQml, /Plasmoid\.configuration\.sourceDefault = workingSourceDefault/, "preferences write the selected source")
assert.match(preferencesQml, /function load\(\) \{[\s\S]*Plasmoid\.configuration\.refreshInterval/, "preferences read the general refresh interval")
assert.match(preferencesQml, /Plasmoid\.configuration\.refreshInterval = workingRefreshInterval/, "preferences write the general refresh interval")
assert.match(preferencesQml, /function load\(\) \{[\s\S]*Plasmoid\.configuration\.claudeRefreshInterval/, "preferences read the Claude refresh interval")
assert.match(preferencesQml, /Plasmoid\.configuration\.claudeRefreshInterval = workingClaudeRefreshInterval/, "preferences write the Claude refresh interval")
assert.match(preferencesQml, /function load\(\) \{[\s\S]*Plasmoid\.configuration\.compactProviderOrder/, "preferences read the compact provider order")
assert.match(preferencesQml, /Plasmoid\.configuration\.compactProviderOrder = workingCompactProviderOrder/, "preferences write the compact provider order")
assert.match(preferencesQml, /Plasmoid\.globalShortcut = workingShortcut/, "preferences apply Plasma's global widget shortcut")
assert.match(preferencesQml, /KeySequenceItem/, "preferences expose a native key-sequence capture control")
assert.match(preferencesQml, /compactResultForOrder\(workingCompactProviderOrder, \{[\s\S]*quotaSelection: workingCompactQuotaSelection[\s\S]*showProvider: workingShowProviderInPanel[\s\S]*showUsed: workingShowUsedPercentInPanel[\s\S]*showCredits: workingShowCreditsInPanel/, "the live preview uses the working compact composition")
assert.match(mainQml, /function compactResultForOrder\(providerOrder, overrides\) \{[\s\S]*overrides \|\| \{\}[\s\S]*values\.quotaSelection === undefined[\s\S]*values\.showProvider === undefined[\s\S]*values\.showUsed === undefined[\s\S]*values\.showCredits === undefined/, "compact composition accepts preview overrides while preserving configured fallbacks")
assert.match(preferencesQml, /objectName: "quotaSelectionField"/, "preferences expose the compact quota field")
assert.match(preferencesQml, /objectName: "showProviderCheck"/, "preferences expose the compact provider-label control")
assert.match(preferencesQml, /objectName: "showUsedCheck"/, "preferences expose the compact used-percent control")
assert.match(preferencesQml, /objectName: "showCreditsCheck"/, "preferences expose the compact credits control")
assert.match(preferencesQml, /objectName: "includeStatusCheck"/, "preferences expose the usage-status control")
assert.match(preferencesQml, /objectName: "showEmailCheck"/, "preferences expose the popup-email control")
assert.match(preferencesQml, /objectName: "showCostCheck"/, "preferences expose the popup-cost control")
assert.match(preferencesQml, /Plasmoid\.configuration\.compactQuotaSelection = workingCompactQuotaSelection/, "preferences apply the compact quota selection")
assert.match(preferencesQml, /Plasmoid\.configuration\.showProviderInPanel = workingShowProviderInPanel/, "preferences apply the compact provider-label setting")
assert.match(preferencesQml, /Plasmoid\.configuration\.showUsedPercentInPanel = workingShowUsedPercentInPanel/, "preferences apply the compact used-percent setting")
assert.match(preferencesQml, /Plasmoid\.configuration\.showCreditsInPanel = workingShowCreditsInPanel/, "preferences apply the compact credits setting")
assert.match(preferencesQml, /Plasmoid\.configuration\.includeStatus = workingIncludeStatus/, "preferences apply the usage-status setting")
assert.match(preferencesQml, /Plasmoid\.configuration\.showEmailInWidget = workingShowEmailInWidget/, "preferences apply the popup-email setting")
assert.match(preferencesQml, /Plasmoid\.configuration\.showCostSummary = workingShowCostSummary/, "preferences apply the popup-cost setting")
assert.match(preferencesQml, /function restoreDefaults\(\) \{[\s\S]*workingCompactQuotaSelection = "primary,weekly"[\s\S]*workingShowProviderInPanel = true[\s\S]*workingShowUsedPercentInPanel = true[\s\S]*workingShowCreditsInPanel = false[\s\S]*workingIncludeStatus = false[\s\S]*workingShowEmailInWidget = false[\s\S]*workingShowCostSummary = true/, "restore defaults resets the seven migrated settings")
assert.match(preferencesQml, /text: i18n\("Show all returned providers"\)/, "preferences expose the all-providers compact toggle")
assert.match(
    preferencesQml,
    /function orderedProviderIds\(\) \{[\s\S]*activeProviderIds[\s\S]*providerIds[\s\S]*return ids/,
    "provider chips follow the working CSV order before appending inactive providers"
)
assert.match(preferencesQml, /model: preferences\.compactProviderChipIds/, "the chip repeater uses the CSV-ordered provider model")
assert.match(preferencesQml, /delegate: Item \{[\s\S]*width: chipContent\.width[\s\S]*DropArea \{/, "provider chips keep a Flow slot wrapper with a drop target")
assert.match(preferencesQml, /Drag\.active: dragHandler\.active[\s\S]*Drag\.source: providerChip[\s\S]*Drag\.hotSpot\.x: width \/ 2/, "chip content publishes pointer-centered drag data from its wrapper source")
assert.doesNotMatch(preferencesQml, /DragHandler \{[\s\S]*target: null/, "chip dragging moves the content instead of keeping it static")
assert.match(preferencesQml, /Drag\.onActiveChanged: \{[\s\S]*chipContent\.x = 0[\s\S]*chipContent\.y = 0/, "chip dragging restores the content to its Flow slot on release")
assert.match(preferencesQml, /TapHandler \{[\s\S]*onTapped: preferences\.toggleProvider\(providerChip\.modelData\)[\s\S]*DragHandler \{/, "chip content keeps its tap toggle alongside the drag handler")
assert.match(
    preferencesQml,
    /activeKnownProviderIds[\s\S]*providerIds\.length - preferences\.activeKnownProviderIds\.length/,
    "the disabled counter intersects active IDs with known providers"
)
assert.match(preferencesQml, /i18n\("Version %1", Plasmoid\.metaData\.version/, "the About page reads the package version from metadata")
assert.match(preferencesQml, /i18n\("Restore defaults"\)/, "preferences localize footer actions")

console.log("provider logic fixtures passed")
