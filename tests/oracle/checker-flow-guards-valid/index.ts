let count: number = 1;
count = 1 + 2;
let ready: boolean = false;
ready = count === 2;
let verdict: boolean = false;
if (ready) {
    verdict = ready === true;
} else {
    verdict = ready === false;
}
if (!ready) {
    verdict = ready === false;
} else {
    verdict = ready === true;
}
if (!(count === 2)) {
    verdict = count === 3;
} else {
    verdict = count === 2;
}
if (ready === false) {
    verdict = ready === false;
} else {
    verdict = ready === true;
}
if (!!(count !== 2)) {
    verdict = count === 3;
} else {
    verdict = count === 2;
}
const restored: boolean = count === 9;
const booleanJoin: boolean = ready === false;
