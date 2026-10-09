// 😀 UTF-16 witness for computed unary Boolean types.
let flag: boolean = false;
flag = 2 < 3;
const inverted = !flag;
const wrong: string = inverted;
const badDomain = inverted === 1;
const fine: boolean = inverted !== false;
