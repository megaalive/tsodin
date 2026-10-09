#!/usr/bin/env node
// Selective official-conformance source adapter. This is NOT Microsoft's
// complete harness, and TypeScript oracle success is NOT Tsodin conformance.
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join, resolve, posix} from "node:path";
import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";

const root=resolve(fileURLToPath(new URL("../..",import.meta.url)));
const revision="1e4744d68260a7cb91b62b12edc3f6a2187faaf1";
const directive=/^\/\/\s*@([a-z][a-z0-9]*)\s*:\s*([^\r\n]*)\s*$/i;
const supportedOptions=new Set(["target","strict","module","lib","noemit",
  "allowunreachablecode","allowunusedlabels","alwaysstrict","jsx"]);
const allowedTargets=new Set(["es5","es2015","es2016","es2017","es2018",
  "es2019","es2020","es2021","es2022","esnext"]);
const allowedModules=new Set(["none","commonjs","es2015","es2020","esnext"]);
const allowedJsx=new Set(["preserve","react","react-jsx","react-jsxdev"]);
const allowedLibs=new Set(["es5","es2015","es2016","es2017","es2018",
  "es2019","es2020","es2021","es2022","esnext","dom"]);
const safeFile=name=>{
  if(typeof name!=="string" || !/^[a-zA-Z0-9_./-]+\.tsx?$/.test(name) ||
     name.startsWith("/") || name.includes("\\") ||
     name.split("/").some(p=>!p||p==="."||p==="..") ||
     name==="tsconfig.ts") throw Error("unsafe or unsupported @filename: "+name);
  return name;
};
const bool=(key,v)=>{
  if(v!=="true"&&v!=="false")throw Error("invalid @"+key+" Boolean value: "+v);
  return v==="true";
};
function optionsFromDirectives(global) {
  const result={noEmit:true,types:[],incremental:false};
  for(const [key,raw] of Object.entries(global)){
    const value=raw.toLowerCase();
    if(!supportedOptions.has(key))throw Error("unsupported global @"+key+" directive");
    switch(key){
      case "target": {
        const targets=value.split(",").map(x=>x.trim());
        if(targets.length<1||targets.some(t=>!allowedTargets.has(t))||
           new Set(targets).size!==targets.length) throw Error("unsupported @target");
        // Preserve target variants: the source is compiled separately for each.
        result.targetVariants=targets;
        break;
      }
      case "strict": result.strict=bool(key,value);break;
      case "noemit": result.noEmit=bool(key,value);break;
      case "alwaysstrict": result.alwaysStrict=bool(key,value);break;
      case "allowunreachablecode": result.allowUnreachableCode=bool(key,value);break;
      case "allowunusedlabels": result.allowUnusedLabels=bool(key,value);break;
      case "module":
        if(!allowedModules.has(value))throw Error("unsupported @module");
        result.module=value;break;
      case "jsx":
        if(!allowedJsx.has(value))throw Error("unsupported @jsx");
        result.jsx=value;break;
      case "lib": {
        const libs=value.split(",").map(x=>x.trim());
        if(libs.length<1||libs.some(x=>!allowedLibs.has(x)))
          throw Error("unsupported @lib");
        result.lib=libs;break;
      }
    }
  }
  const variants=result.targetVariants||[null];
  delete result.targetVariants;
  return variants.map(target=>({...result,...(target?{target}:{})}));
}
// Mirror only the smallest structurally proved segment of Microsoft's
// @option/@filename parser. Unknown directives are rejected, never ignored.
// A named @filename boundary starts a NEW physical test unit.
export function parseOfficialCase(source, implicitName) {
  safeFile(implicitName);
  const opts=Object.create(null), units=[],names=new Set();
  let current=null, sawBoundary=false, sawCode=false;
  const lines=source.match(/[^\r\n]*(?:\r\n|\n|\r|$)/g).filter(Boolean);
  for(const line of lines){
    const match=directive.exec(line.replace(/\r?\n$|\r$/,""));
    if(match){
      const key=match[1].toLowerCase(), value=match[2].trim();
      if(key==="filename"){
        safeFile(value);
        if(!sawBoundary && sawCode)throw Error("source before first @filename");
        if(names.has(value.toLowerCase()))throw Error("duplicate case file: "+value);
        names.add(value.toLowerCase());
        current={name:value,content:""};
        units.push(current);
        sawBoundary=true;
        continue;
      }
      if(!sawBoundary){
        if(Object.hasOwn(opts,key))throw Error("duplicate global directive: "+key);
        opts[key]=value;
      }else{
        // File-local compiler directives are real upstream semantics and are
        // not mapped until a faithful file-option interpreter is available.
        throw Error("file-local @"+key+" not implemented");
      }
      continue;
    }
    if(/^\/\/\s*@/.test(line)){
      throw Error("unrecognized/malformed directive");
    }
    if(!sawBoundary && !current)current={name:implicitName,content:""};
    if(!sawBoundary && !/^\s*(?:\/\/.*)?$/.test(line))sawCode=true;
    if(sawBoundary || !/^\s*$/.test(line) || current.content){
      // Retain original newline boundaries and source text verbatim for
      // real diagnostic line/column positions. Directives stay comments
      // by replacing them with line terminators instead of disappearing.
      current.content+=line;
    }
  }
  if(!sawBoundary){if(!units.length)units.push(current||{name:implicitName,content:""});}
  if(!units.length)throw Error("no real files in official case");
  // The single-file reader has no imported-file awareness. Keep the source
  // shape, but never declare native parity on a multi-file corpus yet.
  const options=optionsFromDirectives(opts);
  return {units,options,directives:opts,hasExplicitFiles:sawBoundary};
}
function hashGitBlob(bytes){
  return createHash("sha1").update(Buffer.from("blob "+bytes.length+"\0")).update(bytes).digest("hex");
}
export function validateSelection(manifest) {
  assert.equal(manifest.schemaVersion,1);
  assert.equal(manifest.pinnedSourceRepository,"microsoft/TypeScript");
  assert.equal(manifest.sourceRevision,revision);
  assert.equal(manifest.pinnedExecutableProfile,"ts7");
  assert.equal(manifest.selection,"selective_official_source_fixtures_not_official_baselines");
  assert.ok(Array.isArray(manifest.cases)&&manifest.cases.length>0&&manifest.cases.length<=30);
  const ids=new Set(),paths=new Set();
  for(const c of manifest.cases){
    assert.match(c.id,/^[a-z0-9]+(?:-[a-z0-9]+)*$/);
    assert.ok(!ids.has(c.id));ids.add(c.id);
    assert.equal(c.tsodinDisposition,"unsupported",
      "a new supported case requires independent parity authorization");
    assert.ok(c.reason.length>=25);
    assert.match(c.upstreamPath,/^tests\/cases\/conformance\/[A-Za-z0-9_./-]+\.ts$/);
    assert.equal(c.localPath,"tests/oracle/official-selected/sources/"+c.id+".ts");
    assert.ok(!paths.has(c.upstreamPath));paths.add(c.upstreamPath);
    assert.match(c.gitBlobSha1,/^[0-9a-f]{40}$/);
    const raw=readFileSync(resolve(root,c.localPath));
    assert.equal(hashGitBlob(raw),c.gitBlobSha1,
      "official source bytes differ from the pinned Microsoft Git blob");
    parseOfficialCase(raw.toString("utf8"),c.id+".ts");
  }
  return manifest.cases;
}
function capture(tsc,c) {
  const source=readFileSync(resolve(root,c.localPath),"utf8");
  const parsed=parseOfficialCase(source,c.id+".ts");
  const workspace=mkdtempSync(join(tmpdir(),"tsodin-official-case-"));
  const reports=[];
  try{
    for(const unit of parsed.units){
      const path=join(workspace,unit.name);
      mkdirSync(resolve(path,".."),{recursive:true});
      writeFileSync(path,unit.content);
    }
    for(const [variant,options] of parsed.options.entries()){
      const config={compilerOptions:options,files:parsed.units.map(x=>x.name)};
      writeFileSync(join(workspace,"tsconfig.json"),JSON.stringify(config));
      const args=["-p","tsconfig.json","--pretty","false","--incremental",
                  "false","--singleThreaded"];
      const run=spawnSync(tsc,args,{cwd:workspace,encoding:"utf8",timeout:60000,
                                      maxBuffer:8*1024*1024});
      if(run.error||run.signal||run.status===null)
        throw Error("TS7 oracle did not complete: "+String(run.error||run.signal||run.status));
      const matches=[...(run.stdout+"\n"+run.stderr).matchAll(
        /^(.*?\.tsx?)\((\d+),(\d+)\): error TS(\d+):/gm)];
      reports.push({variant,options,exitCode:run.status,
        diagnostics:matches.map(m=>({file:posix.basename(m[1].replaceAll("\\","/")),
          line:Number(m[2]),column:Number(m[3]),code:Number(m[4])})),
        diagnosticTextSha256:createHash("sha256").update(run.stdout+"\n"+run.stderr).digest("hex"),
      });
    }
  }finally{rmSync(workspace,{recursive:true,force:true});}
  return {id:c.id,upstreamPath:c.upstreamPath,sourceRevision:revision,
    sourceGitBlob:c.gitBlobSha1,
    tsodinStatus:"unsupported",reason:c.reason,
    officialMicrosoftBaselineCompared:false,
    officialHarnessExecuted:false,
    nativeCheckerInvoked:false,
    unitFileNames:parsed.units.map(x=>x.name),
    compilerVariants:reports};
}
if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const manifest=JSON.parse(readFileSync(resolve(root,
    "tests/oracle/official-selected/manifest.json"),"utf8"));
  const selected=validateSelection(manifest);
  const tsc=process.env.TSODIN_TSC;
  if(!tsc)throw Error("TSODIN_TSC required for independent TS7 capture");
  const version=spawnSync(tsc,["--version"],{encoding:"utf8",timeout:10000});
  assert.equal(version.status,0);
  assert.match(version.stdout,/7\.0\.2\s*$/);
  const records=selected.map(c=>capture(tsc,c));
  const result={schema:"tsodin.official-selection/1",
    authority:"independent TypeScript 7.0.2 CLI, not upstream official harness",
    sourceRevision:revision,referenceVersion:"7.0.2",
    counts:{selected:records.length,tsodinPassed:0,
      tsodinUnsupported:records.length,tsodinFailed:0,tsodinNotRun:0},
    records};
  console.log("OFFICIAL_SELECTION "+JSON.stringify(result));
}
