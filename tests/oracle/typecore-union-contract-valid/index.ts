// TS7 oracle-only: Tsodin does not parse unions or typeof yet.
declare let value: number | string | boolean;
let target: number | string | boolean = value;
if (typeof value === "number") {
  const onlyNumber: number = value;
} else {
  const rest: string | boolean = value;
}
declare let truth: true | false;
const bool: boolean = truth;
