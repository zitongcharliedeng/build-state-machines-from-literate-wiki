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
      in {
        packages.${system} = {
          default = verified.default;
          tangled = verified.tangled;
          web-wiki = pipeline.buildWebWiki { inherit pkgs src; litSourceDir = sourceDir; };
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

        # DevShell is for literate-state-machine-wiki development ONLY.
        # Consumers do not need this — they use nix build.
        # This exists because bootstrapping requires entangled in PATH
        # to tangle flake.nix from its literate source.
        devShells.${system}.default = devshellLib.mkDevShell {
          inherit pkgs;
        };
      };
}
# ~~  ~/~ end
