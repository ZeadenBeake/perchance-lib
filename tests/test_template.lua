local function thisDir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end
local HERE = thisDir()
package.path = HERE .. "/../lua/?.lua;" .. HERE .. "/../lua/?/init.lua;" .. HERE .. "/?.lua;" .. package.path

local T = require("testkit").new()
local Template = require("perchance.template")
local Context = require("perchance.context")
local Eval = require("perchance.eval")

local function render(src, seed, registry)
  return Template.compile(src):render(Context.new(registry or {}, seed), Eval.evalExpr)
end

T:eq(render("hello world", 1), "hello world", "literal text passes through")
T:eq(render("literal \\[brackets\\] and \\{braces\\}", 1), "literal [brackets] and {braces}", "escapes")
T:eq(render("a\\sb\\tc", 1), "a b\tc", "\\s and \\t escapes")

-- Regression (issue #1): an unrecognized escape keeps its backslash
-- instead of silently dropping it, so text meant for another
-- consumer's own escaping rules (e.g. Stable Diffusion prompt
-- syntax's `\(`/`\)` for literal parentheses) passes through intact.
T:eq(render([[hair_ornament \(object\)]], 1), [[hair_ornament \(object\)]],
  "unrecognized escape \\( \\) keeps its backslash")
T:eq(render([[unknown \q escape]], 1), [[unknown \q escape]], "unrecognized escape \\q keeps its backslash generally")
T:eq(render([[trailing backslash\]], 1), [[trailing backslash\]], "a trailing lone backslash is preserved, not dropped")

do
  local ctx = Context.new({}, 1)
  local tpl = Template.compile("[1 + 2]")
  T:eq(tpl:render(ctx, Eval.evalExpr), "3", "arithmetic expression in brackets")
end

do
  local tpl = Template.compile("[x = 10][x > 5 ? \"big\" : \"small\"]")
  T:eq(tpl:render(Context.new({}, 1), Eval.evalExpr), "10big", "assignment renders inline, then is reusable")
end

-- numeric range bounds hold over many trials
do
  local tpl = Template.compile("{1-6}")
  local ctx = Context.new({}, 1)
  for i = 1, 300 do
    local v = tonumber(tpl:render(ctx, Eval.evalExpr))
    T:ok(v >= 1 and v <= 6, "numeric range {1-6} stays in bounds")
  end
end

-- negative numeric range
do
  local tpl = Template.compile("{-5-5}")
  local ctx = Context.new({}, 2)
  local sawNegative = false
  for i = 1, 300 do
    local v = tonumber(tpl:render(ctx, Eval.evalExpr))
    T:ok(v >= -5 and v <= 5, "negative numeric range {-5-5} stays in bounds")
    if v < 0 then sawNegative = true end
  end
  T:ok(sawNegative, "negative numeric range actually produces negative values")
end

-- letter range
do
  local tpl = Template.compile("{a-e}")
  local ctx = Context.new({}, 3)
  for i = 1, 100 do
    local v = tpl:render(ctx, Eval.evalExpr)
    T:ok(#v == 1 and v >= "a" and v <= "e", "letter range {a-e} stays in bounds")
  end
end

-- inline list membership
do
  local tpl = Template.compile("{red|green|blue}")
  local ctx = Context.new({}, 4)
  local allowed = { red = true, green = true, blue = true }
  local seen = {}
  for i = 1, 100 do
    local v = tpl:render(ctx, Eval.evalExpr)
    T:ok(allowed[v], "inline list only produces listed options")
    seen[v] = true
  end
  T:ok(seen.red and seen.green and seen.blue, "inline list eventually produces every option")
end

-- inline list with nested bracket expressions (parser must respect nesting)
do
  local tpl = Template.compile("{[x=1]|[x=2]}")
  local v = tpl:render(Context.new({}, 5), Eval.evalExpr)
  T:ok(v == "1" or v == "2", "inline list options may contain bracket expressions")
end

-- if/else and else-if chains
do
  local tpl = Template.compile("[x = 10]if (x > 5) {big} else {small}")
  T:eq(tpl:render(Context.new({}, 1), Eval.evalExpr), "10big", "if/else true branch")
end
do
  local tpl = Template.compile("[x = 1]if (x > 5) {big} else if (x > 0) {medium} else {small}")
  T:eq(tpl:render(Context.new({}, 1), Eval.evalExpr), "1medium", "if/else-if branch")
end
do
  local tpl = Template.compile("[x = -1]if (x > 5) {big} else if (x > 0) {medium} else {small}")
  T:eq(tpl:render(Context.new({}, 1), Eval.evalExpr), "-1small", "if/else-if falls through to final else")
end
do
  -- "if" appearing in prose must not be misparsed as the keyword
  local tpl = Template.compile("ask if you dare")
  T:eq(tpl:render(Context.new({}, 1), Eval.evalExpr), "ask if you dare", "bare word 'if' in prose is left alone")
end

-- repeat()
do
  local tpl = Template.compile("[n = 3]repeat(n) {ha}")
  T:eq(tpl:render(Context.new({}, 1), Eval.evalExpr), "3hahaha", "repeat(n) repeats body n times")
end
do
  local tpl = Template.compile("repeat(0) {ha}")
  T:eq(tpl:render(Context.new({}, 1), Eval.evalExpr), "", "repeat(0) produces nothing")
end

-- smart grammar: {a}/{s}
do
  local tpl = Template.compile("I saw {a} apple and {a} banana")
  T:eq(tpl:render(Context.new({}, 1), Eval.evalExpr), "I saw an apple and a banana", "{a} picks a/an correctly")
end
do
  local tpl = Template.compile("I caught a fish{s} and a box{s}")
  T:eq(tpl:render(Context.new({}, 1), Eval.evalExpr), "I caught a fishes and a boxes", "{s} pluralizes preceding word")
end

-- unmatched brackets raise clear errors instead of hanging/crashing oddly
T:errors(function() Template.compile("[unterminated") end, "unmatched '[' errors")
T:errors(function() Template.compile("{unterminated") end, "unmatched '{' errors")

return T:summary("template")
