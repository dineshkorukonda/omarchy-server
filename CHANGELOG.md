# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Renamed application to `ssh-client` (`:ssh_client`, `SSHClient.*` namespace).
- Initiated cross-platform revamp (Windows + Linux desktop client) replacing QML with Phoenix LiveView / `elixir-desktop`.
- Migrated SSH transport roadmap to Erlang/OTP native `:ssh_connection` exec/shell channels.

## [0.1.0] - Prior History (`omarchy-server`)
- Historical releases originated as `omarchy-server`, an agentless SSH monitoring daemon and QML bar widget for Omarchy/Hyprland on Linux.
- Included Unix domain socket API, multi-target monitoring, init-system inspection (systemd, docker, pm2), and PTY-backed terminal daemon.
