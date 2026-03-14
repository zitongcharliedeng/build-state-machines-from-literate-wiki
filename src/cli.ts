#!/usr/bin/env bun
/**
 * build-state-machines-from-literate-wiki CLI
 *
 * Single command: build
 * Tangles .lit.md → source, locks generated files, enforces rules,
 * discovers XState machines, detects unknown files.
 */

import { resolve } from 'path';
import { discoverSourceDir } from './discover-source';
import { tangle, lockGeneratedFiles } from './tangle';
import { enforce } from './enforce';
import { discoverMachines } from './discover-machines';
import { detectUnknownFiles } from './unknown-files';
import { basename } from 'path';

const USAGE = `
build-state-machines-from-literate-wiki

Usage:
  lsmw build [project-dir]     Build and verify the project
  lsmw build --source <dir>    Use a custom source directory

Options:
  --source <dir>   Override source directory name
  --help           Show this help

The build command:
  1. Finds the source directory (ONLY_EDIT_*_FROM.lit.md/ or literate/)
  2. Tangles .lit.md files into source code
  3. Locks generated files (chmod 444)
  4. Typechecks (tsc --noEmit)
  5. Enforces ast-grep rules (if sgconfig.yml exists)
  6. Discovers XState machines in tangled output
  7. Detects unknown files not produced by any .lit.md
`.trim();

function log(step: string, message: string) {
  console.log(`[${step}] ${message}`);
}

function logError(step: string, message: string) {
  console.error(`[${step}] ERROR: ${message}`);
}

async function build(projectDir: string, sourceOverride?: string) {
  const absDir = resolve(projectDir);
  console.log(`\nbuild-state-machines-from-literate-wiki\n${'='.repeat(40)}\n`);

  // Step 1: Discover source directory
  let sourceDir: string;
  try {
    sourceDir = discoverSourceDir(absDir, sourceOverride);
    log('source', `Found: ${basename(sourceDir)}/`);
  } catch (err: unknown) {
    logError('source', err instanceof Error ? err.message : String(err));
    process.exit(1);
  }

  // Step 2: Tangle
  log('tangle', 'Tangling .lit.md → source files...');
  const tangleResult = tangle(absDir);
  if (!tangleResult.success) {
    logError('tangle', tangleResult.error ?? 'Unknown tangle error');
    process.exit(1);
  }
  log('tangle', `${tangleResult.filesCount} files tangled`);

  // Step 3: Lock generated files
  const locked = lockGeneratedFiles(absDir);
  log('lock', `${locked} files set to read-only (chmod 444)`);

  // Step 4: Enforce (typecheck + ast-grep)
  log('enforce', 'Running typecheck + ast-grep...');
  const enforceResult = enforce(absDir);
  if (!enforceResult.pass) {
    logError('enforce', `${enforceResult.violations.length} violation(s):`);
    for (const v of enforceResult.violations.slice(0, 20)) {
      console.error(`  ${v.file}:${v.line} [${v.rule}] ${v.message}`);
    }
    if (enforceResult.violations.length > 20) {
      console.error(`  ... and ${enforceResult.violations.length - 20} more`);
    }
    process.exit(1);
  }
  log('enforce', 'All checks passed');

  // Step 5: Discover machines
  const machines = discoverMachines(absDir);
  log('machines', `${machines.length} XState machine(s) discovered:`);
  for (const m of machines) {
    console.log(`  ${m.file} → ${m.exportName}${m.machineId ? ` (id: ${m.machineId})` : ''}`);
  }

  // Step 6: Detect unknown files
  const sourceDirName = basename(sourceDir);
  const unknownFiles = detectUnknownFiles(absDir, sourceDirName);
  if (unknownFiles.length > 0) {
    log('unknown', `${unknownFiles.length} file(s) not produced by any .lit.md:`);
    for (const f of unknownFiles) {
      console.log(`  ⚠ ${f}`);
    }
    log('unknown', 'Move these into the source directory or delete them');
  } else {
    log('unknown', 'No unknown files');
  }

  // Summary
  console.log(`\n${'='.repeat(40)}`);
  console.log(`✓ Build complete`);
  console.log(`  ${tangleResult.filesCount} files tangled`);
  console.log(`  ${locked} files locked`);
  console.log(`  ${machines.length} machines discovered`);
  console.log(`  ${enforceResult.violations.length} violations`);
  if (unknownFiles.length > 0) {
    console.log(`  ${unknownFiles.length} unknown files (warnings)`);
  }
  console.log();
}

// Parse CLI arguments
const args = process.argv.slice(2);

if (args.includes('--help') || args.length === 0) {
  console.log(USAGE);
  process.exit(0);
}

const command = args[0];

if (command !== 'build') {
  console.error(`Unknown command: ${command}`);
  console.log(USAGE);
  process.exit(1);
}

const sourceIdx = args.indexOf('--source');
const sourceOverride = sourceIdx !== -1 ? args[sourceIdx + 1] : undefined;

// Project dir is the first non-flag argument after 'build'
let projectDir = '.';
for (let i = 1; i < args.length; i++) {
  if (args[i] === '--source') { i++; continue; }
  if (!args[i].startsWith('--')) { projectDir = args[i]; break; }
}

build(projectDir, sourceOverride);
