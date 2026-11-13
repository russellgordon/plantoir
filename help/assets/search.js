/* Plantoir Help's search, for the web copy.
 *
 * searchHelp(index, query) is a pure function: it takes the entries of
 * window.PLANTOIR_HELP_INDEX (assets/search-index.js, a script rather than a
 * fetched file, so it works from file:// as well as on plantoir.app) and
 * returns the matching pages, best first. Every word of the query must
 * appear in a page's title, keywords, description or text.
 *
 * The small box below it runs on the contents page: the search form on every
 * page sends ?q=… there. Without scripts the form still lands on the contents.
 * The two sentences it shows are fixed interface words, not Help prose.
 */
(function () {
  "use strict";

  var NO_MATCH = "No page matches.";
  var RESULTS_HEADING = "Search results";

  function words(text) {
    return String(text || "").toLowerCase().split(/[^a-z0-9À-ɏ]+/).filter(function (word) {
      return word.length > 0;
    });
  }

  function searchHelp(index, query) {
    var queryWords = words(query);
    if (queryWords.length === 0) {
      return [];
    }
    var results = [];
    for (var i = 0; i < index.length; i += 1) {
      var entry = index[i];
      var title = words(entry.title);
      var keywords = words((entry.keywords || []).join(" "));
      var description = words(entry.description);
      var text = words(entry.text);
      var score = 0;
      var everyWord = true;
      for (var j = 0; j < queryWords.length; j += 1) {
        var word = queryWords[j];
        var found = 0;
        if (title.indexOf(word) >= 0) { found += 8; }
        if (keywords.indexOf(word) >= 0) { found += 5; }
        if (description.indexOf(word) >= 0) { found += 3; }
        if (text.indexOf(word) >= 0) { found += 1; }
        if (found === 0) {
          everyWord = false;
          break;
        }
        score += found;
      }
      if (everyWord) {
        results.push({ id: entry.id, title: entry.title, description: entry.description, score: score });
      }
    }
    results.sort(function (first, second) {
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
    var field = document.getElementById("help-search");
    if (field) {
      field.value = query;
    }
    var results = searchHelp(window.PLANTOIR_HELP_INDEX, query);
    box.textContent = "";
    var heading = document.createElement("h2");
    heading.textContent = RESULTS_HEADING;
    box.appendChild(heading);
    if (results.length === 0) {
      var none = document.createElement("p");
      none.textContent = NO_MATCH;
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
