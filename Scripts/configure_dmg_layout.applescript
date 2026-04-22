on run argv
  if (count of argv) < 2 then error "Expected volume name and app bundle name"

  set volumeName to item 1 of argv
  set appBundleName to item 2 of argv
  set backgroundPath to ""

  if (count of argv) > 2 then
    set backgroundPath to item 3 of argv
  end if

  tell application "Finder"
    tell disk (volumeName)
      open
      delay 1

      set current view of the container window to icon view
      set toolbar visible of the container window to false
      set statusbar visible of the container window to false
      set bounds of the container window to {120, 120, 820, 540}

      tell the icon view options of the container window
        set arrangement to not arranged
        set icon size to 128
        set text size to 16

        if backgroundPath is not "" then
          set background picture to ((POSIX file backgroundPath) as alias)
        end if
      end tell

      set position of item appBundleName of the container window to {170, 215}
      set position of item "Applications" of the container window to {500, 215}

      close
      open
      update without registering applications
      delay 2
      close
    end tell
  end tell
end run
