# @lsmw/backlinks

**Purpose:** Build a reverse link graph from wiki-links across `.lit.md` files.

**This purpose never changes.**

## Contract

```typescript
type BacklinkGraph = Map<string, Set<string>>

function build(dir: string): Promise<BacklinkGraph>
function getBacklinks(graph: BacklinkGraph, filePath: string): string[]
```

## Dependencies

- @lsmw/wiki-links
- @lsmw/frontmatter
