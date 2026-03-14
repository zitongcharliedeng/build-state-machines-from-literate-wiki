# Knowledge Synthesis: Build State Machines From Literate Wiki

This document links the research, context, and design decisions from the 2026-03-14 design session. It connects LSMW to aito-web, gridinstruments, NixOS, HPI, formal methods, and the LifeOS vision.

See also: [gridinstruments issue #156](https://github.com/zitongcharliedeng/gridinstruments/issues/156) (rhythm game design).

---

## The Unified Axiom (from voicetree)

> Store the source of truth. Assume the capability layer. Never store the derived form.

| Instance | Source (STORE) | Capability (ASSUME) | Derived (NEVER STORE) |
|----------|---------------|--------------------|-----------------------|
| Compute | flake.nix | Nix compiler | Running system |
| Knowledge | .lit.md files | LLM + Entangled | Tangled .ts, wiki views |
| Media | JPEG/MP4 bytes | Decoder + display | Viewable content |
| Time | Block objects | Date.now() | Tracked time |
| IP/Software | Tests + specs | LLM as compiler | Implementation code |
| Personal data | HPI exports (JSON/SQLite) | HPI Python modules | Dashboards, search |
| State machines | .lit.md with XState defs | LSMW build | Generated tests, coverage reports |
| Trust | Explicit p-values in frontmatter | Bayesian propagation | Aggregate trust scores |

LSMW is an instance of this axiom: `.lit.md` files are the source. `build` is the capability. Generated `.ts` + test results are derived.

---

## How LSMW Connects To Everything

```
                         ┌─────────────┐
                         │   TELOS      │
                         │ (Mission,    │
                         │  Goals,      │
                         │  P-values)   │
                         └──────┬───────┘
                                │ informs
                    ┌───────────┴───────────┐
                    │                       │
              ┌─────┴─────┐         ┌──────┴──────┐
              │  aito-web  │         │gridinstruments│
              │ (LifeOS    │         │(music app)    │
              │  web wiki) │         │               │
              └─────┬──────┘         └──────┬───────┘
                    │ uses                   │ uses
                    └───────────┬────────────┘
                                │
                    ┌───────────┴───────────┐
                    │  LSMW build            │
                    │  (tangle + enforce +   │
                    │   discover + test)     │
                    └───────────┬────────────┘
                                │ reads
                    ┌───────────┴───────────┐
                    │  .lit.md files         │
                    │  (source of truth)     │
                    └───────────┬────────────┘
                                │ contains
              ┌─────────────────┼─────────────────┐
              │                 │                  │
     XState machines    Wiki-links [[]]    Trust/assumptions
     (with meta.reason, (backlink graph)   (p-values, explicit
      meta.invariants)                      boundary defs)
```

---

## Formal Methods Stack (from research)

### What to use NOW:
- **@xstate/test** — exhaustive path coverage from machine graph (already used in gridinstruments)
- **fast-check** — property-based fuzzing of XState machines (model-based testing)
- **Explicit assumption sections** in .lit.md frontmatter

### What to use NEXT (3-6 months):
- **Quint** — TypeScript-like syntax for TLA+ temporal logic. Embed Quint specs in .lit.md code blocks alongside XState. Model-check with Apalache.
- **Conformance testing** — verify XState runtime matches Quint spec

### What comes LATER (12-18 months):
- **LLM-generated Quint specs** from natural language in .lit.md (FSE 2025 paper proves feasibility)
- **Quickstrom-style LTL testing** of running web apps
- **P-value trust propagation** (oh-my-markov Phase 2)

### What NOT to use:
- CSP (wrong concurrency model for XState actors)
- Alloy (no TypeScript tooling)
- SPIN/Promela (too distant from web ecosystem)
- TLA+ directly (learn Quint instead — same logic, TypeScript DX)

---

## HPI as Explicit Inspiration

[karlicoss/HPI](https://github.com/karlicoss/HPI) — 1,582 stars, MIT, Python 3.12+

### Why HPI matters for LSMW/LifeOS:

1. **API design**: `from my.reddit.all import saved` — that's the whole API. One import, structured Python objects. LSMW should aim for: `import { build } from 'build-state-machines-from-literate-wiki'` — one import, structured result.

2. **Data ownership**: "Your digital trace is part of your identity." Same axiom as voicetree: store source, assume capability.

3. **Anti-vapourware**: karlicoss explicitly critiques tools that promise but don't deliver. "Stop waiting for someone else to solve it. Export your data today." This aligns with your approach: don't wait for Obsidian to add XState support, build what's missing.

4. **Pragmatic scope**: HPI doesn't try to build a UI, a wiki, a search engine. It provides a Python API. Everything else is a consumer. LSMW should follow this: provide `build`, let aito-web/Obsidian/etc. consume the results.

5. **Overlay/extension system**: HPI allows third-party modules under the `my.*` namespace. LSMW's `@lsmw/*` package scope follows the same pattern.

### Integration paths:
- Package HPI for NixOS flake (community flake exists from GTrunSec)
- Generate .lit.md pages from HPI data (bookmarks, highlights, annotations → wiki pages)
- Promnesia indexes Obsidian vault + browsing history (already supported)
- LLM agent with HPI access → structured personal data as tool calls

---

## The Obsidian Question (resolved)

### What Obsidian does well (2026):
- Graph view, backlinks, wiki-links
- Spaced repetition (Decks plugin with FSRS)
- Task management (Tasks + Dataview + Bases)
- Agent Client plugin (Claude Code inside Obsidian)
- Git integration (obsidian-git)
- 1500+ community plugins
- Mobile 2.0 with touch support

### What Obsidian CANNOT do:
- Literate programming (no tangle)
- XState machine testing
- Formal verification
- Agent sessions with comment threads
- Custom three-column layout (plugin needed)
- Trust/assumption tracking

### Decision:
- Obsidian as **viewer/knowledge tool** for the parts it handles well
- aito-web as **thin server** adding ONLY: agent sessions, task aggregation, spaced repetition review
- LSMW as **build tool** for both
- Same ~/wiki/ directory, shared .lit.md files
- NOT an either/or — both tools pointing at the same source

### Testability concern:
Every Obsidian plugin LSMW depends on needs explicit trust documentation:
```yaml
assumes:
  - tool: "obsidian-spaced-repetition-recall"
    trust: 75
    source: "open-spaced-repetition org, FSRS algorithm proven"
    boundary: "scheduling accuracy, not data persistence"
  - tool: "obsidian-git"
    trust: 90
    source: "Vinzent03, actively maintained, 2M+ downloads"
    boundary: "desktop only, mobile uses isomorphic-git with limitations"
```

---

## Session Persistence Problem (your biggest pain)

### Current state:
- Claude Code sessions are ephemeral (context lost on restart/compaction)
- VoiceTree captures voice notes but doesn't link to active sessions
- .omc state files track mode (ralph, ultrawork) but not conversation context
- Handoff docs exist (handoff-aitoweb-git-identity-refactor.mdx) but are manual

### What HPI teaches:
- Mirror EVERYTHING locally in open formats
- Search is the killer feature (instant ripgrep across all data)
- Don't build a database — build a Python/TS API to files on disk

### What LSMW enables:
- Session summaries as .lit.md pages with frontmatter tags
- `build` verifies the wiki is consistent across sessions
- Wiki-links between session pages and project pages create a navigable graph
- Next session: the LLM reads relevant .lit.md pages, full context restored

### What still needs building:
- Auto-generation of session summary .lit.md on session end
- Tag-based retrieval ("show me all sessions about aito-web identity system")
- Integration with VoiceTree nodes (voice notes → .lit.md pages)

---

## Libraries Needed (Revised)

Based on everything above, the actual libraries are:

### 1. `build-state-machines-from-literate-wiki` (LSMW) — EXISTS, prototype working
- `build` command: tangle + enforce + discover machines + test
- Source dir: `ONLY_EDIT_THIS_DIRECTORY_EVERYTHING_ELSE_IS_GENERATED_FROM.lit.md/`
- Smart defaults for entangled, tsc, ast-grep binary locations

### 2. Task scanner — DOES NOT EXIST, ~100 lines
- Scan `- [ ]` from .lit.md files across directories
- Output structured JSON or feed to aito-web PREDICTIONS panel
- Respects project boundaries (per-directory or global)

### 3. Session persistence — DOES NOT EXIST, ~200 lines
- On session end: generate .lit.md summary with frontmatter
- On session start: find relevant .lit.md pages by tag
- Replaces ephemeral .omc state with permanent wiki pages

### 4. HPI bridge — DOES NOT EXIST, ~150 lines
- Generate .lit.md pages from HPI Python module output
- Bookmarks, highlights, annotations → wiki pages with frontmatter
- Runs on cron or on-demand

### 5. Quint integration (FUTURE) — DOES NOT EXIST
- Embed Quint specs in .lit.md code blocks
- `build` tangles Quint to separate files, runs Apalache model checker
- Conformance testing between Quint spec and XState runtime

---

## Open Questions

1. Should aito-web use Obsidian as its rendering layer (Obsidian plugin) or stay as a standalone web server?
2. Should the three-column layout be an Obsidian plugin or a separate web app?
3. How does TagStudio fit when it doesn't support UUID-based identity yet?
4. Should session summaries be auto-generated or human-triggered?
5. Where does VoiceTree fit — is it a data source (like HPI) or a primary interface?
6. Does Emacs add value as an LLM shell (gptel + org-roam) or is Claude Code terminal sufficient?

---

## References

### Your own work:
- voicetree-11-2/unified-lifeos-axiom-store-source-assume-capability-derive-output.md
- voicetree-11-2/263_Aito_tests_are_the_new_source_code_llm_compiler_ip_moat.md
- voicetree-11-2/indydevdan-and-statemachine-notes-located.md
- aito-web/literate/specs/oh-my-markov.lit.md
- .pi/todos/oh-my-markov-PRD.md
- 01-THE_PRESENT/.../immutable-lifeos-enforcement-pyramid/design.md

### External:
- [karlicoss/HPI](https://github.com/karlicoss/HPI) — Personal data API
- [beepb00p.xyz/sad-infra.html](https://beepb00p.xyz/sad-infra.html) — Anti-vapourware philosophy
- [Quint](https://github.com/informalsystems/quint) — TypeScript-like TLA+
- [Daniel Miessler — Companies Are Graphs of Algorithms](https://danielmiessler.com/blog/companies-graph-of-algorithms)
- [FSE 2025 — NL Outlines for Code](https://dl.acm.org/doi/10.1145/3696630.3728541)
- [silly.business — Literate Programming in the Agent Era](https://silly.business/blog/we-should-revisit-literate-programming-in-the-agent-era/)
- [gamedolphin/system](https://github.com/gamedolphin/system) — Literate NixOS config
- [Quickstrom](https://github.com/quickstrom/quickstrom) — LTL web testing

---

*Generated from design session 2026-03-14. This document should be converted to .lit.md when the LSMW repo dogfoods itself.*
