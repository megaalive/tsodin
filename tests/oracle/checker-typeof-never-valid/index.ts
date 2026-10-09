// Independent TS7 source-to-source witness for impossible typeof arms.
let value: number | string = 1;
let numeric: number = 0;
if (typeof value === "string") { numeric = 1; }
else { numeric = 2; }
const stillNumber: number = value;
if (typeof value !== "number") { numeric = 3; }
else { numeric = 4; }
const sameNumber: number = value;
if (!(typeof value === "number")) { numeric = 5; }
else { numeric = 6; }
const afterNegation: number = value;
let textual: number | string = "start";
if (typeof textual === "number") { numeric = 7; }
else { numeric = 8; }
const stillString: string = textual;
