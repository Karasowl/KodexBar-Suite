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
assert.match(qml, /text: i18n\("Local models"\)/, "local models tab is present");
assert.match(qml, /ScrollBar\.horizontal\.policy: ScrollBar\.AlwaysOff/, "local list cannot create horizontal scrolling");
assert.match(qml, /classificationConfidence/, "classification confidence is rendered");
assert.match(qml, /localMetricText/, "missing throughput has an honest label");
assert.match(qml, /state === "installed"/, "installed but unmounted rows are preserved");
assert.match(qml, /localModelsRefreshTimer/, "periodic local refresh is configured");
assert.match(config, /localModelsRefreshInterval/, "refresh interval is configurable");

console.log("local model QML static checks passed");
