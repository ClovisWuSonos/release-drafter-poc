first_region=$(echo "$REGION_ORDER" | jq -r '.[0].region')
current_version=$(echo "$REGION_INFO" | jq -r --arg region "$first_region" '.[$region].version // empty')

# sort -V cannot order pre-release versions (e.g. 1.0.2-rc.1), so use the default start.
case "${current_version}${NEW_VERSION}" in
  *-*) current_version="" ;;
esac

oldest=$(printf '%s\n%s\n' "$current_version" "$NEW_VERSION" | sort -V | head -1)

# The changelog start must be older than the deployed version; otherwise leave from-tag empty.
if [ -n "$current_version" ] && [ "$current_version" != "$NEW_VERSION" ] && [ "$oldest" = "$current_version" ]; then
  from_tag="${TAG_PREFIX}${current_version}"

  if curl -fs \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/git/ref/tags/${from_tag}"; then
    echo "value=${from_tag}" >> "$GITHUB_OUTPUT"
  else
    echo "::warning::Release tag ${from_tag} not found; using the default changelog start."
  fi
else
  echo "::notice::from-tag left empty: prod version '${current_version:-none}' is not older than ${NEW_VERSION}."
fi

