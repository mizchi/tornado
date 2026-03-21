# tornado.json テンプレート

## テンプレート

```jsonc
{
  "ralph_enabled": true,
  "milestones_path": "<絶対パス>/.runs/{datetime}_{name}/milestones.json",
  "review_dir": ".runs/{datetime}_{name}",
  "max_rework_attempts": 3,
  "agents": [
    { "id": "planner",  "kind": "<PLANNER_KIND>",  "role": "planner",  "max_iterations": 10 },
    { "id": "builder",  "kind": "<DEV_KIND>",      "role": "dev",      "max_iterations": 10 },
    { "id": "verifier", "kind": "<VERIFIER_KIND>", "role": "verifier", "max_iterations": 5 }
  ]
}
```

## 重要事項

- `milestones_path` は**絶対パス**で指定すること（tornado は process.cwd() で動作するため）
- `review_dir` は相対パスで指定

## エージェント構成

| ID       | kind             | role     | 備考 |
|----------|------------------|----------|------|
| planner  | `<PLANNER_KIND>` | planner  | デフォルト: `claude-code` |
| builder  | `<DEV_KIND>`     | dev      | デフォルト: `codex` |
| verifier | `<VERIFIER_KIND>`| verifier | デフォルト: `claude-code` |

> `brief` は `tornado.json` ではなく `milestones.json` で管理する。

## 有効な agent kind 値

`claude-code`, `claude`, `claudecode`, `codex`, `api`, `mock`
