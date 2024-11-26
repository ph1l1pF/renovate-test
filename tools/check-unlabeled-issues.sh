#!/bin/bash

# When the repository labels are changed (i.e dropped a label, added a label, etc), you should make the same change to the lists below.
# For example, if the repository added a "type:task" type label, then add "-label:type:task" to the TYPE_LABELS_FILTER.
TYPE_LABELS_FILTER='-label:type:bug -label:type:feature -label:type:docs -label:type:refactor -label:type:help'

PRIORITY_LABELS_FILTER='-label:priority-1-critical -label:priority-2-high -label:priority-3-medium -label:priority-4-low'

HAS_ISSUES_MISSING_LABELS=false

ISSUE_BODY="# Label check action\n"

REPO='ph1l1pf/renovate-test'

ISSUE_TITLE="Found other non-labled issues"

for FILTER in "$TYPE_LABELS_FILTER" "$PRIORITY_LABELS_FILTER"; do
  # Extract the label type from the filter
  LABEL_TYPE=$(echo "$FILTER" | cut -d ':' -f 2 | cut -d '-' -f 1)

  # Fetch issues filtered by the label type
  ISSUES_MISSING_LABEL=$(gh issue list --repo $REPO --limit 100000 -s open -S "$FILTER" --json "number,title") || { echo "Failed to fetch issues without $LABEL_TYPE labels"; exit 1; }
  # filter out issue with title the label action issue itself
  ISSUES_MISSING_LABEL=$(echo "$ISSUES_MISSING_LABEL" | jq --arg title "$ISSUE_TITLE" 'map(select(.title != $title))')
  
  if [ "$ISSUES_MISSING_LABEL" != "[]" ]; then
    HAS_ISSUES_MISSING_LABELS=true

    # Format the output to be a list of issue numbers
    FORMATTED_OUTPUT=$(echo "$ISSUES_MISSING_LABEL" | jq -r '.[].number' | sed 's/^/- #/')

    # Count the number of issues to determine if it's singular or plural
    ISSUE_COUNT=$(echo "$ISSUES_MISSING_LABEL" | jq '. | length')
    ISSUE_SINGULAR_PLURAL=$(if [ "$ISSUE_COUNT" -eq 1 ]; then echo "issue"; else echo "issues"; fi)

    # Append the list of issues to the new issue body
    ISSUE_BODY="$ISSUE_BODY## Found $ISSUE_COUNT $ISSUE_SINGULAR_PLURAL missing \`$LABEL_TYPE:\` labels:\n$FORMATTED_OUTPUT\n"
  fi
done

if [ "$HAS_ISSUES_MISSING_LABELS" = false ]; then
  echo "Found no issues with missing labels. Exixting the action."
  exit 0
fi

LABEL_CHECK_ACTION="Label check action"

# check if label "Label check action" exists
LABEL_CHECKACTION_EXISTS=$(gh label list --repo $REPO | grep "$LABEL_CHECK_ACTION") || { echo "Failed to fetch existing label"; exit 1; }
if [ -z "$LABEL_CHECKACTION_EXISTS" ]; then
  echo "Label '$LABEL_CHECK_ACTION' does not exist. Will create it."
  # Create a new label "Label check action"
  gh label create "$LABEL_CHECK_ACTION" --description "This label is used for the issue that lists invalid issues." --repo $REPO || { echo "Failed to create label"; exit 1; }
fi

LABEL_CHECK_ISSUE_EXISTS=$(gh search issues --label "$LABEL_CHECK_ACTION" --repo $REPO --json number) || { echo "Failed to fetch existing label check issue"; exit 1; }
ISSUE_NUMBER=$(echo "$LABEL_CHECK_ISSUE_EXISTS" | jq -r '.[].number')

if [ -z "$ISSUE_NUMBER" ]; then

  # Create a new issue with the list of issues
  gh issue create --repo $REPO --label "$LABEL_CHECK_ACTION" --title "$ISSUE_TITLE" --body "$(echo -e "$ISSUE_BODY")" || { echo "Failed to create issue"; exit 1; }
else
  # Update the existing issue with the list of issues
  gh issue edit "$ISSUE_NUMBER" --repo $REPO --title "$ISSUE_TITLE" --body "$(echo -e "$ISSUE_BODY")" || { echo "Failed to update issue"; exit 1; }

  # Reopen the issue
  gh issue reopen "$ISSUE_NUMBER" --repo $REPO || { echo "Failed to reopen issue"; exit 1; }
fi

# Provide an output in the action itself
echo -e "$ISSUE_BODY"

# Fail the action if there are issues missing the correct labels
echo "Found issues missing labels. Please check the issue(s) above."

exit 1

