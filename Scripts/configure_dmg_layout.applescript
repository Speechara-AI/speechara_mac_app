on run argv
  if (count of argv) < 2 then error "Expected volume name and app bundle name"

  set volumeName to item 1 of argv
  set appBundleName to item 2 of argv
  set backgroundFile to ""

  if (count of argv) > 2 then
    set backgroundFile to item 3 of argv
  end if

  tell application "Finder"
    tell disk (volumeName)
      open
      delay 1
      set bgFile to missing value

      if backgroundFile is not "" then
        set bgFile to file backgroundFile
      end if

      set current view of the container window to icon view
      set toolbar visible of the container window to false
      set statusbar visible of the container window to false
      set bounds of the container window to {120, 120, 820, 540}

      tell the icon view options of the container window
        set arrangement to not arranged
        set icon size to 128
        set text size to 16

        if bgFile is not missing value then
          set background picture to bgFile
        end if
      end tell

      set position of item appBundleName of the container window to {170, 215}
      set position of item "Applications" of the container window to {500, 215}
      my moveItemOutOfView(the container window, ".background", {900, 90})
      my moveItemOutOfView(the container window, ".fseventsd", {900, 160})
      my moveItemOutOfView(the container window, ".Trashes", {900, 230})

      close
      open
      update without registering applications
      delay 2
      close
    end tell
  end tell
end run

on moveItemOutOfView(dmgWindow, itemName, itemPosition)
  tell application "Finder"
    if exists item itemName of dmgWindow then
      set position of item itemName of dmgWindow to itemPosition
    end if
  end tell
end moveItemOutOfView
