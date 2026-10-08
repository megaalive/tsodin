// Pure helpers for the current tsodin Observatory.
// Unicode operations are browser-side references, not Odin checker execution.
export function inspectSource(text) {
  if (typeof text !== "string") throw new TypeError("Source must be a string");
  const encoder = new TextEncoder();
  const characters = [];
  let bytes = 0;
  let units = 0;
  let hasUnpairedSurrogate = false;
  for (const character of text) {
    const point = character.codePointAt(0);
    const byteWidth = encoder.encode(character).length;
    const unitWidth = character.length;
    if (point >= 0xD800 && point <= 0xDFFF) hasUnpairedSurrogate = true;
    characters.push({character, point, byteStart:bytes, byteEnd:bytes+byteWidth, unitStart:units, unitEnd:units+unitWidth});
    bytes += byteWidth;
    units += unitWidth;
  }
  return {bytes,units,scalars:characters.length,characters,hasUnpairedSurrogate};
}
export function utf16AtByteOffset(source, position) {
  if (!Number.isInteger(position) || position < 0 || position > source.bytes) return null;
  if (position === 0) return 0;
  for (const character of source.characters) {
    if (position === character.byteEnd) return character.unitEnd;
    if (position > character.byteStart && position < character.byteEnd) return null;
  }
  return position === source.bytes ? source.units : null;
}
// A detected file is evidence of a file, not proof of feature completeness.
export function summarizeSourceTree(tree) {
  if (!tree || tree.truncated === true || !Array.isArray(tree.tree)) {
    throw new TypeError("Missing, invalid or truncated GitHub source tree");
  }
  const files = new Set(tree.tree.filter(item=>item?.type==="blob" && typeof item.path==="string").map(item=>item.path));
  const paths = [...files];
  const has = path => files.has(path);
  const under = prefix => paths.some(path=>path.startsWith(prefix) && path.endsWith(".odin"));
  const projects = paths.filter(path=>/^tests\/oracle\/[^/]+\/tsconfig\.json$/.test(path));
  return {
    odinFiles: paths.filter(path=>path.startsWith("src/") && path.endsWith(".odin")).length,
    oracleProjects: projects.length,
    capabilities: [
      {name:"CLI bootstrap", found:has("src/cli/main.odin"), path:"src/cli/main.odin", detail:"CLI source present; checker success is not implied"},
      {name:"UTF-16 reference",found:has("src/source/utf16.odin"),path:"src/source/utf16.odin",detail:"Reference source mapper, not the complete source pipeline"},
      {name:"Scanner",found:under("src/scanner/")||under("src/lexer/"),path:null,detail:"Dedicated scanner source path"},
      {name:"Parser",found:under("src/parser/")||under("src/syntax/"),path:null,detail:"Dedicated parser source path"},
      {name:"Binder / modules",found:under("src/binder/")||under("src/modules/"),path:null,detail:"Dedicated symbol/module source path"},
      {name:"Type checker",found:under("src/checker/")||under("src/types/"),path:null,detail:"Dedicated checker source path"}
    ]
  };
}
export function latestMainWorkflow(runs, sha, name="Bootstrap CI") {
  if (!Array.isArray(runs) || typeof sha!=="string") return null;
  return runs.filter(run=>run?.name===name && run.head_sha===sha)
    .sort((a,b)=>Date.parse(b.created_at||0)-Date.parse(a.created_at||0))[0]||null;
}
export function workflowOutcome(run) {
  if (!run) return {label:"NOT RUN",tone:"neutral"};
  if (run.status!=="completed") return {label:"RUNNING",tone:"inprogress"};
  const result=run.conclusion;
  if (result==="success") return {label:"PASS",tone:"good"};
  if (result==="failure"||result==="timed_out"||result==="action_required") return {label:"FAIL",tone:"warning"};
  return {label:(result||"UNKNOWN").replaceAll("_"," ").toUpperCase(),tone:"neutral"};
}


// Public conformance data must come from a version-scoped, traceable
// tsodin-vs-upstream test run. TS CLI acceptance is NOT conformance parity.
export function validateConformanceReport(report) {
  if (!report || typeof report !== "object" || report.schemaVersion !== 1 ||
      report.project !== "tsodin" || report.source !== "Microsoft TypeScript compiler/conformance tests" ||
      report.authority !== "https://github.com/microsoft/TypeScript" ||
      !/^[a-z][a-z0-9-]+$/.test(report.profile || "") ||
      !/^\d+\.\d+\.\d+$/.test(report.typescriptVersion || "") ||
      !/^[0-9a-f]{40}$/.test(report.upstreamRevision || "")) {
    throw new TypeError("Invalid conformance evidence identity");
  }
  if (report.status === "not_run") {
    if (report.counts !== null || report.testedTsodinRevision !== null ||
        report.testedAt !== null || report.workflowRunUrl !== null)
      throw new TypeError("Unrun suite cannot contain measured results");
    return {status:"not_run",counts:null,rate:null,revision:null,version:report.typescriptVersion,profile:report.profile,upstreamRevision:report.upstreamRevision};
  }
  if (report.status !== "measured" ||
      !/^[0-9a-f]{40}$/.test(report.testedTsodinRevision || "") ||
      !Number.isFinite(Date.parse(report.testedAt)) ||
      !/^https:\/\/github\.com\/megaalive\/tsodin\/actions\/runs\/[0-9]+$/.test(report.workflowRunUrl || "")) {
    throw new TypeError("Measured conformance requires an exact commit and CI provenance");
  }
  const keys = ["passed","failed","unsupported","skipped_by_scope","not_run"];
  if (!report.counts || keys.some(k => !Number.isSafeInteger(report.counts[k]) || report.counts[k] < 0) ||
      Object.keys(report.counts).sort().join(",") !== [...keys].sort().join(",")) {
    throw new TypeError("Incomplete or invalid outcome counts");
  }
  const evaluated = report.counts.passed + report.counts.failed;
  if (evaluated === 0) throw new TypeError("No executed compatible conformance cases");
  return {status:"measured",counts:report.counts,rate:report.counts.passed / evaluated,revision:report.testedTsodinRevision,version:report.typescriptVersion,profile:report.profile,upstreamRevision:report.upstreamRevision,testedAt:report.testedAt,workflowRunUrl:report.workflowRunUrl};
}
