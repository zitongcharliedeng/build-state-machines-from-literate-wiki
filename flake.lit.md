---
title: literate-state-machine-wiki — bootstrap + consumer API
description: The single source of truth for the LSMW flake. Tangles to flake.nix at the project root and lib/init.nix inside the tangle output, so the bootstrap stub and the public init contract never drift from each other.
tags: [lsmw, flake, bootstrap, init, api]
---

# Bootstrap and consumer API

This file is flat at the LSMW project root — the one exception to "everything literate lives under `literate.lit.md/`". The exception exists because Nix requires `flake.nix` at the flake root, and we want the flake.nix to be derived from prose like the rest of the library. Every change to the bootstrap or the `init` contract happens here, then `entangled tangle` rewrites both `flake.nix` (root) and `lib/init.nix` (under the tangle tree). The committed `flake.nix` is always a function of this file.

## Why the bootstrap exists at all

Nix evaluates `flake.nix` before any user code runs. There is no opportunity to invoke LSMW first to generate it — the file has to already be on disk. So we accept one hand-edit (or one tangle run) as the seed: the bootstrap reads the literate sources from disk, IFD-tangles them, then imports `lib/*.nix` from the tangle output. Once that runs, the rest of the library is in scope.

```{.nix file=flake.nix as-a-real-non-nix-store-file="bootstrap stays on disk because Nix reads flake.nix before any IFD"}
{
  description = "literate-state-machine-wiki — root bootstrap (tangled from flake.lit.md)";

  inputs = {
    nixpkgs.url = "nixpkgs";
    entangled.url = "github:zitongcharliedeng/entangled/dev";
  };

  nixConfig = {
    allow-import-from-derivation = true;
  };
```

## IFD-tangle of the literate source

The bootstrap copies `literate.lit.md/` into the store, writes a minimal `entangled.toml`, runs entangled, and removes `.entangled/` so the result is reproducible. The output is a tangled tree we can `import` `lib/*.nix` from.

```{.nix file=flake.nix as-a-real-non-nix-store-file="bootstrap"}
  outputs = { self, nixpkgs, entangled }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      tangled = pkgs.runCommand "lsmw-bootstrap-tangle" {
        nativeBuildInputs = [ entangled.packages.${system}.default ];
      } ''
        mkdir -p $out
        cp -r ${./literate.lit.md} $out/literate.lit.md
        cp ${./flake.lit.md} $out/flake.lit.md
        chmod -R u+w $out
        cd $out
        cat > entangled.toml <<'TOML'
version = "2.0"
watch_list = ["flake.lit.md", "literate.lit.md/**/*.lit.md", "literate.lit.md/**/*.lit.mdx"]
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
```

## Importing the library modules

After the IFD-tangle, every `.nix` under `lib/` is in the store. The bootstrap imports them in dependency order — `config` first (no deps), then `pipeline` (uses config), then `checksLib`/`devshellLib`, then `initModule` which composes them.

```{.nix file=flake.nix as-a-real-non-nix-store-file="bootstrap"}
      config = import "${tangled}/lib/config.nix" { inherit lib; entangledInput = entangled; };
      pipeline = import "${tangled}/lib/pipeline.nix" { inherit lib config; };
      checksLib = import "${tangled}/lib/checks.nix" { inherit lib config pipeline; };
      devshellLib = import "${tangled}/lib/devshell.nix" { inherit lib config; };
      initModule = import "${tangled}/lib/init.nix" {
        inherit lib pkgs config pipeline checksLib devshellLib;
      };
      inherit (initModule) init tangleAndRead;
      lsmwOutputs = init {
        inherit pkgs;
        src = ./.;
        sourceDir = "literate.lit.md";
        ignoreLiterateGitSubmodules = true;
      };
    in
      lsmwOutputs // {
        lib = {
          inherit init tangleAndRead;
          inherit (config) defaultEntangledToml;
        };

        checks.${system} = initModule.mkChecks {
          inherit pkgs tangled pipeline checksLib init;
          todoVerb = lsmwOutputs.packages.${system}.todoVerb;
          src = ./.;
        };

        devShells.${system}.default = devshellLib.mkDevShell {
          inherit pkgs;
        };
      };
}
```

## The init contract

`init` is the one function consumers call on LSMW. It takes a literate source, a list of `postTangle` hooks, and the consumer's stance on git submodules, and returns a flake-shaped attrset (`packages`, `devShells`, optional `checks`). Every other helper in this module is a private composition stage that `init` orchestrates.

The `ignoreLiterateGitSubmodules` parameter is mandatory — no default. The flag declares what happens when LSMW finds nested git repositories (registered submodules or any directory containing `.git`) inside `src`. `true` means nested repos are foreign LSMW projects whose `.lit.md` files belong to those projects; LSMW will not tangle them here. `false` means the consumer accepts responsibility for resolving the tangling collisions and ownership questions that arise when one LSMW project literates over another. Making it required prevents the silent default that conflates two genuinely different intents.

```{.nix file=lib/init.nix as-a-real-non-nix-store-file="init module imported by the bootstrap"}
{ lib, pkgs, config, pipeline, checksLib, devshellLib }:
rec {
  init = {
    pkgs,
    src,
    system ? "x86_64-linux",
    postTangle ? [ ],
    until ? null,
    sourceDir ? "literate.lit.md",
    enforceDirectoryMatch ? false,
    ignoreLiterateGitSubmodules
  }:
    let
      verified = checksLib.makeVerify {
        inherit pkgs src sourceDir enforceDirectoryMatch;
        inherit postTangle until;
      };
```

## The mv, rm, and todo verbs — thin wrappers, encapsulated, locked

`lsmw mv`, `lsmw rm`, and `lsmw todo` are the consumer API. Two upstream tools sit behind them:

1. **mv / rm** — backed by [notesmd-cli](https://github.com/Yakitrak/notesmd-cli) (Yakitrak's headless Go binary; renamed from "obsidian-cli" because Obsidian Inc shipped an OFFICIAL desktop-required `obsidian-cli`). Either upstream name resolves: the wrapper prefers `notesmd` (post-rename), falls back to `obsidian-cli` (pre-rename installs).
2. **todo** — backed by `mtn` (mdbase-tasknotes, headless — operates on markdown via mdbase, NLP via bundled tasknotes-nlp-core, **no Obsidian required**); falls back to `tn` (tasknotes-cli, HTTP-API — requires Obsidian running with the plugin's API enabled). The wrapper prefers `mtn` so the headless path is the default; `tn` is only used when Obsidian is already open and you want live sync.

**Inline tasknotes are bidirectional primitives.** A bullet `- [[Do this daily]]` in any vault file points to the standalone TaskNote `Do this daily.md` — but absent extra metadata, an agent reading the task file cannot tell where it was inlined without scanning the whole vault (O(N) per task). That's a real gap in upstream TaskNotes. `lsmw todo inline <file> '<title>'` closes it by maintaining the link from BOTH sides under one flock: it appends `- [[<title>]]` to `<file>` AND appends `<file>` (in wikilink form `[[<basename>]]`) to the task file's `referenced_in:` frontmatter list (deduplicated). An agent reading the task file thereafter sees its inline-reference sites in O(1) without grepping. Origin tracking is a primitive of the lsmw API, not a search.

The wikilink form is critical: notesmd-cli's `move` does global string replacement of both basename-form `[[name]]` AND path-form `[[folder/name]]` across all file content (frontmatter included — see `pkg/obsidian/utils.go` `GenerateLinkReplacements`), and Obsidian's "Update internal links" treats wikilinks inside YAML text/list properties as live links. The wrapper stores the **path-form wikilink** (`[[folder/note]]`, vault-relative path without extension) rather than basename-form (`[[note]]`) for two reasons: basename-form is ambiguous when two vault files share a basename (Obsidian resolves to "closest" non-deterministically), and path-form is what disambiguates. Both forms get rewritten on rename, but only path-form is collision-safe at read time. Plain path strings like `"noteA.md"` would NOT survive rename: notesmd's rename only recognises wikilink and markdown-link patterns, never raw path strings in YAML.

Consumers don't see which binary handled the call. Every verb invocation acquires an exclusive `flock` on `${vault}/.lsmw.lock` and **blocks** until released — concurrent `lsmw mv`/`lsmw rm`/`lsmw todo` calls on the same vault serialise, never race.

```{.nix file=lib/init.nix as-a-real-non-nix-store-file="init module imported by the bootstrap"}
      lsmwVerb = name: upstream: pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = [ pkgs.util-linux ];
        text = ''
          bin=$(command -v notesmd || command -v obsidian-cli) || {
            echo "${name} requires notesmd-cli on PATH (go install github.com/Yakitrak/notesmd-cli@latest)" >&2
            exit 1
          }
          vault=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
          exec flock "$vault/.lsmw.lock" "$bin" ${upstream} "$@"
        '';
      };
      mvVerb = lsmwVerb "lsmw-mv" "move";
      rmVerb = lsmwVerb "lsmw-rm" "delete";
      todoVerb = pkgs.writeShellApplication {
        name = "lsmw-todo";
        runtimeInputs = [ pkgs.util-linux pkgs.yq-go pkgs.ripgrep pkgs.coreutils ];
        text = ''
          vault=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
          case "''${1:-}" in
            inline)
              shift
              file="$1"; title="$2"
              task_file=$( { rg -lF --no-ignore --hidden "title: \"$title\"" "$vault" --glob '*.md' 2>/dev/null || true; } | head -n1)
              rel=$(realpath --relative-to="$vault" "$file")
              stem=''${rel%.*}
              (
                flock 200
                printf '\n- [[%s]]\n' "$title" >> "$file"
                yq -i --front-matter=process \
                  ".referenced_in = ((.referenced_in // []) + [\"[[$stem]]\"] | unique)" \
                  "$task_file"
              ) 200>"$vault/.lsmw.lock"
              ;;
            *)
              bin=$(command -v mtn || command -v tn)
              exec flock "$vault/.lsmw.lock" "$bin" "$@"
              ;;
          esac
        '';
      };
```

## The CLI dispatcher

`cli` is the user-facing entry point on `PATH`. It dispatches subcommands to the helpers above. `build` invokes `nix build` against the consumer's flake; `mv` (alias `rename`) forwards two arguments to `lsmw-mv`; `rm` forwards one argument to `lsmw-rm`. Everything else prints usage and exits non-zero.

```{.nix file=lib/init.nix as-a-real-non-nix-store-file="init module imported by the bootstrap"}
      cli = pkgs.writeShellScriptBin "literate-state-machine-wiki" ''
        set -euo pipefail
        case "''${1:-}" in
          build)
            echo "[literate-state-machine-wiki] Building literate project..."
            nix build --no-link "''${2:-.}" "''${@:3}"
            echo "[literate-state-machine-wiki] Build complete."
            ;;
          mv|rename)
            shift
            exec ${mvVerb}/bin/lsmw-mv "$@"
            ;;
          rm)
            shift
            exec ${rmVerb}/bin/lsmw-rm "$@"
            ;;
          todo)
            shift
            exec ${todoVerb}/bin/lsmw-todo "$@"
            ;;
          *)
            echo "literate-state-machine-wiki — opinionated literate build tool"
            echo ""
            echo "Usage:"
            echo "  literate-state-machine-wiki build [flake-ref]"
            echo "  literate-state-machine-wiki mv <src> <dst>"
            echo "  literate-state-machine-wiki rename <src> <dst>"
            echo "  literate-state-machine-wiki rm <path>"
            echo "  literate-state-machine-wiki todo <args...>     (forwards to mtn; falls back to tn)"
            echo ""
            echo "todo examples:"
            echo "  literate-state-machine-wiki todo create '<text>'         (forwarded to mtn — creates standalone task file)"
            echo "  literate-state-machine-wiki todo list --json             (forwarded to mtn)"
            echo "  literate-state-machine-wiki todo inline <file> '<title>' (appends '- [[<title>]]' to <file>; task file must exist)"
            exit 1
            ;;
        esac
      '';
    in {
      packages.${system} = {
        default = verified.default;
        literate-verified = verified.default;
        tangled = verified.tangled;
        web-wiki = pipeline.buildWebWiki { inherit pkgs src; litSourceDir = sourceDir; };
        inherit cli mvVerb rmVerb todoVerb;
      };
      devShells.${system}.default = devshellLib.mkDevShell {
        inherit pkgs;
        extraPackages = [ cli ];
      };
    };
```

## tangleAndRead: IFD helper for consumers

Some consumers need a tangled file at evaluation time — a `package.json` derived from `package.lit.md` to feed `importNpmLock` or `bun2nix`, for example. `tangleAndRead` runs entangled inside a fixed-output-style derivation, then reads one specific file from the result. Gridinstruments uses this to drive its npm lockfile pipeline without committing JSON.

```{.nix file=lib/init.nix as-a-real-non-nix-store-file="init module imported by the bootstrap"}
  tangleAndRead = { pkgs, src, file }: builtins.readFile "${
    pkgs.runCommand "tangle-for-eval" {
      nativeBuildInputs = [ (config.entangledFor pkgs) (config.pythonFor pkgs) ];
    } ''
      cp -r ${src}/. build/
      chmod -R u+w build
      cd build
      cat > entangled.toml <<'TOML'
${config.defaultEntangledToml}
TOML
      entangled tangle --force 2>/dev/null
      ${pipeline.stripEntangledMarkers}
      mkdir -p $out
      cp ${file} $out/ 2>/dev/null || (echo "ERROR: ${file} not found after tangle" && exit 1)
    ''
  }/${file}";
```

## mkChecks: library-internal self-testing

Consumers use `makeVerify` (which returns packages); the library itself needs to expose `checks.*` for `nix flake check`. `mkChecks` wires the internal test suite (`tangle-idempotent`, `tangle-immutable`, `unit-tests`, integration tests, water-model tests) into a single attrset under `checks.${system}`. The bootstrap calls it once.

`lsmw mv`/`rm` correctness is owned upstream by [notesmd-cli](https://github.com/Yakitrak/notesmd-cli); we don't ship a fixture check that re-tests it — would duplicate upstream work and pin notesmd-cli's behaviour to a snapshot we'd have to maintain. `lsmw todo inline`'s bidirectional-link primitive is lsmw-owned (not in any upstream), so it DOES need fixture tests — see [[tests/todo-verb]].

```{.nix file=lib/init.nix as-a-real-non-nix-store-file="init module imported by the bootstrap"}
  mkChecks = { pkgs, tangled, pipeline, checksLib, init, todoVerb, src }:
    let
      prefixed = prefix: lib.mapAttrs' (name: value:
        lib.nameValuePair "${prefix}-${name}" value);
      integrationTests = import "${tangled}/tests/integration.nix" {
        inherit pkgs lib;
        lsmwInit = init;
      };
      waterModelTests = import "${tangled}/tests/water-model.nix" {
        inherit pkgs lib checksLib;
      };
      todoVerbTests = import "${tangled}/tests/todo-verb.nix" {
        inherit pkgs lib todoVerb;
      };
    in {
      tangle-idempotent = checksLib.checkIdempotent { inherit src pkgs; };
      tangle-immutable = checksLib.checkImmutable {
        tangled = pipeline.tangle { inherit pkgs src; };
        inherit pkgs;
      };
      unit-tests = import "${tangled}/tests/unit-check.nix" { inherit pkgs lib checksLib; };
    }
    // prefixed "integration" integrationTests
    // prefixed "water-model" waterModelTests
    // prefixed "todo" todoVerbTests;
}
```
