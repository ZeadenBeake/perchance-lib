--- Execution context for a single generator run: holds the RNG, the
-- current variable scope, and the registry of top-level
-- lists/aliases that bare identifiers resolve against.
local RNG = require("perchance.rng")

local Context = {}
Context.__index = Context

--- `registry` maps top-level names to either
-- `{kind="list", list=List}` or `{kind="alias", template=CompiledTemplate}`.
-- It's shared (by reference) across every Context created for a given
-- Generator, since it represents the generator's fixed definitions,
-- not per-run state.
function Context.new(registry, seed)
  return setmetatable({
    registry = registry or {},
    vars = {},
    rng = RNG.new(seed),
  }, Context)
end

--- A child scope sharing the same registry and RNG but with its own
-- variable bindings that fall back to the parent's on lookup. Used
-- for repeat()/if bodies if callers want isolated scoping; the
-- default evaluator uses a single flat scope per run.
function Context:child()
  local c = setmetatable({
    registry = self.registry,
    vars = setmetatable({}, { __index = self.vars }),
    rng = self.rng,
  }, Context)
  return c
end

return Context
