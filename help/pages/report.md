---
id: report
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/App/ProblemReportCommands.swift
- contracts/shared-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- problem report
- report a problem
- report
- support
- bug
- email
- contact
- developer
- something went wrong
- privacy
description: Report a Problem gathers what Plantoir did lately into one file. You save the file and email it to support@plantoir.app.
---
A problem report is one file that says what Plantoir did on the last few things you asked it to do. You save it, then email it to the developer.

## Steps

1. Choose {{menu:helpReportAProblem}}. An alert titled {{control:problemReportAlertTitle}} opens.
2. Read what the report includes and what it leaves out.
   - It includes the messages Plantoir showed, course codes and section numbers, the names of pages, and what kind of {{machine}} this is.
   - It leaves out what you have written on your pages, your sign-in details for Netlify or Cloudflare, and your name.

{{picture:report-1}}
alt: The Send a report about a problem alert, which lists what the report includes and leaves out, with a Save Report button.

{{assistant}}
If you have typed to the local AI assistant, the alert also has a tick box, {{control:problemReportIncludeWhatITypedCheckbox}}. It starts unticked. Tick it only if you want what you typed to go in the report.
{{/assistant}}

3. Press {{control:problemReportSaveReportButton}}. A panel opens on the Desktop for you to save the file. The file's name begins with Plantoir problem report, followed by the date and the time.
4. Open the file if you want to see what is in it. It carries a note that lists what is in the report and what is not.
5. Email the file to support@plantoir.app. The alert shows the address as a link. In the email, say what you expected to happen.

## If it does not work

- **An alert titled {{control:problemReportNothingToReportYetTitle}} appears.** Plantoir keeps a note of what it does, and it has done nothing yet. Do the thing that went wrong once more, then report.
- **An alert titled {{control:problemReportCouldNotBeSavedTitle}} appears.** Nothing was written. Save the report somewhere else. The Desktop is usually safe.
