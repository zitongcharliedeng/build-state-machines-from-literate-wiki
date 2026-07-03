---
description: Mock-shim acceptance contract for gridinstruments PR #301 — the consumer builds through init and the site still works
tags: [tests, intention, consumer-migration, mock-shims]
---

# Gridinstruments PR #301 Intention

The intention, commit-message sized: **gridinstruments builds through `init` and the site still works.** Everything else the earlier draft of this page listed (no gitignore, store-only artifacts, pipeline order) is library doctrine the library already enforces and tests itself — a consumer PR does not re-claim it.

Two shims, mocked now, replaced with real probes at PR refresh: `buildConsumer` runs the consumer's `nix build` against current `init` and returns the store path or null; `siteSmoke` exercises the built site. The test set is the whole contract.

```{.ts file=tests/gridinstruments-intention/contract.test.ts}
import { describe, expect, test } from 'bun:test';

export type ConsumerShims = {
  buildConsumer: () => string | null;
  siteSmoke: (storePath: string) => boolean;
};

export const mockShims: ConsumerShims = {
  buildConsumer: () => '/nix/store/mock-gridinstruments-site',
  siteSmoke: (p) => p.startsWith('/nix/store/'),
};

describe('gridinstruments builds through init and the site still works', () => {
  test('consumer build succeeds against current init API', () => {
    expect(mockShims.buildConsumer()).not.toBeNull();
  });

  test('the built site passes the smoke check', () => {
    const out = mockShims.buildConsumer();
    expect(out && mockShims.siteSmoke(out)).toBe(true);
  });
});
```
