#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const qml = fs.readFileSync(path.join(root, "contents/ui/main.qml"), "utf8");
const config = fs.readFileSync(path.join(root, "contents/config/main.xml"), "utf8");

assert.match(qml, /id: aiControlButton/, "AI CLI Control remains a separate header action");
assert.match(qml, /id: aiControlPopup/, "AI CLI Control opens the overlapping local inspector");
assert.match(qml, /source: "utilities-terminal"/, "AI CLI Control uses the terminal affordance");
assert.match(qml, /id: headerTabs/, "provider and local tabs live in the compact header");
assert.match(qml, /id: headerIdentity[\s\S]{0,180}width: Math\.max\(0, headerTabs\.x - 64\)/, "the identity column has a width independent of its title row")
assert.match(qml, /id: headerTitleRow/, "the header title row is explicitly identified")
assert.match(qml, /width: Math\.max\(0, headerTitleRow\.width - headerTitleLabel\.width - headerTitleRow\.spacing\)/, "the plan width is derived from the explicit title row")
assert.doesNotMatch(qml, /headerTabs\.x - 8 - \(parent\.x \+ parent\.width\)/, "header text never depends on its own row implicit width")
assert.match(qml, /Layout\.preferredHeight: 1/, "the inherited wide tab band is replaced by a hairline divider");
assert.doesNotMatch(qml, /text: "KodexBar Suite"/, "the inherited generic popup heading is not the visual target");
assert.doesNotMatch(qml, /AI provider quotas/, "the inherited generic popup subtitle is not the visual target");
assert.match(qml, /root\.activeEntry\.displayName/, "the header identifies the selected provider");
assert.match(qml, /width: 32/, "provider tabs are compact icon controls");
assert.match(qml, /modelData\.kind === "local" && providerTabs\.count > 1/, "Local follows provider icons behind a separator");
assert.match(qml, /Layout\.preferredHeight: 520/, "the popup uses the compact 520px viewport");
const popupCard = qml.slice(qml.indexOf("id: popupCard"), qml.indexOf("ColumnLayout", qml.indexOf("id: popupCard")));
assert.doesNotMatch(popupCard, /anchors\.margins/, "the 520px viewport is the visible card, not an inset legacy card");
assert.match(qml, /radius: 18/, "the popup keeps the approved minimal rounded card");
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
assert.match(qml, /delegate: Rectangle \{\s*required property var modelData\s*required property int index\s*readonly property bool groupStart/, "the full local list explicitly receives its delegate index");
assert.match(qml, /delegate: Item \{\s*required property var modelData\s*required property int index\s*readonly property bool groupStart/, "the AI CLI popover explicitly receives its delegate index");
assert.doesNotMatch(qml, /(?:visible|enabled): modelData\.capabilities &&/, "capability-driven boolean properties never receive undefined");
assert.match(qml, /visible: !!\(modelData\.capabilities && \(modelData\.capabilities\.releaseRuntime/, "runtime release controls coerce sparse capabilities to booleans");
assert.match(qml, /visible: !!\(modelData\.capabilities && modelData\.capabilities\.stopRuntime\)/, "runtime stop controls coerce sparse capabilities to booleans");
assert.match(qml, /Layout\.maximumHeight: 340/, "local inventory keeps the approved compact scroll limit");
assert.match(qml, /localKindGlyph/, "local rows are grouped with a semantic type glyph");
assert.match(qml, /localModelMeta/, "local rows retain size, quantization, VRAM and confidence evidence");
assert.match(qml, /context\.setLineDash\(\[2, 3\]\)/, "loaded idle models render a quiet dashed activity line");
assert.match(qml, /text: i18n\("%1 mdl"/, "the compact footer reports active local models");
const localReleaseDialog = qml.slice(qml.indexOf("id: localReleaseDialog"), qml.indexOf("id: localStopDialog"));
const localStopDialog = qml.slice(qml.indexOf("id: localStopDialog"), qml.indexOf("id: previewStrip", qml.indexOf("id: localStopDialog")));
assert.match(localReleaseDialog, /implicitWidth: 300/, "release dialog has a fixed intrinsic content width");
assert.match(localStopDialog, /implicitWidth: 300/, "stop dialog has a fixed intrinsic content width");
assert.doesNotMatch(localReleaseDialog, /\n\s*width: 300/, "release dialog avoids a dialog width binding loop");
assert.doesNotMatch(localStopDialog, /\n\s*width: 300/, "stop dialog avoids a dialog width binding loop");
assert.doesNotMatch(qml, /PlasmaComponents\.Label\s*\{[\s\S]{0,400}\n\s*implicit(?:Width|Height)\s*:/, "labels do not assign read-only intrinsic dimensions");
assert.match(qml, /classificationConfidence/, "classification confidence is rendered");
assert.match(qml, /localMetricText/, "missing throughput has an honest label");
assert.match(qml, /state === "installed"/, "installed but unmounted rows are preserved");
assert.match(qml, /localModelsRefreshTimer/, "periodic local refresh is configured");
assert.match(config, /localModelsRefreshInterval/, "refresh interval is configurable");
assert.strictEqual((qml.match(/Layout\.preferredHeight: 8\b/g) || []).length, 0, "quota bars no longer use the legacy 8px height");
assert.match(qml, /Layout\.preferredHeight: 6/, "quota bars use the thin 6px line");
assert.strictEqual((qml.match(/text: root\.formatUsedPercent/g) || []).length, 1, "percentage has one visual position below its bar");
assert.ok(qml.indexOf("text: root.formatUsedPercent") > qml.indexOf("id: segmentTrack"), "percentage follows the quota activity lines");
assert.match(qml, /id: localStopDialog/, "stopping a runtime has a separate confirmation dialog");
assert.match(qml, /modelData\.capabilities\.stopRuntime/, "stop controls only appear for declared capabilities");
assert.match(qml, /Invalid local runtime action/, "runtime actions validate normalized identifiers before the data-engine command");

console.log("local model QML static checks passed");
