local function thisDir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end
local HERE = thisDir()
package.path = HERE .. "/../lua/?.lua;" .. HERE .. "/../lua/?/init.lua;" .. HERE .. "/?.lua;" .. package.path

local T = require("testkit").new()
local G = require("perchance.grammar")

T:eq(G.upperCase("hello"), "HELLO", "upperCase")
T:eq(G.lowerCase("HELLO"), "hello", "lowerCase")
T:eq(G.sentenceCase("hello world"), "Hello world", "sentenceCase")
T:eq(G.titleCase("the lord of the rings"), "The Lord of the Rings", "titleCase skips small words")
T:eq(G.titleCase("a tale of two cities"), "A Tale of Two Cities", "titleCase capitalizes first word regardless")

T:eq(G.pluralForm("cat"), "cats", "pluralForm regular")
T:eq(G.pluralForm("box"), "boxes", "pluralForm -x")
T:eq(G.pluralForm("fish"), "fishes", "pluralForm -sh matches Perchance's own {s} example")
T:eq(G.pluralForm("city"), "cities", "pluralForm -y consonant")
T:eq(G.pluralForm("day"), "days", "pluralForm -y vowel")
T:eq(G.pluralForm("knife"), "knives", "pluralForm -fe")
T:eq(G.pluralForm("half"), "halves", "pluralForm -f")
T:eq(G.pluralForm("potato"), "potatoes", "pluralForm -o consonant")
T:eq(G.pluralForm("man"), "men", "pluralForm irregular man")
T:eq(G.pluralForm("Child"), "Children", "pluralForm irregular preserves capitalization")
T:eq(G.pluralForm("ox"), "oxen", "pluralForm irregular ox")
T:eq(G.pluralForm("a big red box"), "a big red boxes", "pluralForm only affects trailing word")
T:eq(G.pluralForm(""), "", "pluralForm of empty string is a no-op")

T:eq(G.singularForm("cats"), "cat", "singularForm regular")
T:eq(G.singularForm("boxes"), "box", "singularForm -es")
T:eq(G.singularForm("cities"), "city", "singularForm -ies")
T:eq(G.singularForm("knives"), "knife", "singularForm -ves")
T:eq(G.singularForm("men"), "man", "singularForm irregular")

T:eq(G.article("apple"), "an", "article vowel")
T:eq(G.article("banana"), "a", "article consonant")
T:eq(G.article("hour"), "an", "article silent h exception")
T:eq(G.article("honest person"), "an", "article silent h phrase, uses first word")
T:eq(G.article("unicorn"), "a", "article u-as-y exception")
T:eq(G.article("university"), "a", "article u-as-y exception 2")
T:eq(G.article(""), "a", "article default on empty input")

T:eq(G.pastTense("walk"), "walked", "pastTense regular")
T:eq(G.pastTense("carry"), "carried", "pastTense -y")
T:eq(G.pastTense("smile"), "smiled", "pastTense -e")
T:eq(G.pastTense("go"), "went", "pastTense irregular go")
T:eq(G.pastTense("is"), "was", "pastTense irregular is")

T:eq(G.presentTense("walk"), "walks", "presentTense 3rd person")
T:eq(G.futureTense("walk"), "will walk", "futureTense")
T:eq(G.possessiveForm("cat"), "cat's", "possessiveForm regular")
T:eq(G.possessiveForm("cats"), "cats'", "possessiveForm trailing s")
T:eq(G.negativeForm("is"), "is not", "negativeForm auxiliary")
T:eq(G.negativeForm("run"), "not run", "negativeForm fallback")

T:eq(G.matchCase("CAT", "dog"), "DOG", "matchCase all-caps")
T:eq(G.matchCase("Cat", "dog"), "Dog", "matchCase title")
T:eq(G.matchCase("cat", "dog"), "dog", "matchCase lower")

return T:summary("grammar")
