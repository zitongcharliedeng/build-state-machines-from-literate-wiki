# ~~  ~/~ begin <<literate.lit.mdx/tests/water-model.lit.mdx#tests/water-model.nix>>[init]
# Generated from literate.lit.mdx/tests/water-model.lit.mdx — DO NOT EDIT
{ pkgs, lib, checksLib }:

let
  # Execute a rendered water-model script and capture exit code + output.
  # `hooks` is the nix list passed to renderChecksWaterModel; `phase` is a label.
  # `expectExit` is the expected exit code (0 = success, 1 = pipeline abort).
  # `assertions` is a shell snippet run AFTER the water-model script; it can
  # inspect files created by hooks or check log content via the `$log` variable.
  mkWaterModelTest = { name, phase ? "test", hooks, expectExit ? 0, assertions ? "" }:
    pkgs.runCommand "water-model-${name}" {
      passAsFile = [ "script" ];
      script = checksLib.renderChecksWaterModel phase hooks;
    } ''
      mkdir -p workdir
      cd workdir

      # Run the generated shell script and capture exit + log
      set +e
      log=$(bash "$scriptPath" 2>&1)
      exit_code=$?
      set -e

      echo "--- water-model script ---"
      cat "$scriptPath"
      echo "--- stdout ---"
      echo "$log"
      echo "--- exit: $exit_code (expected: ${toString expectExit}) ---"

      if [ "$exit_code" != "${toString expectExit}" ]; then
        echo "FAIL: exit code $exit_code, expected ${toString expectExit}"
        exit 1
      fi

      ${assertions}

      echo "PASS: water-model ${name}"
      touch "$out"
    '';
in {
  # ── Transition 1: success path ──────────────────────────────────────
  # A single passing hook exits 0 and writes its marker.
  success-single = mkWaterModelTest {
    name = "success-single";
    hooks = [
      { name = "a"; command = "echo 'ran' > a-marker"; }
    ];
    expectExit = 0;
    assertions = ''
      if [ ! -f a-marker ] || [ "$(cat a-marker)" != "ran" ]; then
        echo "FAIL: hook marker missing or wrong content"
        exit 1
      fi
    '';
  };

  # ── Transition 2: warn-mode failure propagates to dependents ─────────
  # A warn-mode hook that fails is recorded as "passed" so its dependent runs.
  warn-propagates = mkWaterModelTest {
    name = "warn-propagates";
    hooks = [
      { name = "warn-fails"; command = "exit 1"; mode = "warn"; }
      { name = "after"; command = "echo 'propagated' > after-marker"; needs = [ "warn-fails" ]; }
    ];
    expectExit = 0;
    assertions = ''
      if [ ! -f after-marker ]; then
        echo "FAIL: dependent of warn-failed hook did not run"
        exit 1
      fi
    '';
  };

  # ── Transition 3: error-mode failure causes dependents to SKIP ───────
  # An error-mode hook failure does NOT add its name to _lsmw_passed, so
  # any dependent hook with `needs = [ "failed" ]` is skipped. The pipeline
  # aborts at the end (exit 1), but the dependent's marker is NEVER written.
  error-mode-skips-dependents = mkWaterModelTest {
    name = "error-mode-skips-dependents";
    hooks = [
      { name = "error-fails"; command = "exit 1"; }
      { name = "should-skip"; command = "echo 'SHOULD-NOT-RUN' > skip-marker"; needs = [ "error-fails" ]; }
    ];
    expectExit = 1;  # pipeline aborts due to error
    assertions = ''
      if [ -f skip-marker ]; then
        echo "FAIL: dependent of error-failed hook ran (should have skipped)"
        cat skip-marker
        exit 1
      fi
      if ! echo "$log" | grep -q "SKIPPED: should-skip"; then
        echo "FAIL: no SKIPPED log message for should-skip hook"
        exit 1
      fi
    '';
  };

  # ── Transition 4: pipeline aborts with exit 1 on any error-mode failure ─
  # Even if later hooks (without needs) would pass, the _lsmw_errors counter
  # causes the pipeline to exit 1 at the end.
  error-mode-aborts-pipeline = mkWaterModelTest {
    name = "error-mode-aborts-pipeline";
    hooks = [
      { name = "a"; command = "echo ran-a > a-marker"; }
      { name = "b-errors"; command = "exit 1"; }
      { name = "c"; command = "echo ran-c > c-marker"; }
    ];
    expectExit = 1;
    assertions = ''
      # Hooks a and c run (no needs on failed hook) but pipeline still aborts
      if [ ! -f a-marker ]; then
        echo "FAIL: a hook did not run"
        exit 1
      fi
      if [ ! -f c-marker ]; then
        echo "FAIL: c hook did not run (no needs → should run independent of b's failure)"
        exit 1
      fi
    '';
  };

  # ── Multi-level skip: failed error hook cascades through transitive needs ─
  # A → B → C where A is error-mode-fails. Both B and C should skip.
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
        echo "FAIL: downstream hooks ran despite upstream error"
        exit 1
      fi
      if ! echo "$log" | grep -q "SKIPPED: b"; then
        echo "FAIL: no SKIPPED log for b"
        exit 1
      fi
      if ! echo "$log" | grep -q "SKIPPED: c"; then
        echo "FAIL: no SKIPPED log for c"
        exit 1
      fi
    '';
  };

  # ── Empty hook list is a no-op that exits 0 ─────────────────────────
  empty-hooks = mkWaterModelTest {
    name = "empty-hooks";
    hooks = [];
    expectExit = 0;
  };
}
# ~~  ~/~ end
