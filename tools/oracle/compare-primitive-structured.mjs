#!/usr/bin/env node
// Auxiliary TS6 structured diagnostic witness, never native TS7 parity.
// The authoritative TS7 CLI still verifies code and UTF-16 diagnostic starts
// in compare-primitive-codes.mjs. TS6 API independently provides END spans.
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {createRequire} from "node:module";
import {readFileSync} from "node:fs";
import {dirname} from "node:path";
import {resolve} from "node:path";
import {fileURLToPath} from "node:url";

const root=resolve(fileURLToPath(new URL("../..",import.meta.url)));
const api=process.env.TSODIN_TS6_API;
const checker=process.env.TSODIN_CHECKTRACE;
if (!api || !checker) throw new Error("Set TSODIN_TS6_API and TSODIN_CHECKTRACE");
const ts=createRequire(import.meta.url)(api);
const packageVersion=JSON.parse(readFileSync(resolve(dirname(api),"../package.json"),"utf8")).version;
if (packageVersion !== "6.0.2") {
  throw new Error("Wrong TS6 package version: "+packageVersion);
}
if (!String(ts.version).startsWith("6.") || typeof ts.getPreEmitDiagnostics !== "function") {
  throw new Error("Unsupported TS6 structured API version: "+String(ts.version));
}

const fixtures=[
  ["checker-primitives-valid",0],
  ["checker-primitives-errors",2],
  ["checker-primitives-utf16",1],
  ["checker-boolean-valid",0],
  ["checker-boolean-errors",2],
  ["checker-logic-valid",0],
  ["checker-logic-errors",2],
  ["checker-literal-valid",0],
  ["checker-literal-disjoint",3],
  ["checker-const-literal-valid",0],
  ["checker-const-literal-disjoint",3],
  ["checker-domain-valid",0],
  ["checker-domain-errors",5],
  ["checker-wide-valid",0],
  ["checker-wide-errors",4],
  ["checker-unary-wide-valid",0],
  ["checker-unary-wide-errors",2],
  ["checker-unary-singleton-valid",0],
  ["checker-unary-singleton-errors",4],
  ["checker-unary-singleton-flow-errors",2],
  ["checker-logical-facts-valid",0],
  ["checker-logical-facts-errors",6],
  ["checker-logical-facts-flow-valid",0],
  ["checker-boolean-identity-valid",0],
  ["checker-boolean-identity-errors",13],
  ["checker-boolean-identity-nested-valid",0],
  ["checker-negated-identity-valid",0],
  ["checker-negated-identity-errors",17],
  ["checker-negated-identity-nested-valid",0],
  ["checker-flow-assign-valid",0],
  ["checker-flow-assign-errors",2],
  ["checker-flow-branch-valid",0],
  ["checker-flow-branch-errors",2],
  ["checker-flow-negative-valid",0],
  ["checker-flow-negative-errors",3],
  ["checker-flow-guards-valid",0],
  ["checker-flow-guards-errors",6],
  ["checker-flow-nested-valid",0],
  ["checker-flow-nested-errors",5],
  ["checker-flow-compound-valid",0],
  ["checker-flow-compound-errors",5],
  ["checker-flow-rhs-valid",0],
  ["checker-flow-rhs-errors",5],
  ["checker-flow-contradiction-valid",0],
  ["checker-flow-contradiction-errors",2],
  ["checker-flow-dead-assign-valid",0],
  ["checker-flow-dead-assign-errors",3],
  ["checker-flow-three-guards-valid",0],
  ["checker-flow-three-guards-errors",7],
  ["checker-flow-three-nested-valid",0],
  ["checker-flow-three-nested-errors",5],
  ["checker-flow-mixed-rhs-valid",0],
  ["checker-flow-mixed-rhs-errors",4],
  ["checker-flow-mixed-left-valid",0],
  ["checker-flow-mixed-left-errors",5],
  ["checker-flow-mixed-nested-valid",0],
  ["checker-flow-mixed-nested-errors",9],
  ["checker-remainder-valid",0],
  ["checker-remainder-errors",3],
  ["checker-annotation-widening-valid",0],
  ["checker-annotation-widening-errors",6],
  // Auxiliary structured spans; TS7 CLI remains the semantic authority.
  ["checker-typeof-flow-valid",0],
  ["checker-typeof-flow-errors",2],
];

function structuredReference(cwd) {
  const configPath=resolve(cwd,"tsconfig.json");
  const config=ts.readConfigFile(configPath,ts.sys.readFile);
  if(config.error) throw new Error(ts.flattenDiagnosticMessageText(config.error.messageText,"\n"));
  const parsed=ts.parseJsonConfigFileContent(config.config,ts.sys,cwd,undefined,configPath);
  assert.equal(parsed.errors.length,0,"TS6 tsconfig errors are not expected");
  assert.equal(parsed.fileNames.length,1,"fixture must have exactly one source");
  const program=ts.createProgram({rootNames:parsed.fileNames,options:parsed.options});
  return ts.getPreEmitDiagnostics(program).map(d=>{
    assert.ok(d.file && d.file.fileName.endsWith("/index.ts"),"No fileless or foreign TS6 diagnostics may be hidden");
    assert.equal(d.category,ts.DiagnosticCategory.Error,"only error diagnostics are expected");
    assert.ok(d.code===2322 || d.code===2367,"unexpected TS6 diagnostic code");
    assert.ok(Number.isSafeInteger(d.start) && Number.isSafeInteger(d.length) && d.length>0,
      "TS6 must provide an actual nonempty source span");
    const begin=d.file.getLineAndCharacterOfPosition(d.start);
    const finish=d.file.getLineAndCharacterOfPosition(d.start+d.length);
    return {
      code:d.code,category:"error",
      line:begin.line+1,column:begin.character+1,
      endLine:finish.line+1,endColumn:finish.character+1,
    };
  });
}
function odinDiagnostics(cwd) {
  const run=spawnSync(checker,[resolve(cwd,"index.ts")],{
    encoding:"utf8",timeout:12000,maxBuffer:1024*1024,
  });
  if(run.error || run.signal || run.status===null) throw new Error("Odin checker did not complete");
  const result=[...run.stdout.matchAll(/^DIAG\t(\d+)\t(\d+)\t(\d+)\t(\d+)\t(\d+)$/gm)].map(m=>{
    const kind=Number(m[1]);
    assert.ok(kind===10 || kind===11 || kind===12,"unmapped Odin issue in structured witness");
    return {
      code:kind===10?2322:2367,category:"error",
      line:Number(m[2])+1,column:Number(m[3])+1,
      endLine:Number(m[4])+1,endColumn:Number(m[5])+1,
    };
  });
  return {status:run.status,result};
}
for(const [name,n] of fixtures){
  const cwd=resolve(root,"tests/oracle",name);
  const reference=structuredReference(cwd);
  const actual=odinDiagnostics(cwd);
  assert.equal(reference.length,n,name+": unexpected TS6 diagnostic count");
  assert.equal(actual.result.length,n,name+": unexpected Odin diagnostic count");
  assert.equal(actual.status,n>0?1:0,name+": fail-closed Odin status");
  assert.deepEqual(actual.result,reference,
    name+": TS6 structured code/category/start/end != Odin primitive witness");
  console.log("PASS "+name+": "+n+" complete TS6 structured diagnostic spans and Odin issue mappings");
}
console.log("STRUCTURED_WITNESS "+JSON.stringify({
  schemaVersion:1,
  kind:"TS6-supplement-not-TS7-conformance",
  referenceVersion:ts.version,
  ts7FullStructuredParity:false,
  dimensions:["code","category-error","start-utf16","end-utf16"],
  excluded:["message","native-TS7-end-spans","official-conformance"],
  fixtures:fixtures.length,
}));
