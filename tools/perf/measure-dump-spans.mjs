#!/usr/bin/env node
// R2: the reference cost of exact spans in tsodin.dump/3, without claiming a
// full compiler benchmark. All validation is OUTSIDE the timed subprocess.
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join,resolve} from "node:path";
import {execFileSync} from "node:child_process";
import {performance} from "node:perf_hooks";

const counts=[128,256,512,1024];
const samples=9;
const decoder=new TextDecoder("utf-8",{fatal:true});
const checksum=value=>createHash("sha256").update(value).digest("hex");
function sourceText(n) {
  // Single line, unique declarations, a mix of ASCII and non-BMP literals.
  // Output and work grow together; source count is the only varied dimension.
  // Non-BMP scalars in a supported comment exercise real UTF-16 offsets.
  // Non-ASCII string *bodies* are currently deliberately fail-closed by
  // scanner policy, and are not legal benchmark work for this subset.
  return "/* é😀 */ " + Array.from({length:n},(_,i)=>
    i%4===0 ? `const v${i}: string = "ascii";`
            : `const v${i}: number = ${i%11};`).join(" ");
}
function checkSpan(source,object,label) {
  assert.ok(Array.isArray(object.bytes)&&object.bytes.length===2,label+": bytes");
  assert.ok(Array.isArray(object.utf16)&&object.utf16.length===2,label+": utf16");
  const bytes=Buffer.from(source,"utf8");
  const [a,b]=object.bytes;
  assert.ok(a>=0&&a<=b&&b<=bytes.length,label+": bounds");
  // Independent strict JS UTF-8 decoder: continuation-byte offsets throw.
  const expected=[decoder.decode(bytes.subarray(0,a)).length,
                  decoder.decode(bytes.subarray(0,b)).length];
  assert.deepEqual(object.utf16,expected,label+": exact independent UTF16 offsets");
}
function verify(stdout,source,n) {
  const doc=JSON.parse(stdout);
  assert.equal(doc.schema,"tsodin.dump/3");
  assert.equal(doc.profile,"ts7");
  assert.equal(doc.source.text,source);
  assert.equal(doc.source.bytes,Buffer.byteLength(source));
  assert.equal(doc.source.utf16,source.length);
  assert.equal(doc.stages.tokens.outcome,"complete");
  assert.equal(doc.stages.ast.outcome,"complete");
  assert.equal(doc.stages.symbols.outcome,"complete");
  assert.equal(doc.stages.types.outcome,"complete");
  const tokens=doc.stages.tokens.tokens;
  const nodes=doc.stages.ast.nodes;
  assert.ok(tokens.length>=n*6&&nodes.length>=n,"representative token+AST density");
  for(let i=0;i<tokens.length;i++)checkSpan(source,tokens[i],"token "+i);
  for(let i=0;i<nodes.length;i++)checkSpan(source,nodes[i],"node "+i);
  for(const [stageName,stage] of Object.entries(doc.stages)) {
    for(const [i,diag] of (stage.diagnostics||[]).entries())checkSpan(source,diag,stageName+" diag "+i);
  }
  for(const [i,rel] of doc.stages.types.relations.entries())checkSpan(source,rel,"relation "+i);
  for(const [i,cmp] of doc.stages.types.comparisons.entries())checkSpan(source,cmp,"comparison "+i);
  return {tokens:tokens.length,nodes:nodes.length,outputBytes:Buffer.byteLength(stdout)};
}
function median(values) {
  const a=[...values].sort((x,y)=>x-y);
  return a[Math.floor(a.length/2)];
}
if(process.argv.includes("--self-test")){
  for(const n of counts){
    const src=sourceText(n);
    assert.equal(src.split("\n").length,1,"one line");
    assert.ok(src.includes("😀") && src.includes("é"),"Unicode in every sample");
    assert.equal((src.match(/const v\d+:/g)||[]).length,n,"unique declarations");
  }
  const utf8=Buffer.from("x😀y","utf8");
  assert.equal(decoder.decode(utf8.subarray(0,5)).length,3);
  assert.throws(()=>decoder.decode(utf8.subarray(0,3)));
  console.log("PASS dump-span input/oracle self-test");
  process.exit(0);
}
const bin=process.env.TSODIN_BIN;
if(!bin)throw new Error("TSODIN_BIN must name a pinned Odin-built CLI");
const baseline=process.env.TSODIN_BASE_BIN||null;
const lanes=baseline
  ? [{name:"baseline",bin:baseline},{name:"candidate",bin}]
  : [{name:"candidate",bin}];
const dir=mkdtempSync(join(tmpdir(),"tsodin-dump-spans-"));
try {
  const fixtures=counts.map(n=>{
    const source=sourceText(n);
    const file=join(dir,`case-${n}.ts`);
    writeFileSync(file,source);
    return {n,source,file,readBack:readFileSync(file,"utf8"),
      times:{baseline:[],candidate:[]},digest:null};
  });
  const run=(fixture,lane)=>{
    const start=performance.now();
    const stdout=execFileSync(lane.bin,["dump","--stage=all",resolve(fixture.file)],{
      encoding:"utf8",maxBuffer:32*1024*1024,timeout:120000,
    });
    const elapsedMs=performance.now()-start;
    assert.equal(fixture.readBack,fixture.source);
    const hash=checksum(stdout);
    if(fixture.digest===null){
      fixture.digest=hash;
      fixture.shape=verify(stdout,fixture.source,fixture.n);
    }else{
      assert.equal(hash,fixture.digest,"nondeterministic stage dump");
    }
    return elapsedMs;
  };
  for(const fixture of fixtures)for(const lane of lanes){
    for(let i=0;i<2;i++)run(fixture,lane);
  }
  // AB/BA order on a single runner, rotating the file sizes. Each lane
  // performs exactly the same work with checksum-identical stage dumps.
  for(let round=0;round<samples;round++){
    const offset=round%fixtures.length;
    const ordered=[...fixtures.slice(offset),...fixtures.slice(0,offset)];
    if(round%2===1)ordered.reverse();
    const orderedLanes=round%2===0?lanes:[...lanes].reverse();
    for(const fixture of ordered)for(const lane of orderedLanes){
      fixture.times[lane.name].push(run(fixture,lane));
    }
  }
  const records=fixtures.map(f=>({
    declarations:f.n,sourceBytes:Buffer.byteLength(f.source),
    utf16:f.source.length,...f.shape,
    sha256:f.digest,
    medianMs:median(f.times.candidate),rawMs:f.times.candidate,
    baselineMedianMs:baseline?median(f.times.baseline):null,
    baselineRawMs:baseline?f.times.baseline:null,
    candidateToBaseline:baseline?
      median(f.times.candidate)/median(f.times.baseline):null,
  }));
  console.log("DUMP_SPAN_PROBE "+JSON.stringify({
    schema:"tsodin.dump-span-probe/1",target:"complete-dump-process-including-startup",
    toolchain:"pinned Odin dev-2026-10 -o:speed",runner:process.platform+" "+process.arch,
    runSha:process.env.GITHUB_SHA||null,
    samples,warmupsPerCase:2,counts,
    baselineCommit:baseline?"7b82fdf7b0703f809e7d5c9093c3c9e6addc4b5c":null,
    records,
  }));
}finally{
  rmSync(dir,{recursive:true,force:true});
}
