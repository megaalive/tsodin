// 😀 Unicode position witness for source-ordered assignments.
let count: number = 1;
count = 2;
const possible = count === 3;
count = 4;
const stillPossible = count !== 2;
const low = 1;
const high = 2;
const impossible = low === high;
count = "bad";
