#!/usr/bin/env python3
import argparse
import json
import os
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request


def request_json(method: str, url: str, token: str | None = None, payload: dict | None = None) -> tuple[int, dict | list | None]:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, method=method, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as ex:
        body = ex.read().decode("utf-8")
        raise RuntimeError(f"{method} {url} failed with HTTP {ex.code}: {body}") from ex


def request_form(url: str, payload: dict) -> dict:
    data = urllib.parse.urlencode(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        method="POST",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as ex:
        body = ex.read().decode("utf-8")
        raise RuntimeError(f"POST {url} failed with HTTP {ex.code}: {body}") from ex


def admin_token(base_url: str, realm: str, username: str, password: str) -> str:
    token_url = f"{base_url.rstrip('/')}/realms/{realm}/protocol/openid-connect/token"
    payload = {
        "username": username,
        "password": password,
        "grant_type": "password",
        "client_id": "admin-cli",
    }
    body = request_form(token_url, payload)
    token = body.get("access_token")
    if not isinstance(token, str) or not token:
        raise RuntimeError("Keycloak token response did not include access_token")
    return token


def find_client(base_url: str, token: str, realm: str, client_id: str) -> dict | None:
    params = urllib.parse.urlencode({"clientId": client_id})
    status, clients = request_json("GET", f"{base_url}/admin/realms/{realm}/clients?{params}", token)
    if status != 200 or not isinstance(clients, list):
        raise RuntimeError(f"Unexpected client search response: {status}")
    for client in clients:
        if isinstance(client, dict) and client.get("clientId") == client_id:
            return client
    return None


def ensure_client(base_url: str, token: str, realm: str, client_id: str, console_url: str) -> str:
    clients_url = f"{base_url}/admin/realms/{realm}/clients"
    redirect_uri = f"{console_url.rstrip('/')}/oauth_callback"
    payload = {
        "clientId": client_id,
        "enabled": True,
        "protocol": "openid-connect",
        "publicClient": False,
        "standardFlowEnabled": True,
        "directAccessGrantsEnabled": False,
        "serviceAccountsEnabled": False,
        "redirectUris": [redirect_uri],
        "webOrigins": [console_url.rstrip("/")],
        "attributes": {
            "post.logout.redirect.uris": f"{console_url.rstrip('/')}/*",
        },
    }
    existing = find_client(base_url, token, realm, client_id)
    if existing:
        internal_id = existing["id"]
        request_json("PUT", f"{clients_url}/{internal_id}", token, {"id": internal_id, **payload})
    else:
        request_json("POST", clients_url, token, payload)
        existing = find_client(base_url, token, realm, client_id)
        if not existing:
            raise RuntimeError(f"Failed to create or locate Keycloak client {client_id}")
        internal_id = existing["id"]

    secret_value = secrets.token_urlsafe(32)
    request_json("POST", f"{clients_url}/{internal_id}/client-secret", token, {"value": secret_value})
    status, secret_body = request_json("GET", f"{clients_url}/{internal_id}/client-secret", token)
    if status != 200 or not isinstance(secret_body, dict):
        raise RuntimeError("Failed to read generated client secret")
    return str(secret_body.get("value") or secret_value)


def ensure_policy_mapper(base_url: str, token: str, realm: str, client_id: str, policy: str) -> None:
    if not policy:
        return
    client = find_client(base_url, token, realm, client_id)
    if not client:
        raise RuntimeError(f"Cannot add mapper because client {client_id} was not found")
    internal_id = client["id"]
    mappers_url = f"{base_url}/admin/realms/{realm}/clients/{internal_id}/protocol-mappers/models"
    status, mappers = request_json("GET", mappers_url, token)
    if status != 200 or not isinstance(mappers, list):
        raise RuntimeError("Failed to list protocol mappers")

    mapper = {
        "name": "minio-policy",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-hardcoded-claim-mapper",
        "config": {
            "claim.name": "policy",
            "claim.value": policy,
            "jsonType.label": "String",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true",
        },
    }
    existing = next((item for item in mappers if isinstance(item, dict) and item.get("name") == "minio-policy"), None)
    if existing:
        request_json("PUT", f"{mappers_url}/{existing['id']}", token, {"id": existing["id"], **mapper})
    else:
        request_json("POST", mappers_url, token, mapper)


def main() -> int:
    parser = argparse.ArgumentParser(description="Create/update the tenant Keycloak client used by MinIO OIDC.")
    parser.add_argument("--tenant", required=True, help="Tenant realm name, for example material")
    parser.add_argument("--tenant-host", required=True, help="Tenant base host, for example material.dil.collab-cloud.eu")
    parser.add_argument("--keycloak-base-url", default=os.getenv("KEYCLOAK_BASE_URL", "https://dil.collab-cloud.eu/auth"))
    parser.add_argument("--admin-realm", default=os.getenv("KEYCLOAK_ADMIN_REALM", "master"))
    parser.add_argument("--client-id", default=os.getenv("MINIO_CLIENT_ID", "minio"))
    parser.add_argument("--policy", default=os.getenv("MINIO_POLICY", "consoleAdmin"))
    args = parser.parse_args()

    username = os.getenv("KEYCLOAK_ADMIN_USER")
    password = os.getenv("KEYCLOAK_ADMIN_PASSWORD")
    if not username or not password:
        print("KEYCLOAK_ADMIN_USER and KEYCLOAK_ADMIN_PASSWORD must be set", file=sys.stderr)
        return 2

    base_url = args.keycloak_base_url.rstrip("/")
    console_url = f"https://minio.{args.tenant_host}"
    token = admin_token(base_url, args.admin_realm, username, password)
    client_secret = ensure_client(base_url, token, args.tenant, args.client_id, console_url)
    ensure_policy_mapper(base_url, token, args.tenant, args.client_id, args.policy)

    result = {
        "tenant": args.tenant,
        "client_id": args.client_id,
        "client_secret": client_secret,
        "console_url": console_url,
        "issuer": f"{base_url}/realms/{args.tenant}",
        "openid_config_url": f"{base_url}/realms/{args.tenant}/.well-known/openid-configuration",
        "policy": args.policy,
    }
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
