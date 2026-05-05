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
      mvVerb = pkgs.writeShellApplication {
        name = "lsmw-mv";
        runtimeInputs = with pkgs; [ git findutils gnused coreutils ];
        text = ''
          set -euo pipefail
          if [ "$#" -ne 2 ]; then
            echo "usage: lsmw mv <src> <dst>" >&2
            exit 2
          fi
          src="$1"
          dst="$2"
          if [ ! -e "$src" ]; then
            echo "lsmw mv: source does not exist: $src" >&2
            exit 1
          fi
          repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
          src_abs="$(realpath -- "$src")"
          rel_old_pre="$(realpath --relative-to="$repo_root" -- "$src_abs" 2>/dev/null || echo "$src")"
          strip_md_ext() {
            local p="$1"
            p="''${p%.lit.mdx}"
            p="''${p%.md}"
            p="''${p%.mdx}"
            printf '%s' "$p"
          }
          base_old_pre="$(basename -- "$(strip_md_ext "$rel_old_pre")")"
          base_old_count=0
          while IFS= read -r -d "" f; do
            base_old_count=$((base_old_count + 1))
          done < <(find "$repo_root" \
              \( -name .git -prune \) -o \
              \( -type d ! -path "$repo_root" -exec test -e {}/.git \; -prune \) -o \
              \( -type f \( -name "$base_old_pre.md" -o -name "$base_old_pre.mdx" -o -name "$base_old_pre.lit.mdx" \) -print0 \))
          dst_dir="$(dirname -- "$dst")"
          mkdir -p "$dst_dir"
          if git ls-files --error-unmatch -- "$src" >/dev/null 2>&1; then
            git mv -- "$src" "$dst"
          else
            mv -- "$src" "$dst"
          fi
          rel_old="$rel_old_pre"
          rel_new="$(realpath --relative-to="$repo_root" -- "$dst" 2>/dev/null || echo "$dst")"
          path_old="$(strip_md_ext "$rel_old")"
          path_new="$(strip_md_ext "$rel_new")"
          base_old="$(basename -- "$path_old")"
          base_new="$(basename -- "$path_new")"
          esc() { printf '%s' "$1" | sed -e 's/[\/&.^$*[]/\\&/g'; }
          path_old_re="$(esc "$path_old")"
          base_old_re="$(esc "$base_old")"
          path_new_lit="$(printf '%s' "$path_new" | sed -e 's/[\&/]/\\&/g')"
          base_new_lit="$(printf '%s' "$base_new" | sed -e 's/[\&/]/\\&/g')"
          tmp_list="$(mktemp)"
          trap 'rm -f "$tmp_list"' EXIT
          find "$repo_root" \
              \( -name .git -prune \) -o \
              \( -type d ! -path "$repo_root" -exec test -e {}/.git \; -prune \) -o \
              \( -type f \( -name "*.md" -o -name "*.mdx" -o -name "*.lit.mdx" \) -print0 \) \
              > "$tmp_list"
          while IFS= read -r -d "" f; do
            sed -i \
              -e "s/\[\[$path_old_re\(#\([^]|]*\)\)\?\(|\([^]]*\)\)\?\]\]/[[$path_new_lit\1\3]]/g" \
              "$f"
            if [ "$base_old_count" -le 1 ] && [ "$base_old" != "$path_old" ]; then
              sed -i \
                -e "s/\[\[$base_old_re\(#\([^]|]*\)\)\?\(|\([^]]*\)\)\?\]\]/[[$base_new_lit\1\3]]/g" \
                "$f"
            fi
          done < "$tmp_list"
          if [ "$base_old_count" -gt 1 ] && [ "$base_old" != "$path_old" ]; then
            echo "lsmw mv: bare basename '$base_old' is not unique ($base_old_count files); bare-basename links left untouched" >&2
          fi
          echo "lsmw mv: $rel_old -> $rel_new"
        '';
      };
      cli = pkgs.writeShellScriptBin "literate-state-machine-wiki" ''
        set -euo pipefail
        case "''${1:-}" in
          build)
            echo "[literate-state-machine-wiki] Building literate project..."
            nix build --no-link "''${2:-.}" "''${@:3}"
            echo "[literate-state-machine-wiki] Build complete."
            ;;
          mv|rename)
            shift
            exec ${mvVerb}/bin/lsmw-mv "$@"
            ;;
          *)
            echo "literate-state-machine-wiki — opinionated literate build tool"
            echo ""
            echo "Usage:"
            echo "  literate-state-machine-wiki build [flake-ref]"
            echo "  literate-state-machine-wiki mv <src> <dst>"
            echo "  literate-state-machine-wiki rename <src> <dst>"
            exit 1
            ;;
        esac
      '';
    in {
      packages.${system} = {
        default = verified.default;
        literate-verified = verified.default;
        tangled = verified.tangled;
        web-wiki = pipeline.buildWebWiki { inherit pkgs src; litSourceDir = sourceDir; };
        inherit cli mvVerb;
      };
      devShells.${system}.default = devshellLib.mkDevShell {
        inherit pkgs;
        extraPackages = [ cli ];
      };
    };
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
  mkChecks = { pkgs, tangled, pipeline, checksLib, init, src }:
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
      probeInit = init {
        inherit pkgs src;
        sourceDir = "literate.lit.md";
        ignoreLiterateGitSubmodules = true;
      };
      probeMv = probeInit.packages.${pkgs.stdenv.hostPlatform.system}.mvVerb;
      mvRewritesWikilinks = pkgs.runCommand "mv-rewrites-wikilinks" {
        nativeBuildInputs = [ pkgs.git probeMv ];
      } ''
        export HOME=$TMPDIR
        export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
        export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
        mkdir fixture && cd fixture
        mkdir subdir
        printf '%s\n' \
          'Bare: [[uniq]].' \
          'Alias: [[uniq|click]].' \
          'Anchor: [[uniq#sec]].' \
          'Both: [[uniq#sec|click]].' \
          'Path: [[subdir/uniq]].' \
          'PathAlias: [[subdir/uniq|c]].' \
          > ref.md
        echo "x" > subdir/uniq.md
        git init -q
        git add -A
        git commit -qm init
        lsmw-mv subdir/uniq.md subdir/renamed.md
        if grep -q '\[\[uniq' ref.md; then
          echo "FAIL: bare/anchor/alias 'uniq' references not rewritten" >&2
          cat ref.md >&2
          exit 1
        fi
        if grep -q '\[\[subdir/uniq' ref.md; then
          echo "FAIL: path 'subdir/uniq' references not rewritten" >&2
          cat ref.md >&2
          exit 1
        fi
        for shape in 'renamed]]' 'renamed|click]]' 'renamed#sec]]' 'renamed#sec|click]]' 'subdir/renamed]]' 'subdir/renamed|c]]'; do
          if ! grep -qF "[[$shape" ref.md; then
            echo "FAIL: expected shape [[$shape in ref.md" >&2
            cat ref.md >&2
            exit 1
          fi
        done
        touch "$out"
      '';
    in {
      tangle-idempotent = checksLib.checkIdempotent { inherit src pkgs; };
      tangle-immutable = checksLib.checkImmutable {
        tangled = pipeline.tangle { inherit pkgs src; };
        inherit pkgs;
      };
      unit-tests = import "${tangled}/tests/unit-check.nix" { inherit pkgs lib checksLib; };
      mv-rewrites-wikilinks = mvRewritesWikilinks;
    }
    // prefixed "integration" integrationTests
    // prefixed "water-model" waterModelTests;
}
