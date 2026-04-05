# ~~  ~/~ begin <<literate.lit.mdx/lib/devshell.lit.mdx#lib/devshell.nix>>[init]
{ lib, config }:
{
  mkDevShell = {
    pkgs,
    basePackages ? [ (config.nodejsFor pkgs) (config.pythonFor pkgs) ],
    extraPackages ? [ ],
    env ? { },
    sourceGlobs ? [ "literate/*.lit.md" "literate/**/*.lit.md" ],
    tangleCommand ? null,
    shellHook ? "",
    includeEntangled ? false
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
      entangledPackages = lib.optionals includeEntangled [ (config.entangledFor pkgs) ];
    in pkgs.mkShell {
      packages = entangledPackages ++ basePackages ++ extraPackages;
      shellHook = ''
        ${envExports}
        ${lib.optionalString includeEntangled ''
          echo "[literate-state-machine-wiki] entangled: $(entangled --version 2>/dev/null || echo 'NOT FOUND')"
        ''}
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
