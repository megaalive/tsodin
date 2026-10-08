#!/usr/bin/env node
// Integration smoke for a developer-only restricted grammar; not TS7 parity.
import assert from "node:assert/strict";
import {readFileSync, mkdtempSync, writeFileSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {spawnSync} from "node:child_process";

const root=resolve(fileURLToPath(new URL("../..",import.meta.url)));
const binary=process.env.TSODIN_SYNTAXTRACE;
if(!binary)throw new Error("Set TSODIN_SYNTAXTRACE to the pinned Odin-built executable");
function run(file) {
  const child=spawnSync(binary,[file],{encoding:"utf8",timeout:12000,maxBuffer:1048576});
  if(child.error)throw child.error;
  assert.equal(child.stderr,"",file+": unexpected stderr");
  const lines=child.stdout.trim().split(/\r?\n/).map(line=>line.split("\t"));
  const summary=lines.at(-1);
  assert.equal(summary?.[0],"SUMMARY",file+": final summary missing");
  return {status:child.status,diagnostics:lines.filter(x=>x[0]==="DIAG"),summary};
}
const clean=run(join(root,"tests/oracle/expression-subset/index.ts"));
assert.equal(clean.status,0,"supported TypeScript file should parse completely");
assert.deepEqual(clean.summary,["SUMMARY","3","0","0"]);
assert.equal(clean.diagnostics.length,0);

const brokenPath=join(root,"tests/oracle/expression-syntax-errors/index.ts");
const broken=run(brokenPath);
assert.equal(broken.status,1,"recoverable syntax issues must be nonzero");
assert.deepEqual(broken.summary,["SUMMARY","2","2","1"]);
assert.deepEqual(broken.diagnostics.map(x=>Number(x[1])),[7,8],
  "two internal error kinds: expected expression then closing paren");
const sourceLines=readFileSync(brokenPath,"utf8").split(/\r?\n/);
const expectedLines=[1,3];
for(let i=0;i<2;i++){
  const diag=broken.diagnostics[i].map((part,j)=>j===0?part:Number(part));
  const line=expectedLines[i];
  const col=sourceLines[line].indexOf(";");
  assert.deepEqual(diag,["DIAG",7+i,line,col,line,col+1],
    "internal diagnostic byte span projects to exact UTF-16 line/column");
}

const dir=mkdtempSync(join(tmpdir(),"tsodin-syntaxtrace-"));
try{
  const unicodePath=join(dir,"unicode.ts");
  writeFileSync(unicodePath,"// 😀 leading comment\r\nconst fail = 1 + ;\r\nlet valid = 42;\r\n","utf8");
  const unicode=run(unicodePath);
  assert.equal(unicode.status,1);
  assert.deepEqual(unicode.summary,["SUMMARY","1","1","1"]);
  assert.deepEqual(unicode.diagnostics[0],["DIAG","7","1","17","1","18"],
    "UTF-8 emoji in earlier line must not disturb UTF-16 error positions");

  const invalidPath=join(dir,"unsupported.ts");
  writeFileSync(invalidPath,"const good = 1;\nconst bad = @;\nconst after = 2;\n","utf8");
  const unsupported=run(invalidPath);
  assert.equal(unsupported.status,2,"unsupported lexical forms are fatal");
  assert.equal(unsupported.summary[3],"2","fatal result has no success exit");
}finally{
  rmSync(dir,{recursive:true,force:true});
}
console.log("PASS: Odin developer syntaxtrace, recovery, UTF-16 diagnostic spans, fatal unsupported syntax");
