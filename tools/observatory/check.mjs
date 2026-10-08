#!/usr/bin/env node
// Offline tests: live Observatory must never display archived benchmark claims
// or claim passing CI when GitHub has no matching workflow evidence.
import assert from "node:assert/strict";
import {readFileSync,existsSync} from "node:fs";
import {resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {inspectSource,utf16AtByteOffset,summarizeSourceTree,latestMainWorkflow,workflowOutcome} from "../../lib/observatory-core.mjs";
const root=resolve(fileURLToPath(new URL("../..",import.meta.url)));
const get=path=>readFileSync(resolve(root,path),"utf8");

const unicode=inspectSource("a😀é\n");
assert.deepEqual([unicode.bytes,unicode.units,unicode.scalars],[8,5,4]);
for(const [byte,units] of [[0,0],[1,1],[2,null],[3,null],[4,null],[5,3],[6,null],[7,4],[8,5]]) {
  assert.equal(utf16AtByteOffset(unicode,byte),units, "UTF-8 byte position "+byte);
}
assert.equal(utf16AtByteOffset(unicode,-1),null);
assert.equal(utf16AtByteOffset(unicode,9),null);
const crlf=inspectSource("a\r\n");
assert.deepEqual([crlf.bytes,crlf.units,crlf.scalars],[3,3,3]);
assert.equal(utf16AtByteOffset(crlf,3),3);
const lone=inspectSource("\ud800");
assert.equal(lone.hasUnpairedSurrogate,true);
assert.deepEqual([lone.bytes,lone.units],[3,1]);
assert.equal(utf16AtByteOffset(inspectSource(""),0),0);

const fakeTree={truncated:false,tree:[
 {type:"blob",path:"src/cli/main.odin"},
 {type:"blob",path:"src/source/utf16.odin"},
 {type:"blob",path:"src/source/utf16_test.odin"},
 {type:"blob",path:"tests/oracle/clean/tsconfig.json"},
 {type:"blob",path:"tests/oracle/utf16-crlf/tsconfig.json"},
 {type:"tree",path:"src/parser"},
 {type:"blob",path:"docs/ORACLE.md"}
]};
const summary=summarizeSourceTree(fakeTree);
assert.equal(summary.odinFiles,3);
assert.equal(summary.oracleProjects,2);
assert.deepEqual(summary.capabilities.map(item=>item.found),[true,true,false,false,false,false]);
assert.throws(()=>summarizeSourceTree({tree:[],truncated:true}),/truncated/);
assert.throws(()=>summarizeSourceTree(null),/invalid/);
const sha="f".repeat(40), oldSha="e".repeat(40);
const runs=[
 {name:"Bootstrap CI",head_sha:oldSha,status:"completed",conclusion:"success",created_at:"2026-01-01T12:00:00Z"},
 {name:"Bootstrap CI",head_sha:sha,status:"in_progress",created_at:"2026-01-02T12:00:00Z"},
 {name:"Observatory smoke",head_sha:sha,status:"completed",conclusion:"success",created_at:"2026-01-02T11:00:00Z"}
];
assert.equal(workflowOutcome(latestMainWorkflow(runs,sha)).label,"RUNNING");
assert.equal(workflowOutcome(latestMainWorkflow(runs,"a".repeat(40))).label,"NOT RUN");
assert.equal(workflowOutcome({status:"completed",conclusion:"failure"}).label,"FAIL");
assert.equal(workflowOutcome({status:"completed",conclusion:"cancelled"}).label,"CANCELLED");
assert.equal(workflowOutcome({status:"completed",conclusion:"success"}).label,"PASS");

const html=get("index.html");
assert.match(html, /<title>tsodin — Compiler Observatory<\/title>/);
assert.match(html, /href="\.\/live\.css"/);
assert.match(html, /href="\.\/soft-glass\.css"/);
assert.match(html, /GITHUB · CURRENT STATE/);
assert.match(html, /Not measured/);
assert.match(html, /REFERENCE TOOL · NOT ODIN EXECUTION/);
for(const id of ["main","activity","pipeline","xray","source-input","byte-offset","last-checked","latest-sha","main-ci","capability-list","refresh-button"]) {
 assert.match(html,new RegExp('id="'+id+'"'));
}
for(const file of ["index.html","styles.css","soft-glass.css","live.css","favicon.svg","app.js","lib/observatory-core.mjs"]) assert.ok(existsSync(resolve(root,file)),file+" missing");
const js=get("app.js");
assert.match(js,/api\.github\.com\/repos\/megaalive\/tsodin/);
assert.match(js,/Promise\.allSettled/);
assert.match(js,/source tree/);
assert.match(js,/Cannot confirm CI for current HEAD/);
assert.match(get("styles.css"),/prefers-reduced-motion:reduce/);
for(const path of ["index.html","app.js","live.css","lib/observatory-core.mjs","preview/index.html","preview/soft/index.html","preview/neon/index.html"]) {
 assert.doesNotMatch(get(path),/megaalive\/ts-fp|odin-hotpath|HOTPATH_P6|0\.821656|P1.?P6|synthetic microkernel/i,path+" leaked old research");
}
assert.equal(existsSync(resolve(root,"data/observatory.json")),false);
assert.equal(existsSync(resolve(root,"preview/soft/data/observatory.json")),false);
assert.equal(existsSync(resolve(root,"preview/neon/data/observatory.json")),false);
console.log("PASS: live-only dashboard, fail-closed CI status, source inventory, Unicode, assets and no legacy benchmark data");
