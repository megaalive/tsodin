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
  assert.equal(trace.schema,"tsodin.dump/3");
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
    const inverted=structuredClone(trace);
    inverted.stages.types.relations[0].result=!inverted.stages.types.relations[0].result;
    assert.throws(()=>validateStageDump(inverted),/Inconsistent primitive compatibility/,
      "A forged YES/NO answer must not pass structural validation");
    const misclassified=structuredClone(trace);
    const first=misclassified.stages.types.relations[0];
    first.relation_kind=first.relation_kind==="Variable"?"Assignment":"Variable";
    assert.throws(()=>validateStageDump(misclassified),/matching statement RHS/,
      "A relation cannot claim the wrong checker decision site");
    const wrongTarget=structuredClone(trace);
    const relation=wrongTarget.stages.types.relations.find(r=>r.relation_kind==="Variable");
    if(relation){
      relation.target=relation.target==="Number"?"Text":"Number";
      relation.result=relation.source===relation.target;
      assert.throws(()=>validateStageDump(wrongTarget),/annotated declaration/,
        "A type-correct-looking decision still needs the original annotated target");
    }
    if(trace.stages.types.relations.length>1){
      const reversed=structuredClone(trace);
      [reversed.stages.types.relations[0],reversed.stages.types.relations[1]]=
        [reversed.stages.types.relations[1],reversed.stages.types.relations[0]];
      assert.throws(()=>validateStageDump(reversed),/expression source order/,
        "Shuffled or duplicated decisions must not masquerade as Odin source order");
    }
    const assignment=trace.stages.types.relations.find(r=>r.relation_kind==="Assignment");
    if(assignment){
      const mismatched=structuredClone(trace);
      const live=mismatched.stages.types.relations.find(r=>r.relation_kind==="Assignment");
      const event=mismatched.stages.ast.statements.find(
        e=>e.kind==="Assignment"&&e.expression===live.node_index);
      const ref=mismatched.stages.symbols.references.find(r=>r.node_index===event.target_node);
      if(mismatched.stages.symbols.symbols.length>1){
        ref.symbol_index=(ref.symbol_index+1)%mismatched.stages.symbols.symbols.length;
        assert.throws(()=>validateStageDump(mismatched),/target disagrees with binder/,
          "Assignment target must resolve to the actual declaration");
      }
    }
  }
  if(trace.stages.types.comparisons.length){
    const id=structuredClone(trace);
    id.stages.types.comparisons[0].node_index=99999;
    assert.throws(()=>validateStageDump(id),/comparison provenance/,
      "Invented comparison node must fail");
    const swapped=structuredClone(trace);
    swapped.stages.types.comparisons[0].overlaps=
      !swapped.stages.types.comparisons[0].overlaps;
    assert.throws(()=>validateStageDump(swapped),/Inconsistent comparison proof/,
      "Invented equality overlap must fail");
    const fakeOp=structuredClone(trace);
    fakeOp.stages.types.comparisons[0].operator="Less_Than";
    assert.throws(()=>validateStageDump(fakeOp),/comparison provenance/,
      "Comparison operator must match the original syntax token");
    const moved=structuredClone(trace);
    moved.stages.types.comparisons[0].bytes[0]++;
    moved.stages.types.comparisons[0].utf16[0]++;
    assert.throws(()=>validateStageDump(moved),/Comparison span/,
      "Moved binary comparison source span must fail");
    const widened=trace.stages.types.comparisons.find(c=>c.proof==="Widened_Domain");
    if(widened){
      const wrongSymbol=structuredClone(trace);
      wrongSymbol.stages.types.comparisons.find(c=>c.node_index===widened.node_index).proof="Same_Symbol";
      assert.throws(()=>validateStageDump(wrongSymbol),/Same_Symbol proof disagrees/,
        "A forged Same_Symbol proof must reference one actual binder symbol twice");
    }
    if(trace.stages.types.comparisons.length>1){
      const reversed=structuredClone(trace);
      [reversed.stages.types.comparisons[0],reversed.stages.types.comparisons[1]]=
        [reversed.stages.types.comparisons[1],reversed.stages.types.comparisons[0]];
      assert.throws(()=>validateStageDump(reversed),/source order/,
        "Out-of-order comparison records must fail");
    }
  }
  console.log("PASS: browser validates actual Odin positions and shape: "+example.id);
}
console.log("PASS: real stage dump gallery; falsified facts rejected");
