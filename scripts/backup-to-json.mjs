import { open, readFile, stat, unlink } from 'node:fs/promises';
import { extname } from 'node:path';

const MAX_EXPORT_BYTES = 4 * 1024 * 1024;
// Leave room for line wrapping and trailing newlines in saved or piped text.
const MAX_SOURCE_BYTES = MAX_EXPORT_BYTES + 256 * 1024;
const MAX_DEPTH = 16;
const FORMAT = 1;
const USAGE = 'Usage: node scripts/backup-to-json.mjs <backup.txt> [output.json]\n'
  + '       node scripts/backup-to-json.mjs - <output.json>';
const utf8 = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });

// Read the CBOR values used by portable KnownPlayers snapshots (RFC 8949).
class BackupDecoder {
  constructor(bytes) {
    this.bytes = bytes;
    this.offset = 0;
  }

  take(length) {
    if (length > this.bytes.length - this.offset) throw new Error('The backup payload is truncated.');
    const start = this.offset;
    this.offset += length;
    return this.bytes.subarray(start, this.offset);
  }

  argument(info) {
    if (info < 24) return info;
    if (info === 31) return undefined;
    if (info > 27) throw new Error('Invalid CBOR length or integer.');
    const size = 2 ** (info - 24);
    const bytes = this.take(size);
    const number = size === 8 ? Number(bytes.readBigUInt64BE()) : bytes.readUIntBE(0, size);
    if (!Number.isSafeInteger(number)) throw new Error('A CBOR integer exceeds the JSON precision limit.');
    return number;
  }

  simple(info) {
    if (info === 20) return false;
    if (info === 21) return true;
    if (info === 22) return null;
    let value;
    if (info === 25) {
      const bits = this.take(2).readUInt16BE();
      const exponent = (bits >> 10) & 31;
      const fraction = bits & 1023;
      if (exponent < 31) {
        const sign = bits & 0x8000 ? -1 : 1;
        value = exponent === 0
          ? sign * fraction * 2 ** -24
          : sign * (1 + fraction / 1024) * 2 ** (exponent - 15);
      }
    } else if (info === 26) {
      value = this.take(4).readFloatBE();
    } else if (info === 27) {
      value = this.take(8).readDoubleBE();
    }
    if (!Number.isFinite(value)) throw new Error('The backup contains a CBOR value without a JSON equivalent.');
    return value;
  }

  container(type, length, depth) {
    const result = type === 4 ? [] : Object.create(null);
    for (let index = 0; length === undefined || index < length; index++) {
      if (length === undefined && this.bytes[this.offset] === 0xff) {
        this.offset++;
        break;
      }
      if (type === 4) {
        result.push(this.value(depth + 1));
      } else {
        const key = this.value(depth + 1);
        if (typeof key !== 'string' && !Number.isSafeInteger(key)) {
          throw new Error('The backup contains an unsupported map key.');
        }
        if (Object.hasOwn(result, key)) throw new Error('The backup contains duplicate map keys.');
        result[key] = this.value(depth + 1);
      }
    }
    return result;
  }

  value(depth = 0) {
    if (depth > MAX_DEPTH) throw new Error('The backup is nested too deeply.');
    const head = this.take(1)[0];
    const type = head >> 5;
    const info = head & 31;
    if (type === 7) return this.simple(info);
    const argument = this.argument(info);
    if (type === 4 || type === 5) return this.container(type, argument, depth);
    if (argument === undefined) throw new Error('Unsupported CBOR value with an indefinite length.');
    if (type === 0) return argument;
    if (type === 1 && argument < Number.MAX_SAFE_INTEGER) return -1 - argument;
    if (type === 2 || type === 3) return utf8.decode(this.take(argument));
    if (type === 6 && argument === 55799 && depth === 0) return this.value(depth + 1);
    throw new Error('The backup contains an unsupported CBOR value.');
  }
}

function isMap(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function hasBackupSection(sections) {
  return ['settings', 'players', 'npcs'].some((key) => {
    const section = sections[key];
    return isMap(section) || (Array.isArray(section) && section.length === 0);
  });
}

function decodeBackup(text) {
  const compact = text.replace(/\s+/g, '');
  if (compact.length > MAX_EXPORT_BYTES) throw new Error('The backup exceeds the 4 MiB export limit.');
  const match = /^KnownPlayers:(\d+):([A-Za-z0-9+/]+={0,2})$/.exec(compact);
  if (!match) throw new Error('Select a text file containing a complete KnownPlayers export.');
  const [, version, payload] = match;
  if (Number(version) !== FORMAT) throw new Error('This KnownPlayers export format is unsupported.');
  const bytes = Buffer.from(payload, 'base64');
  const canonical = bytes.toString('base64');
  if (payload !== canonical && payload !== canonical.replace(/=+$/, '')) {
    throw new Error('The backup has invalid Base64 data.');
  }

  const decoder = new BackupDecoder(bytes);
  const snapshot = decoder.value();
  if (decoder.offset !== bytes.length) throw new Error('The backup payload has trailing data.');
  if (!isMap(snapshot) || snapshot.version !== FORMAT || !Number.isFinite(snapshot.created)
      || snapshot.created < 0 || snapshot.created > Number.MAX_SAFE_INTEGER || !isMap(snapshot.sections)
      || !hasBackupSection(snapshot.sections)) {
    throw new Error('The payload is not a KnownPlayers backup snapshot.');
  }
  return snapshot;
}

async function readSource(input) {
  if (input === '-') {
    const chunks = [];
    let size = 0;
    for await (const chunk of process.stdin) {
      size += chunk.length;
      if (size > MAX_SOURCE_BYTES) throw new Error('The backup text is too large.');
      chunks.push(chunk);
    }
    return Buffer.concat(chunks, size);
  }
  const info = await stat(input);
  if (!info.isFile()) throw new Error('The input must be a text file.');
  if (info.size > MAX_SOURCE_BYTES) throw new Error('The backup text is too large.');
  return readFile(input);
}

async function main(args) {
  if (args.length === 1 && ['--help', '-h'].includes(args[0])) {
    console.log(USAGE);
    return;
  }
  if (args.length < 1 || args.length > 2 || (args[0] === '-' && args.length !== 2)) throw new Error(USAGE);
  const [input, output = input.slice(0, input.length - extname(input).length) + '.json'] = args;
  const source = await readSource(input);
  if (source.length > MAX_SOURCE_BYTES) throw new Error('The backup text is too large.');
  const snapshot = decodeBackup(utf8.decode(source));
  const json = JSON.stringify(snapshot, null, 2) + '\n';
  const destination = await open(output, 'wx', 0o600);
  try {
    try {
      await destination.writeFile(json);
    } finally {
      await destination.close();
    }
  } catch (error) {
    await unlink(output).catch(() => {});
    throw error;
  }
  console.log('Wrote the formatted JSON backup.');
}

try {
  await main(process.argv.slice(2));
} catch (error) {
  let message = error.message;
  if (error.code === 'EEXIST') message = 'The output file already exists. Choose a different name.';
  if (error.code === 'ENOENT') message = 'The input file or output directory was not found.';
  if (error.code === 'ERR_ENCODING_INVALID_ENCODED_DATA') message = 'The backup contains invalid UTF-8 text.';
  console.error(message);
  process.exitCode = 1;
}
