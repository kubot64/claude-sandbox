#!/usr/bin/env bats
# tests/integration/firewall.bats
# ファイアウォール（tinyproxy + iptables）の動作テスト
#
# [環境変数テスト] ネットワーク接続不要
#   - DISABLE_FIREWALL=false → HTTP_PROXY が設定される
#   - DISABLE_FIREWALL=true  → HTTP_PROXY が設定されない
#
# [ネットワークテスト] 実通信あり（require_network）
#   - 許可ホスト → tinyproxy が CONNECT を通す (200)
#   - 非許可ホスト → tinyproxy が拒否する (403)

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

# ----------------------------------------------------------------
# 環境変数テスト（ネットワーク不要）
# ----------------------------------------------------------------

@test "firewall: DISABLE_FIREWALL=false のとき HTTP_PROXY が設定される" {
    run docker run --rm \
        --cap-add NET_ADMIN \
        --sysctl net.ipv6.conf.all.disable_ipv6=1 \
        -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude" \
        -e PROFILE=node \
        -e DISABLE_FIREWALL=false \
        -e CLAUDE_JSON="" \
        -e SSH_KEY="" \
        "$TEST_IMAGE" \
        bash -c 'echo "PROXY:${HTTP_PROXY:-UNSET}"'
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "PROXY:http://127.0.0.1:8888" ]]
}

@test "firewall: DISABLE_FIREWALL=true のとき HTTP_PROXY が設定されない" {
    run docker run --rm \
        -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude" \
        -e PROFILE=node \
        -e DISABLE_FIREWALL=true \
        -e CLAUDE_JSON="" \
        -e SSH_KEY="" \
        "$TEST_IMAGE" \
        bash -c 'echo "PROXY:${HTTP_PROXY:-UNSET}"'
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "PROXY:UNSET" ]]
}

# ----------------------------------------------------------------
# ネットワークテスト（実通信あり）
# ----------------------------------------------------------------

@test "firewall: 許可ホスト (registry.npmjs.org) への CONNECT は 200 を返す" {
    require_network
    run docker run --rm \
        --cap-add NET_ADMIN \
        --sysctl net.ipv6.conf.all.disable_ipv6=1 \
        -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude" \
        -e PROFILE=node \
        -e DISABLE_FIREWALL=false \
        -e CLAUDE_JSON="" \
        -e SSH_KEY="" \
        "$TEST_IMAGE" \
        bash -c '
            code=$(curl -s \
                --proxy http://127.0.0.1:8888 \
                --connect-timeout 10 \
                -w "%{http_connect}" \
                -o /dev/null \
                https://registry.npmjs.org 2>/dev/null || true)
            echo "CONNECT_CODE:${code}"
        '
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "CONNECT_CODE:200" ]]
}

@test "firewall: 非許可ホストへの CONNECT は 403 を返す" {
    run docker run --rm \
        --cap-add NET_ADMIN \
        --sysctl net.ipv6.conf.all.disable_ipv6=1 \
        -v "${FAKE_CLAUDE}:/home/claude/.local/bin/claude" \
        -e PROFILE=node \
        -e DISABLE_FIREWALL=false \
        -e CLAUDE_JSON="" \
        -e SSH_KEY="" \
        "$TEST_IMAGE" \
        bash -c '
            code=$(curl -s \
                --proxy http://127.0.0.1:8888 \
                --connect-timeout 5 \
                -w "%{http_connect}" \
                -o /dev/null \
                https://definitely-not-in-allowlist.evil.test 2>/dev/null || true)
            echo "CONNECT_CODE:${code}"
        '
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "CONNECT_CODE:403" ]]
}
