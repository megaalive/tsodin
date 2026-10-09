#!/usr/bin/env node
// Offline validation of a curated UPSTREAM TRIAGE inventory.
// Paths were inspected in one pinned discovery snapshot, not imported or
// counted as executed conformance tests. The authoritative semantic oracle
// version is deliberately sourced from the separate TS7 profile registry.
import assert from "node:assert/strict";
import {readFileSync,existsSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {resolve} from "node:path";
const root=resolve(fileURLToPath(new URL("../..",import.meta.url)));
const load=path=>JSON.parse(readFileSync(resolve(root,path),"utf8"));
const map=load("tests/oracle/upstream-triage.json");
const profiles=load("tests/oracle/profiles.json");
const oracle=profiles.profiles.find(x=>x.id==="ts7");
const sha=/^[a-f0-9]{40}$/;
const expectedPriority=new Set(["P0","P1","P2"]);
const expectedStatus=new Set(["partial","unsupported"]);
assert.equal(map.schemaVersion,1);
assert.equal(map.project,"tsodin");
assert.equal(map.authority,"microsoft/TypeScript");
assert.match(map.discoverySnapshot,sha);
assert.ok(oracle,"pinned TS7 oracle must exist");
assert.deepEqual(map.pinnedSemanticOracle,{
  profile:oracle.id,version:oracle.version,revision:oracle.upstreamCommit
});
assert.notEqual(map.discoverySnapshot,map.pinnedSemanticOracle.revision,
 "latest discovery source and pinned executable oracle must be separate");
assert.equal(map.discoverySuiteRoot,"tsc/testdata/tests/cases/conformance");
assert.equal(map.pinnedOracleSuiteRoot,"tests/cases/conformance");
assert.equal(map.classification,"source_and_harness_inventory_only");
assert.deepEqual(map.summary,{
  officialCasesExecutedByTsodin:0,officialConformancePassesClaimed:0
});
assert.ok(Array.isArray(map.cases)&&map.cases.length>=5&&map.cases.length<=30);
const ids=new Set(),paths=new Set();
for(const c of map.cases){
  assert.match(c.id,/^[a-z][a-z0-9-]+$/);
  assert.ok(!ids.has(c.id),"duplicate upstream case id");
  ids.add(c.id);
  assert.ok(!paths.has(c.upstreamPath),"duplicate upstream path");
  paths.add(c.upstreamPath);
  assert.ok(expectedPriority.has(c.priority));
  assert.ok(expectedStatus.has(c.status));
  assert.match(c.subsystem,/^[a-z-]+$/);
  assert.match(c.upstreamPath,
    /^tsc\/testdata\/tests\/cases\/conformance\/[A-Za-z0-9_.\/\-]+\.ts$/);
  assert.equal(c.pinnedOraclePath,
    c.upstreamPath.replace("tsc/testdata/tests/cases/conformance/",
      "tests/cases/conformance/"));
  assert.match(c.pinnedOraclePath,
    /^tests\/cases\/conformance\/[A-Za-z0-9_.\/\-]+\.ts$/);
  assert.ok(c.nextAction.length>=24);
  assert.equal(c.verification,"indexed_only_not_executed");
}
assert.ok(ids.has("union-reduction")&&ids.has("annotated-initializers"));
assert.ok(existsSync(resolve(root,"src/checker/primitive.odin")));
console.log("PASS: pinned upstream discovery catalog is not masquerading as tested TS7 parity");
