define x($y) {
  notify { number: message => $y }
}

node default {
  x { test: y => 0777 }
}
