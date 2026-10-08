#!/usr/bin/env node
// Version-scoped auxiliary lexical witness. TS6 scanner is not native TS7.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {createRequire} from "node:module";
import {spawnSync} from "node:child_process";
import {resolve} from "node:path";
import {fileURLToPath} from "node:url";
const root=resolve(fileURLToPath(new URL("../..",import.meta.url)));
const binary=process.env.TSODIN_CONTEXTTRACE;
const api=process.env.TSODIN_TS6_API;
if(!binary||!api)throw new Error("Set TSODIN_CONTEXTTRACE and TSODIN_TS6_API");
const ts=createRequire(import.meta.url)(api);
if(!String(ts.version).startsWith("6.")||typeof ts.createScanner!=="function"){
  throw new Error("Auxiliary reference is not the pinned TS6 scanner");
}
// Stable Odin Token_Kind ordinal mapping; a change is reviewed explicitly.
const kinds=[
  null,
  ts.SyntaxKind.EndOfFileToken,
  ts.SyntaxKind.Identifier,
  ts.SyntaxKind.NumericLiteral,
  ts.SyntaxKind.StringLiteral,
  ts.SyntaxKind.LetKeyword,
  ts.SyntaxKind.ConstKeyword,
  ts.SyntaxKind.VarKeyword,
  ts.SyntaxKind.NumberKeyword,
  ts.SyntaxKind.StringKeyword,
  ts.SyntaxKind.BooleanKeyword,
  ts.SyntaxKind.ColonToken,
  ts.SyntaxKind.SemicolonToken,
  ts.SyntaxKind.EqualsToken,
  ts.SyntaxKind.CommaToken,
  ts.SyntaxKind.OpenParenToken,
  ts.SyntaxKind.CloseParenToken,
  ts.SyntaxKind.OpenBraceToken,
  ts.SyntaxKind.CloseBraceToken,
  ts.SyntaxKind.PlusToken,
  ts.SyntaxKind.MinusToken,
  ts.SyntaxKind.AsteriskToken,
  ts.SyntaxKind.SlashToken,
  ts.SyntaxKind.SlashEqualsToken,
  ts.SyntaxKind.LessThanToken,
  ts.SyntaxKind.GreaterThanToken,
  ts.SyntaxKind.RegularExpressionLiteral,
  ts.SyntaxKind.NoSubstitutionTemplateLiteral,
  ts.SyntaxKind.TemplateHead,
  ts.SyntaxKind.TemplateMiddle,
  ts.SyntaxKind.TemplateTail,
  ts.SyntaxKind.LessThanToken, // JSX start is parser-driven; not used here.
  ts.SyntaxKind.JsxText,
];
assert.equal(kinds.length,33);
for(const kind of kinds.slice(1))assert.equal(typeof kind,"number");

function referenceTokens(src,mode){
  const scanner=ts.createScanner(ts.ScriptTarget.Latest,true,ts.LanguageVariant.Standard,src);
  const tokens=[];
  const templates=[];
  let afterSemicolon=false;
  for(let i=0;i<10000;i++){
    let kind=scanner.scan();
    if(mode==="regex" && afterSemicolon && kind===ts.SyntaxKind.SlashToken){
      kind=scanner.reScanSlashToken();
      afterSemicolon=false;
    }
    if(kind===ts.SyntaxKind.TemplateHead){
      templates.push({braces:0});
    }else if(templates.length){
      const frame=templates.at(-1);
      if(kind===ts.SyntaxKind.OpenBraceToken){
        frame.braces++;
      }else if(kind===ts.SyntaxKind.CloseBraceToken){
        if(frame.braces>0)frame.braces--;
        else {
          kind=scanner.reScanTemplateToken(false);
          if(kind===ts.SyntaxKind.TemplateTail)templates.pop();
        }
      }
    }
    tokens.push({kind,start:scanner.getTokenPos(),end:scanner.getTextPos()});
    if(kind===ts.SyntaxKind.SemicolonToken)afterSemicolon=true;
    if(kind===ts.SyntaxKind.EndOfFileToken){
      assert.equal(templates.length,0,"Reference has an unclosed template");
      return tokens;
    }
  }
  throw new Error("Reference scanner loop exceeded limit");
}
function odinTokens(path,mode){
  const proc=spawnSync(binary,[mode,path],{encoding:"utf8",maxBuffer:1024*1024,timeout:15000});
  if(proc.error||proc.status!==0){
    throw new Error("Odin trace failed: "+String(proc.error||proc.stdout||proc.stderr));
  }
  return proc.stdout.trim().split(/\r?\n/).map((line,i)=>{
    const fields=line.split("\t").map(Number);
    if(fields.length!==3||fields.some(x=>!Number.isSafeInteger(x)))throw new Error("Bad trace line "+i);
    const [ordinal,start,end]=fields;
    if(ordinal<1||ordinal>=kinds.length||start<0||end<start)throw new Error("Invalid Odin token "+line);
    return {kind:kinds[ordinal],start,end};
  });
}
for(const [fixture,mode] of [["context-regex","regex"],["context-template","template"]]){
  const path=resolve(root,"tests/lexical/"+fixture+".ts");
  const src=readFileSync(path,"utf8");
  const reference=referenceTokens(src,mode);
  const actual=odinTokens(path,mode);
  assert.equal(actual.length,reference.length,fixture+": number of tokens differs");
  for(let i=0;i<reference.length;i++){
    assert.deepEqual(actual[i],reference[i],fixture+": token "+i+" ("+ts.SyntaxKind[reference[i].kind]+")");
  }
  console.log("PASS "+fixture+": "+actual.length+" contextual token kinds and UTF-16 spans (TS6 supplemental)");
}
console.log("PASS: contextual lexical witness only; neither TS7 syntax parity nor tsodin checker is established");
