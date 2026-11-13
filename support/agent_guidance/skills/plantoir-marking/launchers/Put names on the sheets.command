#!/bin/bash
# Put names on the sheets: the plantoir-marking skill (#750, piece 750d). For the TEACHER to double-click, never for an
# assistant to run. It asks for your teacher-only folder in this window and does the step your assistant
# asked for in Names request.json (names on the sheets, the report comments, the checks of
# your name table), with what it said written in the marking folder for your assistant.
# It is never adapted: the skill names its SHA-256, and it checks the SHA-256 of the two scripts it runs
# (teacher_only.py and run_with_names.py, in the skill folder named in "Skill folder.txt") before it runs them.
STEP="names"
TITLE="Put names on the sheets"
TEACHER_ONLY_SHA256="364fb9bb87b691d3f9c650e98f2c2180933a3daacda366cfd302d537ac2c87f1"
RUNNER_SHA256="41fa097c8cbdefd87192d3225c7d2fcdf8aa5c760d29235e7ece95e05e7b4ffb"
CHECK="import hashlib,os,sys;a=sys.argv[1:];c=sum(1 for i in range(0,len(a),2) if not os.path.isfile(a[i]) or hashlib.sha256(open(a[i],'rb').read()).hexdigest()!=a[i+1]);print('Stopped: '+str(c)+' of the two scripts this step runs are not the ones Plantoir shipped, so nothing was run. Ask your assistant to copy the launchers again from the plantoir-marking skill. If it still stops, Plantoir puts the skill back as it shipped the next time it opens your working folder.') if c else None;sys.exit(1 if c else 0)"

cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

finish() {
  echo
  read -r -p "Press Return to close this window. " _
  exit "$1"
}

if [ ! -t 0 ]; then
  echo "Stopped: $TITLE is for the teacher to double-click, in its own window. Nothing was done."
  exit 1
fi
PYTHON=""
for candidate in python3 /usr/bin/python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PYTHON="$candidate"
    break
  fi
done
if [ -z "$PYTHON" ]; then
  echo "Stopped: Python 3 is not installed. On a Mac with Homebrew: brew install python. Nothing was done."
  finish 1
fi
SKILL=""
if [ -f "Skill folder.txt" ]; then
  IFS= read -r SKILL < "Skill folder.txt"
fi
if [ -z "$SKILL" ] || [ ! -d "$SKILL/scripts" ]; then
  echo "Stopped: this marking folder does not say where the plantoir-marking skill is. Ask your assistant to copy the launchers again. Nothing was done."
  finish 1
fi
if ! "$PYTHON" -I -B -c "$CHECK" "$SKILL/scripts/teacher_only.py" "$TEACHER_ONLY_SHA256" "$SKILL/scripts/run_with_names.py" "$RUNNER_SHA256"; then
  finish 1
fi
"$PYTHON" -I -B "$SKILL/scripts/teacher_only.py" "$STEP" "$PWD"
finish $?
