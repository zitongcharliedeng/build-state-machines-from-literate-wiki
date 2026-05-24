---
title: Claim Checks — Stage 0 Atom Validation
description: Fixture-based tests for Stage 0 LSMW claim/atom validation over frontmatter YAML
tags: [tests, lsmw, claims, frontmatter, stage-0]
---

# Claim Checks — Stage 0 Atom Validation

Stage 0 validates markdown atoms before XState projections or agents exist.

The DRY encoding rule for this test is: every markdown atom is already a claim. The only required semantic discriminator is `lsmw.claimType`, namespaced under `lsmw` so the YAML frontmatter has one LSMW-owned field system. A file can be named `anything.english.claim.lit.md`; humans and Obsidian can style/query from frontmatter. The library should not require `Claim - ...` or `Machine - ...` in the path, and it should reject duplicate schemas like `lsmw.kind`.

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

## valid-frontmatter-claim-type-builds

A claim atom with YAML `lsmw.claimType = "MachineInvariant"` should validate even though the filename does not contain `Invariant -`.

```{.nix file=tests/claim-checks.nix}
  valid-frontmatter-claim-type-builds = runClaimCheck (mkFixture {
    name = "valid-frontmatter-claim-type-builds";
    files = {
      "machines/voice/high-notes.english.claim.lit.md" = ''
        ---
        title: High notes require independent mouth parts
        lsmw:
          claimType: MachineInvariant
        ---

        This is enough prose to be a living Stage 0 claim atom.
      '';
    };
  });
```

## missing-claim-type-fails

A markdown atom under `.english.lit.md` without `lsmw.claimType` should fail the claim check. This makes YAML the encoded source of truth instead of path prefixes.

```{.nix file=tests/claim-checks.nix}
  missing-claim-type-fails = runClaimCheckExpectFailure {
    name = "missing-claim-type-fails";
    expected = "missing lsmw.claimType";
    src = mkFixture {
      name = "missing-claim-type-fails";
      files = {
        "machines/voice/high-notes.english.claim.lit.md" = ''
          ---
          title: High notes require independent mouth parts
          ---

          This atom has no encoded LSMW kind, so Stage 0 cannot type-check it.
        '';
      };
    };
  };
```

## kind-field-fails

`lsmw.kind` is a duplicate type system. Since every markdown atom is already a claim, Stage 0 should reject it.

```{.nix file=tests/claim-checks.nix}
  kind-field-fails = runClaimCheckExpectFailure {
    name = "kind-field-fails";
    expected = "remove lsmw.kind";
    src = mkFixture {
      name = "kind-field-fails";
      files = {
        "machines/voice/high-notes.english.claim.lit.md" = ''
          ---
          title: High notes require independent mouth parts
          lsmw:
            kind: invariant
            claimType: MachineInvariant
          ---

          The duplicate kind field should fail because claimType is the only Stage 0 discriminator.
        '';
      };
    };
  };
```

## all-markdown-needs-claim-type-fails

`Raw` only makes sense if Stage 0 can type ordinary markdown claim material too, not only files under `machines/`.

```{.nix file=tests/claim-checks.nix}
  all-markdown-needs-claim-type-fails = runClaimCheckExpectFailure {
    name = "all-markdown-needs-claim-type-fails";
    expected = "missing lsmw.claimType";
    src = mkFixture {
      name = "all-markdown-needs-claim-type-fails";
      files = {
        "notes/untyped-thought.md" = ''
          ---
          title: Untyped thought
          ---

          This is markdown claim material and must still carry claimType.
        '';
      };
    };
  };
```

## missing-prereq-claim-target-fails

Claim relation fields should be checked: a missing prerequisite claim target is a Stage 0 graph error.

```{.nix file=tests/claim-checks.nix}
  missing-prereq-claim-target-fails = runClaimCheckExpectFailure {
    name = "missing-prereq-claim-target-fails";
    expected = "missing prereqClaims target";
    src = mkFixture {
      name = "missing-prereq-claim-target-fails";
      files = {
        "machines/voice/high-notes.english.claim.lit.md" = ''
          ---
          title: High notes require independent mouth parts
          lsmw:
            claimType: MachineInvariant
            prereqClaims:
              - notes/missing-source.md
          ---

          This claim depends on a claim file that does not exist.
        '';
      };
    };
  };
```

## prereq-and-assuming-claims-can-target-any-claim-file

`prereqClaims` and `assumingClaims` should accept any claim file in the source surface, including `Raw` notes outside `machines/`.

```{.nix file=tests/claim-checks.nix}
  prereq-and-assuming-claims-can-target-any-claim-file = runClaimCheck (mkFixture {
    name = "prereq-and-assuming-claims-can-target-any-claim-file";
    files = {
      "notes/breath-source.md" = ''
        ---
        title: Breath source observation
        lsmw:
          claimType: Raw
        ---

        A raw observation can still be referenced as claim material.
      '';
      "machines/voice/high-notes.english.claim.lit.md" = ''
        ---
        title: High notes require independent mouth parts
        lsmw:
          claimType: MachineInvariant
          prereqClaims:
            - notes/breath-source.md
          assumingClaims:
            - notes/breath-source.md
        ---

        The referenced file is not under machines, but it is still a claim file.
      '';
    };
  });
}
```
