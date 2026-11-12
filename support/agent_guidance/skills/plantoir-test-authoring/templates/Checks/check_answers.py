#!/usr/bin/env python3
"""
The checks for the worked example's test (Unit 2 Test: Chemical Reactions,
Versions A and B). A STARTING POINT: copy it into the test's own Checks/
folder and rewrite it for the test you are writing. Everything in it may be
changed freely: the facts, the calculations, the helpers, the wording. Keep
three things, because they are what make it a check:

- it works every value out again from what the PAPER gives (the numbers,
  the substances), never by reading the answer it is checking;
- it compares what it worked out with answers.json, and on any difference
  prints the version and the question and exits 1;
- it uses the standard library only, so it runs on any computer with
  Python (`python3 -B Checks/check_answers.py`, or `python` or `py` on
  Windows, from the test's folder).

Where an answer cannot be computed (an explanation, an essay), say so in
Coverage.md instead; the reviewer's re-solve is the check for those.
"""
import json
import math
import re
import sys
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent / "Marking Kit" / "answers.json"

# ---------- What each version's paper gives ----------
# The substances and numbers as they are printed on the paper. When a
# question changes, change it here first, then run this again.
PAPER = {
    "A": {
        "A1": {"metal": ("Ca", 2), "non_metal": ("Cl", -1),
               "options": {"a": "CaCl", "b": "CaCl2", "c": "Ca2Cl", "d": "CCl2"}},
        "A4": {"solutions": {"P": 2, "Q": 4},
               "options": {"a": "Q is more acidic than P, because its number is larger",
                           "b": "both solutions are basic",
                           "c": "P is more acidic than Q, and has 100 times the concentration of hydrogen ions",
                           "d": "P is more acidic than Q, and has 2 times the concentration of hydrogen ions"}},
        "B1": {"fuel": "C2H6"},
        "B2": {"heated": "CuCO3", "left": "CuO", "heated_mass": 8.40, "left_mass": 5.41},
        "D1": {"metal": "Zn", "compound": "CuSO4", "displaced": "Cu", "new_compound": "ZnSO4"},
        "given": [12.0, 2, 4, 8.40, 5.41],
    },
    "B": {
        "A1": {"metal": ("Mg", 2), "non_metal": ("Br", -1),
               "options": {"a": "MgBr", "b": "Mg2Br", "c": "MnBr2", "d": "MgBr2"}},
        "A4": {"solutions": {"R": 6, "S": 3},
               "options": {"a": "S is more acidic than R, and has 3 times the concentration of hydrogen ions",
                           "b": "S is more acidic than R, and has 1000 times the concentration of hydrogen ions",
                           "c": "R is more acidic than S, because its number is larger",
                           "d": "both solutions are basic"}},
        "B1": {"fuel": "C4H10"},
        "B2": {"heated": "CaCO3", "left": "CaO", "heated_mass": 6.20, "left_mass": 3.47},
        "D1": {"metal": "Mg", "compound": "FeSO4", "displaced": "Fe", "new_compound": "MgSO4"},
        "given": [18.5, 6, 3, 6.20, 3.47],
    },
}
ATOMIC_MASS = {"H": 1.008, "C": 12.01, "O": 16.00, "Ca": 40.08, "Cu": 63.55}


# ---------- Helpers ----------
def count_atoms(formula):
    """Atoms in a formula such as C2H6 or Al2(SO4)3."""
    counts = {}
    stack = [counts]
    for token in re.findall(r"[A-Z][a-z]?\d*|\(|\)\d*", formula):
        if token == "(":
            stack.append({})
        elif token.startswith(")"):
            group = stack.pop()
            times = int(token[1:] or "1")
            for element in group:
                stack[-1][element] = stack[-1].get(element, 0) + group[element] * times
        else:
            match = re.match(r"([A-Z][a-z]?)(\d*)", token)
            element = match.group(1)
            stack[-1][element] = stack[-1].get(element, 0) + int(match.group(2) or "1")
    return counts


def side_atoms(side):
    """Atoms on one side of an equation written as '2 C2H6 + 7 O2'."""
    totals = {}
    for term in side.split("+"):
        pieces = term.split()
        coefficient = 1
        if len(pieces) == 2:
            coefficient = int(pieces[0])
        formula = pieces[-1]
        atoms = count_atoms(formula)
        for element in atoms:
            totals[element] = totals.get(element, 0) + atoms[element] * coefficient
    return totals


def is_balanced(equation):
    left, right = equation.split("->")
    return side_atoms(left) == side_atoms(right)


def smallest_combustion(fuel):
    """The smallest whole numbers for fuel + O2 -> CO2 + H2O, by trying each."""
    atoms = count_atoms(fuel)
    for fuel_count in range(1, 21):
        carbon_dioxide = atoms["C"] * fuel_count
        water_twice = atoms["H"] * fuel_count
        if water_twice % 2 != 0:
            continue
        water = water_twice // 2
        oxygen_atoms = 2 * carbon_dioxide + water
        if oxygen_atoms % 2 != 0:
            continue
        return f"{fuel_count} {fuel} + {oxygen_atoms // 2} O2 -> {carbon_dioxide} CO2 + {water} H2O"
    return None


def molar_mass(formula):
    atoms = count_atoms(formula)
    total = 0.0
    for element in atoms:
        total += ATOMIC_MASS[element] * atoms[element]
    return total


def ionic_formula(metal, non_metal):
    symbol_m, charge_m = metal
    symbol_n, charge_n = non_metal
    divisor = math.gcd(charge_m, -charge_n)
    count_m = -charge_n // divisor
    count_n = charge_m // divisor
    return symbol_m + ("" if count_m == 1 else str(count_m)) + symbol_n + ("" if count_n == 1 else str(count_n))


def grams(text):
    return float(text.replace("g", "").strip())


# ---------- The checks ----------
def check_version(key, paper, answers, problems):
    def differs(question, worked_out, in_kit):
        problems.append(f"Version {key}, {question}: worked out {worked_out!r}, answers.json says {in_kit!r}")

    formula = ionic_formula(paper["A1"]["metal"], paper["A1"]["non_metal"])
    letter_of_formula = None
    for letter in paper["A1"]["options"]:
        if paper["A1"]["options"][letter] == formula:
            letter_of_formula = letter
    if letter_of_formula != answers["A1"]["answer"]:
        differs("A1", letter_of_formula, answers["A1"]["answer"])

    acid_test = paper["A4"]["solutions"]
    names = list(acid_test.keys())
    more_acidic = names[0] if acid_test[names[0]] < acid_test[names[1]] else names[1]
    less_acidic = names[1] if more_acidic == names[0] else names[0]
    factor = 10 ** abs(acid_test[names[0]] - acid_test[names[1]])
    wanted = f"{more_acidic} is more acidic than {less_acidic}, and has {factor} times"
    letter_of_factor = None
    for letter in paper["A4"]["options"]:
        if paper["A4"]["options"][letter].startswith(wanted):
            letter_of_factor = letter
    if letter_of_factor != answers["A4"]["answer"]:
        differs("A4", letter_of_factor, answers["A4"]["answer"])

    combustion = smallest_combustion(paper["B1"]["fuel"])
    if combustion != answers["B1.4"]["answer"]:
        differs("B1.4", combustion, answers["B1.4"]["answer"])

    heated = paper["B2"]
    expected_left = heated["heated_mass"] * molar_mass(heated["left"]) / molar_mass(heated["heated"])
    if round(expected_left, 2) != heated["left_mass"]:
        problems.append(f"Version {key}, B2: the paper's {heated['left_mass']} g of {heated['left']} is not what "
                        f"{heated['heated_mass']} g of {heated['heated']} leaves ({expected_left:.3f} g)")
    escaped = round(heated["heated_mass"] - heated["left_mass"], 2)
    if escaped != grams(answers["B2.1"]["answer"]):
        differs("B2.1", f"{escaped:.2f} g", answers["B2.1"]["answer"])

    reaction = paper["D1"]
    equation = f"{reaction['metal']} + {reaction['compound']} -> {reaction['new_compound']} + {reaction['displaced']}"
    if not is_balanced(equation):
        problems.append(f"Version {key}, D1: {equation} does not balance as written")
    if equation != answers["D1.3"]["answer"]:
        differs("D1.3", equation, answers["D1.3"]["answer"])
    products = f"{reaction['new_compound']} and {reaction['displaced']}"
    if products != answers["D1.2"]["answer"]:
        differs("D1.2", products, answers["D1.2"]["answer"])


def check_across_versions(kit, problems):
    """Right answers under different letters, item by item, wherever a
    question has options (misconceptions)."""
    keys = list(kit["versions"].keys())
    for point in kit["points"]:
        point_id = point["id"]
        letters = []
        for key in keys:
            answer = kit["versions"][key]["answers"][point_id]
            if answer.get("misconceptions"):
                letters.append(answer["answer"])
        if len(letters) > 1 and len(set(letters)) < len(letters):
            problems.append(f"{point_id}: two versions have the right answer under the same letter")


def check_no_given_number_is_reused(problems):
    """A number one version gives never appears among another's."""
    keys = list(PAPER.keys())
    for first in keys:
        for second in keys:
            if first >= second:
                continue
            for number in PAPER[first]["given"]:
                if number in PAPER[second]["given"]:
                    problems.append(f"Versions {first} and {second} both give {number}")


def check_every_wrong_option_is_named(kit, problems):
    for key in kit["versions"]:
        answers = kit["versions"][key]["answers"]
        for point_id in answers:
            misconceptions = answers[point_id].get("misconceptions")
            if not misconceptions:
                continue
            if answers[point_id]["answer"] in misconceptions:
                problems.append(f"Version {key}, {point_id}: the right answer is listed as a misconception")
            for letter in ["a", "b", "c", "d"]:
                if letter != answers[point_id]["answer"] and letter not in misconceptions:
                    problems.append(f"Version {key}, {point_id}: option {letter} has no misconception named")


def main():
    kit = json.loads(KIT.read_text(encoding="utf-8"))
    problems = []
    for key in PAPER:
        check_version(key, PAPER[key], kit["versions"][key]["answers"], problems)
    check_across_versions(kit, problems)
    check_no_given_number_is_reused(problems)
    check_every_wrong_option_is_named(kit, problems)
    if problems:
        for line in problems:
            print(line)
        return 1
    print(f"OK: every computed answer in versions {', '.join(PAPER)} matches answers.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
