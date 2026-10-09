#!/usr/bin/env node
// Gallery inputs are ONLY checked-in examples. No hand-written compiler facts.
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {readdirSync,readFileSync,mkdirSync,writeFileSync} from "node:fs";
import {resolve} from "node:path";
const bin=process.env.TSODIN_BIN;
if(!bin)throw new Error("TSODIN_BIN is required");
const mode=process.argv.includes("--check")?"check":"write";
const print=process.argv.includes("--print"); // onboarding only, public examples
const folder=resolve("docs/traces");
if(mode==="write")mkdirSync(folder,{recursive:true});
const names=readdirSync("examples").filter(x=>/^[a-z0-9-]+\.ts$/.test(x)).sort();
assert.ok(names.length>0,"No public gallery examples");
const entries=[];
function emit(name,body){
  const file=resolve(folder,name);
  if(mode==="check"){
    assert.equal(readFileSync(file,"utf8"),body,"stale generated trace "+name);
  }else{
    writeFileSync(file,body);
  }
  if(print)console.log("TSODIN_TRACE|"+name+"|"+body.trimEnd());
}
for(const filename of names){
  const slug=filename.slice(0,-3),path="examples/"+filename;
  const run=spawnSync(bin,["dump","--stage=all","--trace-relations",path],{encoding:"utf8",timeout:12000,maxBuffer:8*1024*1024});
  assert.equal(run.status,0,path+": "+run.stderr);
  assert.equal(run.stderr,"",path+": unexpected stderr");
  const dump=JSON.parse(run.stdout);
  assert.equal(dump.schema,"tsodin.dump/3");
  assert.equal(dump.stages.types.trace_mode,"all");
  assert.equal(dump.stages.types.comparisons_status,"partial");
  assert.equal(dump.source.name,path);
  assert.equal(dump.source.text,readFileSync(path,"utf8"));
  emit(slug+".json",run.stdout);
  const title=slug.split("-").map(x=>x.charAt(0).toUpperCase()+x.slice(1)).join(" ");
  entries.push({id:slug,title,description:"Verified Odin stage dump for "+filename,href:slug+".json"});
}
const index={schema:"tsodin.gallery/1",examples:entries};
emit("index.json",JSON.stringify(index,null,2)+"\n");
console.log("PASS: "+names.length+" curated traces "+(mode==="check"?"match checked-in bytes":"generated")+"; no synthetic compiler facts");
