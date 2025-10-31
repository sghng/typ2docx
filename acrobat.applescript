#!/usr/bin/osascript
on run argv
    if (count of argv) > 0 then
        set pdfPath to item 1 of argv
    else
        set pdfPath to "/Users/sghuang/dev/typ2docx/typ2docx.a.pdf"
    end if

    tell application "System Events"
        set acrobatWasRunning to (exists process "AdobeAcrobat")
    end tell

    tell application "Adobe Acrobat"
        activate
        open POSIX file pdfPath
    end tell

    # File -> Export a PDF -> Microsoft Word -> Word Document

    tell application "System Events"
        tell process "AdobeAcrobat"
            click menu item "Word Document" of ¬
                  menu "Microsoft Word" of ¬
                  menu item "Microsoft Word" of ¬
                  menu "Export a PDF" of ¬
                  menu item "Export a PDF" of ¬
                  menu "File" of ¬
                  menu bar 1
            delay .8 # wait for the finder pop up

            set viewResultCheckbox to ¬
                checkbox "View Result" of splitter group 1 of window 1
            if value of viewResultCheckbox is 1 then
                click viewResultCheckbox
            end if

            keystroke return
            delay .1 # wait for the confirmation pop up

            if exists sheet 1 of window 1 then
                click button "Replace" of sheet 1 of window 1
            end if
        end tell
    end tell

    # FIXME: somehow doesn't work for newly launched Acrobat instances

    delay .1 # wait for the pop up to close
    if not acrobatWasRunning then
        tell application "Adobe Acrobat"
            quit
        end tell
    else
        tell application "System Events"
            tell process "AdobeAcrobat"
                click menu item "Close File" of menu "File" of menu bar 1
            end tell
        end tell
    end if

    return
end run
