// Runnable code (#585): the colours of the code a student types, with
// nothing else in them.
//
// No imports and no DOM, so the same file runs in the browser (the page's
// script, codeRunner.inline.ts, imports it) and in Node, where
// scripts/check_runner_rules_against_the_site.py bundles it and runs every
// case in contracts/shared-rules.json -> codeRunnerBlocks.colour through it,
// and scores it against the image's own Shiki.
//
// WHY A TOKENIZER AT ALL. A static block is coloured by Shiki when the site
// is built: every token is a span carrying `--shiki-light` and `--shiki-dark`,
// and Quartz's syntax.scss turns those into the colour for the theme. Shiki
// cannot run in the student's browser (its grammars and the regular-
// expression engine are hundreds of KB per site), so the editor colours what
// a student types with this small copy of the same rules: each token gets a
// CATEGORY, and codeRunner.scss gives each category's class Shiki's own two
// custom properties (the check pins those values to the image's Shiki, theme
// by theme). Light and dark then follow through Quartz's own rule, exactly as
// a static block's spans do.
//
// UNTOUCHED LINES ARE SHIKI'S OWN. The page's script keeps the highlighted
// copy's lines and shows Shiki's own spans for every line a student has not
// changed (reusePlan, below); this tokenizer only colours the lines they
// have. Where the two disagree (documentation/06, I11: about 0.3 % of the
// characters on edited Python lines), only an edited line can show it.
//
// THE STATE A LINE STARTS IN. Shiki's colouring of a line is decided by the
// line's text and the state the grammar is in when the line starts: inside a
// triple-quoted f-string, inside a multi-line call, and so on. Every line
// this answers carries that state as a string, so a line is reused only
// where both its text AND its state are the original's (#585 plan review
// F1: the same text inside f""", """ and r""" is coloured three ways).

// The categories, each a pair of Shiki's colours (codeRunnerBlocks.colour.
// categories, codeRunner.scss's .plantoir-tok-<category>). "" is plain text.
export type Category = "" | "k" | "s" | "c" | "f" | "m" | "p" | "g" | "r"
export type Token = [string, Category]
export type ColouredLine = { text: string; state: string; tokens: Token[] }

export const CATEGORIES: Category[] = ["k", "s", "c", "f", "m", "p", "g", "r"]

// The languages this colours, by the language row's `colour` field.
export function colourLines(colour: string, source: string): ColouredLine[] | null {
  if (colour === "python") {
    return colourPython(source)
  }
  if (colour === "swift") {
    return colourSwift(source)
  }
  return null
}

// One line's tokens as HTML: a span with the category's class around each
// coloured run, plain text as text.
export function lineHTML(tokens: Token[]): string {
  let html = ""
  for (const [text, category] of tokens) {
    const escaped = escapeHTML(text)
    if (category === "") {
      html += escaped
    } else {
      html += `<span class="plantoir-tok-${category}">${escaped}</span>`
    }
  }
  return html
}

export function escapeHTML(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// Which ORIGINAL line, if any, each current line may show Shiki's own spans
// for (#585 plan review F1). By position first: the lines the two share at
// the top, and then at the bottom, are reused where text and state are both
// the same. Only the edited middle falls back to a lookup by text and state,
// and only for a key every original line that has it colours alike
// (`sameColouring` says whether two original lines do).
export function reusePlan(
  original: { text: string; state: string }[],
  current: { text: string; state: string }[],
  sameColouring: (first: number, second: number) => boolean,
): (number | null)[] {
  const plan: (number | null)[] = []
  for (let index = 0; index < current.length; index += 1) {
    plan.push(null)
  }
  const same = (a: { text: string; state: string }, b: { text: string; state: string }) =>
    a.text === b.text && a.state === b.state
  let top = 0
  while (top < original.length && top < current.length && same(original[top], current[top])) {
    plan[top] = top
    top += 1
  }
  let bottom = 0
  while (
    bottom < original.length - top &&
    bottom < current.length - top &&
    same(original[original.length - 1 - bottom], current[current.length - 1 - bottom])
  ) {
    plan[current.length - 1 - bottom] = original.length - 1 - bottom
    bottom += 1
  }
  if (top + bottom >= current.length) {
    return plan
  }
  // The edited middle: a key's first original line, unless another original
  // line with the same key is coloured differently.
  const byKey = new Map<string, number>()
  const unsafe = new Set<string>()
  for (let index = 0; index < original.length; index += 1) {
    const key = original[index].state + "\u0000" + original[index].text
    const first = byKey.get(key)
    if (first === undefined) {
      byKey.set(key, index)
    } else if (!sameColouring(first, index)) {
      unsafe.add(key)
    }
  }
  for (let index = top; index < current.length - bottom; index += 1) {
    const key = current[index].state + "\u0000" + current[index].text
    const found = byKey.get(key)
    if (found !== undefined && !unsafe.has(key)) {
      plan[index] = found
    }
  }
  return plan
}

// ---- Shared machinery -----------------------------------------------------------

// Collects tokens into lines, noting the state each line starts in. `mode`
// is the scanner's string or comment state, `brackets` its open brackets'
// kinds; both are read at each line break.
type Sink = {
  push: (text: string, category: Category) => void
  mode: string
  brackets: string[]
  finish: () => ColouredLine[]
}

function makeSink(): Sink {
  const lines: ColouredLine[] = []
  let tokens: Token[] = []
  let text = ""
  let state = "|"
  const sink: Sink = {
    mode: "",
    brackets: [],
    push: (piece: string, category: Category) => {
      let start = 0
      while (start <= piece.length) {
        const newline = piece.indexOf("\n", start)
        const part = newline < 0 ? piece.slice(start) : piece.slice(start, newline)
        if (part !== "") {
          const last = tokens.length > 0 ? tokens[tokens.length - 1] : null
          if (last !== null && last[1] === category) {
            last[0] += part
          } else {
            tokens.push([part, category])
          }
          text += part
        }
        if (newline < 0) {
          break
        }
        lines.push({ text, state, tokens })
        tokens = []
        text = ""
        state = sink.mode + "|" + sink.brackets.join(",")
        start = newline + 1
      }
    },
    finish: () => {
      lines.push({ text, state, tokens })
      return lines
    },
  }
  return sink
}

const IDENTIFIER = /[A-Za-z_À-￿][A-Za-z0-9_À-￿]*/y

function matchAt(pattern: RegExp, text: string, at: number): RegExpExecArray | null {
  pattern.lastIndex = at
  return pattern.exec(text)
}

function wordList(words: string): Set<string> {
  return new Set(words.split(/\s+/).filter((word) => word.length > 0))
}

// ---- Python -----------------------------------------------------------------------
// The rules are Shiki's Python grammar's (MagicPython) as github-light and
// github-dark colour them, measured against the image's Shiki 1.26.2:
// keywords and operators red; strings and their prefixes; escapes, `%` and
// `{}` placeholders, numbers, builtins, `self`, ALL_CAPS names and
// `__dunder__` names blue; the names a `def` or `class` defines, base
// classes and decorators purple; a call's keyword-argument names orange;
// comments grey with TODO and the other code tags red; raw strings (a
// lowercase r) read as regular expressions, as Shiki reads them, their text
// in the expression's own colour.

const PY_KEYWORDS = wordList(`and as assert async await break class continue def del elif else except
  finally for from global if import in is lambda nonlocal not or pass raise return try while with yield`)
const PY_CONSTANTS = wordList("True False None Ellipsis NotImplemented __debug__")
const PY_BUILTINS = wordList(`abs aiter all anext any ascii bin bool breakpoint bytearray bytes callable chr
  classmethod compile complex copyright credits delattr dict dir divmod enumerate eval exec exit filter float
  format frozenset getattr globals hasattr hash help hex id input int isinstance issubclass iter len license
  list locals map max memoryview min next object oct open ord pow print property quit range repr reversed
  round set setattr slice sorted staticmethod str sum super tuple type vars zip __import__
  ArithmeticError AssertionError AttributeError BaseException BaseExceptionGroup BlockingIOError
  BrokenPipeError BufferError BytesWarning ChildProcessError ConnectionAbortedError ConnectionError
  ConnectionRefusedError ConnectionResetError DeprecationWarning EncodingWarning EnvironmentError EOFError
  Exception ExceptionGroup FileExistsError FileNotFoundError FloatingPointError FutureWarning GeneratorExit
  ImportError ImportWarning IndentationError IndexError InterruptedError IOError IsADirectoryError KeyError
  KeyboardInterrupt LookupError MemoryError ModuleNotFoundError NameError NotADirectoryError
  NotImplementedError OSError OverflowError PendingDeprecationWarning PermissionError ProcessLookupError
  RecursionError ReferenceError ResourceWarning RuntimeError RuntimeWarning StopAsyncIteration StopIteration
  SyntaxError SyntaxWarning SystemError SystemExit TabError TimeoutError TypeError UnboundLocalError
  UnicodeDecodeError UnicodeEncodeError UnicodeError UnicodeTranslateError UnicodeWarning UserWarning
  ValueError Warning WindowsError ZeroDivisionError`)
// The builtin types, which an index leaves plain (`list[int]`).
const PY_BUILTIN_TYPES = wordList(`bool bytearray bytes classmethod complex dict float frozenset int list object
  property set slice staticmethod str tuple type super`)
// Python 2's names, which the grammar marks as legacy (orange).
const PY_LEGACY = wordList("apply basestring cmp coerce execfile file intern long raw_input reduce unichr unicode xrange")
const PY_OPERATORS = ["**=", "//=", ">>=", "<<=", "**", "//", "==", "!=", "<>", "<=", ">=", ":=", "+=", "-=", "*=",
  "/=", "%=", "&=", "|=", "^=", "@=", "<<", ">>", "=", "+", "-", "*", "/", "%", "<", ">", "&", "|", "^", "~", "@"]
const PY_NUMBER = /(0[xX])([0-9a-fA-F_]+)|(0[bB])([01_]+)|(0[oO])([0-7_]+)|((?:\d[\d_]*)?\.?\d[\d_]*(?:[eE][+-]?\d[\d_]*)?)([jJ])?/y
// ALL_CAPS: the grammar's constant pattern, with at least two capitals (a
// lone `X` or `T` is a name, measured).
const PY_CAPS = /^(?=_*[A-Z][A-Z0-9]*(?:_\w*)?$)(?=[^A-Z]*[A-Z][^A-Z]*[A-Z])/
const PY_DUNDER = /^__\w+__$/
const PY_STRING_START = /([rRbBuUfF]{1,2})?('''|"""|'|")/y
const PY_CODETAG = /\b(NOTE|XXX|HACK|FIXME|BUG|TODO)\b/g
// A `%` placeholder in a string, and the two `{}` placeholder forms.
const PY_PERCENT = /%(\([\w\s]*\))?[-+#0 ]*(\d+|\*)?(\.(\d+|\*))?([hlL])?[diouxXeEfFgGcrsab%]/y
const PY_BRACE_SIMPLE = /\{\{|\}\}|\{(\w*(?:\.[A-Za-z_]\w*|\[[^\]'"]+\])*)(![rsa])?(:\w?[<>=^]?[-+ ]?#?\d*,?(?:\.\d+)?[bcdeEfFgGnosxX%]?)?\}/y
const PY_BRACE_NESTED = /\{(\w*(?:\.[A-Za-z_]\w*|\[[^\]'"]+\])*)(![rsa])?(:)[^'"{}\n]*(?:\{[^'"}\n]*?\}[^'"{}\n]*)*\}/y
// An f-string's format spec that holds no `{}`, up to its closing brace.
const PY_SPEC_SIMPLE = /(![rsa])?(:\w?[<>=^]?[-+ ]?#?\d*,?(?:\.\d+)?[bcdeEfFgGnosxX%]?)?(?=\})/y
const PY_ESCAPE = /\\(?:x[0-9A-Fa-f]{2}|[0-7]{1,3}|[\\"'abfnrtv\n])/y
const PY_UNICODE_ESCAPE = /\\(?:u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8}|N\{[\w\s-]+?\})/y

export function colourPython(source: string): ColouredLine[] {
  const sink = makeSink()
  const push = sink.push
  const text = source
  const end = text.length

  // A statement starts here: only whitespace before it on its line, and no
  // bracket open.
  const atStatementStart = (at: number, brackets: string[]): boolean => {
    if (brackets.length > 0) {
      return false
    }
    let back = at - 1
    while (back >= 0 && (text[back] === " " || text[back] === "\t")) {
      back -= 1
    }
    return back < 0 || text[back] === "\n" || text[back] === ";"
  }

  // `match`/`case` are keywords only where they open a statement that ends
  // in a colon.
  const softKeyword = (at: number, word: string, brackets: string[]): boolean => {
    if (!atStatementStart(at, brackets)) {
      return false
    }
    let lineEnd = text.indexOf("\n", at)
    if (lineEnd < 0) {
      lineEnd = end
    }
    const rest = text.slice(at + word.length, lineEnd).replace(/#.*$/, "").trimEnd()
    return /^[ \t]+[^=\s.,)]/.test(rest) && rest.endsWith(":") && !/^[ \t]*[=:]/.test(rest)
  }

  // Code from `at`: the whole program (fstring false), or one f-string
  // replacement field's expression, which stops at its closing brace or at a
  // conversion or format spec. Answers where it stopped.
  const code = (start: number, fstring: boolean): number => {
    let at = start
    const brackets: string[] = fstring ? [] : sink.brackets
    let previous = ""
    let previousCategory: Category = ""
    let afterDefinition = ""
    let definedWord = ""
    let braces = 0
    while (at < end) {
      const ch = text[at]
      if (ch === "\n") {
        if (fstring && brackets.length === 0) {
          return at
        }
        push("\n", "")
        at += 1
        continue
      }
      if (ch === " " || ch === "\t" || ch === "\r" || ch === "\f") {
        push(ch, "")
        at += 1
        continue
      }
      if (ch === "#") {
        let lineEnd = text.indexOf("\n", at)
        if (lineEnd < 0) {
          lineEnd = end
        }
        pushComment(text.slice(at, lineEnd))
        at = lineEnd
        continue
      }
      if (fstring && brackets.length === 0) {
        if (ch === "}" && braces === 0) {
          return at
        }
        if (ch === "!" && text[at + 1] !== "=") {
          return at
        }
        if (ch === ":" && braces === 0) {
          return at
        }
      }
      if (text.startsWith("...", at)) {
        push("...", "c")
        at += 3
        previous = "..."
        previousCategory = "c"
        continue
      }
      const stringStart = matchAt(PY_STRING_START, text, at)
      if (stringStart !== null && (stringStart[1] === undefined || !/[A-Za-z0-9_]/.test(text[at - 1] ?? ""))) {
        const prefix = stringStart[1] ?? ""
        if (validPrefix(prefix)) {
          if (prefix !== "") {
            push(prefix, "k")
          }
          // A string that opens a statement is a docstring to the grammar:
          // escapes, but no placeholders and no regular expression.
          const docstring = !fstring && /^[rR]?$/.test(prefix) && atStatementStart(at, brackets)
          at = string(at + prefix.length, stringStart[2], prefix, docstring)
          previous = "string"
          previousCategory = "s"
          continue
        }
      }
      if (/[0-9]/.test(ch) || (ch === "." && /[0-9]/.test(text[at + 1] ?? ""))) {
        const number = matchAt(PY_NUMBER, text, at)!
        if (number[1] !== undefined) {
          push(number[1], "k")
          push(number[2], "c")
        } else if (number[3] !== undefined) {
          push(number[3], "k")
          push(number[4], "c")
        } else if (number[5] !== undefined) {
          push(number[5], "k")
          push(number[6], "c")
        } else {
          push(number[7], "c")
          if (number[8] !== undefined) {
            push(number[8], "k")
          }
        }
        at += number[0].length
        previous = "number"
        previousCategory = "c"
        continue
      }
      const identifier = matchAt(IDENTIFIER, text, at)
      if (identifier !== null) {
        const word = identifier[0]
        const inside = brackets.length > 0 ? brackets[brackets.length - 1] : ""
        const atArgument = previous === "(" || previous === ","
        // What follows the name: a call's `(` or an index's `[`, after any spaces.
        const following = /^[ \t]*([([]?)/.exec(text.slice(at + word.length, at + word.length + 16))![1]
        let category: Category = ""
        definedWord = ""
        if (afterDefinition !== "") {
          category = afterDefinition === "def" && PY_DUNDER.test(word) ? "c" : "f"
          definedWord = afterDefinition
          afterDefinition = ""
        } else if (previous === ".") {
          if (PY_DUNDER.test(word)) {
            category = "c"
          } else if (following === "(") {
            category = ""
          } else if (PY_CAPS.test(word)) {
            category = "c"
          } else if (inside === "class") {
            category = "f"
          }
        } else if (PY_KEYWORDS.has(word)) {
          category = "k"
        } else if ((word === "match" || word === "case") && softKeyword(at, word, brackets)) {
          category = "k"
        } else if ((word === "self" || word === "cls") && inside === "def") {
          category = ""
        } else if (word === "self" || word === "cls" || PY_CONSTANTS.has(word)) {
          category = "c"
        } else if (inside === "call" && atArgument && /^[ \t]*=(?!=)/.test(text.slice(at + word.length, at + word.length + 8))) {
          category = "p"
        } else if (inside === "class" && word === "metaclass") {
          category = "c"
        } else if (following === "(") {
          // A call: blue for a builtin, plain for any other name.
          category = PY_BUILTINS.has(word) || PY_DUNDER.test(word) ? "c" : PY_LEGACY.has(word) ? "p" : ""
        } else if (following === "[") {
          // An index: the builtin TYPES are plain there (`list[int]`).
          if (PY_BUILTIN_TYPES.has(word)) {
            category = ""
          } else if (PY_BUILTINS.has(word) || PY_DUNDER.test(word) || PY_CAPS.test(word)) {
            category = "c"
          } else if (PY_LEGACY.has(word)) {
            category = "p"
          }
        } else if (PY_BUILTINS.has(word) || PY_DUNDER.test(word)) {
          category = "c"
        } else if (PY_LEGACY.has(word)) {
          category = "p"
        } else if (PY_CAPS.test(word)) {
          category = "c"
        } else if (inside === "class") {
          category = "f"
        }
        if (word === "def" || word === "class") {
          afterDefinition = word
        }
        push(word, category)
        at += word.length
        previous = word
        previousCategory = category
        continue
      }
      if (ch === "(" || ch === "[" || ch === "{") {
        let kind = "plain"
        if (ch === "(" && definedWord !== "") {
          kind = definedWord
        } else if (
          ch === "(" &&
          previous !== "" &&
          (previous === ")" || previous === "]" || /^[A-Za-z_À-￿]/.test(previous)) &&
          !PY_KEYWORDS.has(previous)
        ) {
          kind = "call"
        }
        definedWord = ""
        if (fstring && ch === "{") {
          braces += 1
        }
        brackets.push(kind)
        push(ch, "")
        at += 1
        previous = ch
        previousCategory = ""
        continue
      }
      if (ch === ")" || ch === "]" || ch === "}") {
        if (fstring && ch === "}") {
          braces -= 1
        }
        brackets.pop()
        push(ch, "")
        at += 1
        previous = ch
        previousCategory = ""
        continue
      }
      if (text.startsWith("->", at)) {
        push("->", "")
        at += 2
        previous = "->"
        previousCategory = ""
        continue
      }
      if (ch === "@" && atStatementStart(at, brackets)) {
        // A decorator: one builtin name is `@` purple and the name blue; any
        // other name, dotted or not, is purple from end to end.
        const dotted = /@[ \t]*([A-Za-z_À-￿][\w.À-￿]*)/y
        const decorator = matchAt(dotted, text, at)
        if (decorator !== null) {
          const name = decorator[1]
          if (!name.includes(".") && PY_BUILTINS.has(name)) {
            push(decorator[0].slice(0, decorator[0].length - name.length), "f")
            push(name, "c")
          } else {
            push(decorator[0], "f")
          }
          at += decorator[0].length
          previous = name
          previousCategory = "f"
          continue
        }
      }
      let operator = ""
      for (const candidate of PY_OPERATORS) {
        if (text.startsWith(candidate, at)) {
          operator = candidate
          break
        }
      }
      if (operator !== "") {
        push(operator, "k")
        at += operator.length
        previous = operator
        previousCategory = "k"
        continue
      }
      push(ch, "")
      at += 1
      previous = ch
      previousCategory = ""
    }
    void previousCategory
    return at
  }

  const pushComment = (comment: string) => {
    let from = 0
    PY_CODETAG.lastIndex = 0
    let tag = PY_CODETAG.exec(comment)
    while (tag !== null) {
      push(comment.slice(from, tag.index), "m")
      push(tag[0], "k")
      from = tag.index + tag[0].length
      tag = PY_CODETAG.exec(comment)
    }
    push(comment.slice(from), "m")
  }

  // A string from its opening quote; answers the index after its closing
  // quote (or where a one-line string stopped at the end of its line).
  const string = (start: number, quote: string, prefix: string, docstring: boolean): number => {
    const regexp = prefix.includes("r") && !/[fF]/.test(prefix) && !docstring
    const raw = /[rR]/.test(prefix)
    const formatted = /[fF]/.test(prefix)
    const bytes = /[bB]/.test(prefix)
    const outerMode = sink.mode
    sink.mode = quote + prefix
    push(quote, "s")
    let at = start + quote.length
    let from = at
    const flush = (to: number) => {
      if (to > from) {
        push(text.slice(from, to), "s")
      }
    }
    const close = (): number => {
      sink.mode = outerMode
      return at
    }
    if (regexp) {
      at = regularExpression(at, quote)
      if (text.startsWith(quote, at)) {
        push(quote, "s")
        at += quote.length
      }
      return close()
    }
    while (at < end) {
      if (text.startsWith(quote, at)) {
        flush(at)
        push(quote, "s")
        at += quote.length
        return close()
      }
      const ch = text[at]
      if (ch === "\n" && quote.length === 1) {
        flush(at)
        return close()
      }
      if (ch === "\\") {
        if (raw) {
          // A raw string's backslash only keeps a quote or a backslash from
          // ending it; a brace after it is still a field.
          at += text[at + 1] === quote[0] || text[at + 1] === "\\" ? 2 : 1
          continue
        }
        const escape = matchAt(PY_ESCAPE, text, at) ?? (bytes ? null : matchAt(PY_UNICODE_ESCAPE, text, at))
        if (escape !== null) {
          flush(at)
          push(escape[0], "c")
          at += escape[0].length
          from = at
          continue
        }
        at += text[at + 1] === undefined || text[at + 1] === "\n" ? 1 : 2
        continue
      }
      if (formatted) {
        if ((ch === "{" || ch === "}") && text[at + 1] === ch) {
          flush(at)
          push(ch + ch, "c")
          at += 2
          from = at
          continue
        }
        if (ch === "{") {
          flush(at)
          at = replacementField(at)
          from = at
          continue
        }
        at += 1
        continue
      }
      if (docstring) {
        // A docstring's code tags are red, as a comment's are.
        const tag = matchAt(/\b(?:NOTE|XXX|HACK|FIXME|BUG|TODO)\b/y, text, at)
        if (tag !== null && !/\w/.test(text[at - 1] ?? "")) {
          flush(at)
          push(tag[0], "k")
          at += tag[0].length
          from = at
          continue
        }
        at += 1
        continue
      }
      if (ch === "%" && !raw) {
        const placeholder = matchAt(PY_PERCENT, text, at)
        if (placeholder !== null) {
          flush(at)
          push(placeholder[0], "c")
          at += placeholder[0].length
          from = at
          continue
        }
      }
      if ((ch === "{" || ch === "}") && !bytes) {
        const simple = matchAt(PY_BRACE_SIMPLE, text, at)
        const nested = simple === null ? matchAt(PY_BRACE_NESTED, text, at) : null
        const found = simple ?? nested
        if (found !== null) {
          flush(at)
          pushPlaceholder(found)
          at += found[0].length
          from = at
          continue
        }
      }
      at += 1
    }
    flush(at)
    return close()
  }

  // A `{}` placeholder in a plain string: blue, with its conversion and
  // format spec red.
  const pushPlaceholder = (found: RegExpExecArray) => {
    const whole = found[0]
    if (whole === "{{" || whole === "}}") {
      push(whole, "c")
      return
    }
    const head = "{" + (found[1] ?? "")
    const conversion = found[2] ?? ""
    const spec = found[3] ?? ""
    push(head, "c")
    if (conversion !== "") {
      push(conversion, "k")
    }
    if (spec !== "") {
      push(spec, "k")
    }
    push(whole.slice(head.length + conversion.length + spec.length), "c")
  }

  // An f-string's replacement field, from its `{`: the expression as code,
  // then a conversion and format spec, then `}`.
  const replacementField = (start: number): number => {
    push("{", "c")
    let at = code(start + 1, true)
    const simple = matchAt(PY_SPEC_SIMPLE, text, at)
    if (simple !== null && simple[0] !== "") {
      push(simple[0], "k")
      at += simple[0].length
    } else if ((text[at] === "!" || text[at] === ":") && /^(![rsa])?:[^\n}]*\{/.test(text.slice(at, at + 200))) {
      // A format spec with fields of its own: `:` red, each `{...}` a
      // field, the spec's own characters red, a lone `.` plain.
      const opener = /(![rsa])?:/y
      const head = matchAt(opener, text, at)!
      push(head[0], "k")
      at += head[0].length
      while (at < end && text[at] !== "}" && text[at] !== "\n") {
        if (text[at] === "{") {
          at = replacementField(at)
          continue
        }
        const decimals = matchAt(/\.\d+/y, text, at)
        if (decimals !== null) {
          push(decimals[0], "k")
          at += decimals[0].length
          continue
        }
        push(text[at], /[\w,#\-+ <>=^%]/.test(text[at]) ? "k" : "")
        at += 1
      }
    } else if (text[at] === "!" || text[at] === ":") {
      // Not a format spec the grammar knows: the rest reads as code.
      push(text[at], text[at] === "!" ? "k" : "")
      at = code(at + 1, true)
    }
    if (text[at] === "}") {
      push("}", "c")
      at += 1
    }
    return at
  }

  // A raw string with a lowercase r, which the grammar reads as a regular
  // expression: classes and groups blue, quantifiers and alternation red,
  // escapes green (a class escape such as \d blue).
  const regularExpression = (start: number, quote: string): number => {
    let at = start
    let from = at
    const groups: string[] = []
    // A regular expression's own text is its own colour: a string's in
    // light, a paler blue in dark (measured: #032F62 / #DBEDFF).
    const flush = (to: number) => {
      if (to > from) {
        push(text.slice(from, to), "r")
      }
    }
    const emit = (piece: string, category: Category) => {
      flush(at)
      push(piece, category)
      at += piece.length
      from = at
    }
    while (at < end) {
      if (text.startsWith(quote, at)) {
        break
      }
      const ch = text[at]
      if (ch === "\n" && quote.length === 1) {
        break
      }
      if (ch === "\\") {
        const escape = regexpEscape(at, quote)
        emit(escape[0], escape[1])
        continue
      }
      if (ch === "#" && quote.length === 3) {
        // A triple-quoted expression is read in verbose mode: `#` starts a
        // comment to the end of the line.
        let stop = at
        while (stop < end && text[stop] !== "\n" && !text.startsWith(quote, stop)) {
          stop += 1
        }
        emit(text.slice(at, stop), "m")
        continue
      }
      if (ch === "[") {
        // `[]` and `[^]` are no set (plain); `]` straight after `[` is a
        // literal only when another `]` follows on the line.
        const empty = matchAt(/\[\^?\]/y, text, at)
        if (empty !== null) {
          let lineEnd = text.indexOf("\n", at)
          if (lineEnd < 0) {
            lineEnd = end
          }
          if (!text.slice(at + empty[0].length, lineEnd).includes("]")) {
            at += empty[0].length
            continue
          }
        }
        flush(at)
        from = at
        at = characterSet(at, quote)
        from = at
        continue
      }
      if (ch === "(") {
        const comment = /\(\?#[^)]*\)/y
        const named = /\(\?P<\w+>/y
        const look = /\(\?(?:=|!|<=|<!)/y
        const nonCapturing = /\(\?:/y
        const foundComment = matchAt(comment, text, at)
        if (foundComment !== null) {
          emit(foundComment[0], "m")
          continue
        }
        const foundNamed = matchAt(named, text, at)
        if (foundNamed !== null) {
          emit("(", "c")
          emit(foundNamed[0].slice(1), "g")
          groups.push("c")
          continue
        }
        const foundLook = matchAt(look, text, at)
        if (foundLook !== null) {
          emit(foundLook[0], "k")
          groups.push("k")
          continue
        }
        const foundNonCapturing = matchAt(nonCapturing, text, at)
        if (foundNonCapturing !== null) {
          emit(foundNonCapturing[0], "c")
          groups.push("c")
          continue
        }
        emit("(", "c")
        groups.push("c")
        continue
      }
      if (ch === ")") {
        // A `)` that closes no group is a plain character.
        const group = groups.pop()
        if (group === undefined) {
          at += 1
          continue
        }
        emit(")", group as Category)
        continue
      }
      const quantifier = matchAt(/(?:[*+?]|\{\d+(?:,\d*)?\})[?+]?/y, text, at)
      if (quantifier !== null) {
        emit(quantifier[0], "k")
        continue
      }
      if (ch === "|") {
        emit("|", "k")
        continue
      }
      if (ch === "^" || ch === "$" || ch === ".") {
        emit(ch, "c")
        continue
      }
      at += 1
    }
    flush(at)
    return at
  }

  const regexpEscape = (at: number, quote: string): [string, Category] => {
    const special = /\\[dDwWsSbBAZz]/y
    const foundSpecial = matchAt(special, text, at)
    if (foundSpecial !== null) {
      return [foundSpecial[0], "c"]
    }
    const long = /\\(?:x[0-9A-Fa-f]{2}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8}|N\{[\w\s-]+?\}|0[0-7]{0,2}|[1-9]\d?)/y
    const foundLong = matchAt(long, text, at)
    if (foundLong !== null) {
      return [foundLong[0], "g"]
    }
    const next = text[at + 1]
    if (next === undefined || (next === "\n" && quote.length === 1)) {
      return ["\\", "g"]
    }
    return ["\\" + next, "g"]
  }

  // A regular expression's [...] set: blue, `^` after `[` red, escapes as
  // above but green unless a class escape.
  const characterSet = (start: number, quote: string): number => {
    let at = start
    push("[", "c")
    at += 1
    if (text[at] === "^") {
      push("^", "k")
      at += 1
    }
    let from = at
    if (text[at] === "]") {
      at += 1
    }
    const flush = (to: number) => {
      if (to > from) {
        push(text.slice(from, to), "c")
      }
    }
    while (at < end) {
      if (text.startsWith(quote, at) || (text[at] === "\n" && quote.length === 1)) {
        flush(at)
        return at
      }
      if (text[at] === "\\") {
        flush(at)
        const escape = regexpEscape(at, quote)
        push(escape[0], escape[1] === "c" ? "c" : "g")
        at += escape[0].length
        from = at
        continue
      }
      if (text[at] === "]") {
        flush(at + 1)
        return at + 1
      }
      at += 1
    }
    flush(at)
    return at
  }

  code(0, false)
  return sink.finish()
}

function validPrefix(prefix: string): boolean {
  if (prefix === "") {
    return true
  }
  const lower = prefix.toLowerCase()
  return ["r", "u", "b", "f", "br", "rb", "fr", "rf"].includes(lower)
}

// ---- Swift ------------------------------------------------------------------------
// Shiki's Swift grammar as github-light and github-dark colour it, measured
// against the image's Shiki 1.26.2. No Swift block is editable yet (#579):
// a Swift block shows Shiki's own copy, so this runs only through the
// contract's cases and the check's agreement score until one is.

const SW_KEYWORDS = wordList(`associatedtype class deinit enum extension fileprivate func import init inout
  internal let open operator private precedencegroup protocol public rethrows static struct subscript
  typealias var break case catch continue default defer do else fallthrough for guard if in repeat return
  throw switch where while as is try throws async await some any lazy weak unowned mutating nonmutating
  override final required convenience dynamic indirect optional get set willSet didSet consuming borrowing
  package nonisolated isolated`)
const SW_CONSTANTS = wordList("true false nil self super")
// The types and the members the grammar knows by name (measured: a name it
// does not list is plain, `Codable` and `width` among them).
const SW_TYPES = wordList(`Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64 Double Float Float80
  Bool String Character Array Dictionary Set Optional Void Any AnyObject Never Range ClosedRange Equatable
  Hashable Comparable Error Sequence Collection CustomStringConvertible CustomDebugStringConvertible
  RawRepresentable FloatingPoint IteratorProtocol Self Strideable SignedInteger`)
const SW_MEMBERS = wordList(`count isEmpty first last indices keys values description min max some none
  startIndex endIndex capacity underestimatedCount lazy rawValue hashValue debugDescription value text utf8
  unicodeScalars characters pi infinity isNaN`)
const SW_OPERATORS = ["...", "..<", "===", "!==", "->", "&&", "||", "==", "!=", "<=", ">=", "+=", "-=", "*=",
  "/=", "%=", "??", "&+", "&-", "&*", "<<", ">>", "=", "+", "-", "*", "/", "%", "<", ">", "!", "&", "|", "^",
  "~", "?"]
const SW_NUMBER = /-?(?:0x[0-9a-fA-F_]+(?:\.[0-9a-fA-F_]+)?(?:[pP][+-]?\d+)?|0b[01_]+|0o[0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)/y
// A `{` after a member in these statements opens their body, not a
// trailing closure.
const SW_CONDITIONS = wordList("if while guard for switch else repeat")
const SW_DECLARING = wordList("func struct class enum protocol extension typealias associatedtype actor")

export function colourSwift(source: string): ColouredLine[] {
  const sink = makeSink()
  const push = sink.push
  const text = source
  const end = text.length

  // Code from `at`: the program, or (plain "s") one string interpolation,
  // which stops at its closing parenthesis.
  const code = (start: number, plain: Category, interpolation: boolean): number => {
    let at = start
    const brackets: string[] = interpolation ? [] : sink.brackets
    let previous = ""
    let declaring = ""
    let statement = ""
    let ternaries = 0
    let afterWhere = false
    let inheritance = false
    let generic = false
    let depth = 0
    while (at < end) {
      const ch = text[at]
      if (interpolation) {
        if (ch === "(") {
          depth += 1
        }
        if (ch === ")") {
          if (depth === 0) {
            return at
          }
          depth -= 1
        }
      }
      if (ch === "\n" || ch === ";") {
        statement = ""
        afterWhere = false
        inheritance = false
        ternaries = 0
        push(ch, ch === ";" ? plain : plain)
        at += 1
        if (ch === ";") {
          previous = ";"
        }
        continue
      }
      if (ch === " " || ch === "\t" || ch === "\r") {
        push(ch, plain)
        at += 1
        continue
      }
      if (text.startsWith("//", at)) {
        let lineEnd = text.indexOf("\n", at)
        if (lineEnd < 0) {
          lineEnd = end
        }
        push(text.slice(at, lineEnd), "m")
        at = lineEnd
        continue
      }
      if (text.startsWith("/*", at)) {
        at = blockComment(at)
        continue
      }
      const stringStart = matchAt(/(#*)("""|")/y, text, at)
      if (stringStart !== null) {
        at = string(at, stringStart[1], stringStart[2])
        previous = '"'
        continue
      }
      const unary = ch === "-" && /[0-9]/.test(text[at + 1] ?? "") && !/^[A-Za-z0-9_)\]"]$/.test(previous)
      if ((/[0-9]/.test(ch) || unary) && previous !== ".") {
        const number = matchAt(SW_NUMBER, text, at)!
        push(number[0], "c")
        at += number[0].length
        previous = "0"
        continue
      }
      if (ch === "@") {
        const attribute = matchAt(IDENTIFIER, text, at + 1)
        if (attribute !== null) {
          push("@" + attribute[0], "k")
          at += 1 + attribute[0].length
          previous = "@" + attribute[0]
          continue
        }
      }
      if (ch === "#") {
        const directive = matchAt(IDENTIFIER, text, at + 1)
        if (directive !== null) {
          if (["if", "elseif", "else", "endif"].includes(directive[0])) {
            push("#", plain)
            push(directive[0], "k")
          } else {
            push("#" + directive[0], "c")
          }
          at += 1 + directive[0].length
          previous = "#" + directive[0]
          continue
        }
      }
      if (ch === "$" && /[0-9]/.test(text[at + 1] ?? "")) {
        let after = at + 1
        while (/[0-9]/.test(text[after] ?? "")) {
          after += 1
        }
        push(text.slice(at, after), "c")
        at = after
        previous = "0"
        continue
      }
      const identifier = matchAt(IDENTIFIER, text, at)
      if (identifier !== null) {
        const word = identifier[0]
        const after = text.slice(at + word.length, at + word.length + 40)
        const inside = brackets.length > 0 ? brackets[brackets.length - 1] : ""
        const atArgument = previous === "(" || previous === ","
        const labelled = /^[ \t]*:(?!:)/.test(after)
        let category: Category = plain
        if (statement === "") {
          statement = word
        }
        if (declaring !== "") {
          category = declaring === "extension" || declaring === "associatedtype" ? "c" : "f"
          if (declaring === "func" || declaring === "init") {
            category = "f"
          }
          inheritance = declaring !== "func" && declaring !== "typealias" && declaring !== "associatedtype"
          declaring = ""
        } else if (previous === "import") {
          category = "f"
        } else if (previous === ".") {
          // A member: blue when called (or given a trailing closure) or
          // one the grammar knows; plain otherwise, even inside a string.
          if (word === "init" || word === "self") {
            category = "k"
          } else if (SW_MEMBERS.has(word) || /^[ \t]*\(/.test(after) || (/^[ \t]*\{/.test(after) && !SW_CONDITIONS.has(statement))) {
            category = "c"
          } else {
            category = ""
          }
        } else if (labelled && atArgument && (inside === "call" || inside === "plain")) {
          category = "c"
        } else if (word === "_") {
          category = inside === "decl" && atArgument ? "f" : "c"
        } else if (word === "try" && text[at + word.length] === "?") {
          category = "k"
        } else if ((word === "as" || word === "try") && (text[at + 2 + (word === "try" ? 1 : 0)] === "?" || text[at + word.length] === "!")) {
          category = "k"
        } else if (SW_KEYWORDS.has(word)) {
          category = "k"
        } else if (SW_CONSTANTS.has(word)) {
          category = "c"
        } else if (generic && inside === "generic") {
          category = SW_TYPES.has(word) || atArgument || previous === "<" ? "c" : plain
        } else if (inheritance) {
          category = SW_TYPES.has(word) ? "c" : "f"
        } else if (inside === "decl" && atArgument) {
          category = "f"
        } else if (inside === "attribute") {
          category = "k"
        } else if (SW_TYPES.has(word) || /^[ \t]*\(/.test(after)) {
          category = "c"
        } else if (statement === "case" && previous === "case" && brackets.includes("enum")) {
          category = "c"
        } else if (previous === "," && statement === "case" && brackets[brackets.length - 1] === "enum") {
          category = "c"
        }
        if (SW_DECLARING.has(word)) {
          declaring = word
        }
        if (word === "where") {
          afterWhere = true
          inheritance = false
        }
        push(word, category)
        at += word.length
        // `try?`, `try!`, `as?` and `as!` are one keyword.
        if ((word === "try" || word === "as") && (text[at] === "?" || text[at] === "!")) {
          push(text[at], "k")
          at += 1
        }
        previous = word
        continue
      }
      if (ch === "(" || ch === "[" || ch === "{") {
        let kind = "plain"
        if (ch === "(" && (previous === "init" || previous === ">" || /^[A-Za-z_]/.test(previous)) && isDeclarationName(at)) {
          kind = "decl"
        } else if (ch === "(" && (previous === "@available" || previous === "#available" || previous === "#unavailable")) {
          kind = "attribute"
        } else if (ch === "(" && statement === "case" && brackets[brackets.length - 1] === "enum") {
          // An enum case's associated values: their labels are plain.
          kind = "enumcase"
        } else if (ch === "(" && /^[A-Za-z0-9_)\]?!>]$/.test(previous.slice(-1)) && !SW_KEYWORDS.has(previous)) {
          kind = "call"
        } else if (ch === "{" && pendingEnum(at)) {
          kind = "enum"
        } else if (ch === "{") {
          kind = "block"
        }
        if (ch === "{") {
          inheritance = false
          afterWhere = false
          statement = ""
        }
        brackets.push(kind)
        push(ch, plain)
        at += 1
        previous = ch
        continue
      }
      if (ch === ")" || ch === "]" || ch === "}") {
        brackets.pop()
        push(ch, plain)
        at += 1
        previous = ch
        if (ch === "}") {
          statement = ""
        }
        continue
      }
      if (ch === "<" && /^[A-Za-z_]/.test(previous) && isGenericDeclaration(at)) {
        generic = true
        brackets.push("generic")
        push("<", plain)
        at += 1
        previous = "<"
        continue
      }
      if (ch === ">" && brackets[brackets.length - 1] === "generic") {
        brackets.pop()
        generic = false
        push(">", plain)
        at += 1
        previous = ">"
        continue
      }
      if (ch === ":") {
        // Red in an expression (a dictionary, the ternary, a case or a
        // where clause, a label); plain after a name that it types or labels.
        let red = true
        if (ternaries > 0) {
          ternaries -= 1
        } else if (afterWhere || statement === "case" || statement === "default") {
          red = !(statement === "case" && brackets.length > 0 && brackets[brackets.length - 1] !== "block" && brackets[brackets.length - 1] !== "enum")
        } else if (/^[A-Za-z_À-￿]/.test(previous) && !(previous === statement && brackets.length === 0)) {
          red = false
        } else if (previous === ">" || previous === "?" || previous === "]" ) {
          red = previous === "]" && !isTypeBracketBefore(at)
        }
        push(":", red ? "k" : plain)
        at += 1
        previous = ":"
        continue
      }
      let operator = ""
      for (const candidate of SW_OPERATORS) {
        if (text.startsWith(candidate, at)) {
          operator = candidate
          break
        }
      }
      if (operator !== "") {
        if (operator === "?" && text[at - 1] === " " && text[at + 1] === " ") {
          ternaries += 1
        }
        push(operator, "k")
        at += operator.length
        previous = operator
        continue
      }
      push(ch, plain)
      at += 1
      previous = ch
    }
    return at
  }

  // `name(` declares when the word before the name is `func` or `init` is
  // the name itself.
  const isDeclarationName = (paren: number): boolean => {
    const before = text.slice(Math.max(0, paren - 120), paren)
    return /(?:\bfunc\s+[^\s(<]+(?:<[^>]*>)?|(?<![.\w])init[?!]?(?:<[^>]*>)?)\s*$/.test(before)
  }

  const isGenericDeclaration = (angle: number): boolean => {
    const before = text.slice(Math.max(0, angle - 120), angle)
    return /\b(?:func|struct|class|enum|protocol|actor|typealias)\s+[A-Za-z_][A-Za-z0-9_]*$/.test(before) || /\binit$/.test(before)
  }

  const pendingEnum = (brace: number): boolean => {
    let lineStart = text.lastIndexOf("\n", brace - 1) + 1
    const line = text.slice(lineStart, brace)
    lineStart = 0
    return /\benum\b/.test(line)
  }

  const isTypeBracketBefore = (colon: number): boolean => {
    void colon
    return false
  }

  const blockComment = (start: number): number => {
    let at = start
    let level = 0
    const outerMode = sink.mode
    while (at < end) {
      if (text.startsWith("/*", at)) {
        level += 1
        sink.mode = "/*" + String(level)
        push("/*", "m")
        at += 2
        continue
      }
      if (text.startsWith("*/", at)) {
        level -= 1
        sink.mode = level > 0 ? "/*" + String(level) : outerMode
        push("*/", "m")
        at += 2
        if (level === 0) {
          break
        }
        continue
      }
      push(text[at], "m")
      at += 1
    }
    sink.mode = outerMode
    return at
  }

  // A string from its opening hashes and quote, with its escapes and its
  // interpolations (string-coloured, with what is inside them coloured).
  const string = (start: number, hashes: string, quote: string): number => {
    const closing = quote + hashes
    const outerMode = sink.mode
    sink.mode = hashes + quote
    push(hashes + quote, "s")
    let at = start + hashes.length + quote.length
    let from = at
    const flush = (to: number) => {
      if (to > from) {
        push(text.slice(from, to), "s")
      }
    }
    const escape = "\\" + hashes
    while (at < end) {
      if (text.startsWith(closing, at)) {
        flush(at)
        push(closing, "s")
        sink.mode = outerMode
        return at + closing.length
      }
      if (text[at] === "\n" && quote === '"') {
        flush(at)
        sink.mode = outerMode
        return at
      }
      if (text.startsWith(escape, at)) {
        const after = at + escape.length
        if (text[after] === "(") {
          flush(at)
          push(escape + "(", "s")
          let inner = code(after + 1, "s", true)
          if (text[inner] === ")") {
            push(")", "s")
            inner += 1
          }
          at = inner
          from = at
          continue
        }
        const unicode = matchAt(/u\{[0-9A-Fa-f]{1,8}\}/y, text, after)
        const length = unicode !== null ? unicode[0].length : 1
        flush(at)
        push(text.slice(at, after + length), "c")
        at = after + length
        from = at
        continue
      }
      at += 1
    }
    flush(at)
    sink.mode = outerMode
    return at
  }

  code(0, "", false)
  return sink.finish()
}
