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

assert.match(topBar, /text: "KodexBar"[\s\S]{0,520}text: "Suite"/, "brand lockup follows the approved reference")
assert.match(topBar, /label: i18n\("Providers"\)/, "provider navigation has a visible label")
assert.match(topBar, /label: i18n\("Local"\)/, "local navigation has a visible label")
assert.match(topBar, /label: i18n\("Skills"\)/, "skills navigation has a visible label")
assert.match(topBar, /root\.signalIconSource\(signalDestination\.modelData\.icon\)/, "destinations share one packaged icon family")
assert.match(topBar, /height: 3[\s\S]{0,120}signalDestination\.selected/, "selected destination has a persistent underline")
assert.match(topBar, /Accessible\.description:/, "top-level navigation announces selection")

assert.match(providerView, /id: signalProviderMark[\s\S]{0,360}width: 64\s*height: 64/, "selected provider has the reference-sized identity tile")
assert.match(providerView, /font\.pixelSize: 27/, "provider name owns the hero hierarchy")
assert.match(providerView, /contentWidth: availableWidth[\s\S]{0,220}width: signalProviderScroll\.availableWidth/, "provider content owns the full reference viewport")
assert.match(providerView, /text: i18n\("Quota usage"\)/, "quota group has a clear heading")
assert.match(providerView, /\? i18n\("Spend"\)\s*: i18n\("Credits"\)/, "cost becomes one condensed line")
assert.match(providerView, /root\.signalCostSummaryRows\(/, "the spend strip uses concise reference-style values")
assert.match(providerView, /text: i18n\("Switch provider"\)/, "provider switching follows the quota summary")
assert.match(providerView, /\n\s*height: 56/, "provider choices have a generous desktop target")
assert.match(providerView, /\n\s*width: 30\s*\n\s*height: 30[\s\S]{0,160}\n\s*width: 22\s*\n\s*height: 22/, "provider logos keep consistent internal padding")
assert.doesNotMatch(providerView, /capacity remaining/, "the implementation does not repeat the generated percentage error")

assert.match(quotaRow, /used >= 80[\s\S]{0,180}root\.errorColor/, "critical usage has a semantic error state")
assert.match(quotaRow, /root\.formatUsedPercent\(/, "quota labels use the real normalized usage contract")
assert.match(quotaRow, /rowData\.segments/, "Grok composition remains available in the redesigned row")
assert.match(quotaRow, /root\.formatResetDateTime\(rowData\.resetsAt\)/, "quota rows retain the reference-style absolute reset detail")
assert.doesNotMatch(topBar + quotaRow + providerView, /font\.pixelSize: (?:8|9|10)\b/, "Signal Console avoids inherited microtype")
assert.match(qml, /id: compactPreviewSection\s*visible: false\s*Layout\.fillWidth: true\s*Layout\.preferredHeight: 0/, "the inherited compact preview is removed from the full surface")

assert.match(
    qml,
    /implicitWidth: 520[\s\S]{0,80}implicitHeight: 560[\s\S]{0,260}Layout\.minimumWidth: 520[\s\S]{0,220}Layout\.minimumHeight: 560[\s\S]{0,120}Layout\.preferredHeight: 560/,
    "the selected 520 by 560 viewport is normative"
)
assert.match(preferences, /function signalIcon\(name\)/, "preferences share the packaged icon family")
assert.match(preferences, /palette\.base: "#14161d"[\s\S]{0,220}palette\.buttonText: "#e9ebf2"/, "preferences keep native controls legible on the dark surface")
assert.match(preferences, /text: i18n\("Panel preview"\)/, "preferences avoid inherited all-caps microtype")
assert.match(preferences, /component PreferenceCard: Rectangle[\s\S]{0,260}color: "transparent"[\s\S]{0,80}border\.width: 0/, "preference groups use flat sections instead of card soup")

console.log("Signal Console static checks passed")
