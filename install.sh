#!/usr/bin/env bash
# install.sh
# claude-sandbox を ~/.local/bin/ にインストールする

set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
COMMAND_NAME="claude-sandbox"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIN_OP_VERSION="2.0.0"
MIN_DOCKER_VERSION="20.0.0"

err()  { echo -e "\033[31m[エラー]\033[0m $*" >&2; }
info() { echo -e "\033[32m[情報]\033[0m $*" >&2; }
warn() { echo -e "\033[33m[警告]\033[0m $*" >&2; }

# セマンティックバージョン比較（a >= b なら 0 を返す）
version_gte() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

echo "=== claude-sandbox インストーラー ==="
echo ""

# ---- 依存確認 ----

MISSING=()
WARNINGS=()

# colima
if ! command -v colima &>/dev/null; then
    WARNINGS+=("colima が見つかりません: brew install colima")
else
    info "colima: OK"
fi

# docker
if ! command -v docker &>/dev/null; then
    MISSING+=("docker: brew install docker")
else
    docker_ver=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
    if version_gte "$docker_ver" "$MIN_DOCKER_VERSION"; then
        info "docker: OK ($docker_ver)"
    else
        WARNINGS+=("docker バージョンが古いです ($docker_ver < $MIN_DOCKER_VERSION)")
    fi
fi

# 1password-cli
if ! command -v op &>/dev/null; then
    MISSING+=("op (1Password CLI): brew install 1password-cli")
else
    op_ver=$(op --version 2>/dev/null || echo "0.0.0")
    if version_gte "$op_ver" "$MIN_OP_VERSION"; then
        info "op (1Password CLI): OK ($op_ver)"
    else
        WARNINGS+=("op バージョンが古いです ($op_ver < $MIN_OP_VERSION)")
    fi
fi

# jq
if ! command -v jq &>/dev/null; then
    MISSING+=("jq: brew install jq")
else
    info "jq: OK"
fi

# rsync
if ! command -v rsync &>/dev/null; then
    MISSING+=("rsync: brew install rsync")
else
    info "rsync: OK"
fi

echo ""

# 必須依存が不足している場合は中断
if [[ ${#MISSING[@]} -gt 0 ]]; then
    err "必須依存が不足しています:"
    for item in "${MISSING[@]}"; do
        err "  - $item"
    done
    exit 1
fi

# 警告表示
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    for w in "${WARNINGS[@]}"; do
        warn "$w"
    done
    echo ""
fi

# ---- インストール ----

# すべてのファイルを lib ディレクトリにインストール（Dockerfile 等も必要）
LIB_DIR="$HOME/.local/lib/claude-sandbox"
mkdir -p "$INSTALL_DIR" "$LIB_DIR"

cp "$SCRIPT_DIR/claude-sandbox"       "$LIB_DIR/claude-sandbox"
cp "$SCRIPT_DIR/Dockerfile"           "$LIB_DIR/Dockerfile"
cp "$SCRIPT_DIR/entrypoint.sh"        "$LIB_DIR/entrypoint.sh"
cp "$SCRIPT_DIR/init-network.sh"      "$LIB_DIR/init-network.sh"
cp "$SCRIPT_DIR/tinyproxy.conf.tmpl"  "$LIB_DIR/tinyproxy.conf.tmpl"
chmod +x "$LIB_DIR/claude-sandbox" "$LIB_DIR/entrypoint.sh" "$LIB_DIR/init-network.sh"

# ~/.local/bin には wrapper スクリプトを置く
# SCRIPT_DIR が lib ディレクトリを指すよう exec で委譲する
cat > "$INSTALL_DIR/$COMMAND_NAME" <<EOF
#!/usr/bin/env bash
exec "$LIB_DIR/claude-sandbox" "\$@"
EOF
chmod +x "$INSTALL_DIR/$COMMAND_NAME"

info "$LIB_DIR/ にインストールしました"
info "$INSTALL_DIR/$COMMAND_NAME (wrapper) を作成しました"

# PATH チェック
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo ""
    warn "$INSTALL_DIR が PATH に含まれていません"
    warn "以下を ~/.zshrc または ~/.bashrc に追加してください:"
    echo ""
    # shellcheck disable=SC2016  # シェル設定用のリテラル文字列を出力
    echo '  export PATH="$HOME/.local/bin:$PATH"'
    echo ""
fi

echo ""
echo "インストール完了！"
echo ""
echo "使い方:"
echo "  claude-sandbox doctor        # 環境を診断"
echo "  claude-sandbox               # 現在のディレクトリで起動"
echo "  claude-sandbox --profile python  # Python プロファイルで起動"
echo ""
echo "初回起動前に 1Password で以下のアイテムを作成してください:"
echo "  - 「Claude Code」（credential フィールド）→ 初回起動後に自動作成"
echo "  - 「SSH Key」（private key フィールド）"
echo "  - 「Anthropic」（api_key フィールド）"
echo ""
