---
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

  runClaimInventory = { name, src, expected }:
    pkgs.runCommand "claim-inventory-${name}" {
      nativeBuildInputs = [ pkgs.python3 ];
    } ''
      cp -r ${src}/. build
      chmod -R u+w build
      cd build
      (
        ${checksLib.renderChecksWaterModel "pre" (checksLib.mkClaimChecks { sourceDir = ".english.lit.md"; reportOnly = true; })}
      ) > log 2>&1
      grep -q ${lib.escapeShellArg expected} log || { echo "FAIL: expected inventory diagnostic not found: ${expected}"; cat log; exit 1; }
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
    expected = "markdown claim atoms need YAML frontmatter with lsmw.claimType";
    src = mkFixture {
      name = "missing-claim-type-fails";
      files = {
        "machines/voice/high-notes.english.claim.lit.md" = ''
          ---
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
    expected = "markdown claim atoms need YAML frontmatter with lsmw.claimType";
    src = mkFixture {
      name = "all-markdown-needs-claim-type-fails";
      files = {
        "notes/untyped-thought.md" = ''
          ---
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
      "assumptions/breath-source.english.claim.lit.md" = ''
        ---
        lsmw:
          claimType: Raw
        ---

        A raw observation can still be referenced as claim material.
      '';
      "machines/voice/high-notes.english.claim.lit.md" = ''
        ---
        lsmw:
          claimType: MachineInvariant
          prereqClaims:
            - assumptions/breath-source.english.claim.lit.md
          assumingClaims:
            - assumptions/breath-source.english.claim.lit.md
        ---

        The referenced file is not under machines, but it is still a claim file.
      '';
    };
  });
```

## yaml-title-field-fails

The title is already the human filename/prose heading. Stage 0 should reject duplicated YAML `title` metadata.

```{.nix file=tests/claim-checks.nix}
  yaml-title-field-fails = runClaimCheckExpectFailure {
    name = "yaml-title-field-fails";
    expected = "remove YAML title";
    src = mkFixture {
      name = "yaml-title-field-fails";
      files = {
        "machines/voice/high-notes.english.claim.lit.md" = ''
          ---
          title: High notes require independent mouth parts
          lsmw:
            claimType: MachineInvariant
          ---

          The title field duplicates the filename and should fail.
        '';
      };
    };
  };
```

## type-prefix-filename-fails

Claim type belongs in `lsmw.claimType`, not filename prefixes like `Invariant -` or `Claim -`.

```{.nix file=tests/claim-checks.nix}
  type-prefix-filename-fails = runClaimCheckExpectFailure {
    name = "type-prefix-filename-fails";
    expected = "remove type prefix from filename";
    src = mkFixture {
      name = "type-prefix-filename-fails";
      files = {
        "machines/voice/Invariant - High notes require independent mouth parts.md" = ''
          ---
          lsmw:
            claimType: MachineInvariant
          ---

          The semantic type is already in lsmw.claimType.
        '';
      };
    };
  };
```

## machine-prefix-directory-fails

Machine folders should be canonical path segments such as `machines/voice`, not duplicated `Machine - Voice` labels.

```{.nix file=tests/claim-checks.nix}
  machine-prefix-directory-fails = runClaimCheckExpectFailure {
    name = "machine-prefix-directory-fails";
    expected = "remove machine prefix from directory";
    src = mkFixture {
      name = "machine-prefix-directory-fails";
      files = {
        "Machine - Voice/high-notes.english.claim.md" = ''
          ---
          lsmw:
            claimType: MachineInvariant
          ---

          The directory repeats machine semantics that belong in the machine root path and claims.
        '';
      };
    };
  };
```

## transition-requires-field-fails

A purist transition part owns event/boundary/from/to/effects. It must not attach invariant prerequisites through a `requires:` field; conditional behavior belongs in guards, and invariants are checked over the composed machine.

```{.nix file=tests/claim-checks.nix}
  transition-requires-field-fails = runClaimCheckExpectFailure {
    name = "transition-requires-field-fails";
    expected = "transition parts must not use requires";
    src = mkFixture {
      name = "transition-requires-field-fails";
      files = {
        "machines/web/user-opens-localhost.english.claim.lit.md" = ''
          ---
          lsmw:
            claimType: MachineTransition
          ---

          Opening localhost enters the initial Web LifeOS state.

          ```xstate-parts
          transitionPart({
            fromBoundary: "machine-start";
            requires: ["[[public version check is disabled]]"];
            toStateConfigPattern: ["[[home page]]"];
          });
          ```
        '';
      };
    };
  };
```

## report-only-inventory-lists-violations-without-failing

A cleanup pass needs a safe inventory mode before mass migration. `reportOnly = true` should print the same diagnostics but exit successfully so dirty sources such as the NixOS literate system can be surveyed before any enforcement step.

```{.nix file=tests/claim-checks.nix}
  report-only-inventory-lists-violations-without-failing = runClaimInventory {
    name = "report-only-inventory-lists-violations-without-failing";
    expected = "claim/missing-frontmatter";
    src = mkFixture {
      name = "report-only-inventory-lists-violations-without-failing";
      files = {
        "possible-nixos/literate/apps/hermes-agent.lit.md" = ''
          ---
          ---

          This file is intentionally unpromoted source material.
          It should appear in a report-only inventory before enforcement.
        '';
      };
    };
  };
}
```
