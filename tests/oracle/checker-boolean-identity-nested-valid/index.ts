// 😀 No nested condition can mutate an outer fork snapshot.
let flag: boolean = false;
flag = 2 < 3;
let gate: boolean = false;
gate = 4 > 2;
let out: boolean = false;
if (gate) {
  if (flag && true) {
    flag = 3 < 4;
    out = flag === false;
  } else {
    out = flag === false;
  }
  out = flag === true;
} else {
  if (!(false || flag)) {
    out = flag === false;
  } else {
    out = flag === true;
  }
}
out = flag === true;
