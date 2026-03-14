/**
 * Machine discovery.
 *
 * Scans tangled .ts files for XState createMachine() or setup().createMachine() exports.
 * Returns list of discovered machines with file path and export name.
 */

import { readFileSync } from 'fs';
import { join, relative } from 'path';
import { globSync } from 'fs';

export interface DiscoveredMachine {
  file: string;
  exportName: string;
  machineId: string | null;
}

// Patterns that indicate a state machine export
const MACHINE_PATTERNS = [
  // export const fooMachine = setup({...}).createMachine({...})
  /export\s+const\s+(\w+)\s*=\s*setup\s*\(/,
  // export const fooMachine = createMachine({...})
  /export\s+const\s+(\w+)\s*=\s*createMachine\s*\(/,
];

// Extract machine id from id: 'foo' in the createMachine call
const ID_PATTERN = /\.createMachine\s*\(\s*\{[^}]*id:\s*['"]([^'"]+)['"]/s;

function findTsFiles(dir: string): string[] {
  const results: string[] = [];

  function walk(currentDir: string) {
    const { readdirSync, statSync } = require('fs');
    const entries = readdirSync(currentDir);
    for (const entry of entries) {
      if (entry === 'node_modules' || entry === '.git' || entry === '.omc') continue;
      const fullPath = join(currentDir, entry);
      const stat = statSync(fullPath);
      if (stat.isDirectory()) {
        // Skip the source directory (ONLY_EDIT_* or literate/)
        if (/^ONLY_EDIT_/.test(entry) || entry === 'literate') continue;
        walk(fullPath);
      } else if (entry.endsWith('.ts') && !entry.endsWith('.test.ts') && !entry.endsWith('.spec.ts')) {
        results.push(fullPath);
      }
    }
  }

  walk(dir);
  return results;
}

export function discoverMachines(projectDir: string): DiscoveredMachine[] {
  const tsFiles = findTsFiles(projectDir);
  const machines: DiscoveredMachine[] = [];

  for (const file of tsFiles) {
    const content = readFileSync(file, 'utf-8');

    for (const pattern of MACHINE_PATTERNS) {
      const match = content.match(pattern);
      if (match) {
        const exportName = match[1];

        // Try to extract machine id
        const idMatch = content.match(ID_PATTERN);
        const machineId = idMatch ? idMatch[1] : null;

        machines.push({
          file: relative(projectDir, file),
          exportName,
          machineId,
        });
        break; // One machine per file (for now)
      }
    }
  }

  return machines;
}
