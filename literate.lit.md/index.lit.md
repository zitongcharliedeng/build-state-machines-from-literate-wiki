---
description: My opinionated build tool — tangles literate sources into verified code for every project I write
tags: [root, map-of-content]
---

# Literate State Machine Wiki

## Purpose

This is my build tool. Every project I write — in any language — uses it. It enforces one rule: all code is literate. Prose explains every line. Code lives inside `.lit.md` files. Generated source files are build artifacts, not things you edit.

It wraps Entangled the way `cargo` wraps `rustc`. Entangled does the tangling. This tool adds the opinions, the checks, and the nix integration.

## Default extension: `.lit.md`

Plain markdown with fenced-code-block attributes (entangled syntax). Obsidian and mdbase index `.md` natively so the lsmw verbs (`mv`/`rm`/`todo`/`create`/`write`) work on the same vault and wikilinks resolve without configuration. `.lit.mdx` is also accepted — use it per-file for JSX/MDX content; the pipeline accepts both interchangeably.

## What it does

Start from the template — `nix flake init -t github:zitongcharliedeng/build-state-machines-from-literate-wiki` — and the whole consumer flake is one call:

```
inputs.lsmw.url = "github:zitongcharliedeng/build-state-machines-from-literate-wiki";
outputs = { self, lsmw, ... }: lsmw.lib.minimalFlake { src = self; };
```

`nix build` runs the full escalating pipeline and fails early at the first broken stage. `nix run` serves the verified result on localhost (default port 8000; `nix run . -- 8931` to pick another). `minimalFlake` optionally takes `sourceDir` (default: auto-detected — `.english.lit.md`, `literate.lit.md`, `literate.lit.mdx`, or `literate`, first that exists in `src`), `postTangle` (an ordered list of commands — your linters and tests — run on the tangled tree), and `pkgs`.

`minimalFlake` is one call to `lib.init`, the full-control entry point:

```
lsmw.lib.init {
  pkgs, src,
  postTangle ? [ ],            # lint/test hooks, run in order on the tangled tree
  sourceDir ? auto-detected,
  until ? null,                # truncate the pipeline at a named stage
  minProseLines ? 3, maxBlockLength ? 50,
  enforceDirectoryMatch ? false, allowRootGitignore ? false,
  ignoreLiterateGitSubmodules  # mandatory, no default - your stance on nested git repos
}
```

Both return a flake-shaped attrset you can `//`-merge extra outputs into: `packages` (`default` = the verified tangled tree, chmod 444 — the whole project tree, not one file; `tangled` = raw tangle escape hatch for debugging), `apps.default` (the localhost server behind `nix run`), and `devShells.default` (entangled on PATH, auto-tangle on entry, the `lsmw` CLI).

## What it enforces

Five stages, four gates. Each stage is a nix derivation depending on the previous — nix's dependency graph IS the escalating pipeline. See [[lib/checks]] for the implementation.

1. **Pre-tangle checks** — literate structure validation (annotations, prose density, no invisible blocks). Operates on `.lit.md` source, not generated code. Water model: all violations collected, shown at once.
2. **Tangle** — Entangled extracts code from `.lit.md` (hidden, consumers never see it). Only runs if pre-checks pass.
3. **Lint** — consumer's linters run on the tangled tree (`tsc`, `eslint`, `ast-grep` — whatever the language needs). These are your `postTangle` hooks. Water model. Only runs if tangle succeeds.
4. **Test** — consumer's tests run on the tangled tree (playwright, vitest, nix eval — whatever verifies correctness). Also `postTangle` hooks, ordered after the linters. Water model. Only runs if linting passes.
5. **Install** — tangled targets extracted to nix store with chmod 444. Only runs if all previous stages pass.

## Authoring rules the pre-tangle gate enforces

Learn these before your first build fails on them:

- at least 3 prose lines per `.lit.md`, and prose must precede the first code block — the explanation is not optional
- code blocks are capped at 50 lines; split long code into several blocks with the same `file=` target — same-target blocks concatenate in document order across the page, which is also how you assemble a module from explained pieces
- no `//` or `/* */` comment lines inside code blocks — explanation belongs in the prose (the check is language-blind, so this applies to every C-family language including JavaScript)
- no root `.gitignore` — generated files live only in the nix store, so a tree-local ignore list means the discipline already broke

## Two nix gotchas

The library bootstraps itself by tangling at eval time (import-from-derivation). `nix build` and `nix run` just work; introspection commands like `nix flake show` on the library need `--option allow-import-from-derivation true`.

Flakes only see git-tracked files: `git add` every new literate page before building, or nix silently builds the tree without it.

## How it works

The pipeline is an escalating sequence of gates. See [[lib/checks]] and [[lib/pipeline]] for the implementation — the code there IS the pipeline, not this prose.

The modules, each doing one thing:

- [[lib/pipeline]] — tangles `.lit.md` into generated files and installs to nix store
- [[lib/checks]] — validates literate discipline (pre-tangle) and code quality (post-tangle), escalating with early fails between stages, water model within each stage
- [[lib/devshell]] — development environment with auto-tangle on entry
- [[lib/config]] — default `entangled.toml` and toolchain helpers
- [[flake]] — the thin orchestrator that imports the modules and wires `lib.init`

`lib.init` composes them into a single call. Consumers never touch the pieces directly.

## The store output IS the product

The full project tree — literate source, tangled code, and any artifacts produced by postTangle hooks — lives in the nix store after `literate-state-machine-wiki build`. Nothing is filtered out. The literate `.lit.md` files are documentation, readable prose, and can serve as static assets. The tangled code is the executable output. Whatever the consumer's hooks produce belongs in the store too.

Nix garbage collection operates on entire store paths, not individual files. If a consumer doesn't reference the store output, nix GC removes the whole thing. The tool does not decide what's useful — the consumer does.

## Hook system

literate-state-machine-wiki is a hook system, like Claude Code hooks. The library provides pre-tangle hooks (prose density, annotations) and the tangle step (entangled, hidden). The consumer provides `postTangle` hooks — an ordered list of commands to run after tangling. The library is language-agnostic: it does not know about npm, TypeScript, vite, or any ecosystem. The consumer handles their own tooling in their hooks.

## Forms emerge when needed

Files only take their final form (JSON, TypeScript, YAML) at the moment they are consumed. Everything is `.lit.md` until the pipeline transforms it. This is the Taoism of file forms — wu wei, no forcing.

`tangleAndRead` implements this principle: it tangles a specific file from literate source at nix eval time (via IFD), strips entangled markers, and returns clean content. The form emerges at the exact moment of need, is consumed, and dissolves. No committed JSON sitting in the repo waiting to be read.

Consumer example — npm deps without a committed `package.json`:
```
npmDeps = pkgs.importNpmLock.buildNodeModules {
  package = builtins.fromJSON (literate-state-machine-wiki.lib.tangleAndRead {
    inherit pkgs; src = ./literate.lit.md; file = "package.json";
  });
};
```

The only exception: lockfiles (`flake.lock`, `package-lock.json`) are auto-generated artifacts committed for reproducibility, like version-pinned snapshots. They are not literate because there is no prose to write about SHA hashes.

## Language-agnostic

Entangled tangles any language — the code block annotation declares the language and target file. The default `entangled.toml` includes language tables for TypeScript, Nix, CSS, HTML, Rust, Python, Bash, YAML, and JSON. Add more by overriding the config.

The pre-tangle checks are language-agnostic (they inspect `.lit.md` structure, not code syntax). The post-tangle checks are language-specific (your linters, your rules).

## Consumers

- **gridinstruments** — isomorphic grid keyboard. 65 literate files, TypeScript + XState. The reference implementation. See [[gridinstruments-example]].
- **NixOS system flake** — system configuration as literate `.lit.md` that tangles to `.nix` modules. Planned.
- **Every future project** — this is the only way I build software.

## Generated files in the repo

Most output goes to nix store. A few files are committed because nix and GitHub require them at fixed paths:

- `flake.nix` + `lib/*.nix` — nix can't evaluate without them (`as-a-real-non-nix-store-file=`)
- `.github/workflows/check.yml` — GitHub requires fixed path (`as-a-real-non-nix-store-file=`)

These are read-only (444), carry entangled markers pointing to their literate source, and are explicitly documented exceptions.

## Self-reference

This page is `index.lit.md`. It is part of the wiki it describes. The code blocks in the other pages tangle into the tool's source. The tool tangles the wiki that defines it — that is the bootstrap.
