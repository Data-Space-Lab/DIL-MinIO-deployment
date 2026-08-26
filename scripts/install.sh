#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/install.sh <tenant> [tenant-host]

Required:
  KEYCLOAK_ADMIN_USER
  KEYCLOAK_ADMIN_PASSWORD

Optional:
  KEYCLOAK_BASE_URL=https://dil.collab-cloud.eu/auth
  TENANT_DOMAIN_SUFFIX=.dil.collab-cloud.eu
  NAMESPACE=minio
  MINIO_CLIENT_ID=minio
  MINIO_POLICY=consoleAdmin
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
tenant="$1"
tenant_host="${2:-${tenant}${TENANT_DOMAIN_SUFFIX:-.dil.collab-cloud.eu}}"
namespace="${NAMESPACE:-minio}"
host_namespace="${TENANT_HOST_NAMESPACE:-loft-${tenant}-v-${tenant}}"
generated_dir="${repo_root}/generated"
client_json="${generated_dir}/${tenant}-keycloak-client.json"
secret_yaml="${generated_dir}/${tenant}-secrets.yaml"

mkdir -p "$generated_dir"

if [[ -z "${KEYCLOAK_ADMIN_USER:-}" || -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]]; then
  usage
  exit 2
fi

echo "Creating/updating Keycloak client for realm ${tenant}"
"${script_dir}/keycloak-minio-client.py" \
  --tenant "$tenant" \
  --tenant-host "$tenant_host" \
  > "$client_json"

client_secret="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["client_secret"])' "$client_json")"

echo "Rendering Kubernetes secrets for namespace ${namespace}"
MINIO_CLIENT_SECRET="$client_secret" "${script_dir}/render-secrets.sh" "$tenant" "$tenant_host" > "$secret_yaml"

echo "Applying MinIO manifests to tenant vCluster ${tenant}"
vcluster connect "$tenant" -n "$host_namespace" --silent -- kubectl apply -k "$repo_root"
vcluster connect "$tenant" -n "$host_namespace" --silent -- kubectl apply -f "$secret_yaml"

echo "Restarting MinIO so OIDC settings are loaded"
vcluster connect "$tenant" -n "$host_namespace" --silent -- kubectl rollout restart deployment/minio -n "$namespace"
vcluster connect "$tenant" -n "$host_namespace" --silent -- kubectl rollout status deployment/minio -n "$namespace" --timeout=180s

echo "MinIO Console: https://minio-console.${tenant_host}"
echo "MinIO S3 API:  https://minio-api.${tenant_host}"
