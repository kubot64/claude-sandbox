# tests/helpers/mocks.bash
# bats テスト用モックヘルパー
# setup() 内で source して使う

# モック用 bin ディレクトリを PATH の先頭に追加
setup_mock_bin() {
    MOCK_BIN="$(mktemp -d)"
    export PATH="$MOCK_BIN:$PATH"
    export MOCK_BIN
}

# モック用 bin ディレクトリを削除
teardown_mock_bin() {
    [[ -n "${MOCK_BIN:-}" ]] && rm -rf "$MOCK_BIN"
}

# ----------------------------------------------------------------
# op モック
# ----------------------------------------------------------------

# op が常に成功するモック（呼び出しログを MOCK_BIN/op_calls に記録）
mock_op_success() {
    cat > "$MOCK_BIN/op" <<'EOF'
#!/bin/bash
echo "$*" >> "${MOCK_BIN}/op_calls"
exit 0
EOF
    chmod +x "$MOCK_BIN/op"
}

# op が常に失敗するモック
mock_op_failure() {
    cat > "$MOCK_BIN/op" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN/op"
}

# op read が指定した値を返すモック
# 使い方: mock_op_read '{"key":"value"}'
mock_op_read() {
    local return_value="$1"
    cat > "$MOCK_BIN/op" <<EOF
#!/bin/bash
if [[ "\$1" == "read" ]]; then
    echo '$return_value'
    exit 0
fi
echo "\$*" >> "\${MOCK_BIN}/op_calls"
exit 0
EOF
    chmod +x "$MOCK_BIN/op"
}

# ----------------------------------------------------------------
# docker モック
# ----------------------------------------------------------------

mock_docker_success() {
    cat > "$MOCK_BIN/docker" <<'EOF'
#!/bin/bash
echo "$*" >> "${MOCK_BIN}/docker_calls"
exit 0
EOF
    chmod +x "$MOCK_BIN/docker"
}

# ----------------------------------------------------------------
# テンポラリディレクトリ管理
# ----------------------------------------------------------------

# テスト用の SANDBOX_DIR を作成する
setup_sandbox_dir() {
    TEST_SANDBOX_DIR="$(mktemp -d)"
    export SANDBOX_DIR="$TEST_SANDBOX_DIR"
    export SHARED_DIR="$SANDBOX_DIR/shared"
    export PROJECTS_DIR="$SANDBOX_DIR/projects"
    mkdir -p "$SHARED_DIR/.claude" "$PROJECTS_DIR"
}

teardown_sandbox_dir() {
    [[ -n "${TEST_SANDBOX_DIR:-}" ]] && rm -rf "$TEST_SANDBOX_DIR"
}
