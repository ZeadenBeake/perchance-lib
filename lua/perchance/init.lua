--- perchance-lib: a Lua reimplementation of the text-generation
-- engine behind perchance.org random generators.
--
-- Two ways to use it:
--
--  1. Native Lua API (this module) -- build generators directly in
--     Lua with perchance.Generator / perchance.List. Item text can
--     use the same `[ref]`/`{a|b|c}` mini-syntax as Perchance itself.
--
--  2. Convert an existing Perchance generator's list syntax into a
--     standalone Lua script with the `perchance2lua` tool (see
--     tools/dslparser.lua, tools/codegen.lua, bin/perchance2lua).
--     The generated script only needs this runtime, not the DSL
--     parser.
local Perchance = {
  _VERSION = "0.1.0",
}

Perchance.RNG = require("perchance.rng")
Perchance.Grammar = require("perchance.grammar")
Perchance.Lexer = require("perchance.lexer")
Perchance.Parser = require("perchance.parser")
Perchance.Template = require("perchance.template")
Perchance.List = require("perchance.list")
Perchance.Context = require("perchance.context")
Perchance.Eval = require("perchance.eval")
Perchance.Generator = require("perchance.generator")

--- Convenience: create a new empty generator.
function Perchance.new()
  return Perchance.Generator.new()
end

--- Convenience: compile a template string once and render it
-- immediately with a fresh, throwaway context (no persistent
-- registry, so `[ref]` to other lists won't resolve -- use
-- Generator for anything beyond a single self-contained snippet).
function Perchance.render(src, seed)
  local ctx = Perchance.Context.new({}, seed)
  return Perchance.Template.compile(src):render(ctx, Perchance.Eval.evalExpr)
end

return Perchance
