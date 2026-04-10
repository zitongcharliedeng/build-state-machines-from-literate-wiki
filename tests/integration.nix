# ~~  ~/~ begin <<literate.lit.mdx/tests/integration.lit.mdx#tests/integration.nix>>[init]
# Generated from literate.lit.mdx/tests/integration.lit.mdx — DO NOT EDIT
{ pkgs, lib, lsmwInit }:

let
  # Minimal valid literate source — enough prose and one tangled file.
  minimalLit = ''
    ---
    title: Hello
    description: minimal fixture for integration tests
    tags: [test]
    ---

    # Hello

    This is a minimal literate file with enough prose to pass the default prose density check. The library requires at least three lines of prose before any code block, and this paragraph satisfies that constraint.

    ```{.sh file=hello.sh}
    #!/bin/sh
    echo "hello from tangled script"
    ```
  '';

  # Build a fixture source tree as a derivation containing literate.lit.mdx/hello.lit.mdx
  mkFixtureTree = { name, litContent }:
    pkgs.runCommand "fixture-${name}-tree" { } ''
      mkdir -p $out/literate.lit.mdx
      cat > $out/literate.lit.mdx/hello.lit.mdx <<'LIT_EOF'
      ${litContent}
      LIT_EOF
    '';

  # Run lsmwInit on a fixture and return the default package (post-tangled tree).
  # Wraps in tryEval so we can assert failure modes.
  mkFixture = { name, litContent, postTangle ? [], until ? null, minProseLines ? 3, maxBlockLength ? 50 }:
    let
      tree = mkFixtureTree { inherit name litContent; };
      outputs = lsmwInit {
        inherit pkgs postTangle until minProseLines maxBlockLength;
        src = tree;
        sourceDir = "literate.lit.mdx";
      };
    in outputs.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Assert that a derivation built and produced an expected file.
  assertBuilds = { name, fixture, expectFile ? "hello.sh" }:
    pkgs.runCommand "assert-builds-${name}" { } ''
      if [ ! -f ${fixture}/${expectFile} ]; then
        echo "FAIL: ${expectFile} not found in ${name} fixture output"
        ls -la ${fixture}
        exit 1
      fi
      echo "PASS: ${name} built and produced ${expectFile}"
      touch "$out"
    '';

  # Assert that a fixture's postTangled output contains a marker from a specific hook.
  assertHookRan = { name, fixture, marker, markerFile ? "hook-marker" }:
    pkgs.runCommand "assert-hook-ran-${name}" { } ''
      if [ ! -f ${fixture}/${markerFile} ]; then
        echo "FAIL: ${markerFile} not present — hook did not run for ${name}"
        exit 1
      fi
      if ! grep -q "${marker}" ${fixture}/${markerFile}; then
        echo "FAIL: marker '${marker}' not found in ${markerFile} for ${name}"
        cat ${fixture}/${markerFile}
        exit 1
      fi
      echo "PASS: ${name} hook ran and wrote marker '${marker}'"
      touch "$out"
    '';

in {
  # ── Minimal success path ────────────────────────────────────────────
  # Proves the base pipeline works: pre-check → tangle → package output.
  minimal = assertBuilds {
    name = "minimal";
    fixture = mkFixture {
      name = "minimal";
      litContent = minimalLit;
    };
  };

  # ── postTangle hook in success path ─────────────────────────────────
  # A passing hook runs, writes a marker, and we assert it appears.
  post-tangle-success = assertHookRan {
    name = "post-tangle-success";
    fixture = mkFixture {
      name = "post-tangle-success";
      litContent = minimalLit;
      postTangle = [{
        name = "write-marker";
        command = "echo 'hook-ran' > hook-marker";
      }];
    };
    marker = "hook-ran";
  };

  # ── Warn-mode hook failure does NOT abort build ─────────────────────
  # A hook with mode = "warn" that fails must still produce a built package.
  post-tangle-warn-mode = assertBuilds {
    name = "post-tangle-warn-mode";
    fixture = mkFixture {
      name = "post-tangle-warn-mode";
      litContent = minimalLit;
      postTangle = [
        {
          name = "failing-warn";
          command = "exit 1";
          mode = "warn";
        }
        {
          name = "after-warn";
          command = "echo 'still-ran' > hook-marker";
        }
      ];
    };
    expectFile = "hook-marker";
  };

  # ── Warn-mode failure PROPAGATES to dependents ──────────────────────
  # A warn-mode hook that fails is recorded as "passed" in the water model
  # ($_lsmw_passed += name), so dependents CAN still run. Warn mode means
  # "non-fatal" — the pipeline continues, and downstream hooks proceed.
  # Contrast with error mode, which does NOT add to passed, causing
  # dependents to skip AND aborting the pipeline at the end.
  needs-warn-propagates = assertHookRan {
    name = "needs-warn-propagates";
    fixture = mkFixture {
      name = "needs-warn-propagates";
      litContent = minimalLit;
      postTangle = [
        {
          name = "warn-fails";
          command = "exit 1";
          mode = "warn";
        }
        {
          name = "after-warn";
          command = "echo 'propagated' > warn-propagate-marker";
          needs = [ "warn-fails" ];
        }
      ];
    };
    marker = "propagated";
    markerFile = "warn-propagate-marker";
  };

  # ── Needs in sequence when all pass ─────────────────────────────────
  # Hooks with needs must run in declared order, and all markers appear.
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
      echo "FAIL: expected chain 'a b c', got:"
      echo "$content"
      exit 1
    fi
    echo "PASS: needs ran in order a → b → c"
    touch "$out"
  '';

  # ── until filter runs target + its transitive deps (3 levels deep) ──
  # Hooks: a → b → c (chain), plus d → e (unrelated branch). until = "c"
  # must run {a, b, c} and skip {d, e}. This proves transitive resolution
  # actually walks the full chain, not just direct deps.
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
      if [ ! -f $fixture/$f ]; then
        echo "FAIL: $f missing — until=c should include full chain {a,b,c}"
        exit 1
      fi
    done
    for f in d-marker e-marker; do
      if [ -f $fixture/$f ]; then
        echo "FAIL: $f present — until=c should exclude unrelated {d,e}"
        exit 1
      fi
    done
    echo "PASS: until=c ran full 3-level chain {a,b,c} and excluded {d,e}"
    touch "$out"
  '';
}
# ~~  ~/~ end
