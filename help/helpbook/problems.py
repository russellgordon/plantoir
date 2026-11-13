"""What the checks found: failures, which stop every build, and warnings,
which are printed and never fail the Xcode build (dates and unused registry
ids are release problems, not build problems)."""

from __future__ import annotations

from typing import List, Optional


class HelpError(Exception):
    """A refusal that stops one command, with a sentence for the builder."""


class Problems:
    """Collects findings with the file and line they belong to."""

    def __init__(self) -> None:
        self.failures: List[str] = []
        self.warnings: List[str] = []
        # For the page's reviewer to read, never a failure: the uses of
        # "publish" and "deploy" a pattern cannot judge (third review of P2a).
        self.review_notes: List[str] = []

    @staticmethod
    def _where(file: str, line: Optional[int]) -> str:
        if line is None:
            return file
        return file + ":" + str(line)

    def fail(self, file: str, line: Optional[int], message: str) -> None:
        # The Mac and web renderings check the same tokens: say each finding once.
        finding: str = self._where(file, line) + ": " + message
        if finding not in self.failures:
            self.failures.append(finding)

    def warn(self, file: str, line: Optional[int], message: str) -> None:
        finding: str = self._where(file, line) + ": " + message
        if finding not in self.warnings:
            self.warnings.append(finding)

    def note_for_review(self, file: str, line: Optional[int], message: str) -> None:
        finding: str = self._where(file, line) + ": " + message
        if finding not in self.review_notes:
            self.review_notes.append(finding)

    def has_failures(self) -> bool:
        return len(self.failures) > 0
