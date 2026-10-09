// Pinned TS7 mirror of the supported subset, not an official suite pass.
let flag: boolean = 1 < 2;
let value: number | string = 1;
if (flag) { value = 8; } else { value = "one"; }
let numeric: number = 0;
let textual: string = "";
if (typeof value === "number") { numeric = value; }
else { textual = value; }
if (typeof value !== "number") { textual = value; }
else { numeric = value; }

let mixed: number | string = 1;
if (flag) { mixed = 8; } else { mixed = "text"; }
if (typeof mixed === "number") {
  numeric = mixed;
  mixed = "changed";
  textual = mixed;
} else {
  textual = mixed;
  mixed = 4;
}
if (typeof mixed === "string") { textual = mixed; }
else { numeric = mixed; }
