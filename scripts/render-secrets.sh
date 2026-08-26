#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <tenant> [tenant-host] [client-secret]" >&2
}

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage
  exit 2
fi

tenant="$1"
tenant_host="${2:-${tenant}${TENANT_DOMAIN_SUFFIX:-.dil.collab-cloud.eu}}"
client_secret="${3:-${MINIO_CLIENT_SECRET:-}}"
namespace="${NAMESPACE:-minio}"
client_id="${MINIO_CLIENT_ID:-minio}"
keycloak_base="${KEYCLOAK_BASE_URL:-https://dil.collab-cloud.eu/auth}"
root_user="${MINIO_ROOT_USER:-minioadmin}"
root_password="${MINIO_ROOT_PASSWORD:-$(openssl rand -base64 30 | tr -d '\n')}"
console_url="https://minio.${tenant_host}"
api_url="https://minio-api.${tenant_host}"

yaml_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\'}"
}

if [[ -z "$client_secret" ]]; then
  echo "client secret is required as the third argument or MINIO_CLIENT_SECRET" >&2
  exit 2
fi

cat <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: minio-root
  namespace: $(yaml_quote "$namespace")
type: Opaque
stringData:
  MINIO_ROOT_USER: $(yaml_quote "$root_user")
  MINIO_ROOT_PASSWORD: $(yaml_quote "$root_password")
---
apiVersion: v1
kind: Secret
metadata:
  name: minio-oidc
  namespace: $(yaml_quote "$namespace")
type: Opaque
stringData:
  MINIO_BROWSER_REDIRECT_URL: $(yaml_quote "$console_url")
  MINIO_SERVER_URL: $(yaml_quote "$api_url")
  MINIO_IDENTITY_OPENID_CLIENT_ID: $(yaml_quote "$client_id")
  MINIO_IDENTITY_OPENID_CLIENT_SECRET: $(yaml_quote "$client_secret")
  MINIO_IDENTITY_OPENID_CONFIG_URL: $(yaml_quote "${keycloak_base%/}/realms/${tenant}/.well-known/openid-configuration")
YAML
