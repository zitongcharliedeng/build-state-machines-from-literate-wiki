{
  description = "literate-state-machine-wiki — root bootstrap (tangled from flake.lit.md)";

  inputs = {
    nixpkgs.url = "nixpkgs";
    entangled.url = "github:zitongcharliedeng/entangled/dev";
  };

  nixConfig = {
    allow-import-from-derivation = true;
  };
  outputs = { self, nixpkgs, entangled }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      tangled = pkgs.runCommand "lsmw-bootstrap-tangle" {
        nativeBuildInputs = [ entangled.packages.${system}.default ];
      } ''
        mkdir -p $out
        cp -r ${./literate.lit.md} $out/literate.lit.md
        cp ${./flake.lit.md} $out/flake.lit.md
        chmod -R u+w $out
        cd $out
        cat > entangled.toml <<'TOML'
version = "2.0"
watch_list = ["flake.lit.md", "literate.lit.md/**/*.lit.md", "literate.lit.md/**/*.lit.mdx"]
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
      config = import "${tangled}/lib/config.nix" { inherit lib; entangledInput = entangled; };
      pipeline = import "${tangled}/lib/pipeline.nix" { inherit lib config; };
      checksLib = import "${tangled}/lib/checks.nix" { inherit lib config pipeline; };
      devshellLib = import "${tangled}/lib/devshell.nix" { inherit lib config; };
      initModule = import "${tangled}/lib/init.nix" {
        inherit lib pkgs config pipeline checksLib devshellLib;
      };
      inherit (initModule) init tangleAndRead;
      lsmwOutputs = init {
        inherit pkgs;
        src = ./.;
        sourceDir = "literate.lit.md";
        ignoreLiterateGitSubmodules = true;
      };
    in
      lsmwOutputs // {
        lib = {
          inherit init tangleAndRead;
          inherit (config) defaultEntangledToml;
        };

        checks.${system} = initModule.mkChecks {
          inherit pkgs tangled pipeline checksLib init;
          todoVerb = lsmwOutputs.packages.${system}.todoVerb;
          src = ./.;
        };

        devShells.${system}.default = devshellLib.mkDevShell {
          inherit pkgs;
        };
      };
}
