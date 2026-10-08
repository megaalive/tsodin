// 😀 Keep non-BMP trivia ahead of branch diagnostics.
let code: number = 1;
code = 1 + 2;
let verdict: boolean = false;
if (code !== 2) {
    verdict = code === 3;
} else {
    verdict = code === 3;
    verdict = "wrong";
}
const after: boolean = code === 4;
let label: string = "a";
label = "p" + "q";
if (label !== "ok") {
    verdict = label === "other";
} else {
    verdict = label === "other";
}
