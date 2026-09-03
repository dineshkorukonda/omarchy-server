# v1.0.0 Manual Release Checklist

This checklist must be executed and verified before tagging any production release (`v1.x.x`).

---

## 1. Automated Verification & Code Health

- [ ] **Dependency check**: Run `mix deps.get` to ensure all lockfile dependencies are clean.
- [ ] **Compilation**: Run `mix compile --warnings-as-errors` with zero warnings.
- [ ] **Code Formatting**: Run `mix format --check-formatted` (must succeed with code 0).
- [ ] **Unit Test Suite**: Run `mix test` (all tests passing, 0 failures).
- [ ] **Integration Test Suite**:
  - Run `docker compose -f docker-compose.test.yml up -d --build`
  - Run `mix test test/integration --include integration` (all 4 integration tests passing)
  - Run `docker compose -f docker-compose.test.yml down`
- [ ] **CI Status**: Verify the GitHub Actions CI workflow is green on the target commit.

---

## 2. Omarchy Shell Bar Widget Verification

- [ ] **Bar Widget Rendering**:
  - Add or verify the `Servers` widget in Omarchy Bar settings (`manifest.json` category: `System`).
  - Verify that the bar widget renders the server status indicator (green dot when all servers ok, amber when degraded, red when offline).
- [ ] **Tooltip Information**:
  - Hover over the bar widget icon to ensure the status summary tooltip displays accurate server counts and aggregate status.

---

## 3. Panel & Detail View Verification

- [ ] **Panel Open / Close**:
  - Click the bar widget. The flyout panel (`Panel.qml`) must open smoothly without QML engine errors.
  - Press `Escape` or click outside to verify the panel closes cleanly.
- [ ] **Server List Display**:
  - Verify all configured servers from `servers.yaml` are listed.
  - Check that CPU %, Memory %, and Disk % gauges update dynamically on the configured refresh interval (`refreshIntervalSec`).
- [ ] **Server Detail Drilldown**:
  - Click on a server in the list.
  - Verify the server detail view displays hostname, IP, detected init system (`systemd`, `openrc`, `sysvinit`), uptime, and listed service checks.

---

## 4. Service Management & Actions

- [ ] **Service Check Status**:
  - Verify running services display green `running` badges, stopped services display `stopped`, and missing check utilities show `skipped`.
- [ ] **Restart Service**:
  - Click "Restart" on a test service.
  - Confirm that the confirmation modal prompt appears with service name and warning.
  - Confirm the action and ensure the command executes, updates the service status badge, and dismisses the dialog.
- [ ] **Stop Service**:
  - Click "Stop" on a test service.
  - Confirm the confirmation dialog.
  - Verify the service transition to stopped status.

---

## 5. Log Viewer (Tail N Lines)

- [ ] **Open Log Viewer**:
  - Click the "Logs" button on a server detail view.
  - Verify the log viewer modal/overlay opens.
- [ ] **Log Content Retrieval**:
  - Verify journalctl / syslog entries are fetched and displayed in the terminal-style view.
  - Test adjusting lines (e.g., 20, 50, 100 lines) and filtering by systemd unit if applicable.
- [ ] **Close Log Viewer**:
  - Close the log viewer and verify return to the server detail view.

---

## 6. SSH Terminal Launcher

- [ ] **Launch SSH Terminal**:
  - Click "Open SSH" on a server card.
  - Verify that the configured terminal emulator (e.g., `foot`, `kitty`, `xterm` according to `terminalEmulator` setting) launches an SSH session to the target host.
  - Verify the Omarchy panel closes upon successful launch.

---

## 7. Desktop Notifications

- [ ] **Notifications Toggle**:
  - Verify `notificationsEnabled` setting in `shell.json` controls alerts.
  - Simulate a server disconnect or degradation; verify desktop notification (`notify-send`) fires with server name and transition details.
  - Simulate server recovery; verify recovery notification fires.

---

## 8. Release Tagging & Packaging

- [ ] **Version Bump**: Update `version` in `mix.exs` and `manifest.json`.
- [ ] **Git Tag**: Create signed annotated tag: `git tag -a v1.0.0 -m "Release v1.0.0"`.
- [ ] **Push Tag**: `git push origin v1.0.0`.
- [ ] **GitHub Release**: Draft release notes highlighting monitoring, service management, log viewer, SSH launcher, and desktop notifications.
