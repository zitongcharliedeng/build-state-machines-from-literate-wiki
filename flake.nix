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
        linters ? [ ],
        tests ? [ ],
        sourceDir ? "literate.lit.mdx",
        forbidTsComments ? true,
        minProseLines ? 3,
        maxBlockLength ? 50,
        enforceDirectoryMatch ? false
      }:
      let
        verified = checksLib.makeVerify {
          inherit pkgs src sourceDir forbidTsComments minProseLines maxBlockLength enforceDirectoryMatch;
          inherit linters tests;
        };
        cli = pkgs.writeShellScriptBin "literate-state-machine-wiki" ''
          set -euo pipefail
          case "''${1:-}" in
            build)
              echo "[literate-state-machine-wiki] Building literate project..."
              nix build "''${2:-.}#literate-verified" "''${@:3}"
              echo "[literate-state-machine-wiki] Build complete."
              if [ -e result ]; then
                target="result/_generated"
                if [ ! -e "$target" ]; then
                  target="result"
                fi
                rm -f _generated
                ln -s "$target" _generated
                echo "[literate-state-machine-wiki] Symlinked _generated -> $target"
              fi
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

        lib = { inherit init; inherit (config) defaultEntangledToml; };

        # Library's own devShell — for developing literate-state-machine-wiki itself.
        # Consumers get their own devShell from lib.init with the CLI included.
        devShells.${system}.default = devshellLib.mkDevShell {
          inherit pkgs;
          includeEntangled = true;
        };
      };
}
# ~~  ~/~ end
