// 😀 Cross-domain comparison with widened and computed operands.
const count: number = 1;
const label: string = "1";
const badNumberText = count === label;
let active: boolean = true;
const total = 2 + 2;
const badBooleanNumber = active !== total;
const badTextBoolean = label === active;
const badComputed = (1 + 2) === "3";
const badAssignment: string = count < total;
