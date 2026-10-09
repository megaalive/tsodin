// Both arms are type errors under pinned TypeScript 7.
let flag: boolean = 1 < 2;
let value: number | string = 1;
if (flag) { value = 8; } else { value = "one"; }
let numeric: number = 0;
let textual: string = "";
if (typeof value === "number") { textual = value; }
else { numeric = value; }
