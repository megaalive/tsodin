// 😀 The mutating arm cannot leak singleton facts into its sibling.
let gate: boolean = false;
gate = 2 < 3;
let output: boolean = false;
if (gate) {
  output = gate && false;
  output = output === false;
  gate = 4 > 2;
  output = gate || true;
  output = output === true;
} else {
  output = gate || true;
  output = output === true;
}
output = gate && gate;
output = output === false;
