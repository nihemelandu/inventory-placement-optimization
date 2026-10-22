#!/usr/bin/env bash
# Loads the initial master backlog into an existing GitHub repo + Project.
# Run once, on your own machine, logged in to GitHub as yourself.
set -euo pipefail

OWNER="nihemelandu"
REPO="inventory-placement-optimization"
PROJECT_TITLE="inventory-placement-optimization-project"

# ---------- Preconditions ----------
command -v gh >/dev/null || { echo "Install the GitHub CLI: https://cli.github.com"; exit 1; }
command -v jq >/dev/null || { echo "Install jq: https://jqlang.github.io/jq/"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Not logged in. Run: gh auth login"; exit 1; }

# Projects need the 'project' scope (interactive, one-time)
gh auth refresh -s project

# ---------- Locate the Project ----------
PROJECT_NUMBER=$(gh project list --owner "$OWNER" --format json \
  | jq -r --arg t "$PROJECT_TITLE" '.projects[] | select(.title==$t) | .number')
[ -n "$PROJECT_NUMBER" ] || { echo "Project '$PROJECT_TITLE' not found under $OWNER"; exit 1; }
PROJECT_ID=$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json | jq -r '.id')
echo "Using project #$PROJECT_NUMBER ($PROJECT_ID)"

fields_json() { gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json; }

# ---------- Create custom fields if missing ----------
if ! fields_json | jq -e '.fields[] | select(.name=="Item Type")' >/dev/null; then
  gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" \
    --name "Item Type" --data-type SINGLE_SELECT \
    --single-select-options "Business Understanding,Data Understanding,Data Preparation,Modeling,Evaluation,Deployment"
fi
if ! fields_json | jq -e '.fields[] | select(.name=="Priority/Rank")' >/dev/null; then
  gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" \
    --name "Priority/Rank" --data-type NUMBER
fi

FIELDS=$(fields_json)
TYPE_FIELD_ID=$(echo "$FIELDS" | jq -r '.fields[] | select(.name=="Item Type") | .id')

# ---------- Initial backlog: "Item Type|Item Name" ----------
# Edit this list freely before running.
ITEMS=$(cat <<'EOF'
Business Understanding|What resources are available?
Business Understanding|What are the risks and contingencies?
Business Understanding|What does the cost-benefit analysis look like?
Business Understanding|What is the domain terminology? (shared glossary)
Business Understanding|How do we translate the business problem into a technical formulation?
Business Understanding|What does technical success look like?
Business Understanding|What is the step-by-step roadmap?
Business Understanding|Which tools and techniques will we use?
Data Understanding|Select the model formulation and document the rationale
Data Understanding|Derive data requirements from the chosen model's symbols
Data Understanding|Decide N (locations) and T (historical samples)
Data Understanding|Evaluate candidate public datasets against the requirements
Data Preparation|Build the toy dataset
Data Preparation|Derive holding, penalty, and transport costs for real data
Modeling|Implement the SAA model in a solver
Modeling|Implement the decentralized baseline
Modeling|Implement the fixed pooling variant
Evaluation|Compare model cost vs. baseline cost
Evaluation|Add out-of-sample (train/test) evaluation
Evaluation|Risk: SAA misses unobserved demand when T is small
Deployment|Build the dashboard (stock per location, fulfillment plan, cost vs. baseline)
Deployment|Package the sprint deliverable for stakeholders
EOF
)

# ---------- Create issues (if missing) and make sure each is on the Project ----------
# Safe to re-run: existing issues and existing board items are reused, not duplicated.
ISSUES=$(gh issue list --repo "$OWNER/$REPO" --state all --limit 500 --json title,url)

# Phase labels (created if missing; --force updates an existing label instead of failing)
for l in business-understanding data-understanding data-preparation modeling evaluation deployment; do
  gh label create "phase:$l" --repo "$OWNER/$REPO" --force </dev/null >/dev/null
done

# Load the board once (one API call instead of one per issue)
BOARD=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 500 --format json </dev/null)

while IFS='|' read -r -u 3 type title; do
  [ -z "$title" ] && continue

  # 1. Issue: reuse if it exists, otherwise create it
  label="phase:$(echo "$type" | tr 'A-Z ' 'a-z-')"
  url=$(echo "$ISSUES" | jq -r --arg t "$title" '.[] | select(.title==$t) | .url' | head -n1)
  if [ -z "$url" ]; then
    url=$(gh issue create --repo "$OWNER/$REPO" --title "$title" \
          --body "Item Type: $type"$'\n'"Status: Captured" \
          --label "$label" </dev/null)
  else
    # existing issue (e.g. created by hand): make sure it carries the phase label
    gh issue edit "$url" --add-label "$label" </dev/null >/dev/null
  fi

  # 2. Board item: use the cached board (loaded once, to stay under the API rate
  #    limit). If the issue is already on the board with its Item Type set, skip it.
  row=$(echo "$BOARD" | jq -c --arg u "$url" --arg t "$title" \
        '[.items[] | select(.content.url==$u or .content.title==$t)] | first // empty')
  item_id=$(echo "$row" | jq -r '.id // empty' 2>/dev/null || true)
  current=$(echo "$row" | jq -r '(.["item Type"] // .["Item Type"]) // empty' 2>/dev/null || true)
  if [ -n "$item_id" ] && [ "$current" = "$type" ]; then
    echo "Skip (already complete): $title"
    continue
  fi
  if [ -z "$item_id" ]; then
    item_id=$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" \
          --url "$url" --format json </dev/null 2>/dev/null | jq -r '.id // empty' || true)
    if [ -z "$item_id" ]; then
      # already on the board (e.g. added by an auto-add workflow): look it up once
      item_id=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 500 \
            --format json </dev/null \
            | jq -r --arg u "$url" --arg t "$title" \
              '[.items[] | select(.content.url==$u or .content.title==$t)] | first | .id // empty')
    fi
  fi
  [ -n "$item_id" ] || { echo "Could not place on board: $title"; continue; }

  # 3. Set Item Type
  opt_id=$(echo "$FIELDS" | jq -r --arg n "$type" \
        '.fields[] | select(.name=="Item Type") | .options[] | select(.name==$n) | .id')

  gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" \
        --field-id "$TYPE_FIELD_ID" --single-select-option-id "$opt_id" </dev/null

  echo "Added: [$type] $title"
done 3<<<"$ITEMS"

cat <<'MSG'

Done. Two fields still need a one-minute manual step in the Project settings
(the GitHub CLI cannot create or edit them):
  1. Status   -> edit the built-in field to: Captured, Refined, Ready, In Sprint, Done
  2. Sprint   -> add a new field of type "Iteration"
MSG
