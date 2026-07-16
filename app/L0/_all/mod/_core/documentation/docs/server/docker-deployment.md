# Docker Deployment Guide (VPS / Hostinger)

Complete guide to running Space Agent with self-hosted sharing in a Docker container on a VPS.

---

## Architecture Overview

```
Internet → nginx (HTTPS) → Docker container (Space Agent :3000)
                                    │
                                    ├── /data (Docker volume: user files + share archives)
                                    └── /app/server/data (auth keys)
```

- **nginx** terminates TLS and reverse-proxies to the container
- **Docker container** runs `node space serve` on port 3000
- **Docker volume** persists user data, spaces, and share archives across container restarts
- All share URLs point to your domain — files never touch space-agent.ai

---

## Prerequisites

| Requirement | Details |
|---|---|
| VPS | Hostinger VPS or any Linux server with root/sudo access |
| Docker | Docker Engine 24+ and Docker Compose v2 |
| Domain | A domain name (e.g. `space.yourdomain.com`) pointed to your VPS IP |
| HTTPS | Handled by nginx + Let's Encrypt (free) |

---

## Step 1 — Install Docker on your VPS

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sudo sh

# Add your user to the docker group
sudo usermod -aG docker $USER

# Log out and back in for the group change to take effect, then verify:
docker --version
docker compose version
```

---

## Step 2 — Point your domain to the VPS

In your domain registrar or Hostinger DNS panel:

| Type | Name | Value |
|---|---|---|
| A | `space` | `YOUR_VPS_IP` |

Wait for DNS to propagate (check with `dig space.yourdomain.com`).

---

## Step 3 — Clone your fork and configure

```bash
cd /opt
git clone https://github.com/YOUR_USERNAME/space-agent.git
cd space-agent
```

---

## Step 4 — Review docker-compose.yml

The included `docker-compose.yml` is pre-configured with sharing enabled:

```yaml
services:
  space-agent:
    build: .
    container_name: space-agent
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - space-data:/data
      - ./server/data:/app/server/data
    environment:
      - CUSTOMWARE_PATH=/data
      - HOST=0.0.0.0
      - PORT=3000
      - ALLOW_GUEST_USERS=true
      - CLOUD_SHARE_ALLOWED=true
      - LOGIN_ALLOWED=true
      # CLOUD_SHARE_URL defaults to empty (auto-detect from browser origin)
      # Set only if behind a reverse proxy with a different hostname:
      # - CLOUD_SHARE_URL=https://space.yourdomain.com
      # Raise upload limit (default 2MB, max 100MB):
      # - CLOUD_SHARE_MAX_BYTES=10485760

volumes:
  space-data:
```

**Key settings:**

| Variable | Default | Purpose |
|---|---|---|
| `CUSTOMWARE_PATH` | `/data` | Where user files and share archives are stored (Docker volume) |
| `CLOUD_SHARE_URL` | empty | Auto-detects from browser origin. Set explicitly only behind a proxy |
| `CLOUD_SHARE_ALLOWED` | `true` | Accept share uploads on this server |
| `ALLOW_GUEST_USERS` | `true` | Allow share recipients to create guest accounts |
| `CLOUD_SHARE_MAX_BYTES` | `2097152` | Max share upload size (2 MB default, up to 100 MB) |

---

## Step 5 — Build and start the container

```bash
docker compose up -d --build
```

This will:
1. Build the Docker image (installs Node.js 22, unzip, git, npm dependencies)
2. Start the container in detached mode
3. Map port 3000 to the host
4. Mount the persistent data volume

Verify it's running:
```bash
docker compose ps
docker compose logs --tail 20
```

You should see:
```
space server version v0.66+1
space server listening at http://127.0.0.1:3000
```

---

## Step 6 — Set up nginx + HTTPS

```bash
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

Create the nginx config:
```bash
sudo nano /etc/nginx/sites-available/space-agent
```

Paste this (replace `space.yourdomain.com` with your domain):

```nginx
server {
    server_name space.yourdomain.com;

    # Must match CLOUD_SHARE_MAX_BYTES if you raised it
    client_max_body_size 10m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

Enable and test:
```bash
sudo ln -s /etc/nginx/sites-available/space-agent /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

Get the SSL certificate:
```bash
sudo certbot --nginx -d space.yourdomain.com
```

Certbot will automatically configure nginx for HTTPS and set up auto-renewal.

---

## Step 7 — Create your admin user

```bash
docker compose exec space-agent node space user create admin --password YourStrongPassword --groups _admin
```

---

## Step 8 — Verify sharing works

1. Open `https://space.yourdomain.com` in your browser
2. Log in with your admin credentials
3. Open a space and click **Share**
4. The share host should show `space.yourdomain.com` ✅
5. Click **Share to Cloud** — you get a URL like:
   `https://space.yourdomain.com/share/space/AbCd1234`
6. Open that URL in an incognito tab — it should clone the space as a guest ✅

---

## Step 9 — (Optional) Set CLOUD_SHARE_URL explicitly

If the auto-detect picks up the wrong hostname (e.g. the container's internal hostname), set it explicitly:

Edit `docker-compose.yml`:
```yaml
    environment:
      - CLOUD_SHARE_URL=https://space.yourdomain.com
```

Then restart:
```bash
docker compose up -d
```

---

## Docker Management Commands

| Action | Command |
|---|---|
| View logs | `docker compose logs -f` |
| Restart | `docker compose restart` |
| Stop | `docker compose down` |
| Start | `docker compose up -d` |
| Rebuild after code changes | `docker compose up -d --build` |
| Update from Git | `git pull && docker compose up -d --build` |
| Create user | `docker compose exec space-agent node space user create <name> --password <pw> --groups _admin` |
| Set a parameter | `docker compose exec space-agent node space set PARAM=VALUE` |
| Check health | `curl -s http://localhost:3000/api/health` |

---

## Data Persistence

```
Docker volume 'space-data' → /data inside container
├── L1/                 # Group customware
├── L2/                 # User spaces, settings, auth files
└── share/
    └── spaces/         # Shared space archives (.zip + .json metadata)
```

- The volume persists across container restarts and rebuilds
- To back up: `docker run --rm -v space-data:/data -v $(pwd):/backup alpine tar czf /backup/space-backup.tar.gz /data`
- To restore: `docker run --rm -v space-data:/data -v $(pwd):/backup alpine tar xzf /backup/space-backup.tar.gz -C /`

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| Share upload returns 404 | `CLOUD_SHARE_ALLOWED` not set | Already set in docker-compose.yml — verify with `docker compose exec space-agent node space get CLOUD_SHARE_ALLOWED` |
| Share upload returns HTTPS error | Server behind HTTP-only proxy | Run certbot to get HTTPS certificate |
| Share clone returns 500 | `unzip` missing | Already installed in Dockerfile — rebuild: `docker compose up -d --build` |
| Port 3000 already in use | Another service on port 3000 | Change `ports: ["3001:3000"]` and update nginx proxy_pass |
| Can't log in | No user created | `docker compose exec space-agent node space user create admin --password YOUR_PW --groups _admin` |
| Share URL points to wrong host | Auto-detect picks up container hostname | Set `CLOUD_SHARE_URL=https://space.yourdomain.com` in docker-compose.yml |
| nginx returns 413 Request Entity Too Large | Body size exceeds nginx limit | Raise `client_max_body_size` in nginx config to match `CLOUD_SHARE_MAX_BYTES` |
