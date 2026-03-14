# Hello World — Test Literate File

This is a test `.lit.md` file that tangles to a TypeScript greeting.

```typescript {file=hello.ts}
export function greet(name: string): string {
  return `Hello, ${name}!`;
}
```

And a Nix expression:

```nix {file=hello.nix}
{ pkgs }:
pkgs.writeText "greeting" "Hello from literate nix!"
```
