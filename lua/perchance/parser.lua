--- Recursive-descent parser for the expression language found inside
-- `[...]` references and `^[...]` dynamic odds.
--
-- Grammar (highest to lowest precedence):
--   primary    := NUMBER | STRING | IDENT | '(' expr ')'
--   postfix    := primary ( '.' IDENT ('(' args ')')? | '[' expr ']' | '(' args ')' )*
--   unary      := ('-' | '!')? postfix
--   multiplic. := unary (('*' | '/' | '%') unary)*
--   additive   := multiplic. (('+' | '-') multiplic.)*
--   relational := additive (('<' | '>' | '<=' | '>=') additive)*
--   equality   := relational (('==' | '!=') relational)*
--   logicAnd   := equality ('&&' equality)*
--   logicOr    := logicAnd ('||' logicAnd)*
--   ternary    := logicOr ('?' expr ':' expr)?
--   expr       := IDENT '=' expr | IDENT ':=' expr | ternary
--
-- `:=` is the same as `=` (bind IDENT, with the same bare-list-
-- collapses-to-one-draw / consumableList-stays-a-handle semantics)
-- except it evaluates to "" wherever it appears, instead of the
-- assigned value -- i.e. it assigns silently, without also printing.
local Lexer = require("perchance.lexer")

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens)
  return setmetatable({ tokens = tokens, pos = 1 }, Parser)
end

function Parser:peek(offset)
  return self.tokens[self.pos + (offset or 0)]
end

function Parser:advance()
  local t = self.tokens[self.pos]
  self.pos = self.pos + 1
  return t
end

function Parser:check(ttype)
  return self:peek().type == ttype
end

function Parser:expect(ttype)
  local t = self:peek()
  if t.type ~= ttype then
    error(("perchance.parser: expected %q but got %q at position %d"):format(ttype, t.type, t.pos))
  end
  return self:advance()
end

function Parser:parseArgs()
  local args = {}
  self:expect("(")
  if not self:check(")") then
    table.insert(args, self:parseExpr())
    while self:check(",") do
      self:advance()
      table.insert(args, self:parseExpr())
    end
  end
  self:expect(")")
  return args
end

function Parser:parsePrimary()
  local t = self:peek()
  if t.type == "number" then
    self:advance()
    return { type = "Number", value = t.value }
  elseif t.type == "string" then
    self:advance()
    return { type = "String", value = t.value }
  elseif t.type == "ident" then
    self:advance()
    return { type = "Ident", name = t.value }
  elseif t.type == "(" then
    self:advance()
    local e = self:parseExpr()
    self:expect(")")
    return e
  else
    error(("perchance.parser: unexpected token %q at position %d"):format(tostring(t.type), t.pos))
  end
end

function Parser:parsePostfix()
  local node = self:parsePrimary()
  while true do
    local t = self:peek()
    if t.type == "." then
      self:advance()
      local nameTok = self:expect("ident")
      node = { type = "Member", object = node, name = nameTok.value }
      if self:check("(") then
        local args = self:parseArgs()
        node = { type = "Call", callee = node, args = args }
      end
    elseif t.type == "[" then
      self:advance()
      local idx = self:parseExpr()
      self:expect("]")
      node = { type = "Index", object = node, index = idx }
    elseif t.type == "(" then
      local args = self:parseArgs()
      node = { type = "Call", callee = node, args = args }
    else
      break
    end
  end
  return node
end

function Parser:parseUnary()
  local t = self:peek()
  if t.type == "-" or t.type == "!" then
    self:advance()
    local value = self:parseUnary()
    return { type = "UnOp", op = t.type, value = value }
  end
  return self:parsePostfix()
end

local function leftAssoc(self, nextLevel, ops)
  local node = nextLevel(self)
  while ops[self:peek().type] do
    local op = self:advance().type
    local right = nextLevel(self)
    node = { type = "BinOp", op = op, left = node, right = right }
  end
  return node
end

function Parser:parseMultiplicative()
  return leftAssoc(self, Parser.parseUnary, { ["*"] = true, ["/"] = true, ["%"] = true })
end

function Parser:parseAdditive()
  return leftAssoc(self, Parser.parseMultiplicative, { ["+"] = true, ["-"] = true })
end

function Parser:parseRelational()
  return leftAssoc(self, Parser.parseAdditive, { ["<"] = true, [">"] = true, ["<="] = true, [">="] = true })
end

function Parser:parseEquality()
  return leftAssoc(self, Parser.parseRelational, { ["=="] = true, ["!="] = true })
end

function Parser:parseLogicAnd()
  return leftAssoc(self, Parser.parseEquality, { ["&&"] = true })
end

function Parser:parseLogicOr()
  return leftAssoc(self, Parser.parseLogicAnd, { ["||"] = true })
end

function Parser:parseTernary()
  local cond = self:parseLogicOr()
  if self:check("?") then
    self:advance()
    local a = self:parseExpr()
    self:expect(":")
    local b = self:parseExpr()
    return { type = "Ternary", cond = cond, a = a, b = b }
  end
  return cond
end

function Parser:parseExpr()
  if self:check("ident") and self:peek(1).type == "=" then
    local name = self:advance().value
    self:advance() -- '='
    local value = self:parseExpr()
    return { type = "Assign", name = name, value = value }
  end
  if self:check("ident") and self:peek(1).type == ":=" then
    local name = self:advance().value
    self:advance() -- ':='
    local value = self:parseExpr()
    return { type = "SilentAssign", name = name, value = value }
  end
  return self:parseTernary()
end

--- Parse a full expression from source text. Errors if trailing
-- tokens remain after the expression (besides EOF).
local function parse(src)
  local tokens = Lexer.tokenize(src)
  local p = Parser.new(tokens)
  local ast = p:parseExpr()
  if not p:check("eof") then
    local t = p:peek()
    error(("perchance.parser: unexpected trailing token %q at position %d"):format(tostring(t.type), t.pos))
  end
  return ast
end

return { parse = parse, Parser = Parser }
