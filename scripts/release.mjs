#!/usr/bin/env node
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { parseVersion, releaseFiles } from './version.mjs';

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

try {
  const [releaseType, versionType = 'patch', ...extra] = process.argv.slice(2);
  if (extra.length || !['prod', 'dev'].includes(releaseType) || !['patch', 'minor', 'major'].includes(versionType)) {
    throw new Error('Usage: node scripts/release.mjs <prod|dev> [patch|minor|major]');
  }
  const root = git('rev-parse', '--show-toplevel');
  process.chdir(root);
  if (git('branch', '--show-current') !== 'main') throw new Error('Releases must be created on main');
  if (git('status', '--porcelain', '--untracked-files=all')) {
    throw new Error('Working tree and index must be clean; commit your changes (including CHANGELOG.md) first');
  }
  const { version, files } = releaseFiles(root, releaseType, versionType);
  const tag = `v${version}`;
  // Check both local and remote refs before writing anything. Never replace tags.
  const tags = new Set(git('tag', '--list', 'v*').split('\n'));
  const remoteTags = git('ls-remote', '--tags', 'origin');
  for (const line of remoteTags.split('\n')) {
    const ref = line.split('\t')[1];
    if (ref) tags.add(ref.replace(/^refs\/tags\//, '').replace(/\^\{\}$/, ''));
  }
  if (tags.has(tag)) throw new Error(`${tag} already exists; releases are immutable`);
  const { parts, beta } = parseVersion(version);
  if (beta !== null) {
    const base = parts.join('.');
    if (tags.has(`v${base}`)) throw new Error(`${base} is already a production release`);
    for (const existing of tags) {
      const match = /^v(.+)b(0|[1-9]\d*)$/.exec(existing);
      if (match && match[1] === base && BigInt(match[2]) >= beta) {
        throw new Error(`Refusing to reuse or decrease a pre-release number (${existing} already exists)`);
      }
    }
  }
  for (const [path, text] of files) writeFileSync(join(root, path), text);
  git('add', '--', ...files.keys());
  git('commit', '-m', `[release] ${version}`);
  git('tag', '-a', tag, '-m', `[release] ${version}`);
  console.log(`Created [release] ${version} and annotated tag ${tag}. Nothing has been pushed.`);
  console.log(`Repository owner: review, then run git push --atomic origin main ${tag}`);
} catch (error) {
  console.error(`Release failed: ${error.stderr?.toString().trim() || error.message}`);
  console.error('No push was attempted. If Git failed after staging/committing, inspect git status and git log before retrying.');
  process.exitCode = 1;
}
