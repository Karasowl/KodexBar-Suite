#!/usr/bin/env node
"use strict";

// Every provider key in the QML icon map and every signal icon name used in
// the UI must resolve to a packaged SVG. A missing file renders as a blank
// placeholder, which reads as a missing icon.

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const qml = fs.readFileSync(path.join(root, "contents/ui/main.qml"), "utf8");

const mapBlock = qml.match(/var icons = \{([\s\S]*?)\}/);
assert.ok(mapBlock, "provider icon map exists");
const keys = new Set([...mapBlock[1].matchAll(/"([a-z0-9]+)":/g)].map((m) => m[1]));
const packaged = new Set(
    fs.readdirSync(path.join(root, "contents/icons/providers"))
        .filter((name) => name.endsWith(".svg"))
        .map((name) => name.slice(0, -4))
);
for (const key of keys) {
    assert.ok(packaged.has(key), `provider icon missing for map key: ${key}`);
}

const signalUsed = new Set(
    [...qml.matchAll(/signalIconSource\("([^"]+)"\)/g)].map((m) => m[1])
);
const signalPackaged = new Set(
    fs.readdirSync(path.join(root, "contents/icons/signal"))
        .filter((name) => name.endsWith(".svg"))
        .map((name) => name.slice(0, -4))
);
for (const name of signalUsed) {
    assert.ok(signalPackaged.has(name), `signal icon missing for: ${name}`);
}

console.log("icon asset checks passed");
