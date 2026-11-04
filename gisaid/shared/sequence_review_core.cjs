/* Shared, dependency-free Sequence Review rules. Legacy v1 hashes remain unchanged. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.SequenceReviewCore = factory();
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const MAX_ROWS = 50000, MAX_COLUMNS = 1000;
  // Samples and the same-origin tree iframe load separate copies of this module.
  const LEGACY_IDENTITY = Symbol.for('sequence-review.legacy-identity');
  const plain = value => value && typeof value === 'object' && !Array.isArray(value);
  const fail = message => { throw new Error(message); };
  const strings = (value, label) => {
    if (!Array.isArray(value) || value.some(x => typeof x !== 'string' || !x.trim()) ||
        new Set(value).size !== value.length) fail(`Invalid ${label}.`);
    return [...value];
  };
  function treeColorings(value = []) {
    if (!Array.isArray(value) || value.length > 30) fail('tree_colorings must be a list of at most 30 columns.');
    const columns = new Set();
    return value.map(entry => {
      if (!plain(entry) || typeof entry.column !== 'string' || !entry.column.trim() || entry.column.length > 256 ||
          columns.has(entry.column)) fail('Each tree coloring needs a unique column name.');
      columns.add(entry.column);
      const title = entry.title ?? entry.column, type = entry.type ?? 'categorical';
      if (typeof title !== 'string' || !title.trim() || title.length > 256 || !['categorical', 'continuous'].includes(type))
        fail('Invalid tree coloring title or type.');
      const result = {column: entry.column, title, type};
      if (entry.colors !== undefined) {
        if (type !== 'categorical' || !plain(entry.colors) || Object.values(entry.colors).some(c => typeof c !== 'string' || !/^#[0-9a-f]{6}$/i.test(c)))
          fail('Categorical colors must map values to six-digit hexadecimal colors.');
        result.colors = {...entry.colors};
      }
      if (entry.range !== undefined) {
        if (type !== 'continuous' || !Array.isArray(entry.range) || entry.range.length !== 2 ||
            entry.range.some(c => typeof c !== 'string' || !/^#[0-9a-f]{6}$/i.test(c)))
          fail('A continuous color range needs two six-digit hexadecimal colors.');
        result.range = [...entry.range];
      }
      return result;
    });
  }
  function config(value, expected) {
    if (!plain(value) || value.schema_version !== 1 ||
        !/^[A-Za-z0-9_-]{1,48}$/.test(value.pathogen) ||
        (expected && value.pathogen !== expected)) fail('Invalid pathogen configuration.');
    const keys = strings(value.key_columns || [value.key_column], 'sample key columns');
    if (!keys.length || keys.length > 8 || ![';', ',', '\t'].includes(value.csv_delimiter)) fail('Invalid key or delimiter configuration.');
    const legacyKeys = strings(value.legacy_key_columns || [], 'legacy sample key columns');
    if (legacyKeys.length > 8 || (legacyKeys.length && JSON.stringify(legacyKeys) === JSON.stringify(keys)))
      fail('Legacy sample key columns must differ from the current sample key columns.');
    const options = strings(value.review_options, 'review options');
    if (!options.includes('Approved')) fail('Review options must include Approved.');
    const edits = strings(value.edit_columns, 'editable fields');
    if (edits.some(c => keys.includes(c))) fail('Sample identifiers cannot be manually changed.');
    return {...value, key_column: keys[0], key_columns: keys, legacy_key_columns: legacyKeys,
      default_columns: strings(value.default_columns, 'default columns'),
      column_order: strings(value.column_order || [], 'column order'),
      edit_columns: edits, review_options: options,
      tree_colorings: treeColorings(value.tree_colorings),
      legacy_edit_columns: strings(value.legacy_edit_columns || edits, 'legacy editable fields')};
  }
  function keyOf(row, cfg) {
    const parts = cfg.key_columns.map(k => row[k]);
    if (parts.some(x => typeof x !== 'string' || !x.trim())) fail(`Empty sample identifier in ${cfg.key_columns.join(' + ')}.`);
    return parts.length === 1 ? parts[0] : JSON.stringify(parts);
  }
  function parseCSV(input, cfg) {
    if (typeof input !== 'string' || input.length > 32 * 1024 * 1024) fail('CSV exceeds 32 MiB.');
    const text = input.replace(/^\uFEFF/, ''), records = [];
    let fields = [], field = '', quoted = false, closed = false, started = false, quoteStart = 0;
    const malformed = (message, offset, hint) => {
      const line = 1 + (text.slice(0, offset).match(/\r\n|\r|\n/g) || []).length;
      const column = fields.length + 1, header = records[0]?.[fields.length];
      fail(`${message} Line ${line}, CSV column ${column}${header ? ` (${header})` : ''}. ${hint}`);
    };
    const cell = () => {fields.push(field); field = ''; closed = false; started = false;};
    const record = () => {cell(); if (fields.some(x => x !== '')) records.push(fields); fields = [];
      if (records.length > MAX_ROWS + 1) fail('CSV exceeds 50,000 rows.');};
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (quoted) {
        if (c === '"' && text[i + 1] === '"') {field += '"'; i++;}
        else if (c === '"') {quoted = false; closed = true;}
        else field += c;
      } else if (c === cfg.csv_delimiter) cell();
      else if (c === '\r' || c === '\n') {if (c === '\r' && text[i + 1] === '\n') i++; record();}
      else if (closed) malformed('Malformed CSV: characters after a closing quote.', i, 'A closing quote must be followed by the delimiter or the end of the row.');
      else if (c === '"') {
        if (started) malformed('Malformed CSV quote.', i, 'A double quote occurs inside an unquoted field. Enclose the whole field in double quotes and double any quotes inside it.');
        quoted = true; started = true; quoteStart = i;
      }
      else {field += c; started = true;}
    }
    if (quoted) malformed('Malformed CSV: unclosed quote.', quoteStart, 'The quoted field starting here has no closing quote.');
    if (fields.length || started || closed) record();
    const headers = records.shift();
    if (!headers || headers.length > MAX_COLUMNS || headers.some(x => !x.trim()) ||
        new Set(headers).size !== headers.length) fail('CSV needs unique, nonempty headers (at most 1,000).');
    const missingKeys = cfg.key_columns.filter(k => !headers.includes(k));
    if (missingKeys.length) fail(`CSV is missing a configured sample key column: ${missingKeys.join(', ')}.`);
    const seen = new Set();
    const rows = records.map((values, index) => {
      if (values.length !== headers.length) fail(`Incorrect column count on row ${index + 2}.`);
      const row = Object.fromEntries(headers.map((h, j) => [h, values[j]]));
      const key = keyOf(row, cfg);
      if (seen.has(key)) fail(`Duplicate sample identifier in CSV (${cfg.key_columns.join(' + ')}).`);
      seen.add(key); return row;
    });
    return {headers, rows};
  }
  function sha256(str) {
    const bytes = new TextEncoder().encode(str), len = bytes.length;
    const K = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    const H = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    const padded = new Uint8Array(Math.ceil((len + 9) / 64) * 64); padded.set(bytes); padded[len] = 0x80;
    const view = new DataView(padded.buffer), bits = len * 8;
    view.setUint32(padded.length - 8, Math.floor(bits / 0x100000000)); view.setUint32(padded.length - 4, bits >>> 0);
    const w = new Uint32Array(64), ror = (x, n) => (x >>> n) | (x << (32 - n));
    for (let off = 0; off < padded.length; off += 64) {
      for (let i = 0; i < 16; i++) w[i] = view.getUint32(off + i * 4);
      for (let i = 16; i < 64; i++) {
        const a = w[i - 15], b = w[i - 2];
        w[i] = (w[i - 16] + (ror(a,7)^ror(a,18)^(a>>>3)) + w[i - 7] + (ror(b,17)^ror(b,19)^(b>>>10))) | 0;
      }
      let [a,b,c,d,e,f,g,h] = H;
      for (let i = 0; i < 64; i++) {
        const t1 = (h + (ror(e,6)^ror(e,11)^ror(e,25)) + ((e&f)^(~e&g)) + K[i] + w[i]) | 0;
        const t2 = ((ror(a,2)^ror(a,13)^ror(a,22)) + ((a&b)^(a&c)^(b&c))) | 0;
        h=g; g=f; f=e; e=(d+t1)|0; d=c; c=b; b=a; a=(t1+t2)|0;
      }
      [a,b,c,d,e,f,g,h].forEach((v,i) => {H[i] = (H[i] + v) | 0;});
    }
    return H.map(x => (x >>> 0).toString(16).padStart(8, '0')).join('');
  }
  function fingerprint(row, headers, cfg) {
    // Exactly the ZIP's v1 algorithm for single-column identifiers. Composite
    // identifiers exclude their configured identity fields, with no normalization.
    const pairs = headers.filter(k => !cfg.key_columns.includes(k) && row[k] !== undefined && row[k] !== '')
      .sort().map(k => [k, row[k]]);
    return 'sha256:' + sha256(JSON.stringify(pairs));
  }
  function normalizeEvent(event, cfg) {
    if (!plain(event) || event.format_version !== 1 || event.pathogen !== cfg.pathogen ||
        typeof event.id !== 'string' || !/^[A-Za-z0-9_-]{1,160}$/.test(event.id) ||
        typeof event.key !== 'string' || !event.key.trim() ||
        !/^sha256:[a-f0-9]{64}$/.test(event.result_hash) ||
        typeof event.created_at !== 'string' || !Number.isFinite(Date.parse(event.created_at)) ||
        !plain(event.review)) fail('Invalid review identity, fingerprint or timestamp.');
    strings(event.supersedes, 'review parents');
    if (event.key_columns !== undefined &&
        JSON.stringify(strings(event.key_columns, 'review key columns')) !== JSON.stringify(cfg.key_columns))
      fail('Review identifier columns do not match the dataset configuration.');
    const review = event.review;
    if (typeof review.reviewer !== 'string' || !review.reviewer.trim() || review.reviewer.length > 80 ||
        !cfg.review_options.includes(review.assessment) || typeof (review.comment ?? '') !== 'string' ||
        (review.comment || '').length > 32000 || !plain(review.overrides)) fail('Invalid review decision or reviewer.');
    const allowed = event.policy_version ? cfg.edit_columns : cfg.legacy_edit_columns;
    if (event.policy_version && event.policy_version !== (cfg.review_policy_version || 'legacy-v1')) fail('Unknown review policy version.');
    for (const [column, value] of Object.entries(review.overrides)) {
      if (cfg.key_columns.includes(column) || !allowed.includes(column) || typeof value !== 'string' || value.length > 32000)
        fail('Review contains an unsupported manual field. Check the historical field policy.');
    }
    return event;
  }
  function buildHeads(events, cfg) {
    const byId = new Map(), heads = new Map(), superseded = new Set();
    for (const raw of events) {
      const event = normalizeEvent(raw, cfg);
      if (byId.has(event.id)) fail('Duplicate review IDs.');
      byId.set(event.id, event);
    }
    const indegree = new Map(), children = new Map();
    for (const event of events) {
      indegree.set(event.id, event.supersedes.length);
      for (const parent of event.supersedes) {
        if (!byId.has(parent) || byId.get(parent).key !== event.key || parent === event.id)
          fail('Review history has a missing or unrelated parent.');
        superseded.add(parent);
        if (!children.has(parent)) children.set(parent, []);
        children.get(parent).push(event.id);
      }
    }
    const queue = [...byId.keys()].filter(id => indegree.get(id) === 0);
    for (let i = 0; i < queue.length; i++) {
      for (const id of children.get(queue[i]) || []) {
        indegree.set(id, indegree.get(id) - 1); if (!indegree.get(id)) queue.push(id);
      }
    }
    if (queue.length !== events.length) fail('Review history contains a cycle.');
    for (const event of events) {
      if (!heads.has(event.key)) heads.set(event.key, []);
      if (!superseded.has(event.id)) heads.get(event.key).push(event);
    }
    return heads;
  }
  function snapshot(raw) {
    const cfg = config(raw.config), parsed = parseCSV(raw.csv, cfg);
    const legacyCfg = cfg.legacy_key_columns.length ? {...cfg, key_columns: cfg.legacy_key_columns} : null;
    let legacyIndex;
    const legacyHashes = new Map();
    const events = (raw.events || []).map(event => {
      const sourceKeys = event.key_columns ?? (legacyCfg ? legacyCfg.key_columns : cfg.key_columns);
      if (JSON.stringify(sourceKeys) === JSON.stringify(cfg.key_columns)) return normalizeEvent(event, cfg);
      if (!legacyCfg || JSON.stringify(sourceKeys) !== JSON.stringify(legacyCfg.key_columns))
        fail('Review identifier columns do not match the current or configured legacy identifiers.');
      normalizeEvent(event, legacyCfg);
      if (!legacyIndex) {
        if (legacyCfg.key_columns.some(column => !parsed.headers.includes(column)))
          fail('The CSV is missing legacy identifier columns needed to link existing reviews.');
        legacyIndex = new Map();
        for (const row of parsed.rows) {
          const oldKey = keyOf(row, legacyCfg), key = keyOf(row, cfg);
          if (legacyIndex.has(oldKey)) fail('Duplicate legacy identifier: existing reviews cannot be linked safely.');
          legacyIndex.set(oldKey, key);
          legacyHashes.set(key, fingerprint(row, parsed.headers, legacyCfg));
        }
      }
      if (!legacyIndex.has(event.key))
        fail('An existing review has no matching legacy identifier in the current master CSV. Restore its mapping before changing identifiers.');
      // Translate identity only in memory. Keep historical hashes, IDs and files intact.
      return {...event, key: legacyIndex.get(event.key), key_columns: [...cfg.key_columns], [LEGACY_IDENTITY]: true};
    });
    const heads = buildHeads(events, cfg);
    return {config: cfg, ...parsed, events, heads, legacyHashes,
      byKey: new Map(parsed.rows.map(row => [keyOf(row, cfg), row])),
      hashes: new Map(parsed.rows.map(row => [keyOf(row, cfg), fingerprint(row, parsed.headers, cfg)]))};
  }
  function sameResult(snapshot, event) {
    const hashes = event[LEGACY_IDENTITY] ? snapshot.legacyHashes : snapshot.hashes;
    return event.result_hash === hashes.get(event.key);
  }
  function state(snapshot, key) {
    const heads = snapshot.heads.get(key) || [];
    return heads.length > 1 ? 'conflict' : !heads.length ? 'pending' :
      sameResult(snapshot, heads[0]) ? 'valid' : 'stale';
  }
  function expected(snapshot, key) {
    if (!snapshot.byKey.has(key)) fail('Sample is not in the current results.');
    return {key, hash: snapshot.hashes.get(key), heads: (snapshot.heads.get(key) || []).map(e => e.id).sort()};
  }
  function assertFresh(wanted, fresh) {
    if (fresh.hashes.get(wanted.key) !== wanted.hash) fail('Analysis changed. Refresh and inspect the current results before saving.');
    const heads = (fresh.heads.get(wanted.key) || []).map(e => e.id).sort();
    if (JSON.stringify(heads) !== JSON.stringify(wanted.heads)) fail('A colleague changed the review. Refresh before saving.');
  }
  function effective(snapshot, row, column) {
    const key = keyOf(row, snapshot.config), head = (snapshot.heads.get(key) || [])[0];
    return state(snapshot, key) === 'valid' && Object.hasOwn(head.review.overrides, column)
      ? head.review.overrides[column] : row[column] ?? '';
  }
  function csv(rows, delimiter = ';', spreadsheet = false) {
    const field = value => {
      let s = String(value ?? '');
      if (spreadsheet && /^[\s]*[=+@\-\t\r]/.test(s)) s = "'" + s;
      return s.includes(delimiter) || /["\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
    };
    return '\uFEFF' + rows.map(row => row.map(field).join(delimiter)).join('\r\n') + '\r\n';
  }
  function uuid() {
    const c = globalThis.crypto;
    if (c.randomUUID) return c.randomUUID();
    return Array.from(c.getRandomValues(new Uint8Array(16)), x => x.toString(16).padStart(2, '0')).join('');
  }
  function linkRows(snapshot, column, ids) {
    if (!snapshot || !snapshot.headers.includes(column)) fail('Choose an existing metadata column to match tree IDs.');
    const wanted = new Set(ids), index = new Map();
    for (const row of snapshot.rows) {
      const id = row[column];
      if (!id || !wanted.has(id)) continue;
      if (index.has(id)) fail(`Multiple metadata rows match "${id}" in "${column}". Choose a unique matching column.`);
      index.set(id, row);
    }
    return {rows: [...wanted].map(id => ({id, row: index.get(id) || null})),
      matched: index.size, missing: [...wanted].filter(id => !index.has(id))};
  }
  function treeIds(value) {
    if (!plain(value) || value.version !== 'v2' || !plain(value.tree)) fail('Choose an Auspice v2 tree JSON.');
    const ids = new Set(), pending = [value.tree];
    let count = 0;
    while (pending.length) {
      const node = pending.pop();
      if (!plain(node) || ++count > 100000) fail('Invalid or oversized tree.');
      if (node.children !== undefined && !Array.isArray(node.children)) fail('Invalid tree children.');
      if (node.children?.length) pending.push(...node.children);
      else {
        if (typeof node.name !== 'string' || !node.name || ids.has(node.name)) fail('Tree sample IDs must be nonempty and unique.');
        ids.add(node.name);
      }
    }
    return [...ids];
  }
  return {config, keyOf, parseCSV, sha256, fingerprint, normalizeEvent, buildHeads,
    snapshot, sameResult, state, expected, assertFresh, effective, csv, uuid, linkRows, treeIds};
}));
