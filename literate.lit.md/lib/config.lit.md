---
description: Default configuration values extracted from flake.nix — the shared constants every consumer of literate-state-machine-wiki needs
tags: [nix, config, defaults, module]
---

# Nix Config Module

This module answers one question: what are the defaults? Every consumer of literate-state-machine-wiki who builds a devshell or tangle derivation needs the same three things — a way to find the `entangled` binary for the right platform, a way to find a sane Python, and a way to find a sane Node.js. And every consumer who does not supply their own `entangled.toml` needs the same language table.

Rather than copy these values into every flake that imports this library, they live here once. `lib/config.nix` is imported by `flake.nix` and passed to [[lib/devshell]] as its `config` argument.

`sourceDirCandidates` is the single answer to "where does literate source live". Consumers who don't pass `sourceDir` get auto-detection: `init` picks the first candidate that exists in `src`, the devshell derives its auto-tangle globs from the same list, and the `install-hooks` pre-commit hook probes the same names. One list, three consumers, no drift.

## Why a separate module rather than inline in flake.nix?

`flake.nix` is the composition layer. It wires inputs to outputs. When the defaults for `entangled.toml` or the toolchain resolution helpers live directly in `flake.nix`, there is no way for a consumer to import just the defaults without importing the full flake machinery. Extracting them here makes the library usable as a plain nix module — `import ./lib/config.nix { lib = nixpkgs.lib; entangledInput = inputs.entangled; }` — without pulling in any derivation-building logic.

## The entangled TOML default

`languages` is the single model of per-language syntax in the whole tool. Each entry declares the language's comment token once; everything else is a projection of this table: the entangled TOML (comment token + `~~ ` becomes Entangled's round-trip marker), and the pre-tangle no-comments check (the same token is what the check flags at line starts — see [[lib/checks]]). Never encode language knowledge anywhere else. The `~~ ` marker is how Entangled tags tangled lines — never change it without also updating all existing `.entangled/filedb.json` caches.

The watch list covers both `.lit.md` (plain markdown) and `.lit.mdx` (MDX with JSX) extensions. Projects that only use one extension can override `entangled.toml` directly — this default is intentionally permissive.

The language table is split out as `defaultEntangledLanguages` so anything that needs to compose a custom `entangled.toml` (e.g. the per-file tangle in `lib/pipeline`, which narrows the `watch_list`) can reuse the exact same language declarations. Adding a new language is one row in one place — no drift.

```{.nix file=lib/config.nix}
{ lib, entangledInput }:
let
  languages = [
    { name = "TypeScript"; identifiers = [ "ts" "typescript" ]; comment = "// "; }
    { name = "JavaScript"; identifiers = [ "js" "jsx" "javascript" ]; comment = "// "; }
    { name = "Nix";        identifiers = [ "nix" ];              comment = "# "; }
    { name = "CSS";        identifiers = [ "css" ];              comment = "/* "; close = " */"; }
    { name = "HTML";       identifiers = [ "html" ];             comment = "<!-- "; close = " -->"; }
    { name = "Rust";       identifiers = [ "rust" "rs" ];        comment = "// "; }
    { name = "Python";     identifiers = [ "python" "py" ];      comment = "# "; }
    { name = "Bash";       identifiers = [ "bash" "sh" ];        comment = "# "; }
    { name = "YAML";       identifiers = [ "yaml" "yml" ];       comment = "# "; }
    { name = "JSON";       identifiers = [ "json" ];             comment = "// "; }
    { name = "Markdown";   identifiers = [ "md" "markdown" ];    comment = "<!-- "; close = " -->"; }
    { name = "TOML";       identifiers = [ "toml" ];             comment = "# "; }
  ];
  defaultEntangledLanguages = lib.concatMapStringsSep "\n" (l: ''
    [[languages]]
    name = "${l.name}"
    identifiers = [${lib.concatMapStringsSep ", " (i: ''"${i}"'') l.identifiers}]
    comment = { open = "${l.comment}~~ "${lib.optionalString (l ? close) '', close = "${l.close}"''} }
  '') languages;
in
{
  inherit languages defaultEntangledLanguages;
  commentTokenFor = builtins.listToAttrs
    (lib.concatMap (l: map (i: { name = i; value = l.comment; }) l.identifiers) languages);
  name = "lsmw";
  sourceDirCandidates = [ ".english.lit.md" "literate.lit.md" "literate.lit.mdx" "literate" ];

  defaultEntangledToml = ''
    version = "2.0"
    watch_list = ["**/*.lit.md", "**/*.lit.mdx"]
    annotation = "standard"

    ${defaultEntangledLanguages}
  '';
```

## Toolchain resolution helpers

These three helpers follow the same pattern: try the most specific attribute first, fall back to the most generic. They exist because nixpkgs attribute names for Node.js and Python shift between major versions and between nixpkgs channels. A consumer on a pinned nixpkgs may have `nodejs_22`; a consumer on a newer channel may have renamed it. These helpers insulate consumers from that churn.

`entangledFor` resolves the entangled binary from the flake input rather than from nixpkgs. Entangled is not in nixpkgs stable. The `entangledInput` argument is the `entangled` flake input — passed in at construction time so this module does not close over any global state.

```{.nix file=lib/config.nix}

  entangledFor = pkgs: entangledInput.packages.${pkgs.stdenv.hostPlatform.system}.default;

  pythonFor = pkgs:
    if pkgs ? python3 then pkgs.python3 else pkgs.python313;

  nodejsFor = pkgs:
    if pkgs ? nodejs_22 then pkgs.nodejs_22
    else if pkgs ? nodejs_20 then pkgs.nodejs_20
    else pkgs.nodejs;
}
```
