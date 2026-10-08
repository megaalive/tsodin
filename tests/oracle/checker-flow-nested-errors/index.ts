// 😀 Nested diagnostic coordinates use UTF-16.
let code: number = 1;
code = 1 + 2;
let ready: boolean = false;
ready = code === 2;
let result: boolean = false;
if (code === 2) {
    if (ready) {
        result = code === 3;
        result = ready === false;
    } else {
        result = code === 4;
    }
} else {
    if (!ready) {
        result = ready === true;
    } else {
        result = "wrong";
    }
}
const after: boolean = code === 9;
