#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ] || [[ "$1" != */* ]]; then
  echo "usage: $0 <owner/repo>" >&2
  exit 2
fi

repo="$1"
here="$(cd "$(dirname "$0")" && pwd)"
expected_file="$here/expected-settings.json"

command -v gh >/dev/null || { echo "gh is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

api() { gh api -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }

api -X PATCH "repos/$repo" --input - >/dev/null <<JSON
{
  "allow_squash_merge": true,
  "allow_rebase_merge": false,
  "allow_merge_commit": false,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "COMMIT_MESSAGES",
  "delete_branch_on_merge": true,
  "security_and_analysis": {
    "secret_scanning": {"status": "enabled"},
    "secret_scanning_push_protection": {"status": "enabled"}
  }
}
JSON

api -X PUT "repos/$repo/vulnerability-alerts" >/dev/null
api -X PUT "repos/$repo/private-vulnerability-reporting" >/dev/null

api -X PUT "repos/$repo/actions/permissions/workflow" --input - >/dev/null <<JSON
{"default_workflow_permissions": "read", "can_approve_pull_request_reviews": false}
JSON

api -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" --input - >/dev/null <<JSON
{"approval_policy": "all_external_contributors"}
JSON

ruleset_body='{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "required_linear_history"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "required_review_thread_resolution": true,
      "dismiss_stale_reviews_on_push": false,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "allowed_merge_methods": ["squash"]
    }},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": true,
      "do_not_enforce_on_create": false,
      "required_status_checks": [
        {"context": "verify", "integration_id": 15368}
      ]
    }}
  ]
}'

ruleset_id="$(api "repos/$repo/rulesets" --jq '.[] | select(.name == "main-protection") | .id' | head -n1)"
if [ -n "$ruleset_id" ]; then
  printf '%s' "$ruleset_body" | api -X PUT "repos/$repo/rulesets/$ruleset_id" --input - >/dev/null
else
  printf '%s' "$ruleset_body" | api -X POST "repos/$repo/rulesets" --input - >/dev/null
  ruleset_id="$(api "repos/$repo/rulesets" --jq '.[] | select(.name == "main-protection") | .id' | head -n1)"
fi

if api "repos/$repo/labels/dependencies" >/dev/null 2>&1; then
  api -X PATCH "repos/$repo/labels/dependencies" -f color=0366d6 -f description="Dependency updates" >/dev/null
else
  api -X POST "repos/$repo/labels" -f name=dependencies -f color=0366d6 -f description="Dependency updates" >/dev/null
fi

repo_json="$(api "repos/$repo")"
if api "repos/$repo/vulnerability-alerts" >/dev/null 2>&1; then dependabot=true; else dependabot=false; fi
pvr_json="$(api "repos/$repo/private-vulnerability-reporting")"
wf_json="$(api "repos/$repo/actions/permissions/workflow")"
fork_json="$(api "repos/$repo/actions/permissions/fork-pr-contributor-approval")"
rs_json="$(api "repos/$repo/rulesets/$ruleset_id")"
label_json="$(api "repos/$repo/labels/dependencies")"

actual="$(jq -n \
  --argjson repo "$repo_json" \
  --argjson dependabot "$dependabot" \
  --argjson pvr "$pvr_json" \
  --argjson wf "$wf_json" \
  --argjson fork "$fork_json" \
  --argjson rs "$rs_json" \
  --argjson label "$label_json" '{
    repo: {
      allow_rebase_merge: $repo.allow_rebase_merge,
      allow_squash_merge: $repo.allow_squash_merge,
      allow_merge_commit: $repo.allow_merge_commit,
      squash_merge_commit_title: $repo.squash_merge_commit_title,
      squash_merge_commit_message: $repo.squash_merge_commit_message,
      delete_branch_on_merge: $repo.delete_branch_on_merge,
      secret_scanning: $repo.security_and_analysis.secret_scanning.status,
      secret_scanning_push_protection: $repo.security_and_analysis.secret_scanning_push_protection.status
    },
    dependabot_alerts: $dependabot,
    private_vulnerability_reporting: $pvr.enabled,
    workflow_permissions: {
      default_workflow_permissions: $wf.default_workflow_permissions,
      can_approve_pull_request_reviews: $wf.can_approve_pull_request_reviews
    },
    fork_pr_approval: {approval_policy: $fork.approval_policy},
    ruleset: {
      name: $rs.name,
      target: $rs.target,
      enforcement: $rs.enforcement,
      bypass_actors: $rs.bypass_actors,
      include: $rs.conditions.ref_name.include,
      exclude: $rs.conditions.ref_name.exclude,
      rule_types: ([$rs.rules[].type] | sort),
      pull_request: ($rs.rules[] | select(.type == "pull_request") | .parameters
        | {required_approving_review_count, required_review_thread_resolution,
           dismiss_stale_reviews_on_push, require_code_owner_review,
           require_last_push_approval, allowed_merge_methods}),
      required_status_checks: ($rs.rules[] | select(.type == "required_status_checks") | .parameters
        | {strict_required_status_checks_policy,
           required_status_checks: (.required_status_checks | sort_by(.context))})
    },
    label: {name: $label.name}
  }')"

status=0
for key in $(jq -r 'keys[]' "$expected_file"); do
  if [ "$(jq -S ".$key" "$expected_file")" != "$(printf '%s' "$actual" | jq -S ".$key")" ]; then
    echo "MISMATCH: $key" >&2
    echo "  expected: $(jq -c ".$key" "$expected_file")" >&2
    echo "  actual:   $(printf '%s' "$actual" | jq -c ".$key")" >&2
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  exit 1
fi
echo "all settings match"
