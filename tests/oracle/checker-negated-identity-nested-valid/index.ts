// 😀 Nested mutation: no fact crosses a sibling path or the outer join.
let flag: boolean = false;
flag = 2 < 3;
let gate: boolean = false;
gate = 4 > 2;
let out: boolean = false;
if (gate) {
  if (!flag && true) {
    out = flag === false;
    flag = 3 < 4;
    out = flag === true;
  } else {
    out = flag === true;
  }
  out = flag === false;
} else {
  if (!(false || !flag)) {
    out = flag === true;
  } else {
    out = flag === false;
  }
}
out = flag === false;
