// Dead arms are checked but never contribute assignments to the join.
let n: number = 1;
n = 1 + 2;
let flag: boolean = false;
flag = n === 2;
let out: boolean = false;
if (flag && !flag) {
    out = true;
    out = false;
} else {
    out = flag === false;
}
if (flag || !flag) {
    out = flag === true;
} else {
    out = false;
}
if (flag) {
    if (flag && !flag) {
        out = false;
    } else {
        out = flag === true;
    }
} else {
    out = flag === false;
}
const after: boolean = flag === false;
