/**
 * Unknown file detection.
 *
 * After tangle, checks for files outside the source directory that are not
 * in entangled's filedb. These are files that no .lit.md produced.
 */

import { readdirSync, statSync, existsSync, readFileSync } from 'fs';
import { join, relative } from 'path';

const IGNORED_ENTRIES = new Set([
  'node_modules', '.git', '.omc', '.entangled', '.venv',
  'entangled.toml', 'package-lock.json', 'bun.lock', 'bun.lockb',
  '.gitignore', '.env', 'dist', 'test-results',
]);

const IGNORED_PATTERNS = [
  /^ONLY_EDIT_/,   // source directory
  /^literate$/,    // fallback source directory
  /^\./,           // dotfiles/dotdirs (except specific ones we care about)
];

function getKnownFiles(projectDir: string): Set<string> {
  const filedbPath = join(projectDir, '.entangled', 'filedb.json');
  if (!existsSync(filedbPath)) return new Set();
  try {
    const db = JSON.parse(readFileSync(filedbPath, 'utf-8'));
    const targets = db.targets ?? [];
    return new Set(targets.map((t: string) => t));
  } catch {
    return new Set();
  }
}

function walkDir(dir: string, baseDir: string, results: string[]) {
  const entries = readdirSync(dir);
  for (const entry of entries) {
    if (IGNORED_ENTRIES.has(entry)) continue;
    if (IGNORED_PATTERNS.some(p => p.test(entry))) continue;

    const fullPath = join(dir, entry);
    const relPath = relative(baseDir, fullPath);
    const stat = statSync(fullPath);

    if (stat.isDirectory()) {
      walkDir(fullPath, baseDir, results);
    } else {
      results.push(relPath);
    }
  }
}

export function detectUnknownFiles(projectDir: string, sourceDirName: string): string[] {
  const knownFiles = getKnownFiles(projectDir);

  // Add known non-generated files
  knownFiles.add('package.json');
  knownFiles.add('tsconfig.json');
  knownFiles.add('entangled.toml');
  knownFiles.add('.gitignore');

  const allFiles: string[] = [];
  const entries = readdirSync(projectDir);

  for (const entry of entries) {
    if (IGNORED_ENTRIES.has(entry)) continue;
    if (IGNORED_PATTERNS.some(p => p.test(entry))) continue;
    if (entry === sourceDirName) continue; // skip source dir

    const fullPath = join(projectDir, entry);
    const stat = statSync(fullPath);

    if (stat.isDirectory()) {
      walkDir(fullPath, projectDir, allFiles);
    } else {
      allFiles.push(entry);
    }
  }

  return allFiles.filter(f => !knownFiles.has(f));
}
