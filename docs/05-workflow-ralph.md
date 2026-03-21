# Tornado ワークフロー & Ralph 利用ガイド

## 1. 2つの実行モード

Tornado には2つの実行モードがある。

| 項目           | 通常モード (Heartbeat)                             | Ralph モード                       |
| -------------- | -------------------------------------------------- | ---------------------------------- |
| 終了条件       | Ctrl+C のみ（無限ループ）                          | 全マイルストーン完了で自動終了     |
| タスク生成     | 自動で次タスクを生成し続ける                       | 事前定義 or Planner が生成         |
| エージェント   | Dev + Reviewer (2体)                               | Planner + Builder + Verifier (3体) |
| 構造           | フラットなタスク列                                 | Milestone > Wave > Task の3層      |
| レビュー       | 3観点レビュー (CodeQuality, Performance, Security) | Wave 単位の統合検証                |
| フィードバック | Review の指摘を Dev に渡す                         | タスクID指定ルーティング（v0.6.0） |

通常モードの詳細は [12. 通常モード (Heartbeat Loop) 詳細](#12-通常モード-heartbeat-loop-詳細) を参照。

---

## 2. Ralph クイックスタート

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

## 3. CLI 引数

### 基本コマンド

```bash
tornado --ralph [オプション...]
```

### 利用可能なオプション

| オプション              | 説明                                                              | デフォルト                               |
| ----------------------- | ----------------------------------------------------------------- | ---------------------------------------- |
| `--ralph`               | **必須**。Ralph モードを有効化する                                | `false`                                  |
| `--config=<path>`       | 設定ファイルのパス                                                | `tornado.json`（なければプリセット使用） |
| `--dev=<kind>`          | Builder（Dev ロール）の種類を上書き                               | `claude-code`                            |
| `--review=<kind>`       | Review ロールの種類を上書き。**Ralph モードでは効かない（後述）** | `codex`                                  |
| `--lang=<auto\|ja\|en>` | エージェントの応答言語                                            | `auto`（環境変数 `LANG` から検出）       |

### エージェント種類 (`--dev`, `--review` に指定可能な値)

| 値                                      | 説明             |
| --------------------------------------- | ---------------- |
| `claude` / `claude-code` / `claudecode` | Claude Code      |
| `codex`                                 | OpenAI Codex     |
| `api`                                   | API バックエンド |
| `mock`                                  | テスト用モック   |

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

| 方法                                    | マイルストーンファイルのパス                                              |
| --------------------------------------- | ------------------------------------------------------------------------- |
| `tornado --ralph` (設定なし)            | `.tornado/milestones.json` 固定                                           |
| `tornado --ralph --config=tornado.json` | 設定ファイル内の `milestones_path`（省略時は `.tornado/milestones.json`） |
| ~~`tornado --ralph --milestones=...`~~  | **未実装（CLI フラグは存在しない）**                                      |

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

## 4. 設定ファイル (`tornado.json`)

`--config` を指定しない場合、カレントディレクトリの `tornado.json` を探す。
見つからなければ組み込みプリセット (`preset_ralph`) が使われる。

### 設定ロード順序

1. `--config=PATH` or デフォルト `tornado.json`
2. JSON パース -> ProjectConfig
3. `apply_overrides()` で CLI フラグ反映
4. `validate()` でエージェント構成チェック

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

| フィールド            | 型      | デフォルト       | 説明                                                            |
| --------------------- | ------- | ---------------- | --------------------------------------------------------------- |
| `project_dir`         | string  | `"."`            | プロジェクトルートディレクトリ                                  |
| `review_dir`          | string  | `"docs/reviews"` | レビュー出力ディレクトリ                                        |
| `ralph_enabled`       | bool    | `false`          | Ralph モード有効化（`--ralph` フラグで自動 `true`）             |
| `milestones_path`     | string? | `null`           | マイルストーンファイルパス（省略時 `.tornado/milestones.json`） |
| `max_rework_attempts` | int     | `3`              | Wave 単位のリワーク最大回数                                     |
| `max_review_cycles`   | int     | `3`              | レビューサイクル上限（Ralph では未使用）                        |
| `review_interval`     | int     | `1`              | レビュー間隔（Ralph では未使用）                                |
| `agents`              | array   | `[]`             | エージェント設定の配列                                          |

### エージェント設定フィールド

| フィールド       | 型      | デフォルト | 説明                                                            |
| ---------------- | ------- | ---------- | --------------------------------------------------------------- |
| `id`             | string  | `""`       | エージェントの一意識別子                                        |
| `kind`           | string  | `"mock"`   | `"claude-code"` / `"codex"` / `"api"` / `"mock"`                |
| `role`           | string  | `"dev"`    | `"planner"` / `"dev"` / `"builder"` / `"verifier"` / `"review"` |
| `model`          | string? | `null`     | 使用モデル名（省略可）                                          |
| `system_prompt`  | string? | `null`     | カスタムシステムプロンプト（省略可）                            |
| `working_dir`    | string  | `"."`      | 作業ディレクトリ                                                |
| `max_iterations` | int     | `10`       | エージェント内部の反復上限                                      |

> **Note:** `role` の `"builder"` は内部的に `Dev` ロールとして扱われる。
> Planner から見た Builder も `Dev` ロールのエージェントを使用する。

### プリセット

**preset_ralph()**: Ralph モード用（`--ralph` のみで起動し `tornado.json` がない場合）

| エージェント | ID         | Kind       | Role     |
| ------------ | ---------- | ---------- | -------- |
| Planner      | `planner`  | ClaudeCode | Planner  |
| Builder      | `builder`  | ClaudeCode | Dev      |
| Verifier     | `verifier` | Codex      | Verifier |

その他のデフォルト: `max_rework_attempts`: 3, `ralph_enabled`: true

**preset_default()**: 通常モード用

- Dev(ClaudeCode) + Reviewer(Codex)
- max_review_cycles: 3

### バリデーションルール

設定は起動時に検証される。以下の場合エラーになる:

- `agents` が空
- エージェント `id` が重複
- `Dev` ロールのエージェントが存在しない
- `ralph_enabled: true` なのに `Planner` ロールのエージェントがない
- `review_interval` が 1 未満

---

## 5. マイルストーンファイル (`.tornado/milestones.json`)

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

| フィールド     | 型     | 必須 | 説明                                                  |
| -------------- | ------ | ---- | ----------------------------------------------------- |
| `id`           | string | Yes  | マイルストーンの一意識別子（例: `"m1"`, `"m2"`）      |
| `goal`         | string | Yes  | マイルストーンの目標を自然言語で記述                  |
| `status`       | string | Yes  | `"pending"` / `"in_progress"` / `"done"` / `"failed"` |
| `current_wave` | int    | No   | 現在の Wave 番号（デフォルト: 0）                     |
| `tasks`        | array  | No   | タスクの配列（空の場合 Planner が自動生成）           |

### タスクフィールド

| フィールド    | 型      | 必須 | Builder に渡されるか  | 説明                                                                           |
| ------------- | ------- | ---- | --------------------- | ------------------------------------------------------------------------------ |
| `id`          | string  | Yes  | No                    | タスクID（例: `"m1-t1"`, `"m1-t2"`）。ログ表示と Verifier への結果紐付けに使用 |
| `description` | string  | Yes  | **Yes（唯一の入力）** | Builder の prompt としてそのまま渡される。後述の「description の書き方」を参照 |
| `wave`        | int     | Yes  | No                    | 所属する Wave 番号（0始まり）。実行順序制御に使用                              |
| `status`      | string  | Yes  | No                    | `"pending"` / `"in_progress"` / `"done"` / `"failed"`                          |
| `result`      | string? | No   | No（出力側）          | タスク実行結果（実行後に自動設定される）                                       |
| `plan_doc`    | string? | No   | No                    | 計画ドキュメント（**どこからも読まれておらず現在未使用**）                     |

### description の書き方

`description` は Builder（Claude Code / Codex）に**そのまま prompt として渡される**唯一の入力である。
system_prompt は空文字固定で、milestone の goal やプロジェクトコンテキストは渡されない。

```moonbit
// ralph_loop.mbt:155-156 — Builder 呼び出しの実装
let result = backend.run(
    task.description,   // <- これだけが prompt になる
    "",                 // <- system_prompt は常に空
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

> **リワーク時の注意:** リワーク時は `task.description + "\n\nFeedback from verifier:\n" + feedback` が
> prompt になる。Verifier のフィードバックはタスクID指定でルーティングされるため、
> 各タスクは自身に関連するフィードバックのみ受け取る（v0.6.0）。

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

## 6. 3層構造: Milestone > Wave > Task

```
Milestone (目標単位)
  +-- Wave 0 (先行タスク群)
  |     +-- Task m1-t1
  |     +-- Task m1-t2
  +-- Wave 1 (Wave 0 の完了・検証後に実行されるタスク群)
  |     +-- Task m1-t3
  |     +-- Task m1-t4
  +-- Wave 2 ...
```

- **Milestone**: 達成すべき目標。複数定義でき、順番に処理される。
- **Wave**: タスクのグループ。Wave 0 → Wave 1 → ... と順序実行される。
- **Task**: 個別の実行単位。同一 Wave 内のタスクも現在は順序実行される。

### Wave の役割

Wave はコード上で以下の3つの機能を担っている:

**1. Verifier 検証のスコープ** (`ralph_loop.mbt:174-176`)

Verifier は Wave 単位で呼ばれる。Milestone 全体ではなく、**その Wave のタスク結果だけ**が検証対象として渡される。これにより、問題の特定が容易になる。

**2. Rework のスコープ** (`ralph_loop.mbt:234`)

再作業も Wave 内に閉じる。Wave 0 の rework が Wave 1 のタスクに波及しない。

**3. 失敗時の早期中断（フェイルファスト）** (`ralph_loop.mbt:116-118`)

Wave が失敗したら後続 Wave を実行せずに Milestone を失敗とする。Wave 0 が壊れている状態で Wave 1 のコストを払わずに済む。

```
Wave 0 実行 → Wave 0 検証 → [失敗なら即中断]
                           → [成功なら] Wave 1 実行 → Wave 1 検証 → ...
```

つまり Wave の実質的な意義は **「検証と失敗の境界線」** であり、段階的な品質ゲートとして機能している。

---

## 7. 実行フロー

### 7.1 起動シーケンス

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

### 7.2 ループ実行フロー

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

### 7.3 アーキテクチャ図

```
CLI (--ralph)
  |
  parse_cli_args()
  |
  run_ralph()
    |-- Load config (tornado.json or preset_ralph)
    |-- apply_overrides() [--dev, --review, --lang]
    |-- Load milestones (.tornado/milestones.json)
    `-- RalphLoop::new()
          |-- backends[Planner, Builder, Verifier]
          |-- MilestoneManager
          `-- run()
                |-- LoadingMilestones
                |     `-- next_pending_milestone() loop
                |           `-- run_milestone(m)
                |                 |-- Planning (Planner agent)
                |                 |     `-- parse_planner_output() -> WAVE
                |                 `-- while has_undone_tasks()
                |                       `-- run_wave(wave_num)
                |                             |-- Executing (Builder agent)
                |                             |     `-- collect_wave_results()
                |                             `-- verify_wave() [recursive]
                |                                   |-- Verifying (Verifier agent)
                |                                   |-- Approved -> next wave
                |                                   |-- NeedsRework(items) -> Reworking
                |                                   |     `-- rework_tasks(feedback routing)
                |                                   |           |-- items にタスクID prefix あり
                |                                   |           |     -> 該当タスクのみリワーク
                |                                   |           `-- prefix なし
                |                                   |                 -> 全タスクにブロードキャスト
                |                                   |     `-- verify_wave(attempt+1)
                |                                   `-- MilestoneFailed -> stop
                `-- AllComplete
```

### 7.4 状態マシン

RalphLoop の状態遷移図は [01-architecture.md のセクション 4](./01-architecture.md) を参照。

---

## 8. 3大エージェントの動作

### 8.1 Planner エージェント

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

### 8.2 Builder エージェント (Dev ロール)

**役割:** 個々のタスクを実行する。

**入力:** `task.description` がそのままプロンプトとして渡される。

**リワーク時の入力（v0.6.0 で改善）:**

```
task.description + "\n\nFeedback from verifier:\n" + "- フィードバック1\n- フィードバック2\n"
```

Verifier のフィードバックはタスクID指定でルーティングされる:
- `"m1-t1: fix error handling"` → タスク `m1-t1` のリワーク時のみ含まれる
- タスクIDプレフィクスがないフィードバック → 全タスクにブロードキャスト

### 8.3 Verifier エージェント

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

| 出力タグ                                   | 判定               | 動作                       |
| ------------------------------------------ | ------------------ | -------------------------- |
| `<wave_approved>`                          | 承認               | 次の Wave へ進む           |
| `<needs_rework>...</needs_rework>`         | 要リワーク         | 失敗タスクを再実行         |
| `<milestone_failed>...</milestone_failed>` | 失敗               | マイルストーンを失敗とする |
| タグなし                                   | 承認（デフォルト） | 次の Wave へ進む           |

**`<needs_rework>` の内容フォーマット:**
```
<needs_rework>
m1-t1: エラーハンドリングを追加してください
m1-t2: テストが不足しています
</needs_rework>
```
改行区切りで複数のリワーク指示を記述できる。

---

## 8A. Planner のタスク分割メカニズム詳解

Planner がマイルストーンをタスクに分割する方法には **2つのパス** がある。
どちらのパスも最終的に同じ `milestones.json` のタスク構造を生成するが、タスクの粒度・品質・文脈の豊富さが異なる。

```
パス1: ralph-tornado スキル（事前変換）
  Markdown計画ファイル
    → parse-rules.md に従いパース
    → milestones-skeleton.json 生成
    → inject-plan-context.js で文脈注入
    → milestones.json（タスク事前定義済み）
    → tornado 起動時に Planner はスキップ

パス2: ランタイム Planner AI（動的生成）
  milestones.json の tasks が空の場合
    → Planner AI にプロンプト送信
    → AI が WAVE 形式テキストを出力
    → parse_plan_text() で構造化
    → milestone.tasks に代入
```

### 8A.1 パス1: ralph-tornado スキルによる事前変換

`/ralph-tornado <plan.md>` で呼び出される 5 フェーズパイプライン（`.claude/skills/ralph-tornado/SKILL.md`）。
人間が書いた Markdown 計画ファイルを milestones.json に変換する。

#### Markdown パース規則

`references/parse-rules.md` に定義された規則で Markdown をパースする:

| Markdown 要素               | 変換先                          | 備考                             |
| --------------------------- | ------------------------------- | -------------------------------- |
| `# 見出し` (最初の H1)      | プロジェクト名 / ディレクトリ名 | kebab-case 化、50文字以内        |
| `## 見出し`                 | マイルストーンの `goal`         | 1つの `##` = 1つのマイルストーン |
| `##` がファイルに存在しない | ファイル全体 = 1マイルストーン  |                                  |
| `-` / `*` / `N.` リスト項目 | タスクの `description`          | Builder への唯一の入力           |
| `###` サブ見出し            | Wave 区切り                     | wave を +1                       |

**Wave 割り当ての具体例:**

```markdown
## 認証システムの構築        ← マイルストーン m1, goal

- ユーザーテーブルを作成     ← m1-t1, wave: 0
- マイグレーション作成       ← m1-t2, wave: 0

### API 実装                 ← wave 区切り（wave +1）

- 認証エンドポイント実装     ← m1-t3, wave: 1
- JWT ミドルウェア追加       ← m1-t4, wave: 1

### テスト                   ← wave 区切り（wave +1）

- 統合テスト作成             ← m1-t5, wave: 2
```

→ 結果: 1 マイルストーン, 5 タスク, 3 Wave (0, 1, 2)

#### description テンプレート

ralph-tornado スキルが生成する `description` は以下のテンプレートに従う:

```
## Task
<具体的な実装指示。ファイルパス・期待動作・実装詳細を含める>

## Acceptance Criteria
- [ ] File exists: <path>
- [ ] <path> contains: <expected content>
- [ ] Run: <command> → <expected result>
```

Acceptance Criteria の3種は Builder が自己検証できる形式に限定されている。
これにより、Builder は実装後にセルフチェックを行い、Verifier 検証前に品質を確保できる。

#### inject-plan-context.js による文脈注入

スキルはまず Plan Context **なし** の `milestones-skeleton.json` を生成し、
その後 `scripts/inject-plan-context.js` が以下を自動注入する:

```
[inject-plan-context.js の処理]

入力:
  - milestones-skeleton.json (タスク定義済み、Plan Context なし)
  - plan-en.md (計画ファイルの英訳版)

処理:
  milestone.goal += Verification Scope 指示 + Plan Context (plan-en.md 全文)
  task.description += Plan Context (plan-en.md 全文)

出力:
  - milestones.json (文脈注入済み)
  - milestones-skeleton.json は削除
```

**Verification Scope 指示** は Verifier が Wave 単位で検証する際に、
他の Wave のタスクが未実装であることを理由に reject しないよう誘導する指示文:

```
## Verification Scope
This milestone may be split into multiple waves. Each wave is verified independently.
Verify ONLY the tasks listed in Wave Results. Do NOT reject a wave because
tasks mentioned in the Plan Context are not yet implemented — they belong to other waves
and will be verified separately.
```

**Plan Context** は計画ファイル全文を `## Plan Context` セクションとして追加する。
これにより Builder は実装時に全体像を参照でき、Verifier はゴール整合性を判断できる。

#### パス1 の特徴

- **タスク粒度を人間が制御できる**: Markdown のリスト項目の書き方で粒度が決まる
- **description が詳細**: テンプレートに従った構造化された指示 + Acceptance Criteria
- **Plan Context が注入される**: Builder と Verifier の両方が全体像を把握
- **Planner AI を経由しない**: タスクが事前定義されているため、ランタイムの Planning フェーズはスキップ

### 8A.2 パス2: ランタイム Planner AI による動的生成

milestones.json の `tasks` 配列が空のマイルストーンに対して実行される。

#### 発動条件

```moonbit
// ralph_loop.mbt:72-107
if milestone.tasks.is_empty() {
    // Planner AI を実行してタスクを生成
    let tasks = planner.plan(milestone, backend, "", mgr)
    milestone.tasks = tasks
}
// tasks が既にある場合 → Planning フェーズはスキップ
```

#### プロンプト構築 (`build_plan_prompt`)

`planner.mbt:16-51` でプロンプトを組み立てる:

```
You are a Planner agent. Respond in English. (--lang=ja なら Japanese)

## Milestone
ID: m1
Goal: Build authentication system

## Project Context
(project_context が渡された場合のみ。現時点では空文字が渡される)

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

AI のシステムプロンプトは固定:
```
You are a planning agent that breaks down milestones into executable tasks.
```

**制約と特徴:**
- `project_context` は現在空文字固定（`ralph_loop.mbt:85`）。将来的にプロジェクト情報を渡す余地がある
- プロンプトにはタスク数・粒度の上下限指示がない → AI の判断に委ねられる
- Wave の意味（独立性・依存性）は説明されるが、具体的な分割戦略の指示はない

#### AI 出力のパースアルゴリズム (`parse_plan_text`)

`milestone.mbt:325-363` に実装された行単位パーサー:

```
入力: AI が出力したテキスト（WAVE 形式）
出力: Array[RalphTask]

アルゴリズム:
  current_wave = 0
  for line in split_lines(output):
    trimmed = trim(line)
    if trimmed is empty → skip

    if has_wave_prefix(trimmed):          // "WAVE N:" / "wave N:" / "Wave N:"
      current_wave = parse_wave_number()  // "WAVE " の後の数字を抽出
      continue

    desc = parse_list_item(trimmed)       // 番号付き or ダッシュリスト
    if desc is not empty:
      id = gen_task_id(milestone_id)      // "m1-t1", "m1-t2", ...
      tasks.push(RalphTask {
        id, description: desc, wave: current_wave,
        status: Pending, result: None, plan_doc: None
      })

  return tasks
```

#### WAVE ヘッダー認識

```moonbit
// milestone.mbt:402-404
fn has_wave_prefix(s : String) -> Bool {
  s.has_prefix("WAVE ") || s.has_prefix("wave ") || s.has_prefix("Wave ")
}
```

- 大文字・小文字・混合の3パターンのみ認識
- `WAVE` と数字の間にスペースが必須（`WAVE0:` は認識しない）
- コロン `:` は必須ではない（`WAVE 0` でも認識する）

#### リスト項目認識

```moonbit
// milestone.mbt:425-448
fn parse_list_item(s : String) -> String {
  // パターン1: "N. description" (番号付きリスト)
  //   数字 → ドット → スペース → description

  // パターン2: "- description" (ダッシュリスト)
  //   ダッシュ → スペース → description

  // どちらにもマッチしない → 空文字を返す (スキップ)
}
```

- `*` (アスタリスクリスト) は認識**されない**（パス2 の制限）
- WAVE ヘッダーでもリスト項目でもない行は無視される（AI の補足テキスト等）
- description はトリミング後そのまま `RalphTask.description` になる

#### タスク ID 生成

```moonbit
// milestone.mbt:120-127
pub fn gen_task_id(self : MilestoneManager, milestone_id : String) -> String {
  let id = "{milestone_id}-t{self.next_task_id}"  // 例: "m1-t1"
  self.next_task_id += 1
  id
}
```

- `next_task_id` は MilestoneManager 全体で共有されるグローバルカウンター
- JSON からロード時は `max(全タスクの番号) + 1` から再開（`milestone.mbt:20-39`）
- マイルストーン間で通し番号（m1 のタスクが t1-t3 なら、m2 の最初のタスクは t4）

#### パス2 の特徴

- **タスク粒度は AI 任せ**: プロンプトに粒度制約がないため、AI の判断で決まる
- **description が簡素**: AI が出力した1行テキストがそのまま description になる
- **Plan Context がない**: project_context は現在空文字固定
- **Wave 割り当ては AI が決定**: AI が `WAVE N:` ヘッダーで明示的に指定

### 8A.3 2つのパスの比較

| 観点               | パス1: ralph-tornado スキル              | パス2: ランタイム Planner AI     |
| ------------------ | ---------------------------------------- | -------------------------------- |
| 発動タイミング     | tornado 起動前（スキルが事前生成）       | tornado 実行中（tasks が空の時） |
| タスク粒度の決定者 | 人間（Markdown の書き方）                | AI（プロンプトへの応答）         |
| description の品質 | 構造化テンプレート + Acceptance Criteria | AI の1行テキスト                 |
| Plan Context       | あり（inject-plan-context.js で注入）    | なし（project_context = 空文字） |
| Wave 割り当て      | `###` サブ見出しの位置                   | AI が `WAVE N:` で明示           |
| `*` リスト認識     | parse-rules.md では可（スキルが解釈）    | parse_plan_text では不可         |
| Verification Scope | あり（Verifier の誤 reject 防止）        | なし                             |
| 再現性             | 高い（同じ Markdown → 同じ JSON）        | 低い（AI の応答に依存）          |

### 8A.4 実行実績からの分析

`.runs/` ディレクトリの実際のラン結果:

| ラン                                           | マイルストーン数 | タスク構成                                 | パス  |
| ---------------------------------------------- | ---------------- | ------------------------------------------ | ----- |
| `adr-0001-4-perspective-parallel-verification` | 4                | m1: 2T/2W, m2: 2T/1W, m3: 4T/3W, m4: 1T/1W | パス1 |
| `pass-verifier-feedback-to-builder`            | 2                | m1: 1T/1W, m2: 2T/2W                       | パス1 |
| `add-log-flag-for-file-logging`                | -                | -                                          | パス1 |
| `fix-verifier-silent-approval-bug`             | -                | -                                          | パス1 |

**観察:**
- 実際の全ランはパス1（ralph-tornado スキル）を使用している
- マイルストーンあたりのタスク数は 1-4 と少数
- Wave 数は 1-3 で、深い依存チェーンは避けられている
- 1 Wave あたり 1-2 タスクが典型的

### 8A.5 Wave 割り当てのセマンティクス

両パスで共通する Wave の意味:

```
Wave 0: 基盤タスク（他に依存しない）
  例: スキーマ作成、型定義、設定ファイル生成

Wave 1: Wave 0 の成果物に依存するタスク
  例: API 実装（スキーマに依存）、テスト（型定義に依存）

Wave 2+: より後段の依存タスク
  例: 統合テスト（API + スキーマの両方に依存）
```

**Wave はコード実行上の意味:**
1. **実行順序**: Wave 0 → 検証 → Wave 1 → 検証 → Wave 2 → ...
2. **検証スコープ**: 各 Wave は独立に検証される
3. **フェイルファスト**: Wave N が失敗したら Wave N+1 は実行しない
4. **リワークスコープ**: リワークは同一 Wave 内に閉じる

**Wave 内のタスク実行順序:**
同一 Wave 内のタスクは「独立に実行可能」と定義されているが、
現在の実装では `for task in tasks` による**順序実行**（`ralph_loop.mbt:152`）。
並列実行は未実装（[14.2 既知の制限事項](#142-wave-内タスクの並列実行は未対応)）。

### 8A.6 粒度に関する考察

タスク粒度に関するハードコードされた制約はコードベースに存在しない:

- **最小タスク数**: 制約なし（1マイルストーン1タスクも可）
- **最大タスク数**: 制約なし
- **description の最大長**: 制約なし
- **Wave 数の上限**: 制約なし
- **タスク自動分割アルゴリズム**: 存在しない（複雑なタスクの自動細分化はしない）

粒度を制御する方法:

| 方法                                    | パス  | 効果                                          |
| --------------------------------------- | ----- | --------------------------------------------- |
| Markdown のリスト項目を細かく書く       | パス1 | 直接的に粒度を決定                            |
| `###` サブ見出しで Wave を分ける        | パス1 | 依存関係を明示的に表現                        |
| milestone の goal を詳細に書く          | パス2 | AI がより具体的なタスクを生成する傾向         |
| planner の system_prompt をカスタマイズ | パス2 | tornado.json で設定可能（ただし現在は固定文） |
| tasks を手動で milestones.json に記述   | 直接  | 完全な制御（Planner をバイパス）              |

---

## 9. エージェント間データ受け渡しとフィードバックルーティング

### 9.1 Planner -> Builder

WAVEテキスト形式:
```
WAVE 0:
1. Create database schema
2. Write migration scripts

WAVE 1:
1. Build API handlers
2. Add authentication
```

パース: `MilestoneManager::parse_planner_output()` が
WAVE ヘッダーと番号付き/箇条書きリストを解析

### 9.2 Builder -> Verifier

タスク結果の配列:
```
[(task_id: "m1-t1", result: "Schema creation output..."),
 (task_id: "m1-t2", result: "Migration output...")]
```

### 9.3 Verifier -> RalphLoop

XMLタグベース判定:
- `<wave_approved>` -> Approved
- `<needs_rework>m1-t1: fix error\nm1-t2: add validation</needs_rework>` -> NeedsRework
- `<milestone_failed>Architecture fundamentally flawed</milestone_failed>` -> Failed

### 9.4 RalphLoop -> Builder (リワーク時)

v0.6.0 でフィードバックルーティングを実装:

**フィードバックマッチング:** 各フィードバック項目がタスクIDプレフィクスを持つか判定
- `"m1-t1: fix error handling"` → タスク `m1-t1` にマッチ（コロン区切り）
- `"m1-t1 needs better validation"` → タスク `m1-t1` にマッチ（スペース区切り）

**ターゲット指定 vs ブロードキャスト:**
- いずれかのフィードバックがタスクIDにマッチ → マッチしたタスクのみ `Pending` にリセット
- どのフィードバックもタスクIDにマッチしない → 全 `Done` タスクを `Pending` にリセット（フォールバックブロードキャスト）

**プレフィクス除去:** `strip_task_feedback_prefix()` がタスクIDプレフィクスを除去
- `"m1-t1: fix error handling"` → `"fix error handling"`

**リワークプロンプト構築:**
```
task.description + "\n\nFeedback from verifier:\n" + "- feedback1\n- feedback2\n"
```

> **通常モードとの一貫性:** 通常モードの `run_review()` も同様に
> `task + "\n\nFeedback from review:\n" + feedback` を渡している。

---

## 10. 制御パラメータと終了条件

### 10.1 制御パラメータ

| パラメータ                      | デフォルト | 効果                                              |
| ------------------------------- | ---------- | ------------------------------------------------- |
| `max_rework_attempts`           | 3          | Wave ごとのリワーク最大回数。超過すると強制承認。 |
| `max_iterations` (エージェント) | 10         | 各エージェント内部の反復上限                      |

### 10.2 終了条件

| レベル        | 終了条件                         | 動作                            |
| ------------- | -------------------------------- | ------------------------------- |
| Milestone     | next_pending_milestone() == None | AllComplete                     |
| Wave          | has_undone_tasks() == false      | MilestoneComplete               |
| Rework        | attempt >= max_rework_attempts   | 強制承認                        |
| Milestone失敗 | `<milestone_failed>` 検出        | milestone.status = Failed, 次へ |

### 10.3 リワーク動作の詳細

1. Verifier が `NeedsRework(items)` を返す（items は `["m1-t1: fix error", "m1-t2: add tests"]` 形式）
2. `rework_tasks()` がフィードバックをルーティング:
   - 各フィードバック項目のタスクIDプレフィクスを判定（`"m1-t1:"` or `"m1-t1 "` 形式）
   - マッチするタスクのみ `Pending` にリセット（ターゲット指定モード）
   - マッチするタスクがない場合は全 `Done` タスクを `Pending` にリセット（ブロードキャストモード）
3. 各タスクに対し、関連するフィードバックを含むリワークプロンプトで再実行
4. 再度 `verify_wave()` を呼び出し（attempt + 1）- **再帰呼び出し**
5. `attempt >= max_rework_attempts` の場合 → 強制承認（`true` を返す）
6. 再び `NeedsRework` なら上記を繰り返す

通常モードの終了条件・制御パラメータは [12. 通常モード詳細](#12-通常モード-heartbeat-loop-詳細) を参照。

---

## 11. 永続化とレジューム

### JSON 形式 (.tornado/milestones.json)

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

### API

- `MilestoneManager::load_from_json()` でロード
- `MilestoneManager::to_json()` でシリアライズ
- ロード時に `max(task_id)` から `next_task_id` を復元

### レジューム

マイルストーンファイルにはタスクの `status` が保存されるため、
中断後に再実行すると `pending` / `in_progress` のマイルストーンから処理が再開される。

- `status: "done"` のマイルストーンはスキップされる
- `status: "failed"` のマイルストーンもスキップされる
- `status: "pending"` / `"in_progress"` のマイルストーンが処理対象

> **Note:** 途中で Ctrl+C した場合は保存されない可能性がある
> （`run()` 完了後に `write_file_sync` で保存するため）。

---

## 12. 通常モード (Heartbeat Loop) 詳細

通常モードは `run_repl()` 内の **無限ループ** で動作する。
`Orchestrator::run()` は呼ばれず、`run_dev()` と `run_review()` を直接呼ぶ。
終了は **Ctrl+C のみ**。Approved でも自動的に次タスクを生成して回り続ける。

### 12.1 ループ構造

```
CLI (tornado plan.md --dev=codex --review=claude)
  -> run_repl()
    while true {                          // Ctrl+C まで永久に回る
      1. check_interrupt()                // ユーザー入力チェック
      2. run_dev(task)                    // Devエージェント実行
      3. if dev_since_review < review_interval:
           build_next_task() -> continue  // レビューせず次のdev
      4. run_review(3 perspectives)       // 3観点レビュー
      5. match result:
           Approved  -> build_next_task() // 自動で次タスク生成 -> continue
           Rejected  -> ユーザー入力待ち  // interrupt polling -> continue
    }
```

**重要な特性:**
- `review_interval` で N 回 dev してから 1 回 review（デフォルト: 1）
- Approved 後は `build_next_task()` / `build_continuation_task()` で自動継続
- Rejected 時は `check_interrupt()` でユーザー入力をポーリング待ち
- セッション状態を `.tornado/session.json` に毎イテレーション保存（resume 可能）
- `--rlm` フラグで improvement loop mode（measure -> improve -> verify -> commit/revert）
- トークン使用量・コストを per-iteration / cumulative で追跡

> **Note:** `src/orchestrator/orchestrator.mbt` には `Orchestrator::run()` メソッドが
> 定義されている（Decompose -> Assign -> Execute -> Review -> Iterate -> Finalize の
> 6フェーズ制御）が、**現在の `run_repl()` からは使われていない**。

### 12.2 アーキテクチャ図

```
CLI (tornado plan.md --dev=codex --review=claude)
  |
  parse_cli_args()
  |
  run_repl()
    |-- Load config (tornado.json or preset_default)
    |-- apply_overrides() [--dev, --review, --lang]
    |-- Create backends (Dev, Reviewer)
    |-- Resume session? (.tornado/session.json)
    |-- Get initial task (plan file / prompt / TODO files)
    |-- start_stdin_watcher()
    `-- while true {                          // INFINITE LOOP (Ctrl+C to stop)
          |-- iteration++
          |-- check_interrupt()               // user input from .tornado/interrupt.txt
          |-- save_session(phase: "dev")
          |-- run_dev(dev_id, task)            // Dev agent execution
          |     `-- backend.run(task, on_event) -> dev_result
          |-- if dev_result empty -> continue
          |-- if dev_since_review < review_interval
          |     `-- build_next_task() -> continue  // skip review
          |-- save_session(phase: "review")
          |-- run_review(task, dev_output)     // 3-perspective review
          |     |-- ReviewAgent::review()
          |     |-- if NeedsChanges:
          |     |     `-- while cycle < max_cycles:
          |     |           run_dev(feedback) -> re-review()  // rework loop
          |     `-- -> Approved(summary) or Rejected(reason)
          |-- save_session(phase: "idle")
          `-- match result:
                Approved  -> build_next_task() -> continue
                Rejected  -> poll check_interrupt() until user input -> continue
        }
```

### 12.3 レビューサイクル

#### run_review() 内の rework ループ

```
run_review(dev_id, reviewer_id, backends, task, dev_output, max_cycles, ...)
  -> ReviewAgent::review(task, backend)  // 3観点レビュー
     -> CodeQuality, Performance, Security -> merge verdict
  -> match verdict:
       Approved -> ReviewOutcome::Approved
       NeedsChanges(items) ->
         while cycle < max_cycles {       // rework ループ (max_review_cycles)
           feedback = items -> "- item1\n- item2\n"
           rework_task = task + feedback
           current_output = run_dev(rework_task)  // Dev に feedback 付きで再実行
           re-review(current_output)
           if Approved -> return Approved
           if Rejected -> return Rejected
           // NeedsChanges -> continue loop
         }
         -> NeedsChanges exhausted -> ReviewOutcome::Approved(latest_summary)
       Rejected -> ReviewOutcome::Rejected
```

**通常モードでは review feedback が Dev に渡される** (Ralph と異なる点):
- `run_review()` 内で `NeedsChanges(items)` を feedback 文字列に変換
- `run_dev()` に `task + "\n\nFeedback from review:\n" + feedback` を渡す

#### 3観点レビュー

```
ReviewAgent::review(task, backend)
  -> CodeQuality: 可読性、命名、関心の分離、エラーハンドリング
  -> Performance: 時間/空間計算量、N+1クエリ、キャッシング
  -> Security: 入力バリデーション、インジェクション、認証
  -> merge: 最初のRejected = 全体Rejected, else NeedsChanges統合
```

#### レビュー プロンプト構造

```
## Task
[task description]

## Agent Output
[agent output]

## Review Focus: [Perspective]
- [aspect 1]
- [aspect 2]

## Important
Your job is to identify issues as TODO list -- do NOT fix them.

## Instructions
Respond with EXACTLY ONE:
- <approved>
- <needs_changes>item1, item2</needs_changes>
- <rejected>reason</rejected>
```

### 12.4 終了条件と制御パラメータ

| 状態           | 終了条件                           | 動作                                 |
| -------------- | ---------------------------------- | ------------------------------------ |
| 外側ループ     | **Ctrl+C のみ**                    | `while true` で永久に回る            |
| Dev実行        | run_dev() 完了                     | 出力が空なら review skip             |
| Review skip    | dev_since_review < review_interval | build_next_task() で次 dev           |
| Review内rework | cycle >= max_review_cycles         | rework 打ち切り                      |
| Approved       | 自動                               | build_next_task() で次イテレーション |
| Rejected       | ユーザー入力受領                   | check_interrupt() polling            |

```
通常モード制御パラメータ:
  max_review_cycles: 3       run_review() 内の rework 上限
  review_interval: 1         N回 dev したら 1回 review
```

> **Note:** 通常モードの外側ループ自体には終了条件がない。
> `max_review_cycles` は `run_review()` 内の rework サイクル上限であり、
> 外側ループの終了には影響しない。

---

## 13. 設定ファイルサンプル集

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

## 14. 既知の制限事項と残存課題

### 14.1 ~~Verifier フィードバックが Builder に渡されない~~ → v0.6.0 で解決済み

**v0.6.0 で実装完了。** `rework_tasks()` はターゲット指定のフィードバックルーティングを実装:

- Verifier の `NeedsRework` フィードバックはタスクID指定で各タスクにルーティング
- タスクIDプレフィクスがない汎用フィードバックは全タスクにブロードキャスト
- リワークプロンプト: `task.description + "\n\nFeedback from verifier:\n" + feedback`
- 5つのユニットテストで動作を検証済み（`ralph_loop_test.mbt`）

### 14.2 Wave 内タスクの並列実行は未対応

同一 Wave のタスクは設計上独立だが、現在は `for task in tasks` で順序実行。

### 14.3 途中中断時の状態保存

マイルストーンの状態保存は `RalphLoop::run()` 完了後に行われるため、
Ctrl+C で中断した場合は途中結果が失われる可能性がある。

### 14.4 マイルストーンの動的追加・削除は未対応

実行中にマイルストーンを追加・削除することはできない。
事前にファイルで定義する必要がある。

### 14.5 `--review` オプションが Ralph モードで効かない

`apply_overrides()` は `Review` ロールのエージェントのみ `--review` で上書きする。
しかし Ralph モードの Verifier は `Verifier` ロールであり `Review` ロールではないため、
`--review` は素通りして無視される。

**根本原因: `Review` と `Verifier` は別のロール値である。**

```moonbit
// types.mbt — AgentRole の定義
pub(all) enum AgentRole {
  Dev
  Review          // <- 通常モードの Reviewer 用
  Orchestrator
  Planner
  Verifier        // <- Ralph モードの Verifier 用（Review とは別の値）
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
      Review => review_kind ...  // <- Ralph モードでは誰もここに来ない
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

| エージェント | ロール   | `--dev`        | `--review`     |
| ------------ | -------- | -------------- | -------------- |
| Planner      | Planner  | 無視           | 無視           |
| Builder      | Dev      | **適用される** | 無視           |
| Verifier     | Verifier | 無視           | **無視される** |

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

### 14.6 Ralph 固有の未使用設定項目

`review_interval` と `max_review_cycles` は通常モード用で、Ralph モードでは使われない。
設定ファイルに記述しても無視される。

### 14.7 Verifier サイレント承認バグ

Verifier バックエンドが障害を起こした場合（レートリミット、ネットワークエラー、クラッシュ等）、
結果は `Approved` にフォールバックする（`verifier.mbt:107`）。
Review モジュールでは同様のバグが修正済み（`Rejected` を返すように変更）だが、
Verifier にはまだ適用されていない。

### 14.8 Orchestrator モジュールの未使用

- `src/orchestrator/orchestrator.mbt` に 6 フェーズ制御の `Orchestrator::run()` が定義されている
- しかし `run_repl()` からは呼ばれず、代わりに独自の `while true` ループが使われている
- `OrchestratorCallbacks` 型は Ralph ループのみで利用
- Orchestrator モジュール自体のテスト (`orchestrator_test.mbt`) は存在するが、
  実際のランタイムパスではデッドコードになっている可能性がある

### 14.9 その他

- Wave 内タスクの順序実行: 同一 Wave 内のタスクは `for task in wave_tasks` で順序実行される。Wave の主な役割は検証スコープとフェイルファストの境界であり、並列化はコードベース上で意図されていない
- `review_interval` が Config で定義されるが Ralph では未使用
- `current_wave` フィールドが resume 機能の準備か不明
- プログレッシブなマイルストーン追加/削除は未対応

---

## 15. 機能進化 (コミット履歴)

| Phase | コミット        | 日付       | 機能                                                           |
| ----- | --------------- | ---------- | -------------------------------------------------------------- |
| 1     | 54cab0c         | 2026-02-20 | 基盤: Orchestrator (Decompose -> Assign -> Execute -> Review)  |
| 2     | 2da99c4-4a0af97 | 2026-02-20 | 自律化: Iteration, 3-perspective review                        |
| 3     | b82f97d-cbea064 | 2026-02-20 | 改善: RLM mode, --lang                                         |
| 4     | f66a8cd         | 2026-03-02 | Ralph: Milestone-driven autonomous development                 |
| 5     | 9ef81d8-5fff019 | 2026-03-07 | ドキュメント: docs/00-06 作成                                  |
| 6     | e9063b4-825b08e | 2026-03-07 | ralph-tornado: コマンド → Plan Context注入 → トークン最適化    |
| 7     | 64b65b3         | 2026-03-20 | フィードバックルーティング: rework_tasks() に実装 + 5テスト    |
| 8     | 79ffad4         | 2026-03-20 | パッケージ名変更: @mizchi/tornado → @ymdvsymd/tornado (v0.6.0) |
| 9     | d10235a         | 2026-03-20 | ralph-tornado スキル化: コマンドから `.claude/skills/` へ移行  |
