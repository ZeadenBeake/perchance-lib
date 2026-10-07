--- Best-effort English grammar heuristics.
--
-- These mirror the spirit of Perchance's built-in text methods
-- (pluralForm, sentenceCase, the {a}/{s} smart-grammar markers, etc).
-- They are heuristic, not a dictionary-backed NLP engine -- exactly like
-- the originals, which also get irregular/uncommon words wrong. Small
-- irregular-word tables cover the common cases.
local Grammar = {}

-- ===== case transforms =====

function Grammar.upperCase(s) return s:upper() end
function Grammar.lowerCase(s) return s:lower() end

function Grammar.sentenceCase(s)
  if s == "" then return s end
  return s:sub(1, 1):upper() .. s:sub(2)
end

local SMALL_WORDS = {
  a = true, an = true, ["and"] = true, as = true, at = true, but = true,
  by = true, ["for"] = true, ["if"] = true, ["in"] = true, nor = true,
  of = true, on = true, ["or"] = true, per = true, the = true, to = true,
  vs = true, ["with"] = true,
}

function Grammar.titleCase(s)
  local words = {}
  local i = 1
  for word, sep in s:gmatch("([^%s]*)(%s*)") do
    if word ~= "" then
      i = i + 1
      local lower = word:lower()
      if i == 2 or not SMALL_WORDS[lower] then
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower() .. sep)
      else
        table.insert(words, lower .. sep)
      end
    end
  end
  return table.concat(words)
end

-- ===== pluralization =====

-- Only true irregulars where the mechanical suffix rules below would
-- get it wrong. Words like "fish" or "sheep" are deliberately absent:
-- the mechanical "sh$" rule already produces "fishes", which is what
-- Perchance's own {s}/pluralForm actually produce.
local PLURAL_IRREGULAR = {
  man = "men", woman = "women", child = "children", person = "people",
  mouse = "mice", goose = "geese", tooth = "teeth", foot = "feet",
  ox = "oxen", die = "dice", louse = "lice",
}
local SINGULAR_IRREGULAR = {}
for k, v in pairs(PLURAL_IRREGULAR) do SINGULAR_IRREGULAR[v] = k end

local function lastWordSplit(s)
  local lead, word = s:match("^(.-)([%a]+)$")
  if word == nil then return s, "" end
  return lead, word
end

local VOWELS = { a = true, e = true, i = true, o = true, u = true }

function Grammar.pluralForm(s)
  local lead, word = lastWordSplit(s)
  if word == "" then return s end
  local lower = word:lower()
  if PLURAL_IRREGULAR[lower] then
    return lead .. Grammar.matchCase(word, PLURAL_IRREGULAR[lower])
  end
  local plural
  if lower:match("[sxz]$") or lower:match("[cs]h$") then
    plural = word .. "es"
  elseif lower:match("[^aeiou]y$") then
    plural = word:sub(1, -2) .. "ies"
  elseif lower:match("fe$") then
    plural = word:sub(1, -3) .. "ves"
  elseif lower:match("[^f]f$") and not lower:match("ff$") then
    plural = word:sub(1, -2) .. "ves"
  elseif lower:match("[^aeiou]o$") then
    plural = word .. "es"
  else
    plural = word .. "s"
  end
  return lead .. plural
end

function Grammar.singularForm(s)
  local lead, word = lastWordSplit(s)
  if word == "" then return s end
  local lower = word:lower()
  if SINGULAR_IRREGULAR[lower] then
    return lead .. Grammar.matchCase(word, SINGULAR_IRREGULAR[lower])
  end
  local singular
  if lower:match("ies$") then
    singular = word:sub(1, -4) .. "y"
  elseif lower:match("ves$") then
    singular = word:sub(1, -4) .. "fe"
  elseif lower:match("[sxz]es$") or lower:match("[cs]hes$") then
    singular = word:sub(1, -3)
  elseif lower:match("s$") and not lower:match("ss$") then
    singular = word:sub(1, -2)
  else
    singular = word
  end
  return lead .. singular
end

-- Re-apply the capitalization pattern of `original` onto `replacement`.
function Grammar.matchCase(original, replacement)
  if original == original:upper() then
    return replacement:upper()
  elseif original:sub(1, 1) == original:sub(1, 1):upper() then
    return replacement:sub(1, 1):upper() .. replacement:sub(2)
  end
  return replacement
end

-- ===== articles (a/an) =====

-- Words that sound like they start with a vowel/consonant contrary to
-- their spelling (silent h, or a leading vowel letter pronounced as a
-- consonant "y"/"w" sound).
local ARTICLE_AN_EXCEPTIONS = {
  hour = true, honest = true, honor = true, honour = true, heir = true,
  herb = true,
}
local ARTICLE_A_EXCEPTIONS = {
  one = true, once = true, unicorn = true, unicycle = true, unit = true,
  united = true, university = true, user = true, useful = true,
  european = true, eucalyptus = true, euro = true,
}

--- Returns "a" or "an" appropriate for the word/phrase that follows.
function Grammar.article(s)
  local word = s:match("^%s*([%a]+)")
  if not word then return "a" end
  local lower = word:lower()
  if ARTICLE_A_EXCEPTIONS[lower] then return "a" end
  if ARTICLE_AN_EXCEPTIONS[lower] then return "an" end
  if VOWELS[lower:sub(1, 1)] then return "an" end
  return "a"
end

-- ===== tense / possessive / negative (best-effort) =====

local PAST_IRREGULAR = {
  is = "was", am = "was", are = "were", go = "went", have = "had",
  has = "had", do_ = "did", say = "said", make = "made", see = "saw",
  come = "came", take = "took", get = "got", know = "knew",
  give = "gave", find = "found", think = "thought", tell = "told",
  become = "became", leave = "left", feel = "felt", bring = "brought",
  begin = "began", run = "ran", eat = "ate", fall = "fell",
  write = "wrote", break_ = "broke", speak = "spoke", win = "won",
  fly = "flew", draw = "drew", drink = "drank", ride = "rode",
  rise = "rose", choose = "chose", blow = "blew", grow = "grew",
}
PAST_IRREGULAR["do"] = "did"
PAST_IRREGULAR["break"] = "broke"

function Grammar.pastTense(s)
  local lead, word = lastWordSplit(s)
  if word == "" then return s end
  local lower = word:lower()
  if PAST_IRREGULAR[lower] then
    return lead .. Grammar.matchCase(word, PAST_IRREGULAR[lower])
  end
  local past
  if lower:match("e$") then
    past = word .. "d"
  elseif lower:match("[^aeiou]y$") then
    past = word:sub(1, -2) .. "ied"
  else
    past = word .. "ed"
  end
  return lead .. past
end

function Grammar.presentTense(s)
  -- Third-person singular present: "walk" -> "walks". Re-use plural
  -- suffix rules, which follow the same -s/-es/-ies pattern.
  return Grammar.pluralForm(s)
end

function Grammar.futureTense(s)
  local lead, word = lastWordSplit(s)
  return lead .. "will " .. word
end

function Grammar.possessiveForm(s)
  if s:match("s$") then
    return s .. "'"
  end
  return s .. "'s"
end

local NEGATIVE_AUX = {
  is = "is not", am = "am not", are = "are not", was = "was not",
  were = "were not", can = "cannot", will = "will not",
  ["do"] = "do not", does = "does not", did = "did not",
  has = "has not", have = "have not", had = "had not",
}

function Grammar.negativeForm(s)
  local lead, word = lastWordSplit(s)
  local lower = word:lower()
  if NEGATIVE_AUX[lower] then
    return lead .. Grammar.matchCase(word, NEGATIVE_AUX[lower])
  end
  return "not " .. s
end

return Grammar
