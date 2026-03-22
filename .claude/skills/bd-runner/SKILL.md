---
name: bd-runner
description: >
  bdチケットを優先度ベースで自動ループ実行するオーケストレーター。
  readyチケットをTDDで実装し、並列実行・結合テスト・バグ起票・コミット・クローズまで一貫処理。
  "bd-runner", "チケット自動実行", "バグ一括修正", "ticket runner", "auto-fix", "チケット消化".
arguments: priority:優先度閾値(P0-P4、デフォルトP3)
---

# bd-runner: bd チケット自動実行オーケストレーター

## 引数

```
/bd-runner [P0-P4] [--sequential] [--dry-run] [--type=bug|task|feature]
```

- `P0-P4`: 優先度閾値。この優先度以下（数値として以下）のreadyチケットを実行。デフォルト: `P3`
- `--sequential`: 並列実行を無効化し、全チケットを直列で処理
- `--dry-run`: 実行計画を表示するのみ。コード変更なし
- `--type=<type>`: チケット種別でフィルタ（bug, task, feature）

`$ARGUMENTS` の内容: `$ARGUMENTS`

## オーケストレーション概要

0. **状態初期化** — PROCESSED_IDS, ALL_RESULTS を初期化
1. **チケット収集・バッチ計画** — readyチケット取得、並列安全性分析、バッチ分割
2. **チケット実行** — TDD（テスト先行）で各チケットを修正・実装
3. **バッチオーケストレーション** — サブエージェント並列起動、worktreeマージ、バッチ毎テスト
4. **障害分離・バグ起票** — live失敗時のper-ticket isolation、P1でバグ起票
5. **クローズ・最終レポート** — 全イテレーションの結果を集約、チケットクローズ

**Phase 1〜4 は外部ループ（最大5回）で繰り返し、毎回 `bd ready` を再スキャンして新規チケットを拾う。**

各フェーズを**必ず順番に**実行すること。

---

### Phase 0: 状態初期化

以下の状態変数を初期化する:

- `ITERATION = 0` — ループ回数カウンタ
- `PROCESSED_IDS = {}` — 処理済みチケットIDの集合
- `ALL_RESULTS = []` — 全イテレーション結果の蓄積リスト

引数を解析する:
- 最初の `P` で始まるトークン（P0〜P4）を `PRIORITY_THRESHOLD` とする（デフォルト: `3` = P3）
- `--sequential` があれば `SEQUENTIAL=true`
- `--dry-run` があれば `DRY_RUN=true`
- `--type=<value>` があれば `TYPE_FILTER` に格納

---

### 外部ループ（ITERATION < 5 の間繰り返す）

`ITERATION` をインクリメントし、Phase 1 〜 Phase 4 を実行する。

---

### Phase 1: チケット収集・バッチ計画

1. readyチケットを取得:

   ```bash
   bd ready
   ```

2. **in_progressチケットを回収**（前セッション中断からの復帰）:

   ```bash
   bd list --status=in_progress
   ```

   in_progressチケットは前セッションで claim 済みだが未完了のもの。
   候補リストに追加し、各チケットに `RESUMED=true` フラグを付与する。

3. 優先度フィルタ: `PRIORITY_THRESHOLD` 以下（P0が最高=0、P4が最低=4）のチケットのみ残す。
   `TYPE_FILTER` が指定されていれば種別でも絞り込む。

4. 処理済みチケットを除外: `PROCESSED_IDS` に含まれるIDを除外する。

5. 対象チケットが 0 件の場合:
   - 初回（`ITERATION == 1`）: 「対象チケットなし」と報告して終了
   - 再スキャン（`ITERATION >= 2`）: 「新規チケットなし」→ ループ終了、Phase 5 へ

6. 各チケットの詳細を取得:

   ```bash
   bd show <ticket-id>
   ```

   タイトル、説明、種別、優先度を記録する。

7. **並列安全性の分析**（`SEQUENTIAL=true` の場合はスキップ、全て直列）:
   - 各チケットの説明から対象ファイルパス・モジュール名を抽出
   - 異なるモジュール/ディレクトリのチケット → 同一バッチ（並列可）
   - 同一ファイルに言及するチケット → 別バッチ（直列）
   - 判定不能 → 別バッチ（保守的に直列）

8. 実行計画を表示:

   ```markdown
   ## bd-runner 実行計画

   **イテレーション**: N / 5
   **優先度閾値**: P<N>
   **対象チケット数**: N
   **モード**: 並列 / 直列

   ### Batch 1 (並列)
   | ID | 優先度 | 種別 | タイトル |
   |----|--------|------|---------|
   | tornado-xxx | P1 | bug | ... |
   | tornado-yyy | P1 | bug | ... |

   ### Batch 2 (直列)
   | ID | 優先度 | 種別 | タイトル |
   |----|--------|------|---------|
   | tornado-zzz | P2 | task | ... |
   ```

9. `DRY_RUN=true` の場合:
   - 初回: 実行計画を表示して終了
   - 再スキャン（`ITERATION >= 2`）: 「再スキャンで N 件の新規チケット発見」と表示して終了

---

### Phase 2: チケット実行（サブエージェント単位）

各チケットは `references/ticket-execution-protocol.md` の手順に従って実行する。

サブエージェントへのプロンプトには以下を含める:
- `references/ticket-execution-protocol.md` の全内容
- 対象チケットID
- チケットのタイトルと説明（`bd show` の出力）
- プロジェクトのテストコマンド: `just test`, `just live`

サブエージェントは以下を返す:
- 成功/失敗のステータス
- commit hash（成功時）
- 変更ファイル一覧
- テスト結果の要約
- エラー詳細（失敗時）

---

### Phase 3: バッチオーケストレーション

各バッチを順番に処理する:

1. **バッチ内チケットが 1 つ**:
   - サブエージェントを起動せず、Phase 2 の手順を直接実行する

2. **バッチ内チケットが 2 つ以上**:
   - 各チケットに対してサブエージェントを**並列起動**する:

     ```
     Agent tool（チケット毎に1つ）:
       subagent_type: "general-purpose"
       isolation: "worktree"
       mode: "bypassPermissions"
       prompt: <ticket-execution-protocol + チケット詳細>
     ```

   - 全サブエージェントの完了を待機する

3. **結果処理**:
   - 成功 → commit hash を記録、`PROCESSED_IDS` に追加
   - 失敗 → エラーを記録、`PROCESSED_IDS` に追加（再試行しない）
   - worktree に変更がある場合 → ステップ4 のマージ手順を実行

4. **worktree マージ**（バッチ内チケットが 2 つ以上の場合）:

   各 worktree ブランチを順番にメインブランチへマージする:

   a. `git merge <worktree-branch> --no-edit`
   b. **競合が発生した場合**:
      - 競合マーカーを解析し、両方の変更を保持する方向で解決する
      - 変数名の不整合（例: 一方が `tasks`、他方が `pending_tasks`）は、
        メインブランチ側の命名を優先して統一する
      - `git add <resolved-files> && git commit --no-edit` でマージコミット作成
   c. 全ブランチのマージ完了後、worktree とブランチをクリーンアップ:
      ```bash
      git worktree remove --force <worktree-path>
      git branch -D <worktree-branch>
      ```

5. **マージ後検証**:

   ```bash
   just test
   ```

   - **PASS** → ステップ6 へ
   - **FAIL** → 競合解決ミスの可能性。失敗内容を確認し修正を試みる。
     3回試行しても通過しない場合、バッチ全体の変更を revert し、
     全チケットを失敗マークして P1 バグを起票:
     ```bash
     bd create --title="[bd-runner] Merge conflict resolution caused test failure" \
       --description="バッチマージ後の just test 失敗。対象チケット: <ticket-ids>\n\n失敗詳細:\n<エラー出力>" \
       --type=bug --priority=1
     ```

6. **バッチ後結合テスト**:

   ```bash
   just test
   ```

   ユニットテスト通過を確認後:

   ```bash
   just live
   ```

   - **成功** → 次バッチへ進行
   - **失敗** → Phase 4（障害分離）へ移行

7. 全バッチ完了後:
   - 結果を `ALL_RESULTS` に追加
   - **このイテレーションの成功チケットを即座にクローズ**:
     ```bash
     bd close <id1> <id2> ... --reason="Fixed in commit <hash>."
     ```
     依存先のチケットがunblockされ、次の再スキャンで拾えるようになる。
   - 外部ループの次のイテレーションへ（Phase 1 に戻り `bd ready` を再スキャン）
   - サーキットブレーカー（`ITERATION >= 5`）到達時は Phase 5 へ

---

### Phase 4: 障害分離・バグ起票（バッチ `just live` 失敗時のみ）

バッチの `just live` が失敗した場合にのみ実行する。

1. **Per-ticket isolation**: バッチ内の各 commit を 1 つずつテスト:
   - バッチ内の全 commit を `git revert` で一旦戻す
   - 1 つずつ `git cherry-pick` して `just live` を実行
   - `just live` が失敗する commit が原因チケット

2. **原因チケットの処理**:
   - 原因 commit を revert する
   - チケットにノート追加:
     ```bash
     bd update <id> --notes="just live failure: <失敗内容の要約>"
     ```

3. **新規バグ起票**（P1 固定）:

   ```bash
   bd create --title="[bd-runner] <失敗の要約>" \
     --description="just live テスト失敗。元チケット: <ticket-id>\n\n失敗詳細:\n<エラー出力>" \
     --type=bug --priority=1
   ```

4. **新規バグの登録**:
   - 新規起票バグは次イテレーションの `bd ready` 再スキャンで自動的に拾われる
   - 新規バグのIDを `ALL_RESULTS` の「新規起票バグ」リストに記録する

5. 残りの成功 commit は維持し、次バッチへ進行

---

### Phase 5: クローズ・最終レポート

1. **未クローズの成功チケットをクローズ**:

   Phase 3 で既にクローズ済みのチケットはスキップし、残りの成功チケットをクローズする:

   ```bash
   bd close <id> --reason="Fixed in commit <hash>. Regression test added."
   ```

2. **失敗チケットのノート追加**:

   ```bash
   bd update <id> --notes="bd-runner attempt failed: <エラー要約>. Manual intervention required."
   ```

3. **最終サマリー表示**:

   ```markdown
   ## bd-runner 実行レポート

   **優先度閾値**: P<N>
   **イテレーション**: <N> / 5
   **処理チケット数**: <N>（全イテレーション合計）

   ### 完了
   | チケット | タイトル | Commit | テスト | イテレーション |
   |----------|---------|--------|--------|--------------|
   | tornado-xxx | ... | abc1234 | PASS | 1 |

   ### 失敗
   | チケット | タイトル | エラー | イテレーション |
   |----------|---------|--------|--------------|
   | tornado-yyy | ... | <要約> | 1 |

   ### 新規起票バグ
   | チケット | タイトル | 優先度 |
   |----------|---------|--------|
   | tornado-zzz | ... | P1 |

   ### テスト結果
   - `just test`: PASS / FAIL
   - `just live`: PASS / FAIL
   ```

---

## エラーハンドリング

| シナリオ | アクション |
|----------|-----------|
| `bd ready` + `in_progress` が 0 件（初回） | 「対象チケットなし」で終了 |
| `in_progress` チケット発見 | `RESUMED=true` フラグ付与、claim スキップ、`git checkout -- .` でクリーンスタート |
| 再スキャンで新規チケット 0 件 | ループ終了、Phase 5 へ |
| `bd update --claim` 失敗 | スキップ、次のチケットへ |
| TDD テスト作成失敗 | チケットを失敗マーク、unclaim、次へ |
| 実装後 `just test` 失敗 | 変更を revert、失敗マーク、次へ |
| worktree マージ競合 | 競合解決 → `just test` → 失敗なら revert + P1 バグ起票 |
| マージ後 `just test` 失敗（3回） | バッチ変更を revert、P1 バグ起票、次バッチ続行 |
| `just live` 失敗 | Phase 4 で障害分離・バグ起票 |
| サーキットブレーカー発動（5回） | 残バグ報告して Phase 5 へ |
| サブエージェント タイムアウト | 失敗扱い、ノート追加、次へ |
