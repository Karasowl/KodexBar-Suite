#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const suite = path.resolve(root, "../..");
const qml = fs.readFileSync(path.join(root, "contents/ui/main.qml"), "utf8");
const preferences = fs.readFileSync(path.join(root, "contents/ui/PreferencesWindow.qml"), "utf8");
const config = fs.readFileSync(path.join(root, "contents/config/main.xml"), "utf8");
const installer = fs.readFileSync(path.join(suite, "packages/ai-cli-control/install.sh"), "utf8");
const uninstaller = fs.readFileSync(path.join(suite, "packages/ai-cli-control/uninstall.sh"), "utf8");
const pkgbuild = fs.readFileSync(path.join(suite, "packaging/aur/PKGBUILD"), "utf8");

assert.match(qml, /kind: "skills"/, "skills is a first-class popup tab");
assert.match(qml, /id: skillsContent/, "skills has a dedicated popup surface");
assert.match(qml, /id: skillsExecutable/, "filesystem work is delegated to the skills engine");
assert.match(qml, /id: skillsList/, "skills shows a read-only inventory list");
assert.match(qml, /Read-only inventory/, "skills states that sync is parked");
assert.doesNotMatch(qml, /id: allSkillsCheck/, "the global sync selector is parked");
assert.doesNotMatch(qml, /id: providerSkillCheck/, "provider sync checkboxes are parked");
assert.doesNotMatch(qml, /id: skillsActionBar/, "the preview and apply bar is parked");
assert.doesNotMatch(qml, /id: skillBatchDialog/, "the sync confirmation dialog is parked");
assert.doesNotMatch(qml, /Preview changes/, "no preview step in read-only mode");
assert.doesNotMatch(qml, /Apply changes/, "no apply step in read-only mode");
assert.match(config, /name="skillsCommand"/, "the skills engine path is configurable");
assert.match(preferences, /workingSkillsCommand/, "preferences preserve the configured engine");
for (const source of [installer, uninstaller, pkgbuild]) {
    assert.match(source, /kodexbar-skills/, "packaging owns the skills engine");
}

console.log("skills QML static checks passed");
