# omarchy-server

Native server monitoring and management daemon and Omarchy bar widget plugin for Linux, OTP-based, SSH-only, no remote agent required.

---

## Installation

Install the plugin directly into Omarchy:

```sh
omarchy plugin add https://github.com/dineshkorukonda/omarchy-server
```

---

## Quick Setup & Authentication

`omarchy-server` monitors your remote servers over standard **SSH** using your existing local SSH keypairs (`~/.ssh/id_ed25519`, `~/.ssh/id_rsa`, or SSH agent). **No remote agent or software installation on target servers is required.**

### 1. Prerequisite: SSH Key Access
Ensure you can SSH into your remote server from your terminal without being prompted for a password:

```sh
# Copy your public SSH key to the remote server:
ssh-copy-id user@your-server-ip

# Verify connection works passwordless:
ssh user@your-server-ip "uname -a"
```

### 2. Adding Servers

You can add and manage servers using **either** the graphical UI or the YAML configuration file:

#### Method A: Directly from the Omarchy UI (Recommended)
1. Click the **Servers** pill in the Omarchy bar to open the flyout panel.
2. Click the **"+ Add Server"** button in the top right.
3. Fill in the fields:
   - **Server Host / IP**: e.g., `192.168.1.100` or `web.example.com`
   - **Display Name**: e.g., `Production Web`
   - **SSH User**: e.g., `deploy` or `root`
   - **Port**: SSH port (default: `22`)
   - **ProxyJump / Bastion**: *(Optional)* Jump host if server is behind a firewall
4. Click **"Save & Connect"**. The server is immediately persisted to `~/.config/omarchy/servers.yaml` and starts polling.

#### Method B: Manual Configuration (`~/.config/omarchy/servers.yaml`)
Create or edit `~/.config/omarchy/servers.yaml`:

```yaml
servers:
  - id: prod-web-1
    name: "Production Web 01"
    host: 192.168.1.100
    user: deploy
    port: 22
    # ProxyJump: bastion.example.com
    checks:
      - type: systemctl
        name: nginx
      - type: docker
        name: postgres
      - type: pm2
        name: api-service

  - id: staging-app
    name: "Staging API"
    host: staging.example.com
    user: ubuntu
```

To reload configuration changes without restarting:
```sh
echo '{"command": "reload"}' | nc -U /tmp/omarchy_server.sock
```

---

## Features

- **Agentless Remote Monitoring**: Collects CPU, memory, load average, disk usage, and uptime via lightweight standard POSIX commands over SSH.
- **Service Management**: Inspect and restart/stop systemd units, Docker containers, and PM2 processes with built-in confirmation dialogs.
- **Log Viewer**: Tail recent system journal (`journalctl`) and syslog logs directly from the UI.
- **One-Click Terminal Launch**: Click "Open SSH" to launch your preferred terminal emulator (`foot`, `kitty`, `xterm`).
- **Desktop Notifications**: Automatic desktop alerts (`notify-send`) when a server goes offline, degrades, or recovers.
- **OTP Supervision**: Fault-tolerant Elixir OTP supervision tree—a single host network drop never crashes other monitored hosts.

---

## Settings Schema (`shell.json`)

Configure plugin options in `~/.config/omarchy/shell.json`:

| Setting | Type | Default | Description |
|---|---|---|---|
| `refreshIntervalSec` | integer | `5` | Polling frequency in seconds (1–300) |
| `socketPath` | string | `/tmp/omarchy_server.sock` | Daemon Unix domain socket path |
| `notificationsEnabled` | boolean | `true` | Desktop alerts on status transitions |
| `terminalEmulator` | string | `"auto"` | Terminal for "Open SSH" (`auto`, `foot`, `kitty`, `xterm`) |
| `logLines` | integer | `50` | Default number of log lines to tail |

---

## Running the Daemon Manually

If running outside the packaged Omarchy environment:

```sh
# Fetch Elixir dependencies
mix deps.get

# Run the daemon
mix run --no-halt
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for commit conventions, testing requirements, and development workflows.
