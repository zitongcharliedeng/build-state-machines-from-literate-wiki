---
title: Claim Checks — Stage 0 Atom Validation
description: Fixture-based tests for Stage 0 LSMW claim/atom validation over frontmatter YAML
tags: [tests, lsmw, claims, frontmatter, stage-0]
---

# Claim Checks — Stage 0 Atom Validation

Stage 0 validates markdown atoms before XState projections or agents exist.

The DRY encoding rule for this test is: the atom kind lives in YAML frontmatter, not in the filename. A file can be named `anything.english.lit.md`; humans and Obsidian can style/query from frontmatter. The library should not require `Claim - ...` or `Machine - ...` in the path.

This keeps the source API stable while leaving UI readability to projections/plugins/views.

```{.nix file=tests/claim-checks.nix}
{ pkgs, lib, checksLib }:
let
  mkFixture = { name, files }:
    pkgs.runCommand "claim-check-fixture-${name}" { } ''
      mkdir -p $out/.english.lit.md
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: content: ''
        mkdir -p "$out/.english.lit.md/$(dirname ${lib.escapeShellArg path})" 2>/dev/null || true
        cat > "$out/.english.lit.md/${path}" <<'LSMW_EOF'
${content}
LSMW_EOF
      '') files)}
    '';

  runClaimCheck = src: pkgs.runCommand "run-claim-check" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    cp -r ${src}/. build
    chmod -R u+w build
    cd build
    ${checksLib.renderChecksWaterModel "pre" (checksLib.mkClaimChecks { sourceDir = ".english.lit.md"; })}
    touch "$out"
  '';

  runClaimCheckExpectFailure = { name, src, expected }:
    pkgs.runCommand "claim-check-fails-${name}" {
      nativeBuildInputs = [ pkgs.python3 ];
    } ''
      cp -r ${src}/. build
      chmod -R u+w build
      cd build
      set +e
      (
        ${checksLib.renderChecksWaterModel "pre" (checksLib.mkClaimChecks { sourceDir = ".english.lit.md"; })}
      ) > log 2>&1
      status=$?
      set -e
      if [ "$status" -eq 0 ]; then
        echo "FAIL: claim check unexpectedly passed"
        cat log
        exit 1
      fi
      grep -q ${lib.escapeShellArg expected} log || { echo "FAIL: expected diagnostic not found: ${expected}"; cat log; exit 1; }
      touch "$out"
    '';
in {
```

## valid-frontmatter-kind-builds

A claim atom with YAML `lsmw.kind = "claim"` should validate even though the filename does not contain `Claim -`.

```{.nix file=tests/claim-checks.nix}
  valid-frontmatter-kind-builds = runClaimCheck (mkFixture {
    name = "valid-frontmatter-kind-builds";
    files = {
      "machines/voice/high-notes.english.lit.md" = ''
        ---
        title: High notes require independent mouth parts
        lsmw:
          kind: claim
          claimType: supporting
          status: raw
        ---

        This is enough prose to be a living Stage 0 claim atom.
      '';
    };
  });
```

## missing-kind-fails

A markdown atom under `.english.lit.md` without `lsmw.kind` should fail the claim check. This makes YAML the encoded source of truth instead of path prefixes.

```{.nix file=tests/claim-checks.nix}
  missing-kind-fails = runClaimCheckExpectFailure {
    name = "missing-kind-fails";
    expected = "missing lsmw.kind";
    src = mkFixture {
      name = "missing-kind-fails";
      files = {
        "machines/voice/high-notes.english.lit.md" = ''
          ---
          title: High notes require independent mouth parts
          ---

          This atom has no encoded LSMW kind, so Stage 0 cannot type-check it.
        '';
      };
    };
  };
}
```
