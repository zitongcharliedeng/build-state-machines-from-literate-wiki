# ~~  ~/~ begin <<literate.lit.mdx/tests/unit.lit.mdx#tests/unit-check.nix>>[init]
# Generated from literate.lit.mdx/tests/unit.lit.mdx — DO NOT EDIT
{ pkgs, lib, checksLib }:

let
  results = import ./unit.nix { inherit lib checksLib; };
  # Pretty-print via lib.generators.toPretty — human-readable, handles any content
  report = pkgs.writeText "unit-test-report.txt"
    (lib.generators.toPretty { multiline = true; } results);
  passed = results == [];
in
pkgs.runCommand "literate-state-machine-wiki-unit-tests" { inherit report; } ''
  if ${if passed then "true" else "false"}; then
    echo "✅ All unit tests passed"
    touch "$out"
  else
    echo "❌ Unit test failures:"
    cat "$report"
    exit 1
  fi
''
# ~~  ~/~ end
