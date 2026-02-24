#!/usr/bin/env bats
# tests/unit/save_token.bats
# save_claude_token のテスト

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
HELPERS="$REPO_ROOT/tests/helpers/mocks.bash"

setup() {
    source "$REPO_ROOT/claude-sandbox"
    source "$HELPERS"
    setup_mock_bin
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    teardown_mock_bin
    rm -rf "$TEST_DIR"
}

# ----------------------------------------------------------------
# スキップ条件
# ----------------------------------------------------------------

@test "save_claude_token: ファイルが存在しない場合はスキップ" {
    mock_op_success
    run save_claude_token "$TEST_DIR/nonexistent.json" ""
    [[ "$status" -eq 0 ]]
    # op が呼ばれていないこと
    [[ ! -f "$MOCK_BIN/op_calls" ]]
}

@test "save_claude_token: 空ファイルの場合はスキップ" {
    mock_op_success
    local token_file="$TEST_DIR/empty.json"
    touch "$token_file"
    run save_claude_token "$token_file" ""
    [[ "$status" -eq 0 ]]
    [[ ! -f "$MOCK_BIN/op_calls" ]]
}

@test "save_claude_token: 不正な JSON の場合は警告してスキップ" {
    mock_op_success
    local token_file="$TEST_DIR/invalid.json"
    echo "not-json-at-all" > "$token_file"
    run save_claude_token "$token_file" ""
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "不正な JSON" ]]
    # op が呼ばれていないこと
    [[ ! -f "$MOCK_BIN/op_calls" ]]
}

@test "save_claude_token: 内容が initial と同じ場合はスキップ" {
    mock_op_success
    local json='{"sessionToken":"abc123"}'
    local token_file="$TEST_DIR/same.json"
    echo "$json" > "$token_file"
    run save_claude_token "$token_file" "$json"
    [[ "$status" -eq 0 ]]
    [[ ! -f "$MOCK_BIN/op_calls" ]]
}

# ----------------------------------------------------------------
# 保存実行条件
# ----------------------------------------------------------------

@test "save_claude_token: 有効な JSON かつ変更あり → op item edit を呼ぶ" {
    # op item get が成功するモック（アイテムが存在する）
    cat > "$MOCK_BIN/op" <<'EOF'
#!/bin/bash
echo "$*" >> "${MOCK_BIN}/op_calls"
exit 0
EOF
    chmod +x "$MOCK_BIN/op"

    local new_json='{"sessionToken":"new_token_xyz"}'
    local old_json='{"sessionToken":"old_token_abc"}'
    local token_file="$TEST_DIR/changed.json"
    echo "$new_json" > "$token_file"

    run save_claude_token "$token_file" "$old_json"
    [[ "$status" -eq 0 ]]
    # op が呼ばれたこと
    [[ -f "$MOCK_BIN/op_calls" ]]
}

@test "save_claude_token: 保存後にトークンファイルを削除する" {
    cat > "$MOCK_BIN/op" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/op"

    local json='{"sessionToken":"new_token"}'
    local token_file="$TEST_DIR/todel.json"
    echo "$json" > "$token_file"

    save_claude_token "$token_file" ""
    [[ ! -f "$token_file" ]]
}
