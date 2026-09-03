# omarchy-server

Native server monitoring and management daemon for Omarchy, OTP-based, SSH-only, no agent.

## Installation

```sh
omarchy plugin add https://github.com/dineshkorukonda/omarchy-server
```

## Features

- Agentless remote host monitoring and management over SSH
- OTP-based daemon with fault-tolerant supervision trees for managed servers
- Periodic health checks, resource metrics gathering, and service status tracking
- Real-time integration and state streaming for Omarchy and Quickshell interfaces
- SSH key-based authentication with zero software dependencies on target nodes

## Requirements

- Omarchy with Quickshell plugin support
- SSH key access to target servers
- Elixir/OTP (if building from source)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contributor rules, commit conventions, and development workflows.
