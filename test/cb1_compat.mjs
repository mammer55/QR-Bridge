// Checks that the page's cb1 block and ClipBridge's shared/cbcrypt.py agree.
//
//   node test/cb1_compat.mjs
//
// Pulls the crypto block out of index.html, runs it in Node's WebCrypto, and
// trades clips both ways with the Python module through ClipBridge's Mac venv
// (CLIPBRIDGE=/path/to/ClipBridge to point elsewhere). Uses a throwaway
// passphrase and never touches Supabase.

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, '..', 'index.html'), 'utf8');
const block = html.split('// --- cb1 crypto')[1].split('// --- end cb1 crypto ---')[0]
  .replace(/^[^\n]*\n/, '');
const cb = new Function(block + '\nreturn { cbDeriveKey, cbEncrypt, cbDecrypt, cbNormalize };')();

const repo = process.env.CLIPBRIDGE || join(homedir(), 'Code', 'ClipBridge');
const py = join(repo, 'mac', '.venv', 'bin', 'python3');
const pyRun = (code, input) => execFileSync(py, ['-c',
  `import sys, json; sys.path.insert(0, ${JSON.stringify(join(repo, 'shared'))}); import cbcrypt\n` + code],
  { input: JSON.stringify(input), encoding: 'utf8' }).trim();

const PHRASE = 'Abacus  flannel orbit\tvanilla canyon';   // spacing and case must not matter
const TEXT = 'السلام عليكم\nline two ✓ "quotes" & <tags>';
let failed = 0;
const check = (name, ok) => { console.log((ok ? 'ok   ' : 'FAIL ') + name); if (!ok) failed++; };

const key = await cb.cbDeriveKey(PHRASE);

// browser to Python
const fromPage = await cb.cbEncrypt(key, TEXT, 'pc-to-mac');
const pyRead = pyRun(`a = json.load(sys.stdin); print(json.dumps(cbcrypt.decrypt(cbcrypt.derive_key(a['p']), a['c'], a['s'])))`,
  { p: 'abacus flannel orbit vanilla canyon', c: fromPage, s: 'pc-to-mac' });
check('page clip opens in Python', JSON.parse(pyRead) === TEXT);

// Python to browser
const fromPy = pyRun(`a = json.load(sys.stdin); print(cbcrypt.encrypt(cbcrypt.derive_key(a['p']), a['t'], 'mac-to-pc'))`,
  { p: PHRASE, t: TEXT });
check('Python clip opens in the page', await cb.cbDecrypt(key, fromPy, 'mac-to-pc') === TEXT);

// refusals
check('wrong source refused', await cb.cbDecrypt(key, fromPy, 'pc-to-mac') === null);
check('wrong passphrase refused', await cb.cbDecrypt(await cb.cbDeriveKey('abacus flannel orbit vanilla canon'), fromPy, 'mac-to-pc') === null);
const flipped = fromPy.slice(0, -3) + (fromPy.at(-3) === 'A' ? 'B' : 'A') + fromPy.slice(-2);
check('tampered clip refused', await cb.cbDecrypt(key, flipped, 'mac-to-pc') === null);
check('plaintext refused', await cb.cbDecrypt(key, 'rm -rf ~', 'pc-to-mac') === null);
const stale = pyRun(`import time, unittest.mock as m
a = json.load(sys.stdin)
with m.patch('time.time', return_value=time.time() - 31 * 60):
    print(cbcrypt.encrypt(cbcrypt.derive_key(a['p']), 'old', 'pc-to-mac'))`, { p: PHRASE });
check('31 minute old replay refused by the page', await cb.cbDecrypt(key, stale, 'pc-to-mac') === null);
const pyStale = pyRun(`a = json.load(sys.stdin); print(json.dumps(cbcrypt.decrypt(cbcrypt.derive_key(a['p']), a['c'], 'pc-to-mac')))`,
  { p: PHRASE, c: stale });
check('31 minute old replay refused by Python', JSON.parse(pyStale) === null);

console.log(failed ? `${failed} failed` : 'all passed');
process.exit(failed ? 1 : 0);
