default: check test

setup:
  npm install

check:
  npm run -s build:sdk
  moon check --target js

test:
  npm run -s build:sdk
  node --test sdk/*.test.mjs
  moon test --target js

build:
  npm run -s build:sdk
  moon build --target js src/cmd/app

pack: build
  mkdir -p bin
  echo '#!/usr/bin/env node' > bin/tornado.js
  cat _build/js/debug/build/cmd/app/app.js >> bin/tornado.js
  chmod +x bin/tornado.js

publish: pack
  npm publish --access public

run *args: build
  node _build/js/debug/build/cmd/app/app.js {{args}}

clean:
  moon clean

fmt:
  moon fmt

info:
  moon info
