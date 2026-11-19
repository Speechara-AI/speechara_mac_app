#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEST_BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/speechara-history-tests.XXXXXX")
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT
xcrun swiftc -parse-as-library \
  Speechara/Services/SessionDraft.swift \
  Speechara/Services/MeetingSessionHistoryService.swift \
  Tests/HistoryPersistence/Support.swift \
  Tests/HistoryPersistence/HistoryPersistenceTests.swift \
  -o "$TEST_BUILD_DIR/history-tests"
"$TEST_BUILD_DIR/history-tests"
