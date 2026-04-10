# ~~  ~/~ begin <<literate.lit.mdx/tests/unit.lit.mdx#tests/unit.nix>>[init]
# Generated from literate.lit.mdx/tests/unit.lit.mdx — DO NOT EDIT
{ lib, checksLib }:

let
  # Linear: deps → tsc → test → build
  linearChain = [
    { name = "deps"; command = "install"; }
    { name = "tsc"; command = "check"; needs = [ "deps" ]; }
    { name = "test"; command = "vitest"; needs = [ "tsc" ]; }
    { name = "build"; command = "vite build"; needs = [ "test" ]; }
  ];

  # Diamond: deps → {tsc, lint} → build
  diamond = [
    { name = "deps"; command = "install"; }
    { name = "tsc"; command = "check"; needs = [ "deps" ]; }
    { name = "lint"; command = "eslint"; needs = [ "deps" ]; }
    { name = "build"; command = "vite build"; needs = [ "tsc" "lint" ]; }
  ];

  # Disjoint: two unrelated chains
  disjoint = [
    { name = "a1"; command = "a1"; }
    { name = "a2"; command = "a2"; needs = [ "a1" ]; }
    { name = "b1"; command = "b1"; }
    { name = "b2"; command = "b2"; needs = [ "b1" ]; }
  ];

  # Helper: does `fn` throw? (catches via tryEval)
  throws = fn:
    let result = builtins.tryEval (fn {}); in !result.success;

  # Helper: convert list to attrset for hooksByName (mirrors makeVerify internals)
  byName = hooks: builtins.listToAttrs (map (h: { name = h.name; value = h; }) hooks);

in
lib.runTests {
  # validateNeeds: topological order enforcement
  testValidateNeeds_linearPasses = {
    expr = checksLib.validateNeeds linearChain;
    expected = true;
  };

  testValidateNeeds_diamondPasses = {
    expr = checksLib.validateNeeds diamond;
    expected = true;
  };

  testValidateNeeds_disjointPasses = {
    expr = checksLib.validateNeeds disjoint;
    expected = true;
  };

  testValidateNeeds_emptyPasses = {
    expr = checksLib.validateNeeds [];
    expected = true;
  };

  testValidateNeeds_noNeedsPasses = {
    expr = checksLib.validateNeeds [
      { name = "a"; command = "a"; }
      { name = "b"; command = "b"; }
    ];
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

  # resolveClosure: transitive dependency resolution
  testResolveClosure_singleton = {
    expr = builtins.sort builtins.lessThan (checksLib.resolveClosure {
      hooksByName = byName linearChain;
      name = "deps";
    });
    expected = [ "deps" ];
  };

  testResolveClosure_linearFromLeaf = {
    expr = builtins.sort builtins.lessThan (checksLib.resolveClosure {
      hooksByName = byName linearChain;
      name = "build";
    });
    expected = [ "build" "deps" "test" "tsc" ];
  };

  testResolveClosure_linearFromMiddle = {
    expr = builtins.sort builtins.lessThan (checksLib.resolveClosure {
      hooksByName = byName linearChain;
      name = "test";
    });
    expected = [ "deps" "test" "tsc" ];
  };

  testResolveClosure_diamondFromBuild = {
    expr = builtins.sort builtins.lessThan (checksLib.resolveClosure {
      hooksByName = byName diamond;
      name = "build";
    });
    expected = [ "build" "deps" "lint" "tsc" ];
  };

  testResolveClosure_disjointIsolated = {
    expr = builtins.sort builtins.lessThan (checksLib.resolveClosure {
      hooksByName = byName disjoint;
      name = "a2";
    });
    expected = [ "a1" "a2" ];
  };

  # resolveClosure cycle handling — even though validateNeeds blocks cycles at
  # declaration time, resolveClosure is called with arbitrary hooksByName maps
  # and must terminate on cycles rather than recursing forever. Construct a
  # direct a→b→a cycle and assert the closure is finite.
  testResolveClosure_cycleTerminates = {
    expr = let
      cycleHooks = {
        a = { name = "a"; command = "a"; needs = [ "b" ]; };
        b = { name = "b"; command = "b"; needs = [ "a" ]; };
      };
      result = checksLib.resolveClosure {
        hooksByName = cycleHooks;
        name = "a";
      };
    in builtins.sort builtins.lessThan result;
    expected = [ "a" "b" ];
  };

  testResolveClosure_selfCycleTerminates = {
    expr = let
      selfHooks = {
        loop = { name = "loop"; command = "loop"; needs = [ "loop" ]; };
      };
    in checksLib.resolveClosure {
      hooksByName = selfHooks;
      name = "loop";
    };
    expected = [ "loop" ];
  };

  # Transitive chain — A→B→C→D, closure of D must include all four.
  testResolveClosure_threeLevelTransitive = {
    expr = let
      chain = [
        { name = "a"; command = "a"; }
        { name = "b"; command = "b"; needs = [ "a" ]; }
        { name = "c"; command = "c"; needs = [ "b" ]; }
        { name = "d"; command = "d"; needs = [ "c" ]; }
      ];
    in builtins.sort builtins.lessThan (checksLib.resolveClosure {
      hooksByName = byName chain;
      name = "d";
    });
    expected = [ "a" "b" "c" "d" ];
  };

  # filterUntil: the public entry point
  testFilterUntil_nullReturnsAll = {
    expr = checksLib.filterUntil { postTangle = linearChain; until = null; };
    expected = linearChain;
  };

  # "deps" is the root of linearChain (no needs) — filtering until it returns
  # just the root with no ancestors.
  testFilterUntil_rootReturnsSingleton = {
    expr = map (h: h.name) (checksLib.filterUntil {
      postTangle = linearChain;
      until = "deps";
    });
    expected = [ "deps" ];
  };

  testFilterUntil_middlePreservesOrder = {
    expr = map (h: h.name) (checksLib.filterUntil {
      postTangle = linearChain;
      until = "test";
    });
    expected = [ "deps" "tsc" "test" ];
  };

  testFilterUntil_diamondFromBuild = {
    expr = map (h: h.name) (checksLib.filterUntil {
      postTangle = diamond;
      until = "build";
    });
    expected = [ "deps" "tsc" "lint" "build" ];
  };

  testFilterUntil_disjointSkipsUnrelated = {
    expr = map (h: h.name) (checksLib.filterUntil {
      postTangle = disjoint;
      until = "a2";
    });
    expected = [ "a1" "a2" ];
  };

  testFilterUntil_missingHookThrows = {
    expr = throws (_: checksLib.filterUntil {
      postTangle = linearChain;
      until = "nonexistent";
    });
    expected = true;
  };

  # Idempotence: applying filterUntil twice with the same target equals once.
  # Proves the filter is a pure function over hook lists, not a side-effect.
  testFilterUntil_idempotent = {
    expr = let
      once = checksLib.filterUntil { postTangle = linearChain; until = "test"; };
      twice = checksLib.filterUntil { postTangle = once; until = "test"; };
    in twice;
    expected = checksLib.filterUntil { postTangle = linearChain; until = "test"; };
  };

  # filterUntil must preserve ALL hook attributes (command, mode, etc), not
  # just the name field. A refactor that accidentally reconstructs hooks from
  # names-only would break this.
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

  # Three-level transitive chain through filterUntil with an unrelated branch.
  # Proves filterUntil resolves the full ancestor set AND excludes unrelated hooks.
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
# ~~  ~/~ end
