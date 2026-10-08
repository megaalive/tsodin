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
    assert.equal(item.kind,10,fixture.id+": unmapped Odin issue");
    assert.ok(item.endLine>item.line ||
             (item.endLine===item.line && item.endColumn>item.column),
             fixture.id+": invalid Odin diagnostic span");
  }
  const mapped=actual.map(d=>({code:2322,line:d.line,column:d.column}));
  assert.deepEqual(upstream,mapped,fixture.id+": TS7 code/start UTF-16 mismatch");
  records.push({fixture:fixture.id,reference:upstream,odin:mapped,
    codeParityChecked:true,startPositionParityChecked:true,
    endPositionParityChecked:false,categoryParityChecked:false,messageParityChecked:false});
  console.log("PASS "+fixture.id+": "+actual.length+" TS2322 codes and UTF-16 start positions match pinned TS7");
}
console.log("START_WITNESS "+JSON.stringify({
  schemaVersion:2,kind:"primitive-code-start-witness-not-conformance",
  referenceVersion:"7.0.2",tsodinCommit:process.env.GITHUB_SHA||null,records,
}));
