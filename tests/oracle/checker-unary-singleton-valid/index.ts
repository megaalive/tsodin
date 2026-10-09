// Native TS7: singleton Boolean negation must preserve exact literal types.
const no = !true;
const yes = !false;
const twice = !!true;
const grouped = !(false);
const a = no === false;
const b = yes === true;
const c = twice !== true;
const d = grouped === true;
let flag: boolean = false;
flag = 2 < 3;
let output: boolean = false;
if (flag) {
  output = (!flag) === false;
  flag = 4 > 2;
  output = (!flag) === false;
} else {
  output = (!flag) === true;
}
output = (!flag) === false;
