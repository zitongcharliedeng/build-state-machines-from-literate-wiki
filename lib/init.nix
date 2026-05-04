{ lib, pkgs, config, pipeline, checksLib, devshellLib }:
rec {
  init = {
    pkgs,
    src,
    system ? "x86_64-linux",
    postTangle ? [ ],
    until ? null,
    sourceDir ? "literate.lit.mdx",
    enforceDirectoryMatch ? false,
    ignoreLiterateGitSubmodules
  }:
    let
      verified = checksLib.makeVerify {
        inherit pkgs src sourceDir enforceDirectoryMatch;
        inherit postTangle until;
      };
      cli = pkgs.writeShellScriptBin "literate-state-machine-wiki" ''
        set -euo pipefail
        case "''${1:-}" in
          build)
            echo "[literate-state-machine-wiki] Building literate project..."
            nix build --no-link "''${2:-.}" "''${@:3}"
            echo "[literate-state-machine-wiki] Build complete."
            ;;
          *)
            echo "literate-state-machine-wiki — opinionated literate build tool"
            echo ""
            echo "Usage: literate-state-machine-wiki build [flake-ref]"
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
        inherit cli;
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
    in {
      tangle-idempotent = checksLib.checkIdempotent { inherit src pkgs; };
      tangle-immutable = checksLib.checkImmutable {
        tangled = pipeline.tangle { inherit pkgs src; };
        inherit pkgs;
      };
      unit-tests = import "${tangled}/tests/unit-check.nix" { inherit pkgs lib checksLib; };
    }
    // prefixed "integration" integrationTests
    // prefixed "water-model" waterModelTests;
}
{ lib, pkgs, config, pipeline, checksLib, devshellLib }:
rec {
  # Public consumer API: wire src + hooks into a full package set.
  init = {
    pkgs,
    src,
    system ? "x86_64-linux",
    postTangle ? [ ],
    until ? null,
    sourceDir ? "literate.lit.mdx",
    enforceDirectoryMatch ? false,
    ignoreLiterateGitSubmodules
  }:
    let
      verified = checksLib.makeVerify {
        inherit pkgs src sourceDir enforceDirectoryMatch;
        inherit postTangle until;
      };
      cli = pkgs.writeShellScriptBin "literate-state-machine-wiki" ''
        set -euo pipefail
        case "''${1:-}" in
          build)
            echo "[literate-state-machine-wiki] Building literate project..."
            nix build --no-link "''${2:-.}" "''${@:3}"
            echo "[literate-state-machine-wiki] Build complete."
            ;;
          *)
            echo "literate-state-machine-wiki — opinionated literate build tool"
            echo ""
            echo "Usage: literate-state-machine-wiki build [flake-ref]"
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
        inherit cli;
      };
      devShells.${system}.default = devshellLib.mkDevShell {
        inherit pkgs;
        extraPackages = [ cli ];
      };
    };

  # tangleAndRead: IFD helper. Tangles literate source in the store and
  # reads one specific file by path. Used by consumers who need tangled
  # content at eval time (e.g. package.json for importNpmLock or bun2nix).
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

  # mkChecks: library-internal test suite wiring. Returns an attrset of
  # derivations to merge into `checks.${system}` in the root flake.
  # Consumers do not use this — it is called by the root bootstrap stub.
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
    in {
      tangle-idempotent = checksLib.checkIdempotent { inherit src pkgs; };
      tangle-immutable = checksLib.checkImmutable {
        tangled = pipeline.tangle { inherit pkgs src; };
        inherit pkgs;
      };
      unit-tests = import "${tangled}/tests/unit-check.nix" { inherit pkgs lib checksLib; };
    }
    // prefixed "integration" integrationTests
    // prefixed "water-model" waterModelTests;
}
