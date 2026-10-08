// 😀 Source coordinates remain UTF-16 based.
let count: number = 1;
count = 1 + 2;
let ready: boolean = false;
ready = count === 2;
let verdict: boolean = false;
if (ready) {
    verdict = ready === false;
} else {
    verdict = ready === true;
}
if (!(count === 2)) {
    verdict = count === 3;
} else {
    verdict = count === 3;
}
if (ready === false) {
    verdict = ready === true;
} else {
    verdict = ready === false;
    verdict = "wrong";
}
const after: boolean = count === 9;
