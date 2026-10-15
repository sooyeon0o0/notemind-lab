#!/usr/bin/env python3
"""Create local .env files once, without printing or overwriting secrets."""

import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import time


def encode(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def jwt(secret, role):
    now = int(time.time())
    header = encode(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = encode(json.dumps({
        "role": role, "iss": "supabase", "iat": now,
        "exp": now + 10 * 365 * 24 * 60 * 60,
    }).encode())
    unsigned = f"{header}.{payload}"
    signature = hmac.new(secret.encode(), unsigned.encode(), hashlib.sha256).digest()
    return f"{unsigned}.{encode(signature)}"


def create_env(directory, values):
    target = directory / ".env"
    if target.exists():
        print(f"Preserved: {target}")
        return
    lines = []
    for line in (directory / ".env.example").read_text().splitlines():
        key = line.split("=", 1)[0]
        lines.append(f"{key}={values[key]}" if key in values else line)
    # Exclusive creation also protects against another setup process writing first.
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write("\n".join(lines) + "\n")
    print(f"Created: {target}")


def main():
    root = Path(__file__).resolve().parent
    secret = secrets.token_hex(32)
    values = {
        "JWT_SECRET": secret,
        "ANON_KEY": jwt(secret, "anon"),
        "SERVICE_ROLE_KEY": jwt(secret, "service_role"),
        "POSTGRES_PASSWORD": secrets.token_hex(24),
        "DASHBOARD_PASSWORD": "Nm" + secrets.token_hex(18),
        "SECRET_KEY_BASE": secrets.token_hex(48),
        "REALTIME_DB_ENC_KEY": secrets.token_hex(8),
        "VAULT_ENC_KEY": secrets.token_hex(16),
        "PG_META_CRYPTO_KEY": secrets.token_hex(32),
        "LOGFLARE_PUBLIC_ACCESS_TOKEN": secrets.token_hex(32),
        "LOGFLARE_PRIVATE_ACCESS_TOKEN": secrets.token_hex(32),
        "S3_PROTOCOL_ACCESS_KEY_ID": secrets.token_hex(16),
        "S3_PROTOCOL_ACCESS_KEY_SECRET": secrets.token_hex(32),
        "MINIO_ROOT_PASSWORD": secrets.token_hex(24),
    }
    create_env(root / "supabase", values)
    create_env(root / "vllm", {"VLLM_API_KEY": secrets.token_hex(32)})


if __name__ == "__main__":
    main()
