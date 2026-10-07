--- Tokenizer for the small expression language used inside `[...]`
-- references and `^[...]` dynamic odds (e.g. `x > 5 ? "big" : "small"`,
-- `name.selectOne`, `g = gender.selectOne`).
local Lexer = {}

local PUNCT_3 = {}
local PUNCT_2 = {
  ["=="] = true, ["!="] = true, ["<="] = true, [">="] = true,
  ["&&"] = true, ["||"] = true,
}
local PUNCT_1 = {
  ["("] = true, [")"] = true, ["["] = true, ["]"] = true,
  ["."] = true, [","] = true, ["="] = true, ["?"] = true, [":"] = true,
  ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["%"] = true,
  ["<"] = true, [">"] = true, ["!"] = true,
}

local function isDigit(c) return c ~= nil and c:match("%d") ~= nil end
local function isAlpha(c) return c ~= nil and c:match("[%a_]") ~= nil end
local function isAlnum(c) return c ~= nil and c:match("[%w_]") ~= nil end

--- Tokenize `src`. Returns an array of tokens: { type, value, pos }.
-- Raises an error (via `error`) with a position-annotated message on
-- invalid input.
function Lexer.tokenize(src)
  local tokens = {}
  local i = 1
  local n = #src

  local function peek(offset)
    local p = i + (offset or 0)
    if p > n then return nil end
    return src:sub(p, p)
  end

  while i <= n do
    local c = peek()
    if c:match("%s") then
      i = i + 1
    elseif isDigit(c) or (c == "." and isDigit(peek(1))) then
      local start = i
      while isDigit(peek()) do i = i + 1 end
      if peek() == "." and isDigit(peek(1)) then
        i = i + 1
        while isDigit(peek()) do i = i + 1 end
      end
      local text = src:sub(start, i - 1)
      table.insert(tokens, { type = "number", value = tonumber(text), pos = start })
    elseif isAlpha(c) then
      local start = i
      while isAlnum(peek()) do i = i + 1 end
      local text = src:sub(start, i - 1)
      table.insert(tokens, { type = "ident", value = text, pos = start })
    elseif c == '"' or c == "'" then
      local quote = c
      local start = i
      i = i + 1
      local buf = {}
      while true do
        local ch = peek()
        if ch == nil then
          error("perchance.lexer: unterminated string starting at position " .. start)
        elseif ch == quote then
          i = i + 1
          break
        elseif ch == "\\" then
          local nextCh = peek(1)
          if nextCh == "n" then table.insert(buf, "\n")
          elseif nextCh == "t" then table.insert(buf, "\t")
          else table.insert(buf, nextCh or "") end
          i = i + 2
        else
          table.insert(buf, ch)
          i = i + 1
        end
      end
      table.insert(tokens, { type = "string", value = table.concat(buf), pos = start })
    else
      local three = src:sub(i, i + 2)
      local two = src:sub(i, i + 1)
      if PUNCT_3[three] then
        table.insert(tokens, { type = three, value = three, pos = i })
        i = i + 3
      elseif PUNCT_2[two] then
        table.insert(tokens, { type = two, value = two, pos = i })
        i = i + 2
      elseif PUNCT_1[c] then
        table.insert(tokens, { type = c, value = c, pos = i })
        i = i + 1
      else
        error(("perchance.lexer: unexpected character %q at position %d"):format(c, i))
      end
    end
  end

  table.insert(tokens, { type = "eof", value = nil, pos = n + 1 })
  return tokens
end

return Lexer
