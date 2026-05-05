---
title: Todo Verb Tests — End-to-End
description: Fixture-based tests for `lsmw todo inline` — bidirectional `referenced_in:` primitive and path-form wikilink collision safety
tags: [tests, todo, lsmw, fixture]
---

# Todo Verb Tests — End-to-End

`lsmw todo inline <file> '<title>'` closes a real upstream gap. notesmd-cli writes only standalone task files; mtn (mdbase-tasknotes) likewise creates task-per-file with no notion of where the task is referenced from. An agent reading a task file in either ecosystem cannot tell which vault files inline it without an O(N) grep over the whole vault. The wrapper's primitive — append the bullet `- [[<title>]]` AND record the target's path-form wikilink in the task's `referenced_in:` frontmatter, both under a single flock — turns that O(N) lookup into an O(1) frontmatter read.

Three behaviours have to hold together for the primitive to be honest. The bullet must land. The back-reference must land. Reruns must dedupe. Each is one test below; each is its own derivation that exists or doesn't, and the build is the test runner.

## Test fixture builder

`mkVaultTest` writes a tiny vault, runs a command against it, and asserts. The vault gets an empty `git init` because the wrapper resolves vault root via `git rev-parse --show-toplevel`; without a repo the lock file would land in `pwd` and the assertions still hold but the realism would be off. Fixture files are passed as a Nix attrset of `path → content`; the body of each file is heredoc-piped at build time.

```{.nix file=tests/todo-verb.nix}
{ pkgs, lib, todoVerb }:
let
  mkVaultTest = { name, files, run, assertions }:
    pkgs.runCommand "todo-verb-${name}" {
      nativeBuildInputs = [ pkgs.git ];
    } ''
      mkdir -p vault && cd vault
      git init -q
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: content: ''
        mkdir -p "$(dirname "${path}")" 2>/dev/null || true
        cat > "${path}" <<'__LSMW_EOF__'
${content}
__LSMW_EOF__
      '') files)}
      ${run}
      ${assertions}
      touch "$out"
    '';
in {
```

## Test 1 — the bullet lands in the target file

The most basic guarantee: `lsmw todo inline note.md "Do this daily"` writes `- [[Do this daily]]` to `note.md`. If this fails the wrapper isn't doing what its name promises, regardless of whatever frontmatter side-effects are working.

```{.nix file=tests/todo-verb.nix}
  inline-creates-bullet = mkVaultTest {
    name = "inline-creates-bullet";
    files = {
      "Do this daily.md" = "---\ntitle: \"Do this daily\"\n---\n";
      "note.md" = "# Note\n";
    };
    run = ''${todoVerb}/bin/lsmw-todo inline note.md "Do this daily"'';
    assertions = ''
      grep -q '^- \[\[Do this daily\]\]$' note.md \
        || { echo FAIL: bullet not appended; cat note.md; exit 1; }
    '';
  };
```

## Test 2 — the bidirectional link primitive lands

The whole reason this verb exists. After `inline note.md "Do this daily"`, the task file `Do this daily.md` must contain a `referenced_in:` frontmatter list whose value is the path-form wikilink `[[note]]`. An agent reading the task can now answer "where am I inlined?" without scanning the vault.

```{.nix file=tests/todo-verb.nix}
  inline-writes-referenced-in = mkVaultTest {
    name = "inline-writes-referenced-in";
    files = {
      "Do this daily.md" = "---\ntitle: \"Do this daily\"\n---\n";
      "note.md" = "# Note\n";
    };
    run = ''${todoVerb}/bin/lsmw-todo inline note.md "Do this daily"'';
    assertions = ''
      grep -q "referenced_in:" "Do this daily.md" \
        || { echo FAIL: referenced_in missing; cat "Do this daily.md"; exit 1; }
      grep -qF "[[note]]" "Do this daily.md" \
        || { echo FAIL: wikilink form missing; cat "Do this daily.md"; exit 1; }
    '';
  };
```

## Test 3 — reruns are idempotent

Inlining the same task into the same file twice must leave exactly one `referenced_in:` entry, not two. yq's `unique` is the dedup mechanism; this test is the only thing that proves the dedup is wired up correctly. Without it, every rerun would silently bloat the task file's frontmatter.

```{.nix file=tests/todo-verb.nix}
  inline-deduplicates-on-rerun = mkVaultTest {
    name = "inline-deduplicates-on-rerun";
    files = {
      "Do this daily.md" = "---\ntitle: \"Do this daily\"\n---\n";
      "note.md" = "# Note\n";
    };
    run = ''
      ${todoVerb}/bin/lsmw-todo inline note.md "Do this daily"
      ${todoVerb}/bin/lsmw-todo inline note.md "Do this daily"
    '';
    assertions = ''
      count=$(grep -cF "[[note]]" "Do this daily.md")
      [ "$count" = "1" ] \
        || { echo FAIL: expected 1 referenced_in entry, got $count; cat "Do this daily.md"; exit 1; }
    '';
  };
```

## Test 4 — basename collisions resolve via path-form

Two files at `projects/foo.md` and `archive/foo.md` share basename `foo`. Obsidian's `[[foo]]` resolves ambiguously; the wrapper must store the path-form `[[projects/foo]]` and `[[archive/foo]]` instead. Without this, the back-reference would point to whichever file Obsidian picks "closest" — non-deterministic at read time, and lossy on rename.

```{.nix file=tests/todo-verb.nix}
  inline-uses-path-form-on-collision = mkVaultTest {
    name = "inline-uses-path-form-on-collision";
    files = {
      "Do this daily.md" = "---\ntitle: \"Do this daily\"\n---\n";
      "projects/foo.md" = "# Projects Foo\n";
      "archive/foo.md" = "# Archive Foo\n";
    };
    run = ''
      ${todoVerb}/bin/lsmw-todo inline projects/foo.md "Do this daily"
      ${todoVerb}/bin/lsmw-todo inline archive/foo.md "Do this daily"
    '';
    assertions = ''
      grep -qF "[[projects/foo]]" "Do this daily.md" \
        || { echo FAIL: projects/foo missing; cat "Do this daily.md"; exit 1; }
      grep -qF "[[archive/foo]]" "Do this daily.md" \
        || { echo FAIL: archive/foo missing; cat "Do this daily.md"; exit 1; }
    '';
  };
}
```

A failed assertion aborts the build with the captured file content. `mkChecks` mounts these via `prefixed "todo" todoVerbTests` so they run alongside integration and water-model tests under one `nix flake check`.
