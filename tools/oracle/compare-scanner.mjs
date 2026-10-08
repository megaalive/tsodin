#!/usr/bin/env node
// Supplemental lexical witness only: TS6 JS scanner vs Odin M1 subset.
// TypeScript 7 native CLI remains the authoritative semantic oracle.
// Matching these tokens is not proof of TS7 scanner or parser conformance.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root=resolve(fileURLToPath(new URL('../..',import.meta.url)));
const scantrace=process.env.TSODIN_SCANTRACE;
const ts6Path=process.env.TSODIN_TS6_API;
if (!scantrace || !ts6Path) {
  throw new Error('Set TSODIN_SCANTRACE and TSODIN_TS6_API to pinned binaries');
}
const require=createRequire(import.meta.url);
const ts=require(ts6Path);
if (typeof ts.createScanner!=='function' || !String(ts.version).startsWith('6.')) {
  throw new Error('Auxiliary lexical reference must be TypeScript 6 scanner API');
}
// These are the explicit numeric enum ordinals from src/scanner/scanner.odin.
// A token-kind API change must update this adapter rather than silently drift.
const ordinals=[
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
];
assert.equal(ordinals.length,22);
for(const value of ordinals.slice(1))assert.equal(typeof value,'number');
const fixtureNames=['scanner-ascii','scanner-utf16-crlf'];
for (const name of fixtureNames) {
  const file=resolve(root,'tests/oracle',name,'index.ts');
  const src=readFileSync(file,'utf8');
  const ref=ts.createScanner(ts.ScriptTarget.Latest,true,ts.LanguageVariant.Standard,src);
  const expected=[];
  for(let i=0;i<10000;i++){
    const kind=ref.scan();
    expected.push({kind,start:ref.getTokenPos(),end:ref.getTextPos()});
    if(kind===ts.SyntaxKind.EndOfFileToken)break;
  }
  if(expected.at(-1)?.kind!==ts.SyntaxKind.EndOfFileToken)throw new Error('Reference token overflow');
  const outcome=spawnSync(scantrace,[file],{encoding:'utf8',timeout:12000,maxBuffer:1024*1024});
  if(outcome.error||outcome.status!==0){
    throw new Error(name+': Odin scantrace failed: '+String(outcome.error||outcome.stdout||outcome.stderr));
  }
  const actual=outcome.stdout.trim().split(/\r?\n/).map((line,i)=>{
    const fields=line.split('\t');
    if(fields.length!==3)throw new Error(name+': malformed Odin trace line '+(i+1)+': '+line);
    const [ordinal,start,end]=fields.map(Number);
    if(![ordinal,start,end].every(Number.isSafeInteger)||ordinal<=0||ordinal>=ordinals.length){
      throw new Error(name+': invalid token trace '+line);
    }
    return {kind:ordinals[ordinal],start,end};
  });
  if(actual.length!==expected.length){
    throw new Error(name+': token count differs (Odin '+actual.length+' vs TS6 '+expected.length+')');
  }
  for(let i=0;i<expected.length;i++){
    assert.deepEqual(actual[i],expected[i],name+': token '+i+' / TS6='+ts.SyntaxKind[expected[i].kind]);
  }
  console.log('PASS '+name+': '+actual.length+' token kind + UTF-16 span records match TypeScript 6 lexical witness');
}
console.log('PASS lexical witness: TS6 scanner auxiliary only; TypeScript 7 CLI acceptance is a separate gate');
