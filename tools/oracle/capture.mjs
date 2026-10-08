#!/usr/bin/env node
// Capture the exact TypeScript 7 CLI behavior before generating expectations.
// This script is tooling, not a TypeScript checker implementation.
import { createHash } from 'node:crypto';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const manifest = JSON.parse(readFileSync(join(root, 'tests/oracle/manifest.json'), 'utf8'));
const baseline = JSON.parse(readFileSync(join(root, 'bench/manifests/baselines.json'), 'utf8'));
const binary = process.env.TSODIN_TSC;
const output = process.env.TSODIN_ORACLE_OUTPUT || join(root, 'build/oracle-capture');
if (!binary) throw new Error('Set TSODIN_TSC to the exact installed TypeScript 7 executable');
if (manifest.oracleVersion !== baseline.primaryOracle.version) throw new Error('Oracle version drift');
if (manifest.schemaVersion !== 1) throw new Error('Unknown oracle manifest schema');

function exec(args, cwd) {
  const r = spawnSync(binary, args, { cwd, encoding: 'utf8', timeout: 60000 });
  if (r.error || r.signal || r.status === null) {
    throw new Error('TypeScript compiler could not complete: ' + String(r.error || r.signal || r.status));
  }
  return { exitCode: r.status, stdout: r.stdout, stderr: r.stderr };
}
function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}
const versionRun = exec(['--version'], root);
if (versionRun.exitCode !== 0 || !versionRun.stdout.includes(baseline.primaryOracle.version)) {
  throw new Error('Pinned TypeScript version mismatch: ' + versionRun.stdout + versionRun.stderr);
}

mkdirSync(output, { recursive: true });
const summary = [];
for (const entry of manifest.projects) {
  if (!/^[a-z0-9-]+$/.test(entry.id)) throw new Error('Unsafe oracle case id');
  const cwd = resolve(root, entry.path);
  if (cwd !== join(root, entry.path)) throw new Error('Unexpected case path');
  const arguments_ = ['-p', 'tsconfig.json', '--noEmit', '--pretty', 'false', '--incremental', 'false', '--singleThreaded'];
  const result = exec(arguments_, cwd);
  if (entry.expectDiagnostics && result.exitCode === 0) throw new Error(entry.id + ': expected diagnostics but got success');
  if (!entry.expectDiagnostics && result.exitCode !== 0) throw new Error(entry.id + ': unexpected compiler failure');
  if (result.exitCode !== 0 && result.stdout.trim().length === 0) throw new Error(entry.id + ': compiler failed without captured diagnostics');
  const hashes = Object.fromEntries(entry.files.map(p => [p, sha256(join(cwd, p))]));
  const record = {
    schemaVersion: 1,
    project: entry.id,
    reference: baseline.primaryOracle,
    versionText: versionRun.stdout.trim(),
    arguments: arguments_,
    inputSha256: hashes,
    expectDiagnostics: entry.expectDiagnostics,
    result
  };
  writeFileSync(join(output, entry.id + '.json'), JSON.stringify(record, null, 2) + '\n');
  console.log(entry.id + ': exit=' + result.exitCode + ', outputBytes=' + result.stdout.length);
  summary.push({ project: entry.id, exitCode: result.exitCode, inputSha256: hashes });
}
writeFileSync(join(output, 'summary.json'), JSON.stringify({
  schemaVersion: 1,
  oracleVersion: manifest.oracleVersion,
  cases: summary
}, null, 2) + '\n');
console.log('Captured ' + summary.length + ' oracle projects (not yet frozen goldens).');
