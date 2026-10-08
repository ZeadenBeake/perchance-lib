local function thisDir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end
local HERE = thisDir()
package.path = HERE .. "/../lua/?.lua;" .. HERE .. "/../lua/?/init.lua;" .. HERE .. "/?.lua;" .. package.path

local T = require("testkit").new()
local Parser = require("perchance.parser")

local function parses(src, msg)
  local ok, ast = pcall(Parser.parse, src)
  T:ok(ok, (msg or src) .. " (parses without error)")
  return ast
end

do
  local ast = parses("42", "number literal")
  T:eq(ast.type, "Number", "number literal type")
  T:eq(ast.value, 42, "number literal value")
end

do
  local ast = parses('"hello"', "string literal")
  T:eq(ast.type, "String", "string literal type")
  T:eq(ast.value, "hello", "string literal value")
end

do
  local ast = parses("foo", "bare identifier")
  T:eq(ast.type, "Ident", "ident type")
  T:eq(ast.name, "foo", "ident name")
end

do
  local ast = parses("g = gender.selectOne", "assignment")
  T:eq(ast.type, "Assign", "assign type")
  T:eq(ast.name, "g", "assign target name")
  T:eq(ast.value.type, "Member", "assign value is a member expr")
  T:eq(ast.value.name, "selectOne", "assign value member name")
end

do
  -- Regression (issue #2): `:=` is the silent-assignment form.
  local ast = parses("c := hairColor", "silent assignment")
  T:eq(ast.type, "SilentAssign", "silent assign type")
  T:eq(ast.name, "c", "silent assign target name")
  T:eq(ast.value.type, "Ident", "silent assign value is an ident")
  T:eq(ast.value.name, "hairColor", "silent assign value name")
end

do
  -- `:` for ternary still works unambiguously alongside `:=`.
  local ast = parses('x > 0 ? "pos" : "neg"', "ternary still parses alongside :=")
  T:eq(ast.type, "Ternary", "ternary type unaffected by := addition")
end

do
  local ast = parses("names[g].selectOne", "dynamic sub-list referencing")
  T:eq(ast.type, "Member", "outer node is member")
  T:eq(ast.name, "selectOne", "outer member name")
  T:eq(ast.object.type, "Index", "object is dynamic index")
  T:eq(ast.object.object.name, "names", "index base is 'names'")
  T:eq(ast.object.index.name, "g", "index key is ident 'g'")
end

do
  local ast = parses("animal.selectUnique(3, 20)", "method call with args")
  T:eq(ast.type, "Call", "call type")
  T:eq(#ast.args, 2, "call arg count")
  T:eq(ast.args[1].value, 3, "first arg")
  T:eq(ast.args[2].value, 20, "second arg")
end

do
  local ast = parses('x > 5 ? "big" : "small"', "ternary")
  T:eq(ast.type, "Ternary", "ternary type")
  T:eq(ast.cond.op, ">", "ternary cond op")
  T:eq(ast.a.value, "big", "ternary true branch")
  T:eq(ast.b.value, "small", "ternary false branch")
end

do
  local ast = parses("t >= 15 && t <= 30", "logical and of comparisons")
  T:eq(ast.op, "&&", "top-level op is &&")
  T:eq(ast.left.op, ">=", "left comparison op")
  T:eq(ast.right.op, "<=", "right comparison op")
end

do
  local ast = parses('x || "default"', "property fallback operator")
  T:eq(ast.op, "||", "fallback op")
end

do
  local ast = parses("-5", "unary minus")
  T:eq(ast.type, "UnOp", "unop type")
  T:eq(ast.op, "-", "unop operator")
end

do
  -- precedence: * before +
  local ast = parses("1 + 2 * 3", "precedence")
  T:eq(ast.op, "+", "top level is +")
  T:eq(ast.right.op, "*", "right side is the * group")
end

do
  local ok = pcall(Parser.parse, "1 +")
  T:ok(not ok, "incomplete expression raises an error")
end

do
  local ok = pcall(Parser.parse, "1 2")
  T:ok(not ok, "trailing garbage after a complete expression raises an error")
end

return T:summary("parser")
