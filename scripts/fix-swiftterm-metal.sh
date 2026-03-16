#!/bin/bash
# Workaround for tuist/tuist#9111: Tuist adds .metal files as both Sources and Resources,
# causing "Unexpected duplicate tasks" build errors.
# This removes the duplicate "Shaders.metal in Sources" entry, keeping only Resources.

PBXPROJ="Tuist/.build/tuist-derived/SwiftTerm/SwiftTerm.xcodeproj/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
  echo "SwiftTerm project not found, skipping"
  exit 0
fi

if grep -q "Shaders.metal in Sources" "$PBXPROJ"; then
  sed -i.bak '/Shaders\.metal in Sources/d' "$PBXPROJ"
  rm -f "${PBXPROJ}.bak"
  echo "Fixed: removed duplicate Shaders.metal from Sources build phase"
else
  echo "No duplicate Metal entry found, skipping"
fi
