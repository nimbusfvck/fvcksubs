// Cricfy's content-list cipher, in JS on the host `crypto`/`codec` API.
//
// A port of Cricfy's content cipher. This is
// the hard case for the host API on purpose: it is the most hostile shape
// either provider has — derived AES key, swapped-alphabet base64, a
// code-unit-level scramble, and a payload that may need repairing.
//
//   stage 1: base64 -> flip -> check sentinel -> strip sentinel
//   stage 2: base64 -> AES-128-CBC -> flip -> base64 -> JSON
//
// Every constant is already decoded from the APK and covered by fixed vectors.

const SENTINEL = 'abcdefghijklmnop';
const FALLBACK_KEY = 'WT1sdkEvUlR4ckd2';
const IV = 'Q7sKcm9LR4VaX2pN';
const CERT_HASH =
  '42d56eca078d4521a1920a61e14a81fd674f91f2c55c53b42d3924c26e3f3835';
const ENTRY_HASH =
  '43744467f50639590811a23c84c6bf35e1394e73a80519dcbea97c805ab68c59';
const SALT = 'bf4b0a33d0f56bf8166fc55adbbcdd0a8a68e72615644a12';
const MASK_HEX = '4d6681537371296d4fc2168d7be6b308';

// `swapPairs` then `reverse`, over UTF-16 code units.
//
// This is the transform PLAN.md §18 flagged as non-portable, to be kept in
// Dart or rewritten byte-only. Neither turned out to be necessary: JS strings
// are UTF-16 like Dart's, so it ports as-is — *provided* the UTF-8 decode
// that produces the string is a host primitive, so malformed input becomes
// U+FFFD identically on both sides rather than diverging here.
function flip(value) {
  const units = Array.from(value, (c) => c.charCodeAt(0));
  for (let i = 0; i + 1 < units.length; i += 2) {
    const temp = units[i];
    units[i] = units[i + 1];
    units[i + 1] = temp;
  }
  units.reverse();
  return units.map((u) => String.fromCharCode(u)).join('');
}

/// The AES-128 key the APK derives from its own hashes, as base64.
function derivedKey() {
  const digest = host.crypto.sha256(
    host.codec.textToBase64(`${CERT_HASH}:${ENTRY_HASH}:${SALT}`),
  );
  // xor truncates to the shorter side, so masking a 32-byte digest with the
  // 16-byte mask yields the 16-byte key directly.
  return host.crypto.xor(digest, host.codec.hexToBase64(MASK_HEX));
}

// Keeps only valid base64 characters, then pads.
function cleanBase64(value) {
  let out = '';
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    const valid =
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a) ||
      (code >= 0x30 && code <= 0x39) ||
      code === 0x2b ||
      code === 0x2f;
    if (valid) out += value[i];
  }
  const remainder = out.length % 4;
  return remainder === 0 ? out : out + '='.repeat(4 - remainder);
}

function parses(value) {
  try {
    JSON.parse(value);
    return true;
  } catch (_) {
    return false;
  }
}

// Trims a truncated JSON tail back to the last complete element.
function repairJsonTail(value) {
  const text = value.trim();
  if (text.length === 0 || parses(text)) return text;

  const closing = text.startsWith('[') ? ']' : '}';
  for (let i = text.length - 1; i > 0; i--) {
    if (text[i] !== '}') continue;
    const candidate = text.substring(0, i + 1) + closing;
    if (parses(candidate)) return candidate;
  }
  return text;
}

/// Opens a content-list response into JSON, or returns null if `raw` isn't
/// this shape of payload.
function decode(raw) {
  const text = raw.trim();
  if (text.length === 0) return null;

  let stage1;
  try {
    stage1 = flip(host.codec.base64ToText(text));
  } catch (_) {
    return null;
  }
  if (!stage1.endsWith(SENTINEL)) return null;

  const payload = stage1.substring(0, stage1.length - SENTINEL.length);
  const iv = host.codec.textToBase64(IV);

  // Same order as the APK: derived key first, then the fallback.
  for (const key of [derivedKey(), host.codec.textToBase64(FALLBACK_KEY)]) {
    const plain = host.crypto.aesCbcDecrypt(key, iv, cleanBase64(payload));
    if (plain === null) continue;

    const cleaned = cleanBase64(flip(host.codec.base64ToText(plain)));
    if (cleaned.length === 0) continue;
    try {
      return repairJsonTail(host.codec.base64ToText(cleaned));
    } catch (_) {
      continue;
    }
  }
  return null;
}

globalThis.cricfyCipher = { derivedKey, decode };
