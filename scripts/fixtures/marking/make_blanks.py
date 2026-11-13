#!/usr/bin/env python3
"""Rebuild the two blank tests the marking tests read (#750, 750a).

blank-quiz-letter.pdf and blank-quiz-legal.pdf are plantoir-handouts' starters/Quiz.tex as it ships,
compiled on letter and on legal paper, with one more page (a second question page) so a test can carry a
name written in the body of page 2. They hold no student data and no name: a blank test is what the
marking skill reads the name box from. Run from anywhere; needs tectonic. The tests never run this:
they read the committed PDFs, so they need no TeX.
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


def main():
    source = STARTER.read_text(encoding="utf-8")
    if source.count("\\end{questions}") != 1:
        sys.exit("the starter has changed shape: look at it and update this script")
    for paper in ("letter", "legal"):
        text = source.replace("\\end{questions}\n", SECOND_PAGE, 1)
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
    main()
