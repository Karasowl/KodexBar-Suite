#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const qml = fs.readFileSync(path.join(root, "contents/ui/main.qml"), "utf8");
const config = fs.readFileSync(path.join(root, "contents/config/main.xml"), "utf8");

assert.match(qml, /id: aiControlButton/, "AI CLI Control remains a separate header action");
assert.doesNotMatch(qml, /text: "KodexBar Suite"/, "the inherited generic popup heading is not the visual target");
assert.doesNotMatch(qml, /AI provider quotas/, "the inherited generic popup subtitle is not the visual target");
assert.match(qml, /root\.activeEntry\.displayName/, "the header identifies the selected provider");
assert.match(qml, /width: 32/, "provider tabs are compact icon controls");
assert.match(qml, /modelData\.kind === "local" && providerTabs\.count > 1/, "Local follows provider icons behind a separator");
assert.match(qml, /Layout\.preferredHeight: 520/, "the popup uses the compact 520px viewport");
assert.match(qml, /text: i18n\("Local models"\)/, "local models tab is present");
const localScrollStart = qml.indexOf("id: localModelsScroll");
const localListStart = qml.indexOf("id: localModelsList", localScrollStart);
const localDelegateStart = qml.indexOf("delegate: Rectangle", localListStart);
const localScrollShell = qml.slice(localScrollStart, localListStart);
const localList = qml.slice(localListStart, localDelegateStart);
assert.match(localScrollShell, /QQC2\.ScrollBar\.horizontal\.policy: QQC2\.ScrollBar\.AlwaysOff/, "local scroll view disables horizontal scrolling");
assert.match(localList, /contentWidth: width/, "local list width cannot exceed its viewport");
assert.match(localList, /flickableDirection: Flickable\.VerticalFlick/, "local list only scrolls vertically");
assert.doesNotMatch(localList, /ScrollBar\./, "local list never dereferences a nullable scrollbar attachment");
const localReleaseDialog = qml.slice(qml.indexOf("id: localReleaseDialog"), qml.indexOf("id: localStopDialog"));
const localStopDialog = qml.slice(qml.indexOf("id: localStopDialog"), qml.indexOf("Item {", qml.indexOf("id: localStopDialog")));
assert.match(localReleaseDialog, /implicitWidth: 300/, "release dialog has a fixed intrinsic content width");
assert.match(localStopDialog, /implicitWidth: 300/, "stop dialog has a fixed intrinsic content width");
assert.doesNotMatch(localReleaseDialog, /\n\s*width: 300/, "release dialog avoids a dialog width binding loop");
assert.doesNotMatch(localStopDialog, /\n\s*width: 300/, "stop dialog avoids a dialog width binding loop");
assert.match(qml, /classificationConfidence/, "classification confidence is rendered");
assert.match(qml, /localMetricText/, "missing throughput has an honest label");
assert.match(qml, /state === "installed"/, "installed but unmounted rows are preserved");
assert.match(qml, /localModelsRefreshTimer/, "periodic local refresh is configured");
assert.match(config, /localModelsRefreshInterval/, "refresh interval is configurable");
assert.strictEqual((qml.match(/Layout\.preferredHeight: 8/g) || []).length, 0, "quota bars no longer use the legacy 8px height");
assert.match(qml, /Layout\.preferredHeight: 6/, "quota bars use the thin 6px line");
assert.strictEqual((qml.match(/text: root\.formatUsedPercent/g) || []).length, 1, "percentage has one visual position below its bar");
assert.ok(qml.indexOf("text: root.formatUsedPercent") > qml.indexOf("id: segmentTrack"), "percentage follows the quota activity lines");
assert.match(qml, /id: localStopDialog/, "stopping a runtime has a separate confirmation dialog");
assert.match(qml, /modelData\.capabilities\.stopRuntime/, "stop controls only appear for declared capabilities");
assert.match(qml, /Invalid local runtime action/, "runtime actions validate normalized identifiers before the data-engine command");

console.log("local model QML static checks passed");
