{
  description = "literate-state-machine-wiki — root bootstrap (tangled from flake.lit.mdx)";

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
        cp -r ${./literate.lit.mdx} $out/literate.lit.mdx
        cp ${./flake.lit.mdx} $out/flake.lit.mdx
        chmod -R u+w $out
        cd $out
        cat > entangled.toml <<'TOML'
version = "2.0"
watch_list = ["flake.lit.mdx", "literate.lit.mdx/**/*.lit.mdx"]
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
    in
      (init {
        inherit pkgs;
        src = ./.;
        sourceDir = "literate.lit.mdx";
        ignoreLiterateGitSubmodules = true;
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
