# ~~  ~/~ begin <<literate.lit.mdx/lib/config.lit.mdx#lib/config.nix>>[init]
{ lib, entangledInput }:
{
  defaultEntangledToml = ''
    version = "2.0"
    watch_list = ["**/*.lit.md", "**/*.lit.mdx"]
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
