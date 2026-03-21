---
name: ralph-tornado
description: >
  Markdown計画ファイルをtornado Ralphモードの入力に変換し、バックグラウンドで起動・監視するオーケストレーター。
  計画 → milestones.json + tornado.json 変換、起動、進捗監視を実行。
  "ralph", "計画ファイルから開発開始", "マイルストーン開発", "tornado起動", "plan file", "launch tornado".
arguments: plan_file:計画ファイル(Markdown)のパス
---

# ralph-tornado: 計画ファイル → tornado Ralph モード起動

## 引数

```
/ralph-tornado <plan-file.md> [--planner=<kind>] [--dev=<kind>] [--verifier=<kind>]
```

- `--planner=<kind>`: Planner agent kind。デフォルトは `claude-code`
- `--dev=<kind>`: Builder agent kind。デフォルトは `codex`
- `--verifier=<kind>`: Verifier agent kind。デフォルトは `claude-code`

`$ARGUMENTS` の内容: `$ARGUMENTS`

## オーケストレーション概要

計画ファイル (Markdown) を tornado Ralph モードの入力に変換し、バックグラウンドで起動・監視する **5フェーズパイプライン**。

1. **入力検証** — 引数解析、ファイル確認、リポジトリルート取得
2. **計画→マイルストーン変換** — 英訳、brief 抽出、`##` 見出しから milestone 配列を直接生成
3. **出力ファイル生成** — tornado.json 生成
4. **検証・起動** — JSON 検証、サマリー表示、バックグラウンド起動
5. **進捗モニタリング** — `/loop 1m` で定期監視

各フェーズを**必ず順番に**実行すること。

---

### Phase 1: 入力検証

1. `$ARGUMENTS` を解析する:
   - 最初の `--` で始まらないトークンを `PLAN_FILE` とする
   - `--planner=<value>` があれば `PLANNER_KIND` に格納（デフォルト: `claude-code`）
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

### Phase 2: 計画ファイル → brief + マイルストーン変換

**Step 1: 出力ディレクトリの作成と英訳版計画ファイルの生成**

1. ディレクトリ名を決定する（`references/parse-rules.md` のディレクトリ名生成規則に従う）
2. 出力ディレクトリを作成する
3. 計画ファイルの全内容を英語に翻訳し、出力ディレクトリに `plan-en.md` として書き出す。
   コード内の識別子やファイルパスはそのまま保持する。

**Step 2: brief 抽出**

英訳済みの計画から、`milestones.json` の `brief` に入れる短い要約を作る。抽出元は plan の Context / goals / constraints とする。

- 優先して抽出する対象:
  - `## Context`
  - ゴールを説明する導入文や要約
  - 制約、非目標、方針、設計上の制限
- `brief` は **plan goals + constraints の短い背景情報** とする
- 実装詳細の羅列や巨大な本文のコピペは避ける
- 2〜8行程度を目安に、Planner/Builder に必要な背景だけを残す
- plan 内に goals / constraints が明確に見つからない、または曖昧な場合は、推測で埋めずユーザーに確認する

**Step 3: milestone 変換**

Markdown を **`references/parse-rules.md`** の規則でパースし、`##` 見出しを milestone に変換する。

**重要: `brief`・`goal`・ディレクトリ名はすべて英語で生成する。** 計画ファイルが日本語の場合は翻訳する。コード内の識別子やファイルパスはそのまま保持する。

この skill では **task / wave 分解を行わない**。`##` 見出しはそのまま milestone になり、各 milestone は空の task 配列だけを持つ。

- `##` 見出しを milestone として扱う
- 各 milestone は `tasks: []` で初期化する
- `summary` は空文字列 `""` で初期化する
- task ID 生成、task description 展開、wave 区切り解釈は行わない
- runtime Planner agent が後で task を生成する前提で、skill 側では milestone 配列だけを作る

パース規則・goal 構成規則・ディレクトリ名生成規則の詳細は `references/parse-rules.md` を Read して参照すること。

---

### Phase 3: 出力ファイル生成

出力ディレクトリは Phase 2 Step 1 で作成済み。最終成果物は `plan-en.md`, `milestones.json`, `tornado.json` の3つ。

#### 3-1. milestones.json

**`references/milestones-schema.md`** の JSON スキーマに従い、`milestones.json` を**直接生成**する。中間 skeleton ファイルや追加の注入ステップは使わない。

生成内容:

```json
{
  "brief": "Plan goals and constraints extracted from the plan document",
  "milestones": [
    {
      "id": "m1",
      "goal": "Goal text from ## heading",
      "status": "pending",
      "summary": "",
      "tasks": []
    }
  ]
}
```

要件:

- `brief` には Phase 2 で抽出した短い背景情報を入れる
- `milestones` には `##` 見出しごとの milestone を順番どおり入れる
- 各 milestone は `status: "pending"`、`summary: ""`、`tasks: []` で初期化する
- runtime Planner agent が後で tasks を生成する前提なので、この skill では task を埋めない

スキーマの詳細は `references/milestones-schema.md` を Read して参照すること。

#### 3-2. tornado.json

**`references/tornado-config.md`** のテンプレートに従い生成する。

- Planner kind には `PLANNER_KIND` を使う
- Builder kind には `DEV_KIND` を使う
- Verifier kind には `VERIFIER_KIND` を使う

テンプレートとエージェント設定の詳細は `references/tornado-config.md` を Read して参照すること。

背景情報の受け渡しは `milestones.json` の `brief` に集約する。追加の plan 注入ステップや補助スクリプトは使わない。

---

### Phase 4: 検証・起動

1. **JSON バリデーション**: 生成した両ファイルを `jq .` で検証

2. **サマリー表示**: Plan file, Output dir, Milestones数, Planner/Builder/Verifier種別, 各マイルストーンの goal先頭行を表示する。

3. **tornado 起動**（バックグラウンド）:

   Bash ツールで以下のコマンドを `run_in_background: true` で実行する。`--log` は出力ディレクトリに ANSI エスケープコードを含まないプレーンテキストのログファイルを書き出し、実行後のレビューに使う:

   ```bash
   npx -y @ymdvsymd/tornado@latest --ralph --config=<tornado.json の絶対パス> --log=<出力ディレクトリの絶対パス>/tornado.log --lang=en
   ```

   起動後、ユーザーにタスク ID を共有する。

---

### Phase 5: 進捗モニタリング

tornado がバックグラウンドで実行中の間、`/loop` スキルを使って **1 分間隔** で進捗を監視する。

1. `/loop 1m` を起動し、以下のプロンプトを実行する:
   - `TaskOutput` でバックグラウンドの tornado タスク出力を取得
   - 最新の出力から進捗状況を要約してユーザーに共有
   - タスクが完了していたら `/loop` を停止

2. tornado 完了通知を受けたら最終結果を報告する。

---

## エラーハンドリング

- 計画ファイルが見つからない場合 → エラーメッセージを出して終了
- 計画ファイルに `##` 見出しベースの milestone が1つもない場合 → エラーメッセージを出して終了
- `brief` 抽出に必要な goals / constraints が曖昧な場合 → ユーザーに確認してから続行
- `--planner` / `--dev` / `--verifier` に無効な値が指定された場合 → エラーメッセージを出して終了
  - 有効な値: `claude-code`, `claude`, `claudecode`, `codex`, `api`, `mock`
- JSON バリデーション失敗 → エラーメッセージを出して終了（ファイルは残す）
