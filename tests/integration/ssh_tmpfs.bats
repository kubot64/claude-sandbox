#!/usr/bin/env bats
# tests/integration/ssh_tmpfs.bats
# SSH 鍵の tmpfs マウント確認テスト
#
# SSH_KEY が設定されているとき、entrypoint.sh は
# /home/claude/.ssh を tmpfs にマウントして鍵を書き込む。
# マウント後に exit すると trap により鍵ファイルが削除される。
#
# --cap-add SYS_ADMIN が必要（mount -t tmpfs のため）

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

@test "ssh_tmpfs: SSH_KEY が設定されると /home/claude/.ssh が tmpfs になる" {
    # tmpfs マウントには --privileged が必要（Colima では SYS_ADMIN のみでは不十分）
    run docker run --rm \
        --privileged \
        -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude" \
        -e PROFILE=node \
        -e DISABLE_FIREWALL=true \
        -e CLAUDE_JSON="" \
        -e SSH_KEY="fake-test-key-content" \
        "$TEST_IMAGE" \
        bash -c '
            mount | grep "tmpfs on /home/claude/.ssh" && echo "SSH_TMPFS:yes"
        '
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "SSH_TMPFS:yes" ]]
}

@test "ssh_tmpfs: SSH_KEY が空のとき /home/claude/.ssh は通常ディレクトリ" {
    run docker run --rm \
        -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude" \
        -e PROFILE=node \
        -e DISABLE_FIREWALL=true \
        -e CLAUDE_JSON="" \
        -e SSH_KEY="" \
        "$TEST_IMAGE" \
        bash -c '
            if mount | grep -q "tmpfs on /home/claude/.ssh"; then
                echo "SSH_TMPFS:yes"
            else
                echo "SSH_TMPFS:no"
            fi
        '
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "SSH_TMPFS:no" ]]
}

@test "ssh_tmpfs: SSH_KEY の内容が /home/claude/.ssh/id_rsa に書き込まれる" {
    run docker run --rm \
        --privileged \
        -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude" \
        -e PROFILE=node \
        -e DISABLE_FIREWALL=true \
        -e CLAUDE_JSON="" \
        -e SSH_KEY="TEST_KEY_CONTENT_XYZ" \
        "$TEST_IMAGE" \
        bash -c 'cat /home/claude/.ssh/id_rsa 2>/dev/null && echo "KEY_READ:ok"'
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "TEST_KEY_CONTENT_XYZ" ]]
    [[ "$output" =~ "KEY_READ:ok" ]]
}
