# @lsmw/tag-query

**Purpose:** Find `.lit.md` files by frontmatter tag.

**This purpose never changes.**

## Contract

```typescript
function query(dir: string, tag: string): Promise<string[]>
function queryAll(dir: string): Promise<Map<string, string[]>>
```

## Dependencies

- @lsmw/frontmatter
