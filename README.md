# DIL MinIO deployment

Tenant-scoped MinIO deployment for the DIL cluster.

The stack deploys a single-node MinIO server with:

- S3 API on port `9000`
- MinIO Console on port `9001`
- persistent storage
- tenant Keycloak OpenID Connect login for the Console
- a bootstrap job that creates an initial bucket

## Hostnames

Use separate public hostnames for the Console and S3 API:

- Console: `https://minio-console.{tenant_host}`
- S3 API: `https://minio-api.{tenant_host}`

The Console OIDC redirect URI is:

```text
https://minio-console.{tenant_host}/oauth_callback
```

## Secrets

Secrets are intentionally not committed. Generate/apply them with:

```bash
./scripts/install.sh material
```

The script:

1. Creates or updates a `minio` OIDC client in the tenant Keycloak realm.
2. Stores the generated client secret in Kubernetes as `minio-oidc`.
3. Creates `minio-root` if it does not already exist.
4. Applies the manifests to the tenant vCluster.
5. Restarts MinIO so OIDC settings are loaded.

Keycloak admin credentials are read from environment variables:

```bash
export KEYCLOAK_ADMIN_USER=admin
export KEYCLOAK_ADMIN_PASSWORD='...'
```

Optional environment variables:

- `KEYCLOAK_BASE_URL`, default `https://dil.collab-cloud.eu/auth`
- `TENANT_DOMAIN_SUFFIX`, default `.dil.collab-cloud.eu`
- `NAMESPACE`, default `minio`
- `MINIO_CLIENT_ID`, default `minio`
- `MINIO_POLICY`, default `consoleAdmin`
- `MINIO_BUCKET`, default `dil-data`
- `MINIO_STORAGE_SIZE`, default `20Gi`
- `MINIO_IMAGE`, default `quay.io/minio/minio:RELEASE.2025-07-23T15-54-02Z`
- `MINIO_MC_IMAGE`, default `quay.io/minio/mc:RELEASE.2025-07-21T05-28-08Z`

## Manual deploy

Render and apply the static manifests:

```bash
kubectl apply -k .
```

Then create `minio-root` and `minio-oidc` secrets using the keys shown in
`scripts/render-secrets.sh`.

## ManagementAPI catalog

`application-catalog-entry.json` contains the application metadata and route
definitions for ManagementAPI. The routes point to the tenant services:

- `minio-console`, namespace `minio`, port `9001`
- `minio`, namespace `minio`, port `9000`
