Run the full verification pipeline for the tornado project:

1. Format check: `moon fmt --check` and `npx prettier --check 'sdk/**/*.{mts,mjs}'`
2. Static analysis: `moon check --target js` and `npx tsc --noEmit -p tsconfig.sdk.json`
3. Tests: `just test`
4. E2E: `just mock`

Report results as a table. Fix any failures found.
