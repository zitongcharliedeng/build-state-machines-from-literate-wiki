# @lsmw/wiki-links

**Purpose:** Parse `[[wiki-links]]` from markdown and resolve them to file paths.

**This purpose never changes.**

## Contract

```typescript
type WikiLink = { raw: string; target: string; resolvedPath: string | null }

function parse(markdown: string): WikiLink[]
function resolve(link: WikiLink, dir: string): string | null
```

## Dependencies

- remark-wiki-link (wraps it)
