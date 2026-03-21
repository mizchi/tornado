# milestones.json 形式

このスキルは skeleton ではなく、`milestones.json` を直接生成する。

## JSON 例

```json
{
  "brief": "Full content of informational sections (Context, Target Files, Design Decisions, etc.) + intro text between # and first ##, translated to English",
  "milestones": [
    {
      "id": "m1",
      "goal": "Implementation Steps\n\n### Step 1: Add perspectives parameter\n\n**File:** src/ralph/verifier.mbt:131-162\n\n```mbt\npub fn VerifierAgent::verify(...)\n```\n\n### Step 2: ...",
      "status": "pending",
      "summary": "",
      "tasks": []
    }
  ]
}
```

## フィールド定義

| フィールド    | 型     | 説明 |
| ------------- | ------ | ---- |
| `brief`       | string | plan の情報セクション（背景・文脈、対象ファイル一覧、設計判断、問題分析、結論等）の全文 + H1〜最初の ## 間のテキストを英訳したもの。plan の背景情報を漏れなく保持する |
| `milestones`  | array  | milestone 配列 |

### milestone

| フィールド | 型     | 説明 |
| ---------- | ------ | ---- |
| `id`       | string | `m{連番}` 形式（例: `m1`, `m2`） |
| `goal`     | string | `##` 見出しテキスト＋配下の本文全体を英訳した milestone goal。実装詳細（ファイルパス・行番号・コード例・手順）をすべて含む |
| `status`   | string | 初期値は `"pending"` |
| `summary`  | string | milestone 完了時に runtime が生成する要約。初期値は `""` |
| `tasks`    | array  | 初期値は `[]` |

## 注記

- plan の情報量を完全に保持する。要約・切り詰め禁止
- `summary` は各 milestone 完了後に runtime が書き戻し、次の Planner 実行時の背景情報として使われる
