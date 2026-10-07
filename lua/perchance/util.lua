--- Small dependency-free helpers shared by template.lua and eval.lua.
-- Kept as a leaf module (no requires) to avoid circular dependencies
-- between the template compiler and the expression evaluator.
local Util = {}

--- JS-flavored truthiness: nil, false, 0, "", and NaN are falsy;
-- everything else (including non-empty strings, non-zero numbers,
-- tables) is truthy. Perchance's conditions ("^[cond]", ternaries,
-- if/else, &&/||) are meant to feel like JS, so we match that rather
-- than Lua's own truthiness (where 0 and "" are truthy).
function Util.isTruthy(v)
  if v == nil or v == false then return false end
  if type(v) == "number" then
    if v ~= v then return false end -- NaN
    return v ~= 0
  end
  if type(v) == "string" then return v ~= "" end
  return true
end

--- Resolve a weight spec to a plain number for use in a weighted
-- pick. `w` may be nil (default weight 1), a plain number, a Lua
-- function `function(ctx) -> number`, or an expression AST (dynamic
-- odds, e.g. `^[s == 1]`): truthy/non-zero evaluates to that number
-- (or 1 for non-numeric truthy values), falsy evaluates to 0.
-- `evalExpr` is only required when `w` is an AST.
function Util.weightValue(w, ctx, evalExpr)
  if w == nil then return 1 end
  local tw = type(w)
  if tw == "number" then return w end
  if tw == "function" then return w(ctx) end
  if tw == "table" and w.type then
    local v = evalExpr(w, ctx)
    if type(v) == "number" then return v end
    return Util.isTruthy(v) and 1 or 0
  end
  return 1
end

--- Coerce a value to a number the way arithmetic operators need to;
-- returns nil (not an error) if the value can't reasonably be read
-- as a number.
function Util.toNumber(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then return tonumber(v) end
  if type(v) == "boolean" then return v and 1 or 0 end
  return nil
end

--- Stringify any runtime value the way text interpolation does:
-- List objects get selected down to their final text, arrays are
-- joined the way a JS Array.toString() would (comma, no space),
-- booleans print as "true"/"false", nil becomes "".
-- `ctx` and `evalExpr` are only needed when `v` might be a List.
function Util.stringify(v, ctx, evalExpr)
  if v == nil then return "" end
  if type(v) == "string" then return v end
  if type(v) == "number" then
    if v == math.floor(v) and math.abs(v) < 1e15 then
      return tostring(math.floor(v))
    end
    return tostring(v)
  end
  if type(v) == "boolean" then return v and "true" or "false" end
  if type(v) == "table" then
    if type(v.selectOne) == "function" then
      -- Duck-typed List object.
      return v:selectOne(ctx, evalExpr)
    end
    if type(v.render) == "function" then
      -- Duck-typed CompiledTemplate (e.g. an alias referenced bare).
      return v:render(ctx, evalExpr)
    end
    -- Plain array: join like JS Array#toString (comma, no separator space).
    local parts = {}
    for i, item in ipairs(v) do
      parts[i] = Util.stringify(item, ctx, evalExpr)
    end
    return table.concat(parts, ",")
  end
  return tostring(v)
end

return Util
