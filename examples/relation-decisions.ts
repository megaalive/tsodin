// Two successful primitive targets and one incompatible reassignment.
let count: number = 1;
let note: string = "ready";
count = 2;
count = "not a number";
note = "still valid";
