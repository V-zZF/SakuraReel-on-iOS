#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TMDB_TEST_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$TMDB_TEST_DIRECTORY"' EXIT
swiftc -swift-version 6 -parse-as-library -o "$TMDB_TEST_DIRECTORY/tests" \
  SakuraReel/Models/MediaItem.swift SakuraReel/Models/MediaStatus.swift SakuraReel/Models/MediaMetadata.swift \
  SakuraReel/Utilities/MediaSort.swift SakuraReel/Services/LibraryArchive.swift SakuraReel/Services/LibrarySync.swift SakuraReel/Services/LibrarySyncDisk.swift SakuraReel/Services/LibrarySyncCoordinator.swift SakuraReel/Services/MediaRepository.swift \
  SakuraReel/Services/TMDb/TMDbClient.swift SakuraReel/Services/TMDb/TMDbImportLoader.swift \
  SakuraReel/Services/TMDb/TMDbSettings.swift SakuraReel/Services/TMDb/TMDbSearchModel.swift Tests/TMDbTests/TMDbServiceTests.swift
"$TMDB_TEST_DIRECTORY/tests"
