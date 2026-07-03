---
description: The pipeline's execution semantics defined once as a state machine; every test derived from it — scenarios are data, expectations are computed, never hand-written
tags: [tests, state-machine, water-model, dag]
---

# Pipeline Machine — the library's semantics as one state machine

Every hook in a pipeline run occupies exactly one status: `ok`, `warn`, `fail`, or `skipped`. The whole water model is one transition function: a hook whose needs contain any `fail` or `skipped` becomes `skipped` without running; a hook that runs and fails becomes `warn` when its mode is warn (non-fatal, dependents proceed) and `fail` otherwise; a run with any `fail` exits 1. That paragraph is the entire semantics of `renderChecksWaterModel` — so it is written below as the `step` function, and all tests are derived from it.

Tests here are *machine-checked instances*: a scenario is only a DAG of named outcomes. The expected status of every hook and the expected exit code are computed by folding `step` over the DAG — the test author never writes an expectation by hand, so the spec cannot drift from the assertions. The generated bash from `renderChecksWaterModel` is then executed against the same scenario and must agree with the machine.

```{.nix file=tests/pipeline-machine.nix}
{ pkgs, lib, checksLib }:
let
  step = { outcome, mode ? "error" }: needsStatuses:
    if lib.any (s: s == "fail" || s == "skipped") needsStatuses then "skipped"
    else if outcome == "fail" && mode == "warn" then "warn"
    else outcome;

  run = hooks: lib.foldl
    (acc: h: acc // {
      ${h.name} = step { inherit (h) outcome; mode = h.mode or "error"; }
        (map (n: acc.${n}) (h.needs or [ ]));
    }) { } hooks;

  exitOf = statuses:
    if lib.any (s: s == "fail") (lib.attrValues statuses) then "1" else "0";
```

A scenario hook with `outcome = "ok"` writes a marker file when it truly runs; `outcome = "fail"` exits 1. The marker is how the machine's prediction is checked against reality: predicted `ok` means the marker must exist, predicted `skipped` means it must not and a `SKIPPED:` line must appear in the log.

```{.nix file=tests/pipeline-machine.nix}
  toHook = h: {
    inherit (h) name;
    command = if h.outcome == "fail" then "exit 1"
              else "echo ran > ${h.name}-marker";
  } // lib.optionalAttrs (h ? mode) { inherit (h) mode; }
    // lib.optionalAttrs (h ? needs) { inherit (h) needs; };

  assertFor = expected: h:
    if expected.${h.name} == "ok" then ''
      [ -f ${h.name}-marker ] || { echo "FAIL: ${h.name} predicted ok, never ran"; exit 1; }
    '' else if expected.${h.name} == "skipped" then ''
      [ ! -f ${h.name}-marker ] || { echo "FAIL: ${h.name} predicted skipped, but ran"; exit 1; }
      echo "$log" | grep -q "SKIPPED: ${h.name}" || { echo "FAIL: no SKIPPED log for ${h.name}"; exit 1; }
    '' else "";
```

The runner renders the real water-model bash for the scenario, executes it, and compares exit code plus per-hook evidence against the machine's fold. One generator, all scenarios.

```{.nix file=tests/pipeline-machine.nix}
  mkMachineTest = { name, hooks }:
    let expected = run hooks;
    in pkgs.runCommand "pipeline-machine-${name}" {
      passAsFile = [ "script" ];
      script = checksLib.renderChecksWaterModel "test" (map toHook hooks);
    } ''
      mkdir -p workdir && cd workdir
      set +e
      log=$(bash "$scriptPath" 2>&1)
      exit_code=$?
      set -e
      echo "$log"
      if [ "$exit_code" != "${exitOf expected}" ]; then
        echo "FAIL: exit $exit_code, machine predicts ${exitOf expected}"; exit 1
      fi
      ${lib.concatMapStrings (assertFor expected) hooks}
      echo "PASS: ${name}"; touch "$out"
    '';
```

The scenario table. Adding a row is adding a test; the machine supplies the expectations. These rows cover every transition: plain success, warn propagation through a dependent, error blocking a dependent, error aborting while independents still run, transitive skip through a chain, a diamond with one warn leg, and the empty degenerate case.

```{.nix file=tests/pipeline-machine.nix}
  scenarios = [
    { name = "success-single"; hooks = [ { name = "a"; outcome = "ok"; } ]; }
    { name = "warn-propagates"; hooks = [
        { name = "w"; outcome = "fail"; mode = "warn"; }
        { name = "after"; outcome = "ok"; needs = [ "w" ]; } ]; }
    { name = "error-skips-dependent"; hooks = [
        { name = "e"; outcome = "fail"; }
        { name = "dep"; outcome = "ok"; needs = [ "e" ]; } ]; }
    { name = "error-aborts-independents-run"; hooks = [
        { name = "a"; outcome = "ok"; }
        { name = "e"; outcome = "fail"; }
        { name = "c"; outcome = "ok"; } ]; }
    { name = "multi-level-skip"; hooks = [
        { name = "e"; outcome = "fail"; }
        { name = "b"; outcome = "ok"; needs = [ "e" ]; }
        { name = "c"; outcome = "ok"; needs = [ "b" ]; } ]; }
    { name = "diamond-warn-leg"; hooks = [
        { name = "deps"; outcome = "ok"; }
        { name = "tsc"; outcome = "ok"; needs = [ "deps" ]; }
        { name = "lint"; outcome = "fail"; mode = "warn"; needs = [ "deps" ]; }
        { name = "build"; outcome = "ok"; needs = [ "tsc" "lint" ]; } ]; }
    { name = "empty"; hooks = [ ]; }
  ];
```

Two static aspects of the machine live at eval time, not in bash. Illegal machine definitions must be rejected before anything runs: a `needs` naming a later hook, a missing hook, or a self-cycle has no valid execution order. And `until` truncates the machine to a target plus its ancestor closure, in declaration order. Both are observable semantics, tested as data through the public `validateNeeds`/`filterUntil` surface.

```{.nix file=tests/pipeline-machine.nix}
  throws = fn: !(builtins.tryEval (fn { })).success;

  evalResults = lib.runTests {
    testRejectsForwardNeed = { expr = throws (_: checksLib.validateNeeds [
      { name = "b"; command = "b"; needs = [ "a" ]; }
      { name = "a"; command = "a"; } ]); expected = true; };
    testRejectsMissingNeed = { expr = throws (_: checksLib.validateNeeds [
      { name = "b"; command = "b"; needs = [ "ghost" ]; } ]); expected = true; };
    testRejectsSelfCycle = { expr = throws (_: checksLib.validateNeeds [
      { name = "loop"; command = "l"; needs = [ "loop" ]; } ]); expected = true; };
    testUntilTruncatesToClosure = {
      expr = map (h: h.name) (checksLib.filterUntil {
        postTangle = [
          { name = "a"; command = "a"; }
          { name = "b"; command = "b"; needs = [ "a" ]; }
          { name = "c"; command = "c"; needs = [ "b" ]; }
          { name = "unrelated"; command = "u"; } ];
        until = "c"; });
      expected = [ "a" "b" "c" ];
    };
    testUntilNullKeepsAll = {
      expr = map (h: h.name) (checksLib.filterUntil {
        postTangle = [ { name = "a"; command = "a"; } ]; until = null; });
      expected = [ "a" ];
    };
    testUntilMissingTargetThrows = { expr = throws (_: checksLib.filterUntil {
      postTangle = [ { name = "a"; command = "a"; } ]; until = "ghost"; }); expected = true; };
  };

  evalGate = pkgs.runCommand "pipeline-machine-eval" {
    report = builtins.toJSON evalResults;
  } ''
    if [ "${if evalResults == [ ] then "yes" else "no"}" = "yes" ]; then
      echo "PASS: machine eval semantics"; touch "$out"
    else
      echo "FAIL:"; echo "$report"; exit 1
    fi
  '';
in
  { eval-semantics = evalGate; }
  // builtins.listToAttrs (map (s: { inherit (s) name; value = mkMachineTest s; }) scenarios)
```
