// 😀 M4-G5F7C: UTF-16 starts, child-local diagnostics and post-join widening.
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
    out = b === false;
} else {
    if (d) {
        out = c === true;
    } else {
        out = c === true;
    }
    out = c === true;
}
if ((a || b) && c) {
    if (d) {
        out = c === false;
    } else {
        c = n === 7;
        out = c === false;
    }
    out = c === false;
} else {
    out = "bad";
}
if (!(a && (b || c))) {
    out = a === true;
} else {
    if (d) {
        out = a === false;
    } else {
        out = a === false;
    }
}
if (!((a && b) || c)) {
    if (d) {
        out = c === true;
    } else {
        out = c === true;
    }
} else {
    out = a === true;
}
