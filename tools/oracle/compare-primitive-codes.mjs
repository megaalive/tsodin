#!/usr/bin/env node
// Narrow code-only differential witness. NOT official conformance or TS7
// diagnostic position/text parity. Both tools execute the same actual files.
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
  const upstreamCodes=[...(ts.stdout+"\n"+ts.stderr).matchAll(/\berror TS(\d+):/g)].map(m=>Number(m[1]));
  const odinIssues=[...odin.stdout.matchAll(/^DIAG\t(\d+)\t/gm)].map(m=>Number(m[1]));
  const mapped=odinIssues.map(issue=>{
    if(issue!==10)throw new Error(fixture.id+": unmapped internal issue "+issue);
    return 2322; // narrowly proven only for primitive assignment mismatches.
  });
  assert.equal(odin.status,fixture.expectedCount?1:0,"Odin semantic completion status");
  assert.equal(ts.status===0,!fixture.expectedCount,"TS7 diagnostic completion status");
  assert.deepEqual(upstreamCodes,new Array(fixture.expectedCount).fill(2322),
    fixture.id+": no unexpected TS7 error code");
  assert.deepEqual(mapped,upstreamCodes,fixture.id+": mapped diagnostic code multiset/order mismatch");
  records.push({fixture:fixture.id,referenceCodes:upstreamCodes,odinMappedCodes:mapped,spanParityChecked:false,messageParityChecked:false});
  console.log("PASS "+fixture.id+": "+upstreamCodes.length+" matched TS2322 diagnostic codes; spans/messages NOT compared");
}
const report={schemaVersion:1,kind:"subset-code-witness-not-conformance",referenceVersion:"7.0.2",
  tsodinCommit:process.env.GITHUB_SHA||null,records};
console.log("CODE_WITNESS "+JSON.stringify(report));
