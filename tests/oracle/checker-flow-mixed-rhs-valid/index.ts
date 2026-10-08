// Exactly one independently proven fact from each mixed formula.
let n: number = 1;
n = 1 + 2;
let a: boolean = false;
a = n === 2;
let b: boolean = false;
b = n === 3;
let c: boolean = false;
c = n === 4;
let out: boolean = false;
if (a && (b || c)) {
    out = a === true;
    out = b === false;
} else {
    out = a === false;
}
if (a || (b && c)) {
    out = b === false;
} else {
    out = a === false;
}
if (!(a && (b || c))) {
    out = c === false;
} else {
    out = a === true;
}
if (!(a || (b && c))) {
    out = a === false;
} else {
    out = b === false;
}
const after: boolean = a === false;
