#!/usr/bin/env bash
# Cuts a public release: build, DMG, GitHub release, Sparkle appcast.
#
#   scripts/release.sh --version 1.0.0 [--notes .github/release-notes/1.0.0.md] [--dry-run]
#
# Omitting --version reuses the version already in version.env, which is how you
# retry a release that failed halfway through.
#
# This runs locally rather than in CI on purpose: signing the appcast needs the
# private EdDSA key, which lives in the login keychain and never leaves this
# machine.
#
# Requirements: gh (authenticated), the Sparkle private key in the login
# keychain, a clean worktree on the release branch.
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="AstroBar"
REPO="nichtlegacy/AstroBar"
RELEASE_BRANCH="main"
RELEASE_REMOTE="origin"
DIST_DIR="dist"

NEW_VERSION=""
NOTES_PATH=""
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version) NEW_VERSION="${2-}"; shift 2 ;;
        --notes) NOTES_PATH="${2-}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 1 ;;
    esac
done

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] $*"
    else
        "$@"
    fi
}

# --- Preflight -------------------------------------------------------------

command -v gh >/dev/null || { echo "error: gh not installed" >&2; exit 1; }
if [ "$DRY_RUN" -eq 0 ]; then
    gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated, run 'gh auth login'" >&2; exit 1; }
fi
git remote get-url "$RELEASE_REMOTE" >/dev/null 2>&1 || {
    echo "error: no git remote named '${RELEASE_REMOTE}'" >&2
    echo "hint: git remote add ${RELEASE_REMOTE} https://github.com/${REPO}.git" >&2
    exit 1
}

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "$RELEASE_BRANCH" ]; then
    echo "error: on branch '${BRANCH}', releases are cut from '${RELEASE_BRANCH}'" >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "error: worktree is dirty, commit or stash first" >&2
    exit 1
fi

# shellcheck disable=SC1091
source version.env

if [ -n "$NEW_VERSION" ]; then
    if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "error: --version must be X.Y.Z, got '${NEW_VERSION}'" >&2
        exit 1
    fi
    if [ "$NEW_VERSION" != "$MARKETING_VERSION" ]; then
        echo "==> Bumping version.env to ${NEW_VERSION}"
        run sed -i '' "s/^MARKETING_VERSION=.*/MARKETING_VERSION=${NEW_VERSION}/" version.env
        run git add version.env
        run git commit -m "chore(release): v${NEW_VERSION}"
    fi
fi

# --dry-run never writes version.env, so take the requested version directly
# rather than re-reading a file that still holds the old one.
VERSION="${NEW_VERSION:-$MARKETING_VERSION}"
TAG="v${VERSION}"
DMG_PATH="${DIST_DIR}/${NAME}-${VERSION}.dmg"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${NAME}-${VERSION}.dmg"

# Sparkle decides whether a build is newer purely by CFBundleVersion, so a build
# number that goes backwards would never be offered to anyone already on the
# higher one.
if [ -f appcast.xml ]; then
    PUBLISHED_BUILD="$(
        sed -n 's/.*<sparkle:version>\([0-9][0-9]*\)<\/sparkle:version>.*/\1/p' appcast.xml \
            | sort -n | tail -1
    )"
    if [ -n "${PUBLISHED_BUILD}" ] && [ "${BUILD_NUMBER}" -le "${PUBLISHED_BUILD}" ]; then
        echo "error: BUILD_NUMBER ${BUILD_NUMBER} is not above the published build ${PUBLISHED_BUILD}" >&2
        echo "hint: raise BUILD_NUMBER in version.env" >&2
        exit 1
    fi
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "note: local tag ${TAG} already exists and will be reused"
fi

if [ -z "$NOTES_PATH" ] && [ -f ".github/release-notes/${VERSION}.md" ]; then
    NOTES_PATH=".github/release-notes/${VERSION}.md"
fi
if [ -n "$NOTES_PATH" ] && [ ! -f "$NOTES_PATH" ]; then
    echo "error: release notes not found at ${NOTES_PATH}" >&2
    exit 1
fi

if [ "$DRY_RUN" -eq 0 ]; then
    echo "==> Checking release state"
    if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
        echo "error: GitHub release ${TAG} already exists" >&2
        exit 1
    fi
fi

echo
echo "About to publish ${NAME} ${VERSION} to https://github.com/${REPO}"
echo "  tag:       ${TAG}"
echo "  asset:     ${DMG_PATH}"
echo "  notes:     ${NOTES_PATH:-<generated from commits>}"
echo "  appcast:   appcast.xml (pushed to ${RELEASE_BRANCH})"
echo
if [ "$DRY_RUN" -eq 0 ]; then
    read -r -p "Publish? This creates a public GitHub release. [y/N] " reply
    case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "aborted"; exit 1 ;;
    esac
fi

# --- Build -----------------------------------------------------------------

run swift test
run ./scripts/package_app.sh release
run mkdir -p "$DIST_DIR"
run rm -f "$DMG_PATH"
run hdiutil create -volname "$NAME" -srcfolder "${NAME}.app" -ov -format UDZO "$DMG_PATH"

# Prove the private Sparkle key is reachable before creating or pushing a tag.
# update_appcast.py signs again when it writes the final feed entry.
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
if [ "$DRY_RUN" -eq 0 ] && [ ! -x "$SIGN_UPDATE" ]; then
    echo "error: sign_update not found at ${SIGN_UPDATE}" >&2
    echo "hint: run 'swift package resolve' first" >&2
    exit 1
fi
echo "==> Verifying Sparkle signing"
run "$SIGN_UPDATE" "$DMG_PATH"

# --- Publish ---------------------------------------------------------------

echo "==> Tagging ${TAG}"
run git tag -f -a "$TAG" -m "${NAME} ${VERSION}"
run git push "$RELEASE_REMOTE" "$RELEASE_BRANCH"
run git push -f "$RELEASE_REMOTE" "$TAG"

echo "==> Creating GitHub release"
if [ -n "$NOTES_PATH" ]; then
    run gh release create "$TAG" "$DMG_PATH" \
        --repo "$REPO" --title "${NAME} ${VERSION}" --notes-file "$NOTES_PATH"
else
    run gh release create "$TAG" "$DMG_PATH" \
        --repo "$REPO" --title "${NAME} ${VERSION}" --generate-notes
fi

echo "==> Updating appcast"
APPCAST_ARGS=(
    --dmg "$DMG_PATH"
    --version "$VERSION"
    --build "$BUILD_NUMBER"
    --url "$DOWNLOAD_URL"
)
if [ -n "$NOTES_PATH" ]; then
    APPCAST_ARGS+=(--notes "$NOTES_PATH")
fi
run python3 scripts/update_appcast.py "${APPCAST_ARGS[@]}"
run git add appcast.xml
run git commit -m "chore(release): appcast for v${VERSION}"
run git push "$RELEASE_REMOTE" "$RELEASE_BRANCH"

echo
echo "Released ${NAME} ${VERSION} (build ${BUILD_NUMBER})"
echo "  ${DOWNLOAD_URL}"
echo
echo "Verify the update feed reaches users:"
echo "  curl -sSf https://raw.githubusercontent.com/${REPO}/${RELEASE_BRANCH}/appcast.xml | head -40"
