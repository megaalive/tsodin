import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadOracleProfile } from './profile.mjs';

const root=resolve(fileURLToPath(new URL('../..',import.meta.url)));
const pinned=loadOracleProfile();
assert.equal(pinned.id,'ts7');
assert.equal(pinned.version,'7.0.2');
assert.equal(pinned.npmSpec,'typescript@7.0.2');
assert.equal(pinned.executable,'tsc');
assert.equal(pinned.manifest,'tests/oracle/manifest.json');
assert.ok(pinned.projectArguments.includes('--singleThreaded'));
assert.throws(()=>loadOracleProfile('ts8'),/Unregistered/);
assert.throws(()=>loadOracleProfile('../ts7'),/Unsafe/);
assert.throws(()=>loadOracleProfile(''),/Unsafe/);
const manifest=JSON.parse(readFileSync(resolve(root,pinned.manifest),'utf8'));
assert.equal(manifest.oracleVersion,pinned.version);
assert.equal(manifest.schemaVersion,1);
assert.ok(manifest.projects.some(item=>item.id==='scanner-ascii' && !item.expectDiagnostics));
for(const [id,expected] of [
  ["checker-unary-wide-valid",false],["checker-unary-wide-errors",true],
  ["checker-unary-singleton-valid",false],["checker-unary-singleton-errors",true],
  ["checker-unary-singleton-flow-errors",true],
]){
  const item=manifest.projects.find(p=>p.id===id);
  assert.ok(item && item.expectDiagnostics===expected &&
    item.path==="tests/oracle/"+id && item.files.includes("index.ts"),
    "unary Boolean TS7 projects must be independently captured");
}
for(const [id,expected] of [
  ["checker-logical-facts-valid",false],
  ["checker-logical-facts-errors",true],
  ["checker-logical-facts-flow-valid",false],
]){
  const item=manifest.projects.find(p=>p.id===id);
  assert.ok(item && item.expectDiagnostics===expected &&
    item.path==="tests/oracle/"+id &&
    item.files.includes("index.ts") && item.files.includes("tsconfig.json"),
    "Boolean logical oracle project must remain independently captured");
}
for(const [id,expected] of [
  ["checker-boolean-identity-valid",false],
  ["checker-boolean-identity-errors",true],
  ["checker-boolean-identity-nested-valid",false],
]){
  const item=manifest.projects.find(p=>p.id===id);
  assert.ok(item && item.expectDiagnostics===expected &&
    item.path==="tests/oracle/"+id &&
    item.files.includes("index.ts") && item.files.includes("tsconfig.json"),
    "Boolean identity guard witness must remain independently pinned");
}
for(const spelling of ["01","00","08"]){
  const id="scanner-leading-zero-"+spelling;
  const witness=manifest.projects.find(item=>item.id===id);
  assert.ok(witness&&witness.expectDiagnostics&&witness.path==="tests/oracle/"+id,
    "each leading-zero form needs its own pinned TS7 failure witness");
  assert.deepEqual(witness.files,["index.ts","tsconfig.json"]);
  const source=readFileSync(resolve(root,witness.path,"index.ts"),"utf8");
  assert.match(source,new RegExp("const value = "+spelling+";"),
    "the exact lexical spelling must remain unmodified");
}
console.log('PASS: explicit pinned CLI oracle profiles, unknown-version rejection, lexical acceptance fixture');
