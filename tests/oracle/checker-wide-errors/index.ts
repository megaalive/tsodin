// 😀 Preserve UTF-16 diagnostic spans after a non-BMP comment.
const num = 1 + 2;
const text = "a" + 'b';
const badDomain = num === text;
const flag = 2 < 3;
const badOtherDomain = flag !== num;
const one = 1;
const two = 2;
const badLiteral = one === two;
const wrong: string = num;
