#!/usr/bin/env bash
# The jq code chunk under test. Input (env): INPUT_PREVIOUS_REGION_INFO (JSON), INPUT_COMMIT_SHA.
# Output: the links, one per line, written to $LINKS_FILE.
links=()
compare_url="https://github.com/example-org/example-repo/compare"

if [[ -n "$INPUT_PREVIOUS_REGION_INFO" && "$INPUT_COMMIT_SHA" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
  if ! compare_links=$(jq -r --arg new "$INPUT_COMMIT_SHA" --arg base "$compare_url" '
    # Regions that ran a different, valid commit before this run
    [ to_entries[]
      | select(
          ((.value.sha? // "") | test("^[0-9a-fA-F]{7,40}$") and (test("[[:cntrl:]]") | not))
          and ((.value.sha | ascii_downcase) != ($new | ascii_downcase))
        )
    ] as $regions

    # One link if they all share a previous commit, otherwise one link per region
    | if ($regions | map(.value.sha) | unique | length) == 1
      then "[Compare changes](\($base)/\($regions[0].value.sha)..\($new))"
      else $regions[] | "[Compare (\(.key))](\($base)/\(.value.sha)..\($new))"
      end
  ' <<<"$INPUT_PREVIOUS_REGION_INFO"); then
    echo "::warning::No Compare changes link added: jq command failed"
  fi
  while IFS= read -r link; do
    if [[ -n "$link" ]]; then links+=("$link"); fi
  done <<<"$compare_links"
fi

if ((${#links[@]})); then printf '%s\n' "${links[@]}" > "$LINKS_FILE"; else : > "$LINKS_FILE"; fi
