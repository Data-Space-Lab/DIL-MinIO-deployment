#!/usr/bin/env bash
set -euo pipefail

tenant="${1:-material}"
namespace="${NAMESPACE:-minio}"
host_namespace="${TENANT_HOST_NAMESPACE:-loft-${tenant}-v-${tenant}}"

vcluster connect "$tenant" -n "$host_namespace" --silent -- kubectl get deploy,pod,svc,pvc,job -n "$namespace"
