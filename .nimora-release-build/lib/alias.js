// Shared helpers for source labels.
//
// Providers pass their original upstream label to sourceAliasWithQuality.
// This file only normalizes real quality tokens; it does not invent aliases.

function sourceAlias(sourceId, serverKey) {
  return String(serverKey ?? sourceId ?? '').trim();
}

function sourceAliasWithQuality(sourceId, serverKey, realName) {
  const label = String(realName ?? '').trim() || sourceAlias(sourceId, serverKey);
  const quality = sourceQuality(realName);
  return quality && !label.toLowerCase().includes(quality.toLowerCase())
    ? `${label} (${quality})`
    : label;
}

function sourceQuality(value) {
  const match = /(?:^|[^0-9])((?:2160|1440|1080|720|576|480|360|240)\s*p?|(?:4|2)k)(?=$|[^a-z0-9])/i.exec(
    String(value ?? ''),
  );
  if (match == null) return '';
  const normalized = match[1].replace(/\s+/g, '').toLowerCase();
  const numeric = /^(2160|1440|1080|720|576|480|360|240)p?$/.exec(normalized);
  return numeric == null ? normalized.toUpperCase() : `${numeric[1]}p`;
}
