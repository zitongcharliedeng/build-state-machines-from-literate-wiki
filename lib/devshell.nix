# ~/~ begin <<literate.lit.md/lib/devshell.lit.md#lib/devshell.nix>>[init]
{ lib, config }:
{
  mkDevShell = {
    pkgs,
    basePackages ? [ (config.nodejsFor pkgs) (config.pythonFor pkgs) ],
    extraPackages ? [ ],
    env ? { },
    sourceGlobs ? [ "literate.lit.md/*.lit.md" "literate.lit.md/**/*.lit.md" "literate.lit.md/*.lit.mdx" "literate.lit.md/**/*.lit.mdx" ],
    tangleCommand ? null,
    shellHook ? ""
  }:
    let
      autoTangleCondition =
        if sourceGlobs == [ ]
        then "true"
        else lib.concatStringsSep " || "
          (map (pattern: "compgen -G ${lib.escapeShellArg pattern} > /dev/null") sourceGlobs);
      envExports = lib.concatStringsSep "\n" (lib.mapAttrsToList
        (name: value: "export ${name}=${lib.escapeShellArg (toString value)}")
        env);
    in pkgs.mkShell {
      packages = [ (config.entangledFor pkgs) ] ++ basePackages ++ extraPackages;
      shellHook = ''
        build() { nix build --no-link --print-out-paths "$@"; }
        export -f build
        ${envExports}
        echo "[${config.name}] entangled: $(entangled --version 2>/dev/null || echo 'NOT FOUND')"
        ${lib.optionalString (tangleCommand != null) ''
          if ${autoTangleCondition}; then
            echo "[${config.name}] Auto-tangling literate source..."
            ${tangleCommand}
          else
            echo "[${config.name}] No literate source matched configured globs"
          fi
        ''}
        ${shellHook}
      '';
    };
}
# ~/~ end
