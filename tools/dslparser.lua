--- Parses the plain-text list syntax used in the Perchance web editor
-- (the "Lists" panel: indentation-based list definitions, weighted
-- items, nested sub-lists, top-level aliases, comments) into a
-- lightweight file-level AST that tools/codegen.lua turns into a
-- standalone Lua script.
--
-- This parser deliberately only reads the plain list/alias syntax --
-- not the separate Output/Code/Config panels, and not interactive
-- input fields -- matching the scope of generators that "don't take
-- inputs" referenced in this library's design brief. See README.md
-- for the exact supported subset.
--
-- Supported per-line syntax:
--   name                         starts a list definition
--   name = <template text>       defines a zero-arg alias/macro
--   <indent>item text             a list item (one tab or two spaces
--                                  per indent level; deeper indentation
--                                  nests a sub-list under the
--                                  preceding item)
--   <indent>item text^3            weight (also `^1/10` or `^[cond]`
--                                  for dynamic odds)
--   // comment                    rest of line ignored
--
-- The item text itself is left untouched (escapes and all) -- it is
-- plain Perchance template text, compiled later by perchance.template
-- when the generated script runs `perchance.List.from(...)`.
local DslParser = {}

local function stripComment(line)
  local i, n = 1, #line
  while i <= n - 1 do
    local c = line:sub(i, i)
    if c == "\\" then
      i = i + 2
    elseif c == '"' or c == "'" then
      local q = c
      i = i + 1
      while i <= n and line:sub(i, i) ~= q do
        if line:sub(i, i) == "\\" then i = i + 1 end
        i = i + 1
      end
      i = i + 1
    elseif c == "/" and line:sub(i + 1, i + 1) == "/" then
      return line:sub(1, i - 1)
    else
      i = i + 1
    end
  end
  return line
end

local function computeDepth(indent)
  local depth = 0
  local i, n = 1, #indent
  while i <= n do
    if indent:sub(i, i) == "\t" then
      depth = depth + 1
      i = i + 1
    elseif indent:sub(i, i + 1) == "  " then
      depth = depth + 1
      i = i + 2
    else
      break
    end
  end
  return depth
end

--- Splits raw source into non-blank, comment-stripped lines with
-- their indentation depth and original line number (for errors).
local function preprocessLines(src)
  local out = {}
  local lineNo = 0
  for raw in (src .. "\n"):gmatch("([^\n]*)\n") do
    lineNo = lineNo + 1
    local noComment = stripComment(raw)
    local indent, rest = noComment:match("^(%s*)(.*)$")
    local trimmed = rest:match("^(.-)%s*$")
    if trimmed ~= "" then
      table.insert(out, { depth = computeDepth(indent), text = trimmed, lineNo = lineNo })
    end
  end
  return out
end

-- Scans `text` for the last top-level (not nested in brackets/
-- quotes) '^' and interprets what follows as a weight spec. Returns
-- (itemText, weightSpecOrNil).
local function extractWeight(text)
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
  local spec = text:sub(lastCaret + 1):match("^%s*(.-)%s*$")

  local num = tonumber(spec)
  if num then
    return itemText:match("^(.-)%s*$"), { kind = "number", value = num }
  end

  local a, b = spec:match("^(%d+%.?%d*)%s*/%s*(%d+%.?%d*)$")
  if a and b then
    return itemText:match("^(.-)%s*$"), { kind = "fraction", num = tonumber(a), den = tonumber(b) }
  end

  if spec:match("^%[.*%]$") then
    return itemText:match("^(.-)%s*$"), { kind = "dynamic", expr = spec:sub(2, -2) }
  end

  -- Not a recognized weight spec (e.g. a literal '^' in prose) --
  -- leave the text untouched and don't assign a weight.
  return text, nil
end

local function splitAliasLine(text, lineNo)
  local name, after = text:match("^([%a_][%w_]*)%s*(.*)$")
  if not name then
    error(("perchance.dslparser: malformed definition name at line %d: %q"):format(lineNo, text))
  end
  if after == "" then
    return name, nil
  end
  if after:sub(1, 1) == "=" and after:sub(2, 2) ~= "=" then
    return name, after:sub(2):match("^%s*(.-)%s*$")
  end
  error(("perchance.dslparser: unexpected content after definition name at line %d: %q"):format(lineNo, text))
end

--- Parse Perchance list-syntax source text into a file AST:
--   { order = {name, ...}, defs = { [name] = def }, root = name }
-- where def is either:
--   { kind = "alias", text = "<template text>" }
--   { kind = "list", items = { item, ... } }
-- and an item is:
--   { text = "<template text>", weight = weightSpecOrNil, children = itemsOrNil }
function DslParser.parse(src)
  local lines = preprocessLines(src)
  local i, n = 1, #lines

  local function parseItemsAtDepth(parentDepth)
    local items = {}
    while i <= n and lines[i].depth > parentDepth do
      local line = lines[i]
      local itemDepth = line.depth
      i = i + 1
      local text, weight = extractWeight(line.text)
      local item = { text = text, weight = weight }
      if i <= n and lines[i].depth > itemDepth then
        item.children = parseItemsAtDepth(itemDepth)
      end
      table.insert(items, item)
    end
    return items
  end

  local order = {}
  local defs = {}

  while i <= n do
    local line = lines[i]
    if line.depth ~= 0 then
      error(("perchance.dslparser: unexpected indentation at line %d (definitions must start at column 0): %q")
        :format(line.lineNo, line.text))
    end
    local name, aliasText = splitAliasLine(line.text, line.lineNo)
    if defs[name] then
      error(("perchance.dslparser: duplicate definition '%s' at line %d"):format(name, line.lineNo))
    end
    i = i + 1
    if aliasText then
      defs[name] = { kind = "alias", text = aliasText }
    else
      defs[name] = { kind = "list", items = parseItemsAtDepth(0) }
    end
    table.insert(order, name)
  end

  if #order == 0 then
    error("perchance.dslparser: no definitions found in source")
  end

  local root = defs.output and "output" or order[1]
  return { order = order, defs = defs, root = root }
end

return DslParser
