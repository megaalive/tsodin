// 😀 Non-BMP comment keeps UTF-16 coordinate provenance.
let flag: boolean = false;
flag = 2 < 3;
let out: boolean = false;
if (!flag && true) { out = flag === true; } else { out = flag === false; }
if (true && !flag) { out = flag === true; } else { out = flag === false; }
if (!flag || false) { out = flag === true; } else { out = flag === false; }
if (false || !flag) { out = flag === true; } else { out = flag === false; }
if ((!flag) && true) { out = flag === true; } else { out = flag === false; }
if (false || (!!flag)) { out = flag === false; } else { out = flag === true; }
if (!(!flag && true)) { out = flag === false; } else { out = flag === true; }
if (!(false || !flag)) { out = flag === false; } else { out = flag === true; }
const wrong: string = 1;
