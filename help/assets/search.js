/* Plantoir Help's search, for the web copy.
 *
 * searchHelp(index, query) is a pure function: it takes the entries of
 * window.PLANTOIR_HELP_INDEX (assets/search-index.js, a script rather than a
 * fetched file, so it works from file:// as well as on plantoir.app) and
 * returns the matching pages, best first.
 *
 * - Words are compared by a simple stem: "deployed", "deploying" and
 *   "deploys" all match "deploy"; "pictures" matches "picture".
 * - Small words ("how", "do", "I", "my") are dropped from the query.
 * - The last word of the query also matches as the start of a word, so a
 *   query typed half way ("schedul") still finds its page.
 * - A word holding a key symbol (⌘P) matches any word that contains it (⇧⌘P).
 * - Pages need not hold every word. Each query word scores by where the page
 *   holds it (title 5, question 4, keywords 4, description 2, body 1) times
 *   how rare it is across the pages, so a word nearly every page holds
 *   ("page", "student") carries almost nothing and a body that merely
 *   mentions the words cannot outrank a title, question or keyword.
 * - A keyword phrase the query says outright ("snow day", "new page") adds
 *   its words' weight again; only the best such phrase counts.
 * - A page whose id and short title the query covers gains a share of the
 *   query's whole weight ("deploy" for deploy, "class-pages" for "classes").
 * - A floor: pages scoring below 0.4 of the best page's score are dropped.
 * - At most ten results are shown, with a line counting the rest.
 *
 * The small box below it runs on the contents page: the search form on every
 * page sends ?q=… there. Without scripts the form still lands on the contents.
 * Its two sentences come from help/interface-words.json, through
 * window.PLANTOIR_HELP_WORDS.
 */
(function () {
  "use strict";

  var STOP_WORDS = [
    "a", "after", "an", "and", "are", "as", "at", "be", "before", "by", "can", "do", "does", "for", "from", "how", "i", "in",
    "is", "it", "me", "my", "of", "on", "or", "the", "this", "that", "to", "what", "when", "where", "which",
    "who", "why", "with", "you", "your", "t", "s"
  ];
  var KEY_SYMBOLS = /[⌘⇧⌥⌃]/;
  // At most this many results are listed; a line counts the rest.
  var MOST_SHOWN = 10;

  function stem(word) {
    if (KEY_SYMBOLS.test(word)) {
      return word;
    }
    var stemmed = word;
    if (stemmed.length > 4 && stemmed.slice(-3) === "ies") {
      stemmed = stemmed.slice(0, -3) + "y";
    } else if (stemmed.length > 3 && stemmed.slice(-1) === "s" && stemmed.slice(-2) !== "ss") {
      stemmed = stemmed.slice(0, -1);
    } else if (stemmed.length > 5 && stemmed.slice(-3) === "ing") {
      stemmed = stemmed.slice(0, -3);
    } else if (stemmed.length > 4 && stemmed.slice(-2) === "ed") {
      stemmed = stemmed.slice(0, -2);
    }
    // A final e goes on both sides, so "scheduled" meets "schedule" and
    // "classes" (classe) meets "class".
    if (stemmed.length > 3 && stemmed.slice(-1) === "e") {
      stemmed = stemmed.slice(0, -1);
    }
    return stemmed;
  }

  function words(text) {
    var pieces = String(text || "").toLowerCase().split(/[^a-z0-9À-ɏ⌘⇧⌥⌃]+/);
    var result = [];
    for (var i = 0; i < pieces.length; i += 1) {
      if (pieces[i].length > 0) {
        result.push(stem(pieces[i]));
      }
    }
    return result;
  }

  function queryWords(query) {
    var all = words(query);
    var result = [];
    for (var i = 0; i < all.length; i += 1) {
      if (STOP_WORDS.indexOf(all[i]) < 0) {
        result.push(all[i]);
      }
    }
    return result;
  }

  function holds(list, word, asPrefix) {
    for (var i = 0; i < list.length; i += 1) {
      var candidate = list[i];
      if (candidate === word) {
        return true;
      }
      if (KEY_SYMBOLS.test(word) && candidate.indexOf(word) >= 0) {
        return true;
      }
      if (asPrefix && word.length >= 3 && candidate.indexOf(word) === 0) {
        return true;
      }
    }
    return false;
  }

  function prepared(index) {
    var entries = [];
    for (var i = 0; i < index.length; i += 1) {
      var entry = index[i];
      var phrases = [];
      var keywordList = entry.keywords || [];
      for (var p = 0; p < keywordList.length; p += 1) {
        var phrase = queryWords(keywordList[p]);
        if (phrase.length > 0) {
          phrases.push(phrase);
        }
      }
      entries.push({
        entry: entry,
        title: words(entry.title + " " + String(entry.id || "").split("-").join(" ")),
        id: queryWords(String(entry.id || "").split("-").join(" ")),
        question: words(entry.question),
        keywords: words(keywordList.join(" ")),
        phrases: phrases,
        description: words(entry.description),
        text: words(entry.text)
      });
    }
    return entries;
  }

  // True when every word of the phrase stands in the query, side by side and in order.
  function queryHoldsPhrase(wanted, phrase) {
    for (var start = 0; start + phrase.length <= wanted.length; start += 1) {
      var all = true;
      for (var i = 0; i < phrase.length; i += 1) {
        var prefix = start + i === wanted.length - 1;
        if (!holds([phrase[i]], wanted[start + i], prefix)) {
          all = false;
          break;
        }
      }
      if (all) {
        return true;
      }
    }
    return false;
  }

  // Where a word counts most: a page's title says what it is about, its question and
  // keywords are the words a teacher would use for it, its body merely mentions things.
  var IN_TITLE = 5;
  var IN_QUESTION = 4;
  var IN_KEYWORDS = 4;
  var IN_DESCRIPTION = 2;
  var IN_TEXT = 1;
  // A word no rarer than this carries next to nothing ("page" is on nearly every page).
  var LEAST_WEIGHT = 0.02;
  // Pages scoring below this share of the best page's score are dropped.
  var FLOOR = 0.4;

  function searchHelp(index, query) {
    var wanted = queryWords(query);
    if (wanted.length === 0) {
      return [];
    }
    var entries = prepared(index);
    // A rare word says more than a common one: weight each by how few pages hold it,
    // so a word nearly every page holds carries almost no weight.
    var weights = [];
    for (var w = 0; w < wanted.length; w += 1) {
      var asPrefix = w === wanted.length - 1;
      var holders = 0;
      for (var e = 0; e < entries.length; e += 1) {
        var all = entries[e].title.concat(entries[e].question, entries[e].keywords, entries[e].description, entries[e].text);
        if (holds(all, wanted[w], asPrefix)) {
          holders += 1;
        }
      }
      weights.push(Math.max(LEAST_WEIGHT, Math.log((entries.length + 1) / (holders + 0.5))));
    }
    var queryWeight = 0;
    for (var qw = 0; qw < weights.length; qw += 1) {
      queryWeight += weights[qw];
    }
    var results = [];
    for (var i = 0; i < entries.length; i += 1) {
      var page = entries[i];
      var matched = 0;
      var score = 0;
      for (var j = 0; j < wanted.length; j += 1) {
        var prefix = j === wanted.length - 1;
        var where = 0;
        if (holds(page.title, wanted[j], prefix)) {
          where = IN_TITLE;
        } else if (holds(page.question, wanted[j], prefix)) {
          where = IN_QUESTION;
        } else if (holds(page.keywords, wanted[j], prefix)) {
          where = IN_KEYWORDS;
        } else if (holds(page.description, wanted[j], prefix)) {
          where = IN_DESCRIPTION;
        } else if (holds(page.text, wanted[j], prefix)) {
          where = IN_TEXT;
        }
        if (where > 0) {
          matched += 1;
          score += where * weights[j];
        }
      }
      if (matched === 0) {
        continue;
      }
      // A keyword phrase of two or more words that the query says outright ("snow day",
      // "new page") is the page naming itself in the teacher's words. Only the best such
      // phrase counts, so a page listing "answer key" and "answer keys" gains nothing twice.
      var bestPhrase = 0;
      for (var k = 0; k < page.phrases.length; k += 1) {
        var phrase = page.phrases[k];
        if (phrase.length > 1 && queryHoldsPhrase(wanted, phrase)) {
          var phraseWeight = 0;
          for (var pw = 0; pw < phrase.length; pw += 1) {
            for (var x = 0; x < wanted.length; x += 1) {
              if (holds([phrase[pw]], wanted[x], x === wanted.length - 1)) {
                phraseWeight += weights[x];
                break;
              }
            }
          }
          bestPhrase = Math.max(bestPhrase, phraseWeight);
        }
      }
      score += IN_KEYWORDS * bestPhrase;
      // How much of the page's id, and of its title, the query covers: all of "deploy" for
      // deploy, half of "class-pages" for "classes". A short title about the words wins.
      var idHits = 0;
      for (var d = 0; d < page.id.length; d += 1) {
        if (holds(wanted, page.id[d], false)) {
          idHits += 1;
        }
      }
      var idShare = idHits / Math.max(1, page.id.length);
      var titleHits = 0;
      for (var h = 0; h < wanted.length; h += 1) {
        if (holds(page.title, wanted[h], h === wanted.length - 1)) {
          titleHits += 1;
        }
      }
      var titleWords = 0;
      var meaningful = queryWords(page.entry.title);
      for (var m = 0; m < meaningful.length; m += 1) {
        if (!/^[0-9]+$/.test(meaningful[m])) {
          titleWords += 1;
        }
      }
      var titleShare = titleHits / Math.max(1, titleWords);
      score += queryWeight * (2 * idShare + titleShare);
      results.push({
        id: page.entry.id, title: page.entry.title, description: page.entry.description,
        matched: matched, score: score
      });
    }
    // A floor relative to the best match: a page far below it only mentions the words.
    var best = 0;
    for (var r = 0; r < results.length; r += 1) {
      best = Math.max(best, results[r].score);
    }
    var kept = [];
    for (var f = 0; f < results.length; f += 1) {
      if (results[f].score >= FLOOR * best) {
        kept.push(results[f]);
      }
    }
    kept.sort(function (first, second) {
      if (second.score !== first.score) {
        return second.score - first.score;
      }
      return first.title < second.title ? -1 : 1;
    });
    return kept;
  }

  function showResults() {
    var box = document.getElementById("help-results");
    if (!box || typeof window.PLANTOIR_HELP_INDEX === "undefined") {
      return;
    }
    var query = new URLSearchParams(window.location.search).get("q");
    if (!query) {
      return;
    }
    var helpWords = window.PLANTOIR_HELP_WORDS || {};
    var field = document.getElementById("help-search");
    if (field) {
      field.value = query;
    }
    var results = searchHelp(window.PLANTOIR_HELP_INDEX, query);
    box.textContent = "";
    var heading = document.createElement("h2");
    heading.textContent = helpWords.resultsHeading || "";
    box.appendChild(heading);
    if (results.length === 0) {
      var none = document.createElement("p");
      none.textContent = helpWords.noMatch || "";
      box.appendChild(none);
    } else {
      var list = document.createElement("ol");
      var shown = Math.min(results.length, MOST_SHOWN);
      for (var i = 0; i < shown; i += 1) {
        var item = document.createElement("li");
        var link = document.createElement("a");
        link.href = results[i].id + ".html";
        link.textContent = results[i].title;
        item.appendChild(link);
        var line = document.createElement("p");
        line.textContent = results[i].description;
        item.appendChild(line);
        list.appendChild(item);
      }
      box.appendChild(list);
      if (results.length > shown) {
        var more = document.createElement("p");
        var rest = results.length - shown;
        var sentence = rest === 1 ? helpWords.moreOne : helpWords.more;
        more.textContent = String(sentence || "").split("{count}").join(String(rest));
        box.appendChild(more);
      }
    }
    box.hidden = false;
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { searchHelp: searchHelp };
  }
  if (typeof document !== "undefined") {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", showResults);
    } else {
      showResults();
    }
  }
})();
