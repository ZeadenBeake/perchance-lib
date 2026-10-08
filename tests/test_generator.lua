local function thisDir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end
local HERE = thisDir()
package.path = HERE .. "/../lua/?.lua;" .. HERE .. "/../lua/?/init.lua;" .. HERE .. "/?.lua;" .. package.path

local T = require("testkit").new()
local perchance = require("perchance")

-- Basic build-and-run.
do
  local gen = perchance.new()
  gen:list("adjective", { "big", "small", "red" })
  gen:list("noun", { "cat", "dog" })
  gen:list("title", { "[adjective] [noun]" })
  gen:setRoot("title")

  local pattern = "^[%a]+ [%a]+$"
  for i = 1, 30 do
    local out = gen:run()
    T:ok(out:match(pattern) ~= nil, "generated output matches '<adjective> <noun>' shape: " .. out)
  end
end

-- First registered list becomes the root automatically.
do
  local gen = perchance.new()
  gen:list("greeting", { "hello" })
  T:eq(gen:run(), "hello", "first list becomes root automatically")
end

-- Determinism: same seed -> same output, every time.
do
  local gen = perchance.new()
  gen:list("thing", { "a", "b", "c", "d", "e", "f", "g", "h" })
  local first = gen:run(12345)
  for i = 1, 10 do
    T:eq(gen:run(12345), first, "same seed reproduces the same output on repeated runs")
  end
end

-- Unseeded runs vary (overwhelmingly likely with 8 options over 20 draws).
do
  local gen = perchance.new()
  gen:list("thing", { "a", "b", "c", "d", "e", "f", "g", "h" })
  local seen = {}
  for i = 1, 20 do seen[gen:run()] = true end
  local distinctCount = 0
  for _ in pairs(seen) do distinctCount = distinctCount + 1 end
  T:ok(distinctCount > 1, "unseeded runs produce varied output")
end

-- Alias definitions.
do
  local gen = perchance.new()
  gen:alias("gender", "{female|male|non-binary^0.1}")
  local allowed = { female = true, male = true, ["non-binary"] = true }
  for i = 1, 20 do
    T:ok(allowed[gen:run()], "alias root produces one of its defined options")
  end
end

-- renderString against a generator's existing registry.
do
  local gen = perchance.new()
  gen:list("noun", { "cat", "dog" })
  local out = gen:renderString("a [noun.pluralForm.titleCase]", 1)
  T:ok(out == "a Cats" or out == "a Dogs", "renderString resolves against the generator's registry: " .. out)
end

-- Regression: assigning a bare list reference (no explicit
-- `.selectOne`) must lock in ONE concrete selection that every later
-- read of that variable agrees with -- otherwise each read would
-- independently reroll, breaking patterns like matching a name to
-- the race it was drawn from via dynamic sub-list referencing.
do
  local gen = perchance.new()
  gen:list("race", { "human", "elf", "dwarf" })
  local npcName = perchance.List.new("npcName")
  npcName:addItem({ name = "human", value = perchance.List.from({ "Alden" }, "human") })
  npcName:addItem({ name = "elf", value = perchance.List.from({ "Silvaren" }, "elf") })
  npcName:addItem({ name = "dwarf", value = perchance.List.from({ "Thrain" }, "dwarf") })
  gen.registry.npcName = { kind = "list", list = npcName }
  gen:alias("output", "[r = race] named [npcName[r]], again: [r]")
  gen:setRoot("output")

  local expectedName = { human = "Alden", elf = "Silvaren", dwarf = "Thrain" }
  for i = 1, 30 do
    local out = gen:run()
    local race, name, raceAgain = out:match("^(%a+) named (%a+), again: (%a+)$")
    T:ok(race ~= nil, "regression output parses: " .. tostring(out))
    if race then
      T:eq(name, expectedName[race], "assigned race's name matches that race (not a different reroll)")
      T:eq(raceAgain, race, "re-reading the assigned variable agrees with its first use")
    end
  end
end

-- consumableList is the deliberate exception: assigning it keeps the
-- list *handle* (not an eagerly-collapsed string) so repeated
-- `.selectOne` calls keep drawing without replacement.
do
  -- Note: referencing a consumableList for display (including the
  -- assignment itself) draws a card, same as an explicit .selectOne
  -- -- so this template deliberately separates every reference with
  -- a literal "-" to make each of the three draws unambiguous.
  local gen = perchance.new()
  gen:list("deck", { "red", "green", "blue" })
  gen:alias("output", "[cl = deck.consumableList]-[cl.selectOne]-[cl.selectOne]")
  gen:setRoot("output")
  local out = gen:run(1)
  local first, a, b = out:match("^(%a+)-(%a+)-(%a+)$")
  T:ok(first ~= nil, "consumableList assignment output parses: " .. tostring(out))
  if first then
    T:ok(first ~= a and first ~= b and a ~= b, "consumableList draws keep being distinct across the assignment display and explicit selectOne calls: " .. out)
  end
end

-- Regression (issue #2): `:=` assigns without printing, reusing the
-- hair-color-across-several-tags scenario that motivated the
-- request. Same consistency guarantee as `=`: every later read
-- agrees with the first.
do
  local gen = perchance.new()
  gen:list("hairColor", { "red", "blonde", "black" })
  gen:alias("output", "[c := hairColor][c]_hair, [c]_tail")
  gen:setRoot("output")

  for i = 1, 20 do
    local out = gen:run()
    local a, b = out:match("^(%a+)_hair, (%a+)_tail$")
    T:ok(a ~= nil, "silent-assign output has no leading printed value: " .. tostring(out))
    if a then
      T:eq(b, a, "both tags agree on the one silently-assigned hair color")
    end
  end
end

-- `:=` keeps the same consumableList-stays-a-handle exception as `=`.
do
  local gen = perchance.new()
  gen:list("deck", { "red", "green", "blue" })
  gen:alias("output", "[cl := deck.consumableList][cl.selectOne]-[cl.selectOne]-[cl.selectOne]")
  gen:setRoot("output")
  local out = gen:run(1)
  local a, b, c = out:match("^(%a+)-(%a+)-(%a+)$")
  T:ok(a ~= nil, "silent-assigned consumableList output parses: " .. tostring(out))
  if a then
    T:ok(a ~= b and a ~= c and b ~= c, "silent-assigned consumableList still draws three distinct cards: " .. out)
  end
end

-- setRoot switches which definition :run() produces.
do
  local gen = perchance.new()
  gen:list("a", { "A-ONLY" })
  gen:list("b", { "B-ONLY" })
  T:eq(gen:run(), "A-ONLY", "root defaults to the first definition")
  gen:setRoot("b")
  T:eq(gen:run(), "B-ONLY", "setRoot switches the active root")
end

return T:summary("generator")
