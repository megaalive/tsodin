// Wrong literal assignments are diagnosed even in impossible arms.
let value: number | string = 1;
let numeric: number = 0;
if (typeof value === "string") { numeric = "dead"; }
else { numeric = "live"; }
if (typeof value !== "number") { numeric = "inverted dead"; }
else { numeric = "inverted live"; }
