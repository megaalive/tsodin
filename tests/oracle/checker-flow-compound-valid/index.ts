// M4-G5F1: two independent, pure short-circuit operands.
let n: number = 1;
n = 1 + 2;
let a: boolean = false;
a = n === 2;
let b: boolean = false;
b = n === 3;
let mode: boolean = false;
mode = n === 4;
let out: boolean = false;
if (a && b) {
    out = a === true;
    out = b === true;
    if (mode) {
        out = a === true;
    } else {
        out = b === true;
    }
} else {
    out = a === b;
}
if (a || b) {
    out = a === false;
} else {
    out = a === false;
    out = b === false;
}
if (!(a && !b)) {
    out = a === false;
} else {
    out = a === true;
    out = b === false;
    a = n === 2;
    out = a === true;
}
const after: boolean = a === false;
