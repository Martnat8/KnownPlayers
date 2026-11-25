import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('./backup-to-json.mjs', import.meta.url));
const hex = (value) => Buffer.from(value, 'hex');

function text(value) {
  const bytes = Buffer.from(value, 'utf8');
  assert(bytes.length < 24);
  return Buffer.concat([Buffer.from([0x60 + bytes.length]), bytes]);
}

// RFC 8949 bytes for a portable snapshot, including UTF-8, three float widths,
// a wide timestamp, and an indefinite-length map.
const snapshot = Buffer.concat([
  hex('a3'), text('version'), hex('01'), text('created'), hex('1b000000006553f100'),
  text('sections'), hex('a2'),
  text('settings'), hex('a2'),
  text('showMinimapButton'), hex('f4'),
  text('nameplateCategoryColors'), hex('a1'), text('manual'), hex('83f93800fa3e800000fb3fe8000000000000'),
  text('players'), hex('a1'), text('records'), hex('bf'),
  text('Synthetic-CAMWOW1'), hex('a2'), text('note'), text('Synthetic café'),
  text('favorite'), hex('f5ff'),
]);

function sandbox(t) {
  const cwd = mkdtempSync(join(tmpdir(), 'knownplayers-json-'));
  t.after(() => rmSync(cwd, { recursive: true, force: true }));
  return cwd;
}

function run(cwd, args, input) {
  const result = spawnSync(process.execPath, [script, ...args], { cwd, input, encoding: 'utf8' });
  assert.ifError(result.error);
  return result;
}

test('converts a wrapped backup to adjacent, indented JSON and preserves the input', (t) => {
  const cwd = sandbox(t);
  const source = 'KnownPlayers:1:\r\n' + snapshot.toString('base64').match(/.{1,40}/g).join('\r\n') + '\r\n';
  const input = join(cwd, 'Saved history.txt');
  writeFileSync(input, '\uFEFF' + source);
  const result = run(cwd, ['Saved history.txt']);
  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stdout, /Synthetic/);
  assert.equal(readFileSync(input, 'utf8'), '\uFEFF' + source);
  const json = readFileSync(join(cwd, 'Saved history.json'), 'utf8');
  assert.match(json, /\n {2}"version": 1,/);
  assert.deepEqual(JSON.parse(json), {
    version: 1,
    created: 1700000000,
    sections: {
      settings: { showMinimapButton: false, nameplateCategoryColors: { manual: [0.5, 0.25, 0.75] } },
      players: { records: { 'Synthetic-CAMWOW1': { note: 'Synthetic café', favorite: true } } },
    },
  });
});

test('supports an explicit output file and never overwrites it', (t) => {
  const cwd = sandbox(t);
  writeFileSync(join(cwd, 'backup.txt'), 'KnownPlayers:1:' + snapshot.toString('base64'));
  const result = run(cwd, ['backup.txt', 'readable.json']);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(join(cwd, 'backup.json')), false);

  const output = join(cwd, 'readable.json');
  const original = readFileSync(output, 'utf8');
  const retry = run(cwd, ['backup.txt', 'readable.json']);
  assert.equal(retry.status, 1);
  assert.match(retry.stderr, /already exists/);
  assert.equal(readFileSync(output, 'utf8'), original);
});

test('accepts piped backup text without an intermediate file', (t) => {
  const cwd = sandbox(t);
  const result = run(cwd, ['-', 'readable.json'], 'KnownPlayers:1:' + snapshot.toString('base64') + '\n');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(readFileSync(join(cwd, 'readable.json'), 'utf8')).version, 1);
});

test('rejects malformed, truncated, and unsupported backups before creating JSON', (t) => {
  const cwd = sandbox(t);
  const cases = [
    ['KnownPlayers:1:A', /invalid Base64/],
    ['KnownPlayers:2:' + snapshot.toString('base64'), /unsupported/],
    ['KnownPlayers:1:' + snapshot.subarray(0, -1).toString('base64'), /truncated/],
    ['KnownPlayers:1:' + Buffer.concat([snapshot, hex('00')]).toString('base64'), /trailing data/],
    ['KnownPlayers:1:' + hex('a0').toString('base64'), /not a KnownPlayers/],
    ['KnownPlayers:1:' + 'A'.repeat(4 * 1024 * 1024), /4 MiB export limit/],
  ];
  for (const [source, message] of cases) {
    writeFileSync(join(cwd, 'backup.txt'), source);
    const result = run(cwd, ['backup.txt']);
    assert.equal(result.status, 1);
    assert.match(result.stderr, message);
    assert.equal(existsSync(join(cwd, 'backup.json')), false);
  }
});
