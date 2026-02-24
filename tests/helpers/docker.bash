# tests/helpers/docker.bash
# bats 統合テスト用 Docker ヘルパー
# setup() 内で source して使う

TEST_IMAGE="${TEST_IMAGE:-claude-sandbox}"

# ----------------------------------------------------------------
# 前提チェック
# ----------------------------------------------------------------

# Docker が利用できなければテストをスキップ
require_docker() {
    if ! docker info &>/dev/null 2>&1; then
        skip "Docker が利用できません（統合テストをスキップ）"
    fi
}

# ホスト側のネットワーク疎通が必要なテスト用
require_network() {
    if ! curl -sf --connect-timeout 3 -o /dev/null https://registry.npmjs.org; then
        skip "ネットワーク疎通なし（ネットワーク統合テストをスキップ）"
    fi
}

# ----------------------------------------------------------------
# イメージ管理
# ----------------------------------------------------------------

# イメージが存在しなければビルド（初回のみ時間がかかる）
ensure_image() {
    if ! docker image inspect "$TEST_IMAGE" &>/dev/null 2>&1; then
        echo "# [docker.bash] イメージをビルド中: $TEST_IMAGE" >&3
        docker build -t "$TEST_IMAGE" "$REPO_ROOT" >&2
    fi
}

# ----------------------------------------------------------------
# フェイクバイナリ
# ----------------------------------------------------------------

# テスト用フェイク claude バイナリを作成し、パスを echo する
# entrypoint の「claude バイナリ存在チェック」を通過させるために使う
# 用途例:
#   setup() { FAKE_CLAUDE="$(make_fake_claude)"; }
#   teardown() { rm -f "$FAKE_CLAUDE"; }
#   test: -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude"
make_fake_claude() {
    local f
    f="$(mktemp)"
    printf '#!/bin/bash\nexec "$@"\n' > "$f"
    chmod 755 "$f"
    echo "$f"
}
