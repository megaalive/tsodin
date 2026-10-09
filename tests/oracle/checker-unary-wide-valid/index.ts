let flag: boolean = false;
flag = 2 < 3;
const inverted = !flag;
const twice = !!flag;
const grouped = !(flag);
const first: boolean = inverted === true;
const second: boolean = twice !== false;
const third: boolean = grouped === false;
