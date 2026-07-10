# Self-Hosted Space Sharing

This guide explains how to enable the Space Agent share feature on your own server so that shareable URLs are generated under **your domain** and all space files stay on **your server** — never copied to space-agent.ai.

---

## How sharing works

When a user clicks **Share** on a space:

1. The browser packages the space as a ZIP archive.
2. The ZIP is uploaded to a share host via `/api/cloud_share_create`.
3. The server stores it locally and returns a shareable URL (`https://yourdomain.com/share/space/<token>`).
4. Recipients open the link. The page downloads the ZIP from the **same server** that stored it, and installs it as a guest space.

When `CLOUD_SHARE_URL` is left empty (the default for self-hosted setups), the share URL is automatically derived from the browser's current origin — so everything stays on your server with zero extra configuration.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **HTTPS** | Sharing is HTTPS-only. Your server must be reachable over `https://`. Localhost (`http://localhost`) is exempt for local dev. |
| **Public domain** | Recipients must be able to reach your server from the internet (unless sharing is only within a private network). |
| **CUSTOMWARE_PATH** | A writable directory outside the repo for user data and share archives. |
| **Node.js ≥ 18** | Required by Space Agent itself. |
| **`unzip`** | Must be available on the server's PATH (used for archive validation). |

---

## Minimal setup (5 steps)

### Step 1 — Set your writable data directory

```bash
node space set CUSTOMWARE_PATH=/srv/space/data
```

This is where user files, shared space archives, and L1/L2 customware layers will be stored.

### Step 2 — Enable guest users

Share links work by creating temporary guest accounts for recipients.

```bash
node space set ALLOW_GUEST_USERS=true
```

### Step 3 — Enable the cloud share receiver

```bash
node space set CLOUD_SHARE_ALLOWED=true
```

This allows your server to accept incoming share uploads.

### Step 4 — (Optional) Set a custom share URL

If left empty, Space Agent automatically uses the browser's current origin as the share base URL. Only set this if your server is behind a reverse proxy that changes the external hostname:

```bash
node space set CLOUD_SHARE_URL=https://yourdomain.com
```

> **Do not set this to `share.space-agent.ai`** unless you specifically want uploads to go to the central server.

### Step 5 — (Optional) Set a custom upload size limit

Default is 2 MB. Raise it if your spaces are larger:

```bash
# 10 MB
node space set CLOUD_SHARE_MAX_BYTES=10485760

# 25 MB
node space set CLOUD_SHARE_MAX_BYTES=26214400

# Maximum supported: 100 MB
node space set CLOUD_SHARE_MAX_BYTES=104857600
```

### Start the server

```bash
node space serve
```

Or with launch-time overrides:

```bash
node space serve CUSTOMWARE_PATH=/srv/space/data ALLOW_GUEST_USERS=true CLOUD_SHARE_ALLOWED=true
```

---

## Reverse proxy (nginx)

Behind nginx, ensure you:

- Forward the real origin in `X-Forwarded-For` and `X-Forwarded-Proto` headers
- Allow large request bodies if you raised `CLOUD_SHARE_MAX_BYTES`

```nginx
server {
    listen 443 ssl;
    server_name yourdomain.com;

    # Adjust if CLOUD_SHARE_MAX_BYTES > 2MB
    client_max_body_size 10m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

> **Important:** `client_max_body_size` must be at least as large as `CLOUD_SHARE_MAX_BYTES`. Default nginx limit is 1 MB, which is below the default 2 MB share limit — always set this explicitly.

---

## Reverse proxy (Caddy)

Caddy handles HTTPS automatically:

```caddyfile
yourdomain.com {
    # Caddy has no body size limit by default; optionally add:
    # request_body { max_size 10MB }

    reverse_proxy localhost:3000
}
```

---

## Runtime parameters reference

| Parameter | Default | Frontend exposed | Description |
|---|---|---|---|
| `CLOUD_SHARE_URL` | `""` (auto) | Yes | Base URL for share links. Empty = auto-detect from browser origin. Set to `https://yourdomain.com` for explicit override. |
| `CLOUD_SHARE_ALLOWED` | `false` | No | Must be `true` to accept share uploads on this server. |
| `CLOUD_SHARE_MAX_BYTES` | `2097152` (2 MB) | Yes | Maximum ZIP upload size in bytes. Max allowed: `104857600` (100 MB). |
| `ALLOW_GUEST_USERS` | `false` | Yes | Must be `true` to allow share link recipients to create guest accounts. |
| `CUSTOMWARE_PATH` | `""` | No | Required for share storage. Archives are saved under `CUSTOMWARE_PATH/share/spaces/`. |

---

## Where shared files are stored

```
<CUSTOMWARE_PATH>/
└── share/
    └── spaces/
        ├── <token>.zip    # The space archive (max CLOUD_SHARE_MAX_BYTES)
        └── <token>.json   # Metadata: created/used timestamps, encryption info
```

These files are owned by the server process and are never served as raw downloads with CORS — they are always served through the authenticated `/api/cloud_share_download` endpoint.

---

## Security notes

- **HTTPS is enforced.** The server rejects upload requests that arrive on a non-HTTPS origin (localhost is exempt for development).
- **Guest accounts are ephemeral.** The built-in maintenance job prunes inactive guest accounts and their data automatically.
- **Archives are validated before installation.** ZIP files are inspected for path traversal, symlinks, and missing space manifests before any files are written.
- **Files never touch space-agent.ai.** When `CLOUD_SHARE_URL` is empty or points to your own domain, no data leaves your server.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|
| `Cloud-share uploads are disabled on this server` | `CLOUD_SHARE_ALLOWED` not set | Run `node space set CLOUD_SHARE_ALLOWED=true` |
| `Guest users are disabled on this server` | `ALLOW_GUEST_USERS` not set | Run `node space set ALLOW_GUEST_USERS=true` |
| `Hosted cloud sharing requires CUSTOMWARE_PATH` | No writable data dir | Run `node space set CUSTOMWARE_PATH=/your/path` |
| `Cloud sharing requires HTTPS` | Server is on `http://` | Put server behind nginx/Caddy with a TLS certificate |
| `Shared space uploads must be N MB or smaller` | Space too large | Raise `CLOUD_SHARE_MAX_BYTES` and update reverse proxy body size |
| Share link returns 404 | `ALLOW_GUEST_USERS=false` | Set `ALLOW_GUEST_USERS=true` |
