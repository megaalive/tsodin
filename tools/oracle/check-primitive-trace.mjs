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
const unaryValid=read("checker-unary-wide-valid");
assert.equal(unaryValid.status,0,"proven-wide logical negation must typecheck");
assert.deepEqual(unaryValid.summary,["SUMMARY","7","0","0"]);
const unaryBad=read("checker-unary-wide-errors");
assert.equal(unaryBad.status,1,"unary Boolean results must preserve disjoint and mismatch errors");
assert.deepEqual(unaryBad.summary,["SUMMARY","5","2","1"]);
assert.deepEqual(unaryBad.diags.map(row=>row[1]),["10","12"],
  "unary-wide errors retain ordered TS2322 and TS2367 candidates");
const singletonValid=read("checker-unary-singleton-valid");
assert.equal(singletonValid.status,0,"proved Boolean unary singleton aliases must typecheck");
assert.equal(singletonValid.diags.length,0);
const singletonErrors=read("checker-unary-singleton-errors");
assert.equal(singletonErrors.status,1,"disjoint inverse singleton comparisons must be diagnosed");
assert.deepEqual(singletonErrors.diags.map(row=>row[1]),["11","11","11","10"],
  "unary singleton disjointness and assignability follow source order");
const singletonFlow=read("checker-unary-singleton-flow-errors");
assert.equal(singletonFlow.status,1,"branch-local inverse singleton comparisons must be diagnosed");
assert.deepEqual(singletonFlow.diags.map(row=>row[1]),["11","11"],
  "mutation/join do not retain stale branch-local singleton facts");
const logicalValid=read("checker-logical-facts-valid");
assert.equal(logicalValid.status,0,"proven Boolean logical operands must typecheck");
assert.equal(logicalValid.diags.length,0);
const logicalBad=read("checker-logical-facts-errors");
assert.equal(logicalBad.status,1,"logical literal contradictions must not be hidden");
assert.deepEqual(logicalBad.diags.map(row=>row[1]),["11","11","11","11","11","10"],
  "five logical TS2367 candidates precede a real assignment TS2322 candidate");
const logicalFlow=read("checker-logical-facts-flow-valid");
assert.equal(logicalFlow.status,0,"branch mutation and logical joins must typecheck");
assert.equal(logicalFlow.diags.length,0);
const identityValid=read("checker-boolean-identity-valid");
assert.equal(identityValid.status,0,"four Boolean identities and outer negations narrow both paths");
assert.equal(identityValid.diags.length,0);
const identityErrors=read("checker-boolean-identity-errors");
assert.equal(identityErrors.status,1,"proven disjoint guard facts must be diagnosed");
assert.deepEqual(identityErrors.diags.map(row=>row[1]),
  [...Array(12).fill("11"),"10"],
  "twelve source-ordered TS2367 candidates and one TS2322 candidate");
const identityNested=read("checker-boolean-identity-nested-valid");
assert.equal(identityNested.status,0,"nested Boolean identity guards must preserve mutation joins");
assert.equal(identityNested.diags.length,0);
const negatedValid=read("checker-negated-identity-valid");
assert.equal(negatedValid.status,0,"pure negated Boolean identity guards narrow both arms");
assert.equal(negatedValid.diags.length,0);
const negatedErrors=read("checker-negated-identity-errors");
assert.equal(negatedErrors.status,1,"disjoint inverse Boolean guards must be diagnosed");
assert.deepEqual(negatedErrors.diags.map(row=>row[1]),[...Array(16).fill("11"),"10"],
  "sixteen ordered TS2367-like cases plus one TS2322-like mismatch");
const negatedNested=read("checker-negated-identity-nested-valid");
assert.equal(negatedNested.status,0,"nested negated Boolean identities must not leak after joins");
assert.equal(negatedNested.diags.length,0);
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
const compoundValid=read("checker-flow-compound-valid");
assert.equal(compoundValid.status,0,"bounded short-circuit paths remain valid");
const compoundErrors=read("checker-flow-compound-errors");
assert.equal(compoundErrors.status,1,"compound guard disjoint facts are rejected");
assert.deepEqual(compoundErrors.diags.map(row=>row[1]),["11","11","10","11","11"],
  "only implied branch facts produce disjointness diagnostics");
const rhsValid=read("checker-flow-rhs-valid");
assert.equal(rhsValid.status,0,"RHS contextual facts and idempotent guards");
const rhsErrors=read("checker-flow-rhs-errors");
assert.equal(rhsErrors.status,1,"disjoint facts on idempotent guard paths");
assert.deepEqual(rhsErrors.diags.map(row=>row[1]),["11","11","11","11","10"],
  "stable code candidates and a later mismatch");
const contradictionValid=read("checker-flow-contradiction-valid");
assert.equal(contradictionValid.status,0,"empty impossible arms join only reachable paths");
const contradictionBad=read("checker-flow-contradiction-errors");
assert.equal(contradictionBad.status,1,"live-arm mismatches remain visible");
assert.deepEqual(contradictionBad.diags.map(x=>x[1]),["10","10"],
  "both reachable type errors retain stable issue IDs");
const deadValid=read("checker-flow-dead-assign-valid");
assert.equal(deadValid.status,0,"dead-arm direct assignments remain checked");
const deadErrors=read("checker-flow-dead-assign-errors");
assert.equal(deadErrors.status,1,"mismatches inside dead and live arms never vanish");
assert.deepEqual(deadErrors.diags.map(x=>x[1]),["10","10","10"],
  "dead-arm TS2322 candidates are emitted in source order");
const threeValid=read("checker-flow-three-guards-valid");
assert.equal(threeValid.status,0,"three-way same-operator Boolean branches typecheck");
const threeBad=read("checker-flow-three-guards-errors");
assert.equal(threeBad.status,1,"all decisive-arm comparisons retain diagnostics");
assert.deepEqual(threeBad.diags.map(x=>x[1]),["11","11","11","10","11","11","11"],
  "three-way TS2367 and TS2322 candidate order remains source-backed");
const threeNestedValid=read("checker-flow-three-nested-valid");
assert.equal(threeNestedValid.status,0,"three-way parent facts survive nested mutation");
const threeNestedBad=read("checker-flow-three-nested-errors");
assert.equal(threeNestedBad.status,1,"nested diagnostics cannot be lost at joins");
assert.deepEqual(threeNestedBad.diags.map(x=>x[1]),["11","11","11","10","11"],
  "nested TS2367 and TS2322 candidates follow lexical order");
const mixedValid=read("checker-flow-mixed-rhs-valid");
assert.equal(mixedValid.status,0,"mixed RHS conditional guards prove outer-left only");
const mixedBad=read("checker-flow-mixed-rhs-errors");
assert.equal(mixedBad.status,1,"mixed RHS decisive-arm diagnostics remain");
assert.deepEqual(mixedBad.diags.map(x=>x[1]),["11","10","11","11"],
  "mixed RHS ordered disjoint and mismatch witness codes");
const mixedLeftValid=read("checker-flow-mixed-left-valid");
assert.equal(mixedLeftValid.status,0,"left-nested mixed formulas prove c only");
const mixedLeftBad=read("checker-flow-mixed-left-errors");
assert.equal(mixedLeftBad.status,1,"left-nested decisive-arm errors remain visible");
assert.deepEqual(mixedLeftBad.diags.map(x=>x[1]),["11","11","10","11","11"],
  "mixed-left ordered TS2367 and TS2322 candidate codes");
const mixedNestedValid=read("checker-flow-mixed-nested-valid");
assert.equal(mixedNestedValid.status,0,"mixed nested parent facts survive split and mutation joins");
const mixedNestedBad=read("checker-flow-mixed-nested-errors");
assert.equal(mixedNestedBad.status,1,"mixed nested path-local errors remain visible");
assert.deepEqual(mixedNestedBad.diags.map(x=>x[1]),
  ["11","11","11","11","10","11","11","11","11"],
  "mixed nested disjointness and assignment mismatch preserve source order");
const remainderValid=read("checker-remainder-valid");
assert.equal(remainderValid.status,0,"multiplicative remainder source must typecheck");
assert.equal(remainderValid.diags.length,0);
const remainderErrors=read("checker-remainder-errors");
assert.equal(remainderErrors.status,1,"remainder assignment/domain errors must not pass");
assert.deepEqual(remainderErrors.diags.map(row=>row[1]),["10","10","12"],
  "source-ordered remainder TS2322 and TS2367 issue mappings");
console.log("PASS: G5F7C nested mixed Boolean mutation and join witnesses, numeric remainder");

const typeofValid=read("checker-typeof-flow-valid");
assert.equal(typeofValid.status,0,"typeof union narrowing must work end to end");
assert.equal(typeofValid.diags.length,0);
const typeofBad=read("checker-typeof-flow-errors");
assert.equal(typeofBad.status,1,"incompatible writes in both typeof arms cannot succeed");
assert.equal(typeofBad.diags.length,2);
assert.deepEqual(typeofBad.diags.map(x=>x[1]),["10","10"],
  "both narrowed assignment failures remain internal TS2322 candidates");

const varValid=read("checker-var-redeclaration-valid");
assert.equal(varValid.status,0,"same-type var redeclarations must be allowed");
assert.equal(varValid.diags.length,0);
const varBad=read("checker-var-redeclaration-errors");
assert.equal(varBad.status,1,"conflicting var redeclarations must fail");
assert.deepEqual(varBad.diags.map(row=>row[1]),["15"],
  "conflicting declarations need a distinct TS2403 candidate");
const varFlowBad=read("checker-var-redeclaration-flow-errors");
assert.equal(varFlowBad.status,1,"later var initializer must replace the flow state");
assert.deepEqual(varFlowBad.diags.map(row=>row[1]),["10"],
  "downstream mismatch after redeclaration remains TS2322 candidate");
