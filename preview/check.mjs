import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repo = resolve(fileURLToPath(new URL(".", import.meta.url)));
const get = p => readFileSync(resolve(repo,p),"utf8");
const root = get("../index.html");
const landing = get("index.html");
assert.match(landing, /href="\.\/soft\/index\.html"/);
assert.match(landing, /href="\.\/neon\/index\.html"/);
for(const option of ["soft","neon"]) {
  const html = get(option+"/index.html");
  const css = get(option === "soft" ? "../soft-glass.css" : "neon.css");
  assert.ok(html.startsWith("<!doctype html>"));
  assert.match(html, /VISUAL COMPARISON · SOFT IS LIVE/);
  assert.match(html, /aria-label="Compare preview themes"/);
  assert.match(html, /href="\.\.\/\.\.\/styles\.css"/);
  assert.match(html, /src="\.\.\/\.\.\/app\.js"/);
  assert.match(html, option === "soft" ? /href="\.\.\/\.\.\/soft-glass\.css"/ : /href="\.\.\/neon\.css"/);
  assert.match(html, /Benchmark Arena|The Benchmark/);
  assert.match(html, /Synthetic microkernels only/);
  for(const link of ["../../styles.css","../../app.js","../../favicon.svg",option === "soft" ? "../../soft-glass.css" : "../neon.css","data/observatory.json"]) {
    assert.ok(existsSync(resolve(repo,option,link)),option+": broken asset "+link);
  }
  const archive = JSON.parse(get(option+"/data/observatory.json"));
  assert.equal(archive.authoritativeSummary.class,"HOTPATH_P6_STRONG");
  assert.ok(css.length > 4500);
  assert.match(css, /backdrop-filter:blur\(/);
  assert.match(css, /--green:#/);
}
assert.match(root, /href="\.\/soft-glass\.css"/);
assert.ok(!root.includes("VISUAL COMPARISON · SOFT IS LIVE"));
console.log("PASS: two standalone branch previews, relative assets, unchanged scientific data and live root");
