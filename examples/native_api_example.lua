-- Hand-authored generator using perchance-lib's native Lua API
-- directly -- no DSL text, no conversion tool. This is the primary,
-- idiomatic way to use the library; perchance2lua (see
-- fantasy_name.perchance / dnd_npc.perchance in this same directory)
-- is only needed when you're starting from an existing Perchance
-- generator's source instead of writing one from scratch.
--
-- Run with:  lua -e "package.path='../lua/?.lua;../lua/?/init.lua;'..package.path" native_api_example.lua
-- or, from the repo root:  LUA_PATH="./lua/?.lua;./lua/?/init.lua;;" lua examples/native_api_example.lua
local perchance = require("perchance")

local gen = perchance.new()

-- A plain weighted list. Item text is itself Perchance-style
-- template syntax, so list items can reference other lists.
gen:list("rarity", {
  { value = "common", weight = 10 },
  { value = "uncommon", weight = 5 },
  { value = "rare", weight = 2 },
  { value = "legendary", weight = 0.2 },
})

gen:list("material", { "iron", "steel", "silver", "mithril", "obsidian" })

-- A hierarchical list: each top-level entry is itself a named
-- sub-list. `[weaponName[r]]` (dynamic sub-list referencing) picks
-- a leaf consistent with whatever rarity was already rolled.
gen:list("weaponName", {
  { name = "common", value = perchance.List.from({ "sword", "axe", "dagger", "mace" }, "common") },
  { name = "uncommon", value = perchance.List.from({ "longsword", "warhammer", "rapier" }, "uncommon") },
  { name = "rare", value = perchance.List.from({ "greatsword", "halberd" }, "rare") },
  { name = "legendary", value = perchance.List.from({ "Doombringer", "Starfall", "the Last Word" }, "legendary") },
})

-- Grammar method chaining (titleCase/pluralForm/article) and
-- variable assignment that locks in one consistent choice for
-- reuse -- `[r = rarity]` picks a rarity once, and `[weaponName[r]]`
-- later reuses that exact same pick.
gen:list("loot", {
  "{a} [material] [r = rarity] [weaponName[r]]",
})

-- Dynamic odds (`^[cond]`): the weight expression is re-evaluated
-- against the current variable scope every time this list is
-- selected from, so the outcome depends on what's already been rolled.
local encounter = perchance.List.new("encounter")
encounter:addItem({ value = "a lone bandit", weight = perchance.Parser.parse("difficulty == 1") })
encounter:addItem({ value = "a bandit patrol", weight = perchance.Parser.parse("difficulty == 2") })
encounter:addItem({ value = "a bandit warlord and their retinue", weight = perchance.Parser.parse("difficulty > 2") })
gen.registry.encounter = { kind = "list", list = encounter }

-- consumableList: draws without replacement across repeated
-- references, like dealing from a deck -- handy for "no duplicate
-- loot in this chest" type generators.
local chest = perchance.List.from({ "a rusty key", "3 gold coins", "a healing potion", "a torn map", "a dull gem" })
gen.registry.chest = { kind = "list", list = chest }

gen:setRoot("loot")

print("-- Ten loot rolls (weighted rarity, consistent rarity/name pairing): --")
for i = 1, 10 do
  print(gen:run())
end

print("\n-- Dynamic odds driven by a variable set before the roll: --")
for difficulty = 1, 3 do
  local ctx = perchance.Context.new(gen.registry, 1)
  ctx.vars.difficulty = difficulty
  print(("difficulty %d -> %s"):format(difficulty, encounter:selectOne(ctx, perchance.Eval.evalExpr)))
end

print("\n-- Opening one chest: five unique items drawn via consumableList --")
local deck = chest:consumableList()
local ctx = perchance.Context.new(gen.registry, 42)
local items = {}
for i = 1, 5 do
  table.insert(items, deck:selectOne(ctx, perchance.Eval.evalExpr))
end
print(perchance.List.joinItems(items, ", "))

print("\n-- Same seed, reproducible loot roll (useful for tests/replays): --")
print(gen:run(2024))
print(gen:run(2024))
