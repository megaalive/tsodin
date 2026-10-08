// 😀 G5F3 active-path diagnostics retain source UTF-16.
let n: number = 1;
n = 1 + 2;
let flag: boolean = false;
flag = n === 2;
let out: boolean = false;
if (flag && !flag) {
} else {
    out = "bad";
}
if (flag || !flag) {
    out = "wrong";
} else {
}
