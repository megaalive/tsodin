// The same union relations must reject writes outside the target domain.
let value: number | string = 7;
value = false;
const wrong: string | boolean = 42;
