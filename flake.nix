# ~~  ~/~ begin <<literate.lit.mdx/flake.lit.mdx#flake.nix>>[init]
{
  description = "literate-state-machine-wiki — my opinionated tangle";

  inputs = {
    nixpkgs.url = "nixpkgs";
    entangled.url = "github:zitongcharliedeng/entangled";
  };

  outputs = { self, nixpkgs, entangled }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      config = import ./lib/config.nix { inherit lib; entangledInput = entangled; };
      pipeline = import ./lib/pipeline.nix { inherit lib config; };
      checksLib = import ./lib/checks.nix { inherit lib config pipeline; };
      devshellLib = import ./lib/devshell.nix { inherit lib config; };

      init = {
        pkgs,
        src,
        system ? "x86_64-linux",
        postTangle ? [ ],
        sourceDir ? "literate.lit.mdx",
        forbidTsComments ? true,
        minProseLines ? 3,
        maxBlockLength ? 50,
        enforceDirectoryMatch ? false
      }:
      let
        verified = checksLib.makeVerify {
          inherit pkgs src sourceDir forbidTsComments minProseLines maxBlockLength enforceDirectoryMatch;
          inherit postTangle;
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
              echo ""
              echo "  build   Run the full escalating pipeline:"
              echo "          pre-check → tangle → lint → test → install"
              echo ""
              echo "Building literate means: check prose, tangle code,"
              echo "lint the code dialect, test, install to store."
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
    in
      # Self-application: this flake uses itself
      (init {
        inherit pkgs;
        src = ./.;
        sourceDir = "literate.lit.mdx";
        maxBlockLength = 200;
      }) // {
        # Library-only checks — self-testing, NOT inherited by consumers
        checks.${system} = {
          tangle-idempotent = checksLib.checkIdempotent { src = ./.; inherit pkgs; };
          tangle-immutable = checksLib.checkImmutable {
            tangled = pipeline.tangle { inherit pkgs; src = ./.; };
            inherit pkgs;
          };
        };

        lib = {
          inherit init;
          inherit (config) defaultEntangledToml;

          # tangleAndRead: forms emerge when needed (IFD wrapped elegantly)
          # Tangles literate source, reads a specific file at nix eval time
          # The file only exists as JSON/TS/etc at the moment it's consumed
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
              mkdir -p $out
              cp ${file} $out/ 2>/dev/null || (echo "ERROR: ${file} not found after tangle" && exit 1)
            ''
          }/${file}";
        };

        # Library's own devShell — for developing literate-state-machine-wiki itself.
        # Consumers get their own devShell from lib.init with the CLI included.
        devShells.${system}.default = devshellLib.mkDevShell {
          inherit pkgs;
        };
      };
}
# ~~  ~/~ end
