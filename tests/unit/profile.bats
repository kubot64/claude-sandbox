#!/usr/bin/env bats
# tests/unit/profile.bats
# resolve_profile 関数のテスト

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    source "$REPO_ROOT/claude-sandbox"
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ----------------------------------------------------------------
# explicit=false の挙動
# ----------------------------------------------------------------

@test "resolve_profile: explicit=false かつ profile_file 存在 → ファイルの値を返す" {
    local profile_file="$TEST_DIR/profile"
    echo "python" > "$profile_file"
    run resolve_profile "false" "node" "$profile_file"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "python" ]]
}

@test "resolve_profile: explicit=false かつ profile_file 不在 → デフォルト値を返す" {
    run resolve_profile "false" "node" "$TEST_DIR/nonexistent"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "node" ]]
}

# ----------------------------------------------------------------
# explicit=true の挙動
# ----------------------------------------------------------------

@test "resolve_profile: explicit=true かつ profile_file 存在 → 引数の値を優先する" {
    local profile_file="$TEST_DIR/profile"
    echo "python" > "$profile_file"
    run resolve_profile "true" "go" "$profile_file"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "go" ]]
}

@test "resolve_profile: explicit=true かつ profile_file 不在 → 引数の値を返す" {
    run resolve_profile "true" "rust" "$TEST_DIR/nonexistent"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "rust" ]]
}

# ----------------------------------------------------------------
# エッジケース
# ----------------------------------------------------------------

@test "resolve_profile: profile_file が空でも explicit=false → デフォルト値を返す" {
    local profile_file="$TEST_DIR/empty_profile"
    touch "$profile_file"
    # ファイルは存在するが内容は空 → cat が空文字列を返す
    run resolve_profile "false" "node" "$profile_file"
    [[ "$status" -eq 0 ]]
    # 空文字列が返ってくる（空ファイルなので）
    [[ "$output" == "" ]]
}
