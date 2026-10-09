let flag: boolean = false;
flag = 2 < 3;
let out: boolean = false;
if (!flag && true) { out = flag === false; } else { out = flag === true; }
if (true && !flag) { out = flag === false; } else { out = flag === true; }
if (!flag || false) { out = flag === false; } else { out = flag === true; }
if (false || !flag) { out = flag === false; } else { out = flag === true; }
if ((!flag) && true) { out = flag === false; } else { out = flag === true; }
if (false || (!!flag)) { out = flag === true; } else { out = flag === false; }
if (!(!flag && true)) { out = flag === true; } else { out = flag === false; }
if (!(false || !flag)) { out = flag === true; } else { out = flag === false; }
const after: boolean = flag === false;
