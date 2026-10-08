// G5F3: only provably empty unreachable branches are accepted.
let n: number = 1;
n = 1 + 2;
let flag: boolean = false;
flag = n === 2;
let out: boolean = false;
if (flag && !flag) {
} else {
    out = flag === false;
}
if (flag || !flag) {
    out = flag === true;
} else {
}
if (!(flag && !flag)) {
    out = flag === false;
} else {
}
if (!(flag || !flag)) {
} else {
    out = flag === true;
}
if (flag && !flag) {
} else {
    flag = n === 3;
}
if (flag || !flag) {
    flag = n === 4;
} else {
}
const after: boolean = flag === false;
let other: boolean = false;
other = n === 3;
if (flag) {
    if (other && !other) {
    } else {
        out = flag === true;
    }
    if (other || !other) {
        out = flag === true;
    } else {
    }
} else {
    out = flag === false;
}
const nestedAfter: boolean = flag === false;
