# @lsmw/verify

**Purpose:** Orchestrate the full pipeline: tangle + enforce + test. Returns pass/fail with evidence.

**This purpose never changes.**

## Contract

```typescript
type VerifyResult = {
  pass: boolean
  tangle: TangleResult
  enforce: EnforceResult
  test: { pass: boolean; output: string }
}

function verify(dir: string, testCmd?: string): Promise<VerifyResult>
```

## Pipeline

1. `@lsmw/tangle` — produce source from `.lit.md`
2. TypeScript `tsc --noEmit` — type check
3. `@lsmw/enforce` — static analysis rules
4. Run test command (user-configured, default: `bun test`)

If any step fails, subsequent steps are skipped and the failure is reported with evidence.

## Dependencies

- @lsmw/tangle
- @lsmw/enforce
