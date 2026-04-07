# ~~  ~/~ begin <<literate.lit.mdx/lib/devshell.lit.mdx#lib/devshell.nix>>[init]
{ lib, config }:
{
  mkDevShell = {
    pkgs,
    basePackages ? [ (config.nodejsFor pkgs) (config.pythonFor pkgs) ],
    extraPackages ? [ ],
    env ? { },
    sourceGlobs ? [ "literate.lit.mdx/*.lit.mdx" "literate.lit.mdx/**/*.lit.mdx" ],
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
        echo "[literate-state-machine-wiki] entangled: $(entangled --version 2>/dev/null || echo 'NOT FOUND')"
        ${lib.optionalString (tangleCommand != null) ''
          if ${autoTangleCondition}; then
            echo "[literate-state-machine-wiki] Auto-tangling literate source..."
            ${tangleCommand}
          else
            echo "[literate-state-machine-wiki] No literate source matched configured globs"
          fi
        ''}
        ${shellHook}
      '';
    };
}
# ~~  ~/~ end
