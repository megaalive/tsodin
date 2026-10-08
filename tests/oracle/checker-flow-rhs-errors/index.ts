// 😀 G5F2 UTF-16 witness for idempotent logical guards.
let n: number = 1;
n = 1 + 2;
let flag: boolean = false;
flag = n === 2;
let out: boolean = false;
if (flag && flag) {
    out = flag === false;
} else {
    out = flag === true;
}
if (flag || flag) {
    out = flag === false;
} else {
    out = flag === true;
}
out = "bad";
