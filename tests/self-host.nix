# ~~  ~/~ begin <<literate.lit.mdx/tests/self-host.lit.mdx#tests/self-host.nix>>[init]
# Generated from literate.lit.mdx/tests/self-host.lit.mdx — DO NOT EDIT
{ pkgs, lib, src, pipelineLib }:

let
  # Tangle the literate source using the library's own pipeline.
  # This is Stage 2 in the bootstrap — the library building itself.
  stage2 = pipelineLib.tangle {
    inherit pkgs src;
    stripGeneratedMarkers = false;  # preserve markers for byte comparison
  };

  # Files that must match bitwise between committed bootstrap and stage2 tangle.
  bootstrapFiles = [
    "flake.nix"
    "lib/checks.nix"
    "lib/pipeline.nix"
    "lib/config.nix"
    "lib/devshell.nix"
  ];

  diffCommands = builtins.concatStringsSep "\n" (map (file: ''
    # stderr visible so "file not found" is distinguishable from "content diff"
    if ! diff -q "${src}/${file}" "${stage2}/${file}" > /dev/null; then
      echo "❌ DRIFT: ${file} differs between committed bootstrap and tangled output"
      echo "   Committed:  ${src}/${file}"
      echo "   Tangled:    ${stage2}/${file}"
      echo ""
      echo "   First 20 lines of diff:"
      diff "${src}/${file}" "${stage2}/${file}" | head -20 || true
      exit 1
    fi
    echo "✅ ${file}"
  '') bootstrapFiles);

in
pkgs.runCommand "literate-state-machine-wiki-self-host-check" { } ''
  echo "=== Self-hosting check: committed bootstrap vs tangled output ==="
  ${diffCommands}

  # README.md must be a symlink to the canonical literate source. If a contributor
  # replaces it with a real file, the bootstrap structure has silently diverged.
  if [ ! -L "${src}/README.md" ]; then
    echo "❌ STRUCTURE: README.md is not a symlink"
    echo "   Expected: symlink to literate.lit.mdx/index.lit.mdx"
    exit 1
  fi
  echo "✅ README.md (symlink)"

  echo ""
  echo "✅ Self-hosting verified: all bootstrap files match bitwise"
  touch "$out"
''
# ~~  ~/~ end
