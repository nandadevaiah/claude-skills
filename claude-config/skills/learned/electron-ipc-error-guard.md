# Electron IPC Error Guard Pattern

**Extracted:** 2026-03-31
**Context:** Electron apps where IPC handlers return error objects instead of throwing

## Problem
Electron IPC handlers that return `{ error: 'some_error' }` on failure instead of throwing
cause crashes in the renderer when the result is used as the expected type. The renderer
calls `window.api.something.action()` and assumes the return value has the expected shape,
but the main process returned an error object instead.

Example crash: `TypeError: Cannot read properties of undefined (reading 'type')` when
`agent.spawn()` returned `{ error: 'max_agents_reached' }` instead of `AgentInfo`.

## Solution
Always guard IPC results before accessing properties:

```typescript
// BAD — assumes success
const info: AgentInfo = await window.api.agent.spawn(request);
const statusBar = new AgentStatusBar(info, callbacks); // crashes if info is { error: '...' }

// GOOD — check for error response
const result = await window.api.agent.spawn(request);
if (!result || ('error' in result) || !result.config) {
  console.error('[Component] Spawn returned error:', result);
  return null;
}
const info: AgentInfo = result;
```

## When to Use
- Any Electron IPC `invoke` call that can fail
- Especially: spawn operations, file operations, network-dependent calls
- When the main process handler has `catch` blocks that return error objects
- When TypeScript types don't account for the error return shape
