# Ralph モード 利用ガイド

## 1. Ralph モードとは

Ralph モードは Tornado のマイルストーン駆動型自律開発ループである。
通常モード（無限ループで dev→review を繰り返す Heartbeat Loop）とは異なり、
**事前に定義したマイルストーン（目標）を順番に達成していく有限ループ**で動作する。

全マイルストーンが完了すると自動的に終了する。

### 通常モードとの違い

| 項目 | 通常モード (Heartbeat) | Ralph モード |
|------|----------------------|-------------|
| 終了条件 | Ctrl+C のみ（無限ループ） | 全マイルストーン完了で自動終了 |
| タスク生成 | 自動で次タスクを生成し続ける | 事前定義 or Planner が生成 |
| エージェント | Dev + Reviewer (2体) | Planner + Builder + Verifier (3体) |
| 構造 | フラットなタスク列 | Milestone > Wave > Task の3層 |
| レビュー | 3観点レビュー (CodeQuality, Performance, Security) | Wave 単位の統合検証 |
| フィードバック | Review の指摘を Dev に渡す | **未実装**（既知の制限事項） |

---

## 2. CLI 引数

### 基本コマンド

```bash
tornado --ralph [オプション...]
```

### 利用可能なオプション

| オプション | 説明 | デフォルト |
|-----------|------|----------|
| `--ralph` | **必須**。Ralph モードを有効化する | `false` |
| `--config=<path>` | 設定ファイルのパス | `tornado.json`（なければプリセット使用） |
| `--dev=<kind>` | Builder（Dev ロール）の種類を上書き | `claude-code` |
| `--review=<kind>` | Review ロールの種類を上書き。**Ralph モードでは効かない（後述）** | `codex` |
| `--lang=<auto\|ja\|en>` | エージェントの応答言語 | `auto`（環境変数 `LANG` から検出） |

### エージェント種類 (`--dev`, `--review` に指定可能な値)

| 値 | 説明 |
|----|------|
| `claude` / `claude-code` / `claudecode` | Claude Code |
| `codex` | OpenAI Codex |
| `api` | API バックエンド |
| `mock` | テスト用モック |

### マイルストーンファイルのパス指定

マイルストーンファイルのパスを CLI 引数で直接指定するオプションは**存在しない**。
パスを変更するには、設定ファイル (`tornado.json`) の `milestones_path` を使う:

```json
{
  "ralph_enabled": true,
  "milestones_path": "path/to/my-milestones.json",
  "agents": [ ... ]
}
```

| 方法 | マイルストーンファイルのパス |
|------|--------------------------|
| `tornado --ralph` (設定なし) | `.tornado/milestones.json` 固定 |
| `tornado --ralph --config=tornado.json` | 設定ファイル内の `milestones_path`（省略時は `.tornado/milestones.json`） |
| ~~`tornado --ralph --milestones=...`~~ | **未実装（CLI フラグは存在しない）** |

### 使用例

```bash
# 最小構成（プリセット使用、.tornado/milestones.json を読み込む）
tornado --ralph

# 設定ファイル指定（milestones_path もここで変更可能）
tornado --ralph --config=tornado.json

# エージェント種類を上書き
tornado --ralph --dev=codex --review=claude

# 日本語で応答
tornado --ralph --lang=ja

# フル指定
tornado --ralph --config=my-config.json --dev=claude --review=codex --lang=ja
```

---

## 3. 設定ファイル (`tornado.json`)

`--config` を指定しない場合、カレントディレクトリの `tornado.json` を探す。
見つからなければ組み込みプリセット (`preset_ralph`) が使われる。

### JSON フォーマット

```json
{
  "project_dir": ".",
  "review_dir": "docs/reviews",
  "ralph_enabled": true,
  "milestones_path": ".tornado/milestones.json",
  "max_rework_attempts": 3,
  "max_review_cycles": 3,
  "review_interval": 1,
  "agents": [
    {
      "id": "planner",
      "kind": "claude-code",
      "role": "planner",
      "working_dir": ".",
      "max_iterations": 10
    },
    {
      "id": "builder",
      "kind": "claude-code",
      "role": "dev",
      "working_dir": ".",
      "max_iterations": 10
    },
    {
      "id": "verifier",
      "kind": "codex",
      "role": "verifier",
      "working_dir": ".",
      "max_iterations": 5
    }
  ]
}
```

### 設定フィールド一覧

| フィールド | 型 | デフォルト | 説明 |
|-----------|------|----------|------|
| `project_dir` | string | `"."` | プロジェクトルートディレクトリ |
| `review_dir` | string | `"docs/reviews"` | レビュー出力ディレクトリ |
| `ralph_enabled` | bool | `false` | Ralph モード有効化（`--ralph` フラグで自動 `true`） |
| `milestones_path` | string? | `null` | マイルストーンファイルパス（省略時 `.tornado/milestones.json`） |
| `max_rework_attempts` | int | `3` | Wave 単位のリワーク最大回数 |
| `max_review_cycles` | int | `3` | レビューサイクル上限（Ralph では未使用） |
| `review_interval` | int | `1` | レビュー間隔（Ralph では未使用） |
| `agents` | array | `[]` | エージェント設定の配列 |

### エージェント設定フィールド

| フィールド | 型 | デフォルト | 説明 |
|-----------|------|----------|------|
| `id` | string | `""` | エージェントの一意識別子 |
| `kind` | string | `"mock"` | `"claude-code"` / `"codex"` / `"api"` / `"mock"` |
| `role` | string | `"dev"` | `"planner"` / `"dev"` / `"builder"` / `"verifier"` / `"review"` |
| `model` | string? | `null` | 使用モデル名（省略可） |
| `system_prompt` | string? | `null` | カスタムシステムプロンプト（省略可） |
| `working_dir` | string | `"."` | 作業ディレクトリ |
| `max_iterations` | int | `10` | エージェント内部の反復上限 |

> **Note:** `role` の `"builder"` は内部的に `Dev` ロールとして扱われる。
> Planner から見た Builder も `Dev` ロールのエージェントを使用する。

### プリセット（設定ファイルなしの場合）

`--ralph` のみで起動し、`tornado.json` がない場合のデフォルト構成:

| エージェント | ID | Kind | Role |
|------------|-----|------|------|
| Planner | `planner` | ClaudeCode | Planner |
| Builder | `builder` | ClaudeCode | Dev |
| Verifier | `verifier` | Codex | Verifier |

その他のデフォルト:
- `max_rework_attempts`: 3
- `ralph_enabled`: true

### バリデーションルール

設定は起動時に検証される。以下の場合エラーになる:

- `agents` が空
- エージェント `id` が重複
- `Dev` ロールのエージェントが存在しない
- `ralph_enabled: true` なのに `Planner` ロールのエージェントがない
- `review_interval` が 1 未満

---

## 4. マイルストーンファイル (`.tornado/milestones.json`)

Ralph モードの入力となるファイル。実行前に手動で作成する必要がある。

### JSON フォーマット

```json
{
  "milestones": [
    {
      "id": "m1",
      "goal": "認証システムを構築する",
      "status": "pending",
      "current_wave": 0,
      "tasks": []
    },
    {
      "id": "m2",
      "goal": "REST API エンドポイントを実装する",
      "status": "pending",
      "current_wave": 0,
      "tasks": []
    }
  ]
}
```

### マイルストーンフィールド

| フィールド | 型 | 必須 | 説明 |
|-----------|------|------|------|
| `id` | string | Yes | マイルストーンの一意識別子（例: `"m1"`, `"m2"`） |
| `goal` | string | Yes | マイルストーンの目標を自然言語で記述 |
| `status` | string | Yes | `"pending"` / `"in_progress"` / `"done"` / `"failed"` |
| `current_wave` | int | No | 現在の Wave 番号（デフォルト: 0） |
| `tasks` | array | No | タスクの配列（空の場合 Planner が自動生成） |

### タスクフィールド

| フィールド | 型 | 必須 | 説明 |
|-----------|------|------|------|
| フィールド | 型 | 必須 | Builder に渡されるか | 説明 |
|-----------|------|------|-------------------|------|
| `id` | string | Yes | No | タスクID（例: `"m1-t1"`, `"m1-t2"`）。ログ表示と Verifier への結果紐付けに使用 |
| `description` | string | Yes | **Yes（唯一の入力）** | Builder の prompt としてそのまま渡される。後述の「description の書き方」を参照 |
| `wave` | int | Yes | No | 所属する Wave 番号（0始まり）。実行順序制御に使用 |
| `status` | string | Yes | No | `"pending"` / `"in_progress"` / `"done"` / `"failed"` |
| `result` | string? | No | No（出力側） | タスク実行結果（実行後に自動設定される） |
| `plan_doc` | string? | No | No | 計画ドキュメント（**どこからも読まれておらず現在未使用**） |

### description の書き方

`description` は Builder（Claude Code / Codex）に**そのまま prompt として渡される**唯一の入力である。
system_prompt は空文字固定で、milestone の goal やプロジェクトコンテキストは渡されない。

```moonbit
// ralph_loop.mbt:155-156 — Builder 呼び出しの実装
let result = backend.run(
    task.description,   // ← これだけが prompt になる
    "",                 // ← system_prompt は常に空
    fn(e) { handle_event(self, bid, e) },
)
```

したがって、**Claude Code に直接指示するのと同じ粒度・具体性**で書く必要がある。

**良い例（具体的で実行可能）:**
```json
{
  "description": "src/db/schema.sql に users テーブルを作成してください。カラムは id (UUID, PK), email (VARCHAR, UNIQUE, NOT NULL), password_hash (VARCHAR, NOT NULL), created_at (TIMESTAMP) です。"
}
```

**悪い例（曖昧すぎる）:**
```json
{
  "description": "スキーマ作成"
}
```

> **Planner 自動生成との比較:** Planner が生成する description は WAVE テキストから
> パースされた1行テキスト（例: `"Create database schema"`）になる。
> 手動で tasks を定義する場合は、より詳細な指示を書けるメリットがある。

> **リワーク時の注意:** リワーク時は `"Rework: " + task.description` が prompt になる。
> Verifier のフィードバック内容は渡されない（既知の制限）。

### 例: タスクを事前定義する場合

Planner を使わず、手動でタスクを定義することもできる:

```json
{
  "milestones": [
    {
      "id": "m1",
      "goal": "データベーススキーマを設計・実装する",
      "status": "pending",
      "current_wave": 0,
      "tasks": [
        {
          "id": "m1-t1",
          "description": "ユーザーテーブルのスキーマを作成",
          "wave": 0,
          "status": "pending"
        },
        {
          "id": "m1-t2",
          "description": "マイグレーションスクリプトを作成",
          "wave": 0,
          "status": "pending"
        },
        {
          "id": "m1-t3",
          "description": "API ハンドラーを実装",
          "wave": 1,
          "status": "pending"
        },
        {
          "id": "m1-t4",
          "description": "認証ミドルウェアを追加",
          "wave": 1,
          "status": "pending"
        }
      ]
    }
  ]
}
```

> **ポイント:** `tasks` が空の場合、Planner エージェントが `goal` を読み取って
> 自動的に WAVE 構造のタスクを生成する。事前にタスクを定義していれば
> Planner はスキップされる。

### 例: 最小構成

```json
{
  "milestones": [
    {
      "id": "m1",
      "goal": "Build a CLI tool that converts CSV files to JSON",
      "status": "pending",
      "tasks": []
    }
  ]
}
```

---

## 5. 3層構造: Milestone > Wave > Task

```
Milestone (目標単位)
  +-- Wave 0 (依存関係なし、同時実行可能なタスク群)
  |     +-- Task m1-t1
  |     +-- Task m1-t2
  +-- Wave 1 (Wave 0 に依存するタスク群)
  |     +-- Task m1-t3
  |     +-- Task m1-t4
  +-- Wave 2 ...
```

- **Milestone**: 達成すべき目標。複数定義でき、順番に処理される。
- **Wave**: 依存関係でグループ化されたタスクの集合。Wave 0 → Wave 1 → ... と順序実行。
- **Task**: 個別の実行単位。同一 Wave 内のタスクは論理的に独立。

> **Note:** 現在の実装では同一 Wave 内のタスクも**順序実行**される。
> 設計上は並列実行可能だが、並列化は未実装。

---

## 6. 実行フロー

### 6.1 起動シーケンス

```
1. CLI 解析: --ralph フラグを検出
2. 設定ロード:
   a. --config 指定あり → ファイル読み込み → ralph_enabled=true に上書き
   b. --config 指定なし → preset_ralph() を使用
3. CLI オーバーライド適用: --dev, --review の値で agents の kind を上書き
4. 設定バリデーション
5. バックエンド生成: 各エージェントの kind に応じたバックエンドを作成
6. マイルストーンロード:
   a. milestones_path (デフォルト .tornado/milestones.json) を読み込み
   b. ファイルがなければ空のマネージャーを作成 → 警告表示して終了
7. RalphLoop 生成・実行
8. 完了後: マイルストーン状態を milestones_path に保存
```

### 6.2 ループ実行フロー

```
RalphLoop::run()
  |
  +-- 各 pending マイルストーンに対して:
  |     |
  |     +-- [Planning] tasks が空なら Planner を実行
  |     |     Planner が goal を WAVE 形式のタスクリストに分解
  |     |
  |     +-- milestone.status = InProgress
  |     |
  |     +-- 未完了タスクがある間:
  |     |     |
  |     |     +-- 最小 Wave 番号を取得
  |     |     |
  |     |     +-- [Executing] Wave 内の各タスクを Builder で実行
  |     |     |     各タスクの結果を記録
  |     |     |
  |     |     +-- [Verifying] Verifier が Wave 結果を検証
  |     |           |
  |     |           +-- Approved → 次の Wave へ
  |     |           +-- NeedsRework → リワーク実行 → 再検証
  |     |           |     (max_rework_attempts まで繰り返し)
  |     |           |     (超過時は強制承認)
  |     |           +-- MilestoneFailed → マイルストーン失敗、次へ
  |     |
  |     +-- 全 Wave 完了 → milestone.status = Done
  |
  +-- AllComplete (全マイルストーン処理完了)
```

### 6.3 状態マシン

RalphLoop は以下の状態を遷移する:

```
LoadingMilestones
  → Planning(milestone_id)
    → ExecutingWave(milestone_id, wave_num)
      → Verifying(milestone_id, wave_num)
        → Approved → 次 Wave or MilestoneComplete
        → NeedsRework → Reworking(milestone_id, wave_num) → Verifying (retry)
        → MilestoneFailed → 次マイルストーン
  → MilestoneComplete(milestone_id)
  → AllComplete
```

---

## 7. 3大エージェントの動作

### 7.1 Planner エージェント

**役割:** マイルストーンの `goal` を具体的なタスクに分解する。

**入力プロンプト構造:**
```
You are a Planner agent. Respond in English.  (--lang=ja なら Japanese)

## Milestone
ID: m1
Goal: Build authentication system

## Project Context
(project_context が渡された場合のみ)

## Instructions
Break down this milestone into concrete tasks grouped by waves.
Tasks in the same wave can be executed independently.
Tasks in later waves depend on earlier waves.

## Output Format
WAVE 0:
1. First task description
2. Second task description

WAVE 1:
1. Task that depends on wave 0
```

**出力パース規則:**
- `WAVE N:` / `wave N:` / `Wave N:` ヘッダーで Wave 番号を認識
- `1. 説明文` (番号付き) または `- 説明文` (箇条書き) でタスクを認識
- 空行は無視される

**出力例:**
```
WAVE 0:
1. Create database schema for users and sessions
2. Write migration scripts

WAVE 1:
1. Build API handlers for authentication endpoints
2. Add JWT middleware
```

→ 4タスク生成: Wave 0 に2タスク, Wave 1 に2タスク

### 7.2 Builder エージェント (Dev ロール)

**役割:** 個々のタスクを実行する。

**入力:** `task.description` がそのままプロンプトとして渡される。

**リワーク時の入力:** `"Rework: " + task.description`

> **既知の制限:** リワーク時に Verifier のフィードバック内容は渡されない。
> `_feedback` パラメータは未使用。

### 7.3 Verifier エージェント

**役割:** Wave の実行結果を検証する。

**入力プロンプト構造:**
```
You are a Verifier agent. Respond in English.

## Milestone
ID: m1
Goal: Build authentication system
Wave: 0

## Wave Results
### Task: m1-t1
(タスクの実行結果)

### Task: m1-t2
(タスクの実行結果)

## Instructions
Verify that all tasks in this wave were completed correctly.
Check code quality, correctness, and alignment with the milestone goal.

## Output Format
Use exactly one of these tags:
- <wave_approved> if all tasks pass verification
- <needs_rework>task_id: reason</needs_rework> for tasks that need fixes
- <milestone_failed>reason</milestone_failed> if the milestone cannot be achieved
```

**出力パース規則:**

| 出力タグ | 判定 | 動作 |
|---------|------|------|
| `<wave_approved>` | 承認 | 次の Wave へ進む |
| `<needs_rework>...</needs_rework>` | 要リワーク | 失敗タスクを再実行 |
| `<milestone_failed>...</milestone_failed>` | 失敗 | マイルストーンを失敗とする |
| タグなし | 承認（デフォルト） | 次の Wave へ進む |

**`<needs_rework>` の内容フォーマット:**
```
<needs_rework>
m1-t1: エラーハンドリングを追加してください
m1-t2: テストが不足しています
</needs_rework>
```
改行区切りで複数のリワーク指示を記述できる。

---

## 8. 制御パラメータ

| パラメータ | 値 | 効果 |
|-----------|-----|------|
| `max_rework_attempts` | 3 (デフォルト) | Wave ごとのリワーク最大回数。超過すると強制承認。 |
| `max_iterations` (エージェント) | 10 (デフォルト) | 各エージェント内部の反復上限 |

### リワーク動作の詳細

1. Verifier が `NeedsRework` を返す
2. `rework_tasks()` で `Failed` / `Pending` 状態のタスクを再実行
3. 再度 `verify_wave()` を呼び出し（attempt + 1）
4. `attempt >= max_rework_attempts` の場合 → 強制承認（`true` を返す）
5. 再び `NeedsRework` なら上記を繰り返す

---

## 9. 永続化とレジューム

### 実行完了時の保存

ループ完了後、マイルストーンの状態が `milestones_path` に JSON として保存される:

```json
{
  "milestones": [
    {
      "id": "m1",
      "goal": "Build auth",
      "status": "done",
      "current_wave": 0,
      "tasks": [
        {
          "id": "m1-t1",
          "description": "Create schema",
          "wave": 0,
          "status": "done",
          "result": "Schema created successfully...",
          "plan_doc": null
        }
      ]
    }
  ]
}
```

### レジューム

マイルストーンファイルにはタスクの `status` が保存されるため、
中断後に再実行すると `pending` / `in_progress` のマイルストーンから処理が再開される。

- `status: "done"` のマイルストーンはスキップされる
- `status: "failed"` のマイルストーンもスキップされる
- `status: "pending"` / `"in_progress"` のマイルストーンが処理対象

> **Note:** 途中で Ctrl+C した場合は保存されない可能性がある
> （`run()` 完了後に `write_file_sync` で保存するため）。

---

## 10. クイックスタート

### Step 1: マイルストーンファイルを作成

```bash
mkdir -p .tornado
cat > .tornado/milestones.json << 'EOF'
{
  "milestones": [
    {
      "id": "m1",
      "goal": "Create a simple HTTP server with health check endpoint",
      "status": "pending",
      "tasks": []
    },
    {
      "id": "m2",
      "goal": "Add user CRUD endpoints with in-memory storage",
      "status": "pending",
      "tasks": []
    }
  ]
}
EOF
```

### Step 2: Ralph モードで実行

```bash
# プリセット構成で実行
tornado --ralph

# または設定ファイルを使って実行
tornado --ralph --config=tornado.json
```

### Step 3: 結果を確認

実行後、`.tornado/milestones.json` が更新され、各タスクの結果が記録される。

---

## 11. 設定ファイルのサンプル集

### 最小構成（Planner + Builder のみ、Verifier なし）

```json
{
  "ralph_enabled": true,
  "agents": [
    { "id": "planner", "kind": "claude-code", "role": "planner" },
    { "id": "builder", "kind": "claude-code", "role": "dev" }
  ]
}
```

> Verifier がない場合、Wave は自動承認される。

### フル構成（3エージェント + カスタム設定）

```json
{
  "project_dir": "/path/to/project",
  "review_dir": "docs/reviews",
  "ralph_enabled": true,
  "milestones_path": "milestones/plan.json",
  "max_rework_attempts": 5,
  "agents": [
    {
      "id": "planner",
      "kind": "claude-code",
      "role": "planner",
      "system_prompt": "You are an expert software architect.",
      "max_iterations": 10
    },
    {
      "id": "builder",
      "kind": "claude-code",
      "role": "dev",
      "working_dir": ".",
      "max_iterations": 15
    },
    {
      "id": "verifier",
      "kind": "codex",
      "role": "verifier",
      "max_iterations": 5
    }
  ]
}
```

### Codex を Builder に使う構成

```json
{
  "ralph_enabled": true,
  "agents": [
    { "id": "planner", "kind": "claude-code", "role": "planner" },
    { "id": "builder", "kind": "codex", "role": "dev" },
    { "id": "verifier", "kind": "claude-code", "role": "verifier" }
  ]
}
```

---

## 12. 既知の制限事項

### 12.1 Verifier フィードバックが Builder に渡されない

リワーク時、`rework_tasks()` の `_feedback` パラメータは未使用。
Builder には `"Rework: " + task.description` のみが渡され、
Verifier が指摘した具体的な修正内容は伝わらない。

**影響:** リワークの精度が低く、同じ問題が繰り返される可能性がある。

### 12.2 Wave 内タスクの並列実行は未対応

同一 Wave のタスクは設計上独立だが、現在は `for task in tasks` で順序実行。

### 12.3 途中中断時の状態保存

マイルストーンの状態保存は `RalphLoop::run()` 完了後に行われるため、
Ctrl+C で中断した場合は途中結果が失われる可能性がある。

### 12.4 マイルストーンの動的追加・削除は未対応

実行中にマイルストーンを追加・削除することはできない。
事前にファイルで定義する必要がある。

### 12.5 `--review` オプションが Ralph モードで効かない

`apply_overrides()` は `Review` ロールのエージェントのみ `--review` で上書きする。
しかし Ralph モードの Verifier は `Verifier` ロールであり `Review` ロールではないため、
`--review` は素通りして無視される。

**根本原因: `Review` と `Verifier` は別のロール値である。**

```moonbit
// types.mbt — AgentRole の定義
pub(all) enum AgentRole {
  Dev
  Review          // ← 通常モードの Reviewer 用
  Orchestrator
  Planner
  Verifier        // ← Ralph モードの Verifier 用（Review とは別の値）
}
```

`apply_overrides()` のマッチング自体は `Dev` も `Review` も同じ構造だが、
Ralph モードには `Review` ロールのエージェントが1つも存在しないため
`Review =>` のブランチを通るエージェントがいない:

```moonbit
// cli.mbt:59-72 — apply_overrides() 内のループ
for agent in config.agents {
    let kind = match agent.role {
      Dev    => dev_kind ...     // Builder (role=Dev) がここにマッチ → --dev で上書き
      Review => review_kind ...  // ← Ralph モードでは誰もここに来ない
      _      => agent.kind       // Planner (role=Planner), Verifier (role=Verifier) はここ
    }
}
```

Ralph プリセットの3エージェントがそれぞれどこにマッチするか:

```text
agent="planner"  (role=Planner)  → _ => agent.kind    変更なし
agent="builder"  (role=Dev)      → Dev => --dev の値   上書きされる
agent="verifier" (role=Verifier) → _ => agent.kind    変更なし
```

| エージェント | ロール | `--dev` | `--review` |
|------------|--------|---------|-----------|
| Planner | Planner | 無視 | 無視 |
| Builder | Dev | **適用される** | 無視 |
| Verifier | Verifier | 無視 | **無視される** |

**回避策:** Verifier（および Planner）の種類を変更するには設定ファイル (`tornado.json`) で直接指定する:

```json
{
  "agents": [
    { "id": "planner", "kind": "claude-code", "role": "planner" },
    { "id": "builder", "kind": "claude-code", "role": "dev" },
    { "id": "verifier", "kind": "claude-code", "role": "verifier" }
  ]
}
```

### 12.6 Ralph 固有の未使用設定項目

`review_interval` と `max_review_cycles` は通常モード用で、Ralph モードでは使われない。
設定ファイルに記述しても無視される。
