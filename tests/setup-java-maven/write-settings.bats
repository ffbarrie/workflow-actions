#!/usr/bin/env bats
# Covers actions/setup-java-maven/write-settings.sh's line-splitting,
# validation, and XML escaping.

SCRIPT="$BATS_TEST_DIRNAME/../../actions/setup-java-maven/write-settings.sh"

setup() {
  FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME"
  export HOME="$FAKE_HOME"
}

@test "single server" {
  SERVER_IDS="github" SERVER_USERNAMES="octocat" SERVER_PASSWORDS="tok123" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "<id>github</id>" "$HOME/.m2/settings.xml"
  grep -q "<username>octocat</username>" "$HOME/.m2/settings.xml"
  grep -q "<password>tok123</password>" "$HOME/.m2/settings.xml"
}

@test "multiple servers, paired by line position" {
  SERVER_IDS=$'github\ninternal-releases' \
    SERVER_USERNAMES=$'octocat\nmavenuser' \
    SERVER_PASSWORDS=$'tok1\ntok2' \
    run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  content=$(cat "$HOME/.m2/settings.xml")
  [[ "$content" == *"<id>github</id>"* ]]
  [[ "$content" == *"<id>internal-releases</id>"* ]]
  [[ "$content" == *"<username>mavenuser</username>"* ]]
}

@test "single server with no trailing newline (plain scalar input) still works" {
  # A caller passing a single id as a bare scalar (not a | block) won't
  # have a trailing newline — this is the case that a plain `while read`
  # would silently drop without the `|| [ -n "$line" ]` guard.
  SERVER_IDS="github" SERVER_USERNAMES="octocat" SERVER_PASSWORDS="tok123" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "<id>github</id>" "$HOME/.m2/settings.xml"
}

@test "mismatched line counts are rejected" {
  SERVER_IDS=$'github\ninternal' SERVER_USERNAMES="octocat" SERVER_PASSWORDS=$'a\nb' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must have the same number of lines"* ]]
}

@test "a blank line in the middle is rejected, not just a length mismatch" {
  SERVER_IDS=$'github\n\ninternal' SERVER_USERNAMES=$'a\nb\nc' SERVER_PASSWORDS=$'x\ny\nz' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"blank line at position 2"* ]]
}

@test "special XML characters in the password are escaped" {
  SERVER_IDS="github" SERVER_USERNAMES="octocat" SERVER_PASSWORDS='tok&123<456>"789"' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  content=$(cat "$HOME/.m2/settings.xml")
  [[ "$content" == *"tok&amp;123&lt;456&gt;&quot;789&quot;"* ]]
}

@test "all-empty input (action.yml gates this via if: server-ids != '', but the script itself handles it) writes an empty but valid servers block" {
  SERVER_IDS="" SERVER_USERNAMES="" SERVER_PASSWORDS="" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "<settings>" "$HOME/.m2/settings.xml"
  grep -q "<servers>" "$HOME/.m2/settings.xml"
}
