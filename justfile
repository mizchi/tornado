default: check test

check:
  moon check --target js

test:
  moon test --target js

build:
  moon build --target js src/cmd/app

run *args: build
  node _build/js/debug/build/cmd/app/app.js {{args}}

clean:
  moon clean

fmt:
  moon fmt

info:
  moon info
