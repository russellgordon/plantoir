"""Plantoir Help: the page format, the checks and the three outputs.

Standard library only, Python 3.9 syntax (Xcode's /usr/bin/python3 is 3.9.6),
so the Xcode build phase, verify.sh and the Windows runtime's 3.14 all run the
same code. help/README.md explains the format for builders.
"""

from __future__ import annotations

# One constant for the language, so a second language is added rather than
# retrofitted: the Mac book's folder and every page's lang attribute.
LANGUAGE_FOLDER = "en.lproj"
LANGUAGE_TAG = "en-CA"

BOOK_TITLE = "Plantoir Help"
BOOK_IDENTIFIER = "ca.russellgordon.Plantoir.help"
CONTENTS_ANCHOR = "plantoir-help"
CS_INDEX_NAME = "Plantoir.cshelpindex"
LSM_INDEX_NAME = "Plantoir.helpindex"

# Fixed placeholder strings. They are not Help prose: the freshness check at a
# release refuses every stub and every placeholder picture, so neither ships.
STUB_SENTENCE = "This page is being written."
PLACEHOLDER_HEADING = "Picture to come"

# How old a dated fact may be before --check warns (the earlier plan
# review's number, not a ruling; F makes it a refusal at a release).
FACT_AGE_LIMIT_DAYS = 60
