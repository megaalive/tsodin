#!/usr/bin/env node
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {parseOfficialCase,validateSelection} from "./official-case.mjs";
const root=resolve(fileURLToPath(new URL("../..",import.meta.url)));
const fixtures=JSON.parse(readFileSync(resolve(root,
  "tests/oracle/official-selected/manifest.json"),"utf8"));
assert.equal(validateSelection(fixtures).length,3,
  "all selected original sources match pinned upstream Git blobs");
const multi=[
  "// @target: es5, es2015\r\n",
  "// @strict: false\r\n",
  "// @filename: alpha.ts\r\n",
  "const a: number = 1;\r\n",
  "// @filename: folder/beta.ts\r\n",
  "const b: string = 'two';\r\n",
].join("");
const parsed=parseOfficialCase(multi,"fallback.ts");
assert.equal(parsed.hasExplicitFiles,true);
assert.deepEqual(parsed.units.map(x=>x.name),["alpha.ts","folder/beta.ts"]);
assert.deepEqual(parsed.options.map(x=>x.target),["es5","es2015"]);
assert.deepEqual(parsed.options.map(x=>x.strict),[false,false]);
assert.equal(parsed.units[0].content,"const a: number = 1;\r\n");
assert.equal(parsed.units[1].content,"const b: string = 'two';\r\n");
assert.equal(parseOfficialCase("// @noEmit: false\nlet a=1;","x.ts").options[0].noEmit,
  false,"supported upstream noEmit directives must remain exact");
assert.throws(()=>parseOfficialCase("// @target: es5\nconst x=1;\n// @filename: a.ts\nconst x=2;","x.ts"),/source before first/);
assert.throws(()=>parseOfficialCase("// @filename: ../escape.ts\nlet x=1;","x.ts"),/unsafe/);
assert.throws(()=>parseOfficialCase("// @filename: a.ts\nlet x=1;\n// @filename: a.ts\nlet x=2;","x.ts"),/duplicate/);
assert.throws(()=>parseOfficialCase("// @target: es5, es999\nlet x=1;","x.ts"),/unsupported/);
assert.throws(()=>parseOfficialCase("// @target: es5\n// @target: es2015\nlet x=1;","x.ts"),/duplicate/);
assert.throws(()=>parseOfficialCase("// @moduleResolution: bundler\nlet x=1;","x.ts"),/unsupported/);
assert.throws(()=>parseOfficialCase("// @filename: a.ts\n// @strict: true\nlet x=1;","x.ts"),/file-local/);
assert.throws(()=>parseOfficialCase("// @filename: C:/absolute.ts\nlet x=1;","x.ts"),/unsafe/);
const listed=fixtures.cases.map(x=>x.id);
assert.deepEqual(listed,["annotated-initializers","typeof-number-guard","strict-octal-literals"]);
console.log("PASS: pinned official source identities, directives, target matrix, real file boundaries, fail-closed unknown options");
