# Tunnel Options for Secure Access

Since OpenClaw requires HTTPS or localhost (secure context) for WebSocket connections, you have two tunnel options:

## Option 1: SSH Tunnel (Local Access)

**Best for:** Development, personal use, temporary access

**Pros:**
- ✅ No external dependencies
- ✅ Works immediately
- ✅ Private (localhost only)
- ✅ No internet exposure

**Cons:**
- ❌ Only accessible from your machine
- ❌ Requires keeping SSH connection open
- ❌ Can't share with team

**Setup:**
```bash
# Start SSH tunnel
make ec2-tunnel NAME=yourname

# Access in browser
http://localhost:18789
```

The tunnel forwards EC2's port 18789 to your local machine. Keep the terminal open while using OpenClaw.

---

## Option 2: Cloudflare Tunnel (Public HTTPS)

**Best for:** Sharing with team, mobile access, production-like testing

**Pros:**
- ✅ Automatic HTTPS
- ✅ Public URL (shareable)
- ✅ Works from anywhere
- ✅ No domain required
- ✅ Free for temporary URLs
- ✅ Runs in background

**Cons:**
- ❌ Publicly accessible (secure with OpenClaw token)
- ❌ Requires cloudflared installation on EC2
- ❌ Temporary URL (changes if tunnel restarts)

**Setup:**
```bash
# Setup Cloudflare Tunnel (one-time)
make ec2-cloudflare-tunnel NAME=yourname

# Output shows HTTPS URL:
# https://random-name-123.trycloudflare.com
```

**Stop tunnel:**
```bash
make ec2-cloudflare-stop NAME=yourname
```

---

## Comparison

| Feature | SSH Tunnel | Cloudflare Tunnel |
|---------|-----------|-------------------|
| **Setup Time** | Instant | ~30 seconds |
| **Access** | Local only | Public HTTPS |
| **URL** | localhost:18789 | random.trycloudflare.com |
| **Security** | Private | Public (token-protected) |
| **Persistence** | While terminal open | Background process |
| **Share with team** | ❌ No | ✅ Yes |
| **Mobile access** | ❌ No | ✅ Yes |
| **Cost** | Free | Free |

---

## Security Notes

### SSH Tunnel
- Only accessible from your machine via localhost
- Most secure option
- Perfect for personal development

### Cloudflare Tunnel
- URL is public but:
  - Protected by OpenClaw's token authentication
  - Random URL (hard to guess)
  - No sensitive data exposed without token
  - Can be stopped when not needed
- Still secure for development/testing
- For production, use custom domain + SSL

---

## Quick Commands

```bash
# SSH Tunnel
make ec2-tunnel NAME=yourname           # Start (keeps terminal open)
# Ctrl+C to stop

# Cloudflare Tunnel
make ec2-cloudflare-tunnel NAME=yourname  # Setup and start
make ec2-cloudflare-stop NAME=yourname    # Stop

# Check which tunnels are running
make ec2-shell NAME=yourname
# Then: ps aux | grep -E 'cloudflared|ssh'
```

---

## Recommendations

**For quick local testing:**
```bash
make ec2-tunnel NAME=yourname
```

**For team collaboration or mobile access:**
```bash
make ec2-cloudflare-tunnel NAME=yourname
# Share the HTTPS URL with your team
```

**For production:**
- Use custom domain with Let's Encrypt
- See README-EC2.md Advanced Topics section
- Or deploy with EKS for full production setup

---

## Troubleshooting

### SSH Tunnel Issues
```bash
# If port already in use
lsof -ti:18789 | xargs kill -9

# Then retry
make ec2-tunnel NAME=yourname
```

### Cloudflare Tunnel Issues
```bash
# Check tunnel logs
make ec2-shell NAME=yourname
cat /tmp/cloudflared.log

# Restart tunnel
make ec2-cloudflare-stop NAME=yourname
make ec2-cloudflare-tunnel NAME=yourname
```

### Connection Refused
```bash
# Verify container is running
make ec2-shell NAME=yourname
docker compose ps

# Check logs
docker compose logs
```
