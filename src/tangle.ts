/**
 * Tangle step.
 *
 * Shells out to entangled tangle. Deletes old generated files first (no stale state).
 * Reports count of tangled files on success.
 */

import { execSync } from 'child_process';
import { existsSync, readFileSync, chmodSync, readdirSync } from 'fs';
import { join } from 'path';

export interface TangleResult {
  success: boolean;
  filesCount: number;
  files: string[];
  error?: string;
}

function getTargetsFromFiledb(projectDir: string): string[] {
  const filedbPath = join(projectDir, '.entangled', 'filedb.json');
  if (!existsSync(filedbPath)) return [];
  try {
    const db = JSON.parse(readFileSync(filedbPath, 'utf-8'));
    return db.targets ?? [];
  } catch {
    return [];
  }
}

export function deleteOldGenerated(projectDir: string): number {
  const targets = getTargetsFromFiledb(projectDir);
  let deleted = 0;
  for (const target of targets) {
    const fullPath = join(projectDir, target);
    if (existsSync(fullPath)) {
      chmodSync(fullPath, 0o644); // unlock before delete
      const { unlinkSync } = require('fs');
      unlinkSync(fullPath);
      deleted++;
    }
  }
  // Clear filedb to prevent stale state
  const filedbPath = join(projectDir, '.entangled', 'filedb.json');
  if (existsSync(filedbPath)) {
    const { unlinkSync } = require('fs');
    unlinkSync(filedbPath);
  }
  return deleted;
}

function findEntangled(projectDir: string): string {
  // Check .venv first (nix devshell pattern)
  const venvPath = join(projectDir, '.venv', 'bin', 'entangled');
  if (existsSync(venvPath)) return venvPath;

  // Check PATH
  try {
    const which = execSync('which entangled', { encoding: 'utf-8' }).trim();
    if (which) return which;
  } catch {}

  throw new Error(
    'entangled not found. Install it:\n' +
    '  python3 -m venv .venv && .venv/bin/pip install entangled-cli==2.4.2\n' +
    '  or: nix develop'
  );
}

export function tangle(projectDir: string): TangleResult {
  // Step 1: Delete old generated files
  deleteOldGenerated(projectDir);

  // Step 2: Find and run entangled tangle
  const entangledBin = findEntangled(projectDir);

  try {
    const output = execSync(`${entangledBin} tangle --force`, {
      cwd: projectDir,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    // Step 3: Read filedb to get list of generated files
    const files = getTargetsFromFiledb(projectDir);

    return {
      success: true,
      filesCount: files.length,
      files,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      success: false,
      filesCount: 0,
      files: [],
      error: message,
    };
  }
}

export function lockGeneratedFiles(projectDir: string): number {
  const targets = getTargetsFromFiledb(projectDir);
  let locked = 0;
  for (const target of targets) {
    const fullPath = join(projectDir, target);
    if (existsSync(fullPath)) {
      chmodSync(fullPath, 0o444); // read-only
      locked++;
    }
  }
  return locked;
}
