# LSMW Proof of Concept — gridinstruments Integration

**Date**: 2026-03-15
**Library**: build-state-machines-from-literate-wiki (LSMW)
**Consumer project**: gridinstruments (github:zitongcharliedeng/gridinstruments)
**Entangled version**: 2.4.2 (bundled by LSMW)

---

## What Worked

### Core tangle succeeds

```
nix build .#tangled
```

Produced `/nix/store/am01s6dsshfajkv33n1fp81rkcc5012r-gridinstruments-tangled` containing:
- 53 TypeScript files in `_generated/`
- 1 HTML file (`index.html`)
- All files at 444 permissions (immutable, read-only)

This matches exactly what `scripts/tangle.sh` produces from the git-tracked source.

### Immutability verified

Every file in the nix store output is mode 444. The `.lsmw-manifest` correctly lists all tangled paths. The nix store path is content-addressed — the same source always produces the same hash.

### Consumer integration is minimal

The flake.nix change required was 10 lines:

```nix
inputs.lsmw.url = "github:zitongcharliedeng/build-state-machines-from-literate-wiki";

packages.${system}.tangled = lsmw.lib.tangle {
  src = ./.;
  name = "gridinstruments-tangled";
  entangledConfig = ./entangled.toml;
};

checks.${system} = lsmw.lib.makeChecks {
  src = ./.;
  inherit pkgs;
  entangledConfig = ./entangled.toml;
};
```

---

## What Didn't Work (and Fixes Applied)

### Bug 1: Stale filedb causes partial tangle (LSMW bug, fixed)

**Symptom**: First build produced only 28/55 output files. 27 files were silently skipped.

**Root cause**: `.entangled/filedb.json` is git-tracked in the gridinstruments repo. When nix copies the source into the sandbox, this stale filedb comes along. Entangled sees the missing output files as "undead" (in db but not on drive) and skips regenerating them — even with `--force`.

This is an entangled incremental-build behaviour: it trusts the filedb over the filesystem state. The `--force` flag forces re-tangle of files that exist but may be stale, but does NOT regenerate files that are absent from disk when the db says they were deleted.

**Fix applied in LSMW flake.nix**:
```nix
# Remove stale filedb before tangling.
# If .entangled/filedb.json is git-tracked in the source repo, it will be
# copied into the sandbox with stale entries. Entangled treats files that are
# "in db but not on drive" as undead and skips regenerating them, even with
# --force. Deleting the filedb forces a clean tangle from scratch.
rm -f .entangled/filedb.json

entangled tangle --force 2>&1
```

**Lesson**: LSMW must always clear the filedb before tangling. Any project that commits `.entangled/filedb.json` will hit this silently — no error, just missing output files.

**Recommendation for projects**: Add `.entangled/filedb.json` to `.gitignore`. The filedb is ephemeral state that belongs alongside `.venv/` and `node_modules/`.

### Bug 2: src must be project root, not literate/ subdirectory

**Symptom**: Initial attempt used `src = ./literate` — entangled found no files to tangle.

**Root cause**: entangled.toml has `watch_list = ["literate/**/*.lit.md"]`. If `src = ./literate`, the sandbox working directory contains `*.lit.md` files at its root, not under `literate/`. The watch_list matches nothing.

Furthermore, the tangle output paths (e.g. `_generated/machines/appMachine.ts`, `index.html`) are relative to the project root. If `src = ./literate`, entangled would write to the wrong relative paths.

**Fix**: Use `src = ./.` (whole project root). Nix flakes automatically git-filter the source — gitignored files (`_generated/`, `node_modules/`, `.venv/`) are never copied into the sandbox. The sandbox is clean and fast.

**Lesson**: When using LSMW with a project where `.lit.md` files reference output paths relative to the project root (not relative to themselves), `src` must be the project root.

### Non-issue: _smoke.ts and raw.d.ts missing from nix output

These two files (`_generated/machines/_smoke.ts`, `_generated/raw.d.ts`) exist locally but are gitignored — they are hand-crafted developer utilities, not tangle outputs. The nix store correctly excludes them (nix flakes only include git-tracked files). This is correct behavior.

---

## Restrictions That Should Be BANNED in .lit.md Files

### 1. TypeScript `//` and `/*` comments inside code blocks

**Rule**: `no-ts-comments-in-lit-md`
**Severity**: ERROR

```markdown
<!-- WRONG: comment inside code block -->
``` {.typescript file=_generated/foo.ts}
// This function does X because of Y
const x = computeX();
```

<!-- CORRECT: prose between blocks -->
``` {.typescript file=_generated/foo.ts}
const x = computeX();
```

This function computes X because of Y. See [RFC-42](link) for the rationale.

``` {.typescript file=_generated/foo.ts}
const y = x * FACTOR;
```
```

Comments inside code blocks defeat the purpose of literate programming. The narrative belongs in Markdown prose, not `//` comments that readers skip. Entangled v2 supports multiple code blocks per output file, concatenating them in document order.

### 2. `@ts-ignore` / `@ts-nocheck` / `@ts-expect-error`

**Rule**: `no-ts-suppress`
**Severity**: ERROR

Type suppressions in literate source are doubly bad: they skip type safety AND they skip the prose explanation that would justify the bypass. If you need to suppress a type error, write a prose paragraph explaining why, then use `@ts-expect-error` with a description — but better, fix the type.

### 3. `as any` casts

**Rule**: `no-as-any`
**Severity**: ERROR

`as any` in a .lit.md file signals that the author didn't understand the type well enough to document it. The literate format demands you explain what you're doing and why — if you can't explain the type, you can't write the prose. Fix the type.

### 4. Code blocks without `file=` annotation

**Rule**: `no-code-block-without-file-annotation`
**Severity**: ERROR

```markdown
<!-- WRONG: entangled silently ignores this -->
```typescript
export const x = 1;
```

<!-- CORRECT: entangled processes this -->
``` {.typescript file=_generated/foo.ts}
export const x = 1;
```
```

Plain fenced code blocks without `{.lang file=path}` are invisible to entangled. They produce no output and make the document misleading — the reader sees code that doesn't exist in the generated output.

---

## Patterns That Should Generate WARNINGS

### 1. Code blocks longer than 50 lines without prose break

**Rule**: `long-block-without-prose`
**Severity**: WARNING

Worst offender: `literate/tests/machines/invariant-checks.lit.md` — 4,161-line single code block with one line of prose. This is a `.ts` file with Markdown syntax, not a literate document.

The 50-line threshold is conservative. The goal is to encourage interleaving, not to mandate it at every function. A 60-line state machine with a prose section explaining the state graph is better than a 60-line block with no context.

### 2. Prose-starved files (fewer than 3 prose lines)

**Rule**: `no-prose-starved`
**Severity**: WARNING

17 of 55 files in gridinstruments have fewer than 3 prose lines. These are migration artifacts — the `.ts` files were wrapped in Markdown syntax but no prose was added. The `.lit.md` format adds overhead with no benefit until prose is written.

Pattern: all `tests/machines/*.lit.md` files are prose-starved. Test machines are harder to document than application code, but they can still explain what states are being tested, what the happy path is, and what the failure modes are.

### 3. No prose before first code block

**Rule**: `no-intro-prose`
**Severity**: WARNING

54 of 55 files have no prose before the first code block (the `# Title` header doesn't count). An introductory paragraph before the first code block dramatically improves readability — it tells the reader what the module does before showing how.

Notable exception: `literate/tool-decision.lit.md` — this file was written as a proper literate document from the start and has extensive prose throughout.

---

## Anti-Patterns Caught

| Anti-Pattern | Files Affected | Severity |
|---|---|---|
| Code blocks without intro prose | 54/55 | Warning |
| Prose-starved (< 3 prose lines) | 17/55 | Warning |
| Long blocks > 50 lines without prose break | 19 locations | Warning |
| Unannotated code blocks (no file=) | 3 files | Warning |
| TypeScript comments in code blocks | 0 | (none found) |
| `as any` casts | 0 | (none found) |
| `@ts-ignore` | 0 | (none found) |

The zero counts for ts-ignore, as-any, and ts-comments are encouraging — gridinstruments already has `no-ts-comments` enforced via ast-grep on the generated files, and this discipline carried over to the .lit.md source.

---

## How the entangled.toml Should Be Managed

### Project-provided vs LSMW-default

LSMW provides a default `entangled.toml` covering TypeScript, Nix, CSS, HTML, Rust, Python, Bash, YAML, JSON. Projects should pass their own `entangled.toml` via `entangledConfig = ./entangled.toml` if they:

1. Have a non-standard `watch_list` (e.g. `literate/**/*.lit.md` not `**/*.lit.md`)
2. Need additional language configs
3. Have project-specific annotation settings

The LSMW default `watch_list = ["**/*.lit.md"]` is a reasonable default for projects where `.lit.md` files are at the repo root. For projects like gridinstruments where they're in a subdirectory, the project's `entangled.toml` must be passed.

### The filedb must not be committed

The key lesson: `.entangled/filedb.json` must be gitignored. It is ephemeral, machine-local state. Committing it causes the stale-filedb bug in LSMW (now fixed). Add to `.gitignore`:

```
.entangled/filedb.json
.entangled/filedb.lock
```

The `filedb.lock` is already gitignored in gridinstruments. The `filedb.json` is not — this caused the bug. LSMW now defensively deletes it before tangling, but projects should gitignore it anyway.

---

## Formalized Rules

### Python linter: `linter/check-lit-md.py`

A Markdown-aware linter implementing all the above rules. Runs against any directory of `.lit.md` files:

```bash
python3 linter/check-lit-md.py --warn-only literate/
```

Results against gridinstruments: **0 errors, 12 warnings** (PASSED).

### ast-grep YAML rules: `linter/ast-grep-rules/`

Three rules as documentation + machine-readable policy:

- `no-code-block-without-file-annotation.yml` — every code block needs `file=`
- `no-ts-comments-in-lit-md.yml` — prose not comments
- `no-prose-starved-lit-md.yml` — meaningful prose required

Note: ast-grep does not natively parse Markdown fences as a structured language. The YAML rules serve as policy documentation; the Python linter does the actual enforcement.

---

## Experience as a Consumer

**Setup friction**: Low. Adding LSMW as a flake input and wiring `lib.tangle` took 10 minutes including reading the library source.

**The filedb bug was frustrating**: The first build silently produced only 28/55 files with no error output. Debugging required reading the nix build log to find the "undead file" warnings, then tracing back to the stale filedb in the git repo. The fix is one line in LSMW but the symptom (silent partial output) is maximally confusing.

**The src = ./ requirement is non-obvious**: The LSMW README should document that `src` must be the project root when tangle targets reference paths outside the literate source directory.

**Immutability is the right default**: Having all tangled files at 444 in the nix store is strictly better than the shell script approach. The shell script does the same thing (`chmod 444` after tangling) but it's easy to forget or bypass. In nix, immutability is structural.

**entangled.toml compatibility**: LSMW bundles entangled 2.4.2 (upstream `github:entangled/entangled.py`). The gridinstruments project uses entangled.toml `version = "2.0"` which is compatible. No changes needed to the project's `entangled.toml`.

**What I'd want next**:
1. A `lib.lintLitMd` function that runs `check-lit-md.py` as a nix check — same pattern as `makeChecks`
2. The linter bundled into the LSMW devShell so consumers get it automatically
3. Documentation in README about the filedb issue and the `src = ./.` requirement

---

## Store Path Summary

| Build | Store Path | Files |
|---|---|---|
| First build (unfixed, stale filedb) | `/nix/store/66rd0a0f0wp4cd5w05f6v8kr2m0lc0bx-gridinstruments-tangled` | 28 of 55 _generated files |
| Second build (fixed filedb deletion) | `/nix/store/am01s6dsshfajkv33n1fp81rkcc5012r-gridinstruments-tangled` | 53 of 55 _generated files + index.html |

The 2 missing files in the second build (`_smoke.ts`, `raw.d.ts`) are gitignored hand-crafted files that are not tangle outputs — correctly absent from the nix store.
