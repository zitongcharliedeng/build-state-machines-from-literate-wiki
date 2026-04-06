# ~~  ~/~ begin <<literate.lit.mdx/lib/checks.lit.mdx#lib/checks.nix>>[init]
# ~~ This file is generated from literate.lit.mdx/nix/checks.lit.mdx
{ lib, config, pipeline }:
rec {
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/checks.lit.mdx#lib/checks.nix>>[1]
  mkDefaultPreTangleChecks = {
    sourceDir ? "literate",
    forbidTsComments ? true,
    tooltipCheckFile ? "literate/index.lit.md",
    minProseLines ? 3,
    maxBlockLength ? 50,
    enforceDirectoryMatch ? false
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
forbid_comments = ${if forbidTsComments then "True" else "False"}
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

                if has_annotation and enforce_dirs and "as-absolute-file-path=" not in trimmed:
                    file_match = re.search(r'file=([^\s}"]+)', trimmed)
                    if file_match:
                        target = file_match.group(1)
                        target_dir = os.path.dirname(target)
                        src_rel_dir = os.path.relpath(root, source_dir)
                        expected_dir = "" if src_rel_dir == "." else src_rel_dir
                        if target_dir != expected_dir:
                            print(f"  error core/directory-mismatch: {path}:{num}")
                            print(f"    file={target} does not match source dir {src_rel_dir}/. Use as-real-file-path= to override.")
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
    print(f"[literate-state-machine-wiki] {errors} violations")
    sys.exit(1)
LITCHECK
        '';
      }]
      (lib.optional (tooltipCheckFile != null) {
        name = "input-title-tooltips";
        command = ''
          if grep -q '<input[^>]*title="' ${lib.escapeShellArg tooltipCheckFile} 2>/dev/null; then
            echo "[literate-state-machine-wiki] ERROR: <input> elements with title= tooltips found."
            grep -n '<input[^>]*title="' ${lib.escapeShellArg tooltipCheckFile} | head -10
            exit 1
          fi
        '';
      })
    ];
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/checks.lit.mdx#lib/checks.nix>>[2]
  mkDefaultPostTangleChecks = {
    sourceDir ? "literate"
  }:
    [ ];
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/checks.lit.mdx#lib/checks.nix>>[3]
  collectNativeBuildInputs = checks:
    builtins.concatLists (map (check: check.nativeBuildInputs or [ ]) checks);

  renderChecks = phase: checks:
    builtins.concatStringsSep "\n" (map
      (check:
        if (check.mode or "error") == "warn" then ''
          echo "[literate-state-machine-wiki:${phase}] ${check.description or check.name}"
          set +e
          (
            cd ${lib.escapeShellArg (check.cwd or ".")}
            ${check.command}
          )
          status=$?
          set -e
          if [ "$status" -ne 0 ]; then
            echo "[literate-state-machine-wiki:${phase}] WARNING: ${check.name} failed with exit code $status"
          fi
        '' else ''
          echo "[literate-state-machine-wiki:${phase}] ${check.description or check.name}"
          (
            cd ${lib.escapeShellArg (check.cwd or ".")}
            ${check.command}
          )
        '')
      checks);
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/checks.lit.mdx#lib/checks.nix>>[4]
  renderChecksWaterModel = phase: checks: ''
    _lsmw_errors=0
    ${builtins.concatStringsSep "\n" (map
      (check: ''
        echo "[literate-state-machine-wiki:${phase}] ${check.description or check.name}"
        set +e
        (
          cd ${lib.escapeShellArg (check.cwd or ".")}
          ${check.command}
        )
        _lsmw_status=$?
        set -e
        if [ "$_lsmw_status" -ne 0 ]; then
          ${if (check.mode or "error") == "warn" then ''
            echo "[literate-state-machine-wiki:${phase}] WARNING: ${check.name} failed"
          '' else ''
            echo "[literate-state-machine-wiki:${phase}] ERROR: ${check.name} failed"
            _lsmw_errors=$((_lsmw_errors + 1))
          ''}
        fi
      '')
      checks)}
    if [ "$_lsmw_errors" -gt 0 ]; then
      echo "[literate-state-machine-wiki:${phase}] $_lsmw_errors error(s)"
      exit 1
    fi
  '';
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/checks.lit.mdx#lib/checks.nix>>[5]
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
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/checks.lit.mdx#lib/checks.nix>>[6]
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
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/checks.lit.mdx#lib/checks.nix>>[7]
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
                  echo "[literate-state-machine-wiki:${phase}] WARNING: ${attrName} failed with exit code $status"
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
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/checks.lit.mdx#lib/checks.nix>>[8]
  makeChecks = {
    src, pkgs,
    sourceDir ? "literate",
    forbidTsComments ? true,
    tooltipCheckFile ? "literate/index.lit.md",
    minProseLines ? 3,
    maxBlockLength ? 50,
    enforceDirectoryMatch ? false,
    stripGeneratedMarkers ? true,
    preTangleChecks ? [ ],
    postTangleChecks ? [ ]
  }:
    let
      allPreChecks = (mkDefaultPreTangleChecks { inherit sourceDir forbidTsComments tooltipCheckFile minProseLines maxBlockLength enforceDirectoryMatch; }) ++ preTangleChecks;
      allPostChecks = (mkDefaultPostTangleChecks { inherit sourceDir; }) ++ postTangleChecks;
      tangled = pipeline.tangle { inherit src pkgs stripGeneratedMarkers; };
    in {
      tangle-and-check = pkgs.runCommand "literate-state-machine-wiki-tangle-and-check" {
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
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/checks.lit.mdx#lib/checks.nix>>[9]
  makeVerify = {
    src, pkgs,
    sourceDir ? "literate.lit.mdx",
    forbidTsComments ? true,
    tooltipCheckFile ? null,
    minProseLines ? 3,
    maxBlockLength ? 50,
    enforceDirectoryMatch ? false,
    stripGeneratedMarkers ? true,
    linters ? [],
    tests ? []
  }:
    let
      allPreChecks = mkDefaultPreTangleChecks {
        inherit sourceDir forbidTsComments tooltipCheckFile minProseLines maxBlockLength enforceDirectoryMatch;
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

      # Stage 3: Lint — consumer linters, water model (depends on tangledTree)
      # Output: the full tree WITH any linter artifacts (e.g. dist/ from vite build)
      linted = if linters == [] then tangledTree else
        pkgs.runCommand "literate-linted" {
          nativeBuildInputs = collectNativeBuildInputs linters;
        } ''
          set -euo pipefail
          cp -r ${tangledTree}/. $out/
          chmod -R u+w $out
          cd $out
          ${renderChecksWaterModel "lint" linters}
        '';

      # Stage 4: Test — consumer tests, water model (depends on linted)
      # Output: the full tree WITH linter + test artifacts
      tested = if tests == [] then linted else
        pkgs.runCommand "literate-tested" {
          nativeBuildInputs = collectNativeBuildInputs tests;
        } ''
          set -euo pipefail
          cp -r ${linted}/. $out/
          chmod -R u+w $out
          cd $out
          ${renderChecksWaterModel "test" tests}
        '';

    in {
      default = tested;
      tangled = pipeline.tangle { inherit src pkgs stripGeneratedMarkers; };
    };
}
# ~~  ~/~ end
