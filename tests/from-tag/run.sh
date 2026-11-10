#!/bin/bash
# Automated tests for the "Resolve from-tag" step of platform-core's argo-prod-deploy.
# step.sh is a verbatim copy of that step's `run:` body. `curl` is stubbed (exit 0 = tag exists,
# exit 22 = 404); GITHUB_OUTPUT is isolated per case. Exits non-zero if any case fails.
D=$(cd "$(dirname "$0")" && pwd); fails=0
ORD='[{"region":"us-east-1"},{"region":"eu-west-1"}]'
info(){ echo "{\"us-east-1\":{\"version\":\"$1\"},\"eu-west-1\":{\"version\":\"$2\"}}"; }

# check <name> <expected value|-> <expected curl tag|-> <region_info> <order> <new> <prefix> <curl_ok 0|1>
check(){
  local name=$1 want=$2 wantcurl=$3 T; T=$(mktemp -d); mkdir "$T/bin"
  if [ "$8" = 1 ]; then printf '#!/bin/bash\necho "${@: -1}" >> %s/curl.log\nexit 0\n' "$T" > "$T/bin/curl"
  else printf '#!/bin/bash\necho "${@: -1}" >> %s/curl.log\nexit 22\n' "$T" > "$T/bin/curl"; fi
  chmod +x "$T/bin/curl"; : > "$T/out"
  env -i PATH="$T/bin:/usr/bin:/bin:/usr/local/bin" REGION_INFO="$4" REGION_ORDER="$5" NEW_VERSION="$6" TAG_PREFIX="$7" \
    GITHUB_TOKEN=x GITHUB_API_URL=https://api.github.com GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$T/out" \
    bash --noprofile --norc -e -o pipefail -c "$(cat "$D/step.sh")" > "$T/log" 2>&1
  local got gotcurl; got=$(sed -n 's/^value=//p' "$T/out"); gotcurl=$(sed 's#.*/git/ref/tags/##' "$T/curl.log" 2>/dev/null | head -1)
  [ -z "$got" ] && got="-"; [ -z "$gotcurl" ] && gotcurl="-"
  if [ "$got" = "$want" ] && [ "$gotcurl" = "$wantcurl" ]; then echo "PASS $name"
  else echo "FAIL $name (value '$got' want '$want'; looked up '$gotcurl' want '$wantcurl')"; fails=$((fails+1)); fi
}
check "rollback: prod 1.0.0, deploying 1.0.2"        acct-1.0.0 acct-1.0.0 "$(info 1.0.0 1.0.0)" "$ORD" 1.0.2 acct- 1
check "first region decides"                         acct-1.0.0 acct-1.0.0 "$(info 1.0.0 1.0.1)" "$ORD" 1.0.2 acct- 1
check "first region decides (reversed order)"        acct-1.0.1 acct-1.0.1 "$(info 1.0.0 1.0.1)" '[{"region":"eu-west-1"},{"region":"us-east-1"}]' 1.0.2 acct- 1
check "numeric boundary 1.9.9 -> 1.10.0"            acct-1.9.9 acct-1.9.9 "$(info 1.9.9 1.9.9)" "$ORD" 1.10.0 acct- 1
check "older deploy 1.10.0 -> 1.9.9 stays unset"     - - "$(info 1.10.0 1.10.0)" "$ORD" 1.9.9 acct- 1
check "equal version stays unset"                    - - "$(info 1.0.2 1.0.2)" "$ORD" 1.0.2 acct- 1
check "prod newer stays unset"                       - - "$(info 2.0.0 2.0.0)" "$ORD" 1.0.2 acct- 1
check "prod version missing stays unset"             - - '{}' "$ORD" 1.0.2 acct- 1
check "empty region info stays unset"                - - '' "$ORD" 1.0.2 acct- 1
check "pre-release prod stays unset"                 - - "$(info 1.0.2-rc.1 1.0.2-rc.1)" "$ORD" 1.0.3 acct- 1
check "pre-release deploy stays unset"               - - "$(info 1.0.0 1.0.0)" "$ORD" 1.0.3-rc.1 acct- 1
check "tag lookup fails stays unset"                 - acct-1.0.0 "$(info 1.0.0 1.0.0)" "$ORD" 1.0.2 acct- 0
check "plain v prefix"                               v1.0.0 v1.0.0 "$(info 1.0.0 1.0.0)" "$ORD" 1.0.2 v 1
check "empty region order stays unset"               - - "$(info 1.0.0 1.0.0)" '[]' 1.0.2 acct- 1
check "malformed region info stays unset"            - - 'not json' "$ORD" 1.0.2 acct- 1
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
