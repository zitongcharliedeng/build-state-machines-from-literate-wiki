# ~/~ begin <<literate.lit.md/tests/todo-verb.lit.md#tests/todo-verb.nix>>[init]
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
# ~/~ end
# ~/~ begin <<literate.lit.md/tests/todo-verb.lit.md#tests/todo-verb.nix>>[1]
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
# ~/~ end
# ~/~ begin <<literate.lit.md/tests/todo-verb.lit.md#tests/todo-verb.nix>>[2]
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
# ~/~ end
# ~/~ begin <<literate.lit.md/tests/todo-verb.lit.md#tests/todo-verb.nix>>[3]
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
# ~/~ end
# ~/~ begin <<literate.lit.md/tests/todo-verb.lit.md#tests/todo-verb.nix>>[4]
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
# ~/~ end
