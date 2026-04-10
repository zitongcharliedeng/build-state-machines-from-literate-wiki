{
  description = "literate-state-machine-wiki — root bootstrap stub (see literate.lit.mdx/bootstrap.lit.mdx)";

  # This file is HAND-MAINTAINED, not tangled from anywhere.
  # It is the equivalent of GCC's ./configure — a tiny stable bootstrap
  # that invokes the seed (entangled) to tangle the real source at
  # eval time via IFD, then delegates to what the tangle produces.
  #
  # Everything else — lib/*.nix, tests/*.nix, init function — lives in
  # literate.lit.mdx/ and is only materialized inside the nix store at
  # eval time. Nothing derived is committed.
  #
  # If you need to change library logic, edit the .lit.mdx files under
  # literate.lit.mdx/. Do not extend this file unless you are modifying
  # the bootstrap contract itself.

  inputs = {
    nixpkgs.url = "nixpkgs";
    entangled.url = "github:zitongcharliedeng/entangled";
  };

  outputs = { self, nixpkgs, entangled }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      # Stage 0: IFD tangle literate source.
      # Copies literate.lit.mdx into the store, writes a minimal entangled.toml,
      # runs entangled tangle --force, and removes .entangled/ so the output is
      # deterministic. The result is a full tangled tree we can import from.
      tangled = pkgs.runCommand "lsmw-bootstrap-tangle" {
        nativeBuildInputs = [ entangled.packages.${system}.default ];
      } ''
        mkdir -p $out
        cp -r ${./literate.lit.mdx} $out/literate.lit.mdx
        chmod -R u+w $out
        cd $out
        cat > entangled.toml <<'TOML'
version = "2.0"
literate_root = "literate.lit.mdx"
watch_list = ["literate.lit.mdx/**/*.lit.mdx"]
annotation = "standard"
[[languages]]
name = "Nix"
identifiers = ["nix"]
comment = { open = "# ~~ " }
[[languages]]
name = "TypeScript"
identifiers = ["ts", "typescript"]
comment = { open = "// ~~ " }
[[languages]]
name = "Python"
identifiers = ["python", "py"]
comment = { open = "# ~~ " }
[[languages]]
name = "Bash"
identifiers = ["bash", "sh"]
comment = { open = "# ~~ " }
[[languages]]
name = "YAML"
identifiers = ["yaml", "yml"]
comment = { open = "# ~~ " }
TOML
        entangled tangle --force
        rm -rf .entangled
      '';

      # Import the tangled library modules.
      config = import "${tangled}/lib/config.nix" { inherit lib; entangledInput = entangled; };
      pipeline = import "${tangled}/lib/pipeline.nix" { inherit lib config; };
      checksLib = import "${tangled}/lib/checks.nix" { inherit lib config pipeline; };
      devshellLib = import "${tangled}/lib/devshell.nix" { inherit lib config; };
      initModule = import "${tangled}/lib/init.nix" {
        inherit lib pkgs config pipeline checksLib devshellLib;
      };
      inherit (initModule) init tangleAndRead;
    in
      # Self-apply: the library uses itself to build itself.
      (init {
        inherit pkgs;
        src = ./.;
        sourceDir = "literate.lit.mdx";
        maxBlockLength = 200;
      }) // {
        lib = {
          inherit init tangleAndRead;
          inherit (config) defaultEntangledToml;
        };

        checks.${system} = initModule.mkChecks {
          inherit pkgs tangled pipeline checksLib init;
          src = ./.;
        };

        devShells.${system}.default = devshellLib.mkDevShell {
          inherit pkgs;
        };
      };
}
