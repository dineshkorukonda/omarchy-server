# ssh-client

A lightweight, cross-platform (Windows + Linux) desktop SSH client with agentless remote host monitoring, interactive terminal sessions, credential management, and service control. Built on Elixir/OTP and Erlang's native `:ssh` application.

## Non-Negotiables

- **No forced accounts, cloud sync, or telemetry**: Fully usable offline, always.
- **Secure credential storage**: Credentials never touch config files — resolved via OS keychain (Windows Credential Manager / Linux libsecret) at connect time.
- **Deterministic error messages**: Specific, plain-language diagnostics for all SSH connection and authentication failures.
- **Resource discipline**: Idle hosts do not keep open shell channels or consume CPU; polling frequency backs off automatically.
- **Native Erlang `:ssh`**: No dependency on external `ssh` binaries — functions consistently on Windows and Linux.

## Project Structure & Architecture

See [**`SPEC.md`**](SPEC.md) for the complete architecture specification and the 9-phase roadmap.

## Quick Start (Development)

### Prerequisites
- Elixir 1.17+ and Erlang/OTP 27+

### Install Dependencies & Run Tests
```sh
mix deps.get
mix test
```

## History & Attribution

This project is the cross-platform evolution of `omarchy-server`, originally created as an agentless SSH monitoring daemon and QML bar widget for Linux desktops. See `CHANGELOG.md` for historical release information.

## License

MIT License - see [LICENSE](LICENSE) for details.
