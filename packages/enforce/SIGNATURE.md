# @lsmw/enforce

**Purpose:** Reject source code that violates literate-only and type-safety rules. Returns a list of violations or passes.

**This purpose never changes.**

## Contract

```typescript
type Violation = { file: string; line: number; rule: string; message: string }
type EnforceResult = { pass: boolean; violations: Violation[] }

function enforce(dir: string): Promise<EnforceResult>
```

## Rules (bundled defaults)

- No `as any`
- No `@ts-ignore` / `@ts-expect-error`
- No hand-editing generated files (files not in tangle filedb)
- No imperative DOM mutation outside renderer
- Source `.ts` files must originate from `.lit.md`

## Dependencies

- ast-grep (shells out)
