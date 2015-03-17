#!/bin/bash
set -o nounset -o pipefail -o errexit
cd "$(dirname "$0")"

# Settings
remote="git@github.com:davejamesmiller/awe.git"

# Ensure everything is checked in
echo "Checking for local changes..."

if [ "$(git status --porcelain)" != "" ]; then
  echo
  echo "Local changes have not been committed:"
  # Now do a regular status command to display status in a human-readable format
  git -c color.status=always status |
  # But tidy up the status output as follows:
  sed "

    # Remove the '#' prefix from all lines:
    s/^# \?//

    # Delete the following lines:
    /^On branch /d
    /^Your branch is ahead of/d
    /^  (use /d
    /^no changes added to commit/d
    /^nothing added to commit/d

    # Indent everything
    s/^/  /

  "
  echo

  # To allow for testing changes to this script, run:
  # PUBLISH_IGNORE_STATUS=1 grunt publish
  if [ "${PUBLISH_IGNORE_STATUS:-0}" == "1" ]; then
    echo "*** Ignored the above for testing ***"
  else
    exit 1
  fi
fi

# Ensure we're on the master branch
echo "Checking local branch..."

branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" != "master" ]; then
  echo
  echo "Not on 'master' branch (currently on '$branch' branch)"
  echo
  exit 1
fi

# Determine the current local commit id
local_commit="$(git rev-parse HEAD)"
if [ -z "$local_commit" ]; then
  echo
  echo "Unable to determine the current local commit ID"
  echo
  exit 1
fi

# Determine the current commit id on the remote
echo "Determining the remote version..."

remote_commit="$(git ls-remote git@github.com:davejamesmiller/awe.git refs/heads/master | cut -f 1)"
if [ -z "$remote_commit" ]; then
  echo
  echo "Unable to determine the current remote commit ID"
  echo
  exit 1
fi

# Check there are no changes that need merging
if [ "$local_commit" != "$remote_commit" ]; then
  echo "Checking for unmerged remote changes..."

  if ! git show "$remote_commit" >/dev/null 2>&1; then
    # The remote commit doesn't exist in the local history - need to download it
    # so we can display the log message
    echo 'fetch'
    git fetch $remote
    echo 'done'
  fi

  log="$(git log --pretty=format:'%C(red)%h %C(yellow)%s %C(green)(%cr) %C(bold blue)<%an>%C(reset)' $local_commit..$remote_commit | sed 's/^/  /')"
  if [ -n "$log" ]; then
    echo
    echo "Remote changes have not been merged:"
    echo
    echo "$log"
    echo
    exit 1
  fi
fi

# Confirm documentation has been updated if needed (prompt the user)
# source "includes/ask.sh"

# if ! ask "Did you remember to update the documentation?" Y; then
#   echo
#   echo "  Hmm... Better go do that then."
#   echo
#   exit 1
# fi

# # Run unit tests
# echo "Running unit tests..."
# echo
# grunt --color test 2>&1 | sed 's/^/  /' || exit
# echo

# Display current version number

# Prompt for new version number (unless a version was given?)

# Tag version with npm

# Push code & tags to GitHub

# Publish in npm (runs unit tests again)
