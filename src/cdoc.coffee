# # CDoc - CoffeeScript documentation extractor
#
# CDoc is a simple NodeJS script that extracts comments from CoffeeScript files
# in the source directory tree, and creates an identical directory tree in the
# target directory that contains markdown comments found in source files.
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
  readFileSync
  writeFileSync
  readdirSync
  statSync
  existsSync
  mkdirSync
} = require 'fs'
{toArray, wrap, slug, a, iter, empty} = require 'dahelpers'
opts = require 'optimist'

commentRe = /^ *(?:#|# (.*))$/
emptyLineRe = /^\s*$/
indentedRe = /^ {1,4}\S.*$/
headingRe = /^(#+) (.*)$/

VERBOSE = true

# ## Internal functions
#
# The functions documented below are internal functions that are not
# accessible otherwise.
#
# ### `extract(filename)`
#
# Internal function.
#
# The return value is an array of paragraphs. Each paragraph is rerpresented by
# an object containing `type` and `content` keys. The `type` key can be one of
# the following:
#
#  + 'heading'
#  + 'code'
#  + 'normal'
#
# The content is an array of lines as found in the source code without any
# wrapping applied.
extract = (filename) ->
  contents = readFileSync filename, encoding: 'utf-8'

  isComment = (line) ->
    line.match commentRe

  lineType = (line) ->
    if not line
      [null, 'source']

    else
      line = line[1]

      if not line?
        [null, 'source']

      else if line.match emptyLineRe
        ['\n', 'empty']

      else if line.match headingRe
        [line, 'heading']

      else if line.match indentedRe
        [line, 'indented']

      else
        [line, 'normal']

  ## Split the contents into lines and create an iterator object
  lines = iter contents.split '\n'

  paragraphs = []

  lines.apply(lineType, isComment).slice (() ->
    paragraph = []
    lastSeen = null

    commit = () ->
      return if empty paragraph
      paragraphs.push {type: lastSeen, content: paragraph}
      paragraph = []

    add = (l) -> paragraph.push l

    (line) ->
      [line, type] = line
      switch type
        when 'source'
          commit()
        when 'empty'
          if lastSeen in ['heading', 'normal']
            commit()
          else
            add line
        when 'heading'
          lastSeen = 'heading'
          commit()
          add line
        when 'normal'
          lastSeen = 'normal'
          add line
        when 'indented'
          lastSeen = 'indented'
          add line
      return
  )()

  paragraphs

# ### `processParagraph(o)`
#
# Processes the single paragraph object.
#
# All paragraphs of type 'heading' are decorated with an anchor so as to make
# them accessible for bookmarking and table of contents.
#
# All normal paragraphs (of type 'normal') are wrapped at 79 characters.
#
# All indented paragraphs are joined with newlines and otherwise left intact.
processParagraph = ({type, content}) ->
  switch type
    when 'heading'
      s = content.join ' '
      m = s.match headingRe
      title = m[2]
      hash = slug m[2]
      '\n' + m[1] + ' ' + a title, id: hash
    when 'normal'
      wrap content.join ' '
    when 'indented'
      content.join '\n'

# ### `processParagraphs(paragraphs)`
#
# Applies the `processParagraph()` function to all paragraph objects extracted
# by the `extract()` function.
processParagraphs = (paragraphs) ->
  (processParagraph p for p in paragraphs).join('\n\n')

# ### `tocIndent(level)`
#
# Returns the number of spaces required for TOC indentation for a given
# `level`.
tocIntend = (level) ->
  new Array((level - 1) * 2 + 2).join ' '

# ### `buildToc(paragraphs)`
#
# Builds the table of contents from given paragraphs. Returns a string of
# Markdown-formatted table of contents.
buildToc = (paragraphs) ->
  toc = ''
  minTocLevel = 2
  maxTocLevel = 4
  bullet = '*'

  paragraphs = iter paragraphs

  filterHeadings = (p) ->
    if p.type is 'heading' then p.content else throw 'skip'

  joinContent = (p) ->
    s = p.join(' ')
    m = s.match headingRe
    level = m[1].length
    title = m[2]
    throw 'skip' if maxTocLevel < level or level < minTocLevel
    [level, title]

  paragraphs.apply(joinContent, filterHeadings).slice ([level, title]) ->
    indent = tocIntend (level - minTocLevel + 1)
    hash = slug title
    toc += "#{indent}#{bullet} [#{title}](##{hash})\n"

  toc

# ### `processFile(filename)`
#
# Performs conversion of source code in `filename` to Markdown.
processFile = (filename) ->
  paragraphs = extract filename
  mkd = processParagraphs paragraphs
  if mkd.indexOf('::TOC::') > -1
    mkd = mkd.replace '::TOC::', buildToc paragraphs
  mkd

# ### `log(msg)`
#
# Wrapper around `console.log()` which suppresses output if `VERBOSE` flag is
# unset.
log = (msg) ->
  console.log(msg) if VERBOSE

# ### `isDir(path)`
#
# Returns `true` if `path` is a directory.
isDir = (path) ->
  statSync(path).isDirectory()

# ### `isGlob(s)`
#
# Returns `true` if string `is` contains glob pattern characters ('\*' and
# '?').
isGlob = (s) ->
  s.indexOf('*') > -1 or s.indexOf('?') > -1

# ### `matchGlob(s, glob)`
#
# Converts the glob pattern string `glob` to RegExp and returns a match against
# the string `s`. Return value is the same as for `String.prototype.match()`.
matchGlob = (s, glob) ->
  glob = glob.
    replace('*', '.*').
    replace('?', '.').
    replace('.', '\\.')
  s.match new RegExp glob

# ### `isSkippable(filename, skipList)`
#
# Returns true if `filename` matches at least one item in the `skipList` array.
# The `skipList` items can either be exact filenames or glob patterns.
isSkippable = (filename, skipList) ->
  for skip in skipList
    if isGlob skip
      t = matchGlob filename, skip
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
processDir = (dir, target, skip=[]) ->
  index = readdirSync dir

  ## Ensure target directory exists
  mkdirSync(target) if not existsSync target

  ## Process each file/directory in the target tree
  for f in index
    if isSkippable f, skip
      log "Skipping ignored file #{f}"
      continue

    path = "#{dir}/#{f}"
    log "Processing #{path}"

    if isDir path
      log "Entering directory #{path}"
      processDir path, "#{target}/#{f}", skip

    else
      name = f.split('.').slice(0, -1).join '.'
      ext = f.split('.').slice(-1)[0]

      if ext isnt 'coffee'
        log "Skipping non-CoffeeScript file #{path}"
        continue

      mkd = processFile path
      targetPath = "#{target}/#{name}.mkd"
      log "Writing markdown to #{targetPath}"
      writeFileSync targetPath, mkd, encoding: 'utf-8'

  return

# ## Command line usage
#
# To get command line usage information, run this script with -h command.
#
# ### Basic usage
#
#     cdoc SOURCE_DIR DOCS_DIR
#
# ### Ignoring directories
#
#     cdoc SOURCE_DIR DOCS_DIR -i IGNORED [-i IGNORED ...]
#
opts = opts.usage([
  'Usage:'
  '    $0 [-q] [-i IGNORE ...] SOURCE_DIR DOCS_DIR'
  '    $0 [-h]'
  ''
].join('\n')).
  alias('i', 'ignore').
  alias('q', 'quiet').
  alias('h', 'help').
  describe('i', 'Ignore IGNORE directory. This option can be '
    'specified multiple times and can include glob patterns.').
  describe('q', 'Do not log messages to STDOUT').
  describe('h', 'Show this help')

if opts.argv.h
  console.log opts.help()
  process.exit 0

sourceDir = opts.argv._[0]
targetDir = opts.argv._[1]

if not sourceDir? or not targetDir?
  console.log "You must specify source and target directories"
  console.log()
  console.log opts.help()
  process.exit 1

if opts.argv.q
  VERBOSE = false

processDir sourceDir, targetDir, toArray opts.argv.i


