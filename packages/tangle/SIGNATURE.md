# @lsmw/tangle

**Purpose:** Tangle `.lit.md` files into source code files. Delete old generated files, run tangle, lock generated files as read-only.

**This purpose never changes.**

## Contract

```typescript
type TangleResult = { files: string[]; errors: TangleError[] }
type TangleError = { file: string; line: number; message: string }

function tangle(dir: string): Promise<TangleResult>
```

## Internals (replaceable)

Currently wraps Entangled. Could be replaced by any tool that reads fenced code blocks with `file=` annotations from markdown and writes them to disk.

## Dependencies

- None at runtime (shells out to tangling tool)
