// M4-G5F7C: mutation invalidates a proven fact at the child join.
let n: number = 1;
n = 1 + 2;
let a: boolean = false;
a = n === 2;
let b: boolean = false;
b = n === 3;
let c: boolean = false;
c = n === 4;
let d: boolean = false;
d = n === 5;
let out: boolean = false;
if ((a && b) || c) {
    if (d) {
        out = a === true;
        c = n === 7;
    } else {
        out = b === false;
    }
    out = c === false;
} else {
    if (d) {
        out = c === false;
        c = n === 8;
    } else {
        out = c === false;
    }
    out = c === true;
}
if ((a || b) && c) {
    if (d) {
        out = c === true;
        c = n === 9;
    } else {
        out = c === true;
    }
    out = c === false;
} else {
    if (d) {
        out = c === false;
    } else {
        out = c === true;
    }
}
if (!(a && (b || c))) {
    if (d) {
        out = a === false;
    } else {
        out = b === true;
    }
} else {
    if (d) {
        out = a === true;
        a = n === 10;
    } else {
        out = a === true;
    }
    out = a === false;
}
if (!((a || b) && c)) {
    if (d) {
        out = c === false;
    } else {
        out = a === true;
    }
} else {
    if (d) {
        out = c === true;
        c = n === 11;
    } else {
        out = c === true;
    }
    out = c === false;
}
const after: boolean = c === true;
