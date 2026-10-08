import { geometricMean, inspectSource, utf16AtByteOffset, validateResearchArchive } from "./lib/observatory-core.mjs";

const $ = id => document.getElementById(id);
const formatRatio = value => value.toFixed(4) + "×";
const roundSelect = $("round-select");
const timeline = $("timeline");
let archive = null;
let chosenRound = "P6";

function node(tag, className = "", text = "") {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== "") element.textContent = text;
  return element;
}

function selectRound(id) {
  const round = archive?.rounds.find(item => item.id === id);
  if (!round) return;
  chosenRound = id;
  $("round-label").textContent = round.id;
  const status = $("round-status");
  status.textContent = round.status;
  status.className = "state-pill " + round.statusTone;

  const chart = $("bar-chart");
  const chartRows = archive.kernels.map(kernel => {
    const ratio = round.values[kernel.id];
    const row = node("div", "bar-group");
    const title = node("div", "bar-title");
    const label = node("span", "", kernel.id);
    label.append(node("small", "", kernel.title));
    const number = node("strong", ratio > 1 ? "over" : "", formatRatio(ratio));
    title.append(label, number);
    const track = node("div", "bar-track");
    const value = node("div", "bar-value" + (ratio > 1 ? " over" : ""));
    value.style.width = Math.min(100, ratio / 1.2 * 100).toFixed(3) + "%";
    const rust = node("span", "rust-line");
    track.append(value, rust);
    row.append(title, track);
    return row;
  });
  chart.replaceChildren(...chartRows);

  const entries = Object.entries(round.values);
  const [worstKernel, worstValue] = entries.reduce((worst, next) => next[1] > worst[1] ? next : worst);
  $("geomean").textContent = formatRatio(geometricMean(entries.map(([, v]) => v))) + (id === "P3" ? "†" : "");
  $("worst-kernel").textContent = worstKernel + " · " + formatRatio(worstValue);
  $("round-qualification").textContent = round.resultNote;
  roundSelect.querySelectorAll("button").forEach(button => {
    const selected = button.dataset.round === id;
    button.classList.toggle("active", selected);
    button.setAttribute("aria-pressed", String(selected));
  });

  $("experiment-index").textContent = "ROUND " + String(round.ordinal).padStart(2, "0") + " / 06";
  $("experiment-title").textContent = round.title;
  $("experiment-description").textContent = round.subtitle;
  $("experiment-decision").textContent = round.decision;
  $("experiment-link").href = round.url;
  timeline.querySelectorAll("button").forEach(button => {
    const selected = button.dataset.timeline === id;
    button.classList.toggle("active", selected);
    button.setAttribute("aria-pressed", String(selected));
  });
}

function buildTimeline() {
  const labels = {
    P1:"Raw table access",
    P2:"Compact state hypothesis",
    P3:"Branch-light cache",
    P4:"u32 specialization",
    P5:"Unchecked input view",
    P6:"Skip redundant zero-fill"
  };
  const items = archive.rounds.slice().reverse().map(round => {
    const button = node("button", "timeline-item");
    button.type = "button";
    button.dataset.timeline = round.id;
    button.setAttribute("aria-pressed", "false");
    button.append(node("span", "timeline-step", String(round.ordinal).padStart(2, "0")));
    const body = node("span", "timeline-text");
    body.append(node("strong", "", round.id + " / " + labels[round.id]));
    body.append(node("small", "", round.status));
    button.append(body, node("span", "", "↗"));
    button.addEventListener("click", () => selectRound(round.id));
    return button;
  });
  timeline.replaceChildren(...items);
}

roundSelect.addEventListener("click", event => {
  const button = event.target.closest("button[data-round]");
  if (button && roundSelect.contains(button)) selectRound(button.dataset.round);
});

async function initializeArchive() {
  try {
    const response = await fetch("./data/observatory.json", { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    const result = await response.json();
    validateResearchArchive(result);
    archive = result;
    buildTimeline();
    selectRound(chosenRound);
  } catch (error) {
    // Static P6 values remain readable when data is temporarily unavailable.
    $("round-qualification").textContent =
      "The interactive archive could not be loaded. The static P6 snapshot is shown; use the methodology link for the original evidence.";
    roundSelect.querySelectorAll("button:not([data-round='P6'])").forEach(button => {
      button.disabled = true;
      button.title = "Archive data unavailable";
    });
    console.error("Observatory archive unavailable:", error);
  }
}

const examples = {
  emoji: 'const emoji = "😀";\nconst count: number = "wrong";',
  ascii: 'let total: number = 42;\nconsole.log(total);',
  crlf: 'const emoji = "😀"; const count: number = "wrong";\r\nconst next: boolean = 123;\r\n'
};
const input = $("source-input");
const slider = $("byte-offset");
let inspection = inspectSource(input.value);

function glyph(character) {
  switch (character) {
    case " ": return "␠";
    case "\n": return "↵";
    case "\r": return "␍";
    case "\t": return "⇥";
    default: return character;
  }
}
function codePointLabel(point) {
  return "U+" + point.toString(16).toUpperCase().padStart(4, "0");
}

function updatePosition() {
  const byte = Number(slider.value);
  const units = utf16AtByteOffset(inspection, byte);
  $("byte-offset-label").textContent = byte + " / " + inspection.bytes;
  $("position-label").textContent = units === null ? "Inside UTF-8 scalar" : "UTF-16 prefix length";
  $("unit-at-offset").textContent = units === null ? "—" : String(units);

  let focused = inspection.characters.find(character => byte > character.byteStart && byte <= character.byteEnd);
  if (!focused && byte === 0) focused = inspection.characters[0];
  const children = $("character-sequence").querySelectorAll("button[data-byte-end]");
  children.forEach(button => {
    button.classList.toggle("selected", focused !== undefined && Number(button.dataset.byteEnd) === focused.byteEnd);
  });

  const note = $("boundary-note");
  if (inspection.hasUnpairedSurrogate) {
    note.textContent = "CAUTION: The browser replaces unpaired UTF-16 surrogates when encoding UTF-8; this visualization is not lossless for that input.";
  } else if (units === null) {
    note.textContent = "Byte " + byte + " is inside a multibyte UTF-8 code point. No valid UTF-16 prefix boundary exists at this position.";
  } else if (focused) {
    note.textContent = codePointLabel(focused.point) + " · byte span [" + focused.byteStart + ", " + focused.byteEnd + ") · UTF-16 span [" + focused.unitStart + ", " + focused.unitEnd + ").";
  } else {
    note.textContent = "Empty source: both byte and UTF-16 offsets are zero.";
  }
}

function renderSource(preferUnicode = false) {
  inspection = inspectSource(input.value);
  $("byte-total").textContent = String(inspection.bytes);
  $("unit-total").textContent = String(inspection.units);
  $("scalar-total").textContent = String(inspection.scalars);
  $("input-length").textContent = inspection.bytes + " B · " + inspection.units + " UTF-16";
  slider.max = String(inspection.bytes);
  let position = Math.min(Number(slider.value), inspection.bytes);
  if (preferUnicode) {
    const first = inspection.characters.find(item => item.unitEnd - item.unitStart !== item.byteEnd - item.byteStart);
    position = first ? first.byteEnd : Math.min(inspection.bytes, 1);
  }
  slider.value = String(position);

  const maxChips = 64;
  const visible = inspection.characters.slice(0, maxChips);
  const buttons = visible.map(character => {
    const button = node("button", "", glyph(character.character));
    button.type = "button";
    button.dataset.byteEnd = String(character.byteEnd);
    button.title = codePointLabel(character.point) + " · click for byte offset " + character.byteEnd;
    button.setAttribute("aria-label", codePointLabel(character.point) + ", UTF-8 byte offset " + character.byteEnd + ", UTF-16 units " + character.unitEnd);
    button.addEventListener("click", () => {
      slider.value = String(character.byteEnd);
      updatePosition();
    });
    return button;
  });
  $("character-sequence").replaceChildren(...buttons);
  $("sequence-limit").textContent = inspection.characters.length > maxChips ?
    "FIRST " + maxChips + " OF " + inspection.characters.length : String(inspection.characters.length) + " POINTS";
  updatePosition();
}

input.addEventListener("input", () => {
  document.querySelectorAll("[data-preset]").forEach(button => {
    button.classList.remove("active");
    button.setAttribute("aria-pressed", "false");
  });
  renderSource(false);
});
slider.addEventListener("input", updatePosition);
document.querySelectorAll("[data-preset]").forEach(button => {
  button.addEventListener("click", () => {
    input.value = examples[button.dataset.preset];
    document.querySelectorAll("[data-preset]").forEach(item => {
      const active = item === button;
      item.classList.toggle("active", active);
      item.setAttribute("aria-pressed", String(active));
    });
    renderSource(true);
  });
});

renderSource(true);
initializeArchive();
