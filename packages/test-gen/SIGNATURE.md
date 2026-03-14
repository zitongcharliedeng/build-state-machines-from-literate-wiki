# @lsmw/test-gen

**Purpose:** Generate test paths from an XState machine config.

**This purpose never changes.**

## Contract

```typescript
import type { MachineConfig } from 'xstate'

type TestPath = { description: string; steps: TestStep[] }
type TestStep = { state: string; event: string }

function generate(machine: MachineConfig): TestPath[]
```

## How it works

Uses `@xstate/graph` shortest path traversal to produce test cases that cover every reachable state and transition. Tests are data, not code — the consumer decides how to execute them.

## Dependencies

- @xstate/graph (wraps it)
- xstate (peer dep)
