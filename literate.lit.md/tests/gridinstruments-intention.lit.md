---
description: Claim machine + mock-shim tests capturing the INTENTION of gridinstruments PR #301 — the consumer authors only literate source and the site emerges verified from the nix store
tags: [tests, intention, consumer-migration, mock-shims]
---

# Gridinstruments Migration Intention — Claim Machine

PR #301 on gridinstruments is not "adopt a build tool's flake API". Its intention: **gridinstruments authors only literate source, and the running site is a verified projection from the nix store.** No committed manifests (package.json emerges via tangleAndRead), no `.gitignore`, no `_generated/` on disk, no `result` symlinks — the escalating pipeline (pre-tangle → tangle → lint → test → store) is the only path from prose to product.

This page freezes that intention as a state machine plus invariants, tested against **mock shims** in the `TEST_IMPLEMENTATION(machine_source, _impl) → diagnostics` shape: the machine and its tests are the contract now; the real `_impl` (shims probing the actual gridinstruments tree and driving real nix builds) is deliberately later. A memoryless implementer given only the shim contract and these tests should be able to finish the migration without reading anyone's chat history.

The machine is one XOR region: each migration stage is a state, each pipeline gate is a transition, any gate failure lands in `NEEDS_REPAIR` and `RETRY` re-enters at the literate source. Reaching `SERVED_FROM_STORE` is the intention fulfilled.

```{.ts file=tests/gridinstruments-intention/machine.ts}
import { setup } from 'xstate';

export const migrationStages = [
  'UNMIGRATED',
  'LITERATE_SOURCE_ONLY',
  'PRE_TANGLE_CLEAN',
  'TANGLED',
  'LINTED',
  'TESTED',
  'SERVED_FROM_STORE',
  'NEEDS_REPAIR',
] as const;

export type MigrationStage = (typeof migrationStages)[number];

export const consumerMigrationMachine = setup({}).createMachine({
  id: 'gridinstruments-consumer-migration',
  initial: 'UNMIGRATED',
  states: {
    UNMIGRATED: { on: { MOVE_SOURCE_TO_LITERATE: 'LITERATE_SOURCE_ONLY' } },
    LITERATE_SOURCE_ONLY: {
      on: { PRE_TANGLE_CHECKS_PASS: 'PRE_TANGLE_CLEAN', STAGE_FAILS: 'NEEDS_REPAIR' },
    },
    PRE_TANGLE_CLEAN: {
      on: { TANGLE_SUCCEEDS: 'TANGLED', STAGE_FAILS: 'NEEDS_REPAIR' },
    },
    TANGLED: { on: { LINTERS_PASS: 'LINTED', STAGE_FAILS: 'NEEDS_REPAIR' } },
    LINTED: { on: { TESTS_PASS: 'TESTED', STAGE_FAILS: 'NEEDS_REPAIR' } },
    TESTED: {
      on: { SITE_BUILDS_FROM_STORE: 'SERVED_FROM_STORE', STAGE_FAILS: 'NEEDS_REPAIR' },
    },
    NEEDS_REPAIR: { on: { RETRY: 'LITERATE_SOURCE_ONLY' } },
    SERVED_FROM_STORE: { type: 'final' },
  },
});
```

The shim contract names every probe and every stage-runner the intention depends on. Mocks stand in today; the real implementation later replaces each function with a probe of the actual gridinstruments checkout or a real `nix build` invocation, without touching the machine or the tests.

```{.ts file=tests/gridinstruments-intention/shims.ts}
export type ConsumerRepoShims = {
  rootHasGitignore: () => boolean;
  rootManifestFiles: () => string[];
  generatedDirExists: () => boolean;
  resultSymlinkExists: () => boolean;
  siteAssetRoot: () => string;
};

export type StageRunnerShims = {
  runPreTangleChecks: () => boolean;
  runTangle: () => boolean;
  runLinters: () => boolean;
  runTests: () => boolean;
  buildSiteFromStore: () => boolean;
};

export const mockCompliantRepo: ConsumerRepoShims = {
  rootHasGitignore: () => false,
  rootManifestFiles: () => [],
  generatedDirExists: () => false,
  resultSymlinkExists: () => false,
  siteAssetRoot: () => '/nix/store/mock-gridinstruments-site',
};

export const mockDriftedRepo: ConsumerRepoShims = {
  rootHasGitignore: () => true,
  rootManifestFiles: () => ['package.json', 'sgconfig.yml'],
  generatedDirExists: () => true,
  resultSymlinkExists: () => true,
  siteAssetRoot: () => './dist',
};
```

Invariants are scoped predicate checks over the repo fixture, TLA-style: each owns its predicate and the set of stages it must hold in. They are the durable claims of the PR — everything after the source moves into literate form must stay manifest-free, gitignore-free, generated-dir-free, and the final state must serve from the store.

```{.ts file=tests/gridinstruments-intention/invariants.ts}
import type { ConsumerRepoShims } from './shims';
import type { MigrationStage } from './machine';

const postMigration: MigrationStage[] = [
  'LITERATE_SOURCE_ONLY',
  'PRE_TANGLE_CLEAN',
  'TANGLED',
  'LINTED',
  'TESTED',
  'SERVED_FROM_STORE',
];

export type IntentionInvariant = {
  name: string;
  scope: MigrationStage[];
  holds: (repo: ConsumerRepoShims) => boolean;
};

export const intentionInvariants: IntentionInvariant[] = [
  { name: 'no-root-gitignore', scope: postMigration, holds: (r) => !r.rootHasGitignore() },
  { name: 'no-committed-manifests', scope: postMigration, holds: (r) => r.rootManifestFiles().length === 0 },
  { name: 'no-generated-dir-on-disk', scope: postMigration, holds: (r) => !r.generatedDirExists() },
  { name: 'store-only-artifacts', scope: postMigration, holds: (r) => !r.resultSymlinkExists() },
  {
    name: 'site-serves-from-store',
    scope: ['SERVED_FROM_STORE'],
    holds: (r) => r.siteAssetRoot().startsWith('/nix/store/'),
  },
];
```

The tests prove the contract itself: the composed machine reaches `SERVED_FROM_STORE` through exactly the escalating pipeline order, every scoped invariant holds along that path on a compliant fixture, and every invariant is individually violated by the drifted fixture — so a real repo that drifts cannot pass by accident.

```{.ts file=tests/gridinstruments-intention/machine.test.ts}
import { describe, expect, test } from 'bun:test';
import { getShortestPaths } from '@xstate/graph';
import { consumerMigrationMachine } from './machine';
import { intentionInvariants } from './invariants';
import { mockCompliantRepo, mockDriftedRepo } from './shims';

const pipelineOrder = [
  'MOVE_SOURCE_TO_LITERATE',
  'PRE_TANGLE_CHECKS_PASS',
  'TANGLE_SUCCEEDS',
  'LINTERS_PASS',
  'TESTS_PASS',
  'SITE_BUILDS_FROM_STORE',
];

describe('gridinstruments migration intention', () => {
  const paths = getShortestPaths(consumerMigrationMachine);
  const target = paths.find((p) => p.state.matches('SERVED_FROM_STORE'));

  test('SERVED_FROM_STORE is reachable', () => {
    expect(target).toBeDefined();
  });

  test('the only shortest path is the escalating pipeline in order', () => {
    expect(target?.steps.map((s) => s.event.type).filter((t) => t !== 'xstate.init')).toEqual(
      pipelineOrder,
    );
  });

  test('all scoped invariants hold on a compliant repo along the path', () => {
    const visited = target?.steps.map((s) => String(s.state.value)) ?? [];
    for (const inv of intentionInvariants) {
      for (const stage of visited.filter((v) => inv.scope.includes(v as never))) {
        expect(`${inv.name}@${stage}:${inv.holds(mockCompliantRepo)}`).toBe(
          `${inv.name}@${stage}:true`,
        );
      }
    }
  });

  test('every invariant individually rejects the drifted repo', () => {
    for (const inv of intentionInvariants) {
      expect(`${inv.name}:${inv.holds(mockDriftedRepo)}`).toBe(`${inv.name}:false`);
    }
  });
});
```

Wiring these tests into the flake check pipeline needs bun + xstate available to a check derivation — that is the same plumbing issue #26 (shared xstate/graph test helper) and #23 (shared lint pack) already want; do it there, once, not bespoke here. Until then: `bun test` inside `tests/gridinstruments-intention/` with `xstate` + `@xstate/graph` installed runs the contract standalone. When the PR refresh happens, replace the mocks with real probes and the same tests become the migration's acceptance gate.
