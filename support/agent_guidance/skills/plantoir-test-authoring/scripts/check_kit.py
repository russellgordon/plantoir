#!/usr/bin/env python3
"""
Check a marking kit's answers.json, and optionally a marks record, against
the kit format (templates/Marking Kit/FORMAT.md beside this skill).

Run it from the working folder, never import it, and do not copy or change
it: this is the one script in the skill that is NOT a starting point. The
format is what the plantoir-marking skill reads, so a kit that passes here
is a kit it can mark from. Change the kit, never this file.

    python3 -B .claude/skills/plantoir-test-authoring/scripts/check_kit.py "<test folder>/Marking Kit/answers.json"
    python3 -B .claude/skills/plantoir-test-authoring/scripts/check_kit.py "<test folder>/Marking Kit/answers.json" --marks "<test folder>/Marking Kit/marks-template.json"

(On Windows, `python` or `py` in place of `python3`, and `.agents` works as
well as `.claude`.) It prints one line per problem, each ending in the
rule it breaks in square brackets, and exits 1; or one OK line and exits 0.
It prints point IDs and keys only, never what a marks record says.
Standard library only.
"""
import json
import sys

KIT_VERSION = 1
FORBIDDEN_KEYS = ["name", "student", "pupil", "email"]
EARNED_VALUES = [None, 0, 0.5, 1]


def load(path, problems):
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as error:
        problems.append(f"{path} could not be read as JSON ({type(error).__name__}) [json]")
        return None
    if not isinstance(data, dict):
        problems.append(f"{path} is not a JSON object [json]")
        return None
    return data


def find_forbidden_keys(value, where, problems):
    """Every key at any depth, so no file in a kit has a place for a name."""
    if isinstance(value, dict):
        for key in value:
            if isinstance(key, str) and key.lower() in FORBIDDEN_KEYS:
                problems.append(f"{where} has a key called {key}; the kit and the marks records never hold a name [forbidden-key]")
            find_forbidden_keys(value[key], f"{where} -> {key}", problems)
    elif isinstance(value, list):
        index = 0
        for item in value:
            find_forbidden_keys(item, f"{where} [{index}]", problems)
            index += 1


def is_text(value):
    return isinstance(value, str) and value.strip() != ""


def list_of_objects(kit, key, problems):
    value = kit.get(key)
    if not isinstance(value, list) or len(value) == 0:
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
    """The IDs in order, reporting a missing or repeated one."""
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
    find_forbidden_keys(kit, "answers.json", problems)
    if kit.get("kit") != KIT_VERSION:
        problems.append(f"kit must be {KIT_VERSION} [kit-version]")
    for key in ["test", "course"]:
        if not is_text(kit.get(key)):
            problems.append(f"{key} must be text [required]")

    categories = list_of_objects(kit, "categories", problems)
    parts = list_of_objects(kit, "parts", problems)
    questions = list_of_objects(kit, "questions", problems)
    points = list_of_objects(kit, "points", problems)
    category_keys = collect_ids(categories, "key", "categories", problems)
    part_keys = collect_ids(parts, "key", "parts", problems)
    question_ids = collect_ids(questions, "id", "questions", problems)
    point_ids = collect_ids(points, "id", "points", problems)

    for category in categories:
        if not is_text(category.get("title")):
            problems.append(f"category {category.get('key')} has no title [required]")

    for part in parts:
        if not is_text(part.get("title")):
            problems.append(f"part {part.get('key')} has no title [required]")
        if "category" in part and part["category"] not in category_keys:
            problems.append(f"part {part.get('key')} names category {part['category']}, which is not in categories [part-category]")

    topics = kit.get("topics", {})
    if not isinstance(topics, dict):
        problems.append("topics must be an object [topic]")
        topics = {}
    for key in topics:
        if key.startswith("_"):
            continue
        topic = topics[key]
        pages = topic.get("pages") if isinstance(topic, dict) else None
        if not isinstance(pages, list) or len(pages) == 0:
            problems.append(f"topic {key} has no pages [topic]")
            continue
        for page in pages:
            if not isinstance(page, dict) or not is_text(page.get("title")) or not is_text(page.get("path")):
                problems.append(f"a page of topic {key} needs a title and a path [topic]")

    for question in questions:
        if question.get("part") not in part_keys:
            problems.append(f"question {question.get('id')} names part {question.get('part')}, which is not in parts [question-part]")
        if not is_text(question.get("skill")):
            problems.append(f"question {question.get('id')} has no skill [required]")
        question_topics = question.get("topics", [])
        if not isinstance(question_topics, list):
            problems.append(f"question {question.get('id')}: topics must be a list [topic]")
            question_topics = []
        for topic_key in question_topics:
            if topic_key not in topics:
                problems.append(f"question {question.get('id')} names topic {topic_key}, which is not in topics [topic]")

    earlier_points = []
    question_of_point = {}
    for point in points:
        point_id = point.get("id")
        if point.get("question") not in question_ids:
            problems.append(f"point {point_id} names question {point.get('question')}, which is not in questions [point-question]")
        if point.get("category") not in category_keys:
            problems.append(f"point {point_id} names category {point.get('category')}, which is not in categories [point-category]")
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
        version = versions[version_key]
        if not isinstance(version, dict):
            problems.append(f"version {version_key} must be an object [required]")
            continue
        if not is_text(version.get("source")):
            problems.append(f"version {version_key} has no source [version-source]")
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
            accept = entry.get("accept", [])
            if not isinstance(accept, list):
                problems.append(f"version {version_key}, point {point_id}: accept must be a list [every-point-answered]")
            misconceptions = entry.get("misconceptions", {})
            if not isinstance(misconceptions, dict):
                problems.append(f"version {version_key}, point {point_id}: misconceptions must be an object [every-point-answered]")
        for answered in answers:
            if answered not in point_ids:
                problems.append(f"version {version_key} answers {answered}, which is not in points [unknown-point]")

    strengths = kit.get("strengths", [])
    if not isinstance(strengths, list):
        problems.append("strengths must be a list [strengths]")
        strengths = []
    for strength in strengths:
        if not isinstance(strength, dict) or not is_text(strength.get("sentence")):
            problems.append("every strength needs a sentence [strengths]")
            continue
        halves = strength.get("halves")
        if not isinstance(halves, list) or len(halves) == 0:
            problems.append(f"strength \"{strength['sentence']}\" has no halves [strengths]")
            continue
        for half in halves:
            half_points = half.get("points") if isinstance(half, dict) else None
            if not isinstance(half_points, list) or len(half_points) == 0:
                problems.append(f"a half of strength \"{strength['sentence']}\" has no points [strengths]")
                continue
            half_sentence = half.get("sentence")
            if half_sentence is not None and not is_text(half_sentence):
                problems.append(f"a half of strength \"{strength['sentence']}\": sentence must be text or null [strengths]")
            for point_id in half_points:
                if point_id not in point_ids:
                    problems.append(f"strength \"{strength['sentence']}\" names point {point_id}, which is not in points [strengths]")
    return point_ids, list(versions.keys())


def check_marks(marks, point_ids, version_keys, problems):
    find_forbidden_keys(marks, "the marks record", problems)
    if marks.get("kit") != KIT_VERSION:
        problems.append(f"the marks record: kit must be {KIT_VERSION} [marks-kit]")
    identifier = marks.get("identifier")
    if identifier is not None and not is_text(identifier):
        problems.append("the marks record: identifier must be text or null [marks-identifier]")
    version = marks.get("version")
    if version is not None and version not in version_keys:
        problems.append("the marks record names a version the kit does not have [marks-version]")
    points = marks.get("points")
    if not isinstance(points, dict):
        problems.append("the marks record has no points [marks-points]")
        return
    for point_id in point_ids:
        if point_id not in points:
            problems.append(f"the marks record does not have point {point_id} [marks-points]")
    for point_id in points:
        if point_id not in point_ids:
            problems.append(f"the marks record has point {point_id}, which is not in the kit [marks-points]")
            continue
        entry = points[point_id]
        if not isinstance(entry, dict) or "earned" not in entry:
            problems.append(f"the marks record: point {point_id} has no earned [marks-earned]")
            continue
        earned = entry["earned"]
        allowed = False
        for value in EARNED_VALUES:
            if earned is value or (value is not None and not isinstance(earned, bool) and earned == value):
                allowed = True
        if not allowed:
            problems.append(f"the marks record: point {point_id} earned must be null, 0, 0.5 or 1 [marks-earned]")


def main(arguments):
    if len(arguments) not in (1, 3) or (len(arguments) == 3 and arguments[1] != "--marks"):
        print("usage: check_kit.py answers.json [--marks marks.json]")
        return 2
    problems = []
    kit = load(arguments[0], problems)
    if kit is None:
        for line in problems:
            print(line)
        return 1
    point_ids, version_keys = check_kit(kit, problems)
    if len(arguments) == 3:
        marks = load(arguments[2], problems)
        if marks is not None:
            check_marks(marks, point_ids, version_keys, problems)
    if problems:
        for line in problems:
            print(line)
        print(f"{len(problems)} problem(s): the kit cannot be marked from until they are fixed")
        return 1
    joined_versions = ", ".join(version_keys)
    checked = "the kit and the marks record" if len(arguments) == 3 else "the kit"
    print(f"OK: {checked}, {len(point_ids)} points, versions {joined_versions}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
