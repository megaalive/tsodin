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
const boolValid=read("checker-boolean-valid");
assert.equal(boolValid.status,0,"boolean declaration fixture must typecheck");
assert.deepEqual(boolValid.summary,["SUMMARY","3","0","0"]);
const boolBad=read("checker-boolean-errors");
assert.equal(boolBad.status,1,"boolean mismatches must fail");
assert.deepEqual(boolBad.summary,["SUMMARY","2","2","1"]);
assert.deepEqual(boolBad.diags.map(x=>x[1]),["10","10"],"boolean mismatches use TS2322 candidate");
assert.deepEqual(boolBad.diags.map(x=>x.slice(2,4)),[["0","6"],["1","6"]],
  "boolean declaration-name source spans in zero-based UTF-16");
const logicValid=read("checker-logic-valid");
assert.equal(logicValid.status,0,"supported comparisons and logic must succeed");
assert.deepEqual(logicValid.summary,["SUMMARY","7","0","0"]);
const logicBad=read("checker-logic-errors");
assert.equal(logicBad.status,1,"assignment mismatches must fail");
assert.deepEqual(logicBad.summary,["SUMMARY","2","2","1"]);
assert.deepEqual(logicBad.diags.map(x=>x[1]),["10","10"]);
const literalValid=read("checker-literal-valid");
assert.equal(literalValid.status,0,"equal primitive literals have no diagnostic");
assert.deepEqual(literalValid.summary,["SUMMARY","3","0","0"]);
const disjoint=read("checker-literal-disjoint");
assert.equal(disjoint.status,1,"disjoint comparisons must never report success");
assert.deepEqual(disjoint.summary,["SUMMARY","3","3","1"]);
assert.deepEqual(disjoint.diags.map(x=>x[1]),["11","11","11"],
  "the new disjoint-literal issue is distinct from TS2322 candidates");
const constValid=read("checker-const-literal-valid");
assert.equal(constValid.status,0,"equal inferred const aliases must pass");
assert.deepEqual(constValid.summary,["SUMMARY","12","0","0"]);
const constBad=read("checker-const-literal-disjoint");
assert.equal(constBad.status,1,"disjoint const aliases must fail");
assert.deepEqual(constBad.summary,["SUMMARY","10","3","1"]);
assert.deepEqual(constBad.diags.map(row=>row[1]),["11","11","11"],
  "all disjoint const alias comparisons use the TS2367-candidate issue");
const domainValid=read("checker-domain-valid");
assert.equal(domainValid.status,0,"proven same-name comparisons remain accepted");
assert.deepEqual(domainValid.summary,["SUMMARY","5","0","0"]);
const domainErrors=read("checker-domain-errors");
assert.equal(domainErrors.status,1,"disjoint primitive domains must not return success");
assert.deepEqual(domainErrors.summary,["SUMMARY","9","5","1"]);
assert.deepEqual(domainErrors.diags.map(row=>row[1]),["12","12","12","12","10"],
  "primitive domain and assignment issues have stable distinct ordinals");
const wideValid=read("checker-wide-valid");
assert.equal(wideValid.status,0,"proven broad computed domains must type-check");
assert.deepEqual(wideValid.summary,["SUMMARY","13","0","0"]);
const wideErrors=read("checker-wide-errors");
assert.equal(wideErrors.status,1,"bad widened comparisons must still fail");
assert.deepEqual(wideErrors.summary,["SUMMARY","9","4","1"]);
assert.deepEqual(wideErrors.diags.map(row=>row[1]),["12","12","11","10"],
  "computed widened operands must not suppress unrelated errors");
const flowValid=read("checker-flow-assign-valid");
assert.equal(flowValid.status,0,"valid straight-line let assignment sequence");
assert.deepEqual(flowValid.summary,["SUMMARY","7","0","0"]);
const flowBad=read("checker-flow-assign-errors");
assert.equal(flowBad.status,1,"incorrect flow facts and assignments fail");
assert.deepEqual(flowBad.summary,["SUMMARY","6","2","1"]);
assert.deepEqual(flowBad.diags.map(row=>row[1]),["11","10"],
  "TS2367-candidate mismatches and TS2322 assignment type errors are distinct");
const branchValid=read("checker-flow-branch-valid");
assert.equal(branchValid.status,0,"bounded if/else and joined facts must succeed");
assert.deepEqual(branchValid.summary,["SUMMARY","4","0","0"]);
const branchBad=read("checker-flow-branch-errors");
assert.equal(branchBad.status,1,"branch-local disjointness and type mismatch fail");
assert.deepEqual(branchBad.summary,["SUMMARY","3","2","1"]);
assert.deepEqual(branchBad.diags.map(row=>row[1]),["11","10"]);
const negativeValid=read("checker-flow-negative-valid");
assert.equal(negativeValid.status,0,"negative guard narrows else only");
assert.deepEqual(negativeValid.summary,["SUMMARY","6","0","0"]);
const negativeBad=read("checker-flow-negative-errors");
assert.equal(negativeBad.status,1,"negative guard errors must not return success");
assert.deepEqual(negativeBad.summary,["SUMMARY","4","3","1"]);
assert.deepEqual(negativeBad.diags.map(row=>row[1]),["11","10","11"]);
const guardsValid=read("checker-flow-guards-valid");
assert.equal(guardsValid.status,0,"boolean and ! guards must succeed");
assert.deepEqual(guardsValid.summary,["SUMMARY","5","0","0"]);
const guardsBad=read("checker-flow-guards-errors");
assert.equal(guardsBad.status,1,"disjoint facts and mismatch cannot succeed");
assert.deepEqual(guardsBad.summary,["SUMMARY","4","6","1"]);
assert.deepEqual(guardsBad.diags.map(row=>row[1]),["11","11","11","11","11","10"]);
const nestedValid=read("checker-flow-nested-valid");
assert.equal(nestedValid.status,0,"bounded nested flow must remain valid");
assert.deepEqual(nestedValid.summary,["SUMMARY","4","0","0"]);
const nestedErrors=read("checker-flow-nested-errors");
assert.equal(nestedErrors.status,1,"nested disjointness and mismatch cannot succeed");
assert.deepEqual(nestedErrors.summary,["SUMMARY","4","5","1"]);
assert.deepEqual(nestedErrors.diags.map(row=>row[1]),["11","11","11","11","10"],
  "child-local TypeScript candidate errors preserve source order");
console.log("PASS: bounded nested branch fork/join and TS7 witnesses");
