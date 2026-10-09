// 😀 Pinned TS7 UTF-16 starts for mixed-left decisive branches.
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
} else {
    out = c === true;
}
if ((a || b) && c) {
    out = c === false;
} else {
    out = "bad";
}
if (!((a && b) || c)) {
    out = c === true;
} else {
    out = b === false;
}
if (!((a || b) && c)) {
    out = b === true;
} else {
    out = c === false;
}
