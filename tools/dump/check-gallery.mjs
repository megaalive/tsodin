#!/usr/bin/env node
import assert from "node:assert/strict";
import {readFileSync,readdirSync} from "node:fs";
import {validateStageDump} from "../../lib/stage-lab.mjs";
const folder="docs/traces/";
const manifest=JSON.parse(readFileSync(folder+"index.json","utf8"));
assert.equal(manifest.schema,"tsodin.gallery/1");
const names=readdirSync("examples").filter(x=>x.endsWith(".ts")).sort().map(x=>x.slice(0,-3));
assert.deepEqual(manifest.examples.map(x=>x.id),names,"Gallery must contain every curated example");
for(const example of manifest.examples){
  assert.match(example.id,/^[a-z0-9-]+$/);
  assert.equal(example.href,example.id+".json");
  const trace=JSON.parse(readFileSync(folder+example.href,"utf8"));
  const verified=validateStageDump(trace);
  assert.equal(trace.stages.types.trace_mode,"all");
  assert.equal(trace.source.name,"examples/"+example.id+".ts");
  assert.ok(verified.tokens>0);
  const falsified=structuredClone(trace);
  falsified.source.utf16++;
  assert.throws(()=>validateStageDump(falsified),/dimensions/,"Bad UTF-16 must fail");
  const tampered=structuredClone(trace);
  tampered.stages.tokens.tokens[0].utf16[1]++;
  assert.throws(()=>validateStageDump(tampered),/mismatch/,"Token divergence must fail");
  if(trace.stages.types.relations.length){
    const forged=structuredClone(trace);
    forged.stages.types.relations[0].node_index=999999;
    assert.throws(()=>validateStageDump(forged),/relation node index/,
      "Forged checker relation IDs must fail");
  }
  console.log("PASS: browser validates actual Odin positions and shape: "+example.id);
}
console.log("PASS: real stage dump gallery; falsified facts rejected");
