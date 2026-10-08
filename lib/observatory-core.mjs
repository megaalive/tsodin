// Pure helpers shared by the static observatory and the CI smoke test.
// These are JavaScript visualization/reference helpers — not tsodin compiler code.
export function geometricMean(ratios) {
  if (!Array.isArray(ratios) || ratios.length === 0 ||
      ratios.some(value => !Number.isFinite(value) || value <= 0)) {
    throw new Error("Expected positive finite benchmark ratios");
  }
  return Math.exp(ratios.reduce((total, value) => total + Math.log(value), 0) / ratios.length);
}

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
    characters.push({
      character,
      point,
      byteStart: bytes,
      byteEnd: bytes + byteWidth,
      unitStart: units,
      unitEnd: units + unitWidth
    });
    bytes += byteWidth;
    units += unitWidth;
  }

  return { bytes, units, scalars: characters.length, characters, hasUnpairedSurrogate };
}

// A byte position inside a multibyte scalar is not a valid UTF-16 prefix
// boundary. Explicit null prevents accidentally rounding spans.
export function utf16AtByteOffset(source, position) {
  if (!Number.isInteger(position) || position < 0 || position > source.bytes) return null;
  if (position === 0) return 0;
  for (const character of source.characters) {
    if (position === character.byteEnd) return character.unitEnd;
    if (position > character.byteStart && position < character.byteEnd) return null;
  }
  return position === source.bytes ? source.units : null;
}

export function validateResearchArchive(archive) {
  if (archive?.schemaVersion !== 1 || archive?.evidenceClass !== "synthetic-hotpath-research") {
    throw new Error("Unknown benchmark archive schema");
  }
  const ids = new Set();
  if (!Array.isArray(archive.rounds) || archive.rounds.length !== 6) {
    throw new Error("Expected six archival rounds");
  }
  for (const round of archive.rounds) {
    if (!/^P[1-6]$/.test(round.id) || ids.has(round.id)) throw new Error("Invalid or duplicate round");
    ids.add(round.id);
    for (const kernel of ["K1", "K2", "K3"]) {
      if (!Number.isFinite(round.values?.[kernel]) || round.values[kernel] <= 0) {
        throw new Error("Missing or invalid ratio");
      }
    }
  }
  const p6 = archive.rounds.find(round => round.id === "P6");
  const calculated = geometricMean(Object.values(p6.values));
  if (Math.abs(calculated - archive.authoritativeSummary.geometricMean) > 0.000001) {
    throw new Error("P6 archived geometric mean mismatch");
  }
  if (archive.canonicalDecision !== "STOP_P1_AND_REVIEW" ||
      archive.authoritativeSummary.class !== "HOTPATH_P6_STRONG") {
    throw new Error("Research outcome drift");
  }
  return true;
}
