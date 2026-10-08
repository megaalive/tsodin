// 😀 G5F1 diagnostic positions are UTF-16, not UTF-8 bytes.
let n: number = 1;
n = 1 + 2;
let a: boolean = false;
a = n === 2;
let b: boolean = false;
b = n === 3;
let out: boolean = false;
if (a && b) {
    out = a === false;
    out = b === false;
} else {
    out = "bad";
}
if (a || b) {
    out = a === false;
} else {
    out = a === true;
    out = b === true;
}
