// Conceptual compiler orbit: browser-only presentation, never a compiler runtime.
// No external dependencies, network polling, or invented implementation state.
export const ORBIT_STAGES = Object.freeze([
  Object.freeze({key:"source",title:"Source & UTF-16",description:"Versioned source and byte-to-UTF-16 position mapping.",file:"src/source/utf16.odin"}),
  Object.freeze({key:"symbols",title:"Symbols & bindings",description:"Declared names, references and symbol resolution.",file:"src/binder/binder.odin"}),
  Object.freeze({key:"types",title:"Primitive type flow",description:"Bounded semantic checks and fail-closed conditional narrowing.",file:"src/checker/primitive.odin"})
]);
export function nextOrbitStage(index) {
  return (Number.isInteger(index) && index>=0 && index<ORBIT_STAGES.length ? index+1 : 0)%ORBIT_STAGES.length;
}
export function orbitStage(key) {
  return ORBIT_STAGES.find(stage=>stage.key===key)??null;
}
export function initArchitectureOrbit(root) {
  if (!root) return;
  const doc=root.ownerDocument;
  const win=doc.defaultView;
  const media=win.matchMedia("(prefers-reduced-motion: reduce)");
  const buttons=[...root.querySelectorAll("[data-orbit-stage]")];
  const pause=root.querySelector("#orbit-motion-toggle");
  const title=root.querySelector("#orbit-stage-name");
  const desc=root.querySelector("#orbit-stage-description");
  const link=root.querySelector("#orbit-stage-link");
  const label=root.querySelector(".orbit-inspector-kicker");
  let current=0;
  let manualPause=false;
  let interacting=false;
  let interval=null;
  const selectedPanel=root.closest("[data-panel]");
  function paint() {
    const stage=ORBIT_STAGES[current];
    root.dataset.stage=stage.key;
    for (const b of buttons) {
      const active=b.dataset.orbitStage===stage.key;
      b.classList.toggle("is-active",active);
      b.setAttribute("aria-pressed",String(active));
    }
    title.textContent=stage.title;
    desc.textContent=stage.description;
    label.textContent="SOURCE FILE · NOT COMPLETION STATUS";
    link.href="https://github.com/megaalive/tsodin/blob/main/"+stage.file;
    link.setAttribute("aria-label","Inspect "+stage.title+" source file");
  }
  function active() {
    return !manualPause && !media.matches && !doc.hidden &&
      !(selectedPanel?.hidden) && !interacting;
  }
  function sync() {
    if(interval!==null) {win.clearInterval(interval);interval=null;}
    const running=active();
    // Pointer/focus pauses stage cycling, not the visual energy flow.
    // Especially on touch browsers, synthetic mouseenter can linger.
    root.classList.toggle("orbit-paused",
      manualPause || media.matches || doc.hidden || !!selectedPanel?.hidden);
    pause.disabled=media.matches;
    pause.setAttribute("aria-pressed",String(manualPause));
    pause.textContent=media.matches?"Motion reduced":manualPause?"▶ Resume motion":"Ⅱ Pause motion";
    if(running) interval=win.setInterval(()=>{current=nextOrbitStage(current);paint();},4800);
  }
  for(const button of buttons) {
    button.addEventListener("click",()=>{
      const chosen=ORBIT_STAGES.findIndex(stage=>stage.key===button.dataset.orbitStage);
      if(chosen<0)return;
      current=chosen;
      paint();
      sync();
    });
  }
  pause.addEventListener("click",()=>{manualPause=!manualPause;sync();});
  root.addEventListener("mouseenter",()=>{interacting=true;sync();});
  root.addEventListener("mouseleave",()=>{interacting=false;sync();});
  root.addEventListener("focusin",()=>{interacting=true;sync();});
  root.addEventListener("focusout",()=>{
    // Wait until focus moves to its next element before deciding.
    win.queueMicrotask(()=>{
      interacting=root.contains(doc.activeElement);
      sync();
    });
  });
  doc.addEventListener("visibilitychange",sync);
  doc.addEventListener("tsodin:view-change",sync);
  media.addEventListener("change",sync);
  paint();
  sync();
}
