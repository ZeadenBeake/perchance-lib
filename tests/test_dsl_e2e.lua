-- End-to-end test of the DSL->Lua conversion pipeline: parse a
-- Perchance-style source, generate a Lua script with the codegen
-- tool, then actually `load()` and run that generated code (in
-- process, no subprocess needed) to make sure the whole round trip
-- produces a working generator.
local function thisDir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end
local HERE = thisDir()
package.path = HERE .. "/../lua/?.lua;" .. HERE .. "/../lua/?/init.lua;"
  .. HERE .. "/../?.lua;" .. HERE .. "/?.lua;" .. package.path

local T = require("testkit").new()

-- Lua 5.1's `load` only accepts a reader function; loading directly
-- from a string is `loadstring` there. 5.2+ unified this into `load`
-- and dropped `loadstring`. This shim keeps the test portable.
local loadChunk = loadstring or load
local DslParser = require("tools.dslparser")
local Codegen = require("tools.codegen")

local SOURCE = [[
title
  [adjective] [noun]

adjective
  big^2
  small
  red

noun
  cat
  dog

gender = {female|male|non-binary^0.1}

names
  female
    Anita
    Jessica
  male
    Kalid
    Bob
]]

local ast = DslParser.parse(SOURCE)
T:eq(ast.root, "title", "root defaults to the first definition ('title')")
T:eq(#ast.order, 5, "all five top-level definitions were found")

local luaSrc = Codegen.generate(ast, { sourceName = "test", outputName = "test.lua" })
T:ok(luaSrc:find('require("perchance")', 1, true) ~= nil, "generated script requires the runtime")
T:ok(luaSrc:find("gen:run()", 1, true) ~= nil, "generated script calls gen:run()")

-- Load and execute the generated source as a real Lua chunk. Stub
-- out `print` during load so the script's own `print(gen:run())`
-- doesn't spam test output, and capture the returned Generator.
local chunk, loadErr = loadChunk(luaSrc, "generated_test_chunk")
T:ok(chunk ~= nil, "generated Lua source compiles: " .. tostring(loadErr))

if chunk then
  local realPrint = print
  print = function() end
  local ok, gen = pcall(chunk)
  print = realPrint
  T:ok(ok, "generated script executes without error: " .. tostring(gen))

  if ok then
    for i = 1, 30 do
      local out = gen:run()
      T:ok(out:match("^[%a]+ [%a]+$") ~= nil, "round-tripped generator output matches shape: " .. tostring(out))
    end

    -- Weight round-trips: "big" should appear roughly twice as often as "small"/"red".
    local counts = { big = 0, small = 0, red = 0 }
    for i = 1, 6000 do
      local out = gen:run()
      local adj = out:match("^(%a+) ")
      if counts[adj] ~= nil then counts[adj] = counts[adj] + 1 end
    end
    T:approx(counts.big / counts.small, 2, 0.5, "round-tripped weight (big^2) still ~2x small")

    -- Nested hierarchical list round-trips.
    local known = { Anita = true, Jessica = true, Kalid = true, Bob = true }
    gen:setRoot("names")
    for i = 1, 30 do
      T:ok(known[gen:run()], "round-tripped hierarchical list auto-descends to a known leaf")
    end

    -- Alias with inline weight round-trips.
    gen:setRoot("gender")
    local genderCounts = { female = 0, male = 0, ["non-binary"] = 0 }
    for i = 1, 6000 do
      local v = gen:run()
      genderCounts[v] = genderCounts[v] + 1
    end
    T:approx(genderCounts.female / genderCounts["non-binary"], 10, 3, "round-tripped inline weight (^0.1) still ~10x")
  end
end

-- Determinism survives the round trip too.
if chunk then
  local realPrint = print
  print = function() end
  local ok1, gen1 = pcall(chunk)
  local chunk2 = loadChunk(luaSrc, "generated_test_chunk_2")
  local ok2, gen2 = pcall(chunk2)
  print = realPrint
  if ok1 and ok2 then
    T:eq(gen1:run(777), gen2:run(777), "two independently loaded copies of the generated script agree under the same seed")
  end
end

return T:summary("dsl_e2e")
