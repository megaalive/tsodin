// 😀 Dead and live assignments must both retain TS2322 UTF-16 starts.
let n: number = 1;
n = 1 + 2;
let flag: boolean = false;
flag = n === 2;
let out: boolean = false;
if (flag && !flag) {
    out = "dead mismatch";
} else {
    out = "live mismatch";
}
if (flag || !flag) {
    out = true;
} else {
    out = 12;
}
