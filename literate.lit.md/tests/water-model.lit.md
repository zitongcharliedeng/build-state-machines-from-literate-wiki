---
title: Water Model Shell-Level Tests
description: Direct tests of the renderChecksWaterModel shell script — error-mode abort, dep-failed skip, warn propagation
tags: [tests, water-model, shell, nix]
---

# Water Model Shell-Level Tests

The hook execution logic lives in two places: pure-nix helpers (`validateNeeds`, `resolveClosure`, `filterUntil` — covered in `unit.lit.md`) decide **which** hooks run; the generated shell script from `renderChecksWaterModel` decides **how** they run and propagate failures. Integration tests exercise the whole pipeline through `lsmwInit`, but only observe end-state outputs — they can't easily assert "the build failed" because a failed derivation produces no output to inspect. These shell-level tests close that gap.

The state-machine has four transitions: success → added to `_lsmw_passed`; warn-failure → still added (non-fatal); error-failure → counted in `_lsmw_errors`, dependents skip; pipeline-abort → if `_lsmw_errors > 0` at end, exit 1. Transition four is load-bearing — without it, error-mode failures silently pass and the library's safety guarantee is broken. The tests here render `renderChecksWaterModel` directly, run the bash with `set +e`, capture the exit code, and assert it matches the state machine's spec.

## Fixture builder

`mkWaterModelTest` renders one hook list, runs the resulting bash, and asserts (a) exit code, (b) marker files written by hooks, (c) log output. Skipped hooks must NOT have their marker; aborted pipelines must exit non-zero.

```{.nix file=tests/water-model.nix}
{ pkgs, lib, checksLib }:
let
  mkWaterModelTest = { name, phase ? "test", hooks, expectExit ? 0, assertions ? "" }:
    pkgs.runCommand "water-model-${name}" {
      passAsFile = [ "script" ];
      script = checksLib.renderChecksWaterModel phase hooks;
    } ''
      mkdir -p workdir && cd workdir
      set +e
      log=$(bash "$scriptPath" 2>&1)
      exit_code=$?
      set -e
      echo "--- water-model script ---"; cat "$scriptPath"
      echo "--- stdout ---"; echo "$log"
      echo "--- exit: $exit_code (expected: ${toString expectExit}) ---"
      if [ "$exit_code" != "${toString expectExit}" ]; then
        echo "FAIL: exit code $exit_code, expected ${toString expectExit}"; exit 1
      fi
      ${assertions}
      echo "PASS: water-model ${name}"; touch "$out"
    '';
in {
```

## success-single — passing hook writes marker, exits 0

The trivial baseline. One hook runs, succeeds, leaves its marker file.

```{.nix file=tests/water-model.nix}
  success-single = mkWaterModelTest {
    name = "success-single";
    hooks = [ { name = "a"; command = "echo 'ran' > a-marker"; } ];
    expectExit = 0;
    assertions = ''
      if [ ! -f a-marker ] || [ "$(cat a-marker)" != "ran" ]; then
        echo "FAIL: hook marker missing or wrong content"; exit 1
      fi
    '';
  };
```

## warn-propagates — warn failure still adds to `_lsmw_passed`

A `mode = "warn"` hook that exits non-zero must STILL be marked passed so its dependent runs. Warn means "non-fatal, keep going" — different from error, which blocks dependents.

```{.nix file=tests/water-model.nix}
  warn-propagates = mkWaterModelTest {
    name = "warn-propagates";
    hooks = [
      { name = "warn-fails"; command = "exit 1"; mode = "warn"; }
      { name = "after"; command = "echo 'propagated' > after-marker"; needs = [ "warn-fails" ]; }
    ];
    expectExit = 0;
    assertions = ''
      if [ ! -f after-marker ]; then
        echo "FAIL: dependent of warn-failed hook did not run"; exit 1
      fi
    '';
  };
```

## error-mode-skips-dependents — error blocks downstream

Default-mode hook failures do NOT add to `_lsmw_passed`. Any hook with `needs = [ "failed" ]` skips. The pipeline aborts at the end (exit 1), and the dependent's marker is NEVER written. Log emits `SKIPPED:` for the dependent.

```{.nix file=tests/water-model.nix}
  error-mode-skips-dependents = mkWaterModelTest {
    name = "error-mode-skips-dependents";
    hooks = [
      { name = "error-fails"; command = "exit 1"; }
      { name = "should-skip"; command = "echo 'SHOULD-NOT-RUN' > skip-marker"; needs = [ "error-fails" ]; }
    ];
    expectExit = 1;
    assertions = ''
      if [ -f skip-marker ]; then
        echo "FAIL: dependent of error-failed hook ran (should have skipped)"; cat skip-marker; exit 1
      fi
      if ! echo "$log" | grep -q "SKIPPED: should-skip"; then
        echo "FAIL: no SKIPPED log message for should-skip hook"; exit 1
      fi
    '';
  };
```

## error-mode-aborts-pipeline — counter forces exit 1

Independent later hooks still run (no `needs`), but the `_lsmw_errors` counter forces `exit 1` at the end. Marker files for the independent successful hooks ARE written; the pipeline-level exit code reflects the failure.

```{.nix file=tests/water-model.nix}
  error-mode-aborts-pipeline = mkWaterModelTest {
    name = "error-mode-aborts-pipeline";
    hooks = [
      { name = "a"; command = "echo ran-a > a-marker"; }
      { name = "b-errors"; command = "exit 1"; }
      { name = "c"; command = "echo ran-c > c-marker"; }
    ];
    expectExit = 1;
    assertions = ''
      if [ ! -f a-marker ]; then echo "FAIL: a hook did not run"; exit 1; fi
      if [ ! -f c-marker ]; then echo "FAIL: c hook did not run (no needs → should run independent of b's failure)"; exit 1; fi
    '';
  };
```

## multi-level-skip — error propagates transitively

A → B → C where A is error-mode-fails. B skips (needs A). C skips (needs B). Transitive skip is what makes the dependency graph honest — partial DAG execution is forbidden.

```{.nix file=tests/water-model.nix}
  multi-level-skip = mkWaterModelTest {
    name = "multi-level-skip";
    hooks = [
      { name = "a-errors"; command = "exit 1"; }
      { name = "b"; command = "echo ran-b > b-marker"; needs = [ "a-errors" ]; }
      { name = "c"; command = "echo ran-c > c-marker"; needs = [ "b" ]; }
    ];
    expectExit = 1;
    assertions = ''
      if [ -f b-marker ] || [ -f c-marker ]; then
        echo "FAIL: downstream hooks ran despite upstream error"; exit 1
      fi
      if ! echo "$log" | grep -q "SKIPPED: b"; then echo "FAIL: no SKIPPED log for b"; exit 1; fi
      if ! echo "$log" | grep -q "SKIPPED: c"; then echo "FAIL: no SKIPPED log for c"; exit 1; fi
    '';
  };
```

## empty-hooks — no hooks is a successful pipeline

The degenerate case. An empty hook list must exit 0 — no work means no failures.

```{.nix file=tests/water-model.nix}
  empty-hooks = mkWaterModelTest {
    name = "empty-hooks";
    hooks = [];
    expectExit = 0;
  };
}
```
