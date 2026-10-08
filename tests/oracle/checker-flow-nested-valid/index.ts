let code: number = 1;
code = 1 + 2;
let ready: boolean = false;
ready = code === 2;
let result: boolean = false;
if (code === 2) {
    if (ready) {
        result = code === 2;
        result = ready === true;
    } else {
        result = code === 2;
        result = ready === false;
    }
    result = code === 2;
} else {
    if (!ready) {
        result = ready === false;
    } else {
        result = ready === true;
    }
    result = code === 9;
}
const after: boolean = code === 4;
