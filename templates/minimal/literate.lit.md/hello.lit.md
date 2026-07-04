---
description: Starter literate page — replace with your own
tags: [starter]
---

# hello

Every `.lit.md` under `literate.lit.md/` is literate source: prose explains the code, and fenced blocks with a `file=` attribute declare where the code tangles to.

The tangled output never lands in this folder. `nix build` runs the pipeline — structure checks, tangle, your linters, your tests — and installs the verified result read-only in the nix store.

This starter tangles one script so a fresh `nix build` has something to verify. Delete it once you have real pages.

```{.bash file=hello.sh}
echo "hello from the nix store"
```
