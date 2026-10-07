--- Seedable, portable pseudo-random number generator.
--
-- Lua's built-in math.random is not guaranteed to behave the same way
-- across Lua versions/platforms (5.1's rand()-based generator differs
-- from 5.4's Xoshiro256), which makes reproducible generators impossible.
-- This module implements a small, self-contained 32-bit LCG using only
-- plain floating point arithmetic (+ - * %), so it produces identical
-- sequences on any Lua 5.1-5.4 / LuaJIT interpreter given the same seed.
local RNG = {}
RNG.__index = RNG

local MULT = 1103515245
local INC = 12345
local MODULUS = 2147483648 -- 2^31

local function normalizeSeed(seed)
  if seed == nil then
    seed = os.time() * 1000 + math.floor((os.clock() or 0) * 1000000) % 1000
  end
  seed = seed % MODULUS
  if seed < 0 then seed = seed + MODULUS end
  return seed
end

--- Create a new RNG instance. `seed` may be any number or nil (uses the
-- current time). Two RNGs created with the same seed always produce the
-- same sequence of outputs.
function RNG.new(seed)
  local self = setmetatable({}, RNG)
  self:seed(seed)
  return self
end

function RNG:seed(seed)
  self.state = normalizeSeed(seed)
  -- Burn one step so that seed=0 and seed=1 don't produce visibly
  -- correlated first outputs.
  self:nextRaw()
  return self
end

function RNG:nextRaw()
  self.state = (self.state * MULT + INC) % MODULUS
  return self.state
end

--- Returns a float in [0, 1).
function RNG:random()
  return self:nextRaw() / MODULUS
end

--- Returns an integer in [lo, hi] inclusive. With one argument, returns
-- an integer in [1, lo].
function RNG:randomInt(lo, hi)
  if hi == nil then
    hi = lo
    lo = 1
  end
  if hi < lo then lo, hi = hi, lo end
  local span = hi - lo + 1
  return lo + math.floor(self:random() * span)
end

--- Fisher-Yates shuffle, returns a new array (does not mutate `arr`).
function RNG:shuffled(arr)
  local out = {}
  for i = 1, #arr do out[i] = arr[i] end
  for i = #out, 2, -1 do
    local j = self:randomInt(1, i)
    out[i], out[j] = out[j], out[i]
  end
  return out
end

--- Weighted pick: `items` is an array, `weightOf(item)` returns a
-- non-negative number. Returns the picked item and its index, or
-- nil if the total weight is zero.
function RNG:weightedPick(items, weightOf)
  local total = 0
  local weights = {}
  for i, item in ipairs(items) do
    local w = weightOf(item, i)
    if w < 0 then w = 0 end
    weights[i] = w
    total = total + w
  end
  if total <= 0 then return nil, nil end
  local target = self:random() * total
  local running = 0
  for i, item in ipairs(items) do
    running = running + weights[i]
    if target < running then
      return item, i
    end
  end
  -- Floating point edge case: fall back to the last item.
  return items[#items], #items
end

return RNG
