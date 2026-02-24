#!/usr/bin/env bats
# tests/unit/lock.bats
# acquire_lock / release_lock のテスト

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    source "$REPO_ROOT/claude-sandbox"
    TEST_DIR="$(mktemp -d)"
    # PROJECTS_DIR を一時ディレクトリに向ける
    export PROJECTS_DIR="$TEST_DIR/projects"
    mkdir -p "$PROJECTS_DIR"
    # グローバル変数をリセット
    LOCK_DIR=""
    LOCK_PID_FILE=""
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "acquire_lock: 正常にロックを取得できる" {
    local proj="$TEST_DIR/proj1"
    mkdir -p "$proj"
    acquire_lock "$proj"
    [[ -d "$proj/.lock" ]]
    [[ -f "$proj/.lock/pid" ]]
    local pid_in_file
    pid_in_file=$(cat "$proj/.lock/pid")
    [[ "$pid_in_file" == "$$" ]]
}

@test "acquire_lock: 生きているPIDのlockがあると失敗する" {
    local proj="$TEST_DIR/proj2"
    mkdir -p "$proj/.lock"
    echo "$$" > "$proj/.lock/pid"  # 現在プロセスのPID（確実に生きている）
    run acquire_lock "$proj"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "別のセッションが実行中" ]]
}

@test "acquire_lock: 死んでいるPIDのlockはstale扱いで回収して再取得する" {
    local proj="$TEST_DIR/proj3"
    mkdir -p "$proj/.lock"
    echo "99999999" > "$proj/.lock/pid"  # 存在しないPID
    acquire_lock "$proj"
    # ロックが再取得されていること
    [[ -d "$proj/.lock" ]]
    local pid_in_file
    pid_in_file=$(cat "$proj/.lock/pid")
    [[ "$pid_in_file" == "$$" ]]
}

@test "acquire_lock: pidファイルが空のstale lockも回収する" {
    local proj="$TEST_DIR/proj4"
    mkdir -p "$proj/.lock"
    touch "$proj/.lock/pid"  # 空ファイル
    acquire_lock "$proj"
    [[ -d "$proj/.lock" ]]
}

@test "release_lock: lock ディレクトリを削除する" {
    local proj="$TEST_DIR/proj5"
    mkdir -p "$proj"
    acquire_lock "$proj"
    [[ -d "$proj/.lock" ]]
    release_lock
    [[ ! -d "$proj/.lock" ]]
}

@test "release_lock: lock なしで呼んでもエラーにならない" {
    LOCK_DIR=""
    run release_lock
    [[ "$status" -eq 0 ]]
}
