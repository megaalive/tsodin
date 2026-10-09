// 😀 Proved inverse literals must not lose disjoint comparisons.
const no = !true;
const yes = !false;
const wrongFirst = no === true;
const good = yes === true;
const wrongSecond = yes !== false;
const wrongThird = !!false === true;
const wrongType: string = no;
