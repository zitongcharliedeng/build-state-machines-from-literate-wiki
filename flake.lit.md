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

      tangled = pkgs.runCommand "bootstrap-tangle" {
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
          minimalFlake = { src, sourceDir ? "literate.lit.md", pkgs ? nixpkgs.legacyPackages.${system} }:
            init { inherit pkgs src sourceDir; ignoreLiterateGitSubmodules = true; };
        };

        templates.default = { path = ./templates/minimal; description = "${config.name} minimal consumer"; };

        checks.${system} = initModule.mkChecks {
          inherit pkgs tangled pipeline checksLib init;
          todoVerb = lsmwOutputs.packages.${system}.todoVerb;
          writeVerb = lsmwOutputs.packages.${system}.writeVerb;
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

## The verbs — thin wrappers, encapsulated, locked

`lsmw mv`/`rm`/`todo`/`create`/`write` are the consumer API. `mv`/`rm` wrap [notesmd-cli](https://github.com/Yakitrak/notesmd-cli) (Yakitrak's headless Go binary; falls back to its pre-rename `obsidian-cli` filename). `todo` falls through to `mtn` (mdbase-tasknotes, headless) or `tn` (tasknotes-cli, HTTP-API, requires Obsidian); `mtn` is preferred so the headless path is the default.

**`lsmw todo inline <file> '<title>'`** appends `- [[<title>]]` to `<file>` AND writes the target's path-form wikilink (`[[folder/note]]`) into the task file's `referenced_in:` frontmatter (deduped, under flock). Auto-creates `TaskNotes/<slug>.md` if no task with that title exists. Path-form is required: collision-safe at read time, rename-safe (notesmd's rename rewrites both `[[name]]` and `[[folder/name]]`).

Every verb invocation acquires an exclusive `flock` on `${vault}/.lsmw.lock` and blocks until released — concurrent calls on the same vault serialise, never race.

```{.nix file=lib/init.nix as-a-real-non-nix-store-file="init module imported by the bootstrap"}
      inherit (config) name;
      lockFile = ".${name}.lock";
      mkVerb = verb: spec: pkgs.writeShellApplication ({ name = "${name}-${verb}"; } // spec);
      notesmdVerb = verb: upstream: mkVerb verb {
        runtimeInputs = [ pkgs.util-linux ];
        text = ''
          bin=$(command -v notesmd || command -v obsidian-cli) || exit 1
          vault=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "${name}: not in a git repo (vault detection failed)" >&2; exit 1; }
          exec flock "$vault/${lockFile}" "$bin" ${upstream} "$@"
        '';
      };
      mvVerb = notesmdVerb "mv" "move";
      rmVerb = notesmdVerb "rm" "delete";
      todoVerb = mkVerb "todo" {
        runtimeInputs = [ pkgs.util-linux pkgs.yq-go pkgs.ripgrep pkgs.coreutils ];
        text = ''
          vault=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "${name}: not in a git repo (vault detection failed)" >&2; exit 1; }
          slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//'; }
          case "''${1:-}" in
            inline)
              shift; file="$1"; title="$2"
              ( flock 200
                # Read-then-write must be atomic under the lock; concurrent calls without an existing task would otherwise clobber each other's TaskNotes/<slug>.md.
                task_file=$( { rg -lF --no-ignore --hidden "title: \"$title\"" "$vault" --glob '*.md' 2>/dev/null || true; } | head -n1)
                rel=$(realpath --relative-to="$vault" "$file"); stem=''${rel%.lit.md}; stem=''${stem%.lit.mdx}; stem=''${stem%.md}; stem=''${stem%.mdx}
                if [ -z "$task_file" ]; then
                  slug=$(slugify "$title")
                  task_file="$vault/TaskNotes/$slug.md"
                  mkdir -p "$(dirname "$task_file")"
                  [ -e "$task_file" ] || printf -- '---\ntitle: "%s"\nstatus: open\ncreated: %s\n---\n\n# %s\n' "$title" "$(date -I)" "$title" > "$task_file"
                fi
                printf '\n- [[%s]]\n' "$title" >> "$file"
                yq -i --front-matter=process ".referenced_in = ((.referenced_in // []) + [\"[[$stem]]\"] | unique)" "$task_file"
              ) 200>"$vault/${lockFile}" ;;
            *)
              bin=$(command -v mtn || command -v tn)
              exec flock "$vault/${lockFile}" "$bin" "$@" ;;
          esac
        '';
      };
      createVerb = mkVerb "create" {
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          path="$1"
          mkdir -p "$(dirname "$path")"
          [ -e "$path" ] && exit 1
          stem=''${path##*/}; stem=''${stem%.lit.md}; stem=''${stem%.md}
          printf -- '---\ntitle: "%s"\n---\n\n# %s\n\n' "$stem" "$stem" > "$path"
        '';
      };
      writeVerb = mkVerb "write" {
        runtimeInputs = [ pkgs.coreutils pkgs.ripgrep pkgs.findutils ];
        text = ''
          file="$1"
          [ -e "$file" ] || exit 1
          ''${EDITOR:-nano} "$file"
          vault=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "${name}: not in a git repo (vault detection failed)" >&2; exit 1; }
          unresolved=0
          while read -r link; do
            [ -z "$link" ] && continue
            base=''${link##*/}
            if [ -z "$(find "$vault" -type f \( -name "$base.md" -o -name "$base.lit.md" -o -name "$base.lit.mdx" -o -name "$base.mdx" \) -print -quit 2>/dev/null)" ]; then
              echo "warn: [[$link]] unresolved" >&2
              unresolved=$((unresolved+1))
            fi
          done < <(rg -oN '\[\[([^]|#]+)' --replace '$1' "$file" 2>/dev/null || true)
          exit 0
        '';
      };
```

## The CLI dispatcher

`cli` is the user-facing entry point on `PATH`. Dispatches subcommands to the verbs above; unknown verb → usage + exit 1.

```{.nix file=lib/init.nix as-a-real-non-nix-store-file="init module imported by the bootstrap"}
      cli = pkgs.writeShellScriptBin name ''
        set -euo pipefail
        case "''${1:-}" in
          build) nix build --no-link "''${2:-.}" "''${@:3}" ;;
          mv|rename)
            shift
            exec ${mvVerb}/bin/${name}-mv "$@"
            ;;
          rm)
            shift
            exec ${rmVerb}/bin/${name}-rm "$@"
            ;;
          todo)
            shift
            exec ${todoVerb}/bin/${name}-todo "$@"
            ;;
          create)
            shift
            exec ${createVerb}/bin/${name}-create "$@"
            ;;
          write)
            shift
            exec ${writeVerb}/bin/${name}-write "$@"
            ;;
          *) exit 1 ;;
        esac
      '';
    in {
      packages.${system} = {
        default = verified.default;
        literate-verified = verified.default;
        tangled = verified.tangled;
        web-wiki = pipeline.buildWebWiki { inherit pkgs src; litSourceDir = sourceDir; };
        inherit cli mvVerb rmVerb todoVerb createVerb writeVerb;
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
  mkChecks = { pkgs, tangled, pipeline, checksLib, init, todoVerb, writeVerb, src }:
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
        inherit pkgs lib todoVerb writeVerb;
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
