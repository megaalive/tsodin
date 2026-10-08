#!/usr/bin/env node
// Offline smoke tests for GitHub Pages; no npm dependencies and no network.
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { geometricMean, inspectSource, utf16AtByteOffset, validateResearchArchive } from "../../lib/observatory-core.mjs";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const get = path => readFileSync(resolve(root, path), "utf8");
const archive = JSON.parse(get("data/observatory.json"));
assert.equal(validateResearchArchive(archive), true);
assert.equal(archive.rounds.length, 6);
assert.deepEqual(archive.rounds.map(item => item.id), ["P1", "P2", "P3", "P4", "P5", "P6"]);
const p6 = archive.rounds[5];
assert.equal(p6.commit, "8e374b388e57fca8b61c359ec4a6dbb792f5c6fe");
assert.equal(p6.values.K1, 0.633695809);
assert.equal(p6.values.K2, 0.944804817);
assert.equal(p6.values.K3, 0.926505222);
assert.equal(archive.authoritativeSummary.sampleRows, 93);
assert.equal(archive.authoritativeSummary.microRows, 6386);
assert.equal(archive.rounds[2].status, "UNSTABLE GLOBAL");
assert.ok(geometricMean(Object.values(p6.values)) < 0.822);
assert.throws(() => geometricMean([1, 0]), /positive finite/);

const unicode = inspectSource("a😀é\n");
assert.deepEqual([unicode.bytes, unicode.units, unicode.scalars], [8, 5, 4]);
assert.equal(utf16AtByteOffset(unicode, 0), 0);
assert.equal(utf16AtByteOffset(unicode, 1), 1);
assert.equal(utf16AtByteOffset(unicode, 2), null);
assert.equal(utf16AtByteOffset(unicode, 3), null);
assert.equal(utf16AtByteOffset(unicode, 4), null);
assert.equal(utf16AtByteOffset(unicode, 5), 3);
assert.equal(utf16AtByteOffset(unicode, 6), null);
assert.equal(utf16AtByteOffset(unicode, 7), 4);
assert.equal(utf16AtByteOffset(unicode, 8), 5);
assert.equal(utf16AtByteOffset(unicode, 9), null);
assert.equal(utf16AtByteOffset(unicode, -1), null);
const crlf = inspectSource("x\r\n");
assert.deepEqual([crlf.bytes, crlf.units, crlf.scalars], [3, 3, 3]);
assert.equal(utf16AtByteOffset(crlf, 3), 3);
const lone = inspectSource("\ud800");
assert.equal(lone.hasUnpairedSurrogate, true);
assert.deepEqual([lone.bytes, lone.units], [3, 1]);
assert.equal(utf16AtByteOffset(lone, 1), null);
const empty = inspectSource("");
assert.equal(utf16AtByteOffset(empty, 0), 0);
assert.equal(utf16AtByteOffset(empty, 1), null);

const html = get("index.html");
assert.match(html, /<title>tsodin — Compiler Observatory<\/title>/);
assert.match(html, /BROWSER REFERENCE · NOT ODIN EXECUTION/);
assert.match(html, /Not yet measurable/);
assert.doesNotMatch(html, /width:19%/);
assert.match(html, /Synthetic microkernels only/);
for (const id of ["main", "arena", "xray", "journey", "status", "source-input", "byte-offset"]) {
  assert.match(html, new RegExp('id="' + id + '"'));
}
for (const localAsset of ["./favicon.svg", "./styles.css", "./app.js", "./lib/observatory-core.mjs", "./data/observatory.json"]) {
  assert.equal(existsSync(resolve(root, localAsset)), true, "Missing local asset " + localAsset);
}
assert.doesNotMatch(html, /(?:https?:)?\/\/(?:unpkg|cdn\.jsdelivr|cdnjs|fonts\.googleapis|esm\.sh)/);
assert.match(get("styles.css"), /prefers-reduced-motion:reduce/);
assert.match(get("app.js"), /textContent/);

console.log("PASS: 6 research rounds, P6 metrics, UTF-8/UTF-16 boundaries, and static-page integrity");
