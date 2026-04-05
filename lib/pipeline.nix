# ~~  ~/~ begin <<literate.lit.mdx/lib/pipeline.lit.mdx#lib/pipeline.nix>>[init]
# ~~ This file is generated from literate.lit.mdx/nix/pipeline.lit.mdx
{ lib, config }:
rec {
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/pipeline.lit.mdx#lib/pipeline.nix>>[1]
  projectSetup = { src }: ''
    mkdir -p build
    cp -r ${src}/. build/
    chmod -R u+w build
    cd build

    rm -f .entangled/filedb.json
  '';
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/pipeline.lit.mdx#lib/pipeline.nix>>[2]
  stripEntangledMarkers = ''
    find . \
      -type f \
      -not -path './.entangled/*' \
      -not -name 'entangled.toml' \
      -not -name '*.lit.md' \
      -print0 | while IFS= read -r -d $'\0' file; do
      chmod u+w "$file" 2>/dev/null || true
      sed -i \
        -e '/^\/\/ ~~ .*$/d' \
        -e '/^# ~~ .*$/d' \
        -e '/^<!-- ~~ .*-->$/d' \
        -e '/^\/\* ~~ .* \*\/$/d' \
        "$file"
    done
  '';
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/pipeline.lit.mdx#lib/pipeline.nix>>[3]
  tangleProject = { stripGeneratedMarkers ? true }: ''
    entangled tangle --force
    ${lib.optionalString stripGeneratedMarkers stripEntangledMarkers}
  '';
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/pipeline.lit.mdx#lib/pipeline.nix>>[4]
  installTargets = ''
    mkdir -p "$out"
    python3 - <<'PY'
    import json, os, shutil, stat

    filedb_path = os.path.join(os.getcwd(), ".entangled", "filedb.json")
    if not os.path.exists(filedb_path):
        raise SystemExit("ERROR: entangled did not produce .entangled/filedb.json")

    with open(filedb_path, "r", encoding="utf-8") as handle:
        data = json.load(handle)

    targets = sorted(data.get("targets", []))
    out_dir = os.environ["out"]

    for rel_path in targets:
        src_path = os.path.join(os.getcwd(), rel_path)
        if not os.path.exists(src_path):
            raise SystemExit(f"ERROR: missing tangled target: {rel_path}")
        dest_path = os.path.join(out_dir, rel_path)
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        shutil.copy2(src_path, dest_path)
        os.chmod(dest_path, stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH)
    PY
  '';
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/pipeline.lit.mdx#lib/pipeline.nix>>[5]
  tangle = {
    src,
    name ? "tangled",
    pkgs,
    stripGeneratedMarkers ? true
  }:
    pkgs.runCommand name {
      nativeBuildInputs = [ (config.entangledFor pkgs) (config.pythonFor pkgs) ];
    } ''
      set -euo pipefail
      ${projectSetup { inherit src; }}
      ${tangleProject { inherit stripGeneratedMarkers; }}
      ${installTargets}
    '';
# ~~  ~/~ end
# ~~  ~/~ begin <<literate.lit.mdx/lib/pipeline.lit.mdx#lib/pipeline.nix>>[6]
  buildWebWiki = {
    src,
    pkgs,
    name ? "literate-state-machine-wiki-docs",
    litSourceDir ? "literate.lit.mdx"
  }:
    pkgs.runCommand name {
      nativeBuildInputs = [ pkgs.python3 ];
    } ''
      mkdir -p $out
      cp -r ${src}/${litSourceDir}/. $out/
      chmod -R u+w $out
      python3 - <<'WIKI'
import os, re

docs = os.environ["out"]
pages = {}

for root, _, files in os.walk(docs):
    for name in files:
        if not (name.endswith(".lit.mdx") or name.endswith(".lit.md")):
            continue
        rel = os.path.relpath(os.path.join(root, name), docs)
        key = name.replace(".lit.mdx", "").replace(".lit.md", "").lower()
        pages[key] = rel
        with open(os.path.join(root, name)) as f:
            for line in f:
                if line.startswith("title:"):
                    pages[line.split(":", 1)[1].strip().lower()] = rel
                    break
                if line == "---\n" and key in pages:
                    break
        dir_key = os.path.relpath(os.path.join(root, name), docs).replace(".lit.mdx", "").replace(".lit.md", "").lower()
        pages[dir_key] = rel

for root, _, files in os.walk(docs):
    for name in files:
        if not (name.endswith(".lit.mdx") or name.endswith(".lit.md")):
            continue
        path = os.path.join(root, name)
        with open(path) as f:
            content = f.read()
        def resolve(m):
            text = m.group(1)
            key = text.lower().strip()
            if key in pages:
                target = os.path.relpath(os.path.join(docs, pages[key]), root)
                return f"[{text}]({target})"
            return f"[{text}](#{key.replace(' ', '-')})"
        modified = re.sub(r"\[\[([^\]]+)\]\]", resolve, content)
        if modified != content:
            with open(path, "w") as f:
                f.write(modified)

count = len(set(pages.values()))
print(f"[literate-state-machine-wiki] Wiki: {count} pages, links resolved")
WIKI
    '';
}
# ~~  ~/~ end
