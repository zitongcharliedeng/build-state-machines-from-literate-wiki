/**
 * Enforce step.
 *
 * Runs tsc --noEmit and ast-grep scan.
 * Reports violations with file:line:message format.
 */

import { execSync } from 'child_process';
import { existsSync } from 'fs';
import { join } from 'path';

export interface Violation {
  file: string;
  line: number;
  rule: string;
  message: string;
}

export interface EnforceResult {
  pass: boolean;
  violations: Violation[];
  typecheckOutput?: string;
  astgrepOutput?: string;
}

function findBin(projectDir: string, name: string): string | null {
  const localBin = join(projectDir, 'node_modules', '.bin', name);
  if (existsSync(localBin)) return localBin;
  try {
    return execSync(`which ${name} 2>/dev/null`, { encoding: 'utf-8' }).trim() || null;
  } catch {
    return null;
  }
}

function runTypecheck(projectDir: string): { pass: boolean; output: string } {
  const tsc = findBin(projectDir, 'tsc');
  if (!tsc) return { pass: true, output: 'tsc not found, skipping typecheck' };

  try {
    const output = execSync(`${tsc} --noEmit`, {
      cwd: projectDir,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return { pass: true, output };
  } catch (err: unknown) {
    const output = err instanceof Error && 'stdout' in err
      ? String((err as any).stdout) + String((err as any).stderr)
      : String(err);
    return { pass: false, output };
  }
}

function runAstGrep(projectDir: string): { pass: boolean; output: string; violations: Violation[] } {
  const sgconfig = join(projectDir, 'sgconfig.yml');
  if (!existsSync(sgconfig)) {
    return { pass: true, output: 'No sgconfig.yml found, skipping ast-grep', violations: [] };
  }

  const astGrep = findBin(projectDir, 'ast-grep');
  if (!astGrep) {
    return { pass: true, output: 'ast-grep not found, skipping', violations: [] };
  }

  try {
    const output = execSync(`${astGrep} scan --json`, {
      cwd: projectDir,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    // Parse JSON output for violations
    const violations: Violation[] = [];
    try {
      const results = JSON.parse(output);
      if (Array.isArray(results)) {
        for (const result of results) {
          violations.push({
            file: result.file ?? 'unknown',
            line: result.range?.start?.line ?? 0,
            rule: result.ruleId ?? 'unknown',
            message: result.message ?? 'ast-grep violation',
          });
        }
      }
    } catch {
      // Non-JSON output means no violations
    }

    return { pass: violations.length === 0, output, violations };
  } catch (err: unknown) {
    const output = err instanceof Error && 'stdout' in err
      ? String((err as any).stdout) + String((err as any).stderr)
      : String(err);

    // Try to parse violations from error output
    const violations: Violation[] = [];
    try {
      const results = JSON.parse(String((err as any).stdout));
      if (Array.isArray(results)) {
        for (const result of results) {
          violations.push({
            file: result.file ?? 'unknown',
            line: result.range?.start?.line ?? 0,
            rule: result.ruleId ?? 'unknown',
            message: result.message ?? 'ast-grep violation',
          });
        }
      }
    } catch {
      // Can't parse, treat as general failure
    }

    return { pass: false, output, violations };
  }
}

export function enforce(projectDir: string): EnforceResult {
  const typecheck = runTypecheck(projectDir);
  const astgrep = runAstGrep(projectDir);

  const violations: Violation[] = [...astgrep.violations];

  // Parse tsc output into violations
  if (!typecheck.pass) {
    const lines = typecheck.output.split('\n');
    for (const line of lines) {
      const match = line.match(/^(.+)\((\d+),\d+\):\s*error\s+(\w+):\s*(.+)$/);
      if (match) {
        violations.push({
          file: match[1],
          line: parseInt(match[2], 10),
          rule: match[3],
          message: match[4],
        });
      }
    }
  }

  return {
    pass: typecheck.pass && astgrep.pass,
    violations,
    typecheckOutput: typecheck.output,
    astgrepOutput: astgrep.output,
  };
}
