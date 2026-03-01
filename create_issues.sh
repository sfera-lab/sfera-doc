#!/usr/bin/env bash
set -euo pipefail

REPO="OWNER/REPO"   # change
LABELS="analysis"
ASSIGNEE=""

find . -type f \
  -not -path './.git/*' \
  | sed 's#^\./##' \
  | sort \
  | while IFS= read -r file; do
    title="Analyze file: $file"
    body=$(cat <<EOB
## File
\`$file\`

## Analysis checklist
- Purpose and responsibility
- API and boundaries
- Error handling and edge cases
- Performance considerations
- Test coverage gaps
- Refactor suggestions
EOB
)

    cmd=(gh issue create --repo "$REPO" --title "$title" --body "$body")
    [ -n "$LABELS" ] && cmd+=(--label "$LABELS")
    [ -n "$ASSIGNEE" ] && cmd+=(--assignee "$ASSIGNEE")

    "${cmd[@]}"
    echo "Created issue for $file"
  done
