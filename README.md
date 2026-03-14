# Literate State Machine Wiki

A wiki that defines state machines. Every page is a `.lit.md` file. Pages link to each other with `[[wiki-links]]`. Pages have frontmatter tags. Tags compose into state machines. State machines generate tests. Code tangles out of the prose.

Based on the insight that [a company is just a graph of algorithms](https://danielmiessler.com/blog/companies-graph-of-algorithms). LSMW is the typed, verified version of that vision — where each algorithm is an XState machine, each connection is a wiki-link, and the graph is proven consistent by generated tests.

## Project Structure

Every LSMW project has this shape:

```
my-project/
├── ONLY_EDIT_THIS_DIRECTORY_EVERYTHING_ELSE_IS_GENERATED_FROM.lit.md/
│   ├── machines/          ← XState machine definitions
│   ├── config.lit.md      ← tangles to package.json, tsconfig.json, etc.
│   ├── ci.lit.md          ← tangles to .github/workflows/
│   └── assets/            ← non-code attachments (images, audio, video)
├── src/                   ← tangled output (read-only, chmod 444)
├── package.json           ← tangled output (read-only)
├── tsconfig.json          ← tangled output (read-only)
├── .github/workflows/     ← tangled output (read-only)
└── entangled.toml         ← bootstrap config (the ONE non-generated file)
```

**The rule:** you edit inside `ONLY_EDIT_THIS_DIRECTORY_EVERYTHING_ELSE_IS_GENERATED_FROM.lit.md/`. Everything outside it is tangled output, read-only (chmod 444). `lsmw verify` enforces this.

If a file exists outside the source directory that no `.lit.md` produced, `verify` warns and fails until you move it into the source directory or delete it.

## Commands

```bash
lsmw verify              # tangle + typecheck + enforce + test all machines
lsmw verify machines/    # test only machines in a subdirectory
```

### What `verify` does

1. **Tangle** — extract code from `.lit.md` files to their declared output paths
2. **Lock** — chmod 444 all generated files
3. **Enforce** — ast-grep rules (no `as any`, no hand-editing generated files, etc.)
4. **Typecheck** — `tsc --noEmit`
5. **Discover machines** — find all XState `createMachine()` exports in tangled output
6. **Generate test paths** — adjacency map traversal of every discovered machine
7. **Run tests** — execute generated paths, verify `meta.invariants` hold per state
8. **Drift check** — any file outside source dir must match what tangle would produce

### What `verify` guarantees for every machine

- Every state is reachable (no dead states)
- Every transition is exercised (no dead events)
- Every guard is evaluated both ways (true and false)
- `meta.invariants` hold in their declared states

## Test Runner

LSMW discovers machines and generates test paths. **You provide the runner** that knows how to execute assertions in your environment:

```typescript
import { testAllMachines } from '@lsmw/test'

// Default: pure state transitions (no browser, no DOM)
testAllMachines()

// With custom runner (e.g., Playwright for browser testing)
import { playwrightRunner } from './test-helpers'
testAllMachines({ runner: playwrightRunner })
```

## Packages

Internal decomposition. Most consumers only call `verify`.

| Package | Purpose (never changes) |
|---------|------------------------|
| `@lsmw/tangle` | Tangle `.lit.md` files into source code (read-only) |
| `@lsmw/enforce` | Reject code that violates literate-only rules |
| `@lsmw/frontmatter` | Read/write YAML frontmatter from `.lit.md` |
| `@lsmw/wiki-links` | Parse `[[links]]` and resolve to file paths |
| `@lsmw/backlinks` | Build reverse link graph |
| `@lsmw/tag-query` | Find `.lit.md` files by frontmatter tag |
| `@lsmw/compose` | Compose XState parallel machines from tagged files (future) |
| `@lsmw/test-gen` | Generate test paths from machine config |
| `@lsmw/test` | Discover machines + run generated tests |
| `@lsmw/verify` | Orchestrate: tangle + enforce + test |

## XState in Everything

Every package models its own behavior as an XState machine. Tests are generated from machines, never hand-written. XState is a peer dependency — your project brings it.

## Future: Composition + Trust Scoring (not MVP)

- P-value trust scores on assumptions (0-100 with source label)
- Trust propagation: parent trust = min(child trusts) × dependency factor
- Explicit `assumes` fields with boundary definitions
- Tag-based composition: glob by tag → XState parallel machines
- `compile --tag gridinstruments` produces the full composed machine

## Bootstrap

1. `@lsmw/tangle` — first package, written in plain TS (chicken-egg)
2. Rewrite as `.lit.md` using itself (dogfood)
3. All subsequent packages are `.lit.md` from the start

## Consumers

- [gridinstruments](https://github.com/zitongcharliedeng/gridinstruments) — isomorphic grid keyboard
- [aito-web](https://github.com/zitongcharliedeng/aito-web) — LifeOS web wiki (future)

## Influences

- [Daniel Miessler — Companies Are Graphs of Algorithms](https://danielmiessler.com/blog/companies-graph-of-algorithms)
- [Entangled](https://github.com/entangled/entangled) — bidirectional literate programming
- [XState v5](https://stately.ai/docs/xstate) — typed state machines
- [Knuth — Literate Programming](https://en.wikipedia.org/wiki/Literate_programming)
