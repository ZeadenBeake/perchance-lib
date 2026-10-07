local function thisDir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end
local HERE = thisDir()
package.path = HERE .. "/../lua/?.lua;" .. HERE .. "/../lua/?/init.lua;" .. HERE .. "/?.lua;" .. package.path

local T = require("testkit").new()
local RNG = require("perchance.rng")

-- Determinism: same seed -> identical sequence.
do
  local a, b = RNG.new(42), RNG.new(42)
  for i = 1, 20 do
    T:eq(a:random(), b:random(), "same seed produces same sequence at step " .. i)
  end
end

-- Different seeds -> (overwhelmingly likely) different sequences.
do
  local a, b = RNG.new(1), RNG.new(2)
  local same = true
  for i = 1, 5 do
    if a:random() ~= b:random() then same = false end
  end
  T:ok(not same, "different seeds produce different sequences")
end

-- randomInt bounds.
do
  local r = RNG.new(7)
  for i = 1, 500 do
    local v = r:randomInt(1, 6)
    T:ok(v >= 1 and v <= 6 and v == math.floor(v), "randomInt(1,6) in range and integral")
  end
  for i = 1, 100 do
    local v = r:randomInt(-5, 5)
    T:ok(v >= -5 and v <= 5, "randomInt(-5,5) in range")
  end
end

-- shuffled preserves the multiset of elements.
do
  local r = RNG.new(3)
  local original = { 1, 2, 3, 4, 5 }
  local shuffled = r:shuffled(original)
  T:eq(#shuffled, #original, "shuffled preserves length")
  local seen = {}
  for _, v in ipairs(shuffled) do seen[v] = true end
  for _, v in ipairs(original) do
    T:ok(seen[v], "shuffled retains element " .. v)
  end
end

-- weightedPick respects relative weights within tolerance over many trials.
do
  local r = RNG.new(99)
  local items = { "common", "rare" }
  local counts = { common = 0, rare = 0 }
  local trials = 20000
  for i = 1, trials do
    local pick = r:weightedPick(items, function(it) return it == "common" and 9 or 1 end)
    counts[pick] = counts[pick] + 1
  end
  local ratio = counts.common / counts.rare
  T:approx(ratio, 9, 1.0, "weightedPick 9:1 ratio holds within tolerance over " .. trials .. " trials")
end

-- weightedPick with all-zero weights returns nil.
do
  local r = RNG.new(1)
  local pick = r:weightedPick({ "a", "b" }, function() return 0 end)
  T:eq(pick, nil, "weightedPick returns nil when total weight is zero")
end

return T:summary("rng")
