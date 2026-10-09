// Only c has a decisive fact; a/b remain unknown.
let n: number = 1;
n = 1 + 2;
let a: boolean = false;
a = n === 2;
let b: boolean = false;
b = n === 3;
let c: boolean = false;
c = n === 4;
let out: boolean = false;
if ((a && b) || c) {
    out = a === false;
    out = c === false;
} else {
    out = c === false;
    out = b === true;
}
if ((a || b) && c) {
    out = c === true;
    out = a === false;
} else {
    out = c === true;
}
if (!((a && b) || c)) {
    out = c === false;
} else {
    out = a === true;
}
if (!((a || b) && c)) {
    out = a === false;
} else {
    out = c === true;
}
const after: boolean = c === false;
