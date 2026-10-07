local function thisDir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end
local HERE = thisDir()
package.path = HERE .. "/../lua/?.lua;" .. HERE .. "/../lua/?/init.lua;" .. HERE .. "/?.lua;" .. package.path

local T = require("testkit").new()
local List = require("perchance.list")
local Context = require("perchance.context")
local Eval = require("perchance.eval")
local Parser = require("perchance.parser")

-- Basic weighted selection ratio.
do
  local weighted = List.new()
  weighted:addItem({ value = "common", weight = 9 })
  weighted:addItem({ value = "rare", weight = 1 })
  local ctx = Context.new({}, 11)
  local counts = { common = 0, rare = 0 }
  for i = 1, 20000 do
    local pick = weighted:selectOne(ctx, Eval.evalExpr)
    counts[pick] = counts[pick] + 1
  end
  T:approx(counts.common / counts.rare, 9, 1.0, "List:selectOne respects weight ratio over many trials")
end

-- Hierarchical auto-descend: selecting the parent recurses into a
-- randomly chosen named branch.
do
  local female = List.from({ "Anita", "Jessica" }, "female")
  local male = List.from({ "Kalid", "Bob" }, "male")
  local names = List.new("names")
  names:addItem({ value = female, name = "female" })
  names:addItem({ value = male, name = "male" })

  local ctx = Context.new({}, 1)
  local known = { Anita = true, Jessica = true, Kalid = true, Bob = true }
  for i = 1, 50 do
    local v = names:selectOne(ctx, Eval.evalExpr)
    T:ok(known[v], "hierarchical list auto-descends to a known leaf: got " .. tostring(v))
  end
end

-- Explicit child navigation.
do
  local female = List.from({ "Anita", "Jessica" }, "female")
  local names = List.new("names")
  names:addItem({ value = female, name = "female" })
  T:eq(names:child("female"), female, "child() returns the named sub-list")
  T:eq(names:child("nope"), nil, "child() returns nil for unknown names")
end

-- selectMany (with replacement): length matches request, every
-- element is a valid option.
do
  local colors = List.from({ "red", "green", "blue" })
  local ctx = Context.new({}, 2)
  local many = colors:selectMany(ctx, Eval.evalExpr, 10)
  T:eq(#many, 10, "selectMany returns the requested count")
  local allowed = { red = true, green = true, blue = true }
  for _, v in ipairs(many) do
    T:ok(allowed[v], "selectMany element is a valid list option")
  end
end

-- selectUnique (without replacement): no duplicates, bounded by pool size.
do
  local colors = List.from({ "red", "green", "blue", "yellow", "purple" })
  local ctx = Context.new({}, 3)
  local unique = colors:selectUnique(ctx, Eval.evalExpr, 4)
  T:eq(#unique, 4, "selectUnique(4) returns exactly 4 items")
  local seen = {}
  for _, v in ipairs(unique) do
    T:ok(not seen[v], "selectUnique never repeats an item: " .. v)
    seen[v] = true
  end

  local overrequest = colors:selectUnique(ctx, Eval.evalExpr, 100)
  T:eq(#overrequest, 5, "selectUnique caps at the pool size when asked for more than available")

  local ranged = colors:selectUnique(ctx, Eval.evalExpr, 2, 4)
  T:ok(#ranged >= 2 and #ranged <= 4, "selectUnique(min,max) picks a count within [min,max]")
end

-- selectAll returns every item, in order.
do
  local colors = List.from({ "red", "green", "blue" })
  local ctx = Context.new({}, 4)
  local all = colors:selectAll(ctx, Eval.evalExpr)
  T:eq(table.concat(all, ","), "red,green,blue", "selectAll preserves definition order")
end

-- joinItems.
do
  T:eq(List.joinItems({ "a", "b", "c" }), "a, b, c", "joinItems default separator")
  T:eq(List.joinItems({ "a", "b", "c" }, "-"), "a-b-c", "joinItems custom separator")
end

-- consumableList: draws without replacement across repeated calls,
-- then returns "" once exhausted; the original list is untouched.
do
  local colors = List.from({ "red", "green", "blue" })
  local ctx = Context.new({}, 5)
  local deck = colors:consumableList()
  local drawn = {}
  for i = 1, 3 do
    local v = deck:selectOne(ctx, Eval.evalExpr)
    T:ok(not drawn[v], "consumableList never redraws an already-drawn item")
    drawn[v] = true
  end
  T:eq(deck:selectOne(ctx, Eval.evalExpr), "", "consumableList returns empty string once exhausted")

  -- original list still has all three items available.
  local originalDrawn = {}
  for i = 1, 20 do
    originalDrawn[colors:selectOne(ctx, Eval.evalExpr)] = true
  end
  T:ok(originalDrawn.red and originalDrawn.green and originalDrawn.blue,
    "original list is unaffected by a consumableList copy's consumption")
end

-- Dynamic odds: a weight AST that's re-evaluated per selection
-- against the current variable scope.
do
  local dyn = List.new()
  dyn:addItem({ value = "not great", weight = Parser.parse("s == 1") })
  dyn:addItem({ value = "good", weight = Parser.parse("s == 2") })
  dyn:addItem({ value = "great", weight = Parser.parse("s > 2") })

  local ctx = Context.new({}, 1)
  ctx.vars.s = 1
  T:eq(dyn:selectOne(ctx, Eval.evalExpr), "not great", "dynamic odds select the only-truthy branch (s=1)")
  ctx.vars.s = 2
  T:eq(dyn:selectOne(ctx, Eval.evalExpr), "good", "dynamic odds select the only-truthy branch (s=2)")
  ctx.vars.s = 5
  T:eq(dyn:selectOne(ctx, Eval.evalExpr), "great", "dynamic odds select the only-truthy branch (s=5)")
end

-- Empty list selectOne returns "" rather than erroring.
do
  local empty = List.new()
  local ctx = Context.new({}, 1)
  T:eq(empty:selectOne(ctx, Eval.evalExpr), "", "selectOne on an empty list returns empty string")
end

return T:summary("list")
