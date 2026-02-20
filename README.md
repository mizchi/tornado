# tornado

Multi-agent development orchestrator with TUI.

## Usage

### Pattern 1: Run with `npx`

```bash
# run from a plan file (first positional arg must be an existing file)
npx -y @mizchi/tornado ./plan.md --dev=codex --review=claude

# run with explicit config
npx -y @mizchi/tornado --config=./tornado.json --dev=codex --review=claude

# validate config
npx -y @mizchi/tornado validate ./tornado.json
```

### Pattern 2: Install globally with `npm i -g`

```bash
npm i -g @mizchi/tornado

# run from a plan file
tornado ./plan.md --dev=codex --review=claude

# run with explicit config
tornado --config=./tornado.json --dev=codex --review=claude

# validate config
tornado validate ./tornado.json
```

## Agent kind options

- `claude` / `claude-code`
- `codex`
- `api`
- `mock`
