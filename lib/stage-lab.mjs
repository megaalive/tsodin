// Source → Token → postorder AST → single-file Symbols → bounded checker decisions.
// Visualization only: neither parser nor binder nor checker is re-run in JS.
const $=id=>document.getElementById(id);
const elt=(tag,cls="",text="")=>{
  const node=document.createElement(tag);
  if(cls)node.className=cls;
  node.textContent=text;
  return node;
};
const allowed=new Set(["implemented","partial","not_implemented"]);
const resultTypes=new Set(["complete","diagnostics","unsupported"]);
const byteUnits=(bytes,offset)=>{
  if(!Number.isSafeInteger(offset)||offset<0||offset>bytes.length)return null;
  try{return new TextDecoder("utf-8",{fatal:true}).decode(bytes.subarray(0,offset)).length;}
  catch{return null;}
};
export function validateStageDump(d){
  if(d?.schema!=="tsodin.dump/3"||typeof d?.source?.text!=="string")
    throw new Error("Unknown or missing Odin dump schema");
  const source=d.source.text,bytes=new TextEncoder().encode(source);
  if(d.source.bytes!==bytes.length||d.source.utf16!==source.length)
    throw new Error("Odin source dimensions do not match browser encoding");
  const stages=d.stages;
  if(!stages || !["tokens","ast","symbols","types"].every(k=>stages[k]))
    throw new Error("Missing required stage records");
  const span=(o,where)=>{
    if(!Array.isArray(o?.bytes)||o.bytes.length!==2||!Array.isArray(o?.utf16)||o.utf16.length!==2)
      throw new Error("Missing positions in "+where);
    const [a,b]=o.bytes;
    if(!Number.isSafeInteger(a)||!Number.isSafeInteger(b)||a>b||
       byteUnits(bytes,a)!==o.utf16[0]||byteUnits(bytes,b)!==o.utf16[1])
      throw new Error("Byte/UTF-16 mismatch in "+where);
  };
  for(const k of ["tokens","ast","symbols","types"]){
    const stage=stages[k];
    if(!allowed.has(stage.status)||!resultTypes.has(stage.outcome))
      throw new Error("Unknown stage status for "+k);
    if(!Array.isArray(stage.diagnostics))throw new Error("No diagnostics array in "+k);
    for(const diag of stage.diagnostics)span(diag,k+" diagnostic");
  }
  const tokens=stages.tokens.tokens,nodes=stages.ast.nodes,symbols=stages.symbols.symbols;
  if(!Array.isArray(tokens)||!Array.isArray(nodes)||!Array.isArray(symbols)||
     !Array.isArray(stages.symbols.references))
    throw new Error("Incomplete stage tables");
  for(const [i,t] of tokens.entries())span(t,"token "+i);
  for(const [i,n] of nodes.entries()){
    span(n,"node "+i);
    for(const child of [n.left,n.right])
      if(!Number.isSafeInteger(child)||(child!==-1&&(child<0||child>=i)))
        throw new Error("Invalid postorder child in node "+i);
    if(!Array.isArray(n.tokens)||n.tokens.length!==2)throw new Error("Missing token IDs in node "+i);
    if(n.tokens[0]!==-1 && (n.tokens[0]<0||n.tokens[1]<n.tokens[0]||
                              n.tokens[1]>=tokens.length))
      throw new Error("Invalid token range in node "+i);
  }
  const declarations=stages.ast.declarations,events=stages.ast.statements;
  if(!Array.isArray(declarations)||!Array.isArray(events))
    throw new Error("Missing original parser declaration or statement tables");
  const references=new Map();
  for(const ref of stages.symbols.references){
    if(!Number.isSafeInteger(ref.node_index)||ref.node_index<0||ref.node_index>=nodes.length||
       !Number.isSafeInteger(ref.symbol_index)||ref.symbol_index<0||ref.symbol_index>=symbols.length||
       references.has(ref.node_index))
      throw new Error("Invalid or repeated binding reference");
    references.set(ref.node_index,symbols[ref.symbol_index]);
  }
  // The browser verifies provenance, never re-evaluates source expressions.
  // Only true statement RHS roots can carry the checker v2 relation records.
  const decisionEvents=new Map();
  for(const event of events){
    if(event.kind!=="Declaration"&&event.kind!=="Assignment")continue;
    if(!Number.isSafeInteger(event.expression)||event.expression<0)continue;
    if(event.expression>=nodes.length||decisionEvents.has(event.expression))
      throw new Error("Invalid or repeated statement expression root");
    decisionEvents.set(event.expression,event);
  }
  const annotationType={Number:"Number",String:"Text",Boolean:"Boolean"};
  const relations=stages.types.relations;
  if(!Array.isArray(relations)||!["failures","all"].includes(stages.types.trace_mode)||
     stages.types.relations_status!=="partial")
    throw new Error("Missing bounded type-relation contract");
  let previousNode=-1;
  for(const [i,rel] of relations.entries()){
    span(rel,"relation "+i);
    if(!["Number","Text","Boolean"].includes(rel.source)||
       !["Number","Text","Boolean"].includes(rel.target)||
       !["Variable","Assignment"].includes(rel.relation_kind)||
       typeof rel.result!=="boolean"||
       !Number.isInteger(rel.node_index)||rel.node_index<0||rel.node_index>=nodes.length||
       !Number.isInteger(rel.declaration_index)||rel.declaration_index<0||
       rel.declaration_index>=declarations.length)
      throw new Error("Invalid relation node index, declaration index or type");
    if(rel.node_index<=previousNode)
      throw new Error("Relations must be unique and in expression source order");
    previousNode=rel.node_index;
    if(rel.result!==(rel.source===rel.target))
      throw new Error("Inconsistent primitive compatibility decision");
    if(stages.types.trace_mode==="failures"&&rel.result)
      throw new Error("Unexpected successful relation in failure-only trace");
    const node=nodes[rel.node_index];
    if(node.bytes[0]!==rel.bytes[0]||node.bytes[1]!==rel.bytes[1])
      throw new Error("Relation span does not match original RHS node");
    const event=decisionEvents.get(rel.node_index);
    const expectedKind=rel.relation_kind==="Variable"?"Declaration":"Assignment";
    if(!event||event.kind!==expectedKind)
      throw new Error("Relation is not backed by a matching statement RHS");
    const decl=declarations[rel.declaration_index];
    if(rel.relation_kind==="Variable"){
      if(event.declaration_index!==rel.declaration_index||
         decl.initializer!==rel.node_index||
         annotationType[decl.type_kind]!==rel.target)
        throw new Error("Variable relation is not backed by its annotated declaration");
    }else{
      const target=nodes[event.target_node];
      const bound=references.get(event.target_node);
      if(!target||target.kind!=="Name"||!bound||bound.kind!=="Let"||
         bound.declaration!==rel.declaration_index)
        throw new Error("Assignment relation target disagrees with binder");
      // Inferred lets have no annotation; the browser must not infer a type.
      const annotated=annotationType[decl.type_kind];
      if(annotated&&annotated!==rel.target)
        throw new Error("Assignment relation disagrees with target annotation");
    }
  }
  // V3 comparison records are only checked for original Odin provenance.
  // Never infer literal identities, type flow or runtime equality in the UI.
  const comparisons=stages.types.comparisons;
  const proofs=new Set(["Disjoint_Domains","Disjoint_Literals",
    "Same_Symbol","Same_Literal","Widened_Domain"]);
  if(stages.types.comparisons_status!=="partial"||!Array.isArray(comparisons))
    throw new Error("Missing bounded comparison evidence contract");
  let lastComparison=-1;
  for(const [i,c] of comparisons.entries()){
    span(c,"comparison "+i);
    const n=nodes[c.node_index];
    if(!Number.isSafeInteger(c.node_index)||c.node_index<0||!n||
       n.kind!=="Binary"||n.operator!==c.operator||
       !["Equals_Equals_Equals","Exclamation_Equals_Equals"].includes(c.operator)||
       !Number.isSafeInteger(n.left)||!Number.isSafeInteger(n.right)||
       n.left<0||n.right<0||n.left>=c.node_index||n.right>=c.node_index||
       !["Number","Text","Boolean"].includes(c.left)||
       !["Number","Text","Boolean"].includes(c.right)||
       !proofs.has(c.proof)||typeof c.overlaps!=="boolean")
      throw new Error("Invalid comparison provenance or proof");
    if(c.node_index<=lastComparison)
      throw new Error("Comparison evidence must be unique and in source order");
    lastComparison=c.node_index;
    if(n.bytes[0]!==c.bytes[0]||n.bytes[1]!==c.bytes[1])
      throw new Error("Comparison span must match its original equality node");
    const disjoint=c.proof==="Disjoint_Domains"||c.proof==="Disjoint_Literals";
    if(c.overlaps===disjoint||
       (c.proof==="Disjoint_Domains")!==(c.left!==c.right)||
       (c.proof!=="Disjoint_Domains"&&c.left!==c.right))
      throw new Error("Inconsistent comparison proof category or operand domains");
    if(stages.types.trace_mode==="failures"&&c.overlaps)
      throw new Error("Unexpected overlap proof in failure-only trace");
  }
  return {bytes:bytes.length,utf16:source.length,tokens:tokens.length,nodes:nodes.length};
}

const STAGES=[["tokens","Token"],["ast","AST"],["symbols","Symbol"],["types","Type"]];
const INTERNAL_CHECK_ISSUES={10:"Assignment_Type_Mismatch",11:"Disjoint_Literal_Comparison",12:"Disjoint_Primitive_Domains"};
const INTERNAL_TYPES={Number:"number",Text:"string",Boolean:"boolean"};
const plainSpan=o=>`byte [${o.bytes.join(", ")}) · UTF-16 [${o.utf16.join(", ")})`;
function statusClass(x){return x==="complete"?"ok":x==="unsupported"?"blocked":"partial";}
function tokenCategory(k){
  if(/^(Let|Const|Var|If_Keyword|Else_Keyword|.*_Keyword)$/.test(k))return "keyword";
  if(k==="Identifier")return "identifier";
  if(k==="Integer_Literal")return "number";
  if(k==="String_Literal")return "string";
  if(k==="Invalid")return "unknown";
  return "operator";
}
const detail=(heading,lines)=>{
  const place=$("lab-detail");
  place.replaceChildren(elt("strong","",heading));
  for(const line of lines)place.append(elt("span","lab-detail-line",line));
};

function render(d){
  const {source,stages}=d;
  const tokens=stages.tokens.tokens,nodes=stages.ast.nodes,symbols=stages.symbols.symbols;
  const sourceBox=$("lab-source"),tokenBox=$("lab-tokens"),treeBox=$("lab-tree");
  $("lab-file").textContent=source.name;
  $("lab-metrics").textContent=source.bytes+" bytes · "+source.utf16+" UTF-16 units · "+nodes.length+" expression nodes";
  $("lab-encoding").textContent="Span verified against browser UTF-8/UTF-16";
  $("lab-encoding").className="lab-trust ok";
  $("lab-stages").replaceChildren(...STAGES.map(([k,label])=>{
    const x=stages[k],chip=elt("span","lab-step "+statusClass(x.outcome),label+" · "+x.status+" · "+x.outcome);
    chip.title="Implementation coverage and outcome of this exact file are distinct";
    return chip;
  }));
  let pos=0;
  sourceBox.replaceChildren();tokenBox.replaceChildren();
  for(const [i,t] of tokens.entries()){
    if(t.kind==="End_Of_File")continue;
    if(t.bytes[0]<pos||t.bytes[1]<t.bytes[0])
      throw new Error("Overlapping or unordered tokens");
    const bytes=new TextEncoder().encode(source.text);
    const gap=new TextDecoder().decode(bytes.subarray(pos,t.bytes[0]));
    const text=new TextDecoder().decode(bytes.subarray(t.bytes[0],t.bytes[1]));
    sourceBox.append(document.createTextNode(gap));
    const word=elt("button","lab-word "+tokenCategory(t.kind),text);
    word.type="button";word.dataset.token=String(i);
    word.title=t.kind;sourceBox.append(word);
    const cap=elt("button","lab-token "+tokenCategory(t.kind),text.length>28?text.slice(0,27)+"…":text);
    cap.type="button";cap.dataset.token=String(i);
    cap.append(elt("small","",t.kind));
    tokenBox.append(cap);
    pos=t.bytes[1];
  }
  const entire=new TextEncoder().encode(source.text);
  sourceBox.append(document.createTextNode(new TextDecoder().decode(entire.subarray(pos))));
  function highlight(ids){
    const chosen=new Set(ids);
    for(const element of document.querySelectorAll("#lab [data-token]"))
      element.classList.toggle("is-selected",chosen.has(Number(element.dataset.token)));
  }
  function selectToken(i){
    const t=tokens[i];if(!t)return;
    highlight([i]);
    detail(t.kind,[plainSpan(t),"Text is sliced from the actual source; it is not duplicated in the Odin token table."]);
  }
  for(const area of [sourceBox,tokenBox]){
    area.onclick=e=>{
      const button=e.target.closest("[data-token]");
      if(button&&area.contains(button))selectToken(Number(button.dataset.token));
    };
  }
  treeBox.replaceChildren();
  // Statement roots are real parser events; the expression children are postorder indices.
  const refs=new Map(stages.symbols.references.map(r=>[r.node_index,r.symbol_index]));
  function treeNode(i,depth){
    if(!Number.isSafeInteger(i)||i<0||i>=nodes.length||depth>64)return null;
    const n=nodes[i],row=elt("li","lab-node");
    const btn=elt("button","lab-node-control",`#${i} ${n.kind}`);
    btn.type="button";
    btn.dataset.node=String(i);
    row.append(btn);
    const sym=refs.get(i);
    if(sym!==undefined)row.append(elt("small","lab-node-info","→ symbol #"+sym));
    const children=[n.left,n.right].filter(c=>c!==-1);
    if(children.length){
      const ul=elt("ul","lab-branch");
      for(const child of children){const item=treeNode(child,depth+1);if(item)ul.append(item);}
      row.append(ul);
    }
    return row;
  }
  const events=stages.ast.statements||[];
  for(const [i,event] of events.entries()){
    const row=elt("div","lab-event");
    row.append(elt("div","lab-event-name",`event #${i} · ${event.kind}`));
    const root=Number(event.expression);
    if(Number.isInteger(root)&&root>=0&&root<nodes.length){
      const ul=elt("ul","lab-branch");
      const n=treeNode(root,0);if(n)ul.append(n);
      row.append(ul);
    }
    treeBox.append(row);
  }
  if(!events.length)treeBox.append(elt("p","lab-muted","No complete parser statement events for this source."));
  treeBox.onclick=e=>{
    const button=e.target.closest("[data-node]");
    if(!button)return;
    const id=Number(button.dataset.node),n=nodes[id];
    highlight(n.tokens[0]>=0?Array.from({length:n.tokens[1]-n.tokens[0]+1},(_,j)=>n.tokens[0]+j):[]);
    detail("Expression node #"+id+" · "+n.kind,[
      plainSpan(n),`left=${n.left}, right=${n.right} (postorder arena indices)`,
      refs.has(id)?`Bound to symbol #${refs.get(id)}`:"No binder reference on this expression node",
    ]);
  };
  const symBox=$("lab-symbols");symBox.replaceChildren();
  symBox.append(elt("p","lab-muted","One file-scope binder · nested lookup path: "+stages.symbols.lookup_status));
  for(const [i,s] of symbols.entries()){
    const button=elt("button","lab-symbol",`#${i} ${s.kind} ${s.name}`);
    button.type="button";
    button.onclick=()=>{
      const related=stages.symbols.references.filter(r=>r.symbol_index===i);
      const ids=related.flatMap(r=>{
        const n=nodes[r.node_index];return n?.tokens?.[0]>=0?[n.tokens[0]]:[];
      });
      highlight(ids);
      detail("Symbol #"+i+" · "+s.name,[
        `Declaration table index: ${s.declaration}`,
        `Recorded references: ${related.length}`,
        "Single-file scope only; no hierarchical lookup trail recorded",
      ]);
    };
    symBox.append(button);
  }
  if(!symbols.length)symBox.append(elt("p","lab-muted","No resolved symbols in this report."));
  const issues=$("lab-issues");issues.replaceChildren();
  const any=[];
  for(const [key,label] of STAGES){
    const stage=stages[key];
    for(const issue of stage.diagnostics){
      const internal=key==="types"?INTERNAL_CHECK_ISSUES[issue.issue_id]:undefined;
      any.push(elt("p","lab-issue",
        label+" · "+(internal||"internal issue")+" #"+issue.issue_id+" · "+plainSpan(issue)));
    }
  }
  issues.append(...(any.length?any:[elt("p","lab-muted","No recorded internal diagnostics in this source.")]));
  issues.append(elt("h3","","Actual type decisions · "+stages.types.trace_mode+" trace"));
  const relations=stages.types.relations;
  if(!relations.length)issues.append(elt("p","lab-muted",
    "No primitive variable/assignment decisions were recorded for this example."));
  for(const [i,relation] of relations.entries()){
    const src=INTERNAL_TYPES[relation.source],target=INTERNAL_TYPES[relation.target];
    const context=relation.relation_kind==="Variable"?"variable initializer":"reassignment";
    const answer=relation.result?"YES":"NO";
    const button=elt("button","lab-relation "+(relation.result?"ok":"blocked"),
      answer+" · Can "+src+" be assigned to "+target+"? ("+context+")");
    button.type="button";
    button.title="Actual decision recorded by Odin checker; select to inspect the RHS source.";
    button.onclick=()=>{
      const node=nodes[relation.node_index];
      highlight(node.tokens[0]>=0?Array.from(
        {length:node.tokens[1]-node.tokens[0]+1},(_,j)=>node.tokens[0]+j):[]);
      detail("Recorded checker decision #"+i+" · "+answer,[
        "Source: "+src+" · Target: "+target,
        "Context: "+context+" · declaration #"+relation.declaration_index,
        "RHS expression node #"+relation.node_index+" · "+plainSpan(relation),
        "Evidence: tsodin.checker.Type_Relation; no browser type inference",
      ]);
    };
    issues.append(button);
  }
  issues.append(elt("h3","","Proven equality operand overlap · "+stages.types.trace_mode+" trace"));
  const proofNames={
    Disjoint_Domains:"different primitive domains",
    Disjoint_Literals:"different literal values",
    Same_Symbol:"same resolved symbol",
    Same_Literal:"same literal value",
    Widened_Domain:"widened primitive domain",
  };
  const comparisons=stages.types.comparisons;
  if(!comparisons.length)issues.append(elt("p","lab-muted",
    "No proven strict-equality operand overlap/disjointness for this example."));
  for(const [i,c] of comparisons.entries()){
    const left=INTERNAL_TYPES[c.left],right=INTERNAL_TYPES[c.right];
    const answer=c.overlaps?"OVERLAP POSSIBLE":"DISJOINT";
    const sign=c.operator==="Equals_Equals_Equals"?"===":"!==";
    const button=elt("button","lab-relation "+(c.overlaps?"ok":"blocked"),
      answer+" · "+left+" "+sign+" "+right+" · "+proofNames[c.proof]);
    button.type="button";
    button.title="Proven operand-domain relation, never the evaluated Boolean result.";
    button.onclick=()=>{
      const node=nodes[c.node_index];
      highlight(node.tokens[0]>=0?Array.from(
        {length:node.tokens[1]-node.tokens[0]+1},(_,j)=>node.tokens[0]+j):[]);
      detail("Odin comparison proof #"+i+" · "+answer,[
        "Operands: "+left+" "+sign+" "+right+" · proof: "+proofNames[c.proof],
        "Binary expression node #"+c.node_index+" · "+plainSpan(c),
        "OVERLAP POSSIBLE does not mean the expression evaluates to true.",
        "Evidence: tsodin.checker.Comparison_Evidence; no browser inference.",
      ]);
    };
    issues.append(button);
  }
  issues.append(elt("p","lab-muted",
    "Partial primitive evidence only; equality proofs describe possible overlap or disjointness, "+
    "not runtime truth or TypeScript parity. Node types: "+stages.types.node_types_status+
    " · broader type relations: not implemented. Internal diagnostics are not TS codes."));
  $("lab-json").textContent=JSON.stringify(d,null,2);
  detail("Inspect an actual Odin fact",["Tap a source token, token capsule, expression node or symbol."]);
}

async function fetchJSON(path){
  const response=await fetch(path,{cache:"no-store"});
  if(!response.ok)throw new Error("HTTP "+response.status);
  return response.json();
}
export async function initStageLab(){
  const status=$("lab-load"),chooser=$("lab-example"),base="./docs/traces/";
  try{
    const index=await fetchJSON(base+"index.json");
    if(index?.schema!=="tsodin.gallery/1"||!Array.isArray(index.examples)||!index.examples.length)
      throw new Error("Unknown gallery manifest");
    const options=[];
    for(const e of index.examples){
      if(!/^[a-z0-9-]+$/.test(e?.id)||e.href!==e.id+".json"||typeof e.title!=="string")
        throw new Error("Invalid gallery entry");
      const option=elt("option","",e.title);
      option.value=e.id;options.push(option);
    }
    chooser.replaceChildren(...options);
    const entries=new Map(index.examples.map(x=>[x.id,x]));
    let requested=0;
    const load=async()=>{
      const id=chooser.value,record=entries.get(id),ticket=++requested;
      if(!record)return;
      status.textContent="Reading published Odin trace…";
      status.className="lab-trust";
      try{
        const dump=await fetchJSON(base+record.href);
        validateStageDump(dump);
        if(ticket!==requested)return;
        render(dump);
        status.textContent="Loaded · "+record.title;
        status.className="lab-trust ok";
      }catch(err){
        if(ticket!==requested)return;
        status.textContent="Trace unavailable or invalid: "+err.message;
        status.className="lab-trust blocked";
        for(const id of ["lab-source","lab-tokens","lab-tree","lab-symbols","lab-issues","lab-stages"])
          $(id).replaceChildren();
        $("lab-json").textContent="";
        $("lab-file").textContent="—";
        $("lab-metrics").textContent="—";
        detail("Trace unavailable",["No previous example has been treated as current."]);
        $("lab-encoding").textContent="Not verified";
        $("lab-encoding").className="lab-trust blocked";
      }
    };
    chooser.addEventListener("change",load);
    await load();
  }catch(err){
    status.textContent="Gallery unavailable: "+err.message;
    status.className="lab-trust blocked";
    chooser.disabled=true;
  }
}
