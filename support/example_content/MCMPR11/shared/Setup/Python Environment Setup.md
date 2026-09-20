---
title: Python Environment Setup
publish: true
created: __CREATED__
tags:
  - setup
enableToc: true
---
To write code, your computer needs to understand the language. Python is the language we 
use, and VS Code is the text editor where we write it. This guide gets both running on your 
machine.

## 1. Check if Python is already there

Mac and Windows machines often come with a version of Python already. Let's find out.

Open your terminal:
- **Mac:** Press `Cmd + Space`, type `Terminal`, and hit Enter.
- **Windows:** Press the `Windows key`, type `PowerShell`, and hit Enter.

Type this exact command and hit Enter:
```bash
python3 --version
```
(On Windows, you might need to use `python --version` without the 3).

If you see something like `Python 3.12.2`, you are good to go. Skip to Step 3. 
If you see `command not found` or an error, go to Step 2.

## 2. Install Python

1. Go to [python.org/downloads](https://www.python.org/downloads/).
2. Click the big yellow download button for your operating system.
3. Run the installer. 
   - **Windows users:** This is critical. On the very first screen of the installer, check the box that says **"Add Python to PATH"**. If you miss this, nothing will work later.
4. Finish the installation, then open a *new* terminal window and run the version check from Step 1 again.

## 3. Verify the REPL

Let's make sure Python can talk back. In your terminal, type:
```bash
python3
```
(Again, just `python` on some Windows machines). 

The prompt will change to `>>>`. You are now talking directly to Python. Try asking it to do math:
```python
>>> 10 + 5
15
>>> print("Hello from BC!")
Hello from BC!
```
To exit, type `quit()` and hit Enter.

## 4. Install VS Code

You could write code in a basic text editor, but VS Code highlights errors, auto-completes 
brackets, and makes life easier.

1. Go to [code.visualstudio.com](https://code.visualstudio.com/).
2. Download and install it for your system.
3. Open VS Code. Go to the Extensions tab (the four squares icon on the left).
4. Search for "Python" (the one by Microsoft) and click Install.

## 5. Write your first file

1. In VS Code, go to `File > Open Folder` and create a new folder on your computer for this class (e.g., `Programming11`).
2. Inside that folder, create a new file named `hello.py`. The `.py` extension tells VS Code this is a Python file.
3. Type this code into the file:

```python
print("Checking systems for the Salish Sea Tracker...")
print("Ready to go.")
```
4. Save the file (`Cmd+S` or `Ctrl+S`).

## 6. Run your program

We run programs from the terminal. 
1. In VS Code, go to `Terminal > New Terminal`. This opens a terminal right at the bottom of your window, already in the correct folder.
2. Tell Python to run your file:

```bash
python3 hello.py
```

You should see:
```text
Checking systems for the Salish Sea Tracker...
Ready to go.
```

## Troubleshooting common issues

- **"command not found: python3"**: Your computer doesn't know where Python is. If you're on Windows, you likely forgot to check "Add to PATH" during installation. Re-run the installer, choose "Modify", and check that box.
- **SyntaxError**: You probably missed a quotation mark or bracket in your `print` statement. Check `hello.py` carefully.

> [!success]- First program checklist
> - [ ] I can open the terminal.
> - [ ] I can check my Python version.
> - [ ] I have VS Code installed with the Python extension.
> - [ ] I wrote and ran a file that printed text to the screen.
