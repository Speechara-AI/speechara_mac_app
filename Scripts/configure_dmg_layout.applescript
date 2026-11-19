on run argv
  if (count of argv) < 2 then error "Expected volume name and app bundle name"

  set volumeName to item 1 of argv
  set appBundleName to item 2 of argv
  set backgroundFile to ""
  set mountPath to ""

  if (count of argv) > 2 then
    set backgroundFile to item 3 of argv
  end if

  if (count of argv) > 3 then
    set mountPath to item 4 of argv
  end if

  tell application "Finder"
    set targetFolder to missing value

    if mountPath is not "" then
      set targetFolder to POSIX file mountPath as alias
    else
      set targetFolder to disk volumeName
    end if

    open targetFolder
    delay 1
    set dmgWindow to container window of targetFolder
    set bgFile to missing value

    if backgroundFile is not "" then
      set bgFile to my backgroundFileReference(targetFolder, backgroundFile, mountPath)
    end if

    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set bounds of dmgWindow to {120, 120, 820, 540}

    tell the icon view options of dmgWindow
      set arrangement to not arranged
      set icon size to 128
      set text size to 16

      if bgFile is not missing value then
        set background picture to bgFile
      end if
    end tell

    set position of item appBundleName of dmgWindow to {170, 215}
    set position of item "Applications" of dmgWindow to {500, 215}
    my moveItemOutOfView(dmgWindow, ".background", {900, 90})
    my moveItemOutOfView(dmgWindow, ".fseventsd", {900, 160})
    my moveItemOutOfView(dmgWindow, ".Trashes", {900, 230})

    close dmgWindow
    open targetFolder
    delay 1
    set dmgWindow to container window of targetFolder
    update targetFolder without registering applications
    delay 2
    -- Finder can close or replace the window while saving the layout.
    -- Closing it afterwards is optional; the disk is detached by create_dmg.sh.
    try
      close dmgWindow
    end try
  end tell
end run

on backgroundFileReference(targetFolder, backgroundFile, mountPath)
  tell application "Finder"
    if backgroundFile starts with ".background:" then
      set backgroundFileName to text 13 thru -1 of backgroundFile
      if mountPath is not "" then
        return POSIX file (mountPath & "/.background/" & backgroundFileName) as alias
      end if

      return file backgroundFileName of folder ".background" of targetFolder
    end if

    if mountPath is not "" then
      return POSIX file (mountPath & "/" & backgroundFile) as alias
    end if

    return file backgroundFile of targetFolder
  end tell
end backgroundFileReference

on moveItemOutOfView(dmgWindow, itemName, itemPosition)
  tell application "Finder"
    if exists item itemName of dmgWindow then
      set position of item itemName of dmgWindow to itemPosition
    end if
  end tell
end moveItemOutOfView
