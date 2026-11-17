import assert from 'node:assert/strict';
import { test } from 'node:test';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { METADATA, nextVersion, parseVersion, releaseFiles, versionFiles } from './version.mjs';

const source = fileURLToPath(new URL('../', import.meta.url));
const workflow = readFileSync(join(source, '.github/workflows/release.yml'), 'utf8');
function run(cwd, command, args, env = {}) {
  return spawnSync(command, args, { cwd, encoding: 'utf8', env: { ...process.env, ...env } });
}
function ok(result) {
  assert.equal(result.status, 0, result.stderr || result.stdout || result.error?.message);
  return result.stdout.trim();
}
function git(root, ...args) { return ok(run(root, 'git', args)); }
function fixture(t, version = '0.1.7') {
  const directory = mkdtempSync(join(tmpdir(), 'knownplayers-release-'));
  const root = join(directory, 'work');
  mkdirSync(root);
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  for (const path of ['scripts', '.githooks', '.github']) cpSync(join(source, path), join(root, path), { recursive: true });
  mkdirSync(join(root, 'KnownPlayers'));
  writeFileSync(join(root, 'VERSION'), `${version}\n`);
  writeFileSync(join(root, 'KnownPlayers/KnownPlayers.toc'), `## Version: ${version}\n`);
  writeFileSync(join(root, 'KnownPlayers/Core.lua'), `local ADDON_VERSION = "${version}"\n`);
  writeFileSync(join(root, 'README.md'), `# KnownPlayers\n\n**Version:** ${version}  \n`);
  writeFileSync(join(root, 'KnownPlayers/README.txt'), `KnownPlayers ${version} (WoW Forever, Interface 16001)\nHistorical: 0.1.0\n`);
  writeFileSync(join(root, 'CHANGELOG.md'), `# Changelog\n\n## [Unreleased]\n\n- Improve release tooling.\n\n## [${version}]\n\n- Existing release.\n`);
  git(root, 'init', '-b', 'main');
  git(root, 'config', 'user.name', 'Release Test');
  git(root, 'config', 'user.email', 'release-test@example.invalid');
  git(root, 'config', 'commit.gpgsign', 'false');
  git(root, 'config', 'tag.gpgsign', 'false');
  git(root, 'config', 'core.hooksPath', join(root, '.githooks'));
  git(root, 'add', '.');
  git(root, 'commit', '-m', 'Initial fixture');
  const remote = join(directory, 'remote.git');
  git(root, 'init', '--bare', remote);
  git(root, 'remote', 'add', 'origin', remote);
  git(root, 'push', '-u', 'origin', 'main');
  return root;
}
function release(root, ...args) { return run(root, process.execPath, ['scripts/release.mjs', ...args]); }
function commitNotes(root, message = 'Document next release') {
  const path = join(root, 'CHANGELOG.md');
  writeFileSync(path, readFileSync(path, 'utf8').replace('## [Unreleased]', '## [Unreleased]\n\n- Another improvement.'));
  git(root, 'add', 'CHANGELOG.md');
  git(root, 'commit', '-m', message);
}
function unchangedFailure(root, args, pattern) {
  const before = git(root, 'rev-parse', 'HEAD');
  const status = git(root, 'status', '--porcelain');
  const result = release(root, ...args);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, pattern);
  assert.equal(git(root, 'rev-parse', 'HEAD'), before);
  assert.equal(git(root, 'status', '--porcelain'), status);
}
function workflowStep(name) {
  const section = workflow.split(`      - name: ${name}\n`)[1];
  assert.ok(section, `Missing workflow step ${name}`);
  const body = section.split('        run: |\n')[1];
  assert.ok(body, `Missing run block for ${name}`);
  const lines = [];
  for (const line of body.split('\n')) {
    if (line && !line.startsWith('          ')) break;
    lines.push(line.slice(10));
  }
  return lines.join('\n');
}
function prCheck(root, base, head = 'HEAD') {
  return run(root, 'bash', ['-c', workflowStep('Reject version changes in pull requests')], {
    BASE: base, HEAD: git(root, 'rev-parse', head),
  });
}

test('all production bumps and initial beta numbers', () => {
  for (const [type, core] of [['patch', '1.2.4'], ['minor', '1.3.0'], ['major', '2.0.0']]) {
    assert.equal(nextVersion('1.2.3', 'prod', type), core);
    assert.equal(nextVersion('1.2.3', 'dev', type), `${core}b0`);
  }
  assert.equal(nextVersion('0.1.7', 'prod'), '0.1.8');
  assert.equal(nextVersion('0.1.7', 'dev'), '0.1.8b0');
});

test('pre-releases ignore bump type; beta numbers increase numerically', () => {
  for (const type of ['patch', 'minor', 'major']) {
    assert.equal(nextVersion('0.1.14b3', 'prod', type), '0.1.14');
    assert.equal(nextVersion('0.1.14b3', 'dev', type), '0.1.14b4');
  }
  assert.equal(nextVersion('0.1.14b9', 'dev'), '0.1.14b10');
  assert.equal(nextVersion('0.1.14b9007199254740992', 'dev'), '0.1.14b9007199254740993');
});

test('reject invalid versions and arguments', () => {
  assert.throws(() => parseVersion('1.2.3\n'), /Invalid version/);
  for (const version of ['v1.2.3', '1.2', '01.2.3', '1.02.3', '1.2.03', '1.2.3b01', '1.2.3-beta.0', '1.2.3b-1', '1.2.3b', '1.2.3+meta']) {
    assert.throws(() => parseVersion(version), /Invalid version/);
  }
  assert.throws(() => nextVersion('1.2.3', 'beta'), /Usage/);
  assert.throws(() => nextVersion('1.2.3b0', 'dev', 'invalid'), /Usage/);
});

test('release end-to-end updates all metadata, notes, commit and annotated tag without pushing', (t) => {
  const root = fixture(t);
  const base = git(root, 'rev-parse', 'HEAD');
  ok(release(root, 'dev', 'minor'));
  assert.equal(versionFiles(root).version, '0.2.0b0');
  const log = readFileSync(join(root, 'CHANGELOG.md'), 'utf8');
  assert.match(log, /## \[Unreleased\]\n\n## \[0\.2\.0b0\] - \d{4}-\d{2}-\d{2}\n\n- Improve release tooling\./);
  assert.match(log, /## \[0\.1\.7\]\n\n- Existing release\./);
  assert.match(readFileSync(join(root, 'KnownPlayers/README.txt'), 'utf8'), /Historical: 0\.1\.0/);
  assert.equal(git(root, 'log', '-1', '--format=%s'), '[release] 0.2.0b0');
  assert.equal(git(root, 'cat-file', '-t', 'v0.2.0b0'), 'tag');
  assert.equal(git(root, 'rev-parse', 'v0.2.0b0^{}'), git(root, 'rev-parse', 'HEAD'));
  assert.equal(git(root, 'status', '--porcelain'), '');
  assert.equal(git(root, 'ls-remote', '--tags', 'origin'), '');
  assert.equal(git(root, 'ls-remote', 'origin', 'refs/heads/main').split('\t')[0], base);
  ok(run(root, process.execPath, ['scripts/check-version.mjs'], { TAG: 'v0.2.0b0' }));
  assert.notEqual(run(root, process.execPath, ['scripts/check-version.mjs'], { TAG: 'v0.2.0' }).status, 0);
  commitNotes(root);
  ok(release(root, 'dev', 'major'));
  assert.equal(versionFiles(root).version, '0.2.0b1');
  commitNotes(root);
  ok(release(root, 'prod', 'minor'));
  assert.equal(versionFiles(root).version, '0.2.0');
  ok(run(root, 'bash', ['scripts/check-changelog.sh', '--range', base, 'HEAD']));
  unchangedFailure(root, ['prod'], /at least one bullet/);
});

test('production releases bump and commit by default', (t) => {
  const root = fixture(t);
  ok(release(root, 'prod'));
  assert.equal(versionFiles(root).version, '0.1.8');
  assert.equal(git(root, 'log', '-1', '--format=%s'), '[release] 0.1.8');
  assert.equal(git(root, 'cat-file', '-t', 'v0.1.8'), 'tag');
});

test('argument and dirty-tree failures do not create commits or tags', (t) => {
  const root = fixture(t);
  for (const args of [[], ['beta'], ['prod', 'invalid'], ['dev', 'patch', 'extra']]) unchangedFailure(root, args, /Usage/);
  writeFileSync(join(root, 'untracked'), 'unfinished work\n');
  unchangedFailure(root, ['dev'], /must be clean/);
  git(root, 'add', 'untracked');
  unchangedFailure(root, ['dev'], /must be clean/);
  git(root, 'reset', '--hard', 'HEAD');
  git(root, 'checkout', '-b', 'contribution');
  unchangedFailure(root, ['prod'], /on main/);
});

test('inconsistent metadata and empty or duplicate release notes fail before edits', (t) => {
  const root = fixture(t);
  for (const [path] of METADATA) {
    const original = readFileSync(join(root, path), 'utf8');
    writeFileSync(join(root, path), original.replace('0.1.7', '0.1.6'));
    assert.throws(() => releaseFiles(root, 'dev'), /must match VERSION/);
    writeFileSync(join(root, path), original);
  }
  const logPath = join(root, 'CHANGELOG.md');
  writeFileSync(logPath, '# Changelog\n\n## [Unreleased]\n\n## [0.1.7]\n\n- Historical note.\n');
  assert.throws(() => releaseFiles(root, 'dev'), /at least one bullet/);
  writeFileSync(logPath, '# Changelog\n\n## [Unreleased]\n\n- Notes.\n\n## [0.1.8]\n\n- Already released.\n');
  assert.throws(() => releaseFiles(root, 'prod'), /already contains/);
  git(root, 'add', 'CHANGELOG.md');
  git(root, 'commit', '-m', 'Duplicate notes fixture');
  unchangedFailure(root, ['prod'], /already contains/);
});

test('local and remote release tags are immutable, including remotely deleted local refs', (t) => {
  const root = fixture(t);
  git(root, 'tag', '-a', 'v0.1.8', '-m', 'Already published');
  unchangedFailure(root, ['prod'], /already exists/);
  git(root, 'push', 'origin', 'v0.1.8');
  git(root, 'tag', '-d', 'v0.1.8');
  unchangedFailure(root, ['prod'], /already exists/);
  unchangedFailure(root, ['dev'], /already a production release/);
});

test('beta sequence cannot decrease relative to local or remote tags', (t) => {
  const root = fixture(t, '0.1.8b2');
  git(root, 'tag', 'v0.1.8b4');
  git(root, 'push', 'origin', 'v0.1.8b4');
  git(root, 'tag', '-d', 'v0.1.8b4');
  unchangedFailure(root, ['dev', 'major'], /decrease a pre-release/);
});

test('unreachable origin fails closed before changing any files', (t) => {
  const root = fixture(t);
  git(root, 'remote', 'set-url', 'origin', join(root, 'missing-remote'));
  unchangedFailure(root, ['dev'], /Release failed/);
});

test('shared hook checks the index, not unstaged notes, and rejects changelog deletion', (t) => {
  const root = fixture(t);
  writeFileSync(join(root, 'feature'), 'new feature\n');
  git(root, 'add', 'feature');
  assert.notEqual(run(root, 'git', ['commit', '-m', 'Missing changelog']).status, 0);
  const path = join(root, 'CHANGELOG.md');
  writeFileSync(path, `${readFileSync(path, 'utf8')}\n- Unstaged notes.\n`);
  assert.notEqual(run(root, 'git', ['commit', '-m', 'Unstaged changelog']).status, 0);
  git(root, 'add', 'CHANGELOG.md');
  git(root, 'commit', '-m', 'Document feature');
  git(root, 'rm', 'CHANGELOG.md');
  assert.notEqual(run(root, 'git', ['commit', '-m', 'Delete changelog']).status, 0);
});

test('CI range check handles an initial push with no base commit', (t) => {
  const root = fixture(t);
  ok(run(root, 'bash', ['scripts/check-changelog.sh', '--range', '0'.repeat(40), 'HEAD']));
});

test('CI range checks each commit, not just the combined PR diff', (t) => {
  const root = fixture(t);
  const base = git(root, 'rev-parse', 'HEAD');
  writeFileSync(join(root, 'feature'), 'undocumented\n');
  git(root, 'add', 'feature');
  git(root, '-c', 'core.hooksPath=/dev/null', 'commit', '-m', 'Bypass hook');
  commitNotes(root);
  const result = run(root, 'bash', ['scripts/check-changelog.sh', '--range', base, 'HEAD']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /each commit/);
});

test('PR guard allows unchanged versions and initial VERSION adoption', (t) => {
  const root = fixture(t);
  const base = git(root, 'rev-parse', 'HEAD');
  commitNotes(root);
  ok(prCheck(root, base));
  git(root, 'rm', 'VERSION');
  commitNotes(root, 'Simulate pre-tooling base');
  const legacy = git(root, 'rev-parse', 'HEAD');
  writeFileSync(join(root, 'VERSION'), '0.1.7\n');
  git(root, 'add', 'VERSION');
  commitNotes(root, 'Adopt VERSION without a release');
  ok(prCheck(root, legacy));
});

test('PR guard rejects changes to VERSION or any version-bearing metadata', (t) => {
  const root = fixture(t);
  const base = git(root, 'rev-parse', 'HEAD');
  for (const path of ['VERSION', ...METADATA.map(([path]) => path)]) {
    writeFileSync(join(root, path), readFileSync(join(root, path), 'utf8').replace('0.1.7', '0.1.8b0'));
    git(root, 'add', path);
    commitNotes(root, `Change ${path}`);
    const result = prCheck(root, base);
    assert.notEqual(result.status, 0, path);
    assert.match(result.stdout, /must remain at 0\.1\.7/);
    git(root, 'reset', '--hard', base);
  }
});

test('workflow authorizes owner tags and uses the full changelog and beta flag', (t) => {
  const root = fixture(t);
  const auth = workflowStep('Authorize and validate release tag');
  ok(run(root, 'bash', ['-c', auth], { TAG: 'v0.1.7', ACTOR: 'owner', OWNER: 'owner' }));
  assert.notEqual(run(root, 'bash', ['-c', auth], { TAG: 'v0.1.7', ACTOR: 'contributor', OWNER: 'owner' }).status, 0);
  assert.match(workflow, /if: github.event_name == 'push' && startsWith\(github.ref, 'refs\/tags\/v'\) && github.actor == github.repository_owner/);
  const publish = workflowStep('Publish GitHub release');
  // Substitute gh with a shell function; no GitHub calls or release side effects.
  const probe = 'gh() { printf "%s\\n" "$@"; }\n' + publish;
  const prod = ok(run(root, 'bash', ['-c', probe], { TAG: 'v0.1.7' }));
  const dev = ok(run(root, 'bash', ['-c', probe], { TAG: 'v0.1.8b0' }));
  assert.match(prod, /--notes-file\nCHANGELOG\.md/);
  assert.match(prod, /--verify-tag/);
  assert.doesNotMatch(prod, /--prerelease/);
  assert.match(dev, /--prerelease/);
  assert.doesNotMatch(publish, /--generate-notes|--clobber|release edit/);
});
