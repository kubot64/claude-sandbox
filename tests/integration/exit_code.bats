#!/usr/bin/env bats
# tests/integration/exit_code.bats
# entrypoint.sh の終了コード伝播テスト
#
# 検証内容:
#   setpriv でスイッチしたコマンドの終了コードが
#   docker run の終了コードとして正しく伝播することを確認する

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    source "$REPO_ROOT/tests/helpers/docker.bash"
    require_docker
    ensure_image
    FAKE_CLAUDE="$(make_fake_claude)"
}

teardown() {
    rm -f "${FAKE_CLAUDE:-}"
}

@test "exit_code: 終了コード 0 を伝播する" {
    run docker run --rm \
        -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude" \
        -e PROFILE=node \
        -e DISABLE_FIREWALL=true \
        -e CLAUDE_JSON="" \
        -e SSH_KEY="" \
        "$TEST_IMAGE" \
        bash -c "exit 0"
    [[ "$status" -eq 0 ]]
}

@test "exit_code: 任意の終了コード (42) を伝播する" {
    run docker run --rm \
        -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude" \
        -e PROFILE=node \
        -e DISABLE_FIREWALL=true \
        -e CLAUDE_JSON="" \
        -e SSH_KEY="" \
        "$TEST_IMAGE" \
        bash -c "exit 42"
    [[ "$status" -eq 42 ]]
}

@test "exit_code: コマンド失敗時は非ゼロを返す" {
    run docker run --rm \
        -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude" \
        -e PROFILE=node \
        -e DISABLE_FIREWALL=true \
        -e CLAUDE_JSON="" \
        -e SSH_KEY="" \
        "$TEST_IMAGE" \
        false
    [[ "$status" -ne 0 ]]
}
