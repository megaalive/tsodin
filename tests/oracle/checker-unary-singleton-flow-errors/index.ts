// 😀 A reassignment broadens only the mutated arm, not its sibling.
let flag: boolean = false;
flag = 2 < 3;
let output: boolean = false;
if (flag) {
  output = (!flag) === true;
  flag = 4 > 2;
  output = (!flag) === false;
} else {
  output = (!flag) === false;
}
output = (!flag) === true;
