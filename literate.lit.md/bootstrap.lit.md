---
title: Bootstrap — Compiler-Style Self-Hosting
description: How literate-state-machine-wiki bootstraps itself using IFD tangle-at-eval, mirroring GCC's configure-and-make pattern
tags: [bootstrap, self-hosting, compiler, nix, ifd]
---

# Bootstrap — Compiler-Style Self-Hosting

**The bootstrap problem:** literate-state-machine-wiki is a nix library that processes `.lit.md` files via entangled. But to evaluate the library at all, nix must first load `flake.nix`. And `flake.nix` ideally lives in the literate source. Chicken, egg.

**GCC's solution:** The C compiler is written in C. To build GCC, you need a C compiler. Does GCC ship a pre-built binary? No. GCC ships source code plus a `configure` script written in portable shell, and a Makefile. The host operating system provides a **seed compiler** (usually an older gcc or cc). You run `./configure && make`, and the seed compiler compiles gcc into Stage 1, Stage 1 compiles gcc into Stage 2, Stage 2 into Stage 3. Stage 2 and Stage 3 are bitwise identical — that proves self-hosting.

**Mapping to literate-state-machine-wiki:**

| GCC | literate-state-machine-wiki |
|-----|------------------------------|
| Source: `.c` files in `gcc/` | Source: `.lit.md` files in `literate.lit.md/` |
| Seed: host C compiler (external) | Seed: `entangled` (external, flake input) |
| Bootstrap config: `configure` + `Makefile` | Bootstrap config: root `flake.nix` (hand-maintained) |
| Built product: `gcc` binary (NOT committed) | Built product: tangled `.nix` files (NOT committed) |

**The one committed bootstrap file is the root `flake.nix`.** It is the equivalent of GCC's `configure` script: tiny, portable, stable, hand-maintained, and its only job is to invoke the seed (entangled) to tangle the real source code, then delegate to what the tangle produced.

## The root flake.nix stub

The root `flake.nix` is **not tangled from anywhere**. It is hand-edited. It does exactly four things:

1. **Declare inputs**: `nixpkgs` + `entangled` (the seed tangler).
2. **IFD tangle literate source**: invokes `entangled tangle --force` inside a derivation whose output is the full tangled tree in the nix store. This is Import From Derivation — nix builds the derivation at eval time and reads the result.
3. **Import from the tangled tree**: `import "${tangled}/lib/init.nix" { ... }` pulls the library's `init` function out of the tangled output.
4. **Delegate**: call `init` with the library's own literate source, exposing `packages`, `devShells`, `checks`.

Total size: ~60 lines. This file changes only when the bootstrap contract itself changes (new flake input, different IFD structure). It never changes when library logic changes — all logic lives in the literate source.

## Why IFD and not committed bootstrap sub-files?

The alternative is to commit `lib/*.nix` as a "Stage 0 bootstrap" that `flake.nix` imports directly. This works, but it violates the principle that only literate source is truth. The committed `lib/*.nix` would drift from `literate.lit.md/lib/*.lit.md` unless every contributor remembers to retangle before committing. The self-hosting check catches drift, but you still end up with two copies of the same code in git.

IFD eliminates that entirely. There is exactly one copy of `checks.nix` — it's defined in `literate.lit.md/lib/checks.lit.md`, and it only exists on disk inside the nix store after IFD tangle. Contributors cannot drift it because it is not a file they can edit.

**The cost:** IFD is slower than direct imports because nix must build the tangle derivation before continuing evaluation. Hydra users who need pure-eval can tangle manually and point nix at the already-tangled tree. The root `flake.nix` declares `nixConfig.allow-import-from-derivation = true` so consumers do not need to pass `--impure` on every command — the library announces its impurity up front.

## What's committed at the root

Only these files exist at the repository root:

- **`flake.nix`** — the ~60-line bootstrap stub described above
- **`flake.lock`** — nix's auto-generated lockfile for the flake inputs
- **`.github/workflows/check.yml`** — CI entry point (GitHub Actions reads this from disk; no alternative)
- **`README.md`** — symlink to `literate.lit.md/index.lit.md`
- **`literate.lit.md/`** — the actual source tree

That's it. No committed `lib/`, no committed `tests/`, no committed `entangled.toml`, no `.gitignore`. Nothing derivable from literate source is checked into git.

## The stub in full

Here is the complete root `flake.nix`. It is hand-maintained. Changes to this file should be rare. All logic additions go to `literate.lit.md/lib/*.lit.md` files, which are tangled at eval time and consumed by this stub.

```nix
{
  description = "literate-state-machine-wiki — root bootstrap stub";

  inputs = {
    nixpkgs.url = "nixpkgs";
    entangled.url = "github:zitongcharliedeng/entangled";
  };

  outputs = { self, nixpkgs, entangled }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      tangled = pkgs.runCommand "bootstrap-tangle" {
        nativeBuildInputs = [ entangled.packages.${system}.default ];
      } ''
        mkdir -p $out
        cp -r ${./literate.lit.md} $out/literate.lit.md
        chmod -R u+w $out
        cd $out
        cat > entangled.toml <<'TOML'
version = "2.0"
literate_root = "literate.lit.md"
watch_list = ["literate.lit.md/**/*.lit.md", "literate.lit.md/**/*.lit.mdx"]
annotation = "standard"
[[languages]]
name = "Nix"
identifiers = ["nix"]
comment = { open = "# ~~ " }
[[languages]]
name = "TypeScript"
identifiers = ["ts", "typescript"]
comment = { open = "// ~~ " }
[[languages]]
name = "Python"
identifiers = ["python", "py"]
comment = { open = "# ~~ " }
[[languages]]
name = "Bash"
identifiers = ["bash", "sh"]
comment = { open = "# ~~ " }
[[languages]]
name = "YAML"
identifiers = ["yaml", "yml"]
comment = { open = "# ~~ " }
TOML
        entangled tangle --force
        rm -rf .entangled
      '';

      config = import "${tangled}/lib/config.nix" { inherit lib; entangledInput = entangled; };
      pipeline = import "${tangled}/lib/pipeline.nix" { inherit lib config; };
      checksLib = import "${tangled}/lib/checks.nix" { inherit lib config pipeline; };
      devshellLib = import "${tangled}/lib/devshell.nix" { inherit lib config; };
      initModule = import "${tangled}/lib/init.nix" {
        inherit lib pkgs config pipeline checksLib devshellLib;
      };
      init = initModule.init;
    in
      (init {
        inherit pkgs;
        src = ./.;
        sourceDir = "literate.lit.md";
        maxBlockLength = 200;
      }) // {
        lib = { inherit init; inherit (config) defaultEntangledToml; inherit (initModule) tangleAndRead; };

        checks.${system} = initModule.mkChecks { inherit pkgs tangled pipeline checksLib init; src = ./.; };

        devShells.${system}.default = devshellLib.mkDevShell { inherit pkgs; };
      };
}
```

This stub is documented here in literate form but **it is not tangled to `flake.nix` at the root**. The root `flake.nix` is hand-maintained. When you edit this file's prose you can copy the nix code block to the root if needed, but the root file is authoritative for the bootstrap layer only.
