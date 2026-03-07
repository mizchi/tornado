---
description: 'Convert a plan file (Markdown) to tornado Ralph mode input files and launch tornado'
arguments: plan_file:計画ファイル(Markdown)のパス
---

# ralph-start: 計画ファイル -> tornado Ralph モード起動

## 引数

```
/ralph-start <plan-file.md> [--dev=<kind>] [--verifier=<kind>]
```

`$ARGUMENTS` の内容: `$ARGUMENTS`

## 実行手順

以下の Phase 1〜4 を**必ず順番に**実行すること。

---

### Phase 1: 入力検証

1. `$ARGUMENTS` を解析する:
   - 最初の `--` で始まらないトークンを `PLAN_FILE` とする
   - `--dev=<value>` があれば `DEV_KIND` に格納（デフォルト: `codex`）
   - `--verifier=<value>` があれば `VERIFIER_KIND` に格納（デフォルト: `claude-code`）
   - 引数が空、または `PLAN_FILE` が見つからない場合はエラーメッセージを出して終了

2. `PLAN_FILE` の存在を確認する（相対パスの場合は CWD からの解決）

3. リポジトリルートを取得:

   ```bash
   git rev-parse --show-toplevel
   ```

4. `PLAN_FILE` を読み込む

---

### Phase 2: 計画ファイル -> マイルストーン + タスク変換

**Step 1: 出力ディレクトリの作成と英訳版計画ファイルの生成**

1. ディレクトリ名を決定する（ディレクトリ名生成規則は後述）
2. 出力ディレクトリを作成する
3. 計画ファイルの全内容を英語に翻訳し、出力ディレクトリに `plan-en.md` として書き出す。
   コード内の識別子やファイルパスはそのまま保持する。

以降の goal / description で参照する Plan Context はこのファイルの内容を使用する。

**Step 2: パースと変換**

Markdown を以下の規則でパースする。

**重要: `goal`・`description`・ディレクトリ名はすべて英語で生成する。** 計画ファイルが日本語の場合は翻訳する。コード内の識別子やファイルパスはそのまま保持する。

#### パース規則

| Markdown 要素               | 変換先                                                |
| --------------------------- | ----------------------------------------------------- |
| `# 見出し` (最初のH1)       | プロジェクト名（ディレクトリ名に使用）                |
| `## 見出し`                 | マイルストーンの `goal`（後述の goal 構成規則に従う） |
| `##` がない場合             | ファイル全体を1マイルストーンとして扱う               |
| `-` / `*` / `N.` リスト項目 | タスクの `description`                                |
| `###` サブ見出し            | 同一マイルストーン内の Wave 区切り（wave を +1）      |

#### goal の構成規則（Verifier 検証精度向上のため）

`goal` は Verifier エージェントが Wave 検証時に参照する。
Verifier は `task.description` を受け取らないため、`goal` が検証の主要な文脈となる。

各マイルストーンの `goal` は以下の構成で生成すること:

```
<## 見出しテキスト>
```

> **Note:** Plan Context は plan-en.md から自動注入される。Claude が直接出力する必要はない。

#### ディレクトリ名の生成

- 最初の `# 見出し` のテキストを**英語に翻訳して**タイトルとする
- 小文字化、スペース/アンダースコアをハイフンに変換、英数字とハイフン以外を除去、50文字以内に切り詰め
- 出力ディレクトリ: `{repo_root}/.history/{yyyy-mm-dd}_{kebab-case-name}/`

#### タスク ID 命名規則

- `{milestone_id}-t{連番}` 形式（例: `m1-t1`, `m1-t2`, `m2-t1`）

#### description の拡張（最重要）

`description` は Builder に渡される**唯一の入力**（system_prompt・goal は渡されない）。

> **Note:** Plan Context は `plan-en.md` から `goal` と `description` の両方に自動注入される（Phase 3 の node スクリプトで実行）。
>
> - `goal` 側: Verifier が Wave 検証時に参照（Builder は参照しない）
> - `description` 側: Builder が実装時に参照（Verifier は参照しない）
> - 将来 Tornado 本体が修正され Builder に goal が渡されるようになれば、description 側の Plan Context は削除可能

各タスクの `description` は以下のテンプレートで生成する:

```
## Task
<具体的な実装指示。ファイルパス・期待動作・実装詳細を含める>

## Acceptance Criteria
<Builder が自己検証可能な条件。以下の3種のみ使用>
- [ ] File exists: <path>
- [ ] <path> contains: <expected content>
- [ ] Run: <command> → <expected result>
```

---

### Phase 3: 出力ファイル生成

出力ディレクトリは Phase 2 Step 1 で作成済み。以下のファイルを生成する（最終成果物は plan-en.md, milestones.json, tornado.json の3つ）。

#### 3-1. milestones-skeleton.json（中間ファイル）

Plan Context **なし** の JSON を `milestones-skeleton.json` として生成する:

```json
{
  "milestones": [
    {
      "id": "m1",
      "goal": "Goal text from ## heading (in English)",
      "status": "pending",
      "current_wave": 0,
      "tasks": [
        {
          "id": "m1-t1",
          "description": "## Task\n<concrete instructions in English>\n\n## Acceptance Criteria\n- [ ] File exists: <path>\n- [ ] <path> contains: <expected content>\n- [ ] Run: <command> → <expected result>",
          "wave": 0,
          "status": "pending",
          "result": null,
          "plan_doc": null
        }
      ]
    }
  ]
}
```

#### 3-2. milestones.json（Plan Context 注入）

bash/node スクリプトで `plan-en.md` の内容を各フィールドに注入し、`milestones.json` を生成する:

```bash
node -e "
const fs = require('fs');
const plan = fs.readFileSync('<output_dir>/plan-en.md', 'utf-8');
const data = JSON.parse(fs.readFileSync('<output_dir>/milestones-skeleton.json', 'utf-8'));
const suffix = '\n\n---\n## Plan Context\n' + plan;
for (const m of data.milestones) {
  m.goal += suffix;
  for (const t of m.tasks) {
    t.description += suffix;
  }
}
fs.writeFileSync('<output_dir>/milestones.json', JSON.stringify(data, null, 2));
"
rm <output_dir>/milestones-skeleton.json
```

> `<output_dir>` は実際の出力ディレクトリパスに置き換えること。

#### 3-3. tornado.json

`milestones_path` は**絶対パス**で指定すること（tornado は process.cwd() で動作するため）。

```jsonc
{
  "ralph_enabled": true,
  "milestones_path": "<絶対パス>/.history/{date}_{name}/milestones.json",
  "review_dir": ".history/{date}_{name}",
  "max_rework_attempts": 3,
  "agents": [
    { "id": "planner",  "kind": "mock",             "role": "planner",  "max_iterations": 1 },  // mock固定（tasks事前定義済み）
    { "id": "builder",  "kind": "<DEV_KIND>",        "role": "dev",      "max_iterations": 10 }, // デフォルト: codex
    { "id": "verifier", "kind": "<VERIFIER_KIND>",   "role": "verifier", "max_iterations": 5 }   // デフォルト: claude-code
  ]
}
```

---

### Phase 4: 検証・起動

1. **JSON バリデーション**: 生成した両ファイルを `jq .` で検証

2. **サマリー表示**: Plan file, Output dir, Milestones数, Tasks数, Builder/Verifier種別, 各マイルストーンの goal先頭行・タスク数・Wave数を表示

3. **tornado 起動**:

   ```bash
   npx -y @mizchi/tornado --ralph --config=<tornado.json の絶対パス> --lang=ja
   ```

---

## エラーハンドリング

- 計画ファイルが見つからない場合 -> エラーメッセージを出して終了
- 計画ファイルにリスト項目が1つもない場合 -> エラーメッセージを出して終了
- `--dev` / `--verifier` に無効な値が指定された場合 -> エラーメッセージを出して終了
  - 有効な値: `claude-code`, `claude`, `claudecode`, `codex`, `api`, `mock`
- JSON バリデーション失敗 -> エラーメッセージを出して終了（ファイルは残す）
