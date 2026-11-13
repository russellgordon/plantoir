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
 * - Pages need not hold every word: they are ranked by how many of the
 *   query's words they hold, then by where (title, keywords, description,
 *   text).
 *
 * The small box below it runs on the contents page: the search form on every
 * page sends ?q=… there. Without scripts the form still lands on the contents.
 * Its two sentences come from help/interface-words.json, through
 * window.PLANTOIR_HELP_WORDS.
 */
(function () {
  "use strict";

  var STOP_WORDS = [
    "a", "an", "and", "are", "as", "at", "be", "by", "can", "do", "does", "for", "from", "how", "i", "in",
    "is", "it", "me", "my", "of", "on", "or", "the", "this", "that", "to", "what", "when", "where", "which",
    "who", "why", "with", "you", "your"
  ];
  var KEY_SYMBOLS = /[⌘⇧⌥⌃]/;

  function stem(word) {
    if (KEY_SYMBOLS.test(word)) {
      return word;
    }
    if (word.length > 5 && word.slice(-3) === "ing") {
      return word.slice(0, -3);
    }
    if (word.length > 4 && word.slice(-2) === "ed") {
      return word.slice(0, -2);
    }
    if (word.length > 4 && word.slice(-3) === "ies") {
      return word.slice(0, -3) + "y";
    }
    if (word.length > 3 && word.slice(-1) === "s" && word.slice(-2) !== "ss") {
      return word.slice(0, -1);
    }
    return word;
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

  function searchHelp(index, query) {
    var wanted = queryWords(query);
    if (wanted.length === 0) {
      return [];
    }
    var results = [];
    for (var i = 0; i < index.length; i += 1) {
      var entry = index[i];
      var fields = [
        { words: words(entry.title), weight: 8 },
        { words: words((entry.keywords || []).join(" ")), weight: 5 },
        { words: words(entry.description), weight: 3 },
        { words: words(entry.text), weight: 1 }
      ];
      var matched = 0;
      var score = 0;
      for (var j = 0; j < wanted.length; j += 1) {
        var asPrefix = j === wanted.length - 1;
        var found = 0;
        for (var k = 0; k < fields.length; k += 1) {
          if (holds(fields[k].words, wanted[j], asPrefix)) {
            found += fields[k].weight;
          }
        }
        if (found > 0) {
          matched += 1;
          score += found;
        }
      }
      if (matched > 0) {
        results.push({ id: entry.id, title: entry.title, description: entry.description, matched: matched, score: score });
      }
    }
    results.sort(function (first, second) {
      if (second.matched !== first.matched) {
        return second.matched - first.matched;
      }
      if (second.score !== first.score) {
        return second.score - first.score;
      }
      return first.title < second.title ? -1 : 1;
    });
    return results;
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
      for (var i = 0; i < results.length; i += 1) {
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
