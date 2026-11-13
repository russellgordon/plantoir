@echo off
rem Box the papers: the plantoir-marking skill (#750, piece 750d). For the TEACHER to double-click, never for an
rem assistant to run. It asks for your teacher-only folder in this window, boxes the papers there, puts them in
rem one file for you to look through, and moves them to where your assistant reads only when
rem you type yes.
rem It is never adapted: the skill names its SHA-256, and it checks the SHA-256 of the two scripts it runs
rem (teacher_only.py and run_with_names.py, in the skill folder named in "Skill folder.txt") before it runs them.
setlocal
set "STEP=box"
set "TITLE=Box the papers"
set "TEACHER_ONLY_SHA256=d0373eba4f687175c9fbc068f0d5f4e1be32a6e19e2c19c1be93572f5b2c8a99"
set "RUNNER_SHA256=41fa097c8cbdefd87192d3225c7d2fcdf8aa5c760d29235e7ece95e05e7b4ffb"
title %TITLE%
cd /d "%~dp0"
set "PYTHON="
where py >nul 2>nul && set "PYTHON=py -3"
if not defined PYTHON where python >nul 2>nul && set "PYTHON=python"
if not defined PYTHON goto no_python
set "SKILL="
if exist "Skill folder.txt" set /p SKILL=<"Skill folder.txt"
if not defined SKILL goto no_skill
if not exist "%SKILL%\scripts" goto no_skill
%PYTHON% -I -B -c "import hashlib,os,sys;a=sys.argv[1:];c=sum(1 for i in range(0,len(a),2) if not os.path.isfile(a[i]) or hashlib.sha256(open(a[i],'rb').read()).hexdigest()!=a[i+1]);print('Stopped: '+str(c)+' of the two scripts this step runs are not the ones Plantoir shipped, so nothing was run. Ask your assistant to copy the launchers again from the plantoir-marking skill. If it still stops, Plantoir puts the skill back as it shipped the next time it opens your working folder.') if c else None;sys.exit(1 if c else 0)" "%SKILL%\scripts\teacher_only.py" %TEACHER_ONLY_SHA256% "%SKILL%\scripts\run_with_names.py" %RUNNER_SHA256%
if errorlevel 1 goto failed
%PYTHON% -I -B "%SKILL%\scripts\teacher_only.py" %STEP% "%CD%\."
set "CODE=%ERRORLEVEL%"
echo.
pause
exit /b %CODE%
:no_python
echo Stopped: Python 3 is not installed. Install it from python.org, then double-click again. Nothing was done.
goto failed
:no_skill
echo Stopped: this marking folder does not say where the plantoir-marking skill is. Ask your assistant to copy the launchers again. Nothing was done.
:failed
echo.
pause
exit /b 1
