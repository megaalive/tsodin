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
  ["comparison-evidence", "diagnostics"],
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
  assert.equal(data.schema,"tsodin.dump/3");
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
  assert.equal(data.stages.types.relations_status,"partial");
  assert.equal(data.stages.types.comparisons_status,"partial");
  assert.equal(data.stages.types.trace_mode,"failures");
  assert.ok(Array.isArray(data.stages.types.relations));
  assert.ok(Array.isArray(data.stages.types.comparisons));
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
    // Deliberately slow independent reference for the optimized Odin
    // token-range lookup; exact token IDs must not change with the algorithm.
    const covered=tokens.flatMap((t,j)=>
      t.kind==="End_Of_File"||t.kind==="Invalid"||t.bytes[0]<n.bytes[0]||t.bytes[1]>n.bytes[1]
        ? [] : [j]);
    assert.deepEqual(n.tokens,covered.length?[covered[0],covered.at(-1)]:[-1,-1],
      "AST node "+i+": binary token range matches independent full scan");
  }
  for(const r of data.stages.symbols.references) {
    assert.ok(r.node_index>=0 && r.node_index<data.stages.ast.nodes.length);
    assert.ok(r.symbol_index>=0 && r.symbol_index<data.stages.symbols.symbols.length);
  }
  for(const [i,rel] of data.stages.types.relations.entries()){
    checkSpan(rel,"relation "+i);
    assert.ok(["Number","Text","Boolean"].includes(rel.source));
    assert.ok(["Number","Text","Boolean"].includes(rel.target));
    assert.ok(["Variable","Assignment"].includes(rel.relation_kind));
    assert.ok(Number.isInteger(rel.node_index)&&rel.node_index>=0&&
              rel.node_index<data.stages.ast.nodes.length);
    assert.ok(Number.isInteger(rel.declaration_index)&&rel.declaration_index>=0&&
              rel.declaration_index<data.stages.ast.declarations.length);
    assert.deepEqual(rel.bytes,[
      data.stages.ast.nodes[rel.node_index].bytes[0],
      data.stages.ast.nodes[rel.node_index].bytes[1],
    ]);
    assert.equal(rel.result,false,"default trace must only contain failed relations");
  }
  for(const [i,c] of data.stages.types.comparisons.entries()){
    checkSpan(c,"comparison "+i);
    const node=data.stages.ast.nodes[c.node_index];
    assert.ok(node&&node.kind==="Binary"&&node.operator===c.operator);
    assert.deepEqual(c.bytes,node.bytes,"comparison must span the original binary node");
    assert.equal(c.overlaps,false,"default trace records only disjoint proofs");
    assert.ok(["Disjoint_Domains","Disjoint_Literals"].includes(c.proof));
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
    assert.equal(data.stages.types.relations.length,1,"same failed decision is traced");
    assert.deepEqual(
      ["Text","Number","Variable",false],
      [data.stages.types.relations[0].source,data.stages.types.relations[0].target,
       data.stages.types.relations[0].relation_kind,data.stages.types.relations[0].result]
    );
  }
  if(name==="comparison-evidence"){
    assert.equal(data.stages.types.comparisons.length,2,
      "default trace records two proven disjoint comparison sites");
    assert.deepEqual(data.stages.types.comparisons.map(c=>c.proof),
      ["Disjoint_Literals","Disjoint_Domains"]);
  }
  if(name==="unsupported-name"){
    assert.equal(data.stages.types.outcome,"unsupported");
    assert.ok(data.stages.symbols.diagnostics.length>0,"binding failure must remain visible");
  }
  console.log("PASS: "+name+" Odin stages, UTF-16 boundaries and honest status");
}
const full=spawnSync(compiler,["dump","--stage=all","--trace-relations",
  resolve("examples/mixed-boolean.ts")],{encoding:"utf8",timeout:12000});
assert.equal(full.status,0,"all-relations mode must succeed: "+full.stderr);
const fullDoc=JSON.parse(full.stdout);
assert.equal(fullDoc.stages.types.trace_mode,"all");
assert.ok(fullDoc.stages.types.relations.length>0,"all mode must capture successful checks");
assert.ok(fullDoc.stages.types.relations.some(r=>r.result),"all mode must contain true decisions");
const comparisonRun=spawnSync(compiler,["dump","--stage=all","--trace-relations",
  resolve("examples/comparison-evidence.ts")],{encoding:"utf8",timeout:12000});
assert.equal(comparisonRun.status,0,comparisonRun.stderr);
const comparisons=JSON.parse(comparisonRun.stdout).stages.types.comparisons;
assert.deepEqual(comparisons.map(c=>c.proof),
  ["Disjoint_Literals","Same_Literal","Same_Symbol","Widened_Domain","Disjoint_Domains"]);
assert.deepEqual(comparisons.map(c=>c.overlaps),[false,true,true,true,false]);
for(const args of [["check"],["dump"],["dump","--trace-relations","examples/typed-mismatch.ts"]]){
  const run=spawnSync(compiler,args,{encoding:"utf8",timeout:12000});
  assert.equal(run.status,2,"unsupported checker and trace-relations remain closed");
}
console.log("PASS: deterministic tsodin.dump/3 relation and comparison contract; public check disabled");
