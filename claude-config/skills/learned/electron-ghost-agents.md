# Electron Dev Reload Ghost Agents

**Extracted:** 2026-03-31
**Context:** Electron apps with PTY/process management and Vite HMR dev server

## Problem
When an Electron app manages child processes (PTY sessions, agent processes) in the
main process, and the renderer hot-reloads during development (Vite HMR), the main
process keeps all child processes alive. The new renderer has no knowledge of these
processes. They consume resources (file descriptors, memory, API rate limits, agent
slot limits) but are invisible to the UI.

Symptoms:
- "max_agents_reached" errors when trying to spawn new agents
- Memory/CPU usage climbing over time during development
- Agent processes visible in `ps aux` but not in the app UI
- IPC calls returning error objects that the renderer doesn't expect

## Solution
1. **Short term:** Restart the full Electron app (not just HMR) to clear stale processes.

2. **Long term:** Add a renderer reconnection protocol:
```typescript
// On renderer load, ask main process for current state
const currentAgents = await window.api.agent.list();
// Reconcile: kill orphans, rebuild UI for active agents
for (const agent of currentAgents) {
  if (!isStillNeeded(agent)) {
    await window.api.agent.kill(agent.id);
  } else {
    workspace.reconnectAgent(agent);
  }
}
```

3. **Always guard IPC results** for error objects (see electron-ipc-error-guard pattern).

## When to Use
- Electron app with child process management (node-pty, child_process)
- Debugging "resource exhausted" or "max limit reached" errors during development
- When the app UI shows zero items but system resources show many active processes
- Any Electron + Vite HMR dev workflow with stateful main process
