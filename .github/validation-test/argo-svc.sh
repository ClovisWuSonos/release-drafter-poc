argo_svc="$INPUT_ARGO_SERVICE_NAME"
if [ -z "$argo_svc" ]; then
  argo_svc="$INPUT_SERVICE"
fi
# Validate Argo service name: only letters, numbers, dot, underscore and hyphen.
if [[ ! "$argo_svc" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "::error::argo service name is invalid."
  exit 1
fi
echo "name=${argo_svc}" >> "$GITHUB_OUTPUT"
echo "Using Argo service name: ${argo_svc}"
