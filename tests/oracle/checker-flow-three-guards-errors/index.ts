// 😀 G5F5 error positions are compared in UTF-16.
let n: number = 1;
n = 1 + 2;
let a: boolean = false;
a = n === 2;
let b: boolean = false;
b = n === 3;
let c: boolean = false;
c = n === 4;
let out: boolean = false;
if (a && b && c) {
    out = a === false;
    out = b === false;
    out = c === false;
} else {
    out = "wrong";
}
if (a || b || c) {
    out = c === true;
} else {
    out = a === true;
    out = b === true;
    out = c === true;
}
