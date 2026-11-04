#!/usr/bin/env node
'use strict';
// Read-only adapter to the same decision, hash and conflict rules as Sequence Review.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const Core = require('./sequence_review_core.cjs');
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const decode = value => new TextDecoder('utf-8', {fatal: true}).decode(value);

function load(master, pathogen) {
  const base = path.dirname(path.resolve(master));
  const reviewDir = path.join(base, 'reviews');
  function readSnapshot() {
    const files = fs.readdirSync(reviewDir, {withFileTypes: true})
      .filter(entry => entry.isFile() && entry.name.endsWith('.json')).map(entry => entry.name).sort();
    if (files.length > 20000) throw Error('Review history exceeds the supported 20,000 events.');
    function read(filename, limit) {
      const data = fs.readFileSync(filename);
      if (data.length > limit) throw Error('Review input exceeds the supported size limit.');
      return data;
    }
    const config = read(path.join(base, 'config.json'), 256000);
    const csv = read(master, 32 * 1024 * 1024);
    const reviews = files.map(name => [name, read(path.join(reviewDir, name), 256000)]);
    const token = digest(JSON.stringify([digest(config), digest(csv), reviews.map(([name, data]) => [name, digest(data)])]));
    return {config: JSON.parse(decode(config)), csv: decode(csv),
      events: reviews.map(([, data]) => JSON.parse(decode(data))), token, master_sha256: digest(csv)};
  }
  const raw = readSnapshot();
  Core.config(raw.config, pathogen);
  const snapshot = Core.snapshot(raw);
  const counts = {total: snapshot.rows.length, approved: 0, pending: 0, stale: 0, conflict: 0, not_approved: 0};
  const rows = [], approvals = [];
  for (const row of snapshot.rows) {
    const key = Core.keyOf(row, snapshot.config), state = Core.state(snapshot, key);
    if (state !== 'valid') {counts[state]++; continue;}
    const event = snapshot.heads.get(key)[0];
    if (event.review.assessment !== 'Approved') {counts.not_approved++; continue;}
    counts.approved++;
    rows.push(Object.fromEntries(snapshot.headers.map(column => [column, Core.effective(snapshot, row, column)])));
    approvals.push({key, event_id: event.id, result_hash: event.result_hash});
  }
  // Do not export a snapshot assembled while another writer changes inputs.
  if (readSnapshot().token !== raw.token) throw Error('Master or review history changed while reading; retry.');
  const identityHeaders = ['review_key', 'Key', 'Prove_LW_ID', 'NGS_LW_ID', 'OriginalName', 'SampleID'];
  const identities = snapshot.rows.map(row => ({...Object.fromEntries(identityHeaders.map(name => [name, row[name] || ''])),
    review_key: Core.keyOf(row, snapshot.config)}));
  return {headers: snapshot.headers, rows, identities, counts, approvals,
    token: raw.token, master_sha256: raw.master_sha256, identity_headers: identityHeaders};
}

function main(args) {
  const options = {};
  const allowed = new Set(['--master', '--pathogen', '--output', '--identities-output', '--token-output', '--expect-token']);
  for (let i = 0; i < args.length; i += 2) {
    if (!allowed.has(args[i]) || !args[i + 1] || Object.hasOwn(options, args[i])) throw Error('Invalid approval reader arguments.');
    options[args[i]] = args[i + 1];
  }
  if (!options['--master'] || !['INF', 'SC2'].includes(options['--pathogen'])) throw Error('--master and --pathogen INF|SC2 are required.');
  const result = load(options['--master'], options['--pathogen']);
  if (options['--expect-token']) {
    if (result.token !== options['--expect-token']) throw Error('Master or reviews changed during export; regenerate the submission.');
    return;
  }
  if (options['--output']) {
    fs.writeFileSync(options['--output'], Core.csv([result.headers, ...result.rows.map(row => result.headers.map(h => row[h]))]), {flag: 'wx'});
    if (options['--identities-output']) fs.writeFileSync(options['--identities-output'],
      Core.csv([result.identity_headers, ...result.identities.map(row => result.identity_headers.map(h => row[h]))]), {flag: 'wx'});
    if (options['--token-output']) fs.writeFileSync(options['--token-output'], result.token, {flag: 'wx'});
    console.log('Sequence Review approval filter: ' + JSON.stringify(result.counts));
  } else {
    process.stdout.write(JSON.stringify(result));
  }
}
module.exports = {load};
if (require.main === module) {
  try {main(process.argv.slice(2));}
  catch (error) {console.error('Approval filter failed: ' + error.message); process.exitCode = 1;}
}
