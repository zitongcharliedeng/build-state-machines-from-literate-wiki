# @lsmw/frontmatter

**Purpose:** Read and write YAML frontmatter from `.lit.md` files.

**This purpose never changes.**

## Contract

```typescript
type Frontmatter = { id?: string; title?: string; tags?: string[]; [key: string]: unknown }
type ParsedFile = { data: Frontmatter; content: string }

function read(filePath: string): Promise<ParsedFile>
function write(filePath: string, data: Frontmatter, content: string): Promise<void>
```

## Dependencies

- gray-matter (wraps it)
