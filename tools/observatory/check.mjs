#!/usr/bin/env node
// Offline tests: live Observatory must never display archived benchmark claims
// or claim passing CI when GitHub has no matching workflow evidence.
import assert from "node:assert/strict";
import {readFileSync,existsSync} from "node:fs";
import {resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {inspectSource,utf16AtByteOffset,summarizeSourceTree,latestMainWorkflow,workflowOutcome,validateConformanceReport} from "../../lib/observatory-core.mjs";
import {ORBIT_STAGES,nextOrbitStage,orbitStage} from "../../lib/architecture-orbit.mjs";
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

const labCss=get("lab.css");
for(const surface of [".lab-pre",".lab-caps",".lab-tree",".lab-json"]){
  assert.ok(labCss.includes("#lab "+surface),
    "Lab must explicitly theme scrollable "+surface);
  assert.ok(labCss.includes("#lab "+surface+"::-webkit-scrollbar-thumb"),
    "Blink/WebKit thumb must follow Lab blue for "+surface);
}
assert.match(labCss,/scrollbar-color:\s*var\(--blue\) var\(--surface-2\)/,
  "Firefox scrollbar uses Observatory blue and dark track");
assert.match(labCss,/scrollbar-width:\s*thin/,
  "Keep compact but visible Firefox scrollbars");
const html=get("index.html");
assert.match(html, /<title>tsodin — Compiler Observatory<\/title>/);
assert.match(html, /href="\.\/live\.css\?v=20261009-live-orbit"/);
assert.match(html, /href="\.\/soft-glass\.css\?v=20261008-xray-editor"/);
assert.match(html, /GITHUB · CURRENT STATE/);
const sparkCount=(html.match(/<svg class="spark-icon"/g)??[]).length;
assert.equal(sparkCount,3,"Hero note, Product Truth and footer use consistent SVG sparks");
assert.doesNotMatch(html,/✳|&#x2733;|&#10035;/i,
  "Emoji-presentable Unicode star must not return to the site");
assert.match(html,/<span class="tiny-cross" aria-hidden="true"><svg class="spark-icon"/,
  "Product Truth icon must be font- and emoji-independent");
assert.match(html,/<span class="footer-spark" aria-hidden="true"><svg class="spark-icon"/,
  "Footer icon must be font- and emoji-independent");
assert.match(html,/<span class="star-mark" aria-hidden="true"><svg class="spark-icon"/,
  "Overview note icon must be font- and emoji-independent");
assert.match(get("styles.css"),/\.tiny-cross \{ color:var\(--green\)/,
  "Product Truth icon must follow the blue-glass theme token");
assert.match(get("styles.css"),/\.spark-icon \{[^}]*width:20px;[^}]*height:20px;/,
  "Symbols must have explicit stable dimensions on mobile");
assert.match(html, /data-panel="conformance" hidden/);
assert.match(html, /data-view="overview"/);
assert.match(html, /aria-controls="conformance"/);
for(const panel of ["activity","pipeline","conformance","xray","principles"]) {
  assert.match(html,new RegExp('id="'+panel+'"[^>]*data-panel="'+panel+'" hidden'));
}
assert.match(html, /Not measured/);
assert.match(html, /REFERENCE TOOL · NOT ODIN EXECUTION/);
for(const id of ["main","activity","pipeline","xray","source-input","byte-offset","last-checked","latest-sha","main-ci","capability-list","refresh-button"]) {
 assert.match(html,new RegExp('id="'+id+'"'));
}
for(const file of ["index.html","styles.css","soft-glass.css","live.css","favicon.svg","app.js","lib/observatory-core.mjs","lib/architecture-orbit.mjs","data/conformance.json"]) assert.ok(existsSync(resolve(root,file)),file+" missing");
const js=get("app.js");
assert.match(js,/api\.github\.com\/repos\/megaalive\/tsodin/);
assert.match(js,/Promise\.allSettled/);
assert.match(js,/source tree/);
assert.match(js,/Cannot confirm CI for current HEAD/);
assert.match(js,/selectView/);
assert.match(html, /src="\.\/app\.js\?v=20261009-live-orbit"/);
const theme=get("soft-glass.css");
assert.match(theme,/\.state-pill\.neutral,\s*\.state-pill\.pending\s*\{[^}]*background:\s*rgba\(54,121,180/s,
  "Neutral and pending badges must use muted blue glass rather than inherited gray");
assert.match(theme,/button\.quiet-link\s*\{[^}]*appearance:\s*none/s,
  "Secondary action must not use a native gray button skin");
assert.match(theme,/input\.byte-slider\s*\{[^}]*--range-progress:\s*0%/s,
  "X-Ray slider uses an explicit blue rail with a progress variable");
assert.match(theme,/input\.byte-slider::-webkit-slider-thumb/,
  "Blink/WebKit thumb must use the theme");
assert.match(theme,/input\.byte-slider::-moz-range-thumb/,
  "Firefox thumb must use the theme");
assert.match(js,/slider\.style\.setProperty\("--range-progress"/,
  "X-Ray control must update its filled track when position changes");
assert.match(js,/publishedConformance/);
assert.deepEqual(ORBIT_STAGES.map(x=>x.key),["source","symbols","types"]);
assert.deepEqual([nextOrbitStage(0),nextOrbitStage(1),nextOrbitStage(2),nextOrbitStage(-1)],[1,2,0,0]);
assert.equal(orbitStage("types").file,"src/checker/primitive.odin");
assert.equal(orbitStage("unknown"),null);
for(const stage of ORBIT_STAGES){
  assert.match(html,new RegExp('data-orbit-stage="'+stage.key+'"'));
  assert.ok(stage.file.startsWith("src/"),"source-backed stage link");
}
assert.match(html,/id="orbit-motion-toggle"[^>]*aria-pressed="false"/);
assert.match(html,/animated architecture illustration, not a running compiler/i);
assert.match(html,/id="orbit-detail"[^>]*role="group"/);
assert.match(js,/initArchitectureOrbit/);
const orbitJs=get("lib/architecture-orbit.mjs");
assert.match(orbitJs,/prefers-reduced-motion/);
assert.match(orbitJs,/visibilitychange/);
assert.match(orbitJs,/root\.classList\.toggle\("orbit-paused",[\s\S]*manualPause \|\| media\.matches/);
assert.match(orbitJs,/interacting/);
assert.match(orbitJs,/selectedPanel\?\.hidden/);
assert.match(orbitJs,/setInterval\(\(\)=>\{current=nextOrbitStage\(current\);paint\(\);\},4800\)/);
assert.doesNotMatch(orbitJs,/fetch\(|XMLHttpRequest|localStorage|requestAnimationFrame/);
const orbitCss=get("live.css");
assert.match(orbitCss,/@keyframes orbit-halo/);
assert.match(orbitCss,/\.orbit-paused \.orbit-ring/);
assert.match(orbitCss,/@media\(prefers-reduced-motion:reduce\)/);
assert.match(html, /id="edit-source"[^>]*aria-controls="source-input"/,
  "X-Ray must provide an explicit, discoverable edit action");
assert.match(html, /id="source-input"[^>]*aria-describedby="source-edit-hint"/,
  "Editable textarea needs a visible instructional description");
assert.match(html, /Click Edit code or tap the editor to type/,
  "The first-visit prompt must clearly invite actual typing");
assert.doesNotMatch(html, /EDIT ANY TIME/,
  "Do not revert to a tiny non-actionable edit label");
assert.match(js, /editSource\.addEventListener\("click",\(\)=>\{/,
  "Edit action must be wired to a click");
assert.match(js, /input\.focus\(\)/,
  "Edit action must focus the actual editable input");
assert.match(js, /input\.addEventListener\("focus"/,
  "Editing cue must respond to keyboard or touch focus");
assert.match(js, /input\.addEventListener\("blur"/,
  "Editing cue must clear on blur");
assert.match(theme, /\.editor-edit-action\s*\{[^}]*appearance:\s*none/s,
  "Edit action must use intentional blue-glass styling, not native gray");
assert.match(theme, /\.editor-panel\.is-editing\s*\.source-edit-hint/,
  "Focus state must visibly reinforce that this is a live editor");
assert.match(theme, /@media \(max-width:460px\)[\s\S]*#source-input\s*\{font-size:16px;/,
  "Mobile editing text must avoid tiny tap/zoom targets");
assert.match(get("styles.css"),/prefers-reduced-motion:reduce/);
const footerCss=get("live.css");
assert.match(html,/<footer class="site-footer">/,"semantic footer remains in document");
assert.match(footerCss,/body > \.site-footer\s*\{[^}]*position:\s*fixed/s,
  "footer must remain attached to viewport, not scroll with content");
assert.match(footerCss,/body > \.site-footer\s*\{[^}]*bottom:\s*0/s,
  "dock is pinned to viewport bottom");
assert.match(footerCss,/body\s*\{[^}]*padding-bottom:\s*calc\(82px \+ env\(safe-area-inset-bottom/s,
  "desktop content clearance must include footer and device safe area");
assert.match(footerCss,/@media \(max-width: 900px\)[\s\S]*body \{ padding-bottom: calc\(65px \+ env\(safe-area-inset-bottom/s,
  "mobile clearance must reserve footer and device safe area");
assert.match(footerCss,/\.site-footer \.footer-inner\s*\{[^}]*flex-wrap:\s*nowrap/s,
  "fixed footer should not unexpectedly grow to multiple rows");
assert.match(footerCss,/body > \.site-footer\s*\{[^}]*padding:\s*10px 0/s,
  "footer remains compact");
assert.doesNotMatch(footerCss,/body > \.site-footer\s*\{[^}]*margin-top:\s*auto/s,
  "old flow-only footer positioning must not return");

for(const path of ["index.html","app.js","live.css","lib/observatory-core.mjs","preview/index.html","preview/soft/index.html","preview/neon/index.html"]) {
 assert.doesNotMatch(get(path),/megaalive\/ts-fp|odin-hotpath|HOTPATH_P6|0\.821656|P1.?P6|synthetic microkernel/i,path+" leaked old research");
}
assert.equal(existsSync(resolve(root,"data/observatory.json")),false);
assert.equal(existsSync(resolve(root,"preview/soft/data/observatory.json")),false);
assert.equal(existsSync(resolve(root,"preview/neon/data/observatory.json")),false);

const report=JSON.parse(get("data/conformance.json"));
const unrun=validateConformanceReport(report);
assert.equal(unrun.status,"not_run");
assert.equal(unrun.counts,null);
assert.equal(unrun.rate,null);
assert.throws(()=>validateConformanceReport({...report,counts:{passed:0,failed:0}}),/Unrun/);
assert.throws(()=>validateConformanceReport({...report,status:"measured"}),/Measured/);
const evidence={
  ...report,status:"measured",testedTsodinRevision:"a".repeat(40),
  testedAt:"2026-10-08T11:00:00Z",
  workflowRunUrl:"https://github.com/megaalive/tsodin/actions/runs/1234",
  counts:{passed:4,failed:1,unsupported:50,skipped_by_scope:8,not_run:20}
};
assert.equal(validateConformanceReport(evidence).rate,.8);
assert.throws(()=>validateConformanceReport({...evidence,counts:{...evidence.counts,passed:0,failed:0}}),/No executed/);
assert.throws(()=>validateConformanceReport({...evidence,workflowRunUrl:"https://other.example/1"}),/Measured/);

console.log("PASS: live-only dashboard, fail-closed CI status, source inventory, Unicode, assets and no legacy benchmark data");
