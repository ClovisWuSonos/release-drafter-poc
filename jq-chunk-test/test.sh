#!/usr/bin/env bash
# Runs chunk.sh under the same flags GitHub uses for `shell: bash` and checks every jq failure mode.
cd "$(dirname "$0")"
BASH_BIN=$(command -v bash); fails=0
run() {  # $1=name  $2=previous-region-info  $3=commit sha  $4=PATH to use
  LINKS_FILE=$(mktemp); out=$(mktemp); err=$(mktemp)
  env -i PATH="${4:-$PATH}" LINKS_FILE="$LINKS_FILE" INPUT_PREVIOUS_REGION_INFO="$2" INPUT_COMMIT_SHA="${3:-bbbbbbb}" \
    "$BASH_BIN" --noprofile --norc -e -o pipefail ./chunk.sh >"$out" 2>"$err"; rc=$?
  links=$(cat "$LINKS_FILE"); so=$(cat "$out"); se=$(cat "$err"); rm -f "$LINKS_FILE" "$out" "$err"
}
check() { if [[ "$2" == "ok" ]]; then echo "PASS $1"; else echo "FAIL $1   [$3]"; fails=$((fails+1)); fi; }
WARN="::warning::No Compare changes link added: jq command failed"

for c in "invalid JSON|not json" "JSON null|null" "number root|5" "string root|\"abc\"" "numeric sha|{\"a\":{\"sha\":1234567}}"; do
  name=${c%%|*}; prev=${c#*|}; run "$name" "$prev"
  echo "   [$name] stdout='$so' stderr='${se:0:75}'"
  [[ $rc == 0 && -z "$links" && "$so" == "$WARN" && "$se" == jq:* ]] && check "$name: exit 0, no link, warning on stdout, jq error on stderr" ok || check "$name" bad "rc=$rc links=$links so=$so se=$se"
done
run valid '{"a":{"sha":"aaaaaaa"}}'
[[ $rc == 0 && "$links" == "[Compare changes](https://github.com/example-org/example-repo/compare/aaaaaaa..bbbbbbb)" && -z "$so" && -z "$se" ]] && check "valid JSON: link added, nothing printed" ok || check "valid JSON" bad "rc=$rc links=$links so=$so se=$se"
run two-regions '{"a":{"sha":"aaaaaaa"},"b":{"sha":"ccccccc"}}'
[[ $rc == 0 && $(echo "$links" | wc -l | tr -d ' ') == 2 && "$links" == *"[Compare (a)]"* && "$links" == *"[Compare (b)]"* ]] && check "two different previous SHAs: one link per region" ok || check "two regions" bad "$links"
run redeploy '{"a":{"sha":"bbbbbbb"}}'; [[ $rc == 0 && -z "$links" && -z "$so" ]] && check "same SHA (redeploy): no link, no warning" ok || check "redeploy" bad "$links|$so"
run empty ''; [[ $rc == 0 && -z "$links" && -z "$so" ]] && check "empty previous-region-info: no link, no warning" ok || check "empty" bad "$links|$so"
run bad-new-sha '{"a":{"sha":"aaaaaaa"}}' 'zz;x'; [[ $rc == 0 && -z "$links" && -z "$so" ]] && check "invalid commit sha: no link, no warning" ok || check "bad new sha" bad "$links|$so"
nojq=$(mktemp -d); run no-jq '{"a":{"sha":"aaaaaaa"}}' bbbbbbb "$nojq"; rmdir "$nojq"
echo "   [jq missing] stdout='$so' stderr='${se: -50}'"
[[ $rc == 0 && -z "$links" && "$so" == "$WARN" && "$se" == *"jq"* ]] && check "jq not installed: exit 0, no link, warning on stdout, error on stderr" ok || check "jq missing" bad "rc=$rc so=$so se=$se"
echo; [[ $fails == 0 ]] && echo "RESULT: all checks passed" || echo "RESULT: $fails check(s) failed"; exit $fails
