#!/usr/bin/env node
// Integration test of the Odin checker slice; TS7 native CLI is a separate
// reference lane. Internal checker issues must not be labeled TS7 diagnostics.
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {resolve} from "node:path";
import {fileURLToPath} from "node:url";
const root=resolve(fileURLToPath(new URL("../..",import.meta.url)));
const tool=process.env.TSODIN_CHECKTRACE;
if(!tool)throw new Error("Set TSODIN_CHECKTRACE to the compiled Odin executable");
const file=id=>resolve(root,"tests/oracle/"+id+"/index.ts");
function read(id){
  const run=spawnSync(tool,[file(id)],{encoding:"utf8",timeout:12000,maxBuffer:1024*1024});
  if(run.error)throw run.error;
  if(run.signal)throw new Error(id+": signal "+run.signal);
  const rows=run.stdout.trim().split(/\r?\n/).map(line=>line.split("\t"));
  const summary=rows.at(-1);
  if(summary?.[0]!=="SUMMARY")throw new Error(id+": missing summary: "+run.stdout+run.stderr);
  return {status:run.status,summary,diags:rows.filter(row=>row[0]==="DIAG"),stderr:run.stderr};
}
const valid=read("checker-primitives-valid");
assert.equal(valid.status,0,"valid supported grammar must finish");
assert.deepEqual(valid.summary,["SUMMARY","3","0","0"]);
assert.equal(valid.diags.length,0);
const mismatch=read("checker-primitives-errors");
assert.equal(mismatch.status,1,"type mismatches must never return success");
assert.deepEqual(mismatch.summary,["SUMMARY","3","2","1"]);
assert.equal(mismatch.diags.length,2);
assert.deepEqual(mismatch.diags.map(x=>x[1]),["10","10"],"internal mismatch kind");
for(const row of mismatch.diags) {
  assert.equal(row.length,6);
  const [,issue,line,start,endLine,end]=row.map((x,i)=>i===0?x:Number(x));
  assert.equal(issue,10);
  assert.equal(line,endLine);
  assert.ok(end>start);
}
console.log("PASS: Odin source → parse → bind → primitive type diagnostics; TS7 semantic parity not yet established");
