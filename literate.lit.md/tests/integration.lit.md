---
description: Fixture-based integration tests that build tiny literate projects and assert expected outputs
tags: [tests, integration, nix, fixtures]
---

# Integration Tests — End-to-End Pipeline

Unit tests prove the DAG helpers are correct in isolation. Integration tests prove they work **inside a real build**: a tiny fixture project goes in, `lib.init` runs, a derivation comes out (or fails in the expected way). Slower than unit tests (each is a real nix derivation with a tangle + hook pipeline) but they catch bugs that only surface under the full pipeline — shell quoting, water-model propagation, pre-tangle check ordering, hook skip-on-failed-deps.

The fixtures here cover transitions visible from outside the pipeline: success path, warn-mode propagation, warn-mode non-abort, needs ordering, and `until` transitive resolution. The error-mode failure and dep-failed skip transitions are tested at the shell-script level in [[tests/water-model]] — a derivation that aborts produces no output to inspect, so the abort-behavior tests rendering `renderChecksWaterModel` directly is much cleaner.

## Fixture builder

`mkFixture` writes a minimal `.english.lit.md/hello.lit.md` to a tree, then runs `lib.init` with the fixture's `postTangle` hooks. We can't call `lib.init` from inside another derivation's build phase (IFD-within-IFD), so the fixture tree is built in one derivation and passed at eval time. `assertBuilds` and `assertHookRan` are the two assertion shapes — file present, or file present with marker content.

```{.nix file=tests/integration.nix}
{ pkgs, lib, lsmwInit, tangleAndRead }:
let
  minimalLit = ''
    ---
    description: minimal fixture for integration tests
    tags: [test]
    lsmw:
      claimType: Raw
    ---

    # Hello

    This is a minimal literate file with enough prose to pass the default prose density check. The library requires at least three lines of prose before any code block, and this paragraph satisfies that constraint.

    ```{.sh file=hello.sh}
    #!/bin/sh
    echo "hello from tangled script"
    ```
  '';

  mkFixtureTree = { name, litContent, litFile ? "hello.lit.md" }:
    pkgs.runCommand "fixture-${name}-tree" { } ''
      mkdir -p $out/.english.lit.md/$(dirname ${lib.escapeShellArg litFile})
      cat > $out/.english.lit.md/${litFile} <<'LIT_EOF'
      ${litContent}
      LIT_EOF
    '';

  localDotTargetLit = ''
    ---
    lsmw:
      claimType: Raw
    ---

    Dot-local targets inherit the literate owner filename.

    This fixture uses the default English literate filename form.

    The target `file=.ts` should produce `machine.english.ts`.

    ```{file=.ts}
    export const localDotTarget = "ok";
    ```
  '';

  mkFixture = { name, litContent, litFile ? "hello.lit.md", postTangle ? [], until ? null }:
    let
      tree = mkFixtureTree { inherit name litContent litFile; };
      outputs = lsmwInit {
        inherit pkgs postTangle until;
        src = tree;
        ignoreLiterateGitSubmodules = true;
      };
    in outputs.packages.${pkgs.stdenv.hostPlatform.system}.default;

  assertBuilds = { name, fixture, expectFile ? "hello.sh" }:
    pkgs.runCommand "assert-builds-${name}" { } ''
      if [ ! -f ${fixture}/${expectFile} ]; then
        echo "FAIL: ${expectFile} not found in ${name} fixture output"; ls -la ${fixture}; exit 1
      fi
      echo "PASS: ${name} built and produced ${expectFile}"; touch "$out"
    '';

  assertHookRan = { name, fixture, marker, markerFile ? "hook-marker" }:
    pkgs.runCommand "assert-hook-ran-${name}" { } ''
      if [ ! -f ${fixture}/${markerFile} ]; then
        echo "FAIL: ${markerFile} not present — hook did not run for ${name}"; exit 1
      fi
      if ! grep -q "${marker}" ${fixture}/${markerFile}; then
        echo "FAIL: marker '${marker}' not found in ${markerFile} for ${name}"; cat ${fixture}/${markerFile}; exit 1
      fi
      echo "PASS: ${name} hook ran and wrote marker '${marker}'"; touch "$out"
    '';
in {
```

## minimal — the happy-path baseline

A literate fixture with one tangle target builds and produces the expected file. If this fails, the entire pipeline is broken before we test anything interesting.

```{.nix file=tests/integration.nix}
  minimal = assertBuilds {
    name = "minimal";
    fixture = mkFixture { name = "minimal"; litContent = minimalLit; };
  };
```

## local-dot-target — owner filename is inherited

A source file named `machine.english.lit.md` can use `file=.ts`. LSMW expands the target to `machine.english.ts` and infers the TypeScript fence language before Entangled runs.

```{.nix file=tests/integration.nix}
  local-dot-target = assertBuilds {
    name = "local-dot-target";
    fixture = mkFixture {
      name = "local-dot-target";
      litContent = localDotTargetLit;
      litFile = "machine.english.lit.md";
    };
    expectFile = "machine.english.ts";
  };
```

## tangle-and-read-local-dot-target — eval-time reader uses the same rule

`tangleAndRead` is the eval-time consumer API. It must apply the same local-dot target expansion as the build pipeline.

```{.nix file=tests/integration.nix}
  tangle-and-read-local-dot-target =
    let
      tree = mkFixtureTree {
        name = "tangle-and-read-local-dot-target";
        litContent = localDotTargetLit;
        litFile = "machine.english.lit.md";
      };
      content = tangleAndRead { inherit pkgs; src = tree; file = "machine.english.ts"; };
    in pkgs.runCommand "tangle-and-read-local-dot-target" { } ''
      cat > content.ts <<'CONTENT'
${content}
CONTENT
      grep -q 'localDotTarget = "ok"' content.ts
      touch "$out"
    '';
```

## post-tangle-success — hook runs, writes marker

A `postTangle` hook executes and its file artifact lands in the post-tangled tree. This proves hooks have access to the tangled output and can mutate it.

```{.nix file=tests/integration.nix}
  post-tangle-success = assertHookRan {
    name = "post-tangle-success";
    fixture = mkFixture {
      name = "post-tangle-success";
      litContent = minimalLit;
      postTangle = [{ name = "write-marker"; command = "echo 'hook-ran' > hook-marker"; }];
    };
    marker = "hook-ran";
  };
```

## post-tangle-warn-mode — warn failures don't abort

A `mode = "warn"` hook that exits 1 must not abort the build; subsequent hooks run, and the build still produces output. Warn mode is for non-fatal advisories (linters, format-checks).

```{.nix file=tests/integration.nix}
  post-tangle-warn-mode = assertBuilds {
    name = "post-tangle-warn-mode";
    fixture = mkFixture {
      name = "post-tangle-warn-mode";
      litContent = minimalLit;
      postTangle = [
        { name = "failing-warn"; command = "exit 1"; mode = "warn"; }
        { name = "after-warn"; command = "echo 'still-ran' > hook-marker"; }
      ];
    };
    expectFile = "hook-marker";
  };
```

## needs-warn-propagates — warn-failed dep still satisfied

When a hook with `needs = [ "warn-failed" ]` runs, it does so because warn-mode adds to `_lsmw_passed` even on failure. Contrast with error mode, where dependents skip and the pipeline aborts.

```{.nix file=tests/integration.nix}
  needs-warn-propagates = assertHookRan {
    name = "needs-warn-propagates";
    fixture = mkFixture {
      name = "needs-warn-propagates";
      litContent = minimalLit;
      postTangle = [
        { name = "warn-fails"; command = "exit 1"; mode = "warn"; }
        { name = "after-warn"; command = "echo 'propagated' > warn-propagate-marker"; needs = [ "warn-fails" ]; }
      ];
    };
    marker = "propagated";
    markerFile = "warn-propagate-marker";
  };
```

## needs-success-chain — order proven by content

Hooks `a → b → c` write their names to a single file. The contents must be `a\nb\nc` in order — proving the topological sort actually executes hooks in dependency order, not just declares it.

```{.nix file=tests/integration.nix}
  needs-success-chain = pkgs.runCommand "needs-success-chain" { } ''
    fixture=${mkFixture {
      name = "needs-success-chain";
      litContent = minimalLit;
      postTangle = [
        { name = "a"; command = "echo a >> chain-marker"; }
        { name = "b"; command = "echo b >> chain-marker"; needs = [ "a" ]; }
        { name = "c"; command = "echo c >> chain-marker"; needs = [ "b" ]; }
      ];
    }}
    content=$(cat $fixture/chain-marker)
    expected=$'a\nb\nc'
    if [ "$content" != "$expected" ]; then
      echo "FAIL: expected chain 'a b c', got:"; echo "$content"; exit 1
    fi
    echo "PASS: needs ran in order a → b → c"; touch "$out"
  '';
```

## until-transitive — `until` walks the full chain

`until = "c"` over hooks `{a, b, c, d, e}` where `c` needs `b` needs `a`, and `e` needs `d`: must run `{a, b, c}` and skip `{d, e}`. Proves transitive resolution walks the full needs-chain, not just direct deps.

```{.nix file=tests/integration.nix}
  until-transitive = pkgs.runCommand "until-transitive" { } ''
    fixture=${mkFixture {
      name = "until-transitive";
      litContent = minimalLit;
      until = "c";
      postTangle = [
        { name = "a"; command = "echo a > a-marker"; }
        { name = "b"; command = "echo b > b-marker"; needs = [ "a" ]; }
        { name = "c"; command = "echo c > c-marker"; needs = [ "b" ]; }
        { name = "d"; command = "echo d > d-marker"; }
        { name = "e"; command = "echo e > e-marker"; needs = [ "d" ]; }
      ];
    }}
    for f in a-marker b-marker c-marker; do
      if [ ! -f $fixture/$f ]; then echo "FAIL: $f missing — until=c should include full chain"; exit 1; fi
    done
    for f in d-marker e-marker; do
      if [ -f $fixture/$f ]; then echo "FAIL: $f present — until=c should exclude unrelated"; exit 1; fi
    done
    echo "PASS: until=c ran full 3-level chain {a,b,c} and excluded {d,e}"; touch "$out"
  '';
}
```
