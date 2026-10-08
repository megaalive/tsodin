// M4-G5F6: child mutation widens b but does not erase a/c.
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
        out = a === true;
        out = c === true;
        b = n === 7;
    } else {
        out = b === true;
        out = c === true;
    }
    out = c === true;
    out = b === false;
} else {
    out = a === false;
}
const after: boolean = a === false;
