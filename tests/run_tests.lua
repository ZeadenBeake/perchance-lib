--- Runs every test_*.lua file in this directory and exits non-zero
-- if any of them failed. Each test file is self-contained (sets up
-- its own package.path) and returns true/false from testkit:summary().
local function thisDir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end
local HERE = thisDir()

local FILES = {
  "test_rng.lua",
  "test_grammar.lua",
  "test_parser.lua",
  "test_template.lua",
  "test_list.lua",
  "test_generator.lua",
  "test_dsl_e2e.lua",
}

local allPassed = true
for _, filename in ipairs(FILES) do
  print("==> " .. filename)
  local ok, result = pcall(dofile, HERE .. "/" .. filename)
  if not ok then
    print("ERROR running " .. filename .. ": " .. tostring(result))
    allPassed = false
  elseif result == false then
    allPassed = false
  end
  print("")
end

if allPassed then
  print("ALL SUITES PASSED")
  os.exit(0)
else
  print("SOME SUITES FAILED")
  os.exit(1)
end
