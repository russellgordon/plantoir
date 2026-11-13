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
 * - Pages need not hold every word. They rank by how many query words they
 *   hold; then a page whose title or id holds them ranks above one that only
 *   mentions them (a page whose id the query covers most, then a short
 *   title the words cover, first); then by where the words are and how rare.
 * - A floor: when some pages hold at least half the query's words, pages
 *   holding fewer are dropped.
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
      entries.push({
        entry: entry,
        title: words(entry.title + " " + String(entry.id || "").split("-").join(" ")),
        id: words(String(entry.id || "").split("-").join(" ")),
        keywords: words((entry.keywords || []).join(" ")),
        description: words(entry.description),
        text: words(entry.text)
      });
    }
    return entries;
  }

  function searchHelp(index, query) {
    var wanted = queryWords(query);
    if (wanted.length === 0) {
      return [];
    }
    var entries = prepared(index);
    // A rare word says more than a common one: weight each by how few pages hold it.
    var weights = [];
    for (var w = 0; w < wanted.length; w += 1) {
      var asPrefix = w === wanted.length - 1;
      var holders = 0;
      for (var e = 0; e < entries.length; e += 1) {
        var all = entries[e].title.concat(entries[e].keywords, entries[e].description, entries[e].text);
        if (holds(all, wanted[w], asPrefix)) {
          holders += 1;
        }
      }
      weights.push(Math.log(1 + entries.length / Math.max(1, holders)));
    }
    var results = [];
    for (var i = 0; i < entries.length; i += 1) {
      var page = entries[i];
      var matched = 0;
      var titleHits = 0;
      var score = 0;
      for (var j = 0; j < wanted.length; j += 1) {
        var prefix = j === wanted.length - 1;
        var where = 0;
        if (holds(page.title, wanted[j], prefix)) {
          where = 4;
          titleHits += 1;
        } else if (holds(page.keywords, wanted[j], prefix)) {
          where = 3;
        } else if (holds(page.description, wanted[j], prefix)) {
          where = 2;
        } else if (holds(page.text, wanted[j], prefix)) {
          where = 1;
        }
        if (where > 0) {
          matched += 1;
          score += where * weights[j];
        }
      }
      // How much of the page's id the query asks for: all of "deploy" for deploy,
      // half of "class-pages" for "classes".
      var idHits = 0;
      for (var d = 0; d < page.id.length; d += 1) {
        if (holds(wanted, page.id[d], false)) {
          idHits += 1;
        }
      }
      var idShare = idHits / Math.max(1, page.id.length);
      // How much of the title the query covers (numbers aside): a short title about the words wins.
      var titleWords = 0;
      var meaningful = queryWords(page.entry.title);
      for (var m = 0; m < meaningful.length; m += 1) {
        if (!/^[0-9]+$/.test(meaningful[m])) {
          titleWords += 1;
        }
      }
      var titleShare = titleHits / Math.max(1, titleWords);
      if (matched > 0) {
        results.push({
          id: page.entry.id, title: page.entry.title, description: page.entry.description,
          matched: matched, titleHits: titleHits, idShare: idShare, titleShare: titleShare, score: score
        });
      }
    }
    // A floor: when some pages hold at least half the query's words, drop the rest.
    var half = Math.ceil(wanted.length / 2);
    var best = 0;
    for (var r = 0; r < results.length; r += 1) {
      best = Math.max(best, results[r].matched);
    }
    if (best >= half) {
      var kept = [];
      for (var k = 0; k < results.length; k += 1) {
        if (results[k].matched >= half) {
          kept.push(results[k]);
        }
      }
      results = kept;
    }
    // A page whose title or id holds the words ranks above one that only mentions them.
    results.sort(function (first, second) {
      if (second.matched !== first.matched) {
        return second.matched - first.matched;
      }
      if (second.titleHits !== first.titleHits) {
        return second.titleHits - first.titleHits;
      }
      if (second.idShare !== first.idShare) {
        return second.idShare - first.idShare;
      }
      if (second.titleShare !== first.titleShare) {
        return second.titleShare - first.titleShare;
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
        more.textContent = String(helpWords.more || "").split("{count}").join(String(results.length - shown));
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
