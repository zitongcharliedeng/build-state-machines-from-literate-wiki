# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[init]
# ~~ This file is generated from literate.lit.md/nix/checks.lit.mdx
{ lib, config, pipeline }:
rec {
# ~/~ end
# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[1]
  mkDefaultPreTangleChecks = {
    sourceDir ? "literate",
    tooltipCheckFile ? "literate/index.lit.md",
    enforceDirectoryMatch ? false
  }:
    lib.flatten [
      [{
        name = "literate-structure";
        command = ''
          python3 - <<'LITCHECK'
import os, re, sys

source_dir = ${builtins.toJSON sourceDir}
min_prose = 3
max_block = 50
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
                print(f"    File must end in .lit.mdx to be processed. Rename it.")
                errors += 1

if errors > 0:
    print(f"[${config.name}] {errors} violations")
    sys.exit(1)
LITCHECK
        '';
      }]
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
# ~/~ end
# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[2]
  mkDefaultPostTangleChecks = [ ];
# ~/~ end
# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[3]
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
# ~/~ end
# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[4]
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
# ~/~ end
# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[5]
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
# ~/~ end
# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[6]
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
# ~/~ end
# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[7]
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
# ~/~ end
# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[8]
  makeChecks = {
    src, pkgs,
    sourceDir ? "literate.lit.md",
    tooltipCheckFile ? null,
    enforceDirectoryMatch ? false,
    stripGeneratedMarkers ? true,
    preTangleChecks ? [ ],
    postTangleChecks ? [ ]
  }:
    let
      allPreChecks = (mkDefaultPreTangleChecks { inherit sourceDir tooltipCheckFile enforceDirectoryMatch; }) ++ preTangleChecks;
      allPostChecks = mkDefaultPostTangleChecks ++ postTangleChecks;
      tangled = pipeline.tangle { inherit src pkgs stripGeneratedMarkers; };
    in {
      tangle-and-check = pkgs.runCommand "${config.name}-tangle-and-check" {
        nativeBuildInputs =
          [ (config.entangledFor pkgs) (config.pythonFor pkgs) ]
          ++ collectNativeBuildInputs allPreChecks
          ++ collectNativeBuildInputs allPostChecks;
      } ''
        set -euo pipefail
        ${pipeline.projectSetup { inherit src; }}
        ${renderChecks "pre" allPreChecks}
        ${pipeline.tangleProject { inherit stripGeneratedMarkers; }}
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
# ~/~ end
# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[9]
  # Walk hook list in order; every hook's needs must reference earlier hooks.
  # Throws on forward reference or missing hook. Returns true on success.
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

  # Transitive closure of needs for a hook, as a list (order not preserved).
  # hooksByName: attrset {hookname = hook;}. Uses visited accumulator to handle cycles.
  resolveClosure = { hooksByName, name, visited ? [] }:
    if builtins.elem name visited then visited
    else let
      hook = hooksByName.${name};
      needs = hook.needs or [];
      withSelf = visited ++ [name];
    in builtins.foldl' (acc: n: resolveClosure { inherit hooksByName; name = n; visited = acc; }) withSelf needs;

  # Filter postTangle list by until target. Returns full list if until is null.
  # Preserves declaration order within the closure.
  filterUntil = { postTangle, until }:
    if until == null then postTangle else
    let
      hooksByName = builtins.listToAttrs (map (h: { name = h.name; value = h; }) postTangle);
      _untilExists = if !(builtins.hasAttr until hooksByName) then
        builtins.throw "until='${until}' does not name a postTangle hook. Available: ${builtins.concatStringsSep ", " (map (h: h.name) postTangle)}"
      else true;
      needed = assert _untilExists; resolveClosure { inherit hooksByName; name = until; };
    in builtins.filter (h: builtins.elem h.name needed) postTangle;
# ~/~ end
# ~/~ begin <<literate.lit.md/lib/checks.lit.md#lib/checks.nix>>[10]
  makeVerify = {
    src, pkgs,
    sourceDir ? "literate.lit.md",
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

      # Stage 1: Pre-check — validates literate structure
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

      # Stage 2: Tangle — entangled extracts code (depends on preChecked)
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
        ${pipeline.tangleProject { inherit stripGeneratedMarkers; }}
      '';

      _needsValid = validateNeeds postTangle;
      effectivePostTangle = filterUntil { inherit postTangle until; };

      # Stage 3: Post-tangle hooks — consumer's commands, water model (depends on tangledTree)
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
# ~/~ end
