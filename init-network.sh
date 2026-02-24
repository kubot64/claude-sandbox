#!/bin/bash
# init-network.sh
# tinyproxy 起動 + iptables によるネットワーク制御
# entrypoint.sh から root 権限で呼び出される

set -euo pipefail

# ファイアウォール無効化フラグ
if [[ "${DISABLE_FIREWALL:-false}" == "true" ]]; then
    echo -e "\033[31m[警告] ファイアウォールが無効化されています。すべての外部通信が許可されます。\033[0m" >&2
    # source 時は return、直接実行時は exit（SC2317 は意図的な fallback）
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi

PROFILE="${PROFILE:-node}"
CUSTOM_ALLOWLIST="${CUSTOM_ALLOWLIST_FILE:-}"

# ---- 許可ホスト名リストを構築 ----

ALLOWED_HOSTS=(
    # Anthropic
    "api.anthropic.com"
    "console.anthropic.com"
    "statsig.anthropic.com"
    "sentry.io"

    # 共通開発
    "github.com"
    "raw.githubusercontent.com"
    "objects.githubusercontent.com"
    "codeload.github.com"

    # Claude Code インストール用
    "registry.npmjs.org"
    "npmjs.com"
    "nodejs.org"
)

# プロファイル別の追加ホスト
case "$PROFILE" in
    python)
        ALLOWED_HOSTS+=(
            "pypi.org"
            "files.pythonhosted.org"
            "bootstrap.pypa.io"
        )
        ;;
    go)
        ALLOWED_HOSTS+=(
            "proxy.golang.org"
            "sum.golang.org"
            "storage.googleapis.com"
            "go.dev"
        )
        ;;
    rust)
        ALLOWED_HOSTS+=(
            "crates.io"
            "static.crates.io"
            "index.crates.io"
        )
        ;;
    node)
        # デフォルトの npm 設定は既に含まれている
        ;;
esac

# カスタム許可リスト（プロジェクト別 allowlist ファイル）
if [[ -f "$CUSTOM_ALLOWLIST" ]]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        ALLOWED_HOSTS+=("$line")
    done < "$CUSTOM_ALLOWLIST"
fi

# ---- tinyproxy 設定ファイルを生成 ----

TINYPROXY_CONF="/etc/tinyproxy/tinyproxy.conf"
FILTER_FILE="/etc/tinyproxy/filter"

mkdir -p /etc/tinyproxy

# フィルタファイルを生成（正規表現でホスト名マッチ）
{
    for host in "${ALLOWED_HOSTS[@]}"; do
        # glibc ERE は (.*\.)? のバックトラックが壊れているため 2 パターンに分割:
        # 完全一致 + サブドメイン（\.HOST$ で先頭ドット必須 → evilHOST 非マッチ）
        _esc="${host//./\\.}"
        echo "^${_esc}\$"
        echo "\\.${_esc}\$"
    done
} > "$FILTER_FILE"

# テンプレートから設定ファイルを生成
FILTER_SECTION="Filter \"$FILTER_FILE\"
FilterURLs Off
FilterCaseSensitive Off
FilterDefaultDeny Yes"

# sed の multiline 置換を避けるため:
# 1. テンプレートから {{FILTER_SECTION}} 行を削除
# 2. フィルタ設定を末尾に追記
{
    sed '/{{FILTER_SECTION}}/d' /tinyproxy.conf.tmpl
    echo "$FILTER_SECTION"
} > "$TINYPROXY_CONF"

# ---- tinyproxy 起動 ----

tinyproxy -c "$TINYPROXY_CONF"

# 起動確認（最大 3 秒待機）
for _ in 1 2 3; do
    if kill -0 "$(cat /tmp/tinyproxy.pid 2>/dev/null)" 2>/dev/null; then
        break
    fi
    sleep 1
done

if ! kill -0 "$(cat /tmp/tinyproxy.pid 2>/dev/null)" 2>/dev/null; then
    echo "[エラー] tinyproxy の起動に失敗しました" >&2
    exit 1
fi

# ---- iptables 設定 ----
# 設計:
#   - tinyproxy（root, UID=0）: 外部アウトバウンド接続を許可
#   - claude ユーザー（非 root）: ループバック（プロキシ経由）のみ許可
#     直接外部接続は DROP（プロキシを迂回させない）
#
# UID ベースの制御に xt_owner モジュールを使用

# まず既存ルールをリセット
iptables -F OUTPUT 2>/dev/null || true
iptables -F INPUT  2>/dev/null || true

# ループバック（claude ユーザー → tinyproxy の通信路）を許可
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -i lo -j ACCEPT

# DNS を許可（tinyproxy が名前解決するため必要; root が実行）
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT

# tinyproxy（root = UID 0）の外部アウトバウンド接続を許可
iptables -A OUTPUT -m owner --uid-owner 0 -j ACCEPT

# 確立済みセッションを許可（tinyproxy ↔ 外部の戻りパケット）
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT

# デフォルトポリシーを DROP に設定
# → claude ユーザーの直接外部接続はここで遮断（プロキシ迂回防止）
iptables -P OUTPUT DROP
iptables -P INPUT  DROP

echo "[ネットワーク] tinyproxy (L7 プロキシ) + iptables を設定しました" >&2
echo "[ネットワーク] 許可ホスト数: ${#ALLOWED_HOSTS[@]}" >&2
