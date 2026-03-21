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

英訳済みの計画から、`milestones.json` の `brief` に入れる情報セクションを収集する。

`references/parse-rules.md` の情報セクション判定規則に従い、セマンティック一致する `##` セクションの**全文**を `brief` に含める（要約しない）。

- `#`（H1）と最初の `##` の間のテキストも `brief` に含める
- 情報セクションの全内容を漏れなく保持する
- 要約や切り詰めは行わない
- 情報セクションが無い場合、`brief` は空文字列

**Step 3: milestone 変換**

Markdown を **`references/parse-rules.md`** の規則でパースし、`##` 見出しを milestone に変換する。

**重要: `brief`・`goal`・ディレクトリ名はすべて英語で生成する。** 計画ファイルが日本語の場合は翻訳する。コード内の識別子やファイルパスはそのまま保持する。

この skill では **task / wave 分解を行わない**。マイルストーン対象の `##` 見出しごとに milestone を生成し、各 milestone は空の task 配列を持つ。

- 情報セクション（Step 2 で `brief` に統合済み）はスキップする
- それ以外の `##` 見出し＋**配下の本文全体**を milestone の `goal` とする
- 各 milestone は `tasks: []` で初期化する
- `summary` は空文字列 `""` で初期化する
- task ID 生成、task description 展開、wave 区切り解釈は行わない
- runtime Planner agent が後で task を生成する前提で、skill 側では milestone 配列だけを作る

パース規則・goal 構成規則・情報セクション判定規則・ディレクトリ名生成規則の詳細は `references/parse-rules.md` を Read して参照すること。

---

### Phase 3: 出力ファイル生成

最終成果物は `plan-en.md`, `milestones.json`, `tornado.json` の3つ。

#### 3-1. milestones.json

**`references/milestones-schema.md`** の JSON スキーマに従い、`milestones.json` を**直接生成**する。Phase 2 で構築した brief・milestones をそのまま使用する。

スキーマの詳細は `references/milestones-schema.md` を Read して参照すること。

#### 3-2. tornado.json

**`references/tornado-config.md`** のテンプレートに従い生成する。

- Planner kind には `PLANNER_KIND` を使う
- Builder kind には `DEV_KIND` を使う
- Verifier kind には `VERIFIER_KIND` を使う

テンプレートとエージェント設定の詳細は `references/tornado-config.md` を Read して参照すること。

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
- 情報セクションの判定に迷う場合 → マイルストーンにする（安全側に倒す）
- `--planner` / `--dev` / `--verifier` に無効な値が指定された場合 → エラーメッセージを出して終了
  - 有効な値: `claude-code`, `claude`, `claudecode`, `codex`, `api`, `mock`
- JSON バリデーション失敗 → エラーメッセージを出して終了（ファイルは残す）
