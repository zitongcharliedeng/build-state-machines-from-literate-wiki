---
description: Pure nix unit tests for validateNeeds, resolveClosure, and filterUntil using nixpkgs.lib.runTests
tags: [tests, unit, nix, dag]
---

# Unit Tests — DAG Helpers

The library's hook execution model is a DAG: each `postTangle` hook declares `needs` (dependencies), and the library runs them in topological order with cycle detection and transitive closure resolution for `until`. Three helpers implement that logic — `validateNeeds` (topological order at eval time), `resolveClosure` (transitive deps for a target), `filterUntil` (filters list to target + closure). These are pure nix functions — no derivations, no IFD, no filesystem — so they're tested directly with `nixpkgs.lib.runTests`, which compares expected vs actual at eval time. Every test runs in milliseconds; the alternative (fixture-build per case) takes ~30s per test.

## Test fixture hooks

Reusable test data. `linearChain` is `deps → tsc → test → build`, a straight pipeline. `diamond` has `deps` as a common root with `tsc` and `lint` branching off, both feeding `build` (classic diamond dependency). `disjoint` has two independent chains with no shared deps. The `throws` and `byName` helpers wrap eval-time exception detection and convert hook lists to attrsets keyed by name.

```{.nix file=tests/unit.nix}
{ lib, checksLib }:
let
  linearChain = [
    { name = "deps"; command = "install"; }
    { name = "tsc"; command = "check"; needs = [ "deps" ]; }
    { name = "test"; command = "vitest"; needs = [ "tsc" ]; }
    { name = "build"; command = "vite build"; needs = [ "test" ]; }
  ];
  diamond = [
    { name = "deps"; command = "install"; }
    { name = "tsc"; command = "check"; needs = [ "deps" ]; }
    { name = "lint"; command = "eslint"; needs = [ "deps" ]; }
    { name = "build"; command = "vite build"; needs = [ "tsc" "lint" ]; }
  ];
  disjoint = [
    { name = "a1"; command = "a1"; }
    { name = "a2"; command = "a2"; needs = [ "a1" ]; }
    { name = "b1"; command = "b1"; }
    { name = "b2"; command = "b2"; needs = [ "b1" ]; }
  ];
  throws = fn:
    let result = builtins.tryEval (fn {}); in !result.success;
  byName = hooks: builtins.listToAttrs (map (h: { name = h.name; value = h; }) hooks);
in
lib.runTests {
```

## validateNeeds — topological order at eval time

`validateNeeds` accepts a hook list and returns `true` if every `needs` reference points to an earlier hook (forward references and missing names throw). Empty lists and lists without any `needs` always pass. Self-cycles (`needs = [self]`) throw, since they have no valid topological order.

```{.nix file=tests/unit.nix}
  testValidateNeeds_linearPasses = { expr = checksLib.validateNeeds linearChain; expected = true; };
  testValidateNeeds_diamondPasses = { expr = checksLib.validateNeeds diamond; expected = true; };
  testValidateNeeds_disjointPasses = { expr = checksLib.validateNeeds disjoint; expected = true; };
  testValidateNeeds_emptyPasses = { expr = checksLib.validateNeeds []; expected = true; };
  testValidateNeeds_noNeedsPasses = {
    expr = checksLib.validateNeeds [ { name = "a"; command = "a"; } { name = "b"; command = "b"; } ];
    expected = true;
  };
  testValidateNeeds_forwardReferenceThrows = {
    expr = throws (_: checksLib.validateNeeds [
      { name = "build"; command = "build"; needs = [ "deps" ]; }
      { name = "deps"; command = "install"; }
    ]);
    expected = true;
  };
  testValidateNeeds_missingHookThrows = {
    expr = throws (_: checksLib.validateNeeds [
      { name = "build"; command = "build"; needs = [ "nonexistent" ]; }
    ]);
    expected = true;
  };
  testValidateNeeds_selfNeedsThrows = {
    expr = throws (_: checksLib.validateNeeds [
      { name = "loop"; command = "loop"; needs = [ "loop" ]; }
    ]);
    expected = true;
  };
```

## resolveClosure — transitive dependency resolution

Given a `hooksByName` attrset and a target name, returns every hook reachable transitively via `needs`. Singletons return just themselves. Cycles must terminate (validateNeeds blocks at declaration, but resolveClosure is called with arbitrary maps — it must not recurse forever). Diamond and three-level chains exercise the transitive walk.

```{.nix file=tests/unit.nix}
  testResolveClosure_singleton = {
    expr = builtins.sort builtins.lessThan (checksLib.resolveClosure { hooksByName = byName linearChain; name = "deps"; });
    expected = [ "deps" ];
  };
  testResolveClosure_linearFromLeaf = {
    expr = builtins.sort builtins.lessThan (checksLib.resolveClosure { hooksByName = byName linearChain; name = "build"; });
    expected = [ "build" "deps" "test" "tsc" ];
  };
  testResolveClosure_linearFromMiddle = {
    expr = builtins.sort builtins.lessThan (checksLib.resolveClosure { hooksByName = byName linearChain; name = "test"; });
    expected = [ "deps" "test" "tsc" ];
  };
  testResolveClosure_diamondFromBuild = {
    expr = builtins.sort builtins.lessThan (checksLib.resolveClosure { hooksByName = byName diamond; name = "build"; });
    expected = [ "build" "deps" "lint" "tsc" ];
  };
  testResolveClosure_disjointIsolated = {
    expr = builtins.sort builtins.lessThan (checksLib.resolveClosure { hooksByName = byName disjoint; name = "a2"; });
    expected = [ "a1" "a2" ];
  };
  testResolveClosure_cycleTerminates = {
    expr = let
      cycleHooks = {
        a = { name = "a"; command = "a"; needs = [ "b" ]; };
        b = { name = "b"; command = "b"; needs = [ "a" ]; };
      };
      result = checksLib.resolveClosure { hooksByName = cycleHooks; name = "a"; };
    in builtins.sort builtins.lessThan result;
    expected = [ "a" "b" ];
  };
  testResolveClosure_selfCycleTerminates = {
    expr = let
      selfHooks = { loop = { name = "loop"; command = "loop"; needs = [ "loop" ]; }; };
    in checksLib.resolveClosure { hooksByName = selfHooks; name = "loop"; };
    expected = [ "loop" ];
  };
  testResolveClosure_threeLevelTransitive = {
    expr = let
      chain = [
        { name = "a"; command = "a"; }
        { name = "b"; command = "b"; needs = [ "a" ]; }
        { name = "c"; command = "c"; needs = [ "b" ]; }
        { name = "d"; command = "d"; needs = [ "c" ]; }
      ];
    in builtins.sort builtins.lessThan (checksLib.resolveClosure { hooksByName = byName chain; name = "d"; });
    expected = [ "a" "b" "c" "d" ];
  };
```

## filterUntil — public entry point

The user-facing `until` filter: returns target hook plus its full ancestor closure, in declaration order. `null` returns the input list unchanged. Singletons (root-of-chain) return just themselves. Idempotent (filtering twice equals filtering once). Preserves full hook records (command, mode, needs) — not just names. Missing target throws.

```{.nix file=tests/unit.nix}
  testFilterUntil_nullReturnsAll = { expr = checksLib.filterUntil { postTangle = linearChain; until = null; }; expected = linearChain; };
  testFilterUntil_rootReturnsSingleton = {
    expr = map (h: h.name) (checksLib.filterUntil { postTangle = linearChain; until = "deps"; });
    expected = [ "deps" ];
  };
  testFilterUntil_middlePreservesOrder = {
    expr = map (h: h.name) (checksLib.filterUntil { postTangle = linearChain; until = "test"; });
    expected = [ "deps" "tsc" "test" ];
  };
  testFilterUntil_diamondFromBuild = {
    expr = map (h: h.name) (checksLib.filterUntil { postTangle = diamond; until = "build"; });
    expected = [ "deps" "tsc" "lint" "build" ];
  };
  testFilterUntil_disjointSkipsUnrelated = {
    expr = map (h: h.name) (checksLib.filterUntil { postTangle = disjoint; until = "a2"; });
    expected = [ "a1" "a2" ];
  };
  testFilterUntil_missingHookThrows = {
    expr = throws (_: checksLib.filterUntil { postTangle = linearChain; until = "nonexistent"; });
    expected = true;
  };
  testFilterUntil_idempotent = {
    expr = let
      once = checksLib.filterUntil { postTangle = linearChain; until = "test"; };
      twice = checksLib.filterUntil { postTangle = once; until = "test"; };
    in twice;
    expected = checksLib.filterUntil { postTangle = linearChain; until = "test"; };
  };
  testFilterUntil_preservesFullHookRecords = {
    expr = let
      annotated = [
        { name = "deps"; command = "install"; mode = "error"; }
        { name = "tsc"; command = "check"; mode = "warn"; needs = [ "deps" ]; }
      ];
      filtered = checksLib.filterUntil { postTangle = annotated; until = "tsc"; };
      tsc = builtins.elemAt filtered 1;
    in { inherit (tsc) name command mode; };
    expected = { name = "tsc"; command = "check"; mode = "warn"; };
  };
  testFilterUntil_threeLevelTransitiveWithUnrelated = {
    expr = map (h: h.name) (checksLib.filterUntil {
      postTangle = [
        { name = "a"; command = "a"; }
        { name = "b"; command = "b"; needs = [ "a" ]; }
        { name = "c"; command = "c"; needs = [ "b" ]; }
        { name = "unrelated"; command = "u"; }
      ];
      until = "c";
    });
    expected = [ "a" "b" "c" ];
  };
}
```

## Running the tests

`lib.runTests` returns `[]` on success, or a list of mismatches on failure. We wrap in a derivation that fails if any test fails. The failure report is written to a store file via `pkgs.writeText` rather than interpolated into shell — interpolation is brittle when test names contain backticks/`$`/quotes, and the developer would see a bash parse error instead of the actual diff.

```{.nix file=tests/unit-check.nix}
{ pkgs, lib, checksLib }:
let
  results = import ./unit.nix { inherit lib checksLib; };
  report = pkgs.writeText "unit-test-report.txt"
    (builtins.toJSON results);
  passed = results == [];
in
pkgs.runCommand "literate-state-machine-wiki-unit-tests" { inherit report; } ''
  if [ "${if passed then "yes" else "no"}" = "yes" ]; then
    echo "PASS: all unit tests"
    touch "$out"
  else
    echo "FAIL: unit test mismatches:"
    cat "$report"
    exit 1
  fi
''
```
