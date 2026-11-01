#!/usr/bin/env python3
r"""Write the finite-difference scaffold (plantoir-handouts, section 10) as TikZ.

The scaffold is a table of values with, beside it, a curved arrow between
each pair of rows that starts at the LOWER value and points UP to the one
above, labelled with the whole subtraction, lower minus upper, for example
`1 - (-2) = 3`; a second column does the same for second differences.

Run it; never import it (an import leaves a __pycache__ folder behind):

    python3 finite_differences.py --x -2 -1 0 1 2 --y 1 -2 -3 -2 1
    python3 finite_differences.py --x 0 1 2 3 --y 2 5 8 11 --columns 1
    python3 finite_differences.py --x -2 -1 0 1 2 --y 1 -2 -3 -2 1 \
        --page --alt "A table of y = x^2 - 3 with its first and second differences"

What it prints:

- by default, a tikzpicture for a handout in which every part that differs
  between the student copy and the answer key is written \qa{student}{answer}
  (the handout's own switch): the student copy works the first TWO first
  differences and the first second difference, so every value a worked line
  uses is already on the sheet, and the rest are short blank rules; the
  answer key has every line;
- `--nothing-worked`: the y values are what students compute, so the student
  copy has no y values and no worked lines;
- `--mode filled` or `--mode student`: one copy only, no \qa;
- `--page`: a ```tikz fence for a page, every line filled, in teal (readable
  on the site's light and dark themes). `--alt` is the sentence a screen
  reader says, and is required with `--page`.

The x and y columns are one width, from the widest value in either of
them, and the first- and second-difference columns are one width, from the
widest line in either. In a column with a negative value, or whole numbers
beside decimals, each value is right-aligned in a box as wide as the
column's widest value without its sign, the box centred (\inbox), as the
handout's N columns do (tables.tex). Every row is one pitch with its value
centred in it, so the first and last values sit half a row from the
heading rule and the bottom rule.

Values may be whole numbers or decimals. If any value in a column has a
decimal part, every value in it is written with the same number of places
(2.0 beside 4.5) and, if it mixes whole numbers and decimals, its values
are boxed as above so the points line up; the differences are written to the y
column's places.

A teacher without Python copies the static example in finite_differences.tex
(or plantoir-math-graphs section 4E for a page) and changes the numbers.
"""
import argparse
import sys
from decimal import Decimal, InvalidOperation

PAGE_COLOUR = (0, 128, 128)      # teal: readable on the site's light and dark themes
HANDOUT_COLOUR = (20, 50, 140)   # the handouts' dark blue

# Width of a maths string in cm, measured from compiled handouts: about
# 0.17 cm a character and 0.27 cm for each spaced operator at \footnotesize.
FONT_SCALE = {r"\scriptsize": 0.875, r"\footnotesize": 1.0, r"\small": 1.1, r"\normalsize": 1.2}
HEADING_HALF_WIDTH = {r"\scriptsize": 0.67, r"\footnotesize": 0.76, r"\small": 0.84, r"\normalsize": 0.92}

CAPTION = "Each difference is the lower value minus the one above it."


def read_number(text):
    try:
        return Decimal(text)
    except InvalidOperation:
        sys.exit(f"finite_differences.py: {text!r} is not a number")


def decimal_places(values):
    places = 0
    for value in values:
        exponent = value.as_tuple().exponent
        if exponent < 0 and -exponent > places:
            places = -exponent
    return places


def written(value, places):
    return f"{value:.{places}f}"


def bracketed(value, places):
    if value < 0:
        return "(" + written(value, places) + ")"
    return written(value, places)


def subtraction(lower, upper, places):
    return written(lower, places) + " - " + bracketed(upper, places)


def text_width(text, font):
    scale = FONT_SCALE.get(font, 1.0)
    characters = 0
    for character in text:
        if character != " ":
            characters += 1
    operators = text.count(" - ") + text.count("= ")
    return scale * (0.17 * characters + 0.27 * operators)


def has_negative(values):
    """Zero is not negative, so a column of 0, -3, -4 has a negative value."""
    for value in values:
        if value < 0:
            return True
    return False


def mixes_whole_and_decimal(values):
    """True for a column such as 9, 10.5, 12 (written 9.0, 10.5, 12.0)."""
    whole = False
    decimal = False
    for value in values:
        if value == value.to_integral_value():
            whole = True
        else:
            decimal = True
    return whole and decimal


def right_aligned(values):
    """Any negative value, or whole numbers beside decimals, means each
    value is right-aligned in a box as wide as the column's widest value
    without its sign, the box centred, so the units digits and decimal
    points line up and a minus sign juts out to the left; any other column
    of numbers is centred."""
    return has_negative(values) or mixes_whole_and_decimal(values)


def widest_value(values, places, font):
    widest = 0.0
    for value in values:
        width_of_value = text_width(written(value, places), font)
        if width_of_value > widest:
            widest = width_of_value
    return widest


def widest_unsigned(values, places):
    """The widest value of a column written WITHOUT its sign - the width of
    the box its values are right-aligned in (TeX measures it exactly)."""
    widest = ""
    for value in values:
        text = written(abs(value), places)
        if len(text) > len(widest):
            widest = text
    return widest


def column_placement(values, places, left, width):
    """The x position of one column's values - always the column's middle -
    and, for a right-aligned column, the widest unsigned value its box is
    as wide as (None for a centred column)."""
    if not right_aligned(values):
        return None, left + width / 2
    return widest_unsigned(values, places), left + width / 2


def value_cell(box, text):
    """A value's node text: right-aligned in the box when there is one."""
    if box is None:
        return "$%s$" % text
    return r"\inbox{$%s$}{$%s$}" % (box, text)


def differences_of(values):
    result = []
    for index in range(len(values) - 1):
        result.append(values[index + 1] - values[index])
    return result


def scaffold(xs, ys, columns=2, mode="switch", colour=HANDOUT_COLOUR, worked_first=2,
             nothing_worked=False):
    """Return the tikzpicture as text. mode is 'switch', 'filled' or 'student'."""
    # Geometry, in cm: row height, heading height; the x and y columns share
    # one width, the widest value in either plus 0.25 cm each side
    row = 0.62
    heading = 0.75
    padding = 0.25
    gap = 0.07
    bulge = 0.32
    column_gap = 0.3
    inner = 0.18
    number_font = r"\small"
    subtraction_font = r"\footnotesize"
    heading_font = r"\scriptsize"

    count = len(xs)
    x_places = decimal_places(xs)
    y_places = decimal_places(ys)
    widest = max(widest_value(xs, x_places, number_font), widest_value(ys, y_places, number_font))
    x_width = round(max(0.85, widest + 2 * padding), 2)
    y_width = x_width
    first = differences_of(ys)
    second = differences_of(first)
    table_width = x_width + y_width

    def centre_of_row(index):
        return -heading - (index + 0.5) * row

    def rule_below_row(index):
        return -heading - (index + 1) * row

    bottom = -heading - count * row
    lines = []
    add = lines.append
    add(r"\begin{tikzpicture}[font=%s]" % number_font)
    add(r"\definecolor{diffcol}{RGB}{%d,%d,%d}" % colour)
    add(r"\definecolor{headfill}{RGB}{70,100,170}")
    add(r"\tikzset{num/.style={anchor=center, inner sep=0pt, text height=1.5ex, text depth=0pt},")
    add(r"  dif/.style={anchor=east, inner sep=0pt, text height=1.6ex, text depth=0.45ex, text=diffcol, font=%s}," % subtraction_font)
    add(r"  diffarrow/.style={diffcol, thin, -stealth}}")
    add("% The table of values: a shaded heading row, a full outer border, one ruled row for each x;")
    add("% the x and y columns are one width, and each value is centred in its row")
    add("% \\inbox{widest}{value}: the value right-aligned in a box as wide as the widest, the box centred")
    add(r"\def\inbox#1#2{\setbox0\hbox{#1}\hbox to\wd0{\hss#2}}")
    add(r"\fill[headfill, fill opacity=0.13] (0,0) rectangle (%.2f,%.2f);" % (table_width, -heading))
    add(r"\draw (0,0) rectangle (%.2f,%.3f);" % (table_width, bottom))
    add(r"\draw (%.2f,0) -- (%.2f,%.3f);" % (x_width, x_width, bottom))
    for index in range(count):
        add(r"\draw (0,%.3f) -- (%.2f,%.3f);" % (-heading - index * row, table_width, -heading - index * row))
    add(r"\node at (%.3f,%.3f) {$x$};" % (x_width / 2, -heading / 2))
    add(r"\node at (%.3f,%.3f) {$y$};" % (x_width + y_width / 2, -heading / 2))
    add("% A column with any negative value, or whole numbers beside decimals, is right-aligned in")
    add("% its box (\\inbox); any other column of numbers is centred")
    x_box, x_position = column_placement(xs, x_places, 0, x_width)
    y_box, y_position = column_placement(ys, y_places, x_width, y_width)
    for index in range(count):
        add(r"\node[num] at (%.3f,%.3f) {%s};" % (x_position, centre_of_row(index), value_cell(x_box, written(xs[index], x_places))))
    for index in range(count):
        y_cell = r"\node[num] at (%.3f,%.3f) {%s};" % (y_position, centre_of_row(index), value_cell(y_box, written(ys[index], y_places)))
        if not nothing_worked or mode == "filled":
            add(y_cell)
        elif mode == "switch":
            add(r"\qa{}{%s}" % y_cell.replace(r"\node[num]", r"\node[num, text=diffcol]"))

    sources = [ys, first]
    results = [first, second]
    names = ["First", "Second"]

    def arrow_y(column, index):
        if column == 0:
            return centre_of_row(index)
        return rule_below_row(index)

    def label_y(column, index):
        if column == 0:
            return rule_below_row(index)
        return centre_of_row(index + 1)

    def worked_on_student_copy(column, index):
        if nothing_worked:
            return False
        if column == 0:
            return index < worked_first
        return index == 0

    # The difference columns share one width: the widest subtraction and the
    # widest result in EITHER column, so their equals signs and their right
    # edges sit at the same offset in each
    widest_left = 0.0
    widest_right = 0.0
    for column in range(columns):
        for index in range(len(results[column])):
            left_text = subtraction(sources[column][index + 1], sources[column][index], y_places)
            right_text = "= " + written(results[column][index], y_places)
            if text_width(left_text, subtraction_font) > widest_left:
                widest_left = text_width(left_text, subtraction_font)
            if text_width(right_text, subtraction_font) > widest_right:
                widest_right = text_width(right_text, subtraction_font)

    starts = []
    equals_at = []
    right_edges = []
    left = table_width + gap
    for column in range(columns):
        starts.append(left)
        equals_at.append(left + bulge + inner + widest_left)
        right_edges.append(equals_at[-1] + widest_right)
        left = right_edges[-1] + column_gap

    # Headings centred over their columns, clear of the table and of each other
    half = HEADING_HALF_WIDTH.get(heading_font, 0.76)
    heading_x = []
    for column in range(columns):
        centre = (starts[column] + bulge + right_edges[column]) / 2
        if column == 0 and centre - half < table_width + 0.12:
            centre = table_width + 0.12 + half
        if column > 0 and centre - half < heading_x[column - 1] + half + 0.15:
            centre = heading_x[column - 1] + 2 * half + 0.15
        heading_x.append(centre)

    for column in range(columns):
        values = results[column]
        source = sources[column]
        add("%% %s differences: each arrow starts at the lower value and points up to the one above it;" % names[column])
        add("% beside it, the subtraction: lower value minus the one above it")
        add(r"\node[font=%s\sffamily\bfseries, align=center, anchor=south] at (%.3f,%.3f) {%s\\differences};"
            % (heading_font, heading_x[column], -heading + 0.05, names[column]))
        if column == 0:
            clearance = 0.05
        else:
            clearance = max(0.05, 0.12 * row)
        start = starts[column]
        for index in range(len(values)):
            lower = arrow_y(column, index + 1) + clearance
            upper = arrow_y(column, index) - clearance
            span = upper - lower
            add(r"\draw[diffarrow] (%.3f,%.3f) .. controls (%.3f,%.3f) and (%.3f,%.3f) .. (%.3f,%.3f);"
                % (start, lower, start + bulge * 1.3, lower + 0.05 * span,
                   start + bulge * 0.95, upper - 0.5 * span, start + 0.07, upper))
            line_y = label_y(column, index)
            filled = (r"\node[dif] at (%.3f,%.3f) {$%s$}; \node[dif, anchor=west] at (%.3f,%.3f) {${}= %s$};"
                      % (equals_at[column], line_y, subtraction(source[index + 1], source[index], y_places),
                         equals_at[column], line_y, written(values[index], y_places)))
            # A blank rule under the whole line, stopped short of the next column's arrows
            blank = (r"\draw[gray] (%.3f,%.3f) -- (%.3f,%.3f);"
                     % (start + bulge + inner, line_y - 0.12, right_edges[column], line_y - 0.12))
            if mode == "filled" or worked_on_student_copy(column, index):
                add(filled)
            elif mode == "student":
                add(blank)
            else:
                add(r"\qa{%s}{%s}" % (blank, filled))

    right_edge = right_edges[-1]
    caption_width = max(right_edge - 0.25, 3.9)
    add(r"\node[font=\scriptsize, text=gray, anchor=north, text width=%.2fcm, align=center] at (%.3f,%.3f) {%s};"
        % (caption_width, right_edge / 2, bottom - 0.1, CAPTION))
    add(r"\end{tikzpicture}")
    return "\n".join(lines)


def page_fence(alt, xs, ys, columns):
    picture = scaffold(xs, ys, columns=columns, mode="filled", colour=PAGE_COLOUR)
    return "```tikz\n% alt: " + alt + "\n\\begin{document}\n" + picture + "\n\\end{document}\n```"


def main():
    parser = argparse.ArgumentParser(description="Write the finite-difference scaffold as TikZ.")
    parser.add_argument("--x", nargs="+", required=True, help="the x values, top row first")
    parser.add_argument("--y", nargs="+", required=True, help="the y values, top row first")
    parser.add_argument("--columns", type=int, choices=[1, 2], default=2,
                        help="1 for first differences only, 2 for first and second")
    parser.add_argument("--mode", choices=["switch", "filled", "student"], default="switch")
    parser.add_argument("--nothing-worked", action="store_true",
                        help="the y values are what students compute: no y values or worked lines on the student copy")
    parser.add_argument("--page", action="store_true", help="a ```tikz fence for a page, every line filled")
    parser.add_argument("--alt", help="the sentence a screen reader says (required with --page)")
    arguments = parser.parse_args()

    xs = []
    for text in arguments.x:
        xs.append(read_number(text))
    ys = []
    for text in arguments.y:
        ys.append(read_number(text))
    if len(xs) != len(ys):
        sys.exit("finite_differences.py: give as many y values as x values")
    if len(xs) < arguments.columns + 2:
        sys.exit("finite_differences.py: give at least %d rows" % (arguments.columns + 2))

    if arguments.page:
        if not arguments.alt:
            sys.exit("finite_differences.py: --page needs --alt, the sentence a screen reader says")
        print(page_fence(arguments.alt, xs, ys, arguments.columns))
    else:
        print(scaffold(xs, ys, columns=arguments.columns, mode=arguments.mode,
                       nothing_worked=arguments.nothing_worked))


if __name__ == "__main__":
    main()
