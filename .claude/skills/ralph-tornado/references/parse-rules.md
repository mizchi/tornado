# Markdown パース規則

## パース規則テーブル

| Markdown 要素               | 変換先                                                |
| --------------------------- | ----------------------------------------------------- |
| `# 見出し` (最初のH1)       | プロジェクト名（ディレクトリ名に使用）                |
| `## 見出し`                 | マイルストーンの `goal`（後述の goal 構成規則に従う） |
| `##` がない場合             | ファイル全体を1マイルストーンとして扱う               |
| `-` / `*` / `N.` リスト項目 | タスクの `description`                                |
| `###` サブ見出し            | 同一マイルストーン内の Wave 区切り（wave を +1）      |

## goal の構成規則

`goal` は Verifier エージェントが Wave 検証時に参照する。
Verifier は `task.description` を受け取らないため、`goal` が検証の主要な文脈となる。

各マイルストーンの `goal` は以下の構成で生成すること:

```
<## 見出しテキスト>
```

> **Note:** Verification Scope 指示と Plan Context は `scripts/inject-plan-context.js` が自動注入する。Claude が直接出力する必要はない。

## ディレクトリ名の生成

- 最初の `# 見出し` のテキストを**英語に翻訳して**タイトルとする
- 小文字化、スペース/アンダースコアをハイフンに変換、英数字とハイフン以外を除去、50文字以内に切り詰め
- 出力ディレクトリ: `{repo_root}/.runs/{yyyy-mm-dd}_{kebab-case-name}/`

## タスク ID 命名規則

- `{milestone_id}-t{連番}` 形式（例: `m1-t1`, `m1-t2`, `m2-t1`）

## description テンプレート

`description` は Builder に渡される**唯一の入力**（system_prompt・goal は渡されない）。

> **Note:** `scripts/inject-plan-context.js` で以下が自動注入される:
>
> - `goal` 側: Verification Scope 指示 + Plan Context → Verifier が当該 Wave のタスクのみ検証
> - `description` 側: Plan Context のみ → Builder が実装時に参照
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
