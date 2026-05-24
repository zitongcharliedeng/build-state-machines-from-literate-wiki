---
description: All validation logic for literate-state-machine-wiki — pre-tangle checks, post-tangle checks, structural integrity checks, and the makeChecks public API
tags: [nix, checks, validation, module]
---

# Nix Checks Module

This module owns all validation logic for literate-state-machine-wiki projects, taking `{ lib, config, pipeline }` and exporting every function that answers "is this literate source well-formed?".

## Module signature

The module uses `rec` so helpers can reference each other by name without argument threading.

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
# ~~ Generated from literate.lit.md/lib/checks.lit.md
{ lib, config, pipeline }:
rec {
```

## Pre-tangle checks

Two checks run before Entangled writes output. `literate-structure` walks every `.lit.md`/`.lit.mdx` and enforces eight invariants: (1) code blocks contain no `//`/`/*` comments (explanations belong in prose); (2) blocks ≤ `maxBlockLength` lines (default 50); (3) ≥ `minProseLines` prose lines per file (default 3); (4) prose precedes the first code block; (5) `as-a-real-non-nix-store-file=` annotations warn (these are bootstrap escapes); (6) `file=` paths are relative, not absolute; (7) optional `enforceDirectoryMatch` rejects `file=` paths that don't match the source dir; (8) no `.md`/`.mdx` files outside the literate convention. `input-title-tooltips` rejects `<input title=>` in favor of accessible info-button dialogs.

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
  mkClaimChecks = {
    sourceDir ? ".english.lit.md",
    reportOnly ? false
  }:
    [{
      name = "claim-atoms";
      command = ''
        python3 - <<'CLAIMCHECK'
import os, re, sys

source_dir = ${builtins.toJSON sourceDir}
report_only = ${if reportOnly then "True" else "False"}
allowed_claim_types = {"Raw", "Machine", "MachineInvariant", "MachineTransition"}
errors = 0

def frontmatter(text):
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    return text[4:end]

def parse_lsmw(fm):
    data = {}
    in_lsmw = False
    for raw in fm.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if re.match(r"^lsmw:\s*$", line):
            in_lsmw = True
            continue
        if in_lsmw:
            if not line.startswith(" "):
                in_lsmw = False
            else:
                m = re.match(r"^\s+([A-Za-z][A-Za-z0-9_-]*):\s*(.*?)\s*$", line)
                if m:
                    value = m.group(2).strip().strip('"').strip("'")
                    data[m.group(1)] = value
    return data

def markdown_file(name):
    return name.endswith(".md") or name.endswith(".mdx")

type_prefix_re = re.compile(r"^(Claim|Invariant|Global Invariant|Entry Transition|Transition|TBC Rule|Rule|TaskNotes|Existence)\s+-\s+")
machine_prefix_re = re.compile(r"^(Machine|Proxy Machine)\s+-\s+")

def has_top_level_yaml_key(fm, key):
    return any(re.match(r"^" + re.escape(key) + r":\s*", line) for line in fm.splitlines())

def parse_lsmw_list(fm, key):
    values = []
    in_lsmw = False
    in_list = False
    key_indent = None
    for raw in fm.splitlines():
        line = raw.rstrip()
        if re.match(r"^lsmw:\s*$", line):
            in_lsmw = True
            in_list = False
            key_indent = None
            continue
        if in_lsmw and line and not line.startswith(" "):
            in_lsmw = False
            in_list = False
            key_indent = None
        if not in_lsmw:
            continue
        m = re.match(r"^(\s+)" + re.escape(key) + r":\s*(.*?)\s*$", line)
        if m:
            key_indent = len(m.group(1))
            rest = m.group(2).strip()
            in_list = True
            if rest.startswith("[") and rest.endswith("]"):
                body = rest[1:-1].strip()
                if body:
                    values.extend([item.strip().strip('"').strip("'") for item in body.split(",") if item.strip()])
                in_list = False
            elif rest:
                values.append(rest.strip('"').strip("'"))
            continue
        if in_list:
            item = re.match(r"^\s+-\s*(.*?)\s*$", line)
            if item:
                values.append(item.group(1).strip().strip('"').strip("'"))
                continue
            if line.strip() and (len(line) - len(line.lstrip(" "))) <= key_indent:
                in_list = False
    return values

claim_files = {}
relations = []
for root, dirs, files in os.walk(source_dir):
    dirs[:] = [d for d in dirs if d != ".git"]
    for name in files:
        if not markdown_file(name):
            continue
        path = os.path.join(root, name)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        fm = frontmatter(text)
        rel = os.path.relpath(path, source_dir)
        for part in rel.split(os.sep)[:-1]:
            if machine_prefix_re.match(part):
                print(f"  error claim/machine-prefix-directory: {rel}")
                print("    remove machine prefix from directory; use machines/<slug> and explicit claim files")
                errors += 1
        if fm is None:
            print(f"  error claim/missing-frontmatter: {rel}")
            print("    markdown claim atoms need YAML frontmatter with lsmw.claimType")
            errors += 1
            continue
        if has_top_level_yaml_key(fm, "title"):
            print(f"  error claim/duplicate-title: {rel}")
            print("    remove YAML title; filename/prose already names the atom")
            errors += 1
        if type_prefix_re.match(name):
            print(f"  error claim/type-prefix-filename: {rel}")
            print("    remove type prefix from filename; use lsmw.claimType for semantic type")
            errors += 1
        lsmw = parse_lsmw(fm)
        if "kind" in lsmw:
            print(f"  error claim/duplicate-kind: {rel}")
            print("    remove lsmw.kind; every markdown atom is already a claim, use lsmw.claimType only")
            errors += 1
        claim_type = lsmw.get("claimType")
        if not claim_type:
            print(f"  error claim/missing-claim-type: {rel}")
            print("    missing lsmw.claimType")
            errors += 1
        elif claim_type not in allowed_claim_types:
            print(f"  error claim/unknown-claim-type: {rel}")
            print(f"    unknown lsmw.claimType '{claim_type}'")
            errors += 1
        else:
            claim_files[rel] = claim_type
        for field in ("prereqClaims", "assumingClaims"):
            for target in parse_lsmw_list(fm, field):
                relations.append((rel, field, target))

for rel, field, target in relations:
    candidates = []
    clean_target = os.path.normpath(target.lstrip("/"))
    candidates.append(clean_target)
    candidates.append(os.path.normpath(os.path.join(os.path.dirname(rel), target)))
    if not any(candidate in claim_files for candidate in candidates):
        print(f"  error claim/missing-{field}-target: {rel}")
        print(f"    missing {field} target '{target}'")
        errors += 1

if errors:
    print(f"[${config.name}] {errors} claim atom violation(s)")
    if report_only:
        print(f"[${config.name}] reportOnly=true; claim atom violations reported without failing")
    else:
        sys.exit(1)
CLAIMCHECK
      '';
    }];

  mkDefaultPreTangleChecks = {
    sourceDir ? ".english.lit.md",
    tooltipCheckFile ? "literate/index.lit.md",
    enforceDirectoryMatch ? false,
    minProseLines ? 3,
    maxBlockLength ? 50
  }:
    lib.flatten [
      [{
        name = "literate-structure";
        command = ''
          python3 - <<'LITCHECK'
import os, re, sys

source_dir = ${builtins.toJSON sourceDir}
min_prose = ${toString minProseLines}
max_block = ${toString maxBlockLength}
forbid_comments = True
enforce_dirs = ${if enforceDirectoryMatch then "True" else "False"}
errors = 0
violations = 0
fence = chr(96) * 3  # three backticks

for root, _, files in os.walk(source_dir):
    for name in files:
        if not (name.endswith(".lit.md") or name.endswith(".lit.mdx")):
            continue
        path = os.path.join(root, name)
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        in_block = False
        block_start = 0
        block_lines = 0
        has_annotation = False
        prose_lines = 0
        first_block = False
        has_intro = False

        for i, line in enumerate(lines):
            trimmed = line.strip()
            num = i + 1

            if trimmed.startswith(fence) and not in_block:
                in_block = True
                block_start = num
                block_lines = 0
                has_annotation = "file=" in trimmed

                if not first_block and prose_lines > 0:
                    has_intro = True
                first_block = True

                # Warn on bootstrap files (as-a-real-non-nix-store-file)
                if "as-a-real-non-nix-store-file=" in trimmed:
                    reason_match = re.search(r'as-a-real-non-nix-store-file="([^"]*)"', trimmed)
                    reason = reason_match.group(1) if reason_match else "no reason given"
                    print(f"  warn core/bootstrap-file: {path}:{num}")
                    print(f"    This file exists outside the nix store: {reason}")
                    violations += 1

                # Warn on absolute file= paths (antipattern — prefer relative)
                if has_annotation:
                    file_match = re.search(r'file=([^\s}"]+)', trimmed)
                    if file_match:
                        target = file_match.group(1)
                        if target.startswith("/"):
                            print(f"  warn core/absolute-path: {path}:{num}")
                            print(f"    Absolute file= path '{target}' — prefer relative paths")
                            violations += 1

                if has_annotation and enforce_dirs and "as-a-real-non-nix-store-file=" not in trimmed:
                    file_match = re.search(r'file=([^\s}"]+)', trimmed)
                    if file_match:
                        target = file_match.group(1)
                        target_dir = os.path.dirname(target)
                        src_rel_dir = os.path.relpath(root, source_dir)
                        expected_dir = "" if src_rel_dir == "." else src_rel_dir
                        if target_dir != expected_dir:
                            print(f"  error core/directory-mismatch: {path}:{num}")
                            print(f"    file={target} does not match source dir {src_rel_dir}/. Use as-a-real-non-nix-store-file= for bootstrap files.")
                            errors += 1
                continue

            if trimmed.startswith(fence) and in_block:
                in_block = False
                if block_lines > max_block:
                    print(f"  error core/block-length: {path}:{block_start}")
                    print(f"    Code block is {block_lines} lines - split with prose")
                    violations += 1
                continue

            if in_block:
                block_lines += 1
                if forbid_comments and re.match(r"^\s*(//|/\*|\*/)", line):
                    if "http://" not in line and "https://" not in line:
                        print(f"  error core/no-comments-in-blocks: {path}:{num}")
                        print(f"    Comments belong in prose between blocks")
                        errors += 1
            else:
                if len(trimmed) > 0 and not trimmed.startswith("#") and not trimmed.startswith("---"):
                    prose_lines += 1

        if prose_lines < min_prose:
            print(f"  error core/prose-density: {path}:1")
            print(f"    Only {prose_lines} prose lines - minimum is {min_prose}")
            errors += 1

        if first_block and not has_intro:
            print(f"  error core/intro-prose: {path}:1")
            print(f"    No prose before first code block")
            errors += 1

for root, _, files in os.walk(source_dir):
    for name in files:
        if name.endswith(".md") or name.endswith(".mdx"):
            if not (name.endswith(".lit.mdx") or name.endswith(".lit.md")):
                path = os.path.join(root, name)
                print(f"  error core/non-literate-file: {path}")
                print(f"    File must end in .lit.md or .lit.mdx to be processed. Rename it.")
                errors += 1

if errors > 0:
    print(f"[${config.name}] {errors} violations")
    sys.exit(1)
LITCHECK
        '';
      }]
      (mkClaimChecks { inherit sourceDir; })
      (lib.optional (tooltipCheckFile != null) {
        name = "input-title-tooltips";
        command = ''
          if grep -q '<input[^>]*title="' ${lib.escapeShellArg tooltipCheckFile} 2>/dev/null; then
            echo "[${config.name}] ERROR: <input> elements with title= tooltips found."
            grep -n '<input[^>]*title="' ${lib.escapeShellArg tooltipCheckFile} | head -10
            exit 1
          fi
        '';
      })
    ];
```

## Post-tangle checks

No default post-tangle checks. Block-length is already checked pre-tangle with configurable `maxBlockLength`.

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
  mkDefaultPostTangleChecks = [ ];
```

## Check execution helpers

`collectNativeBuildInputs` flattens per-check dependency lists; `renderChecks` builds the bash script that runs them, wrapping warn-mode checks in `set +e` so they report without aborting.

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
  collectNativeBuildInputs = checks:
    builtins.concatLists (map (check: check.nativeBuildInputs or [ ]) checks);

  renderChecks = phase: checks: let tag = "[${config.name}:${phase}]"; in
    builtins.concatStringsSep "\n" (map
      (check: let
        body = ''( set -euo pipefail; cd ${lib.escapeShellArg (check.cwd or ".")}; ${check.command} )'';
      in ''
        echo "${tag} ${check.description or check.name}"
      '' + (if (check.mode or "error") == "warn" then ''
        set +e
        ${body}
        status=$?
        set -e
        if [ "$status" -ne 0 ]; then
          echo "${tag} WARNING: ${check.name} failed with exit code $status"
        fi
      '' else body))
      checks);
```

## Water model check execution

`renderChecksWaterModel` runs ALL checks in a stage, collects all violations, and shows everything at once. Only fails at the end if any error-mode check failed. This is the O(n) water model — contrast with `renderChecks` which aborts at the first error.

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
  renderChecksWaterModel = phase: checks: let tag = "[${config.name}:${phase}]"; var = "_${config.name}"; in ''
    ${var}_errors=0
    ${var}_passed=""
    ${builtins.concatStringsSep "\n" (map
      (check:
        let
          needs = check.needs or [];
          needsCheck = if needs == [] then "true" else
            builtins.concatStringsSep " && " (map (n: ''echo "''$${var}_passed" | grep -qw "${n}"'') needs);
        in ''
        if ${needsCheck}; then
          echo "${tag} ${check.description or check.name}"
          set +e
          ( set -euo pipefail; cd ${lib.escapeShellArg (check.cwd or ".")}; ${check.command} )
          ${var}_status=$?
          set -e
          if [ "''$${var}_status" -ne 0 ]; then
            ${if (check.mode or "error") == "warn" then ''
              echo "${tag} WARNING: ${check.name} failed"
              ${var}_passed="''$${var}_passed ${check.name}"
            '' else ''
              echo "${tag} ERROR: ${check.name} failed"
              ${var}_errors=$((${var}_errors + 1))
            ''}
          else
            ${var}_passed="''$${var}_passed ${check.name}"
          fi
        else
          echo "${tag} SKIPPED: ${check.name} (needs not met: ${builtins.concatStringsSep ", " needs})"
        fi
      '')
      checks)}
    if [ "''$${var}_errors" -gt 0 ]; then
      echo "${tag} ''$${var}_errors error(s)"
      exit 1
    fi
  '';
```

## mkProjectCheck — single-check derivation builder

`mkProjectCheck` wraps a single check in a nix derivation, making each custom check independently addressable and cacheable as `nix build .#checks.x86_64-linux.post-my-check`.

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
  mkProjectCheck = {
    pkgs, src, name, command,
    nativeBuildInputs ? [ ],
    beforeTangle ? false,
    stripGeneratedMarkers ? true
  }:
    pkgs.runCommand name {
      nativeBuildInputs = [ (config.entangledFor pkgs) (config.pythonFor pkgs) ] ++ nativeBuildInputs;
    } ''
      set -euo pipefail
      ${pipeline.projectSetup { inherit src; }}
      ${lib.optionalString (!beforeTangle) (pipeline.tangleProject { inherit stripGeneratedMarkers; })}
      ${command}
      touch "$out"
    '';
```

## Structural integrity checks

`checkIdempotent` runs tangle twice and diffs the results (any difference is a hard failure); `checkImmutable` asserts every output file has permissions `444`.

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
  checkIdempotent = {
    src, name ? "idempotent-check", pkgs,
 stripGeneratedMarkers ? true
  }:
    let
      run1 = pipeline.tangle { inherit src pkgs stripGeneratedMarkers; name = "''${name}-run1"; };
      run2 = pipeline.tangle { inherit src pkgs stripGeneratedMarkers; name = "''${name}-run2"; };
    in pkgs.runCommand name { } ''
      diff -r ${run1} ${run2} || \
        (echo "ERROR: Tangle is NOT idempotent" && exit 1)
      echo "OK: Tangle is idempotent"
      touch "$out"
    '';

  checkImmutable = { tangled, name ? "immutable-check", pkgs }:
    pkgs.runCommand name { } ''
      find ${tangled} -type f | while read -r file; do
        perms=$(stat -c %a "$file")
        if [ "$perms" != "444" ]; then
          echo "ERROR: $file has permissions $perms, expected 444"
          exit 1
        fi
      done
      echo "OK: All tangled files are immutable (444)"
      touch "$out"
    '';
```

## makeNamedChecks — per-check derivations for custom checks

Each check in `preTangleChecks` / `postTangleChecks` gets its own named derivation prefixed `pre-` or `post-`, with warn-mode checks exiting 0 so the derivation succeeds and caches.

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
  makeNamedChecks = {
    phase, checks, pkgs, src, stripGeneratedMarkers
  }:
    lib.listToAttrs (map
      (check:
        let
          attrName = check.attrName or check.name;
          drvName = lib.strings.sanitizeDerivationName "${phase}-${attrName}";
        in {
          name = "${phase}-${attrName}";
          value = mkProjectCheck {
            inherit pkgs src stripGeneratedMarkers;
            name = drvName;
            command = ''
              set +e
              ${check.command}
              status=$?
              set -e
              if [ "$status" -ne 0 ]; then
                if [ "${check.mode or "error"}" = "warn" ]; then
                  echo "[${config.name}:${phase}] WARNING: ${attrName} failed with exit code $status"
                else
                  exit "$status"
                fi
              fi
            '';
            nativeBuildInputs = check.nativeBuildInputs or [ ];
            beforeTangle = phase == "pre";
          };
        })
      checks);
```

## makeChecks — self-testing API (consumers use makeVerify)

`makeChecks` is used by the library's own flake for self-testing via `nix flake check`. Consumers call `makeVerify` instead — see below. Produces four standard derivations (`tangle-and-check`, `tangle-succeeds`, `tangle-idempotent`, `tangle-immutable`) plus one named derivation per entry in `preTangleChecks` / `postTangleChecks`.

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
  makeChecks = {
    src, pkgs,
    sourceDir ? ".english.lit.md",
    tooltipCheckFile ? null,
    enforceDirectoryMatch ? false,
    stripGeneratedMarkers ? true,
    preTangleChecks ? [ ],
    postTangleChecks ? [ ]
  }:
    let
      allPreChecks = (mkDefaultPreTangleChecks { inherit sourceDir tooltipCheckFile enforceDirectoryMatch; }) ++ preTangleChecks;
      allPostChecks = mkDefaultPostTangleChecks ++ postTangleChecks;
      tangled = pipeline.tangle { inherit src pkgs sourceDir stripGeneratedMarkers; };
    in {
      tangle-and-check = pkgs.runCommand "${config.name}-tangle-and-check" {
        nativeBuildInputs =
          [ (config.entangledFor pkgs) (config.pythonFor pkgs) ]
          ++ collectNativeBuildInputs allPreChecks
          ++ collectNativeBuildInputs allPostChecks;
      } ''
        set -euo pipefail
        ${pipeline.projectSetup { inherit src sourceDir; }}
        ${renderChecks "pre" allPreChecks}
        ${pipeline.tangleProject { inherit sourceDir stripGeneratedMarkers; }}
        ${renderChecks "post" allPostChecks}
        touch "$out"
      '';
      tangle-succeeds = tangled;
      tangle-idempotent = checkIdempotent { inherit src pkgs stripGeneratedMarkers; };
      tangle-immutable = checkImmutable { inherit tangled pkgs; };
    } // makeNamedChecks {
      phase = "pre"; checks = preTangleChecks;
      inherit pkgs src stripGeneratedMarkers;
    } // makeNamedChecks {
      phase = "post"; checks = postTangleChecks;
      inherit pkgs src stripGeneratedMarkers;
    };
```

## Hook DAG helpers — validateNeeds, resolveClosure, filterUntil

These pure functions operate on the `postTangle` hook list. They are extracted to top level so they can be unit-tested directly (see `tests/unit.lit.md`). `makeVerify` calls them internally.

**`validateNeeds`** — walks the hook list in declaration order, asserting every hook's `needs` list references hooks that appear **earlier**. This enforces topological order at eval time, so consumers get a clear error at `nix eval` rather than a cryptic failure during build. A hook that references a non-existent name, or a hook that appears after its dependents, throws with the offending hook name and the missing names.

**`resolveClosure`** — given a target hook name and a `hooksByName` attrset, returns the transitive closure of `needs` as a list, including the target itself. Uses a `visited` accumulator to terminate on cycles (a cycle would short-circuit when it re-encounters a visited node). Order within the closure is not preserved — callers should filter the original ordered list to recover ordering.

**`filterUntil`** — the public entry point used by `until = "hookname"`. When `until == null`, returns the full hook list unchanged. When set, asserts the target hook exists (clear error if not), resolves its transitive closure, and filters the original list to that closure while preserving declaration order.

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
  validateNeeds = hooks:
    let
      go = seen: remaining:
        if remaining == [] then true
        else let h = builtins.head remaining; rest = builtins.tail remaining;
          needs = h.needs or [];
          missing = builtins.filter (n: ! builtins.elem n seen) needs;
        in if missing != [] then
          builtins.throw "Hook '${h.name}' needs [${builtins.concatStringsSep ", " missing}] but they appear after it or don't exist. Reorder your postTangle list."
        else go (seen ++ [h.name]) rest;
    in go [] hooks;

  resolveClosure = { hooksByName, name, visited ? [] }:
    if builtins.elem name visited then visited
    else let
      hook = hooksByName.${name};
      needs = hook.needs or [];
      withSelf = visited ++ [name];
    in builtins.foldl' (acc: n: resolveClosure { inherit hooksByName; name = n; visited = acc; }) withSelf needs;

  filterUntil = { postTangle, until }:
    if until == null then postTangle else
    let
      hooksByName = builtins.listToAttrs (map (h: { name = h.name; value = h; }) postTangle);
      _untilExists = if !(builtins.hasAttr until hooksByName) then
        builtins.throw "until='${until}' does not name a postTangle hook. Available: ${builtins.concatStringsSep ", " (map (h: h.name) postTangle)}"
      else true;
      needed = assert _untilExists; resolveClosure { inherit hooksByName; name = until; };
    in builtins.filter (h: builtins.elem h.name needed) postTangle;
```

## makeVerify — the consumer product

`makeVerify` returns **packages**, not checks. The consumer calls `lib.init`, gets `packages.default`, runs `nix build`. Done.

Each stage is a separate nix derivation depending on the previous. Nix's dependency graph IS the escalating pipeline — if pre-checks fail, tangle never runs. If tangle fails, linters never run. Within each stage, checks use the water model: all run, all violations collected.

Five stages, four gates:

1. `preChecked` — validates literate structure (annotations, prose, invisible blocks)
2. `tangledTree` — entangled extracts code, produces full source + generated tree
3. `linted` — consumer linters run on the tree (water model)
4. `tested` — consumer tests run on the tree (water model)
5. `default` — extracts tangled targets with chmod 444 into nix store

```{.nix file=lib/checks.nix as-a-real-non-nix-store-file="flake.nix imports this module"}
  makeVerify = {
    src, pkgs,
    sourceDir ? ".english.lit.md",
    tooltipCheckFile ? null,
    enforceDirectoryMatch ? false,
    stripGeneratedMarkers ? true,
    postTangle ? [],
    until ? null
  }:
    let
      allPreChecks = mkDefaultPreTangleChecks {
        inherit sourceDir tooltipCheckFile enforceDirectoryMatch;
      };

      preChecked = pkgs.runCommand "literate-pre-checked" {
        nativeBuildInputs = [ (config.pythonFor pkgs) ];
      } ''
        set -euo pipefail
        mkdir -p $out
        cp -r ${src}/. $out/
        chmod -R u+w $out
        cd $out
        ${renderChecksWaterModel "pre" allPreChecks}
      '';

      tangledTree = pkgs.runCommand "literate-tangled-tree" {
        nativeBuildInputs = [ (config.entangledFor pkgs) (config.pythonFor pkgs) ];
      } ''
        set -euo pipefail
        mkdir -p $out
        cp -r ${preChecked}/. $out/
        chmod -R u+w $out
        cd $out
        rm -f .entangled/filedb.json
        cat > entangled.toml <<'TOML'
${config.defaultEntangledToml}
TOML
        ${pipeline.tangleProject { inherit sourceDir stripGeneratedMarkers; }}
      '';

      _needsValid = validateNeeds postTangle;
      effectivePostTangle = filterUntil { inherit postTangle until; };

      # Output: the full tree WITH any hook artifacts (e.g. dist/ from vite build)
      postTangled = assert _needsValid; if effectivePostTangle == [] then tangledTree else
        pkgs.runCommand "literate-post-tangled" {
          nativeBuildInputs = collectNativeBuildInputs effectivePostTangle;
        } ''
          set -euo pipefail
          cp -r ${tangledTree}/. $out/
          chmod -R u+w $out
          cd $out
          ${renderChecksWaterModel "post" effectivePostTangle}
        '';

    in {
      default = postTangled;
      tangled = pipeline.tanglePerFile { inherit src pkgs sourceDir stripGeneratedMarkers; };
    };
}
```
