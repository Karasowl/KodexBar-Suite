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
assert.match(qml, /id: skillBatchDialog/, "synchronization requires a visible confirmation");
assert.match(qml, /id: allSkillsCheck/, "the matrix offers one safe global selector");
assert.match(qml, /id: providerSkillCheck/, "every provider cell has a checkbox");
assert.match(qml, /id: skillsActionBar/, "skills keeps a fixed preview and apply action bar");
assert.match(qml, /id: previewSkillChangesButton/, "skills exposes an explicit preview step");
assert.match(qml, /id: applySkillChangesButton[\s\S]{0,520}root\.skillsPreview !== null/, "apply remains locked until a preview succeeds");
assert.match(qml, /function invalidateSkillPreview\(\)/, "editing the selection invalidates a stale preview");
assert.match(qml, /text: i18n\("Status"\)/, "the skill-first matrix has a dedicated status column");
assert.match(qml, /root\.skillProviderIconSource\(modelData\.id\)/, "provider columns use real packaged provider marks");
assert.match(qml, /"batch", "--changes-json", JSON\.stringify\(changes\)/, "the preview sends one validated batch");
assert.match(qml, /JSON\.stringify\(skillsPendingChanges\),\s*"--apply"/, "confirmation applies the exact previewed selection");
assert.match(qml, /the whole batch is cancelled/, "the dialog states the atomic conflict boundary");
assert.match(qml, /Matching copies are backed up first/, "the dialog states the backup contract");
assert.match(qml, /Conflicts are locked/, "the matrix exposes blocked provider cells");
assert.match(qml, /payload\.skills instanceof Array/, "inventory and mutation responses have separate handling");
assert.match(qml, /payload\.applied === true[\s\S]{0,100}root\.refreshSkills/, "an applied sync is verified with a fresh inventory");
assert.doesNotMatch(qml, /completedOperation === "preview"[\s\S]{0,180}skillBatchDialog\.open\(\)/, "preview does not skip the explicit Apply action");
assert.doesNotMatch(qml, /function refreshSkills\(\)[\s\S]{0,500}"--apply"/, "read-only refresh cannot apply a sync");
assert.match(config, /name="skillsCommand"/, "the skills engine path is configurable");
assert.match(preferences, /workingSkillsCommand/, "preferences preserve the configured engine");
for (const source of [installer, uninstaller, pkgbuild]) {
    assert.match(source, /kodexbar-skills/, "packaging owns the skills engine");
}

console.log("skills QML static checks passed");
