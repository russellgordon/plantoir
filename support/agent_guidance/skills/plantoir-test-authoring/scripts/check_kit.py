#!/usr/bin/env python3
"""
Check a marking kit's answers.json against the kit format
(templates/Marking Kit/FORMAT.md beside this skill), and optionally a marks
record, each version's paper and the Marking Guide against the kit.

Run it from the working folder, never import it, and do not copy or change
it: this is the one script in the skill that is NOT a starting point. A kit
that passes here is in the format the plantoir-marking skill reads. Change
the kit, the paper or the guide, never this file.

    python3 -B .claude/skills/plantoir-test-authoring/scripts/check_kit.py "<test>/Marking Kit/answers.json"
        --marks "<test>/Marking Kit/marks-template.json"
        --paper A "<test>/Version A.tex" --paper B "<test>/Version B.tex"
        --guide "<test>/Marking Guide.tex"

Every option is optional and may be left out. (On Windows, `python` or `py`
in place of `python3`; `.agents` works as well as `.claude`.) It prints one
line per problem, each ending in the rule it breaks in square brackets, and
exits 1; or one OK line with the counts by category, and exits 0. It prints
IDs, keys and counts only, never what a marks record says.

The paper is read the way the plantoir-handouts Quiz.tex starter writes it:
each question's `\\score{T 4}` and the slash totals on the front
(`T \\rule[...]{...}{...}\\,/\\,6`). The Marking Guide is read from its
`\\catrow{K}{4}{...}` rows and `\\totalrow{16}`. A paper laid out another
way is reported as unreadable rather than passed.
Standard library only.
"""
import json
import re
import sys

KIT_VERSION = 1
EARNED_VALUES = [0, 0.5, 1]

# ---------- Keys that look like they hold a person ----------
# A key is split into its words (camelCase, snake_case, kebab-case, spaces)
# and also read run together, whatever its case. These words, alone or as
# part of a word, are refused ...
PERSON_WORDS = ["name", "student", "pupil", "learner", "email", "mail", "username",
                "surname", "nickname", "handle", "login"]
# ... these only as the whole key, since "first" and "last" are ordinary
# words in a topic but a person's name when a key is nothing else ...
PERSON_WHOLE_KEYS = ["first", "last", "full", "given", "family", "middle"]
# ... and these are the keys the format itself defines that would otherwise
# match: a sentence written TO the student about a lost mark.
DEFINED_EXCEPTIONS = ["studentNote"]

# ---------- The keys the format defines, per place ----------
KIT_KEYS = ["kit", "test", "course", "categories", "parts", "questions", "points",
            "versions", "strengths", "topics"]
CATEGORY_KEYS = ["key", "title"]
PART_KEYS = ["key", "title", "category"]
QUESTION_KEYS = ["id", "part", "skill", "topics"]
POINT_KEYS = ["id", "question", "category", "meaning", "followThrough"]
VERSION_KEYS = ["source", "solutions", "answers"]
ANSWER_KEYS = ["answer", "accept", "misconceptions"]
STRENGTH_KEYS = ["sentence", "halves"]
HALF_KEYS = ["points", "sentence"]
TOPIC_KEYS = ["when", "pages"]
PAGE_KEYS = ["title", "path", "anchor"]
MARKS_KEYS = ["kit", "identifier", "section", "version", "points", "voided", "checks",
              "summary", "byQuestion", "strengths", "focus", "closing", "feedback"]
MARKS_POINT_KEYS = ["earned", "seen", "note", "studentNote"]
VOIDED_KEYS = ["reason", "intended"]
# The marks record's byQuestion, focus and strengths are what a feedback
# sheet says; plantoir-marking defines what is inside them, so only the
# person check applies there.
MARKS_EXTENSION_PLACES = ["byQuestion", "focus", "strengths"]


def key_words(key):
    return [word.lower() for word in re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+", key)]


def looks_like_a_person(key):
    if key in DEFINED_EXCEPTIONS:
        return False
    run_together = re.sub(r"[^a-z]", "", key.lower())
    for word in PERSON_WORDS:
        if word in run_together:
            return True
        if word in key_words(key):
            return True
    return run_together in PERSON_WHOLE_KEYS


def check_keys(value, allowed, where, problems):
    """The keys of one object: none that looks like a person, none the
    format does not define. Keys that start with an underscore are notes."""
    if not isinstance(value, dict):
        return
    for key in value:
        if looks_like_a_person(key):
            problems.append(f"{where} has a key called {key}; the kit and the marks records never hold a name [forbidden-key]")
        elif not key.startswith("_") and key not in allowed:
            problems.append(f"{where} has a key called {key}, which the format does not define [unknown-key]")


def check_person_keys_anywhere(value, where, problems):
    """Inside a place another skill defines: only the person check."""
    if isinstance(value, dict):
        for key in value:
            if looks_like_a_person(key):
                problems.append(f"{where} has a key called {key}; the kit and the marks records never hold a name [forbidden-key]")
            check_person_keys_anywhere(value[key], f"{where} -> {key}", problems)
    elif isinstance(value, list):
        for item in value:
            check_person_keys_anywhere(item, where, problems)


def load(path, problems):
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError, RecursionError) as error:
        problems.append(f"{path} could not be read as JSON ({type(error).__name__}) [json]")
        return None
    if not isinstance(data, dict):
        problems.append(f"{path} is not a JSON object [json]")
        return None
    return data


def is_text(value):
    return isinstance(value, str) and value.strip() != ""


def list_of_objects(kit, key, problems, required=True):
    value = kit.get(key)
    if value is None and not required:
        return []
    if not isinstance(value, list) or (required and len(value) == 0):
        problems.append(f"{key} must be a list with at least one entry [required]")
        return []
    objects = []
    for item in value:
        if isinstance(item, dict):
            objects.append(item)
        else:
            problems.append(f"every entry in {key} must be an object [required]")
    return objects


def collect_ids(entries, field, label, problems):
    ids = []
    for entry in entries:
        value = entry.get(field)
        if not is_text(value):
            problems.append(f"an entry in {label} has no {field} [required]")
            continue
        if value in ids:
            problems.append(f"{label} has {value} twice [unique]")
            continue
        ids.append(value)
    return ids


def check_kit(kit, problems):
    """Returns the point IDs, the version keys and the kit's counts."""
    check_keys(kit, KIT_KEYS, "answers.json", problems)
    if type(kit.get("kit")) is not int or kit.get("kit") != KIT_VERSION:
        problems.append(f"kit must be {KIT_VERSION} [kit-version]")
    for key in ["test", "course"]:
        if not is_text(kit.get(key)):
            problems.append(f"{key} must be text [required]")

    categories = list_of_objects(kit, "categories", problems)
    parts = list_of_objects(kit, "parts", problems)
    questions = list_of_objects(kit, "questions", problems)
    points = list_of_objects(kit, "points", problems)
    for category in categories:
        check_keys(category, CATEGORY_KEYS, "a category", problems)
    for part in parts:
        check_keys(part, PART_KEYS, "a part", problems)
    for question in questions:
        check_keys(question, QUESTION_KEYS, "a question", problems)
    for point in points:
        check_keys(point, POINT_KEYS, "a point", problems)
    category_keys = collect_ids(categories, "key", "categories", problems)
    part_keys = collect_ids(parts, "key", "parts", problems)
    question_ids = collect_ids(questions, "id", "questions", problems)
    point_ids = collect_ids(points, "id", "points", problems)

    for category in categories:
        if not is_text(category.get("title")):
            problems.append(f"category {category.get('key')} has no title [required]")
    category_of_part = {}
    for part in parts:
        if not is_text(part.get("title")):
            problems.append(f"part {part.get('key')} has no title [required]")
        if "category" in part:
            if part["category"] not in category_keys:
                problems.append(f"part {part.get('key')} names a category that is not in categories [part-category]")
            else:
                category_of_part[part.get("key")] = part["category"]

    topics = kit.get("topics", {})
    if not isinstance(topics, dict):
        problems.append("topics must be an object [topic]")
        topics = {}
    for topic_key in topics:
        if topic_key.startswith("_"):
            continue
        if looks_like_a_person(topic_key):
            problems.append(f"topics has a key called {topic_key}; the kit never holds a name [forbidden-key]")
        topic = topics[topic_key]
        check_keys(topic, TOPIC_KEYS, f"topic {topic_key}", problems)
        pages = topic.get("pages") if isinstance(topic, dict) else None
        if not isinstance(pages, list) or len(pages) == 0:
            problems.append(f"topic {topic_key} has no pages [topic]")
            continue
        for page in pages:
            check_keys(page, PAGE_KEYS, f"a page of topic {topic_key}", problems)
            if not isinstance(page, dict) or not is_text(page.get("title")) or not is_text(page.get("path")):
                problems.append(f"a page of topic {topic_key} needs a title and a path [topic]")

    part_of_question = {}
    for question in questions:
        if question.get("part") not in part_keys:
            problems.append(f"question {question.get('id')} names a part that is not in parts [question-part]")
        part_of_question[question.get("id")] = question.get("part")
        if not is_text(question.get("skill")):
            problems.append(f"question {question.get('id')} has no skill [required]")
        question_topics = question.get("topics", [])
        if not isinstance(question_topics, list):
            problems.append(f"question {question.get('id')}: topics must be a list [topic]")
            question_topics = []
        for topic_key in question_topics:
            if not isinstance(topic_key, str) or topic_key not in topics:
                problems.append(f"question {question.get('id')} names a topic that is not in topics [topic]")

    earlier_points = []
    question_of_point = {}
    for point in points:
        point_id = point.get("id")
        if point.get("question") not in question_ids:
            problems.append(f"point {point_id} names a question that is not in questions [point-question]")
        if point.get("category") not in category_keys:
            problems.append(f"point {point_id} names a category that is not in categories [point-category]")
        part_key = part_of_question.get(point.get("question"))
        if part_key in category_of_part and point.get("category") != category_of_part[part_key]:
            problems.append(f"point {point_id} is in another category than its part {part_key} [part-category]")
        if not is_text(point.get("meaning")):
            problems.append(f"point {point_id} has no meaning [required]")
        follow = point.get("followThrough", [])
        if not isinstance(follow, list):
            problems.append(f"point {point_id}: followThrough must be a list of point IDs [follow-through]")
            follow = []
        for earlier in follow:
            same_question = question_of_point.get(earlier) == point.get("question")
            if earlier not in earlier_points or not same_question:
                problems.append(f"point {point_id} follows through from {earlier}, which is not an earlier point of the same question [follow-through]")
        if is_text(point_id):
            earlier_points.append(point_id)
            question_of_point[point_id] = point.get("question")

    for question_id in question_ids:
        has_point = False
        for point in points:
            if point.get("question") == question_id:
                has_point = True
        if not has_point:
            problems.append(f"question {question_id} has no points [question-without-points]")

    versions = kit.get("versions")
    if not isinstance(versions, dict) or len(versions) == 0:
        problems.append("versions must be an object with at least one version [required]")
        versions = {}
    for version_key in versions:
        if looks_like_a_person(version_key):
            problems.append(f"versions has a key called {version_key}; the kit never holds a name [forbidden-key]")
        version = versions[version_key]
        if not isinstance(version, dict):
            problems.append(f"version {version_key} must be an object [required]")
            continue
        check_keys(version, VERSION_KEYS, f"version {version_key}", problems)
        if not is_text(version.get("source")):
            problems.append(f"version {version_key} has no source [version-source]")
        if "solutions" in version and not is_text(version.get("solutions")):
            problems.append(f"version {version_key}: solutions must be a file name [version-source]")
        answers = version.get("answers")
        if not isinstance(answers, dict):
            problems.append(f"version {version_key} has no answers [every-point-answered]")
            continue
        for point_id in point_ids:
            if point_id not in answers:
                problems.append(f"version {version_key} does not answer point {point_id} [every-point-answered]")
                continue
            entry = answers[point_id]
            if not isinstance(entry, dict) or not is_text(entry.get("answer")):
                problems.append(f"version {version_key}, point {point_id}: answer must be text [every-point-answered]")
                continue
            check_keys(entry, ANSWER_KEYS, f"version {version_key}, point {point_id}", problems)
            if not isinstance(entry.get("accept", []), list):
                problems.append(f"version {version_key}, point {point_id}: accept must be a list [every-point-answered]")
            misconceptions = entry.get("misconceptions", {})
            if not isinstance(misconceptions, dict):
                problems.append(f"version {version_key}, point {point_id}: misconceptions must be an object [every-point-answered]")
            elif entry["answer"] in misconceptions:
                problems.append(f"version {version_key}, point {point_id}: the right answer is listed as a misconception [misconception]")
        for answered in answers:
            if answered not in point_ids:
                problems.append(f"version {version_key} answers {answered}, which is not in points [unknown-point]")

    strengths = kit.get("strengths", [])
    if not isinstance(strengths, list):
        problems.append("strengths must be a list [strengths]")
        strengths = []
    index = 0
    for strength in strengths:
        index += 1
        if not isinstance(strength, dict) or not is_text(strength.get("sentence")):
            problems.append(f"strength {index} needs a sentence [strengths]")
            continue
        check_keys(strength, STRENGTH_KEYS, f"strength {index}", problems)
        halves = strength.get("halves")
        if not isinstance(halves, list) or len(halves) == 0:
            problems.append(f"strength {index} has no halves [strengths]")
            continue
        for half in halves:
            check_keys(half, HALF_KEYS, f"a half of strength {index}", problems)
            half_points = half.get("points") if isinstance(half, dict) else None
            if not isinstance(half_points, list) or len(half_points) == 0:
                problems.append(f"a half of strength {index} has no points [strengths]")
                continue
            half_sentence = half.get("sentence")
            if half_sentence is not None and not is_text(half_sentence):
                problems.append(f"a half of strength {index}: sentence must be text or null [strengths]")
            for point_id in half_points:
                if point_id not in point_ids:
                    problems.append(f"strength {index} names point {point_id}, which is not in points [strengths]")

    counts = {}
    for key in category_keys:
        counts[key] = 0
    per_question = []
    for question_id in question_ids:
        question_counts = {}
        for point in points:
            if point.get("question") == question_id and point.get("category") in counts:
                category = point["category"]
                question_counts[category] = question_counts.get(category, 0) + 1
                counts[category] += 1
        per_question.append((question_id, question_counts))
    return point_ids, list(versions.keys()), counts, per_question, part_keys


def check_marks(marks, point_ids, version_keys, part_keys, problems):
    check_keys(marks, MARKS_KEYS, "the marks record", problems)
    for place in MARKS_EXTENSION_PLACES:
        check_person_keys_anywhere(marks.get(place), f"the marks record's {place}", problems)
    if type(marks.get("kit")) is not int or marks.get("kit") != KIT_VERSION:
        problems.append(f"the marks record: kit must be {KIT_VERSION} [marks-kit]")
    identifier = marks.get("identifier")
    if identifier is not None and not is_text(identifier):
        problems.append("the marks record: identifier must be text or null [marks-identifier]")
    version = marks.get("version")
    if version is not None and version not in version_keys:
        problems.append("the marks record names a version the kit does not have [marks-version]")
    feedback = marks.get("feedback", {})
    if isinstance(feedback, dict):
        for key in feedback:
            if key not in part_keys:
                problems.append(f"the marks record's feedback has a key {key}, which is not a part [unknown-key]")
    voided = marks.get("voided", {})
    if isinstance(voided, dict):
        for point_id in voided:
            if point_id not in point_ids:
                problems.append(f"the marks record voids {point_id}, which is not in the kit [marks-points]")
            check_keys(voided[point_id], VOIDED_KEYS, f"the marks record's voided {point_id}", problems)
    points = marks.get("points")
    if not isinstance(points, dict):
        problems.append("the marks record has no points [marks-points]")
        return
    for point_id in point_ids:
        if point_id not in points:
            problems.append(f"the marks record does not have point {point_id} [marks-points]")
    for point_id in points:
        if point_id not in point_ids:
            problems.append(f"the marks record has a point the kit does not have [marks-points]")
            continue
        entry = points[point_id]
        if not isinstance(entry, dict) or "earned" not in entry:
            problems.append(f"the marks record: point {point_id} has no earned [marks-earned]")
            continue
        check_keys(entry, MARKS_POINT_KEYS, f"the marks record's point {point_id}", problems)
        earned = entry["earned"]
        allowed = earned is None
        if not isinstance(earned, bool) and isinstance(earned, (int, float)):
            for value in EARNED_VALUES:
                if earned == value:
                    allowed = True
        if not allowed:
            problems.append(f"the marks record: point {point_id} earned must be null, 0, 0.5 or 1 [marks-earned]")


# ---------- The paper and the guide ----------
def read_tex(path, problems, rule):
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except (OSError, ValueError) as error:
        problems.append(f"{path} could not be read ({type(error).__name__}) [{rule}]")
        return None
    text = re.sub(r"(?<!\\)%.*", "", text)
    start = text.find("\\begin{document}")
    return text[start:] if start >= 0 else text


def describe(counts):
    parts = []
    for key in counts:
        parts.append(f"{key} {counts[key]}")
    return ", ".join(parts)


def as_counts(pairs):
    counts = {}
    for key, number in pairs:
        value = float(number)
        counts[key] = counts.get(key, 0) + (int(value) if value.is_integer() else value)
    return counts


def without_zeros(counts):
    kept = {}
    for key in counts:
        if counts[key] != 0:
            kept[key] = counts[key]
    return kept


def check_paper(version_key, path, version_keys, counts, per_question, problems):
    if version_key not in version_keys:
        problems.append(f"--paper names version {version_key}, which the kit does not have [paper-marks]")
        return
    text = read_tex(path, problems, "paper-marks")
    if text is None:
        return
    scores = re.findall(r"\\score\{([^}]*)\}", text)
    if not scores:
        problems.append(f"Version {version_key}: found no \\score{{...}} on the paper, so its marks could not be compared [paper-marks]")
    else:
        each = []
        everything = []
        for score in scores:
            pairs = re.findall(r"([A-Za-z]+)\s*(\d+(?:\.\d+)?)", score)
            each.append(as_counts(pairs))
            everything.extend(pairs)
        if as_counts(everything) != without_zeros(counts):
            problems.append(f"Version {version_key}: the marks column adds up to {describe(as_counts(everything))}, the kit has {describe(counts)} [paper-marks]")
        if len(each) == len(per_question):
            index = 0
            for question_id, question_counts in per_question:
                if each[index] != question_counts:
                    problems.append(f"Version {version_key}: question {question_id} is marked {describe(each[index])} on the paper and has {describe(question_counts)} in the kit [paper-marks]")
                index += 1
    totals = re.findall(r"([A-Za-z]+)\s*\\rule(?:\[[^\]]*\])?\{[^}]*\}\{[^}]*\}\s*\\,\s*/\s*\\,\s*(\d+(?:\.\d+)?)", text)
    if not totals:
        problems.append(f"Version {version_key}: found no slash totals on the front, so they could not be compared [paper-totals]")
    elif as_counts(totals) != without_zeros(counts):
        problems.append(f"Version {version_key}: the totals on the front read {describe(as_counts(totals))}, the kit has {describe(counts)} [paper-totals]")


def check_guide(path, point_ids, counts, problems):
    text = read_tex(path, problems, "guide-totals")
    if text is None:
        return
    rows = re.findall(r"\\catrow\{([^}]*)\}\{([^}]*)\}", text)
    if not rows:
        problems.append("the Marking Guide has no \\catrow{...}{...} rows, so its totals could not be compared [guide-totals]")
    elif without_zeros(as_counts(rows)) != without_zeros(counts):
        problems.append(f"the Marking Guide's category table reads {describe(as_counts(rows))}, the kit has {describe(counts)} [guide-totals]")
    total = re.findall(r"\\totalrow\{([^}]*)\}", text)
    whole = 0
    for key in counts:
        whole += counts[key]
    if len(total) != 1 or total[0].strip() != str(whole):
        problems.append(f"the Marking Guide's total is not {whole} [guide-totals]")
    named = re.findall(r"\\pid\{([^}]*)\}", text)
    for point_id in point_ids:
        if point_id not in named:
            problems.append(f"the Marking Guide has no row for point {point_id} [guide-points]")


def read_arguments(arguments):
    """answers.json first, then any of --marks FILE, --paper KEY FILE (again
    for each version) and --guide FILE. None when they cannot be read."""
    if not arguments or arguments[0].startswith("--"):
        return None
    options = {"kit": arguments[0], "marks": None, "papers": [], "guide": None}
    index = 1
    while index < len(arguments):
        flag = arguments[index]
        if flag == "--marks" and index + 1 < len(arguments):
            options["marks"] = arguments[index + 1]
            index += 2
        elif flag == "--guide" and index + 1 < len(arguments):
            options["guide"] = arguments[index + 1]
            index += 2
        elif flag == "--paper" and index + 2 < len(arguments):
            options["papers"].append((arguments[index + 1], arguments[index + 2]))
            index += 3
        else:
            return None
    return options


def main(arguments):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    options = read_arguments(arguments)
    if options is None:
        print("usage: check_kit.py answers.json [--marks marks.json] [--paper A Version.tex ...] [--guide Guide.tex]")
        return 2
    problems = []
    kit = load(options["kit"], problems)
    checked = ["the kit"]
    if kit is not None:
        try:
            point_ids, version_keys, counts, per_question, part_keys = check_kit(kit, problems)
            if options["marks"] is not None:
                marks = load(options["marks"], problems)
                if marks is not None:
                    check_marks(marks, point_ids, version_keys, part_keys, problems)
                checked.append("the marks record")
            for version_key, path in options["papers"]:
                check_paper(version_key, path, version_keys, counts, per_question, problems)
                checked.append(f"paper {version_key}")
            if options["guide"] is not None:
                check_guide(options["guide"], point_ids, counts, problems)
                checked.append("the Marking Guide")
        except (RecursionError, TypeError, AttributeError) as error:
            problems.append(f"the file's shape could not be read ({type(error).__name__}) [json]")
    if problems:
        for line in problems:
            print(line)
        print(f"{len(problems)} problem(s): fix them before the kit is used")
        return 1
    print(f"OK: {', '.join(checked)}; {len(point_ids)} points ({describe(counts)}), versions {', '.join(version_keys)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
