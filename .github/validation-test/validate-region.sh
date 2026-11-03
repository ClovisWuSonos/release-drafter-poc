# Validate region: a single valid region name
if [[ ! "$INPUT_REGION" =~ ^[A-Za-z0-9._-]+$ || "$INPUT_REGION" == "all" ]]; then
  echo "::error::region must be a single region for rollback (got '${INPUT_REGION}'). 'all' is not supported because previous versions can differ per region."
  exit 1
fi
echo "Rollback region: ${INPUT_REGION}"
