--- Weighted, hierarchical list -- the core data structure behind
-- every Perchance list.
--
-- An item is a table: { weight = <number|fn|AST|nil>, kind = "text"|"list"|"raw",
-- value = <CompiledTemplate|List|any>, name = <string|nil> }.
--
-- Items of kind "list" double as both a weighted option in their
-- parent's selection pool (selecting one recurses into it) and a
-- named child reachable via `:child(name)` -- this is what makes
-- `[planet]` auto-descend through a hierarchy while `[planet.country]`
-- can still navigate explicitly.
local Template = require("perchance.template")
local Util = require("perchance.util")

local List = {}
List.__index = List

local function isList(v)
  return type(v) == "table" and getmetatable(v) == List
end
List.isList = isList

function List.new(name)
  return setmetatable({
    name = name,
    items = {},
    children = {},
  }, List)
end

--- Add an item. `item.value` may already be a CompiledTemplate/List,
-- or a plain Lua string (auto-compiled into a template) for
-- convenience when building lists through the native API.
function List:addItem(item)
  item = item or {}
  if type(item.value) == "string" then
    item.value = Template.compile(item.value)
    item.kind = item.kind or "text"
  elseif isList(item.value) then
    item.kind = item.kind or "list"
  else
    item.kind = item.kind or "raw"
  end
  table.insert(self.items, item)
  if item.kind == "list" and item.name then
    self.children[item.name] = item.value
  end
  return self
end

--- Convenience builder. `items` is an array where each element is
-- either a plain string, or a table like
-- `{value=..., weight=..., name=...}`.
function List.from(items, name)
  local list = List.new(name)
  for _, raw in ipairs(items or {}) do
    if type(raw) == "table" and not isList(raw) then
      list:addItem(raw)
    else
      list:addItem({ value = raw })
    end
  end
  return list
end

function List:child(name)
  return self.children[name]
end

local function weightOf(item, ctx, evalExpr)
  return Util.weightValue(item.weight, ctx, evalExpr)
end

local function renderItem(item, ctx, evalExpr)
  if item.kind == "list" then
    return item.value:selectOne(ctx, evalExpr)
  elseif item.kind == "text" then
    return item.value:render(ctx, evalExpr)
  end
  return tostring(item.value)
end

local function activePool(self)
  if not self._consumed then return self.items end
  local pool = {}
  for _, it in ipairs(self.items) do
    if not self._consumed[it] then table.insert(pool, it) end
  end
  return pool
end

--- Select a single item (weighted) and render it to a final string.
-- Returns "" if the list (or the remaining pool of a consumableList)
-- is empty.
function List:selectOne(ctx, evalExpr)
  local pool = activePool(self)
  if #pool == 0 then return "" end
  local picked = ctx.rng:weightedPick(pool, function(it) return weightOf(it, ctx, evalExpr) end)
  if not picked then return "" end
  if self._consumed then self._consumed[picked] = true end
  return renderItem(picked, ctx, evalExpr)
end

--- Select `n` items with replacement, each independently weighted.
-- Returns an array of strings.
function List:selectMany(ctx, evalExpr, n)
  local out = {}
  for i = 1, n do out[i] = self:selectOne(ctx, evalExpr) end
  return out
end

--- Select between `nMin` and `nMax` (or exactly `nMin` if `nMax` is
-- nil) distinct items without replacement, weighted. Returns an
-- array of strings.
function List:selectUnique(ctx, evalExpr, nMin, nMax)
  local n = nMin
  if nMax then n = ctx.rng:randomInt(nMin, nMax) end
  local pool = activePool(self)
  n = math.min(n, #pool)
  local remaining = {}
  for i, it in ipairs(pool) do remaining[i] = it end
  local out = {}
  for i = 1, n do
    if #remaining == 0 then break end
    local picked, idx = ctx.rng:weightedPick(remaining, function(it) return weightOf(it, ctx, evalExpr) end)
    if not picked then break end
    table.remove(remaining, idx)
    if self._consumed then self._consumed[picked] = true end
    table.insert(out, renderItem(picked, ctx, evalExpr))
  end
  return out
end

--- Render every item, in order. Returns an array of strings.
function List:selectAll(ctx, evalExpr)
  local out = {}
  for i, it in ipairs(activePool(self)) do
    out[i] = renderItem(it, ctx, evalExpr)
  end
  return out
end

--- Returns a new List that shares this list's items but tracks its
-- own set of consumed (already-selected) items, so repeated
-- selections never repeat until the pool is exhausted. The original
-- list (and any other consumableList copies of it) are unaffected.
function List:consumableList()
  return setmetatable({
    name = self.name,
    items = self.items,
    children = self.children,
    _consumed = {},
  }, List)
end

--- Join an array of strings (e.g. the result of selectMany/
-- selectUnique/selectAll) with `sep` (default ", ").
function List.joinItems(arr, sep)
  return table.concat(arr, sep or ", ")
end

return List
