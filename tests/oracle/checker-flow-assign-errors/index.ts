// 😀 Unicode position witness for source-ordered assignments.
let count: number = 1;
count = 2;
const impossible = count === 3;
count = 4;
const stillImpossible = count !== 2;
count = "bad";
