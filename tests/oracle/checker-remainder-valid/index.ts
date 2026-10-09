// TypeScript 7 pinned remainder expressions: precedence, numeric inference,
// assignments, unary grouping, and independent widened number comparisons.
let a: number = 17;
let b: number = 5;
const remainder = a % b;
const chained = 22 / 5 % 3 * 2;
const grouped: number = (-9) % (2 + 1);
let adjusted: number = 0;
adjusted = (a + 4) % 3;
const first: boolean = remainder === 2;
const second: boolean = chained !== 0;
const third: boolean = grouped === 4;
