# ~/~ begin <<flake.lit.md#lib/init.nix>>[init]
{ lib, pkgs, config, pipeline, checksLib, devshellLib }:
rec {
  init = {
    pkgs,
    src,
    system ? "x86_64-linux",
    postTangle ? [ ],
    until ? null,
    sourceDir ? "literate.lit.md",
    enforceDirectoryMatch ? false,
    ignoreLiterateGitSubmodules
  }:
    let
      verified = checksLib.makeVerify {
        inherit pkgs src sourceDir enforceDirectoryMatch;
        inherit postTangle until;
      };
# ~/~ end
# ~/~ begin <<flake.lit.md#lib/init.nix>>[1]
      name = "lsmw";
      lockFile = ".${name}.lock";
      mkVerb = verb: spec: pkgs.writeShellApplication ({ name = "${name}-${verb}"; } // spec);
      notesmdVerb = verb: upstream: mkVerb verb {
        runtimeInputs = [ pkgs.util-linux ];
        text = ''
          bin=$(command -v notesmd || command -v obsidian-cli) || exit 1
          vault=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
          exec flock "$vault/${lockFile}" "$bin" ${upstream} "$@"
        '';
      };
      mvVerb = notesmdVerb "mv" "move";
      rmVerb = notesmdVerb "rm" "delete";
      todoVerb = mkVerb "todo" {
        runtimeInputs = [ pkgs.util-linux pkgs.yq-go pkgs.ripgrep pkgs.coreutils ];
        text = ''
          vault=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
          slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//'; }
          case "''${1:-}" in
            inline)
              shift; file="$1"; title="$2"
              ( flock 200
                # Read-then-write must be atomic under the lock; concurrent calls without an existing task would otherwise clobber each other's TaskNotes/<slug>.md.
                task_file=$( { rg -lF --no-ignore --hidden "title: \"$title\"" "$vault" --glob '*.md' 2>/dev/null || true; } | head -n1)
                rel=$(realpath --relative-to="$vault" "$file"); stem=''${rel%.lit.md}; stem=''${stem%.lit.mdx}; stem=''${stem%.md}; stem=''${stem%.mdx}
                if [ -z "$task_file" ]; then
                  slug=$(slugify "$title")
                  task_file="$vault/TaskNotes/$slug.md"
                  mkdir -p "$(dirname "$task_file")"
                  [ -e "$task_file" ] || printf -- '---\ntitle: "%s"\nstatus: open\ncreated: %s\n---\n\n# %s\n' "$title" "$(date -I)" "$title" > "$task_file"
                fi
                printf '\n- [[%s]]\n' "$title" >> "$file"
                yq -i --front-matter=process ".referenced_in = ((.referenced_in // []) + [\"[[$stem]]\"] | unique)" "$task_file"
              ) 200>"$vault/${lockFile}" ;;
            *)
              bin=$(command -v mtn || command -v tn)
              exec flock "$vault/${lockFile}" "$bin" "$@" ;;
          esac
        '';
      };
      createVerb = mkVerb "create" {
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          path="$1"
          mkdir -p "$(dirname "$path")"
          [ -e "$path" ] && exit 1
          stem=''${path##*/}; stem=''${stem%.lit.md}; stem=''${stem%.md}
          printf -- '---\ntitle: "%s"\n---\n\n# %s\n\n' "$stem" "$stem" > "$path"
        '';
      };
      writeVerb = mkVerb "write" {
        runtimeInputs = [ pkgs.coreutils pkgs.ripgrep pkgs.findutils ];
        text = ''
          file="$1"
          [ -e "$file" ] || exit 1
          ''${EDITOR:-nano} "$file"
          vault=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
          unresolved=0
          while read -r link; do
            [ -z "$link" ] && continue
            base=''${link##*/}
            if [ -z "$(find "$vault" -type f \( -name "$base.md" -o -name "$base.lit.md" -o -name "$base.lit.mdx" -o -name "$base.mdx" \) -print -quit 2>/dev/null)" ]; then
              echo "warn: [[$link]] unresolved" >&2
              unresolved=$((unresolved+1))
            fi
          done < <(rg -oN '\[\[([^]|#]+)' --replace '$1' "$file" 2>/dev/null || true)
          exit 0
        '';
      };
# ~/~ end
# ~/~ begin <<flake.lit.md#lib/init.nix>>[2]
      cli = pkgs.writeShellScriptBin name ''
        set -euo pipefail
        case "''${1:-}" in
          build) nix build --no-link "''${2:-.}" "''${@:3}" ;;
          mv|rename)
            shift
            exec ${mvVerb}/bin/${name}-mv "$@"
            ;;
          rm)
            shift
            exec ${rmVerb}/bin/${name}-rm "$@"
            ;;
          todo)
            shift
            exec ${todoVerb}/bin/${name}-todo "$@"
            ;;
          create)
            shift
            exec ${createVerb}/bin/${name}-create "$@"
            ;;
          write)
            shift
            exec ${writeVerb}/bin/${name}-write "$@"
            ;;
          *) exit 1 ;;
        esac
      '';
    in {
      packages.${system} = {
        default = verified.default;
        literate-verified = verified.default;
        tangled = verified.tangled;
        web-wiki = pipeline.buildWebWiki { inherit pkgs src; litSourceDir = sourceDir; };
        inherit cli mvVerb rmVerb todoVerb createVerb writeVerb;
      };
      devShells.${system}.default = devshellLib.mkDevShell {
        inherit pkgs;
        extraPackages = [ cli ];
      };
    };
# ~/~ end
# ~/~ begin <<flake.lit.md#lib/init.nix>>[3]
  tangleAndRead = { pkgs, src, file }: builtins.readFile "${
    pkgs.runCommand "tangle-for-eval" {
      nativeBuildInputs = [ (config.entangledFor pkgs) (config.pythonFor pkgs) ];
    } ''
      cp -r ${src}/. build/
      chmod -R u+w build
      cd build
      cat > entangled.toml <<'TOML'
${config.defaultEntangledToml}
TOML
      entangled tangle --force 2>/dev/null
      ${pipeline.stripEntangledMarkers}
      mkdir -p $out
      cp ${file} $out/ 2>/dev/null || (echo "ERROR: ${file} not found after tangle" && exit 1)
    ''
  }/${file}";
# ~/~ end
# ~/~ begin <<flake.lit.md#lib/init.nix>>[4]
  mkChecks = { pkgs, tangled, pipeline, checksLib, init, todoVerb, writeVerb, src }:
    let
      prefixed = prefix: lib.mapAttrs' (name: value:
        lib.nameValuePair "${prefix}-${name}" value);
      integrationTests = import "${tangled}/tests/integration.nix" {
        inherit pkgs lib;
        lsmwInit = init;
      };
      waterModelTests = import "${tangled}/tests/water-model.nix" {
        inherit pkgs lib checksLib;
      };
      todoVerbTests = import "${tangled}/tests/todo-verb.nix" {
        inherit pkgs lib todoVerb writeVerb;
      };
    in {
      tangle-idempotent = checksLib.checkIdempotent { inherit src pkgs; };
      tangle-immutable = checksLib.checkImmutable {
        tangled = pipeline.tangle { inherit pkgs src; };
        inherit pkgs;
      };
      unit-tests = import "${tangled}/tests/unit-check.nix" { inherit pkgs lib checksLib; };
    }
    // prefixed "integration" integrationTests
    // prefixed "water-model" waterModelTests
    // prefixed "todo" todoVerbTests;
}
# ~/~ end
