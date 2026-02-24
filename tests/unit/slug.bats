#!/usr/bin/env bats
# tests/unit/slug.bats
# make_slug 関数のテスト

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    source "$REPO_ROOT/claude-sandbox"
    # realpath は存在するパスが必要なので mktemp で実ディレクトリを作る
    TEST_DIR="$(mktemp -d)"
    DIR_A="$(mktemp -d -t projectA.XXXX)"
    DIR_B="$(mktemp -d -t projectB.XXXX)"
    DIR_HASH="$(mktemp -d -t test.XXXX)"
    DIR_UNDER="$(mktemp -d -t my_project_name.XXXX)"
    NAMED_DIR="${TEST_DIR}/myapp"
    mkdir -p "$NAMED_DIR"
}

teardown() {
    rm -rf "$TEST_DIR" "$DIR_A" "$DIR_B" "$DIR_HASH" "$DIR_UNDER"
}

@test "make_slug: フォーマットが <basename>_<12桁hash> になる" {
    local slug
    slug=$(make_slug "$NAMED_DIR")
    [[ "$slug" =~ ^myapp_[0-9a-f]{12}$ ]]
}

@test "make_slug: 同じパスは常に同じスラグになる" {
    local slug1 slug2
    slug1=$(make_slug "$NAMED_DIR")
    slug2=$(make_slug "$NAMED_DIR")
    [[ "$slug1" == "$slug2" ]]
}

@test "make_slug: 異なるパスは異なるスラグになる" {
    local slug1 slug2
    slug1=$(make_slug "$DIR_A")
    slug2=$(make_slug "$DIR_B")
    [[ "$slug1" != "$slug2" ]]
}

@test "make_slug: ハッシュ部分がちょうど12文字" {
    local slug hash_part
    slug=$(make_slug "$DIR_HASH")
    hash_part="${slug##*_}"
    [[ "${#hash_part}" -eq 12 ]]
}

@test "make_slug: basename にアンダースコアを含む場合もフォーマットが正しい" {
    local slug
    slug=$(make_slug "$DIR_UNDER")
    # my_project_name.XXXX 形式のベース名にマッチ
    [[ "$slug" =~ _[0-9a-f]{12}$ ]]
}
