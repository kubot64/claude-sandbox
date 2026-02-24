# claude-sandbox 設計ドキュメント v2

## 背景・目的

claude-docker（シンプル・セキュリティ配慮なし）と claudebox（高機能・複雑）の中間。
Colima + 1Password CLI を前提に、セキュリティと使いやすさのバランスを取るツール。

**前提環境:** macOS / Colima / Docker CLI / 1Password CLI + Desktop

---

## ChatGPT レビュー後の設計変更サマリ

| # | 指摘 | 対応方針 |
|---|---|---|
| C1 | iptables+ipset のIP許可は CDN/IPv6/DNS ズレで穴が出る | **L7プロキシ（tinyproxy）に変更** |
| C2 | SSH鍵をコンテナFSに書くのは漏洩リスク | **tmpfs + umask077 + trap削除、またはGitトークン** |
| H1 | .claude.json の上書き保存で last-writer-wins / 破損リスク | **JSON検証 + 差分のみ保存** |
| H2 | --no-firewall が完全無効化で誤用リスク | **--no-firewall-i-know を要求** |
| M1 | Colima自動検出が単純すぎる | **docker context 優先 + 接続テスト後のみ切替** |
| M2 | 初回セットアップ失敗時の導線不足 | **`claude-sandbox doctor` サブコマンド追加** |
| M3 | slug が sha1 6桁で衝突・パス変更に弱い | **realpath 正規化 + 12桁ハッシュ** |

---

## 機能設計

### 1. プロジェクト別分離

```bash
# realpath で正規化してからハッシュ（シンボリックリンク対応）
canonical="$(realpath "$PWD")"
slug="$(basename "$canonical")_$(echo "$canonical" | sha1sum | head -c 12)"
# 例: myapp_a3f9c1b8e2d4
```

```
~/.claude-sandbox/
  shared/
    .claude.json          # 認証トークン（全プロジェクト共有）
    .claude/
      settings.json
      CLAUDE.md

  projects/myapp_a3f9c1b8e2d4/
    history/              # プロジェクト別の会話履歴
    allowlist             # 追加許可ホスト名（1行1ホスト名）
    profile               # 使用プロファイル記録
```

**Named volume:** `claude-sandbox-<slug>`（Claude Code 本体・プロファイルツールを永続化）

---

### 2. 言語プロファイル（4種類）

```bash
claude-sandbox                   # node（デフォルト）
claude-sandbox --profile python  # Python
claude-sandbox --profile go      # Go
claude-sandbox --profile rust    # Rust
```

---

### 3. ネットワーク制御（L7 プロキシ方式）※設計変更

**変更理由:** iptables + ipset の IP ベース許可は CDN/マルチA/IPv6 で信頼性が低い。
ホスト名ベース制御ができる L7 プロキシ（tinyproxy）に変更。

**構成:**

```
コンテナ内
  Claude Code → HTTP_PROXY=127.0.0.1:8888 → tinyproxy → 外部
                                              ↓
                                         ホスト名チェック（許可リスト）
                                         CONNECT トンネリング（HTTPS対応）
```

**iptables の役割を最小化:**
```bash
# DNS のみ許可（tinyproxy が名前解決するため）
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
# tinyproxy 経由のみ許可
iptables -A OUTPUT -d 127.0.0.1 -p tcp --dport 8888 -j ACCEPT
# それ以外は DROP（fail-close）
iptables -P OUTPUT DROP
```

**tinyproxy の許可ホスト名（デフォルト）:**
```
# Anthropic
api.anthropic.com
console.anthropic.com
statsig.anthropic.com
sentry.io

# 共通
github.com
raw.githubusercontent.com
objects.githubusercontent.com

# プロファイル別（自動追加）
registry.npmjs.org
pypi.org
files.pythonhosted.org
proxy.golang.org
sum.golang.org
crates.io
static.crates.io
```

#### tinyproxy フィルタ正規表現（glibc ERE 回避）

glibc の POSIX ERE 実装では `(.*\.)?` オプショナルグループのバックトラックが正しく動作しない（tinyproxy 1.11.x / Debian Bookworm で確認）。

```
# NG: glibc ERE でバックトラック失敗 → 許可ホストも 403 になる
^(.*\.)?registry\.npmjs\.org$

# OK: 2 パターンに分割
^registry\.npmjs\.org$      # 完全一致
\.registry\.npmjs\.org$     # サブドメイン（先頭ドット必須）
```

`init-network.sh` は各ホスト名につき 2 行を出力する。
`evilregistry.npmjs.org` は先頭ドットがないため非マッチ（意図的）。

---

**IPv6:** コンテナ起動時に `--sysctl net.ipv6.conf.all.disable_ipv6=1` で無効化（IPv6経路漏れ防止）。将来的に IPv6 対応が必要な場合は別途設計。

**カスタム許可:** `~/.claude-sandbox/projects/<slug>/allowlist` にホスト名を追記

**無効化:** `--no-firewall-i-know-what-im-doing`（意図的に長くする + 実行時に赤字警告を出力）

---

### 4. 認証情報管理（1Password CLI 統合）

#### Claude 認証トークン（.claude.json）

```
起動時:
  op read → $CLAUDE_JSON → entrypoint が ~/.claude.json に書き出し

終了後（改善点反映）:
  1. コンテナ内の ~/.claude.json を読み取り
  2. jq . で JSON バリデーション（壊れていたらスキップ＆警告）
  3. 起動時と内容が変わっていない場合はスキップ
  4. 変わっている場合のみ op item edit で上書き
  ※ 並列セッションは非対応（ドキュメントに明記、警告表示）
```

#### SSH 鍵（改善点反映）

**基本方針:** SSH 鍵本体をコンテナ FS に置くリスクを最小化。

```bash
# entrypoint 内
# 1. tmpfs にマウントして書き込む（メモリのみ、コンテナ外に漏れない）
mount -t tmpfs tmpfs /home/claude/.ssh
umask 077

echo "$SSH_KEY" > /home/claude/.ssh/id_rsa
chmod 600 /home/claude/.ssh/id_rsa

# 2. core dump 抑止
ulimit -c 0

# 3. trap で終了時に確実削除
trap 'rm -f /home/claude/.ssh/id_rsa' EXIT
```

**推奨（将来の改善）:** SSH 鍵の代わりに GitHub の Fine-grained token を使う。
鍵本体を扱わずに済み、スコープも絞れる。`--github-token` オプションで対応予定。

**known_hosts:** ビルド時に `github.com` 等を固定埋め込み（TOFU リスク回避）。

#### API キー

```bash
op run \
  --env=ANTHROPIC_API_KEY=op://Personal/Anthropic/api_key \
  -- docker run -e ANTHROPIC_API_KEY ...
```

---

### 5. Colima 自動検出（改善点反映）

```bash
# 優先順位:
# 1. 既存の DOCKER_HOST があればそのまま使う
# 2. docker context inspect で現在のコンテキストを確認
# 3. Colima が動いていれば Colima のソケットを試す
# 4. 接続テストが通ったときだけ DOCKER_HOST を切り替える

setup_docker_host() {
  # 既存設定を尊重
  [[ -n "$DOCKER_HOST" ]] && return

  # 現在の docker context が使えるか確認
  if docker info &>/dev/null 2>&1; then
    return  # 既存コンテキストで動いている
  fi

  # Colima を試みる
  local colima_profile="${COLIMA_PROFILE:-default}"
  local colima_sock="$HOME/.colima/$colima_profile/docker.sock"

  if colima status "$colima_profile" &>/dev/null && [[ -S "$colima_sock" ]]; then
    export DOCKER_HOST="unix://$colima_sock"
    # 接続テスト
    if ! docker info &>/dev/null 2>&1; then
      err "Colima は動いていますが Docker に接続できません"
      exit 1
    fi
  else
    err "Docker が見つかりません。Colima を起動してください: colima start"
    exit 1
  fi
}
```

---

### 6. `claude-sandbox doctor`（初回セットアップ支援）

```
$ claude-sandbox doctor

[✓] colima: installed (0.7.2)
[✓] colima: running (default profile)
[✓] docker: connected
[✓] op: installed (2.24.0)
[✓] op: signed in (user@example.com)
[✓] 1Password item "Claude Code": found
[✓] 1Password item "SSH Key": found
[✗] 1Password item "Anthropic": NOT FOUND
    → op item create --category=login --title="Anthropic" \
        --field=api_key=<your_key>
```

`install.sh` でも依存関係のバージョン検証を実施。

---

## ファイル構成

```
claude-sandbox          # メインスクリプト（bash）
install.sh             # 依存確認 + ~/.local/bin/ へのインストール

# コンテナ内（docker build でイメージに埋め込む）
entrypoint.sh          # Claude Code 起動前の初期化
init-network.sh        # tinyproxy 起動 + iptables 設定
tinyproxy.conf.tmpl    # 許可ホスト名のテンプレート
```

---

## Dockerfile（概要）

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl git openssh-client \
    iptables \
    tinyproxy \       ← L7 プロキシ
    jq \
    ca-certificates gnupg \
    && rm -rf /var/lib/apt/lists/*

# Node.js（Claude Code 用）
# GitHub CLI
# cloudユーザー作成

COPY entrypoint.sh init-network.sh tinyproxy.conf.tmpl /
ENTRYPOINT ["/entrypoint.sh"]
```

---

## メインスクリプトの流れ

```
1. setup_docker_host()         ← Colima 自動検出（改善版）
2. 依存コマンド確認（op, docker）
3. op signin 状態確認
4. 引数パース
   --profile <node|python|go|rust>
   --no-firewall-i-know-what-im-doing
   --rebuild
   doctor（サブコマンド）
5. realpath でパス正規化 → スラグ生成（12桁）
6. ディレクトリ初期化
7. ~/.claude/ 設定を rsync -u で同期
8. Docker イメージビルド（初回 or --rebuild 時のみ）
9. 1Password から認証情報取得
   CLAUDE_JSON=$(op read ... || echo "")
   SSH_KEY=$(op read ...)
10. 並列セッション警告
    lock ファイルが存在する場合は警告表示
11. op run でラップして docker run 実行
    --sysctl net.ipv6.conf.all.disable_ipv6=1
    --cap-add NET_ADMIN
    -e PROFILE, CLAUDE_JSON, SSH_KEY
    -e ANTHROPIC_API_KEY（op run 経由）
    -v claude-sandbox-<slug>:/home/claude/.local
    -v shared/.claude:/home/claude/.claude
    -v projects/<slug>/history:...
    -v allowlist:/home/claude/.allowlist:ro
    -v ~/.gitconfig:ro
    -v $(pwd):/workspace -w /workspace
12. コンテナ終了後
    - lock ファイル削除
    - .claude.json の JSON バリデーション
    - 変更があれば op item edit で保存
```

---

## 設計補足

### A. NO_PROXY の明示

tinyproxy がローカルの 127.0.0.1:8888 で動いているため、
プロキシ設定がプロキシ自身に向く自己参照ループを防ぐ。

```bash
# docker run の -e に追加
-e HTTP_PROXY=http://127.0.0.1:8888
-e HTTPS_PROXY=http://127.0.0.1:8888
-e NO_PROXY=localhost,127.0.0.1
```

### B. lock の扱いを明文化

**方式:** `mkdir` ロック（アトミックなディレクトリ作成を利用）+ PID ファイル

```bash
LOCK_DIR="$PROJECT_DIR/.lock"
LOCK_PID="$LOCK_DIR/pid"

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    # ロック取得成功
    echo $$ > "$LOCK_PID"
    return 0
  fi

  # stale lock チェック: PID が生存しているか確認
  local old_pid
  old_pid=$(cat "$LOCK_PID" 2>/dev/null)
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    # プロセスが生きている → 本当の競合
    warn "別のセッションが実行中です (PID: $old_pid)"
    warn "並列実行は非対応です。終了するか --force で stale lock を強制削除してください。"
    exit 1
  else
    # プロセスが死んでいる → stale lock を回収して再取得
    warn "stale lock を検出しました (PID: ${old_pid:-不明})。回収します。"
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    echo $$ > "$LOCK_PID"
  fi
}

release_lock() {
  rm -rf "$LOCK_DIR"
}

# trap で異常終了時も確実に解放
trap 'release_lock' EXIT
```

**--force フラグ:** stale lock を強制削除して続行（デバッグ用）。

---

## セキュリティ設計の原則

> **強い安全デフォルト + 明示的な危険オプトアウト**

- ファイアウォールはデフォルト ON（無効化は長いフラグ名で意図的に面倒に）
- SSH 鍵は tmpfs のみ（ホスト FS に残らない）
- 秘密情報は環境変数経由（ファイルに平文保存しない）
- 複数セッションは非対応（安全のため。将来の課題）

---

## 未対応・既知の制限（ドキュメントに明記する）

- 並列セッション非対応（last-writer-wins 問題を避けるため）
- IPv6 無効化（将来の課題）
- Windows/Linux 非対応（macOS + Colima 専用）
- `--profile` の複数指定非対応
- SSH 鍵の代わりに GitHub Token を使う `--github-token` は将来対応
