#!/usr/bin/env bash
# Runs the two validation shell steps (verbatim from argo-rollback-test-java/workflow.yml) against cases with
# expected accept/reject results. Needs only bash. No network, no secrets.
cd "$(dirname "$0")"; fail=0
chk() { # name expected(accept|reject) rc
  got=reject; [ "$3" -eq 0 ] && got=accept
  if [ "$got" = "$2" ]; then echo "PASS  $1 ($got)"; else echo "FAIL  $1: expected $2, got $got"; fail=1; fi
}
region() { env -i PATH=/usr/bin:/bin INPUT_REGION="$2" bash --noprofile --norc -e ./validate-region.sh >/dev/null 2>&1; chk "region: $1" "$3" $?; }
svc() { out=$(mktemp); env -i PATH=/usr/bin:/bin INPUT_SERVICE="$2" INPUT_ARGO_SERVICE_NAME="$3" GITHUB_OUTPUT="$out" bash --noprofile --norc -e ./argo-svc.sh >/dev/null 2>&1; rc=$?
  if [ -n "$5" ] && [ $rc -eq 0 ] && [ "$(cat $out)" != "name=$5" ]; then echo "FAIL  svc: $1 wrong output $(cat $out)"; fail=1; fi
  rm -f "$out"; chk "service: $1" "$4" $rc; }
region "empty" "" reject;            region "all" "all" reject;          region "all + space" "all " reject
region "space" " " reject;           region "inner space" "us east" reject; region "slash" "a/b" reject
region "dotdot slash" "../x" reject; region "semicolon" "a;b" reject;    region "cmd subst" '$(touch /tmp/PWNED)' reject
region "backtick" '`touch /tmp/PWNED`' reject; region "quote" 'a"b' reject; region "newline" $'us-east-1\nx' reject
region "us-east-1" "us-east-1" accept; region "eu-west-1" "eu-west-1" accept; region "ap-southeast-2" "ap-southeast-2" accept
region "ALL upper (known gap: accepted)" "ALL" accept
svc "explicit override" authz-thor authz-thor-v2 accept authz-thor-v2
svc "explicit canary" authz-thor authz-thor-canary accept authz-thor-canary
svc "fallback to service" authz-thor "" accept authz-thor
svc "dots/underscore" a.b_c "" accept a.b_c
svc "both empty" "" "" reject;       svc "explicit space" svc "bad name" reject; svc "explicit slash" svc a/b reject
svc "explicit semicolon" svc "a;b" reject; svc "cmd subst" svc '$(touch /tmp/PWNED)' reject
svc "backtick" svc '`touch /tmp/PWNED`' reject; svc "bad service fallback" "bad svc" "" reject; svc "newline" svc $'a\nb' reject
[ ! -e /tmp/PWNED ] || { echo "FAIL  injection payload executed"; fail=1; }
[ $fail -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
