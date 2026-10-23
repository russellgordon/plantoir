on run argv
  set needle to item 1 of argv
  tell application "System Events" to tell process "Safari"
    set ws to (every window whose name contains needle)
    if (count of ws) is 0 then return "nowindow"
    set w to item 1 of ws
    if (count of sheets of w) is 0 then return "nosheet"
    set c to entire contents of sheet 1 of w
    set pages to "?"
    set target to missing value
    repeat with i from 1 to count of c
      set e to item i of c
      try
        set r to role of e
        set n to name of e
        if r is "AXStaticText" and n is not missing value and (n as text) starts with "Page " then set pages to n as text
        if r is "AXButton" and n is not missing value and (n as text) is "Cancel" then set target to e
      end try
    end repeat
    if target is missing value then return "nocancel"
    click target
    return "cancelled " & pages
  end tell
end run
