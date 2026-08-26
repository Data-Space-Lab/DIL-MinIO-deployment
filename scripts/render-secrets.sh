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
console_url="https://minio-console.${tenant_host}"
api_url="https://minio-api.${tenant_host}"

if [[ -z "$client_secret" ]]; then
  echo "client secret is required as the third argument or MINIO_CLIENT_SECRET" >&2
  exit 2
fi

cat <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: minio-root
  namespace: ${namespace}
type: Opaque
stringData:
  MINIO_ROOT_USER: ${root_user}
  MINIO_ROOT_PASSWORD: ${root_password}
---
apiVersion: v1
kind: Secret
metadata:
  name: minio-oidc
  namespace: ${namespace}
type: Opaque
stringData:
  MINIO_BROWSER_REDIRECT_URL: ${console_url}
  MINIO_SERVER_URL: ${api_url}
  MINIO_IDENTITY_OPENID_CLIENT_ID: ${client_id}
  MINIO_IDENTITY_OPENID_CLIENT_SECRET: ${client_secret}
  MINIO_IDENTITY_OPENID_CONFIG_URL: ${keycloak_base%/}/realms/${tenant}/.well-known/openid-configuration
YAML
