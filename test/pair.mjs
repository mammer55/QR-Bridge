// Checks the QR pairing handoff in index.html.
//
//   node test/pair.mjs
//
// Pulls the cb1 and pair crypto blocks out of the page and plays both sides:
// a borrowed computer showing a code, a phone sealing its key for it, and
// the people who should get nothing (someone with a photo of the code, a
// different computer, a tampered row). Never touches Supabase.

import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const html = readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', 'index.html'), 'utf8');
const between = (a, b) => html.split(a)[1].split(b)[0].replace(/^[^\n]*\n/, '');
const code = between('// --- cb1 crypto', '// --- end cb1 crypto ---')
  + between('// --- pair crypto', '// --- end pair crypto ---');
const f = new Function(code + '\nreturn { cbDeriveRaw, cbImportKey, cbEncrypt, cbDecrypt, pairNewSession, pairSeal, pairOpen, PAIR_PREFIX };')();

let failed = 0;
const check = (name, ok) => { console.log((ok ? 'ok   ' : 'FAIL ') + name); if (!ok) failed++; };
const same = (a, b) => a && b && a.length === b.length && a.every((x, i) => x === b[i]);

const phoneRaw = await f.cbDeriveRaw('abacus flannel orbit vanilla canyon');
const computer = await f.pairNewSession();
const qrUrl = 'https://mammer55.github.io/QR-Bridge/#pair=' + computer.id + '.' + computer.pub;
check('QR link is short enough for a clear code (' + qrUrl.length + ' chars)', qrUrl.length < 160);

const row = await f.pairSeal(phoneRaw, computer.id, computer.pub);
check('row carries no passphrase or key in the clear', !row.includes('abacus') && !row.includes(Buffer.from(phoneRaw).toString('base64url')));

const got = await f.pairOpen(computer, row);
check('computer gets the phone key', same(got, phoneRaw));

// with the key it got, the computer reads what the phone encrypts
const phoneClip = await f.cbEncrypt(await f.cbImportKey(phoneRaw), 'from the phone', 'mac-to-pc');
check('computer reads clips after pairing', await f.cbDecrypt(await f.cbImportKey(got), phoneClip, 'mac-to-pc') === 'from the phone');

// someone who photographed the code has the id and public key, not the private key
const photographer = await f.pairNewSession();
check('photo of the code opens nothing', await f.pairOpen({ ...photographer, id: computer.id, pub: computer.pub }, row) === null);
check('another computer opens nothing', await f.pairOpen(await f.pairNewSession(), row) === null);
const parts = row.split('.');
parts[4] = parts[4].slice(0, -2) + (parts[4].at(-2) === 'A' ? 'B' : 'A') + parts[4].at(-1);
check('tampered row refused', await f.pairOpen(computer, parts.join('.')) === null);
check('row for another id refused', await f.pairOpen({ ...computer, id: computer.id + 'x' }, row) === null);

console.log(failed ? `${failed} failed` : 'all passed');
process.exit(failed ? 1 : 0);
