---
title: Verb Tests — End-to-End
description: Fixture-based tests for `lsmw todo inline` (bidirectional `referenced_in:` primitive, path-form wikilink collision safety) and `lsmw write` (wikilink validation)
tags: [tests, lsmw, fixture]
---

# Verb Tests — End-to-End

`lsmw todo inline` closes a real upstream gap: notesmd-cli and mtn both write standalone task files with no notion of where the task is referenced from. The wrapper appends `- [[<title>]]` to a target file AND records the target's path-form wikilink in the task's `referenced_in:` frontmatter, both under a single flock — turning O(N) backlink lookup into O(1) frontmatter read. `lsmw write` opens `$EDITOR` then validates `[[wikilinks]]` post-save, warning on unresolved targets.

`mkVaultTest` writes a tiny vault, runs a command, asserts. `git init` makes the wrapper's `git rev-parse --show-toplevel` resolve to the fixture root.

```{.nix file=tests/todo-verb.nix}
{ pkgs, lib, todoVerb, writeVerb }:
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

## Test 1 — bullet lands in target

Basic guarantee: `lsmw todo inline note.md "Do this daily"` writes `- [[Do this daily]]` to `note.md`.

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

## Test 2 — bidirectional link primitive lands

After `inline`, the task file's `referenced_in:` contains the target's path-form wikilink `[[note]]`. Agent reading the task answers "where am I inlined?" in O(1).

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

## Test 3 — reruns dedupe

Inlining the same task into the same file twice leaves exactly one `referenced_in:` entry. yq's `unique` is the dedup mechanism.

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

## Test 4 — basename collisions use path-form

Two files at `projects/foo.md` and `archive/foo.md` share basename. Wrapper stores path-form `[[projects/foo]]` and `[[archive/foo]]` so back-references stay unambiguous and rename-safe.

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

  write-warns-unresolved-wikilinks = mkVaultTest {
    name = "write-warns-unresolved-wikilinks";
    files = {
      "note.md" = "# Note\n\n[[real]] and [[missing]]\n";
      "real.md" = "# Real\n";
    };
    run = ''EDITOR=true ${writeVerb}/bin/lsmw-write note.md 2> stderr.log || true'';
    assertions = ''
      grep -q "missing" stderr.log || { echo FAIL: no warn for unresolved [[missing]]; cat stderr.log; exit 1; }
    '';
  };
}
```

`mkChecks` mounts these via `prefixed "todo" todoVerbTests`; failed assertions abort the build with captured fixture content.
