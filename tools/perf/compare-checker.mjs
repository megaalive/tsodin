#!/usr/bin/env node
// G5F8P: same-host, three-revision, checker-only diagnostic probe.
// NOT an official TypeScript/tsgo/Rust benchmark or a headline speed claim.
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {appendFileSync} from "node:fs";
import {cpus,freemem,platform,release,arch} from "node:os";
import {resolve} from "node:path";
import {performance} from "node:perf_hooks";
import {fileURLToPath} from "node:url";

const repo=resolve(fileURLToPath(new URL("../..",import.meta.url)));
const CASES=[
  "checker-primitives-valid",
  "checker-boolean-identity-valid",
  "checker-negated-identity-valid",
  "checker-flow-mixed-rhs-valid",
  "checker-flow-mixed-left-valid",
  "checker-flow-mixed-nested-errors",
  "checker-flow-three-nested-valid",
];
const LANES=["preN","postN","postO"];
const PERMUTATIONS=[
  ["preN","postN","postO"], ["postO","postN","preN"],
  ["postN","preN","postO"], ["postN","postO","preN"],
  ["preN","postO","postN"], ["postO","preN","postN"],
];
const REPETITIONS=8192;
const ROUNDS=12;
const WARMUPS=2;
const median=values=>{
  assert.ok(values.length>0 && values.every(v=>Number.isFinite(v) && v>=0));
  const a=[...values].sort((x,y)=>x-y),i=Math.floor(a.length/2);
  return a.length%2?a[i]:(a[i-1]+a[i])/2;
};
const stats=values=>{
  const m=median(values);
  const mad=median(values.map(v=>Math.abs(v-m)));
  const half=Math.floor(values.length/2);
  const first=median(values.slice(0,half)),last=median(values.slice(half));
  return {medianMs:m,relativeMadPercent:m?100*mad/m:null,
    splitHalfDriftPercent:m?100*Math.abs(first-last)/m:null,
    samplesMs:values};
};
const parseOutput=(stdout,label)=>{
  const m=/^RESULT\t(\d+)\t(\d+)\t(\d+)\r?\n?$/.exec(stdout);
  assert.ok(m,label+": malformed or additional benchmark output: "+stdout.slice(0,500));
  assert.equal(Number(m[1]),REPETITIONS,label+": benchmark repetition drift");
  return {repetitions:Number(m[1]),diagnostics:Number(m[2]),checksum:m[3]};
};
if(process.argv[2]==="--self-test"){
  assert.equal(median([9,1,3]),3);
  assert.equal(median([8,2,4,6]),5);
  assert.equal(stats([1,1,1,1]).relativeMadPercent,0);
  assert.deepEqual(parseOutput("RESULT\t8192\t0\t12345\n","fixture"),
    {repetitions:8192,diagnostics:0,checksum:"12345"});
  assert.throws(()=>parseOutput("DIAG\nRESULT\t8192\t0\t12345\n","bad"),/malformed/);
  assert.equal(new Set(PERMUTATIONS.flat()).size,3);
  console.log("PASS: checker performance runner stats, strict checksums and format");
  process.exit(0);
}
assert.equal(process.argv.length,2,"no arbitrary benchmark CLI arguments");
const executables={
  preN:process.env.TSODIN_BENCH_PRE_N,
  postN:process.env.TSODIN_BENCH_POST_N,
  postO:process.env.TSODIN_BENCH_POST_O,
};
for(const lane of LANES)assert.ok(executables[lane],lane+": missing compiled executable");
function run(lane,id){
  const file=resolve(repo,"tests/oracle",id,"index.ts");
  const start=performance.now();
  const child=spawnSync(executables[lane],[file],{
    cwd:repo,encoding:"utf8",timeout:120000,maxBuffer:1048576,
  });
  const elapsed=performance.now()-start;
  assert.ifError(child.error);
  assert.equal(child.status,0,lane+"/"+id+": "+child.stdout+" "+child.stderr);
  assert.equal(child.signal,null,lane+"/"+id+": killed");
  return {elapsed,result:parseOutput(child.stdout,lane+"/"+id)};
}
const all=[];
for(const id of CASES){
  const samples=Object.fromEntries(LANES.map(lane=>[lane,[]]));
  let expected=null;
  // Every lane is warmed on the exact same source before observations.
  for(let i=0;i<WARMUPS;i++){
    for(const lane of PERMUTATIONS[i]){
      const actual=run(lane,id).result;
      if(expected===null)expected=actual;
      else assert.deepEqual(actual,expected,id+": pre/post diagnostic checksum differs");
    }
  }
  for(let round=0;round<ROUNDS;round++){
    for(const lane of PERMUTATIONS[round%PERMUTATIONS.length]){
      const sample=run(lane,id);
      assert.deepEqual(sample.result,expected,id+": correctness drift mid-run");
      samples[lane].push(sample.elapsed);
    }
  }
  const measured=Object.fromEntries(LANES.map(lane=>[lane,stats(samples[lane])]));
  const ratios={
    postNOverPreN:measured.postN.medianMs/measured.preN.medianMs,
    postOOverPostN:measured.postO.medianMs/measured.postN.medianMs,
    postOOverPreN:measured.postO.medianMs/measured.preN.medianMs,
  };
  const unstable=LANES.some(lane=>
    measured[lane].relativeMadPercent>8 ||
    measured[lane].splitHalfDriftPercent>12);
  all.push({id,expected,lanes:measured,ratios,unstable});
  console.error(id+": O/pre-N="+ratios.postOOverPreN.toFixed(4)+"x "+
    "N/pre-N="+ratios.postNOverPreN.toFixed(4)+"x "+
    "O/N="+ratios.postOOverPostN.toFixed(4)+"x "+
    (unstable?"UNSTABLE":"exploratory"));
}
const output={
  schema:"tsodin.checker-perf/1",
  scope:"checker only; warmed parser/binder, repeated real check_file; process startup remains",
  claims:"exploratory CI comparison, NOT official conformance or external compiler ranking",
  revisions:{
    preN:process.env.TSODIN_SHA_PRE_N,
    postN:process.env.TSODIN_SHA_POST_N,
    postO:process.env.TSODIN_SHA_POST_O,
  },
  flags:"-o:speed",
  benchmarkDriver:"identical src/checkbench/main.odin copied into all 3 revisions",
  toolchain:"Odin dev-2026-10 pinned release",
  environment:{platform:platform(),osRelease:release(),arch:arch(),
    cpuModel:cpus()[0]?.model??"unknown",logicalCores:cpus().length,
    freeMemoryBytesAtEnd:freemem(),affinity:"uncontrolled shared GitHub runner"},
  protocol:{repetitionsPerProcess:REPETITIONS,warmupsPerLanePerCase:WARMUPS,
    roundsPerLanePerCase:ROUNDS,order:"six balanced lane permutations repeated twice",
    timing:"Node process wall; no baseline/startup subtraction"},
  results:all,
  inconclusiveCases:all.filter(x=>x.unstable).map(x=>x.id),
};
if(process.env.GITHUB_STEP_SUMMARY){
  const lines=["### Checker refactor probe (exploratory only)","",
    "| Workload | N / pre-N | O / N | O / pre-N | Stability |",
    "|---|---:|---:|---:|---|"];
  for(const c of all)lines.push("| "+c.id+" | "+
    c.ratios.postNOverPreN.toFixed(3)+"x | "+
    c.ratios.postOOverPostN.toFixed(3)+"x | "+
    c.ratios.postOOverPreN.toFixed(3)+"x | "+
    (c.unstable?"inconclusive":"exploratory")+" |");
  lines.push("","**No official performance claims**. Real TS project and end-to-end work are outside this probe. Full samples retained in artifact.");
  appendFileSync(process.env.GITHUB_STEP_SUMMARY,lines.join("\n")+"\n");
}
console.log(JSON.stringify(output,null,2));
