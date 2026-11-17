import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// The project uses SemVer's major/minor/patch rules with a compact bN suffix.
export const VERSION_PATTERN = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:b(0|[1-9]\d*))?$/;
export const METADATA = [
  ['KnownPlayers/KnownPlayers.toc', /^## Version: (\S+)$/m],
  ['KnownPlayers/Core.lua', /^local ADDON_VERSION = "([^"\n]+)"$/m],
  ['README.md', /^\*\*Version:\*\* (\S+)[ \t]*$/m],
  ['KnownPlayers/README.txt', /^KnownPlayers (\S+) \(WoW Forever, Interface 16001\)$/m],
];

export function parseVersion(version) {
  const match = VERSION_PATTERN.exec(version);
  if (!match || match[0] !== version) throw new Error(`Invalid version: ${version}; expected MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCHbN`);
  return { parts: match.slice(1, 4).map(BigInt), beta: match[4] === undefined ? null : BigInt(match[4]) };
}

export function nextVersion(current, releaseType, versionType = 'patch') {
  if (!['prod', 'dev'].includes(releaseType) || !['patch', 'minor', 'major'].includes(versionType)) {
    throw new Error('Usage: node scripts/release.mjs <prod|dev> [patch|minor|major]');
  }
  const { parts, beta } = parseVersion(current);
  if (beta !== null) return `${parts.join('.')}${releaseType === 'dev' ? `b${beta + 1n}` : ''}`;
  const index = { major: 0, minor: 1, patch: 2 }[versionType];
  parts[index] += 1n;
  for (let i = index + 1; i < parts.length; i++) parts[i] = 0n;
  return `${parts.join('.')}${releaseType === 'dev' ? 'b0' : ''}`;
}

export function versionFiles(root) {
  const versionText = readFileSync(join(root, 'VERSION'), 'utf8');
  const version = versionText.trim();
  parseVersion(version);
  if (versionText !== `${version}\n`) throw new Error('VERSION must contain only the version and a newline');
  const files = new Map([['VERSION', versionText]]);
  for (const [path, pattern] of METADATA) {
    const text = readFileSync(join(root, path), 'utf8');
    const matches = [...text.matchAll(new RegExp(pattern.source, 'gm'))];
    if (matches.length !== 1 || matches[0][1] !== version) {
      throw new Error(`${path} version must match VERSION (${version})`);
    }
    files.set(path, text);
  }
  return { version, files };
}

export function releaseFiles(root, releaseType, versionType, date = new Date().toISOString().slice(0, 10)) {
  const { version, files } = versionFiles(root);
  const next = nextVersion(version, releaseType, versionType);
  files.set('VERSION', `${next}\n`);
  for (const [path, pattern] of METADATA) {
    files.set(path, files.get(path).replace(pattern, (line, old) => line.replace(old, next)));
  }
  const changelog = readFileSync(join(root, 'CHANGELOG.md'), 'utf8');
  const unreleased = /^## \[Unreleased\][ \t]*\n([\s\S]*?)(?=^## |$(?![\s\S]))/gm;
  const sections = [...changelog.matchAll(unreleased)];
  if (sections.length !== 1 || !/^\s*[-*] \S/m.test(sections[0][1])) {
    throw new Error('CHANGELOG.md must have one ## [Unreleased] section with at least one bullet describing the release');
  }
  const headings = [...changelog.matchAll(/^## \[?([^\]\s]+)\]?(?: - .*|[ \t]*)$/gm)];
  if (headings.some((match) => match[1] === next)) throw new Error(`CHANGELOG.md already contains ${next}`);
  files.set('CHANGELOG.md', changelog.replace(unreleased, (section, notes) =>
    `## [Unreleased]\n\n## [${next}] - ${date}\n${notes.trimEnd()}\n\n`));
  return { version: next, files };
}
