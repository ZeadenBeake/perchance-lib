--- The native, idiomatic Lua API for building a Perchance-style
-- generator by hand (no DSL text required). A Generator is a named
-- registry of lists/aliases plus a chosen root to run.
local List = require("perchance.list")
local Context = require("perchance.context")
local Eval = require("perchance.eval")
local Template = require("perchance.template")

local Generator = {}
Generator.__index = Generator

function Generator.new()
  return setmetatable({
    registry = {},
    root = nil,
  }, Generator)
end

--- Register a top-level list under `name`. `list` may be a List
-- instance, or an array of items (passed through List.from).
-- The first definition registered becomes the root (the thing
-- :run() produces) unless :setRoot() is called explicitly.
function Generator:list(name, items)
  local list = List.isList(items) and items or List.from(items, name)
  self.registry[name] = { kind = "list", list = list }
  if self.root == nil then self.root = name end
  return list
end

--- Register a top-level alias/macro under `name`: a plain template
-- string (or a pre-compiled CompiledTemplate) that gets rendered
-- fresh every time `[name]` is referenced, e.g. `gen:alias("gender",
-- "{female|male|non-binary^0.1}")`.
function Generator:alias(name, templateOrString)
  local tpl = templateOrString
  if type(tpl) == "string" then tpl = Template.compile(tpl) end
  self.registry[name] = { kind = "alias", template = tpl }
  if self.root == nil then self.root = name end
  return tpl
end

--- Explicitly choose which top-level name :run() should produce.
function Generator:setRoot(name)
  assert(self.registry[name], "perchance.generator: no such definition '" .. tostring(name) .. "'")
  self.root = name
  return self
end

--- Run the generator once and return the resulting string. `seed`
-- is optional; omit it for a fresh random result each call, or pass
-- a fixed number to get a fully reproducible output.
function Generator:run(seed)
  assert(self.root, "perchance.generator: generator has no root definition to run")
  local ctx = Context.new(self.registry, seed)
  local def = self.registry[self.root]
  if def.kind == "list" then
    return def.list:selectOne(ctx, Eval.evalExpr)
  end
  return def.template:render(ctx, Eval.evalExpr)
end

--- Render an arbitrary one-off template string against this
-- generator's registry (handy for testing a fragment without
-- defining a whole new root).
function Generator:renderString(src, seed)
  local ctx = Context.new(self.registry, seed)
  return Template.compile(src):render(ctx, Eval.evalExpr)
end

return Generator
