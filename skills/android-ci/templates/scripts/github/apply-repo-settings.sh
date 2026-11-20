#!/usr/bin/env bash
set -euo pipefail

check=0
print_expected=0
case "${1:-}" in
  --check) check=1; shift ;;
  --print-expected) print_expected=1; shift ;;
esac

if [ "$print_expected" -eq 0 ] && { [ "$#" -ne 1 ] || [[ "$1" != */* ]]; }; then
  echo "usage: $0 [--check] <owner/repo> | $0 --print-expected" >&2
  exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
project_file="${PROJECT_SETTINGS:-$here/project-settings.json}"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

[ -f "$project_file" ] || { echo "missing project-settings file: $project_file" >&2; exit 2; }
for key in release_reviewer_user_id release_app_id; do
  jq -e --arg k "$key" '(.[$k] | type) == "number" and .[$k] > 0 and .[$k] == (.[$k] | floor)' "$project_file" >/dev/null \
    || { echo "$project_file: $key must be a positive integer" >&2; exit 2; }
done

jq -e '(.main_bypass_actors // []) | type == "array" and all(.[];
    (.actor_id | type == "number" and . > 0 and . == floor)
    and (.actor_type | IN("RepositoryRole", "Team", "Integration", "OrganizationAdmin", "DeployKey"))
    and (.bypass_mode | IN("always", "pull_request", "exempt")))' "$project_file" >/dev/null \
  || { echo "$project_file: main_bypass_actors must be a list of {actor_id, actor_type, bypass_mode}" >&2; exit 2; }
expected_file="$(mktemp)"
trap 'rm -f "$expected_file"' EXIT
jq --slurpfile p "$project_file" '
  .environments.release.reviewers |= map(.id = $p[0].release_reviewer_user_id)
  | .release_tags.bypass_actors |= map(.actor_id = $p[0].release_app_id)
  | .ruleset.bypass_actors = ($p[0].main_bypass_actors // [])
' "$here/expected-settings.json" > "$expected_file"

if [ "$print_expected" -eq 1 ]; then
  cat "$expected_file"
  exit 0
fi

repo="$1"

command -v gh >/dev/null || { echo "gh is required" >&2; exit 2; }

api() { gh api -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }

api_or_null() {
  local out
  if out="$(api "$@" 2>/dev/null)"; then
    printf '%s' "$out"
  else
    printf 'null'
  fi
}

ruleset_id_by_name() {
  api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$1\") | .id" | head -n1
}

if [ "$check" -eq 0 ]; then

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
        {"context": "checks", "integration_id": 15368},
        {"context": "pr-rules", "integration_id": 15368},
        {"context": "analyze (java-kotlin)", "integration_id": 15368},
        {"context": "analyze (actions)", "integration_id": 15368},
        {"context": "ui-tests (phone-31)", "integration_id": 15368},
        {"context": "ui-tests (phone-37)", "integration_id": 15368},
        {"context": "ui-tests (tablet-37)", "integration_id": 15368},
        {"context": "release-smoke", "integration_id": 15368}
      ]
    }}
  ]
}'

ruleset_body="$(printf '%s' "$ruleset_body" | jq --slurpfile e "$expected_file" '.bypass_actors = $e[0].ruleset.bypass_actors')"

ruleset_id="$(ruleset_id_by_name main-protection)"
if [ -n "$ruleset_id" ]; then
  printf '%s' "$ruleset_body" | api -X PUT "repos/$repo/rulesets/$ruleset_id" --input - >/dev/null
else
  printf '%s' "$ruleset_body" | api -X POST "repos/$repo/rulesets" --input - >/dev/null
fi

if api "repos/$repo/labels/dependencies" >/dev/null 2>&1; then
  api -X PATCH "repos/$repo/labels/dependencies" -f color=0366d6 -f description="Dependency updates" >/dev/null
else
  api -X POST "repos/$repo/labels" -f name=dependencies -f color=0366d6 -f description="Dependency updates" >/dev/null
fi

while IFS= read -r env_name; do
  jq --arg n "$env_name" '.environments[$n] | {
    wait_timer: 0,
    prevent_self_review,
    can_admins_bypass,
    reviewers: [.reviewers[] | {type, id}],
    deployment_branch_policy
  }' "$expected_file" | api -X PUT "repos/$repo/environments/$env_name" --input - >/dev/null
  existing_policies="$(api "repos/$repo/environments/$env_name/deployment-branch-policies" --jq '.branch_policies[].name')"
  while IFS= read -r policy; do
    if ! printf '%s\n' "$existing_policies" | grep -Fxq -- "$policy"; then
      jq -n --arg n "$policy" '{name: $n, type: "branch"}' \
        | api -X POST "repos/$repo/environments/$env_name/deployment-branch-policies" --input - >/dev/null
    fi
  done < <(jq -r --arg n "$env_name" '.environments[$n].branch_policies[]' "$expected_file")
done < <(jq -r '.environments | keys[]' "$expected_file")

tag_body="$(jq '.release_tags | {
  name,
  target,
  enforcement,
  bypass_actors,
  conditions: {ref_name: {include, exclude: []}},
  rules: [.rule_types[] | {type: .}]
}' "$expected_file")"
tag_id="$(ruleset_id_by_name release-tags)"
if [ -n "$tag_id" ]; then
  printf '%s' "$tag_body" | api -X PUT "repos/$repo/rulesets/$tag_id" --input - >/dev/null
else
  printf '%s' "$tag_body" | api -X POST "repos/$repo/rulesets" --input - >/dev/null
fi

while IFS= read -r label_name; do
  case "$label_name" in
    "autorelease: pending") label_color=fbca04; label_description="A release PR is open" ;;
    "autorelease: tagged") label_color=0e8a16; label_description="The release PR is merged and tagged" ;;
    *) echo "no colour defined for label $label_name" >&2; exit 2 ;;
  esac
  encoded="$(jq -rn --arg n "$label_name" '$n|@uri')"
  if api "repos/$repo/labels/$encoded" >/dev/null 2>&1; then
    api -X PATCH "repos/$repo/labels/$encoded" -f color="$label_color" -f description="$label_description" >/dev/null
  else
    api -X POST "repos/$repo/labels" -f name="$label_name" -f color="$label_color" -f description="$label_description" >/dev/null
  fi
done < <(jq -r '.release_labels[]' "$expected_file")

api -X PUT "repos/$repo/immutable-releases" >/dev/null

fi

ruleset_id="$(ruleset_id_by_name main-protection)"

repo_json="$(api "repos/$repo")"
if api "repos/$repo/vulnerability-alerts" >/dev/null 2>&1; then dependabot=true; else dependabot=false; fi
pvr_json="$(api "repos/$repo/private-vulnerability-reporting")"
wf_json="$(api "repos/$repo/actions/permissions/workflow")"
fork_json="$(api "repos/$repo/actions/permissions/fork-pr-contributor-approval")"
if [ -n "$ruleset_id" ]; then
  rs_json="$(api_or_null "repos/$repo/rulesets/$ruleset_id")"
else
  rs_json=null
fi
label_json="$(api_or_null "repos/$repo/labels/dependencies")"

env_json() {
  local name="$1" e p sec
  e="$(api_or_null "repos/$repo/environments/$name")"
  p="$(api_or_null "repos/$repo/environments/$name/deployment-branch-policies")"
  sec="$(api_or_null "repos/$repo/environments/$name/secrets?per_page=100")"
  jq -n --argjson e "$e" --argjson p "$p" --argjson s "$sec" '
    if $e == null or $p == null or $s == null then null else
      ([$e.protection_rules[]? | select(.type == "required_reviewers")][0]) as $rr
      | {
          deployment_branch_policy: {
            custom_branch_policies: $e.deployment_branch_policy.custom_branch_policies,
            protected_branches: $e.deployment_branch_policy.protected_branches
          },
          branch_policies: ([$p.branch_policies[]? | select(.type == "branch") | .name] | sort),
          reviewers: ([$rr.reviewers[]? | {type, id: .reviewer.id}] | sort_by(.id)),
          prevent_self_review: ($rr.prevent_self_review // false),
          can_admins_bypass: $e.can_admins_bypass,
          secrets: ([$s.secrets[]?.name] | sort)
        }
    end'
}

envs_json='{}'
for env_name in $(jq -r '.environments | keys[]' "$expected_file"); do
  one="$(env_json "$env_name")"
  envs_json="$(jq -n --argjson all "$envs_json" --arg n "$env_name" --argjson v "$one" '$all + {($n): $v}')"
done
envs_json="$(printf '%s' "$envs_json" | jq 'if any(.[]; . == null) then null else . end')"

vars_resp="$(api_or_null "repos/$repo/actions/variables?per_page=100")"
vars_json="$(jq -n --argjson v "$vars_resp" 'if $v == null then null else [$v.variables[]?.name] | sort end')"

tag_id="$(ruleset_id_by_name release-tags)"
if [ -n "$tag_id" ]; then
  tag_json="$(api_or_null "repos/$repo/rulesets/$tag_id")"
else
  tag_json=null
fi

labels_json='[]'
while IFS= read -r label_name; do
  encoded="$(jq -rn --arg n "$label_name" '$n|@uri')"
  lbl="$(api_or_null "repos/$repo/labels/$encoded")"
  labels_json="$(jq -n --argjson all "$labels_json" --argjson l "$lbl" 'if $all == null or $l == null then null else $all + [$l.name] end')"
done < <(jq -r '.release_labels[]' "$expected_file")
labels_json="$(printf '%s' "$labels_json" | jq 'if . == null then null else sort end')"

imm_resp="$(api_or_null "repos/$repo/immutable-releases")"
imm_json="$(jq -n --argjson i "$imm_resp" 'if $i == null then null else {enabled: $i.enabled} end')"

actual="$(jq -n \
  --argjson repo "$repo_json" \
  --argjson dependabot "$dependabot" \
  --argjson pvr "$pvr_json" \
  --argjson wf "$wf_json" \
  --argjson fork "$fork_json" \
  --argjson rs "$rs_json" \
  --argjson label "$label_json" \
  --argjson envs "$envs_json" \
  --argjson vars "$vars_json" \
  --argjson tag "$tag_json" \
  --argjson labels "$labels_json" \
  --argjson imm "$imm_json" '{
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
    ruleset: (if $rs == null then null else {
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
    } end),
    label: (if $label == null then null else {name: $label.name} end),
    environments: $envs,
    variables: $vars,
    release_tags: (if $tag == null then null else {
      name: $tag.name,
      target: $tag.target,
      enforcement: $tag.enforcement,
      include: $tag.conditions.ref_name.include,
      rule_types: ([$tag.rules[].type] | sort),
      bypass_actors: ([$tag.bypass_actors[] | {actor_id, actor_type, bypass_mode}] | sort_by(.actor_id))
    } end),
    release_labels: $labels,
    immutable_releases: $imm
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
