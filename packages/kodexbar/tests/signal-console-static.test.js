#!/usr/bin/env node
"use strict"

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const root = path.resolve(__dirname, "..")
const qml = fs.readFileSync(path.join(root, "contents/ui/main.qml"), "utf8")
const preferences = fs.readFileSync(path.join(root, "contents/ui/PreferencesWindow.qml"), "utf8")

const topBarStart = qml.indexOf("component SignalTopBar: Item")
const quotaStart = qml.indexOf("component SignalQuotaRow: Item")
const providerStart = qml.indexOf("component SignalProviderView: Item")
const compactStart = qml.indexOf("component CompactStrip: Item")

assert.ok(topBarStart >= 0, "Signal Console has a global product bar")
assert.ok(quotaStart > topBarStart, "Signal Console has a reusable quota row")
assert.ok(providerStart > quotaStart, "Signal Console has a focused provider surface")
assert.ok(compactStart > providerStart, "Signal Console components close before compact mode")

const topBar = qml.slice(topBarStart, quotaStart)
const quotaRow = qml.slice(quotaStart, providerStart)
const providerView = qml.slice(providerStart, compactStart)

assert.match(topBar, /source: Qt\.resolvedUrl\("\.\.\/icons\/kodexbar\.svg"\)/, "the product bar restores the packaged K mark")
assert.match(topBar, /label: i18n\("Providers"\)/, "provider navigation has a visible label")
assert.match(topBar, /label: i18n\("Local"\)/, "local navigation has a visible label")
assert.match(topBar, /label: i18n\("Skills"\)/, "skills navigation has a visible label")
assert.match(topBar, /root\.signalIconSource\(signalDestination\.modelData\.icon\)/, "destinations share one packaged icon family")
assert.match(topBar, /height: 3[\s\S]{0,120}signalDestination\.selected/, "selected destination has a persistent underline")
assert.match(topBar, /Accessible\.description:/, "top-level navigation announces selection")

assert.doesNotMatch(providerView, /id: signalProviderMark/, "the redundant provider hero is removed")
assert.match(providerView, /id: signalProviderIdentity/, "provider views retain a compact identity header")
assert.match(providerView, /id: signalProviderLogo[\s\S]{0,180}root\.providerIconSource\(root\.activeEntry\.provider\)/, "provider identity uses the packaged provider logo")
assert.match(providerView, /root\.activeEntry\.plan[\s\S]{0,500}root\.activeEntry\.source[\s\S]{0,500}root\.activeEntry\.account/, "provider identity preserves plan, source, and privacy-controlled account context")
assert.match(providerView, /contentWidth: availableWidth/, "provider scroll content follows the available viewport width")
assert.match(providerView, /width: signalProviderScroll\.availableWidth/, "provider layout owns the full reference viewport")
assert.match(providerView, /height: Math\.max\(implicitHeight, signalProviderScroll\.availableHeight\)/, "short provider content still fills the fixed viewport")
assert.match(providerView, /text: i18n\("Quota usage"\)/, "quota group has a clear heading")
assert.match(providerView, /\? i18n\("Spend"\)\s*: i18n\("Credits"\)/, "cost becomes one condensed line")
assert.match(providerView, /root\.signalCostSummaryRows\(/, "the spend strip uses concise reference-style values")
assert.match(providerView, /signalProviderView\.detailRows/, "provider-specific supplemental data remains visible")
assert.match(providerView, /text: i18n\("No usage reported"\)/, "connected providers retain an explicit empty state")
assert.doesNotMatch(providerView, /text: i18n\("Switch provider"\)/, "the compact panel is the single provider switcher")
assert.doesNotMatch(providerView, /capacity remaining/, "the implementation does not repeat the generated percentage error")

assert.match(quotaRow, /used >= 80[\s\S]{0,180}root\.errorColor/, "critical usage has a semantic error state")
assert.match(quotaRow, /root\.formatUsedPercent\(/, "quota labels use the real normalized usage contract")
assert.match(quotaRow, /rowData\.segments/, "Grok composition remains available in the redesigned row")
assert.match(quotaRow, /root\.formatResetDateTime\(rowData\.resetsAt\)/, "quota rows retain the reference-style absolute reset detail")
assert.doesNotMatch(topBar + quotaRow + providerView, /font\.pixelSize: (?:8|9|10)\b/, "Signal Console avoids inherited microtype")
assert.match(qml, /id: compactPreviewSection\s*visible: false\s*Layout\.fillWidth: true\s*Layout\.preferredHeight: 0/, "the inherited compact preview is removed from the full surface")

assert.match(
    qml,
    /width: 520\s*height: 400\s*implicitWidth: 520[\s\S]{0,80}implicitHeight: 400[\s\S]{0,260}Layout\.minimumWidth: 520[\s\S]{0,220}Layout\.minimumHeight: 400[\s\S]{0,120}Layout\.preferredHeight: 400/,
    "the compact 520 by 400 viewport is stable"
)
assert.match(qml, /signal providerActivated\(string selectionKey\)/, "compact provider blocks expose an activation contract")
assert.match(qml, /required property int index\s*required property var modelData/, "compact provider delegates declare the repeater index they use")
assert.match(qml, /root\.selectedEntryKey = selectionKey[\s\S]{0,80}root\.expanded = true/, "compact provider blocks open the exact provider")
const compactStrip = qml.slice(compactStart, qml.indexOf("compactRepresentation: Item", compactStart))
assert.doesNotMatch(compactStrip, /QQC2\.ToolTip/, "compact provider navigation never covers taskbar icons with hover overlays")
const compactRep = qml.slice(qml.indexOf("compactRepresentation: Item"), qml.indexOf("fullRepresentation: Item"))
assert.match(compactRep, /compactContentWidth/, "the panel representation sizes itself from every provider block")
assert.doesNotMatch(compactRep, /Layout\.maximumWidth:\s*520/, "the compact panel is not hard-capped at 520px so extra accounts can push the item wider")
assert.match(compactStrip, /ElideNone/, "panel provider quota labels keep their full text instead of clipping siblings")
assert.match(preferences, /function signalIcon\(name\)/, "preferences share the packaged icon family")
assert.match(preferences, /palette\.base: preferences\.th\("#14161d"\)[\s\S]{0,300}palette\.buttonText: preferences\.th\("#e9ebf2"\)/, "preferences keep native controls legible on the dark surface")
assert.match(preferences, /text: i18n\("Panel preview"\)/, "preferences avoid inherited all-caps microtype")
assert.match(preferences, /component PreferenceCard: Rectangle[\s\S]{0,260}color: "transparent"[\s\S]{0,80}border\.width: 0/, "preference groups use flat sections instead of card soup")

console.log("Signal Console static checks passed")
