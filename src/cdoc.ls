/**!
 * @author Branko Vukelic <branko@brankovukelic.com>
 * @license MIT
 */

# # CDoc - CoffeeScript/LiveScript documentation extractor
#
# CDoc is a simple NodeJS script that extracts comments from CoffeeScript or
# LiveScript files in the source directory tree, and creates an identical
# directory tree in the target directory that contains markdown comments found
# in source files.
#
# Other than extracting markdown comments, CDoc doesn't do anything. It does
# not compile HTML, has no templates or CSS. In other words, CDoc is not a
# documetnation generator.
#
# ::TOC::
#
# ## Dependencies
#
# CDoc depends on [DaHelpers](https://github.com/foxbunny/dahelpers) and
# [node-optimist](https://github.com/substack/node-optimist).

{
  read-file-sync
  write-file-sync
  readdir-sync
  stat-sync
  exists-sync
  mkdir-sync
} = require 'fs'
{toArray, wrap, slug, a, iter, empty} = require 'dahelpers'

const comment-re = /^ *(?:#|# (.*))$/
const empty-line-re = /^\s*$/
const indented-re = /^ {1,4}\S.*$/
const heading-re = /^(#+) (.*)$/
const utf8 = encoding: 'utf8'

## Alias module.exports for brevity
cdoc = module.exports

cdoc.VERBOSE = true

# ## Internal functions
#
# This module implements the methods used for parsing and extracting the
# Markdown sources from the source code. The command line interface is
# implemented in the `bin/cli.js` script, which is what users run when they
# want to use CDoc from command line.

# ### `isComment(line)`
#
# Matches the unprocessed source file line against regexp and returns the match
# if the line is a comment.
#
cdoc.is-comment = (line) ->
  line.match comment-re

# ### `lineType(line)`
#
# Returns the type of the processed source file line. Output is a an array with
# two members. The first memeber is either the unmodified input, a `null`, or a
# newline character, depending on the type of line. The second member is the
# type of the line.
#
#  + `[null, 'source']`: source code
#  + `['\n', 'empty']`: empty line
#  + `[line, 'heading`']`: heading comment block
#  + `[line, 'indented']`: indented comment block
#  + `[line, 'normal']`: normal comment block
#
cdoc.line-type = (line) ->
  if line is null
    [null, \source]

  else
    line = line.1

    if line is void
      [null, \source]

    else if line.match emptyLineRe
      ['\n', \empty]

    else if line.match headingRe
      [line, \heading]

    else if line.match indentedRe
      [line, \indented]

    else
      [line, \normal]

# ### `extract(filename)`
#
# Internal function.
#
# The return value is an array of paragraphs. Each paragraph is rerpresented by
# an object containing `type` and `content` keys. The `type` key can be one of
# the following:
#
#  + 'source'
#  + 'empty'
#  + 'heading'
#  + 'indented'
#  + 'normal'
#
# The content is an array of lines as found in the source code without any
# wrapping applied.
cdoc.extract = (filename) ->
  contents = read-file-sync filename, utf8

  ## Split the contents into lines and create an iterator object
  lines = iter contents.split '\n'

  ## Processed paragraphs, added to by the slice callback below
  paragraphs = []

  lines.apply @line-type, @is-comment .slice do ->
    ## Paragraph buffer
    paragraph = []

    ## Last line seen
    lastSeen = null

    ## Helper function that adds the paragraph buffer to the `paragraphs` array
    ## and empties the buffer.
    commit = ->
      if not empty paragraph
        paragraphs.push do
          type: lastSeen
          content: paragraph
        paragraph := []
      void

    ## Helper function that pushes a line into the paragraph buffer.
    add = (l) ->
      paragraph.push l
      void

    ## This function is returned and passed to the slice call above. The
    ## function processes all the lines to fill the `paragraphs` array.
    (line) ->
      [line, type] = line
      switch type
      case \source
        commit!
      case \empty
        if lastSeen in [\heading, \normal]
          commit!
        else
          add line
      case \heading
        lastSeen := \heading
        commit!  ## Break paragraph at each heading
        add line
      case \normal
        lastSeen := \normal
        add line
      case \indented
        lastSeen := \indented
        add line
      void

  paragraphs

# ### `processParagraph(o)`
#
# Processes the single paragraph object.
#
# All paragraphs of type \heading are decorated with an anchor so as to make
# them accessible for bookmarking and table of contents.
#
# All normal paragraphs (of type \normal) are wrapped at 79 characters.
#
# All indented paragraphs are joined with newlines and otherwise left intact.
cdoc.process-paragraph = ({type, content}) ->
  switch type
  case \heading
    s = content.join ' '
    m = s.match heading-re
    title = m.2
    hash = slug m.2
    '\n' + m.1 + ' ' + a title, id: hash
  case \normal
    wrap content.join ' '
  case \indented
    content.join '\n'

# ### `processParagraphs(paragraphs)`
#
# Applies the `processParagraph()` function to all paragraph objects extracted
# by the `extract()` function.
cdoc.process-paragraphs = (paragraphs) ->
  [@process-paragraph p for p in paragraphs].join '\n\n'

# ### `tocIndent(level)`
#
# Returns the number of spaces required for TOC indentation for a given
# `level`.
cdoc.toc-indent = (level) ->
  new Array (level - 1) * 2spaces + 2spaces .join ' '

# ### `buildToc(paragraphs)`
#
# Builds the table of contents from given paragraphs. Returns a string of
# Markdown-formatted table of contents.
cdoc.build-toc = (paragraphs) ->
  const min-toc-level = 2
  const max-toc-level = 4
  const bullet = '*'

  toc = ''

  paragraphs = iter paragraphs

  ## Helper function that filters out non-heading paragraphs. Returns the
  ## contents of the paragraph when paragraph is a header.
  filter-headings = (p) ->
    if p.type is \heading then p.content else throw 'skip'

  ## Helper function that joins the contents of a paragraph `p` and also
  ## filters out paragraphs that don't match the minimum and maximum header
  ## level requirements. Returns and array containing the heading level and
  ## heading title.
  join-content = (p) ->
    s = p.join(' ')
    m = s.match heading-re
    level = m.1.length
    title = m.2
    throw 'skip' if maxTocLevel < level or level < minTocLevel
    [level, title]

  paragraphs.apply join-content, filter-headings .slice ([level, title]) ~>
    indent = @toc-indent level - minTocLevel + 1
    hash = slug title
    toc += "#{indent}#{bullet} [#{title}](##{hash})\n"

  toc

# ### `processFile(filename)`
#
# Performs conversion of source code in `filename` to Markdown.
cdoc.process-file = (filename) ->
  paragraphs = @extract filename
  mkd = @process-paragraphs paragraphs
  if (mkd.index-of '::TOC::') > -1
    mkd = mkd.replace '::TOC::', @build-toc paragraphs
  mkd

# ### `log(msg)`
#
# Wrapper around `console.log()` which suppresses output if `VERBOSE` flag is
# unset.
cdoc.log = (msg) ->
  console.log msg if @VERBOSE

# ### `isDir(path)`
#
# Returns `true` if `path` is a directory.
cdoc.is-dir = (path) ->
  stat-sync path .is-directory!

# ### `isGlob(s)`
#
# Returns `true` if string `is` contains glob pattern characters ('\*' and
# '?').
cdoc.is-glob = (s) ->
  (s.index-of '*') > -1 or (s.index-of '?') > -1

# ### `matchGlob(s, glob)`
#
# Converts the glob pattern string `glob` to RegExp and returns a match against
# the string `s`. Return value is the same as for `String.prototype.match()`.
cdoc.match-glob = (s, glob) ->
  glob = glob
    .replace '*', '.*'
    .replace '?', '.'
    .replace '.', '\\.'
  s.match new RegExp glob

# ### `isSkippable(filename, skipList)`
#
# Returns true if `filename` matches at least one item in the `skipList` array.
# The `skipList` items can either be exact filenames or glob patterns.
cdoc.is-skippable = (filename, skip-list) ->
  for skip in skipList
    if is-glob skip
      t = match-glob filename, skip
    else
      t = filename == skip
    return true if t
  false

# ### `processDir(dir, target, [skip])`
#
# Recursively processes the `dir` directory and creates extracted Markdown
# files in the `target` directory.
#
# The `target` directory tree will be created to match the source directory
# tree. The target filenames will be the same as source filenames except for
# the 'mkd' extension.
cdoc.process-dir = (dir, target, skip=[]) ->
  index = readdir-sync dir

  ## Ensure target directory exists
  mkdir-sync target if not exists-sync target

  ## Process each file/directory in the target tree
  for f in index
    if @is-skippable f, skip
      @log "Skipping ignored file #{f}"
      continue

    path = "#{dir}/#{f}"
    @log "Processing #{path}"

    if @is-dir path
      @log "Entering directory #{path}"
      @process-dir path, "#{target}/#{f}", skip

    else
      name = f.split '.' .slice 0, -1 .join '.'
      ext = (f.split '.' .slice -1)[0]

      if ext not in <[ coffee ls ]>
        @log "Skipping non-source file #{path}"
        continue

      mkd = @process-file path
      target-path = "#{target}/#{name}.mkd"
      @log "Writing markdown to #{target-path}"
      write-file-sync target-path, mkd, utf8

  return

