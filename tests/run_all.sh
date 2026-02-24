#!/usr/bin/env bash
# tests/run_all.sh
# shellcheck + bats 単体テスト + Docker 統合テストをまとめて実行する
#
# オプション:
#   --unit-only       shellcheck + 単体テストのみ（Docker 不要）
#   --integration     統合テストも実行（Docker + ネットワーク必要）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# bats は日本語テスト名のために bash 5 が必要
# Homebrew 版があれば優先して使う
if [[ -x /opt/homebrew/bin/bash ]]; then
    export BASH=/opt/homebrew/bin/bash
fi

# ================================================================
# ユーティリティ
# ================================================================

ok()   { echo -e "\033[32m[PASS]\033[0m $*"; }
fail() { echo -e "\033[31m[FAIL]\033[0m $*"; }
info() { echo -e "\033[34m[INFO]\033[0m $*"; }

overall_exit=0
RUN_INTEGRATION=false

# 引数パース
for arg in "$@"; do
    case "$arg" in
        --integration) RUN_INTEGRATION=true ;;
        --unit-only)   RUN_INTEGRATION=false ;;
    esac
done

# ================================================================
# shellcheck
# ================================================================

run_shellcheck() {
    echo ""
    echo "=== shellcheck ==="

    if ! command -v shellcheck &>/dev/null; then
        echo "  shellcheck が見つかりません。スキップします。"
        echo "  → brew install shellcheck"
        return
    fi

    local targets=(
        "$REPO_ROOT/claude-sandbox"
        "$REPO_ROOT/entrypoint.sh"
        "$REPO_ROOT/init-network.sh"
        "$REPO_ROOT/install.sh"
        "$REPO_ROOT/tests/helpers/mocks.bash"
        "$REPO_ROOT/tests/helpers/docker.bash"
    )

    local sc_exit=0
    for f in "${targets[@]}"; do
        if shellcheck "$f"; then
            ok "$f"
        else
            fail "$f"
            sc_exit=1
        fi
    done

    if [[ $sc_exit -ne 0 ]]; then
        overall_exit=1
    fi
}

# ================================================================
# bats 単体テスト
# ================================================================

run_unit_tests() {
    echo ""
    echo "=== bats unit tests ==="

    if ! command -v bats &>/dev/null; then
        echo "  bats が見つかりません。スキップします。"
        echo "  → brew install bats-core"
        return
    fi

    local bats_exit=0
    bats "$REPO_ROOT/tests/unit/" || bats_exit=$?

    if [[ $bats_exit -ne 0 ]]; then
        overall_exit=1
    fi
}

# ================================================================
# Docker 統合テスト
# ================================================================

run_integration_tests() {
    echo ""
    echo "=== bats integration tests (Docker) ==="

    if ! command -v bats &>/dev/null; then
        echo "  bats が見つかりません。スキップします。"
        return
    fi

    if ! docker info &>/dev/null 2>&1; then
        echo "  Docker が利用できません。統合テストをスキップします。"
        echo "  → colima start"
        return
    fi

    # イメージが存在しなければビルド（初回のみ時間がかかる）
    if ! docker image inspect "${TEST_IMAGE:-claude-sandbox}" &>/dev/null 2>&1; then
        info "Docker イメージをビルド中..."
        docker build -t "${TEST_IMAGE:-claude-sandbox}" "$REPO_ROOT" >&2
    fi

    local bats_exit=0
    bats "$REPO_ROOT/tests/integration/" || bats_exit=$?

    if [[ $bats_exit -ne 0 ]]; then
        overall_exit=1
    fi
}

# ================================================================
# メイン
# ================================================================

info "テスト対象リポジトリ: $REPO_ROOT"

if [[ "$RUN_INTEGRATION" == "true" ]]; then
    info "モード: 単体テスト + 統合テスト"
else
    info "モード: 単体テストのみ（統合テストは --integration で実行）"
fi

run_shellcheck
run_unit_tests

if [[ "$RUN_INTEGRATION" == "true" ]]; then
    run_integration_tests
fi

echo ""
if [[ $overall_exit -eq 0 ]]; then
    ok "全テスト通過"
else
    fail "失敗したテストがあります"
fi

exit $overall_exit
