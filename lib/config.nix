# ~~  ~/~ begin <<literate.lit.mdx/lib/config.lit.mdx#lib/config.nix>>[init]
{ lib, entangledInput }:
{
  defaultEntangledToml = ''
    version = "2.0"
    watch_list = ["**/*.lit.md", "**/*.lit.mdx"]
    annotation = "standard"

    [[lib/config]]
    name = "TypeScript"
    identifiers = ["ts", "typescript"]
    comment = { open = "// ~~ " }

    [[lib/config]]
    name = "Nix"
    identifiers = ["nix"]
    comment = { open = "# ~~ " }

    [[lib/config]]
    name = "CSS"
    identifiers = ["css"]
    comment = { open = "/* ~~ ", close = " */" }

    [[lib/config]]
    name = "HTML"
    identifiers = ["html"]
    comment = { open = "<!-- ~~ ", close = " -->" }

    [[lib/config]]
    name = "Rust"
    identifiers = ["rust", "rs"]
    comment = { open = "// ~~ " }

    [[lib/config]]
    name = "Python"
    identifiers = ["python", "py"]
    comment = { open = "# ~~ " }

    [[lib/config]]
    name = "Bash"
    identifiers = ["bash", "sh"]
    comment = { open = "# ~~ " }

    [[lib/config]]
    name = "YAML"
    identifiers = ["yaml", "yml"]
    comment = { open = "# ~~ " }

    [[lib/config]]
    name = "JSON"
    identifiers = ["json"]
    comment = { open = "// ~~ " }
  '';
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/config.lit.mdx#lib/config.nix>>[1]

  entangledFor = pkgs: entangledInput.packages.${pkgs.stdenv.hostPlatform.system}.default;

  pythonFor = pkgs:
    if pkgs ? python3 then pkgs.python3 else pkgs.python313;

  nodejsFor = pkgs:
    if pkgs ? nodejs_22 then pkgs.nodejs_22
    else if pkgs ? nodejs_20 then pkgs.nodejs_20
    else pkgs.nodejs;
}
# ~~  ~/~ end
