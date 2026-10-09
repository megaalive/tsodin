#!/usr/bin/env node
// Scope: pinned native TS7 CLI evidence, not a Javascript type checker.
// Every inference witness runs in its own strict/noEmit TypeScript project.
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";

const compiler=process.env.TSODIN_TSC;
if(!compiler)throw new Error("TSODIN_TSC is required");
const v=spawnSync(compiler,["--version"],{encoding:"utf8"});
assert.equal(v.status,0);
assert.match(v.stdout,/7\.0\.2\s*$/);
const root=mkdtempSync(join(tmpdir(),"tsodin-logical-ts7-"));
const prefix="const wide = 2 < 3; const other = 4 > 1; ";
const cases={
  and_false_false:"const a = false && false; const exact: false = a;",
  and_false_true:"const a = false && true; const exact: false = a;",
  and_true_false:"const a = true && false; const exact: false = a;",
  and_true_true:"const a = true && true; const exact: true = a;",
  or_false_false:"const a = false || false; const exact: false = a;",
  or_false_true:"const a = false || true; const exact: true = a;",
  or_true_false:"const a = true || false; const exact: true = a;",
  or_true_true:"const a = true || true; const exact: true = a;",
  chain_singleton:"const a = !!true && (!false || false); const exact: true = a;",
  and_wide_wide:prefix+"const a = wide && other; const mustBeBoolean: boolean = a; const comparison = a === true;",
  or_wide_wide:prefix+"const a = wide || other; const mustBeBoolean: boolean = a; const comparison = a === false;",
  and_wide_true:prefix+"const a = wide && true; const mustBeBoolean: boolean = a; const comparison = a === true;",
  and_true_wide:prefix+"const a = true && wide; const mustBeBoolean: boolean = a; const comparison = a === true;",
  or_wide_false:prefix+"const a = wide || false; const mustBeBoolean: boolean = a; const comparison = a === true;",
  or_false_wide:prefix+"const a = false || wide; const mustBeBoolean: boolean = a; const comparison = a === false;",
  and_false_wide:prefix+"const a = false && wide; const exact: false = a;",
  or_true_wide:prefix+"const a = true || wide; const exact: true = a;",
};
try {
 for(const [id,source] of Object.entries(cases)){
  const dir=join(root,id);mkdirSync(dir);
  writeFileSync(join(dir,"index.ts"),source+"\n");
  writeFileSync(join(dir,"tsconfig.json"),JSON.stringify({
   compilerOptions:{noEmit:true,strict:true,types:[],lib:["es2022"],skipLibCheck:true,incremental:false},
   files:["index.ts"],
  })+"\n");
  const run=spawnSync(compiler,["-p","tsconfig.json","--pretty","false","--singleThreaded"],{
   cwd:dir,encoding:"utf8",timeout:45000,maxBuffer:1048576,
  });
  if(run.error||run.signal||run.status===null)throw Error(id+": compiler did not finish");
  const errors=[...(run.stdout+"\n"+run.stderr).matchAll(/error TS(\d+):/g)].map(m=>Number(m[1]));
  assert.deepEqual(errors,[],id+": native pinned TS7 Boolean logical acceptance drift");
  assert.equal(run.status,0,id+": native TS7 must typecheck the exact singleton/domain witness");
  console.log("PASS native TS7 Boolean logical inference "+id);
 }
}finally{rmSync(root,{recursive:true,force:true});}
