#!/usr/bin/env node
// M4-G5F8A: differential span and shape sanity checks on real Odin output.
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

const compiler=process.env.TSODIN_BIN;
if(!compiler)throw new Error("Set TSODIN_BIN to the built Odin executable");
const cases=[
  ["typed-mismatch", "diagnostics"],
  ["unicode-span", "diagnostics"],
  ["mixed-boolean", "complete"],
  ["unsupported-name", "unsupported"],
];
const prefixUtf16=(s,byte)=>{
  const buffer=Buffer.from(s,"utf8");
  assert.ok(Number.isInteger(byte)&&byte>=0&&byte<=buffer.length);
  const prefix=buffer.subarray(0,byte);
  const decoded=new TextDecoder("utf-8",{fatal:true}).decode(prefix);
  return decoded.length;
};
for(const [name,expected] of cases){
  const path=resolve("examples",name+".ts");
  const s=readFileSync(path,"utf8");
  const cmd=[ "dump","--stage=all",path ];
  const run=()=>spawnSync(compiler,cmd,{encoding:"utf8",maxBuffer:8*1024*1024,timeout:12000});
  const result=run();
  assert.equal(result.status,0,name+": dump must serialize even incomplete semantic checks: "+result.stderr);
  assert.equal(result.stderr,"",name+": unexpected stderr");
  assert.equal(result.stdout,run().stdout,name+": dump must be deterministic");
  const data=JSON.parse(result.stdout);
  assert.equal(data.schema,"tsodin.dump/1");
  assert.equal(data.profile,"ts7");
  assert.equal(data.source.name,path);
  assert.equal(data.source.text,s);
  assert.equal(data.source.bytes,Buffer.byteLength(s));
  assert.equal(data.source.utf16,s.length);
  assert.equal(data.stages.types.outcome,expected,name+": checker outcome must be truthful");
  assert.equal(data.stages.tokens.outcome,"complete");
  assert.equal(data.stages.ast.outcome,"complete");
  assert.equal(data.stages.symbols.outcome,name==="unsupported-name"?"unsupported":"complete");
  assert.equal(data.stages.types.issue_namespace,"tsodin.checker.Check_Issue");
  assert.equal(data.stages.symbols.lookup_status,"not_implemented");
  assert.equal(data.stages.types.node_types_status,"not_implemented");
  assert.equal(data.stages.types.relations_status,"not_implemented");
  assert.ok(!("code" in (data.stages.types.diagnostics[0]||{})),"internal issue is not a TS code");
  const checkSpan=(o,where)=>{
    assert.ok(Array.isArray(o.bytes)&&o.bytes.length===2,where+": bytes");
    assert.ok(Array.isArray(o.utf16)&&o.utf16.length===2,where+": utf16");
    const [a,b]=o.bytes;
    assert.ok(a<=b,where+": ordered span");
    assert.deepEqual(o.utf16,[prefixUtf16(s,a),prefixUtf16(s,b)],where+": exact UTF-16");
  };
  const tokens=data.stages.tokens.tokens;
  for(const [i,t] of tokens.entries())checkSpan(t,"token "+i);
  assert.equal(tokens.at(-1).kind,"End_Of_File");
  assert.deepEqual(tokens.at(-1).bytes,[Buffer.byteLength(s),Buffer.byteLength(s)]);
  for(const [i,n] of data.stages.ast.nodes.entries()){
    checkSpan(n,"ast "+i);
    for(const child of [n.left,n.right])assert.ok(child===-1||(child>=0&&child<i),"postorder node index");
    if(n.tokens[0]!==-1)assert.ok(n.tokens[0]<=n.tokens[1]&&n.tokens[1]<tokens.length);
  }
  for(const r of data.stages.symbols.references) {
    assert.ok(r.node_index>=0 && r.node_index<data.stages.ast.nodes.length);
    assert.ok(r.symbol_index>=0 && r.symbol_index<data.stages.symbols.symbols.length);
  }
  for(const stage of Object.values(data.stages)){
    for(const diagnostic of stage.diagnostics||[])checkSpan(diagnostic,"diagnostic");
    assert.ok(["implemented","partial","not_implemented"].includes(stage.status));
    assert.ok(["complete","diagnostics","unsupported"].includes(stage.outcome));
  }
  if(name==="unicode-span"){
    assert.ok(tokens.some(t=>t.bytes[0]!==t.utf16[0]),"Unicode offsets must diverge");
  }
  if(name==="typed-mismatch"){
    assert.equal(data.stages.types.diagnostics.length,1,"single internal mismatch");
    assert.equal(data.stages.types.diagnostics[0].issue_id,10,"stable internal checker issue");
  }
  if(name==="unsupported-name"){
    assert.equal(data.stages.types.outcome,"unsupported");
    assert.ok(data.stages.symbols.diagnostics.length>0,"binding failure must remain visible");
  }
  console.log("PASS: "+name+" Odin stages, UTF-16 boundaries and honest status");
}
for(const args of [["check"],["dump","--trace-relations","examples/typed-mismatch.ts"]]){
  const run=spawnSync(compiler,args,{encoding:"utf8",timeout:12000});
  assert.equal(run.status,2,"unsupported checker and trace-relations remain closed");
}
console.log("PASS: deterministic tsodin.dump/1 contract; public check disabled");
