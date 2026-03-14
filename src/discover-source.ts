/**
 * Source directory discovery.
 *
 * Finds the literate source directory in a project.
 * Default: looks for ONLY_EDIT_*_FROM.lit.md pattern.
 * Fallback: literate/
 */

import { readdirSync, statSync } from 'fs';
import { join } from 'path';

const SOURCE_DIR_PATTERN = /^ONLY_EDIT_.*_FROM\.lit\.md$/;
const FALLBACK_DIRS = ['literate', 'lit'];

export function discoverSourceDir(projectDir: string, override?: string): string {
  if (override) {
    const overridePath = join(projectDir, override);
    try {
      if (statSync(overridePath).isDirectory()) return overridePath;
    } catch {
      throw new Error(`Source directory not found: ${overridePath}`);
    }
  }

  const entries = readdirSync(projectDir);

  // Look for ONLY_EDIT_*_FROM.lit.md directory
  for (const entry of entries) {
    if (SOURCE_DIR_PATTERN.test(entry)) {
      const fullPath = join(projectDir, entry);
      if (statSync(fullPath).isDirectory()) return fullPath;
    }
  }

  // Fallback to literate/ or lit/
  for (const fallback of FALLBACK_DIRS) {
    const fullPath = join(projectDir, fallback);
    try {
      if (statSync(fullPath).isDirectory()) return fullPath;
    } catch {
      continue;
    }
  }

  throw new Error(
    `No source directory found in ${projectDir}. ` +
    `Expected: ONLY_EDIT_THIS_DIRECTORY_EVERYTHING_ELSE_IS_GENERATED_FROM.lit.md/ or literate/`
  );
}
