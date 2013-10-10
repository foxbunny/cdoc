#!/usr/bin/env node

var opts = require('optimist');
var toArray = require('dahelpers').toArray;
var cdoc = require('../lib/cdoc');
var sourceDir;
var targetDir;

opts = opts.usage([
  'Usage:',
  '    cdoc [-q] [-i IGNORE ...] SOURCE_DIR DOCS_DIR',
  '    cdoc [-h]',
  ''
].join('\n')).
  alias('i', 'ignore').
  alias('q', 'quiet').
  alias('h', 'help').
  describe('i', 'Ignore IGNORE directory. This option can be ' +
    'specified multiple times and can include glob patterns.').
  describe('q', 'Do not log messages to STDOUT').
  describe('h', 'Show this help');

if (opts.argv.h) {
  console.log(opts.help());
  process.exit(0);
}

sourceDir = opts.argv._[0];
targetDir = opts.argv._[1];

if (sourceDir == null || targetDir == null) {
  console.log("You must specify source and target directories");
  console.log();
  console.log(opts.help());
  process.exit(1);
}

if (opts.argv.q) {
  cdoc.VERBOSE = false;
}

cdoc.processDir(sourceDir, targetDir, toArray(opts.argv.i));

