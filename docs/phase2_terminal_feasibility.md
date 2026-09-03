# Phase 2 Feasibility Finding: Embedded Terminal Rendering in QML

**Issue Reference**: #22
**Status**: Completed

---

## Executive Summary

Quickshell on Linux renders QML surfaces using Qt Quick SceneGraph. Embedding an interactive terminal directly inside the Omarchy flyout panel is technically viable, highly performant, and achievable without external native C++ plugins or Wayland subcompositor complexity.

The recommended and viable architecture is a **virtual line-grid model rendered via `ListView` with styled monospace character spans**, backed by a daemon-side PTY session managed over OTP `:ssh`.

---

## Evaluation of Rendering Approaches

### Approach A: Canvas 2D Rendering
- **Mechanism**: Use Qt Quick `Canvas` element with 2D context to draw characters onto an image buffer.
- **Pros**: Exact control over character pixel positioning.
- **Cons**:
  - Software rasterized on the CPU before texture upload in default Qt Quick Linux configurations.
  - High CPU usage and frame stutter during rapid terminal outputs (e.g. `htop`, `dmesg`, `cmatrix`).
  - Lacks built-in font kerning optimizations and accessibility.
- **Verdict**: Not recommended.

### Approach B: Single `TextArea` / `TextEdit` with Rich Text
- **Mechanism**: Accumulate ANSI-parsed escape sequences into an HTML / rich text string.
- **Pros**: Native scrolling, selection, and clipboard integration.
- **Cons**:
  - Full document re-layout occurs when appending high-frequency lines.
  - Causes noticeable latency and memory spikes on large scrollback buffers (> 1000 lines).
- **Verdict**: Suitable for static logs, but inadequate for full-screen PTY interactive applications.

### Approach C: Virtual Line Grid with `ListView` and Monospace Spans (Recommended)
- **Mechanism**:
  - Maintain an in-memory buffer of fixed terminal rows (e.g. 24 rows, 80 columns) in JavaScript or a dedicated QML ListModel.
  - Each visible row is a lightweight `Text` item styled with a monospace font.
  - ANSI colors (foreground, background, bold) are rendered using styled line segments.
  - Keystrokes are captured via `Keys.onPressed` on the terminal focus scope and sent as raw bytes to the daemon Unix socket.
- **Pros**:
  - Qt Quick SceneGraph batches monospace glyphs efficiently into texture atlases.
  - 60 FPS update rate with minimal CPU/GPU overhead.
  - Natural fit for Quickshell's reactive property bindings.
- **Verdict**: **Recommended architecture for Phase 2.**

---

## Daemon Protocol Recommendation

1. **PTY Session Allocation**:
   - The daemon allocates an OTP `:ssh` session channel with `:ssh_connection.ptty_alloc/4` (`term: "xterm-256color"`, `width`, `height`).
   - The daemon starts an interactive shell using `:ssh_connection.shell/2`.
2. **Socket Bridging**:
   - Each terminal session is bridged to an independent Unix domain socket or a framed protocol over `/tmp/omarchy_server.sock`.
   - Raw bytes from the PTY are streamed directly to the QML reader; keyboard inputs from QML are piped back into the PTY.
3. **Window Resizing**:
   - When the user resizes the panel or tab, QML sends `{"command": "resize_pty", "session_id": "...", "cols": C, "rows": R}`.
   - Daemon forwards this via `:ssh_connection.window_change/4`.

---

## Conclusion & Scope for Phase 2

Proceed with Phase 2 implementation under the following milestones:
1. **#23**: Daemon PTY session manager and streaming socket.
2. **#24**: Daemon terminal buffer and line wrapping.
3. **#25**: QML terminal surface component (`TerminalSurface.qml`).
4. **#26**: QML keyboard input forwarding.
5. **#27**: PTY window resize negotiation.
