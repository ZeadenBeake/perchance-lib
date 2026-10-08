--- Evaluates expression ASTs (produced by perchance.parser) against a
-- Context. This is the piece that ties identifiers to lists/vars,
-- dispatches `.method(...)` calls, and implements operators.
local List = require("perchance.list")
local Grammar = require("perchance.grammar")
local Util = require("perchance.util")

local Eval = {}

-- Methods callable on a List via dot-notation, e.g. `[animal.selectOne]`
-- or `[animal.selectUnique(3, 8)]`. Each receives (list, ctx, evalExpr, args).
local LIST_METHODS = {
  selectOne = function(list, ctx, evalExpr, args)
    return list:selectOne(ctx, evalExpr)
  end,
  selectMany = function(list, ctx, evalExpr, args)
    local n = Util.toNumber(args[1]) or 1
    return list:selectMany(ctx, evalExpr, n)
  end,
  selectUnique = function(list, ctx, evalExpr, args)
    local a, b = Util.toNumber(args[1]), Util.toNumber(args[2])
    return list:selectUnique(ctx, evalExpr, a, b)
  end,
  selectAll = function(list, ctx, evalExpr, args)
    return list:selectAll(ctx, evalExpr)
  end,
  consumableList = function(list, ctx, evalExpr, args)
    return list:consumableList()
  end,
}

-- Methods callable on an array result (e.g. the output of
-- selectMany/selectUnique/selectAll), e.g. `.joinItems(", ")`.
local ARRAY_METHODS = {
  joinItems = function(arr, ctx, evalExpr, args)
    return List.joinItems(arr, args[1])
  end,
}

-- Grammar/case methods callable on a string, e.g. `[noun.pluralForm]`.
local STRING_METHODS = {
  upperCase = function(s) return Grammar.upperCase(s) end,
  lowerCase = function(s) return Grammar.lowerCase(s) end,
  titleCase = function(s) return Grammar.titleCase(s) end,
  sentenceCase = function(s) return Grammar.sentenceCase(s) end,
  pluralForm = function(s) return Grammar.pluralForm(s) end,
  singularForm = function(s) return Grammar.singularForm(s) end,
  pastTense = function(s) return Grammar.pastTense(s) end,
  presentTense = function(s) return Grammar.presentTense(s) end,
  futureTense = function(s) return Grammar.futureTense(s) end,
  possessiveForm = function(s) return Grammar.possessiveForm(s) end,
  negativeForm = function(s) return Grammar.negativeForm(s) end,
  article = function(s) return Grammar.article(s) end,
}

local function methodsFor(value)
  if List.isList(value) then return LIST_METHODS, "list" end
  if type(value) == "string" then return STRING_METHODS, "string" end
  if type(value) == "table" then return ARRAY_METHODS, "array" end
  return nil, type(value)
end

local evalExpr -- forward declaration (recursive)

local function evalIdent(node, ctx)
  local vars = ctx.vars
  if vars[node.name] ~= nil then return vars[node.name] end
  local def = ctx.registry[node.name]
  if def == nil then
    error("perchance: unknown identifier '" .. node.name .. "'")
  end
  if def.kind == "list" then
    return def.list
  elseif def.kind == "alias" then
    return def.template:render(ctx, evalExpr)
  end
  error("perchance: malformed registry entry for '" .. node.name .. "'")
end

-- Note: grammar/case methods (pluralForm, titleCase, etc.) only
-- apply to strings, but it reads naturally to chain them straight
-- off a bare list reference, e.g. `[noun.titleCase]` with no
-- explicit `.selectOne`. When `name` isn't a list method or a named
-- child, and the list has no such child, fall back to selecting the
-- list down to a string and retrying against STRING_METHODS.
local function evalMember(node, ctx)
  local obj = evalExpr(node.object, ctx)
  local methods, kind = methodsFor(obj)
  if methods and methods[node.name] then
    return methods[node.name](obj, ctx, evalExpr, {})
  end
  if kind == "list" then
    local child = obj:child(node.name)
    if child then return child end
    if STRING_METHODS[node.name] then
      return STRING_METHODS[node.name](obj:selectOne(ctx, evalExpr))
    end
  end
  error(("perchance: %s has no method or property '%s'"):format(kind, node.name))
end

local function evalCall(node, ctx)
  local callee = node.callee
  if callee.type ~= "Member" then
    error("perchance: only `object.method(...)` calls are supported")
  end
  local obj = evalExpr(callee.object, ctx)
  local methods, kind = methodsFor(obj)
  local fn = methods and methods[callee.name]
  if fn then
    local args = {}
    for i, argAst in ipairs(node.args) do
      args[i] = evalExpr(argAst, ctx)
    end
    return fn(obj, ctx, evalExpr, args)
  end
  if kind == "list" and STRING_METHODS[callee.name] then
    return STRING_METHODS[callee.name](obj:selectOne(ctx, evalExpr))
  end
  error(("perchance: %s has no method '%s'"):format(kind, callee.name))
end

local function evalIndex(node, ctx)
  local obj = evalExpr(node.object, ctx)
  if not List.isList(obj) then
    error("perchance: dynamic `[...]` indexing requires a list on the left-hand side")
  end
  local key = Util.stringify(evalExpr(node.index, ctx), ctx, evalExpr)
  local child = obj:child(key)
  if child == nil then
    error("perchance: list '" .. (obj.name or "?") .. "' has no entry named '" .. key .. "'")
  end
  return child
end

local function numeric(v)
  local n = Util.toNumber(v)
  if n == nil then
    error("perchance: expected a number, got " .. tostring(v))
  end
  return n
end

local function looseEquals(a, b)
  if type(a) == type(b) then return a == b end
  local an, bn = Util.toNumber(a), Util.toNumber(b)
  if an and bn then return an == bn end
  return tostring(a) == tostring(b)
end

local function evalBinOp(node, ctx)
  local op = node.op
  if op == "&&" then
    local l = evalExpr(node.left, ctx)
    if not Util.isTruthy(l) then return l end
    return evalExpr(node.right, ctx)
  elseif op == "||" then
    local l = evalExpr(node.left, ctx)
    if Util.isTruthy(l) then return l end
    return evalExpr(node.right, ctx)
  end

  local l = evalExpr(node.left, ctx)
  local r = evalExpr(node.right, ctx)

  if op == "+" then
    local ln, rn = Util.toNumber(l), Util.toNumber(r)
    if type(l) == "number" and type(r) == "number" then return l + r end
    return Util.stringify(l, ctx, evalExpr) .. Util.stringify(r, ctx, evalExpr)
  elseif op == "-" then return numeric(l) - numeric(r)
  elseif op == "*" then return numeric(l) * numeric(r)
  elseif op == "/" then return numeric(l) / numeric(r)
  elseif op == "%" then return numeric(l) % numeric(r)
  elseif op == "==" then return looseEquals(l, r)
  elseif op == "!=" then return not looseEquals(l, r)
  elseif op == "<" then return numeric(l) < numeric(r)
  elseif op == ">" then return numeric(l) > numeric(r)
  elseif op == "<=" then return numeric(l) <= numeric(r)
  elseif op == ">=" then return numeric(l) >= numeric(r)
  end
  error("perchance: unsupported operator '" .. tostring(op) .. "'")
end

local function evalUnOp(node, ctx)
  local v = evalExpr(node.value, ctx)
  if node.op == "-" then return -numeric(v) end
  if node.op == "!" then return not Util.isTruthy(v) end
  error("perchance: unsupported unary operator '" .. tostring(node.op) .. "'")
end

-- Recognizes `x.consumableList` / `x.consumableList()` by AST shape,
-- so Assign can special-case it (see below) without needing a
-- separate runtime tag on the List type.
local function isConsumableListExpr(node)
  if node.type == "Member" then return node.name == "consumableList" end
  if node.type == "Call" then return node.callee.type == "Member" and node.callee.name == "consumableList" end
  return false
end

-- Shared by Assign and SilentAssign: evaluate node.value, collapse a
-- bare list reference (or navigation to one) to a single concrete
-- selection so every later read of the variable agrees with it --
-- e.g. `[r = race]` should lock in one race, not reroll on every
-- `[r]`. The one deliberate exception is `.consumableList`, whose
-- entire point is to hand back a reusable list *handle* rather than
-- a draw. Returns the (possibly collapsed) value that got stored.
local function assignTo(node, ctx)
  local v = evalExpr(node.value, ctx)
  if List.isList(v) and not isConsumableListExpr(node.value) then
    v = v:selectOne(ctx, evalExpr)
  end
  ctx.vars[node.name] = v
  return v
end

local DISPATCH = {
  Number = function(node) return node.value end,
  String = function(node) return node.value end,
  Ident = evalIdent,
  Member = evalMember,
  Call = evalCall,
  Index = evalIndex,
  BinOp = evalBinOp,
  UnOp = evalUnOp,
  Ternary = function(node, ctx)
    if Util.isTruthy(evalExpr(node.cond, ctx)) then
      return evalExpr(node.a, ctx)
    end
    return evalExpr(node.b, ctx)
  end,
  Assign = function(node, ctx)
    return assignTo(node, ctx)
  end,
  -- Same binding semantics as Assign (including the bare-list-
  -- collapses-to-one-draw / consumableList-stays-a-handle rules
  -- below), but evaluates to "" instead of the assigned value --
  -- i.e. it assigns without also printing. Useful for locking in a
  -- value you only want to reuse later, e.g. `[c := hairColor]`
  -- followed by `[c]_hair, [c]_tail` with no extra copy printed up
  -- front.
  SilentAssign = function(node, ctx)
    assignTo(node, ctx)
    return ""
  end,
}

--- Evaluate an expression AST node against `ctx`. Returns a Lua
-- value: number, string, boolean, a List (unselected), or an array
-- of strings (from selectMany/selectUnique/selectAll).
evalExpr = function(node, ctx)
  local handler = DISPATCH[node.type]
  if not handler then
    error("perchance.eval: no handler for node type '" .. tostring(node.type) .. "'")
  end
  return handler(node, ctx)
end

Eval.evalExpr = evalExpr

--- Fully render a value (as produced by evalExpr, or a List/
-- CompiledTemplate directly) down to a plain string.
function Eval.stringify(value, ctx)
  return Util.stringify(value, ctx, evalExpr)
end

return Eval
