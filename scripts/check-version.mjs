#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { versionFiles } from './version.mjs';

try {
  const { version } = versionFiles(process.cwd());
  const changelog = readFileSync('CHANGELOG.md', 'utf8');
  if (!/^## \[Unreleased\]$/m.test(changelog)) throw new Error('CHANGELOG.md must have an [Unreleased] section');
  const versions = [...changelog.matchAll(/^## \[?([^\]\s]+)\]?(?: - .*|[ \t]*)$/gm)];
  if (!versions.some((match) => match[1] === version)) throw new Error(`CHANGELOG.md is missing release ${version}`);
  if (process.env.TAG && process.env.TAG !== `v${version}`) {
    throw new Error(`Tag ${process.env.TAG} does not match VERSION (${version})`);
  }
  console.log(`Version metadata and changelog match ${version}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
