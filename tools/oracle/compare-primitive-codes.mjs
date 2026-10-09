#!/usr/bin/env node
// Exact TS7 CLI vs Odin primitive checker: compare diagnostic CODE + START.
// TS7 --pretty false exposes line/column but no authoritative end-span here.
// This is NOT full span/message/category parity or official conformance.
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {resolve} from "node:path";
import {fileURLToPath} from "node:url";

const root=resolve(fileURLToPath(new URL("../..",import.meta.url)));
const tsc=process.env.TSODIN_TSC;
const checker=process.env.TSODIN_CHECKTRACE;
if(!tsc||!checker)throw new Error("Set TSODIN_TSC and TSODIN_CHECKTRACE");
const fixtures=[
  {id:"checker-primitives-valid",expectedCount:0},
  {id:"checker-primitives-errors",expectedCount:2},
  {id:"checker-primitives-utf16",expectedCount:1},
  {id:"checker-boolean-valid",expectedCount:0},
  {id:"checker-boolean-errors",expectedCount:2},
  {id:"checker-logic-valid",expectedCount:0},
  {id:"checker-logic-errors",expectedCount:2},
  {id:"checker-literal-valid",expectedCount:0},
  {id:"checker-literal-disjoint",expectedCount:3},
  {id:"checker-const-literal-valid",expectedCount:0},
  {id:"checker-const-literal-disjoint",expectedCount:3},
  {id:"checker-domain-valid",expectedCount:0},
  {id:"checker-domain-errors",expectedCount:5},
  {id:"checker-wide-valid",expectedCount:0},
  {id:"checker-wide-errors",expectedCount:4},
  {id:"checker-unary-wide-valid",expectedCount:0},
  {id:"checker-unary-wide-errors",expectedCount:2},
  {id:"checker-unary-singleton-valid",expectedCount:0},
  {id:"checker-unary-singleton-errors",expectedCount:4},
  {id:"checker-unary-singleton-flow-errors",expectedCount:2},
  {id:"checker-flow-assign-valid",expectedCount:0},
  {id:"checker-flow-assign-errors",expectedCount:2},
  {id:"checker-flow-branch-valid",expectedCount:0},
  {id:"checker-flow-branch-errors",expectedCount:2},
  {id:"checker-flow-negative-valid",expectedCount:0},
  {id:"checker-flow-negative-errors",expectedCount:3},
  {id:"checker-flow-guards-valid",expectedCount:0},
  {id:"checker-flow-guards-errors",expectedCount:6},
  {id:"checker-flow-nested-valid",expectedCount:0},
  {id:"checker-flow-nested-errors",expectedCount:5},
  {id:"checker-flow-compound-valid",expectedCount:0},
  {id:"checker-flow-compound-errors",expectedCount:5},
  {id:"checker-flow-rhs-valid",expectedCount:0},
  {id:"checker-flow-rhs-errors",expectedCount:5},
  {id:"checker-flow-contradiction-valid",expectedCount:0},
  {id:"checker-flow-contradiction-errors",expectedCount:2},
  {id:"checker-flow-dead-assign-valid",expectedCount:0},
  {id:"checker-flow-dead-assign-errors",expectedCount:3},
  {id:"checker-flow-three-guards-valid",expectedCount:0},
  {id:"checker-flow-three-guards-errors",expectedCount:7},
  {id:"checker-flow-three-nested-valid",expectedCount:0},
  {id:"checker-flow-three-nested-errors",expectedCount:5},
  {id:"checker-flow-mixed-rhs-valid",expectedCount:0},
  {id:"checker-flow-mixed-rhs-errors",expectedCount:4},
  {id:"checker-flow-mixed-left-valid",expectedCount:0},
  {id:"checker-flow-mixed-left-errors",expectedCount:5},
  {id:"checker-flow-mixed-nested-valid",expectedCount:0},
  {id:"checker-flow-mixed-nested-errors",expectedCount:9},
];
function call(cmd,args,cwd){
  const result=spawnSync(cmd,args,{cwd,encoding:"utf8",timeout:45000,maxBuffer:1048576});
  if(result.error||result.signal||result.status===null){
    throw new Error("Command did not finish: "+String(result.error||result.signal||result.status));
  }
  return result;
}
const version=call(tsc,["--version"],root);
assert.equal(version.status,0);
assert.match(version.stdout,/7\.0\.2\s*$/,"reference version drift");
const records=[];
for(const fixture of fixtures){
  const cwd=resolve(root,"tests/oracle",fixture.id);
  const ts=call(tsc,["-p","tsconfig.json","--noEmit","--pretty","false","--incremental","false","--singleThreaded"],cwd);
  const odin=call(checker,[resolve(cwd,"index.ts")],root);
  const upstream=[...(ts.stdout+"\n"+ts.stderr).matchAll(/^(?:.*[\\/])?index\.ts\((\d+),(\d+)\):\s*error TS(\d+):/gm)]
    .map(m=>({code:Number(m[3]),line:Number(m[1]),column:Number(m[2])}));
  const actual=[...odin.stdout.matchAll(/^DIAG\t(\d+)\t(\d+)\t(\d+)\t(\d+)\t(\d+)$/gm)]
    .map(m=>({kind:Number(m[1]),line:Number(m[2])+1,column:Number(m[3])+1,
      endLine:Number(m[4])+1,endColumn:Number(m[5])+1}));
  assert.equal(odin.status,fixture.expectedCount?1:0,fixture.id+": Odin semantic exit");
  assert.equal(ts.status===0,!fixture.expectedCount,fixture.id+": pinned TS7 exit");
  assert.equal(upstream.length,fixture.expectedCount,fixture.id+": expected TS7 errors");
  assert.equal(actual.length,fixture.expectedCount,fixture.id+": expected Odin diagnostics");
  for(const item of actual){
    assert.ok(item.kind===10 || item.kind===11 || item.kind===12,fixture.id+": unmapped Odin issue");
    assert.ok(item.endLine>item.line ||
             (item.endLine===item.line && item.endColumn>item.column),
             fixture.id+": invalid Odin diagnostic span");
  }
  const mapped=actual.map(d=>({code:d.kind===10?2322:2367,line:d.line,column:d.column}));
  if(fixture.id==="checker-primitives-utf16") {
    // Emoji precedes the declaration ON THE SAME LINE. UTF-8 byte columns
    // are different from UTF-16 units; this locks the real TS7 coordinate.
    assert.deepEqual(upstream,[{code:2322,line:2,column:16}],
      "Pinned TS7 inline non-BMP/CRLF diagnostic start changed");
  }
  assert.deepEqual(upstream,mapped,fixture.id+": TS7 code/start UTF-16 mismatch");
  records.push({fixture:fixture.id,reference:upstream,odin:mapped,
    codeParityChecked:true,startPositionParityChecked:true,
    endPositionParityChecked:false,categoryParityChecked:false,messageParityChecked:false});
  console.log("PASS "+fixture.id+": "+actual.length+" mapped TS2322/TS2367 codes and UTF-16 start positions match pinned TS7");
}
console.log("START_WITNESS "+JSON.stringify({
  schemaVersion:2,kind:"primitive-code-start-witness-not-conformance",
  referenceVersion:"7.0.2",tsodinCommit:process.env.GITHUB_SHA||null,records,
}));
