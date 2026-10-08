// 😀 Keep Unicode trivia ahead of narrowed diagnostics.
let code: number = 1;
code = 1 + 2;
let verdict: boolean = false;
if (code === 2) {
    verdict = code === 3;
} else {
    verdict = "wrong";
}
const after: boolean = code === 4;
