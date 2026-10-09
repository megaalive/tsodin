#!/usr/bin/env node
// The actual pinned TS7 CLI decides whether unary ! preserves literal types.
// Each probe is a separate strict project so a diagnostic cannot hide another.
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
const compiler=process.env.TSODIN_TSC;
if(!compiler)throw new Error("TSODIN_TSC must identify the pinned TypeScript 7 executable");
const v=spawnSync(compiler,["--version"],{encoding:"utf8"});
assert.equal(v.status,0);
assert.match(v.stdout,/7\\.0\\.2\\s*$/);
const root=mkdtempSync(join(tmpdir(),"tsodin-unary-ts7-"));
const cases={
  not_true_assign_false:"const negated = !true; const literal: false = negated;\\n",
  not_false_assign_true:"const negated = !false; const literal: true = negated;\\n",
  twice_true_assign_true:"const twice = !!true; const literal: true = twice;\\n",
  not_true_compare_true:"const negated = !true; const compared = negated === true;\\n",
  not_true_compare_false:"const negated = !true; const compared = negated === false;\\n",
  narrowed_branch_assign_false:"let flag: boolean = false; flag = 2 < 3; if(flag){ const inverted = !flag; const literal: false = inverted; }\\n",
};
try{
 for(const [id,raw] of Object.entries(cases)){
  const dir=join(root,id);mkdirSync(dir);
  writeFileSync(join(dir,"index.ts"),raw.replaceAll("\\n","\n"));
  writeFileSync(join(dir,"tsconfig.json"),JSON.stringify({
   compilerOptions:{noEmit:true,strict:true,types:[],lib:["es2022"],skipLibCheck:true,incremental:false},
   files:["index.ts"],
  })+"\n");
  const run=spawnSync(compiler,["-p","tsconfig.json","--pretty","false","--singleThreaded"],{
   cwd:dir,encoding:"utf8",timeout:45000,maxBuffer:1048576
  });
  if(run.error||run.signal||run.status===null)throw Error(id+": compiler did not finish");
  const diagnostics=[...(run.stdout+"\n"+run.stderr).matchAll(/error TS(\d+):/g)].map(x=>Number(x[1]));
  console.log("TSODIN_UNARY_PROBE|"+JSON.stringify({id,exit:run.status,diagnostics,output:run.stdout.trim()}));
 }
}finally{rmSync(root,{recursive:true,force:true});}
