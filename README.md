# claude-sandbox

Claude Code をネットワーク制限付きの Docker コンテナで動かすツール。
macOS + Colima + 1Password CLI を前提とした最小構成。

設計の詳細は [DESIGN.md](DESIGN.md) を参照。

---

## セットアップ

```bash
# 依存確認 + ~/.local/bin/ へのインストール
./install.sh

# 初回確認（依存ツールと 1Password アイテムの疎通チェック）
claude-sandbox doctor
```

**必要なもの:** colima, docker CLI, 1Password CLI (`op`), jq, git

---

## 使い方

```bash
# カレントディレクトリをワークスペースとして起動（Node.js プロファイル）
claude-sandbox

# 言語プロファイルを指定
claude-sandbox --profile python
claude-sandbox --profile go
claude-sandbox --profile rust

# ファイアウォールを無効化（デバッグ用）
claude-sandbox --no-firewall-i-know-what-im-doing

# Docker イメージを強制再ビルド
claude-sandbox --rebuild
```

---

## テスト

### ローカル実行

```bash
# shellcheck + bats 単体テスト（Docker 不要）
bash tests/run_all.sh --unit-only

# 統合テストも含めて全件実行（Docker 必要）
bash tests/run_all.sh --integration
```

**前提:** `bats-core`, `shellcheck` がインストール済みであること。

```bash
brew install bats-core shellcheck
```

統合テストは初回に Docker イメージを自動ビルドする（数分かかる）。
`TEST_IMAGE=my-tag bash tests/run_all.sh --integration` で使用イメージを切り替え可能。

### CI（GitHub Actions）

PR 作成・main push で自動実行。

| ジョブ | 内容 | 所要時間目安 |
|---|---|---|
| `unit` | shellcheck + bats 単体テスト | ~30秒 |
| `integration` | Docker ビルド + 統合テスト全10件 | ~3分 |

---

## CI 失敗時の切り分け

### `unit` ジョブが失敗した場合

```bash
bash tests/run_all.sh --unit-only
```

shellcheck エラーはファイル名と行番号で特定できる。
bats の失敗は `not ok N テスト名` の行を確認する。

### `integration` ジョブが失敗した場合

```bash
# 対象テストファイルだけ手元で実行（Docker 起動中に限り）
bats tests/integration/firewall.bats
bats tests/integration/ssh_tmpfs.bats
bats tests/integration/exit_code.bats
```

よくある原因と対処：

| 症状 | 原因 | 対処 |
|---|---|---|
| Docker ビルドで失敗 | Dockerfile の依存変更 / apt ミラー障害 | `docker build` を手元で実行してエラーを確認 |
| `firewall` テストが 403 | tinyproxy フィルタのパターン変更 | `DESIGN.md § tinyproxy フィルタ正規表現` を参照 |
| `ssh_tmpfs` テストが失敗 | `--privileged` 非対応環境 | ランナーが privileged コンテナを許可しているか確認 |
| ネットワーク系テストがタイムアウト | registry.npmjs.org への疎通なし | `require_network` スキップが効いているはず（`firewall.bats` L16 参照） |

### `require_network` によるスキップ

`firewall.bats` の実ネットワーク疎通テスト（test 6, 7）は `require_network` チェックで外部接続がない場合に自動スキップされる。
CI ランナーに外部アクセスがない場合は `ok N # skip` と表示される。

---

## カスタム許可ホスト

プロジェクト固有のホストは `~/.claude-sandbox/projects/<slug>/allowlist` に追記する（1行1ホスト名、`#` でコメント）：

```
# 追加したいホスト名を1行ずつ記述
api.example.com
```
