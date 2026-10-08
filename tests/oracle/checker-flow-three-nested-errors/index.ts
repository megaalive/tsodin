// 😀 M4-G5F6 nested diagnostic starts use UTF-16.
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
if (a && b && c) {
    if (d) {
        out = a === false;
    } else {
        out = c === false;
    }
    out = c === false;
} else {
    out = "wrong";
}
if (a || b || c) {
    out = a === false;
} else {
    out = b === true;
}
