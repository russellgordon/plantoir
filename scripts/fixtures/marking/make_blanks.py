#!/usr/bin/env python3
"""Rebuild the two blank tests the marking tests read (#750, 750a).

blank-quiz-letter.pdf and blank-quiz-legal.pdf are plantoir-handouts' starters/Quiz.tex as it ships,
compiled on letter and on legal paper, with one more page (a second question page) so a test can carry a
name written in the body of page 2. They hold no student data and no name: a blank test is what the
marking skill reads the name box from. Run from anywhere; needs tectonic. The tests never run this:
they read the committed PDFs, so they need no TeX. blank-quiz-letter-name-on-page-1.pdf is the letter one
with the Name blank on page 1 only, for a page whose blank has no name box.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
STARTER = HERE.parents[2] / "support" / "agent_guidance" / "skills" / "plantoir-handouts" / "starters" / "Quiz.tex"
SECOND_PAGE = (
    "\\clearpage\n"
    "\\q{4}\\score{A 2} Two dice are rolled. How many outcomes are there? Explain how you counted them.\n"
    "\\onlyq{\\vspace{10\\baselineskip}}\n"
    "\\end{questions}\n"
)


STYLES = r"""\documentclass[11pt]{article}
\usepackage[letterpaper,margin=0.75in,top=0.6in]{geometry}
\usepackage[T1]{fontenc}\usepackage{lmodern}\usepackage{array}
\setlength{\parindent}{0pt}\usepackage{fancyhdr}\pagestyle{fancy}\fancyhf{}\renewcommand{\headrulewidth}{0pt}
\fancyfoot[L]{A Test About Dice $\cdot$ COURSE}\fancyfoot[R]{Page \thepage\ of 6}\setlength{\footskip}{0.4in}
\newcommand{\question}[1]{{\Large\bfseries A Test About Dice}\par\bigskip #1\par\vfill\hfill Turn over\clearpage}
\begin{document}
Dice Academy\hspace{1.2in}Name \rule[-0.1em]{2.2in}{0.4pt}\hfill Date \rule[-0.1em]{0.8in}{0.4pt}\par\bigskip
\question{1. Roll two dice. How many outcomes are there?}
Dice Academy\hspace{1.2in}Name: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\hfill Date\par\bigskip
\question{2. What is the chance of a double six?}
Dice Academy\hspace{1.2in}Name: \makebox[2.2in]{\dotfill}\hfill Date\par\bigskip
\question{3. What is the chance of a total of seven?}
Dice Academy\hspace{1.2in}\begin{tabular}[b]{|l|p{2.2in}|}\hline Name & \\ \hline\end{tabular}\hfill Date\par\bigskip
\question{4. Which total is most likely?}
Dice Academy\hspace{1.2in}Name: \framebox[2.2in]{\strut}\hfill Date\par\bigskip
\question{5. Explain your answer to question 4.}
Name: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\hfill Dice Academy\par\bigskip
{\Large\bfseries A Test About Dice}\par\bigskip 6. Draw the table of outcomes.\par\vfill\hfill End
\end{document}
"""


LABELS = r"""\documentclass[11pt]{article}
\usepackage[letterpaper,margin=0.75in,top=0.6in]{geometry}
\usepackage[T1]{fontenc}\usepackage{lmodern}
\setlength{\parindent}{0pt}\usepackage{fancyhdr}\pagestyle{fancy}\fancyhf{}\renewcommand{\headrulewidth}{0pt}
\fancyfoot[L]{A Test About Dice $\cdot$ COURSE}\fancyfoot[R]{Page \thepage\ of 5}\setlength{\footskip}{0.4in}
\newcommand{\question}[1]{{\Large\bfseries A Test About Dice}\par\bigskip #1\par\vfill\hfill Turn over\clearpage}
\begin{document}
Dice Academy\hspace{1.2in}Student Name: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\hfill Date\par\bigskip
\question{1. Roll two dice. How many outcomes are there?}
Dice Academy\hspace{1.2in}Name: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\hfill Date\par\smallskip
Name and date go on every page.\par\bigskip
\question{2. What is the chance of a double six?}
Dice Academy\hspace{1.2in}Name \rule[-0.1em]{2.2in}{0.4pt}\hfill Date\par\smallskip
Partner Name: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\par\bigskip
\question{3. What is the chance of a total of seven?}
Dice Academy\hspace{1.2in}{\sffamily\bfseries NAME} \rule[-0.1em]{2.2in}{0.4pt}\hfill Date\par\bigskip
\question{4. Which total is most likely?}
Dice Academy\hfill Date \rule[-0.1em]{1in}{0.4pt}\par\bigskip
{\Large\bfseries A Test About Dice}\par\bigskip 5. Draw the table of outcomes.\par\vfill\hfill End
\end{document}
"""

TWO_BLANKS = r"""\documentclass[11pt]{article}
\usepackage[letterpaper,margin=0.75in,top=0.6in]{geometry}
\usepackage[T1]{fontenc}\usepackage{lmodern}\setlength{\parindent}{0pt}\pagestyle{empty}
\begin{document}
Dice Academy\hspace{1.2in}Name \rule[-0.1em]{2.2in}{0.4pt}\par\vspace{0.5in}
{\Large\bfseries A Test About Dice}\par\bigskip
Name \rule[-0.1em]{2.2in}{0.4pt}\par\bigskip
1. Roll two dice. How many outcomes are there?\par
\end{document}
"""


def compile_to(source, name):
    with tempfile.TemporaryDirectory() as folder:
        tex = Path(folder) / "blank.tex"
        tex.write_text(source, encoding="utf-8")
        result = subprocess.run(["tectonic", "-c", "minimal", str(tex)], capture_output=True, cwd=folder)
        if result.returncode != 0:
            sys.exit(f"{name} did not compile")
        shutil.copyfile(Path(folder) / "blank.pdf", HERE / name)
    print(f"{name} written")


IN_A_CELL = r"""\documentclass[11pt]{article}\usepackage[letterpaper,margin=0.75in,bottom=0.9in]{geometry}\usepackage[T1]{fontenc}\usepackage{lmodern}\usepackage{xcolor}\usepackage{fancyhdr}\setlength{\parindent}{0pt}\pagestyle{fancy}\fancyhf{}\renewcommand{\headrulewidth}{0pt}\fancyfoot[L]{\small\sffamily\color{gray}Dice Quiz $\cdot$ COURSE}\fancyfoot[R]{\small\sffamily\color{gray}Page \thepage}
\begin{document}
\begin{tabular}{|p{3in}|p{1.5in}|}\hline \footnotesize Name & \footnotesize Date\\[0.35in]\hline\end{tabular}\par\bigskip {\LARGE\bfseries\sffamily Dice Quiz}\par\medskip{\color{gray}Answer every question. Show your work.}\par\bigskip 1. Two dice are rolled. How many outcomes?\par\vfill 2. What is the chance of a double?\par\vfill
\end{document}
"""


def make_labels():
    """blank-label-cases.pdf (five pages: Student Name; Name with an instruction line that starts with Name;
    Name with a Partner Name line under it; NAME in bold sans; no name blank at all) and
    blank-two-name-blanks.pdf (a page with two name blanks, which the script must not guess between)."""
    compile_to(LABELS, "blank-label-cases.pdf")
    compile_to(TWO_BLANKS, "blank-two-name-blanks.pdf")
    # A form cell with a small Name in its corner and the room to write UNDER it (750a fix review 3, M6).
    compile_to(IN_A_CELL, "blank-name-in-a-cell.pdf")


def make_styles():
    """blank-name-styles.pdf: six pages, each with its Name blank drawn another way (a rule, underscores,
    dots, a table cell, a frame, and underscores at the left margin): every one is a name blank to box
    (750a fix review H1 and M4)."""
    with tempfile.TemporaryDirectory() as folder:
        tex = Path(folder) / "styles.tex"
        tex.write_text(STYLES, encoding="utf-8")
        result = subprocess.run(["tectonic", "-c", "minimal", str(tex)], capture_output=True, cwd=folder)
        if result.returncode != 0:
            sys.exit("the styles blank did not compile")
        shutil.copyfile(Path(folder) / "styles.pdf", HERE / "blank-name-styles.pdf")
    print("blank-name-styles.pdf written")


def main():
    source = STARTER.read_text(encoding="utf-8")
    if source.count("\\end{questions}") != 1:
        sys.exit("the starter has changed shape: look at it and update this script")
    for paper in ("letter", "legal", "letter-name-on-page-1"):
        second = SECOND_PAGE
        if paper == "letter-name-on-page-1":
            # A test whose Name blank is on page 1 only: page 2 keeps the school's name and the footer.
            second = SECOND_PAGE.replace("\\clearpage\n", "\\clearpage\n\\thispagestyle{later}\n", 1)
        text = source.replace("\\end{questions}\n", second, 1)
        if paper == "letter-name-on-page-1":
            text = text.replace("\\begin{document}", "\\fancypagestyle{later}{\\fancyhead[R]{}}\n\\begin{document}", 1)
        if paper == "legal":
            text = text.replace("letterpaper", "legalpaper", 1)
        with tempfile.TemporaryDirectory() as folder:
            tex = Path(folder) / "blank.tex"
            tex.write_text(text, encoding="utf-8")
            result = subprocess.run(["tectonic", "-c", "minimal", str(tex)], capture_output=True, cwd=folder)
            if result.returncode != 0:
                sys.exit(f"the {paper} blank did not compile")
            shutil.copyfile(Path(folder) / "blank.pdf", HERE / f"blank-quiz-{paper}.pdf")
        print(f"blank-quiz-{paper}.pdf written")


if __name__ == "__main__":
    if sys.argv[1:] == ["--styles"]:
        make_styles()
    elif sys.argv[1:] == ["--labels"]:
        make_labels()
    else:
        main()
        make_styles()
        make_labels()
