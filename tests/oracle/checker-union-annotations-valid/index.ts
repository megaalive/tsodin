// Pinned TS7 source contract mirrored by bounded native union tests.
let value: number | string = 7;
value = "word";
value = 2 + 5;
const boolOrText: boolean | string = true;
const both: string | number = value;
const numeric: number | number = 7;
