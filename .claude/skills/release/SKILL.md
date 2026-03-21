---
name: release
description: >
  バージョンアップ → ビルド → コミット → push → npm パブリッシュの一連のリリースフローを実行。
  "release", "リリース", "パブリッシュ", "publish", "バージョンアップ", "version bump".
arguments: version_bump:バージョンバンプ種別(patch|minor|major)。省略時は修正差分から推測。
---

# release: npm リリースフロー

## 引数

```
/release [patch|minor|major]
```

`$ARGUMENTS` のパース:
- 最初のトークンを `BUMP` とする（省略時は修正差分から推測）
- 有効な値: `patch`, `minor`, `major`
- 無効な値の場合はエラーメッセージを出して終了

## 実行手順

以下を**必ず順番に**実行すること。各ステップが失敗した場合は即座に停止してユーザーに報告する。

### Step 1: 事前チェック

1. ワーキングツリーが clean であることを確認:
   ```bash
   git diff --quiet && git diff --cached --quiet
   ```
   dirty な場合はエラーを出して終了（「先にコミットしてください」）

2. 現在のブランチが `main` であることを確認

### Step 2: バージョンアップ

1. `package.json` の現在のバージョンを読み取る
2. `BUMP` に従って新バージョンを算出する
3. `npm version $BUMP --no-git-tag-version` で package.json を更新
4. `package-lock.json` も更新される場合がある — `npm install --package-lock-only` で同期

### Step 3: ビルド

```bash
just pack
```

ビルドが失敗した場合は停止。

### Step 4: コミット

```bash
git add package.json package-lock.json
git commit -m "chore: bump version to $NEW_VERSION"
```

### Step 5: Push

```bash
git push origin main
```

push が失敗した場合は停止。

### Step 6: パブリッシュ

```bash
just publish
```

### Step 7: 完了報告

以下を表示:
- 旧バージョン → 新バージョン
- npm パッケージ URL: `https://www.npmjs.com/package/@ymdvsymd/tornado`
