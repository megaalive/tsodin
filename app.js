import {inspectSource,utf16AtByteOffset,summarizeSourceTree,latestMainWorkflow,workflowOutcome} from "./lib/observatory-core.mjs";
const $ = id => document.getElementById(id);
const REPO = "https://github.com/megaalive/tsodin";
const API = "https://api.github.com/repos/megaalive/tsodin";
let refreshing = false;

function element(tag, className="", content="") {
  const x = document.createElement(tag);
  if (className) x.className = className;
  if (content !== "") x.textContent = content;
  return x;
}
function setStatus(elementRef,label,tone) {
  elementRef.className = "state-pill " + tone;
  elementRef.textContent = label;
}
function safeGitHubLink(url,fallback=REPO) {
  // API payload is untrusted. Restrict navigation to this public repository.
  return typeof url==="string" && url.startsWith(REPO+"/") ? url : fallback;
}
function shortSha(sha) {return typeof sha==="string" && /^[0-9a-f]{40}$/.test(sha) ? sha.slice(0,8) : "—";}
function humanTime(iso) {
  const date=new Date(iso);
  return Number.isNaN(date.getTime())?"Time unavailable":date.toLocaleString(undefined,{dateStyle:"medium",timeStyle:"short"});
}
async function githubJSON(path) {
  const controller=new AbortController();
  const timeout=setTimeout(()=>controller.abort(),9000);
  try {
    const response=await fetch(API+path,{
      signal:controller.signal,cache:"no-store",
      headers:{Accept:"application/vnd.github+json"}
    });
    if(!response.ok) throw new Error("GitHub HTTP "+response.status+" for "+path);
    return await response.json();
  } finally {clearTimeout(timeout);}
}
function unavailable(container,message) {
  container.replaceChildren(element("p","pending-text",message));
}
function displayCommits(commits) {
  if(!Array.isArray(commits) || !commits.length)throw new Error("No commit records");
  const sha=commits[0]?.sha;
  $("latest-sha").textContent=shortSha(sha);
  $("latest-sha").href=safeGitHubLink(commits[0]?.html_url,REPO+"/commits/main");
  $("latest-time").textContent=humanTime(commits[0]?.commit?.committer?.date||commits[0]?.commit?.author?.date);

  const rows=commits.slice(0,5).map(commit=>{
    const row=element("div","feed-row");
    const left=element("div","feed-primary");
    const anchor=element("a","commit-title",String(commit?.commit?.message||"No title").split("\n")[0].slice(0,150));
    anchor.href=safeGitHubLink(commit?.html_url,REPO+"/commits/main");
    anchor.target="_blank";anchor.rel="noopener noreferrer";
    const note=element("span","feed-note",shortSha(commit?.sha)+" · "+humanTime(commit?.commit?.committer?.date||commit?.commit?.author?.date));
    left.append(anchor,note);row.append(left,element("span","feed-arrow","↗"));
    return row;
  });
  $("commit-feed").replaceChildren(...rows);
  return sha;
}
function displayWorkflows(payload,headSha) {
  const runs=payload?.workflow_runs;
  if(!Array.isArray(runs))throw new Error("Missing workflow runs");
  const current=latestMainWorkflow(runs,headSha);
  const summary=workflowOutcome(current);
  $("main-ci").textContent=summary.label;
  $("main-ci").className="metric-ci status-"+summary.tone;
  $("main-ci-detail").textContent=current?
    "On main "+shortSha(current.head_sha)+" · "+humanTime(current.created_at):
    "No pinned CI run found for loaded HEAD";
  const seen=new Set();
  const chosen=runs.filter(run=>{
    if(!run?.name||seen.has(run.name))return false;
    seen.add(run.name);
    return true;
  }).slice(0,6);
  if(!chosen.length) {unavailable($("workflow-feed"),"No workflow runs were reported.");return;}
  $("workflow-feed").replaceChildren(...chosen.map(run=>{
    const row=element("div","feed-row");
    const left=element("div","feed-primary");
    const title=element("a","commit-title",String(run.name));
    title.href=safeGitHubLink(run.html_url,REPO+"/actions");
    title.target="_blank";title.rel="noopener noreferrer";
    const same=run.head_sha===headSha && typeof headSha==="string" && headSha.length===40;
    left.append(title,element("span","feed-note",shortSha(run.head_sha)+" · "+(same?"loaded HEAD":"earlier/other revision")+" · "+humanTime(run.created_at)));
    const badge=element("span");
    const outcome=workflowOutcome(run);
    setStatus(badge,outcome.label,outcome.tone);
    row.append(left,badge);
    return row;
  }));
}
function displayTree(payload){
  const summary=summarizeSourceTree(payload);
  $("odin-count").textContent=String(summary.odinFiles);
  $("oracle-count").textContent=String(summary.oracleProjects);
  $("source-proof").textContent=summary.odinFiles+" Odin files detected";
  setStatus($("tree-status"),"TREE READ","good");
  $("capability-list").replaceChildren(...summary.capabilities.map(item=>{
    const row=element("div","capability-item");
    const primary=element("div","capability-primary");
    const name=element("strong","",item.name);
    primary.append(name,element("small","",item.detail));
    const right=element("div","capability-state");
    const badge=element("span");
    setStatus(badge,item.found?"FILE FOUND":"NOT DETECTED",item.found?"good":"neutral");
    right.append(badge);
    if(item.found&&item.path){
      const link=element("a","tiny-link","Source ↗");
      link.href=REPO+"/blob/main/"+item.path;
      link.target="_blank";link.rel="noopener noreferrer";right.append(link);
    }
    row.append(primary,right);
    return row;
  }));
}
async function refreshLive(){
  if(refreshing)return;
  refreshing=true;
  const button=$("refresh-button");
  button.disabled=true;
  button.textContent="↻ Checking…";
  setStatus($("live-connection"),"CONNECTING","inprogress");
  const results=await Promise.allSettled([
    githubJSON("/commits?sha=main&per_page=5"),
    githubJSON("/actions/runs?branch=main&per_page=30"),
    githubJSON("/git/trees/main?recursive=1")
  ]);
  const errors=[];
  let sha=null,success=0;
  if(results[0].status==="fulfilled"){
    try {sha=displayCommits(results[0].value);success++;}
    catch(e){errors.push("commits");unavailable($("commit-feed"),"Commit data unavailable.");}
  }else {errors.push("commits");unavailable($("commit-feed"),"Commit data unavailable.");}
  if(results[1].status==="fulfilled"){
    try{displayWorkflows(results[1].value,sha);success++;}
    catch(e){errors.push("workflow runs");unavailable($("workflow-feed"),"Workflow status unavailable.");}
  }else {errors.push("workflow runs");unavailable($("workflow-feed"),"Workflow status unavailable.");}
  if(results[2].status==="fulfilled"){
    try{displayTree(results[2].value);success++;}
    catch(e){errors.push("source tree");setStatus($("tree-status"),"UNAVAILABLE","warning");unavailable($("capability-list"),"Cannot verify source tree. No implementation state inferred.");}
  }else {errors.push("source tree");setStatus($("tree-status"),"UNAVAILABLE","warning");unavailable($("capability-list"),"Cannot verify source tree. No implementation state inferred.");}
  // Don't leave results from a previous refresh appearing fresh after a failed request.
  if(errors.includes("commits")){
    $("latest-sha").textContent="—";$("latest-sha").href=REPO+"/commits/main";$("latest-time").textContent="Not available";
  }
  if(errors.includes("workflow runs") || (errors.includes("commits")&&results[1].status==="fulfilled")){
    $("main-ci").textContent="—";$("main-ci").className="metric-ci status-neutral";
    $("main-ci-detail").textContent="Cannot confirm CI for current HEAD";
  }
  if(errors.includes("source tree")){
    $("odin-count").textContent="—";$("oracle-count").textContent="—";$("source-proof").textContent="Not verifiable";
  }
  setStatus($("live-connection"),success===3?"SYNCED":success>0?"PARTIAL":"UNAVAILABLE",success===3?"good":success>0?"warning":"neutral");
  $("last-checked").textContent=humanTime(new Date().toISOString());
  const notice=$("load-errors");
  notice.hidden=errors.length===0;
  notice.textContent=errors.length?"Could not load "+errors.join(", ")+". GitHub API can be unavailable or rate-limited. Missing data are not treated as successful tests. Use Refresh to retry.":"";
  button.disabled=false;
  button.textContent="↻ Refresh data";
  refreshing=false;
}

const examples={
  emoji:'const emoji = "😀";\nconst count: number = "wrong";',
  ascii:'let total: number = 42;\nconsole.log(total);',
  crlf:'const emoji = "😀";\r\nconst next: boolean = 123;\r\n'
};
const input=$("source-input");
const slider=$("byte-offset");
let inspection=inspectSource(input.value);
function glyph(character){return ({" ":"␠","\n":"↵","\r":"␍","\t":"⇥"})[character]||character;}
function codePointLabel(point){return "U+"+point.toString(16).toUpperCase().padStart(4,"0");}
function updatePosition(){
  const byte=Number(slider.value);
  const units=utf16AtByteOffset(inspection,byte);
  $("byte-offset-label").textContent=byte+" / "+inspection.bytes;
  $("position-label").textContent=units===null?"Inside UTF-8 scalar":"UTF-16 prefix length";
  $("unit-at-offset").textContent=units===null?"—":String(units);
  let focus=inspection.characters.find(item=>byte>item.byteStart&&byte<=item.byteEnd);
  if(!focus && byte===0)focus=inspection.characters[0];
  $("character-sequence").querySelectorAll("button[data-byte-end]").forEach(b=>b.classList.toggle("selected",focus!==undefined&&Number(b.dataset.byteEnd)===focus.byteEnd));
  const note=$("boundary-note");
  if(inspection.hasUnpairedSurrogate)note.textContent="Caution: TextEncoder replaces lone surrogates. This visualization is not lossless for malformed UTF-16 input.";
  else if(units===null)note.textContent="Byte "+byte+" is inside a multibyte UTF-8 scalar; it is not a valid UTF-16 prefix boundary.";
  else if(focus)note.textContent=codePointLabel(focus.point)+" · bytes ["+focus.byteStart+", "+focus.byteEnd+") · UTF-16 ["+focus.unitStart+", "+focus.unitEnd+")";
  else note.textContent="Empty input. Both offsets are zero.";
}
function renderSource(jump=false){
  inspection=inspectSource(input.value);
  $("byte-total").textContent=String(inspection.bytes);
  $("unit-total").textContent=String(inspection.units);
  $("scalar-total").textContent=String(inspection.scalars);
  $("input-length").textContent=inspection.bytes+" B · "+inspection.units+" UTF-16";
  slider.max=String(inspection.bytes);
  let position=Math.min(Number(slider.value),inspection.bytes);
  if(jump){const first=inspection.characters.find(x=>x.byteEnd-x.byteStart!==x.unitEnd-x.unitStart);position=first?first.byteEnd:Math.min(inspection.bytes,1);}
  slider.value=String(position);
  const max=64;
  const chips=inspection.characters.slice(0,max).map(char=>{
    const b=element("button","",glyph(char.character));
    b.type="button";b.dataset.byteEnd=String(char.byteEnd);
    b.title=codePointLabel(char.point)+" · byte "+char.byteEnd;
    b.setAttribute("aria-label",codePointLabel(char.point)+", byte offset "+char.byteEnd+", UTF-16 units "+char.unitEnd);
    b.addEventListener("click",()=>{slider.value=String(char.byteEnd);updatePosition();});
    return b;
  });
  $("character-sequence").replaceChildren(...chips);
  $("sequence-limit").textContent=inspection.characters.length>max?"FIRST "+max+" / "+inspection.characters.length:inspection.characters.length+" POINTS";
  updatePosition();
}
input.addEventListener("input",()=>{
  document.querySelectorAll("[data-preset]").forEach(b=>{b.classList.remove("active");b.setAttribute("aria-pressed","false");});
  renderSource();
});
slider.addEventListener("input",updatePosition);
document.querySelectorAll("[data-preset]").forEach(button=>{
  button.addEventListener("click",()=>{
    input.value=examples[button.dataset.preset];
    document.querySelectorAll("[data-preset]").forEach(other=>{const active=other===button;other.classList.toggle("active",active);other.setAttribute("aria-pressed",String(active));});
    renderSource(true);
  });
});
$("refresh-button").addEventListener("click",refreshLive);
renderSource(true);
refreshLive();
