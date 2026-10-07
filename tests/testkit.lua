--- Minimal, dependency-free assertion helper for this project's test
-- suite (no busted/luaunit dependency -- keeps the library itself
-- zero-dependency too).
local Testkit = {}

function Testkit.new()
  return setmetatable({ count = 0, failures = 0 }, { __index = Testkit })
end

function Testkit:eq(actual, expected, msg)
  self.count = self.count + 1
  if actual ~= expected then
    self.failures = self.failures + 1
    print(("FAIL [%s]\n  expected: %s\n  actual:   %s"):format(msg or "?", tostring(expected), tostring(actual)))
  end
end

function Testkit:ok(cond, msg)
  self.count = self.count + 1
  if not cond then
    self.failures = self.failures + 1
    print(("FAIL [%s]: expected truthy"):format(msg or "?"))
  end
end

function Testkit:approx(actual, expected, tolerance, msg)
  self.count = self.count + 1
  if math.abs(actual - expected) > tolerance then
    self.failures = self.failures + 1
    print(("FAIL [%s]\n  expected ~%s (+/- %s)\n  actual:   %s"):format(
      msg or "?", tostring(expected), tostring(tolerance), tostring(actual)))
  end
end

function Testkit:errors(fn, msg)
  self.count = self.count + 1
  local ok = pcall(fn)
  if ok then
    self.failures = self.failures + 1
    print(("FAIL [%s]: expected an error, got none"):format(msg or "?"))
  end
end

--- Prints a summary line and returns true iff every assertion in
-- this suite passed.
function Testkit:summary(label)
  print(("%s: %d assertions, %d failures"):format(label or "suite", self.count, self.failures))
  return self.failures == 0
end

return Testkit
