#!/bin/bash
# entrypoint.sh
# コンテナ内で root として実行し、初期化後に claude ユーザーへ切り替える

set -euo pipefail

export PROFILE="${PROFILE:-node}"
export DISABLE_FIREWALL="${DISABLE_FIREWALL:-false}"
CUSTOM_ALLOWLIST_FILE="/home/claude/.allowlist"
export CUSTOM_ALLOWLIST_FILE

# ---- P1 #6: プロキシ設定をネットワーク初期化の直後に確立 ----
# tinyproxy が起動してから設定することで、Claude Code インストール等も
# プロキシ経由になり、iptables DROP ルール適用後も通信できる

source /init-network.sh

# ファイアウォール有効時はプロキシを現在のシェルに設定
# （su 経由の子プロセスにも明示的に渡す）
if [[ "$DISABLE_FIREWALL" != "true" ]]; then
    export HTTP_PROXY="http://127.0.0.1:8888"
    export HTTPS_PROXY="http://127.0.0.1:8888"
    export NO_PROXY="localhost,127.0.0.1"
    PROXY_ENV="HTTP_PROXY=http://127.0.0.1:8888 HTTPS_PROXY=http://127.0.0.1:8888 NO_PROXY=localhost,127.0.0.1"
else
    PROXY_ENV=""
fi

# ---- Claude Code インストール確認 ----

CLAUDE_BIN="/home/claude/.local/bin/claude"

if [[ ! -x "$CLAUDE_BIN" ]]; then
    echo "[セットアップ] Claude Code をインストール中..." >&2
    # P1 #6: プロキシ環境変数を明示的に渡す
    su -s /bin/bash claude -c \
        "$PROXY_ENV npm install -g @anthropic-ai/claude-code --prefix ~/.local"
fi

# ---- 認証トークンの書き出し ----

if [[ -n "${CLAUDE_JSON:-}" ]]; then
    echo "$CLAUDE_JSON" > /home/claude/.claude.json
    chown claude:claude /home/claude/.claude.json
    chmod 600 /home/claude/.claude.json
fi

# ---- SSH 鍵の設定（tmpfs に書き込み、ホスト FS に残さない）----

if [[ -n "${SSH_KEY:-}" ]]; then
    # マウントポイントが存在しない場合は作成
    mkdir -p /home/claude/.ssh
    # tmpfs をマウント（メモリのみ、コンテナ外に漏れない）
    # Docker の設定によっては --privileged または --cap-add SYS_ADMIN が必要
    # 失敗した場合は通常ファイルにフォールバック（--rm 使用時はコンテナ終了時に削除される）
    if ! mount -t tmpfs -o size=1m,mode=0700 tmpfs /home/claude/.ssh 2>/dev/null; then
        warn "tmpfs マウントに失敗しました。通常ファイルで SSH 鍵を管理します"
        warn "より安全な運用には --cap-add SYS_ADMIN または --privileged が必要です"
    fi

    # umask を厳格に設定
    (
        umask 077
        echo "$SSH_KEY" > /home/claude/.ssh/id_rsa
    )
    chmod 600 /home/claude/.ssh/id_rsa
    chown -R claude:claude /home/claude/.ssh

    # core dump 抑止
    ulimit -c 0

    # システムの known_hosts をコピー
    if [[ -f /etc/ssh/ssh_known_hosts ]]; then
        cp /etc/ssh/ssh_known_hosts /home/claude/.ssh/known_hosts
        chmod 644 /home/claude/.ssh/known_hosts
        chown claude:claude /home/claude/.ssh/known_hosts
    fi
fi

# ---- プロファイル別ツールのインストール ----

PROFILE_FLAG="/home/claude/.local/.profile_${PROFILE}_installed"

if [[ ! -f "$PROFILE_FLAG" ]]; then
    case "$PROFILE" in
        python)
            echo "[プロファイル] Python ツールをインストール中..." >&2
            # P1 #6: プロキシを明示的に渡す
            su -s /bin/bash claude -c \
                "$PROXY_ENV curl -LsSf https://astral.sh/uv/install.sh | sh"
            ;;
        go)
            echo "[プロファイル] Go をインストール中..." >&2
            GO_VERSION="1.22.5"
            ARCH=$(uname -m)
            case "$ARCH" in
                x86_64)  GO_ARCH="amd64" ;;
                aarch64) GO_ARCH="arm64" ;;
                *)        GO_ARCH="amd64" ;;
            esac
            # P1 #6: curl にプロキシを渡す（PROXY_ENV は意図的に単語分割）
            # shellcheck disable=SC2086
            env $PROXY_ENV curl -fsSL \
                "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" \
                | tar -C /home/claude/.local -xz
            chown -R claude:claude /home/claude/.local/go
            # shellcheck disable=SC2016  # $HOME/$PATH は子シェルで展開させる
            su -s /bin/bash claude -c \
                'echo "export PATH=$HOME/.local/go/bin:$PATH" >> ~/.bashrc'
            ;;
        rust)
            echo "[プロファイル] Rust をインストール中..." >&2
            # P1 #6: プロキシを明示的に渡す
            su -s /bin/bash claude -c \
                "$PROXY_ENV curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
                    | sh -s -- -y --no-modify-path"
            ;;
        node)
            # Node.js はイメージに含まれているので追加作業なし
            ;;
    esac

    touch "$PROFILE_FLAG"
    chown claude:claude "$PROFILE_FLAG"
fi

# ---- claude ユーザーにスイッチして実行 ----
# P1 #5: exec を使わず実行し、終了後に .claude.json を write-back する

# SSH 鍵の EXIT 時削除トラップ（exec しないので機能する）
trap 'rm -f /home/claude/.ssh/id_rsa 2>/dev/null || true' EXIT

cmd_exit=0
setpriv \
    --reuid="$(id -u claude)" \
    --regid="$(id -g claude)" \
    --init-groups \
    env \
        HOME=/home/claude \
        PATH="/home/claude/.local/bin:$PATH" \
        ${HTTP_PROXY:+HTTP_PROXY="$HTTP_PROXY"} \
        ${HTTPS_PROXY:+HTTPS_PROXY="$HTTPS_PROXY"} \
        ${NO_PROXY:+NO_PROXY="$NO_PROXY"} \
        PROFILE="$PROFILE" \
    "$@" || cmd_exit=$?

# ---- P1 #5: セッション終了後に .claude.json を出力ファイルへ書き出し ----
# ホスト側がマウントしている /home/claude/.claude.json.out へコピーする

if [[ -f /home/claude/.claude.json ]] && [[ -e /home/claude/.claude.json.out ]]; then
    cp /home/claude/.claude.json /home/claude/.claude.json.out
fi

exit $cmd_exit
