#!/usr/bin/env node
"use strict";

// A QML property binding must never be split by an inserted line: a ternary
// whose branches land on detached lines silently rebinds the wrong property
// (this once turned every provider chip label dim).

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
for (const file of ["contents/ui/main.qml", "contents/ui/PreferencesWindow.qml"]) {
    const lines = fs.readFileSync(path.join(root, file), "utf8").split("\n");
    lines.forEach((line, index) => {
        if (!/^\s*font\.weight:/.test(line) || index === 0) {
            return;
        }
        const prev = lines[index - 1].replace(/\s+$/, "");
        const next = (lines[index + 1] || "").replace(/^\s+/, "");
        const continues = /[:?,\(\[]$/.test(prev) || /^[?:]/.test(next);
        assert.ok(
            !continues,
            `${file}:${index + 1} splits an expression (prev: ${prev.slice(-50)} / next: ${next.slice(0, 50)})`
        );
    });
}

console.log("binding sanity checks passed");
