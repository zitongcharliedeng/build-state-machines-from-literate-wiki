# @lsmw/compose

**Purpose:** Compose XState parallel machines from tagged `.lit.md` files.

**This purpose never changes.**

## Contract

```typescript
import type { MachineConfig } from 'xstate'

function compose(files: string[]): Promise<MachineConfig>
function composeByTag(dir: string, tag: string): Promise<MachineConfig>
```

## How it works

1. Reads `.lit.md` files
2. Extracts XState machine definitions from code blocks
3. Groups by frontmatter tag
4. Composes into parallel state machine (all active simultaneously)

## Dependencies

- @lsmw/tag-query
- @lsmw/frontmatter
- xstate (peer dep)
