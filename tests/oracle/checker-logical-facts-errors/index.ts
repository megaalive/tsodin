// 😀 Short-circuit singleton facts must preserve five TS2367 diagnostics.
const a = true && false;
const badA = a === true;
const b = false || true;
const badB = b !== false;
const c = !!true && (!false || false);
const badC = c === false;
let gate: boolean = false;
gate = 2 < 3;
const alwaysFalse = gate && false;
const badD = alwaysFalse === true;
const alwaysTrue = gate || true;
const badE = alwaysTrue === false;
const wrong: string = alwaysTrue;
