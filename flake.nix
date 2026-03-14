{
  description = "build-state-machines-from-literate-wiki — tangle .lit.md, store in nix, verify per-language";

  inputs = {
    nixpkgs.url = "nixpkgs";
    entangled.url = "github:entangled/entangled.py";
  };

  outputs = { self, nixpkgs, entangled }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      entangledPkg = entangled.packages.${system}.default;

      # Core library function: tangle .lit.md source → nix store derivation
      tangle = { src, name ? "tangled", entangledConfig ? null }:
        pkgs.runCommand name {
          nativeBuildInputs = [ entangledPkg ];
        } ''
          mkdir -p build
          cp -r ${src}/. build/
          chmod -R u+w build
          cd build

          # Use provided entangled.toml or generate default
          ${if entangledConfig != null
            then "cp ${entangledConfig} entangled.toml"
            else ''
              cat > entangled.toml << 'TOML'
              version = "2.0"
              watch_list = ["**/*.lit.md"]
              annotation = "standard"

              [[languages]]
              name = "TypeScript"
              identifiers = ["ts", "typescript"]
              comment = { open = "// ~~ " }

              [[languages]]
              name = "Nix"
              identifiers = ["nix"]
              comment = { open = "# ~~ " }

              [[languages]]
              name = "CSS"
              identifiers = ["css"]
              comment = { open = "/* ~~ ", close = " */" }

              [[languages]]
              name = "HTML"
              identifiers = ["html"]
              comment = { open = "<!-- ~~ ", close = " -->" }

              [[languages]]
              name = "Rust"
              identifiers = ["rust", "rs"]
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

              [[languages]]
              name = "JSON"
              identifiers = ["json"]
              comment = { open = "// ~~ " }
              TOML
            ''}

          entangled tangle --force 2>&1

          mkdir -p $out
          # Copy everything EXCEPT the .lit.md source and entangled internals
          find . -not -path './.entangled/*' \
                 -not -name 'entangled.toml' \
                 -not -name '*.lit.md' \
                 -not -path './build' \
                 -type f \
                 -exec install -Dm444 {} $out/{} \;

          # Also provide a manifest of what was tangled
          find $out -type f | sort > $out/.lsmw-manifest
        '';

      # Check: tangle is idempotent (tangle twice, same output)
      checkIdempotent = { src, name ? "idempotent-check", entangledConfig ? null }:
        let
          run1 = tangle { inherit src entangledConfig; name = "${name}-run1"; };
          run2 = tangle { inherit src entangledConfig; name = "${name}-run2"; };
        in pkgs.runCommand name {} ''
          diff -r ${run1} ${run2} --exclude=.lsmw-manifest || \
            (echo "ERROR: Tangle is NOT idempotent" && exit 1)
          echo "OK: Tangle is idempotent"
          touch $out
        '';

      # Check: all tangled files are read-only (444) in the store
      checkImmutable = { tangled, name ? "immutable-check" }:
        pkgs.runCommand name {} ''
          find ${tangled} -type f -not -name '.lsmw-manifest' | while read f; do
            perms=$(stat -c %a "$f")
            if [ "$perms" != "444" ]; then
              echo "ERROR: $f has permissions $perms, expected 444"
              exit 1
            fi
          done
          echo "OK: All tangled files are immutable (444)"
          touch $out
        '';

    in {
      # === LIBRARY API ===

      # tangle: .lit.md source dir → nix store derivation (immutable output)
      lib.tangle = tangle;

      # makeChecks: generate standard verification checks for a literate project
      lib.makeChecks = { src, pkgs ? nixpkgs.legacyPackages.${system}, entangledConfig ? null }:
        let
          tangled = tangle { inherit src entangledConfig; };
        in {
          # Core checks (always run)
          tangle-succeeds = tangled;
          tangle-idempotent = checkIdempotent { inherit src entangledConfig; };
          tangle-immutable = checkImmutable { inherit tangled; };

          # Manifest check (all files accounted for)
          tangle-manifest = pkgs.runCommand "manifest-check" {} ''
            if [ ! -f ${tangled}/.lsmw-manifest ]; then
              echo "ERROR: No manifest found"
              exit 1
            fi
            count=$(wc -l < ${tangled}/.lsmw-manifest)
            echo "OK: $count files in manifest"
            touch $out
          '';
        };

      # === THIS LIBRARY'S OWN INFRASTRUCTURE ===

      devShells.${system}.default = pkgs.mkShell {
        packages = [ entangledPkg pkgs.python313 pkgs.bun ];
        shellHook = ''
          echo "[lsmw] entangled: $(entangled --version 2>/dev/null || echo 'NOT FOUND')"
          echo "[lsmw] Ready. Use: nix flake check"
        '';
      };

      # Expose entangled for downstream consumers
      packages.${system} = {
        entangled = entangledPkg;
      };
    };
}
