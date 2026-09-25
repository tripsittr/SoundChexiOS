#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 SoundChex

#
# Generates SoundChex.xcodeproj after Xcode Cloud clones the repository.
#
# The project file is gitignored here: `project.yml` is the source of truth and
# XcodeGen writes the .xcodeproj from it. That is right for the repo — a
# generated file in version control is a merge conflict waiting to happen — but
# it means a clean checkout has nothing to build. Without this script every
# Xcode Cloud build fails at once, in a way that reads like a broken
# configuration rather than a missing file.
#
# Apple fixes the path and the name: ci_scripts/ci_post_clone.sh, run
# automatically after the clone. The file must be executable, or it is skipped
# in silence — which looks exactly like it not being here at all.
#

set -e

echo "--- Installing XcodeGen"

# Homebrew is present on Xcode Cloud runners but not always on PATH.
if ! command -v brew > /dev/null 2>&1; then
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

if ! command -v brew > /dev/null 2>&1; then
    echo "Homebrew is not available on this runner; cannot install XcodeGen." >&2
    exit 1
fi

# Skip the analytics ping and the auto-update: both add a minute or more to
# every build, and the runner is thrown away afterwards.
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1

brew install xcodegen

echo "--- Generating SoundChex.xcodeproj"

# Xcode Cloud starts this script in ci_scripts/, so the project root is up one.
cd "$CI_PRIMARY_REPOSITORY_PATH" || cd "$(dirname "$0")/.."

xcodegen generate

# Fail loudly here rather than letting the build fail later with a confusing
# error about a missing scheme.
if [ ! -d "SoundChex.xcodeproj" ]; then
    echo "XcodeGen ran but produced no project." >&2
    exit 1
fi

echo "--- Generated the project for $(grep MARKETING_VERSION project.yml | head -1 | sed 's/.*: *//' | tr -d '\"')"
