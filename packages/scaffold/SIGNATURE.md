# @lsmw/scaffold

**Purpose:** Generate a new literate project with all config files from a template.

**This purpose never changes.**

## Contract

```typescript
type ScaffoldOptions = { name: string; nix?: boolean }
type ScaffoldResult = { dir: string; files: string[] }

function scaffold(options: ScaffoldOptions): Promise<ScaffoldResult>
```

## Generates

- `entangled.toml` — language definitions for TS/CSS/HTML
- `tangle.sh` — delete → tangle → chmod 444
- `.gitignore` — generated files excluded
- `package.json` — name, version, exports
- `literate/index.lit.md` — starter page
- `flake.nix` — devshell with entangled (if `nix: true`)

## Dependencies

- None (writes files)
