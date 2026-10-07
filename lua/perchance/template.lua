--- Compiles Perchance-flavored text (containing `[...]` references and
-- `{...}` inline constructs) into a reusable, renderable structure.
--
-- Supported `[...]` content: any expression from perchance.parser
-- (references, dot methods, dynamic `[x]` indexing, assignment,
-- ternary, operators).
--
-- Supported `{...}` content:
--   {option1|option2|...}   inline anonymous list
--   {1-10}, {-5-5}          inline numeric range
--   {a-z}                   inline letter range
--   {a}                     smart article ("a"/"an") for the text that follows
--   {s}                     smart plural suffix applied to the word before it
--   if (cond) {a} else if (cond) {b} else {c}   long-form conditional
--   repeat(n) {body}        repeats body n times
--   anything else           treated as a plain expression
--
-- Escapes: \[ \] \{ \} \= \^ \\ \s \t
local Parser = require("perchance.parser")
local Grammar = require("perchance.grammar")
local Util = require("perchance.util")

local Template = {}

local CompiledTemplate = {}
CompiledTemplate.__index = CompiledTemplate

local ESCAPES = {
  ["["] = "[", ["]"] = "]", ["{"] = "{", ["}"] = "}",
  ["="] = "=", ["^"] = "^", ["\\"] = "\\", s = " ", t = "\t",
}

--- Finds the index of the closing bracket matching the opening
-- bracket/brace/paren at `openIdx`, honoring nested brackets of all
-- three kinds, quoted strings, and backslash escapes. Returns nil if
-- unbalanced.
local function findMatchingClose(str, openIdx)
  local n = #str
  local depth = 1
  local i = openIdx + 1
  while i <= n do
    local c = str:sub(i, i)
    if c == "\\" then
      i = i + 2
    elseif c == '"' or c == "'" then
      local q = c
      i = i + 1
      while i <= n and str:sub(i, i) ~= q do
        if str:sub(i, i) == "\\" then i = i + 1 end
        i = i + 1
      end
      i = i + 1
    elseif c == "[" or c == "{" or c == "(" then
      depth = depth + 1
      i = i + 1
    elseif c == "]" or c == "}" or c == ")" then
      depth = depth - 1
      if depth == 0 then return i end
      i = i + 1
    else
      i = i + 1
    end
  end
  return nil
end

--- Splits `str` on top-level occurrences of `sep` (a single
-- character), ignoring separators nested inside brackets/parens or
-- quoted strings.
local function splitTopLevel(str, sep)
  local parts = {}
  local depth = 0
  local buf = {}
  local i, n = 1, #str
  while i <= n do
    local c = str:sub(i, i)
    if c == "\\" then
      table.insert(buf, c)
      table.insert(buf, str:sub(i + 1, i + 1))
      i = i + 2
    elseif c == '"' or c == "'" then
      local q = c
      table.insert(buf, c)
      i = i + 1
      while i <= n and str:sub(i, i) ~= q do
        table.insert(buf, str:sub(i, i))
        i = i + 1
      end
      if i <= n then
        table.insert(buf, str:sub(i, i))
        i = i + 1
      end
    elseif c == "[" or c == "{" or c == "(" then
      depth = depth + 1
      table.insert(buf, c)
      i = i + 1
    elseif c == "]" or c == "}" or c == ")" then
      depth = depth - 1
      table.insert(buf, c)
      i = i + 1
    elseif c == sep and depth == 0 then
      table.insert(parts, table.concat(buf))
      buf = {}
      i = i + 1
    else
      table.insert(buf, c)
      i = i + 1
    end
  end
  table.insert(parts, table.concat(buf))
  return parts
end

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

-- Scans an inline-list option's text for a trailing top-level '^'
-- weight suffix (e.g. `non-binary^0.1`), mirroring the weight syntax
-- supported in the indentation-based list file format. Returns
-- (remainingText, weightOrNil) where weight is a plain number or an
-- expression AST (for dynamic odds, `^[cond]`).
local function extractInlineWeight(text)
  local depth = 0
  local lastCaret = nil
  local i, n = 1, #text
  while i <= n do
    local c = text:sub(i, i)
    if c == "\\" then
      i = i + 2
    elseif c == '"' or c == "'" then
      local q = c
      i = i + 1
      while i <= n and text:sub(i, i) ~= q do
        if text:sub(i, i) == "\\" then i = i + 1 end
        i = i + 1
      end
      i = i + 1
    elseif c == "[" or c == "{" or c == "(" then
      depth = depth + 1
      i = i + 1
    elseif c == "]" or c == "}" or c == ")" then
      depth = depth - 1
      i = i + 1
    elseif c == "^" and depth == 0 then
      lastCaret = i
      i = i + 1
    else
      i = i + 1
    end
  end
  if not lastCaret then return text, nil end

  local itemText = text:sub(1, lastCaret - 1)
  local spec = trim(text:sub(lastCaret + 1))

  local num = tonumber(spec)
  if num then return itemText, num end

  local a, b = spec:match("^(%d+%.?%d*)%s*/%s*(%d+%.?%d*)$")
  if a and b then return itemText, tonumber(a) / tonumber(b) end

  if spec:match("^%[.*%]$") then
    return itemText, Parser.parse(spec:sub(2, -2))
  end

  -- Not a recognized weight spec -- leave the '^' as literal text.
  return text, nil
end

local function compileBraceContent(inner)
  local trimmed = trim(inner)
  if trimmed == "a" then
    return { kind = "article" }
  elseif trimmed == "s" then
    return { kind = "pluralMarker" }
  end

  local lo, hi = trimmed:match("^(%-?%d+)%s*%-%s*(%-?%d+)$")
  if lo and hi then
    return { kind = "range", numeric = true, lo = tonumber(lo), hi = tonumber(hi) }
  end

  local loL, hiL = trimmed:match("^(%a)%s*%-%s*(%a)$")
  if loL and hiL then
    return { kind = "range", numeric = false, lo = loL, hi = hiL }
  end

  if inner:find("|") then
    local parts = splitTopLevel(inner, "|")
    if #parts > 1 then
      local options, weights = {}, {}
      for idx, part in ipairs(parts) do
        local text, weight = extractInlineWeight(part)
        options[idx] = Template.compile(text)
        weights[idx] = weight
      end
      return { kind = "inlineList", options = options, weights = weights }
    end
  end

  return { kind = "expr", ast = Parser.parse(inner) }
end

local function isWordBoundaryBefore(src, i)
  if i <= 1 then return true end
  return src:sub(i - 1, i - 1):match("[%w_]") == nil
end

local function isWordBoundaryAfter(src, i)
  local c = src:sub(i, i)
  return c == "" or c:match("[%w_]") == nil
end

local function matchKeyword(src, i, kw)
  if src:sub(i, i + #kw - 1) ~= kw then return false end
  if not isWordBoundaryBefore(src, i) then return false end
  if not isWordBoundaryAfter(src, i + #kw) then return false end
  return true
end

local function skipWs(src, i)
  local _, e = src:find("^%s*", i)
  return e + 1
end

-- Parses `(expr)` starting at `i` (which must point at '('). Returns
-- the parsed AST and the index just past the closing ')'.
local function parseParenExpr(src, i)
  if src:sub(i, i) ~= "(" then
    error("perchance.template: expected '(' at position " .. i)
  end
  local closeIdx = findMatchingClose(src, i)
  if not closeIdx then error("perchance.template: unbalanced '(' at position " .. i) end
  local ast = Parser.parse(src:sub(i + 1, closeIdx - 1))
  return ast, closeIdx + 1
end

-- Parses `{body}` starting at `i` (which must point at '{'). Returns
-- the compiled sub-template and the index just past the closing '}'.
local function parseBraceBody(src, i)
  if src:sub(i, i) ~= "{" then
    error("perchance.template: expected '{' at position " .. i)
  end
  local closeIdx = findMatchingClose(src, i)
  if not closeIdx then error("perchance.template: unbalanced '{' at position " .. i) end
  local body = Template.compile(src:sub(i + 1, closeIdx - 1))
  return body, closeIdx + 1
end

-- Parses `if (cond) {body} [else if (cond) {body}]* [else {body}]`
-- starting at `i` (pointing at the 'i' of "if"). Returns the control
-- node and the index just past the construct.
local function parseIfChain(src, i)
  local branches = {}
  i = i + 2 -- past "if"
  i = skipWs(src, i)
  local condAst, bodyNode
  condAst, i = parseParenExpr(src, i)
  i = skipWs(src, i)
  bodyNode, i = parseBraceBody(src, i)
  table.insert(branches, { condAst = condAst, body = bodyNode })

  while true do
    local peekI = skipWs(src, i)
    if matchKeyword(src, peekI, "else") then
      local afterElse = skipWs(src, peekI + 4)
      if matchKeyword(src, afterElse, "if") then
        local nextCond, nextBody
        local j = afterElse + 2
        j = skipWs(src, j)
        nextCond, j = parseParenExpr(src, j)
        j = skipWs(src, j)
        nextBody, j = parseBraceBody(src, j)
        table.insert(branches, { condAst = nextCond, body = nextBody })
        i = j
      else
        local elseBody
        elseBody, i = parseBraceBody(src, afterElse)
        table.insert(branches, { condAst = nil, body = elseBody })
        break
      end
    else
      break
    end
  end

  return { kind = "if", branches = branches }, i
end

-- Parses `repeat(n) {body}` starting at `i` (pointing at the 'r' of
-- "repeat"). Returns the control node and the index just past it.
local function parseRepeat(src, i)
  i = i + 6 -- past "repeat"
  i = skipWs(src, i)
  local countAst, body
  countAst, i = parseParenExpr(src, i)
  i = skipWs(src, i)
  body, i = parseBraceBody(src, i)
  return { kind = "repeat", countAst = countAst, body = body }, i
end

--- Compile raw text into a CompiledTemplate. Does not evaluate
-- anything; evaluation happens at render() time against a Context.
function Template.compile(src)
  local fragments = {}
  local buf = {}
  local i, n = 1, #src

  local function flushLiteral()
    if #buf > 0 then
      table.insert(fragments, { kind = "literal", text = table.concat(buf) })
      buf = {}
    end
  end

  while i <= n do
    local c = src:sub(i, i)
    if c == "\\" then
      local nc = src:sub(i + 1, i + 1)
      table.insert(buf, ESCAPES[nc] or nc)
      i = i + 2
    elseif c == "[" then
      flushLiteral()
      local closeIdx = findMatchingClose(src, i)
      if not closeIdx then error("perchance.template: unmatched '[' at position " .. i) end
      local ast = Parser.parse(src:sub(i + 1, closeIdx - 1))
      table.insert(fragments, { kind = "expr", ast = ast })
      i = closeIdx + 1
    elseif c == "{" then
      flushLiteral()
      local closeIdx = findMatchingClose(src, i)
      if not closeIdx then error("perchance.template: unmatched '{' at position " .. i) end
      table.insert(fragments, compileBraceContent(src:sub(i + 1, closeIdx - 1)))
      i = closeIdx + 1
    elseif matchKeyword(src, i, "if") and src:match("^%s*%(", i + 2) then
      flushLiteral()
      local node, nextI = parseIfChain(src, i)
      table.insert(fragments, node)
      i = nextI
    elseif matchKeyword(src, i, "repeat") and src:match("^%s*%(", i + 6) then
      flushLiteral()
      local node, nextI = parseRepeat(src, i)
      table.insert(fragments, node)
      i = nextI
    else
      table.insert(buf, c)
      i = i + 1
    end
  end
  flushLiteral()

  return setmetatable({ fragments = fragments }, CompiledTemplate)
end

-- Scans forward through already-rendered string parts starting at
-- `fromIdx`, concatenating until non-whitespace is found (enough
-- context for Grammar.article to find the next word).
local function nextWordContext(parts, fromIdx)
  local buf = {}
  for j = fromIdx, #parts do
    local p = parts[j]
    if type(p) == "string" then
      table.insert(buf, p)
      if table.concat(buf):match("%S") then
        return table.concat(buf)
      end
    end
  end
  return table.concat(buf)
end

--- Render this template against `ctx`, using `evalExpr(ast, ctx)` to
-- evaluate any embedded expressions. Always returns a string.
function CompiledTemplate:render(ctx, evalExpr)
  local parts = {}

  for idx, frag in ipairs(self.fragments) do
    local kind = frag.kind
    if kind == "literal" then
      parts[idx] = frag.text
    elseif kind == "expr" then
      parts[idx] = Util.stringify(evalExpr(frag.ast, ctx), ctx, evalExpr)
    elseif kind == "inlineList" then
      local chosen = ctx.rng:weightedPick(frag.options, function(_, optIdx)
        return Util.weightValue(frag.weights[optIdx], ctx, evalExpr)
      end)
      parts[idx] = (chosen or frag.options[1]):render(ctx, evalExpr)
    elseif kind == "range" then
      if frag.numeric then
        parts[idx] = tostring(ctx.rng:randomInt(frag.lo, frag.hi))
      else
        parts[idx] = string.char(ctx.rng:randomInt(frag.lo:byte(), frag.hi:byte()))
      end
    elseif kind == "if" then
      local rendered = ""
      for _, branch in ipairs(frag.branches) do
        if branch.condAst == nil or Util.isTruthy(evalExpr(branch.condAst, ctx)) then
          rendered = branch.body:render(ctx, evalExpr)
          break
        end
      end
      parts[idx] = rendered
    elseif kind == "repeat" then
      local count = Util.toNumber(evalExpr(frag.countAst, ctx)) or 0
      local buf = {}
      for k = 1, count do buf[k] = frag.body:render(ctx, evalExpr) end
      parts[idx] = table.concat(buf)
    elseif kind == "article" or kind == "pluralMarker" then
      parts[idx] = false -- resolved in the second pass below
    end
  end

  -- Second pass: resolve {a}/{s} smart-grammar markers against
  -- neighboring already-rendered text.
  for idx, frag in ipairs(self.fragments) do
    if frag.kind == "article" then
      parts[idx] = Grammar.article(nextWordContext(parts, idx + 1))
    elseif frag.kind == "pluralMarker" then
      if idx > 1 and type(parts[idx - 1]) == "string" then
        parts[idx - 1] = Grammar.pluralForm(parts[idx - 1])
      end
      parts[idx] = ""
    end
  end

  return table.concat(parts)
end

Template.CompiledTemplate = CompiledTemplate
Template.findMatchingClose = findMatchingClose
Template.splitTopLevel = splitTopLevel

return Template
