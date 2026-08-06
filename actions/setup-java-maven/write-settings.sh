#!/usr/bin/env bash
# Reads SERVER_IDS, SERVER_USERNAMES, SERVER_PASSWORDS (newline-delimited,
# paired by line position) from the environment. Writes ~/.m2/settings.xml,
# replacing it entirely — see server-ids' description in action.yml for
# why that's deliberate.
set -euo pipefail
# while-read (not readarray/mapfile) for portability to bash 3.2 (macOS runners' /bin/bash).
ids=()
while IFS= read -r line || [ -n "$line" ]; do ids+=("$line"); done < <(printf '%s' "$SERVER_IDS")
usernames=()
while IFS= read -r line || [ -n "$line" ]; do usernames+=("$line"); done < <(printf '%s' "$SERVER_USERNAMES")
passwords=()
while IFS= read -r line || [ -n "$line" ]; do passwords+=("$line"); done < <(printf '%s' "$SERVER_PASSWORDS")
if [ "${#ids[@]}" -ne "${#usernames[@]}" ] || [ "${#ids[@]}" -ne "${#passwords[@]}" ]; then
  echo "::error::setup-java-maven: server-ids (${#ids[@]}), server-usernames (${#usernames[@]}), and server-passwords (${#passwords[@]}) must have the same number of lines."
  exit 1
fi
for i in "${!ids[@]}"; do
  if [ -z "${ids[$i]}" ] || [ -z "${usernames[$i]}" ] || [ -z "${passwords[$i]}" ]; then
    echo "::error::setup-java-maven: blank line at position $((i + 1)) in server-ids/server-usernames/server-passwords (id='${ids[$i]}', username='${usernames[$i]}'). Each must be non-empty and free of blank lines."
    exit 1
  fi
done
mkdir -p ~/.m2
xml_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e "s/'/\&apos;/g" -e 's/"/\&quot;/g'
}
{
  echo '<settings>'
  echo '  <servers>'
  for i in "${!ids[@]}"; do
    id=$(printf '%s' "${ids[$i]}" | xml_escape)
    username=$(printf '%s' "${usernames[$i]}" | xml_escape)
    password=$(printf '%s' "${passwords[$i]}" | xml_escape)
    echo '    <server>'
    echo "      <id>${id}</id>"
    echo "      <username>${username}</username>"
    echo "      <password>${password}</password>"
    echo '    </server>'
  done
  echo '  </servers>'
  echo '</settings>'
} > ~/.m2/settings.xml
