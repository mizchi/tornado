# ralph-tornado スキル: 計画ファイルから Ralph モード起動

**追加日**: 2026-03-07 (コマンド版)
**最終更新**: 2026-03-20 (スキル版に移行)

---

## 1. 概要

`ralph-tornado` は Markdown 形式の計画ファイルを tornado Ralph モードの入力に変換し、
バックグラウンドで起動・監視するオーケストレーションスキルである。

Claude Code の `/ralph-tornado` スキルとして動作し、以下の5フェーズパイプラインを実行する:

```
計画ファイル (Markdown)
  → Phase 1: 入力検証
  → Phase 2: 計画→マイルストーン変換
  → Phase 3: 出力ファイル生成 (milestones.json + tornado.json)
  → Phase 4: 検証・起動
  → Phase 5: 進捗モニタリング
```

### tornado ランタイムとの関係

| 層 | 担当 | 説明 |
|----|------|------|
| ralph-tornado スキル | Claude Code | 計画の変換・起動・監視 |
| tornado Ralph モード | tornado ランタイム | マイルストーン駆動の自律開発ループ |
| Agent バックエンド | Claude/Codex | 実際のコード生成・検証 |

ralph-tornado は tornado の**外側**で動作し、入力データの準備と起動・監視を担う。
tornado のランタイム（`RalphLoop::run()`）とは直接の依存関係はない。

---

## 2. CLI 引数

```
/ralph-tornado <plan-file.md> [--dev=<kind>] [--verifier=<kind>]
```

| 引数 | 説明 | デフォルト |
|------|------|----------|
| `<plan-file.md>` | 計画ファイルのパス（Markdown） | 必須 |
| `--dev=<kind>` | Builder エージェントの種類 | `codex` |
| `--verifier=<kind>` | Verifier エージェントの種類 | `claude-code` |

有効な kind 値: `claude-code`, `claude`, `claudecode`, `codex`, `api`, `mock`

---

## 3. 5フェーズパイプライン

### Phase 1: 入力検証

1. 引数を解析（計画ファイルパス + オプションフラグ）
2. 計画ファイルの存在確認
3. リポジトリルートの取得（`git rev-parse --show-toplevel`）
4. 計画ファイルの読み込み

### Phase 2: 計画→マイルストーン変換

**Step 1: 出力ディレクトリ作成 + 英訳**

1. 出力ディレクトリ名を決定（`.runs/` 配下にタイムスタンプ + 計画名）
2. 計画ファイルを英語に翻訳し `plan-en.md` として保存
   - コード識別子・ファイルパスはそのまま保持
   - この英訳版が以降の Plan Context の基準となる

**Step 2: パースと変換**

`references/parse-rules.md` の規則に従い、Markdown をパース:
- 見出しレベルでマイルストーン/タスクの階層を判定
- goal、description はすべて英語で生成
- タスクID命名規則: `m{N}-t{M}` 形式
- Wave 番号: タスクの依存関係に基づいて自動割り当て

### Phase 3: 出力ファイル生成

3つの成果物を生成:

#### 3-1. milestones-skeleton.json（中間ファイル）

`references/milestones-schema.md` のスキーマに従い、Plan Context **なし** の JSON を生成。

#### 3-2. milestones.json（Plan Context 注入）

```bash
node .claude/skills/ralph-tornado/scripts/inject-plan-context.js <output_dir>
```

`inject-plan-context.js` スクリプトが以下を自動処理:

1. **Verification Scope 指示を `goal` に追加**: Verifier がスコープ外のタスクで Wave を却下しないよう指示
2. **Plan Context を `goal` に追加**: マイルストーンの全体的な文脈を提供
3. **Plan Context を各タスクの `description` に追加**: Builder に計画全体の文脈を提供
4. **中間ファイル `milestones-skeleton.json` を削除**

> **設計意図:** tornado ランタイムの Builder は `task.description` のみを prompt として受け取り、
> milestone の goal やプロジェクトコンテキストは渡されない。
> このスクリプトで Plan Context を各タスクの description に直接注入することで、
> ランタイムの制約を回避している。

#### 3-3. tornado.json

`references/tornado-config.md` のテンプレートに従い、エージェント設定を生成。

Planner は `mock` に設定（タスクは事前定義済みのため Planning フェーズをスキップ）:

```json
{
  "ralph_enabled": true,
  "milestones_path": "<output_dir>/milestones.json",
  "max_rework_attempts": 3,
  "agents": [
    { "id": "planner", "kind": "mock", "role": "planner" },
    { "id": "builder", "kind": "<DEV_KIND>", "role": "dev", "max_iterations": 30 },
    { "id": "verifier", "kind": "<VERIFIER_KIND>", "role": "verifier", "max_iterations": 10 }
  ]
}
```

### Phase 4: 検証・起動

1. **JSON バリデーション**: `jq .` で両ファイルを検証
2. **サマリー表示**: マイルストーン数、タスク数、Wave 数、エージェント種別
3. **バックグラウンド起動**:

```bash
npx -y @ymdvsymd/tornado@latest --ralph --config=<tornado.json> --lang=ja
```

### Phase 5: 進捗モニタリング

`/loop 1m` で 1 分間隔の定期監視:
- バックグラウンドタスクの出力を `TaskOutput` で取得
- 現在のマイルストーン、Wave、タスク状態を要約
- 完了時にループを停止し最終結果を報告

---

## 4. ファイル構成

```
.claude/skills/ralph-tornado/
  SKILL.md                         # スキル定義（5フェーズパイプライン）
  references/
    milestones-schema.md           # milestones.json のスキーマ定義
    parse-rules.md                 # Markdown → マイルストーン パース規則
    tornado-config.md              # tornado.json テンプレート
  scripts/
    inject-plan-context.js         # Plan Context + Verification Scope 注入
```

### 進化の経緯

| 日付 | 変更 |
|------|------|
| 2026-03-07 | `.claude/commands/ralph-tornado.md` として作成 |
| 2026-03-07 | 引数サポート、受容基準、Plan Context 注入追加 |
| 2026-03-07 | トークン最適化（~40%削減）、plan-en.md 注入 |
| 2026-03-19 | Phase 5 進捗モニタリング追加 |
| 2026-03-20 | Verification Scope 指示追加 |
| 2026-03-20 | `.claude/skills/ralph-tornado/` にスキル化（参照ドキュメント分離） |

---

## 5. Plan Context 注入の詳細

### 問題

tornado ランタイムの Builder は `task.description` のみを prompt として受け取る:

```moonbit
// ralph_loop.mbt — Builder 呼び出し
let result = backend.run(task.description, "", fn(e) { ... })
```

- `system_prompt` は常に空文字
- milestone の `goal` は Builder に渡されない
- プロジェクトコンテキストは Builder に渡されない

### 解決策

`inject-plan-context.js` が milestones.json の生成時に Plan Context を注入:

1. `plan-en.md` の全内容を読み込み
2. 各 milestone の `goal` に追記:
   - Verification Scope 指示（Verifier がスコープ外タスクで却下しないよう）
   - Plan Context（計画ファイルの英訳全文）
3. 各 task の `description` に Plan Context を追記

これにより Builder は description 経由で計画全体の文脈を把握できる。

### Verification Scope 指示

```
## Verification Scope
IMPORTANT: You are verifying ONLY the tasks in the current wave.
Do NOT reject the wave for issues related to tasks in other waves
or milestones that haven't been implemented yet.
```

この指示により、Verifier が未実装の将来タスクを理由に Wave を却下する問題を防止する。

---

## 6. エラーハンドリング

| 状況 | 動作 |
|------|------|
| 計画ファイルが見つからない | エラーメッセージを出して終了 |
| 計画ファイルにリスト項目がない | エラーメッセージを出して終了 |
| `--dev` / `--verifier` に無効な値 | エラーメッセージを出して終了 |
| JSON バリデーション失敗 | エラーメッセージを出して終了（ファイルは残す） |
| inject-plan-context.js 実行失敗 | エラーメッセージを出して終了（中間ファイルは残す） |

---

## 7. 出力ディレクトリ構造

実行後、以下のファイルが生成される:

```
.runs/<timestamp>_<plan-name>/
  plan-en.md                # 計画ファイルの英訳版
  milestones.json           # Plan Context 注入済みマイルストーン定義
  tornado.json              # tornado 設定ファイル
```

---

## 8. ralph-tornado と tornado ランタイムの連携

```
/ralph-tornado plan.md --dev=codex
  |
  +-- Phase 1-3: 変換パイプライン
  |     plan.md → plan-en.md + milestones.json + tornado.json
  |
  +-- Phase 4: tornado 起動 (バックグラウンド)
  |     npx -y @ymdvsymd/tornado@latest --ralph --config=<絶対パス>/tornado.json --lang=ja
  |       |
  |       +-- RalphLoop::run()
  |       |     milestones.json をロード
  |       |     tasks が事前定義済み → Planning スキップ (Planner=mock)
  |       |     Wave ごとに Builder 実行 → Verifier 検証
  |       |     NeedsRework → フィードバックルーティング → 再実行
  |       |     全マイルストーン完了 → AllComplete
  |       |
  |       +-- milestones.json に結果を保存
  |
  +-- Phase 5: 進捗モニタリング (/loop 1m)
        TaskOutput で出力を読み取り、進捗をユーザーに報告
```
