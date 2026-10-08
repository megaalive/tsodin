let n: number = 1;
n = 1 + 2;
let flag: boolean = false;
flag = n === 2;
let out: boolean = false;
if (flag && flag) {
    out = flag === true;
} else {
    out = flag === false;
}
if (flag || flag) {
    out = flag === true;
} else {
    out = flag === false;
}
if (flag && (flag === true)) {
    out = flag === true;
} else {
    out = flag === false;
}
if (!(flag && flag)) {
    out = flag === false;
} else {
    out = flag === true;
}
if (n === 2 && n === 2) {
    out = n === 2;
} else {
    out = n === 4;
}
const after: boolean = flag === false;
