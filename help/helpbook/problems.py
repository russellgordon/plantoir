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

    @staticmethod
    def _where(file: str, line: Optional[int]) -> str:
        if line is None:
            return file
        return file + ":" + str(line)

    def fail(self, file: str, line: Optional[int], message: str) -> None:
        self.failures.append(self._where(file, line) + ": " + message)

    def warn(self, file: str, line: Optional[int], message: str) -> None:
        self.warnings.append(self._where(file, line) + ": " + message)

    def has_failures(self) -> bool:
        return len(self.failures) > 0
