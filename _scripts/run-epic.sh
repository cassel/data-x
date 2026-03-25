#!/bin/bash
# ==============================================================================
# run-epic.sh — Unified BMAD Epic Development Pipeline
# ==============================================================================
# Reads sprint-status.yaml to auto-discover pending stories, then orchestrates
# create-story → dev-story → code-review → commit for each one.
# Works on any BMAD project (bmm or gds).
# Supports both Claude Code CLI and OpenAI Codex CLI via --agent flag.
#
# Usage:
#   ./_scripts/run-epic.sh --epic 2                    # All pending stories in epic 2
#   ./_scripts/run-epic.sh --epic 2 --from 2-8         # Start from story 2-8
#   ./_scripts/run-epic.sh --dry-run                   # Show plan for ALL pending stories
#   ./_scripts/run-epic.sh --epic 2 --parallel 3       # 3 stories in parallel
#   ./_scripts/run-epic.sh --status                    # Dashboard of all stories
#   ./_scripts/run-epic.sh --epic 2 --adversarial      # Extra adversarial review
#   ./_scripts/run-epic.sh --merge-only                # Merge existing epic/* branches
#   ./_scripts/run-epic.sh --epic 2 --agent codex      # Use Codex instead of Claude
#   ./_scripts/run-epic.sh --agent codex --model o4-mini --epic 2
#
# Options:
#   --epic <N>           Filter to stories in epic N
#   --from <prefix>      Start from story matching prefix (e.g., 2-8)
#   --parallel <N>       Run N stories in parallel via git worktrees (default: 1)
#   --adversarial        Add adversarial review before code-review
#   --retry <N>          Retry failed dev phase up to N times (default: 0)
#   --no-review          Skip code-review phase
#   --no-create          Skip story creation (backlog stories skipped)
#   --force              Process even "done" stories
#   --cooldown <secs>    Pause between stories in sequential mode (default: 10)
#   --dry-run            Show execution plan without running
#   --status             Show sprint dashboard without running anything
#   --merge-only         Merge existing epic/* branches into main
#   --agent <name>       AI agent CLI: claude | codex (default: claude)
#   --model <model>      Model override for the agent CLI
#   --log-dir <path>     Log directory (default: .logs/epic-pipeline/)
#   --help               Show this help message
#
# Story Processing (based on sprint-status.yaml):
#   done           → skip
#   review         → [adversarial] → code-review → commit
#   in-progress    → dev-story → [adversarial] → code-review → commit
#   ready-for-dev  → dev-story → [adversarial] → code-review → commit
#   backlog        → create-story → dev-story → [adversarial] → code-review → commit
# ==============================================================================

set -euo pipefail

# ── Portable relpath (macOS lacks realpath --relative-to) ─────────────────────
relpath() {
  python3 -c "import os; print(os.path.relpath('$1', '${2:-$PWD}'))"
}

# ── Detect PROJECT_ROOT by walking up to find _bmad/ ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_project_root() {
  local dir="$SCRIPT_DIR"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/_bmad" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo ""
  return 1
}

PROJECT_ROOT="$(find_project_root)"
if [ -z "$PROJECT_ROOT" ]; then
  echo "ERROR: Not in a BMAD project (_bmad/ not found in any parent directory)"
  exit 1
fi

# ── Configuration ─────────────────────────────────────────────────────────────
LOG_DIR="${PROJECT_ROOT}/.logs/epic-pipeline"
WORKTREE_BASE="${PROJECT_ROOT}/.worktrees"
COOLDOWN=10
PARALLEL=1
DRY_RUN=false
NO_REVIEW=false
NO_CREATE=false
ADVERSARIAL=false
MAX_RETRIES=0
STATUS_ONLY=false
FORCE=false
MERGE_ONLY=false
EPIC_FILTER=""
FROM_PREFIX=""
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
PIPELINE_START=0
AGENT_CLI="claude"   # claude | codex
AGENT_MODEL=""       # optional model override

# Auto-detected from BMAD config
IMPL_ARTIFACTS=""
SPRINT_STATUS=""
SKILL_PREFIX="bmad"
DEFAULT_BRANCH=""

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
  local level="$1"; shift
  local ts; ts=$(date +"%H:%M:%S")
  case "$level" in
    INFO)  echo -e "${BLUE}[$ts]${NC} ${BOLD}INFO${NC}  $*" ;;
    OK)    echo -e "${GREEN}[$ts]${NC} ${GREEN}${BOLD}OK${NC}    $*" ;;
    WARN)  echo -e "${YELLOW}[$ts]${NC} ${YELLOW}${BOLD}WARN${NC}  $*" ;;
    ERROR) echo -e "${RED}[$ts]${NC} ${RED}${BOLD}ERROR${NC} $*" ;;
    STEP)  echo -e "${CYAN}[$ts]${NC} ${CYAN}${BOLD}STEP${NC}  $*" ;;
  esac
  echo "[$ts] $level $*" >> "${LOG_DIR}/run-${TIMESTAMP}.log" 2>/dev/null || true
}

separator() {
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  $1${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
  echo ""
}

usage() {
  head -n 42 "$0" | tail -n +2 | sed 's/^# //' | sed 's/^#//'
  exit 0
}

# Format seconds as Xm Ys
fmt_duration() {
  local secs=$1
  if [ "$secs" -ge 60 ]; then
    printf "%dm %ds" $((secs / 60)) $((secs % 60))
  else
    printf "%ds" "$secs"
  fi
}

# ── BMAD Config Detection ────────────────────────────────────────────────────
load_bmad_config() {
  local config_file=""

  # Detect which BMAD module is installed (gds for games, bmm for general)
  for candidate in \
    "$PROJECT_ROOT/_bmad/gds/config.yaml" \
    "$PROJECT_ROOT/_bmad/bmm/config.yaml"; do
    if [ -f "$candidate" ]; then
      config_file="$candidate"
      break
    fi
  done

  if [ -z "$config_file" ]; then
    log ERROR "No BMAD config found (_bmad/bmm/config.yaml or _bmad/gds/config.yaml)"
    exit 1
  fi

  # Detect skill prefix from config path
  if [[ "$config_file" == *"/gds/"* ]]; then
    SKILL_PREFIX="gds"
  else
    SKILL_PREFIX="bmad"
  fi

  # Extract implementation_artifacts path, resolve {project-root}
  IMPL_ARTIFACTS=$(grep '^implementation_artifacts:' "$config_file" \
    | sed 's/^implementation_artifacts: *//' \
    | sed 's/^"//' | sed 's/"$//' \
    | sed "s|{project-root}|$PROJECT_ROOT|")

  if [ -z "$IMPL_ARTIFACTS" ]; then
    # Fallback to default
    IMPL_ARTIFACTS="${PROJECT_ROOT}/_bmad-output/implementation-artifacts"
  fi

  SPRINT_STATUS="${IMPL_ARTIFACTS}/sprint-status.yaml"

  log INFO "Config:       $config_file"
  log INFO "Skills:       ${SKILL_PREFIX}-*"
  log INFO "Artifacts:    $(relpath "$IMPL_ARTIFACTS" "$PROJECT_ROOT")"
}

# ── Prerequisites ─────────────────────────────────────────────────────────────
check_prerequisites() {
  if ! command -v "$AGENT_CLI" &> /dev/null; then
    case "$AGENT_CLI" in
      claude) log ERROR "claude CLI not found. Install: https://docs.anthropic.com/en/docs/claude-code" ;;
      codex)  log ERROR "codex CLI not found. Install: npm i -g @openai/codex" ;;
      *)      log ERROR "$AGENT_CLI CLI not found." ;;
    esac
    exit 1
  fi

  if [ ! -f "$SPRINT_STATUS" ]; then
    log ERROR "Sprint status not found: $SPRINT_STATUS"
    log ERROR "Run sprint-planning first to generate sprint-status.yaml"
    exit 1
  fi

  if [ "$PARALLEL" -gt 1 ]; then
    if ! git -C "$PROJECT_ROOT" rev-parse HEAD &>/dev/null; then
      log ERROR "No commits found. Parallel mode needs an initial commit."
      log ERROR "Run: git add -A && git commit -m 'initial commit'"
      exit 1
    fi
    # Auto-detect default branch (main or master)
    DEFAULT_BRANCH=$(git -C "$PROJECT_ROOT" symbolic-ref --short HEAD 2>/dev/null || echo "main")
    log INFO "Git branch:   $DEFAULT_BRANCH"
  fi
}

# ── Sprint Status Parsing ────────────────────────────────────────────────────
# Builds STORY_KEYS and STORY_STATUSES parallel arrays from sprint-status.yaml
STORY_KEYS=()
STORY_STATUSES=()

build_story_queue() {
  local in_dev_status=false

  while IFS= read -r line; do
    # Detect development_status section
    if [[ "$line" =~ ^development_status: ]]; then
      in_dev_status=true
      continue
    fi

    # Exit if we hit a non-indented line after development_status
    if [ "$in_dev_status" = true ] && [[ ! "$line" =~ ^[[:space:]] ]] && [ -n "$line" ]; then
      break
    fi

    [ "$in_dev_status" = false ] && continue

    # Match story lines: "  2-8-checkpoint-system: backlog"
    # Skip epic lines (epic-N) and retrospective lines (epic-N-retrospective)
    if [[ "$line" =~ ^[[:space:]]+([0-9]+-[0-9]+-[a-z0-9-]+):[[:space:]]*(.*) ]]; then
      local key="${BASH_REMATCH[1]}"
      local status="${BASH_REMATCH[2]}"
      # Clean whitespace and comments
      status=$(echo "$status" | sed 's/#.*//' | tr -d ' ')

      # Apply --epic filter
      if [ -n "$EPIC_FILTER" ] && [[ ! "$key" =~ ^${EPIC_FILTER}- ]]; then
        continue
      fi

      # Skip done stories unless --force
      if [ "$FORCE" = false ] && [ "$status" = "done" ]; then
        continue
      fi

      STORY_KEYS+=("$key")
      STORY_STATUSES+=("$status")
    fi
  done < "$SPRINT_STATUS"

  # Apply --from filter (drop everything before the prefix match)
  if [ -n "$FROM_PREFIX" ]; then
    local filtered_keys=()
    local filtered_statuses=()
    local found=false
    for i in "${!STORY_KEYS[@]}"; do
      if [ "$found" = true ] || [[ "${STORY_KEYS[$i]}" =~ ^${FROM_PREFIX} ]]; then
        found=true
        filtered_keys+=("${STORY_KEYS[$i]}")
        filtered_statuses+=("${STORY_STATUSES[$i]}")
      fi
    done
    if [ "$found" = false ]; then
      log ERROR "No story matching prefix '$FROM_PREFIX' found"
      exit 1
    fi
    STORY_KEYS=("${filtered_keys[@]}")
    STORY_STATUSES=("${filtered_statuses[@]}")
  fi

  if [ ${#STORY_KEYS[@]} -eq 0 ]; then
    log OK "No pending stories found. All done!"
    exit 0
  fi
}

# Get the action plan for a story based on its status
story_action() {
  local status="$1"
  local adv=""
  [ "$ADVERSARIAL" = true ] && adv="adversarial -> "
  local rev="review -> "
  [ "$NO_REVIEW" = true ] && rev=""
  case "$status" in
    done)          echo "skip" ;;
    review)        echo "${adv}${rev}commit" ;;
    in-progress)   echo "dev -> ${adv}${rev}commit" ;;
    ready-for-dev) echo "dev -> ${adv}${rev}commit" ;;
    backlog)       echo "create -> dev -> ${adv}${rev}commit" ;;
    *)             echo "unknown ($status)" ;;
  esac
}

# Re-read a story's current status from sprint-status.yaml
refresh_status() {
  local key="$1"
  grep -E "^\s+${key}:" "$SPRINT_STATUS" 2>/dev/null \
    | sed 's/.*:\s*//' | sed 's/#.*//' | tr -d ' ' || echo "unknown"
}

# ── Build Agent Command ───────────────────────────────────────────────────────
# Populates global AGENT_CMD array with the correct CLI invocation
build_agent_cmd() {
  local prompt="$1"
  AGENT_CMD=()

  case "$AGENT_CLI" in
    claude)
      AGENT_CMD=(env -u CLAUDECODE claude --dangerously-skip-permissions)
      [ -n "$AGENT_MODEL" ] && AGENT_CMD+=(--model "$AGENT_MODEL")
      AGENT_CMD+=(-p "$prompt")
      ;;
    codex)
      AGENT_CMD=(codex exec --dangerously-bypass-approvals-and-sandbox)
      [ -n "$AGENT_MODEL" ] && AGENT_CMD+=(-m "$AGENT_MODEL")
      AGENT_CMD+=("$prompt")
      ;;
    *)
      log ERROR "Unknown agent CLI: $AGENT_CLI"
      return 1
      ;;
  esac
}

# ── Run Agent ─────────────────────────────────────────────────────────────────
run_claude() {
  local description="$1"
  local prompt="$2"
  local log_file="$3"
  local work_dir="${4:-$PROJECT_ROOT}"

  if [ "$DRY_RUN" = true ]; then
    log INFO "[DRY RUN] Would execute ($AGENT_CLI): \"${prompt:0:80}...\""
    return 0
  fi

  log STEP "$description"
  log INFO "Agent: $AGENT_CLI${AGENT_MODEL:+ (model: $AGENT_MODEL)}"
  log INFO "Log: $log_file"

  # Prepend autonomy instructions
  local full_prompt="You are running in a fully autonomous pipeline -- do NOT ask questions, do NOT wait for input. If you need to choose an option, always choose the most productive one. Proceed immediately without confirmation. ${prompt}"

  build_agent_cmd "$full_prompt"

  if (cd "$work_dir" && "${AGENT_CMD[@]}" < /dev/null > "$log_file" 2>&1); then
    if grep -q "Unknown skill" "$log_file" 2>/dev/null; then
      log ERROR "$description — skill not found"
      return 1
    fi
    log OK "$description — completed"
    return 0
  else
    local exit_code=$?
    log ERROR "$description — failed (exit code: $exit_code)"
    log ERROR "Check log: $log_file"
    return $exit_code
  fi
}

# ── Story Processing Phases ───────────────────────────────────────────────────

phase_create() {
  local story_key="$1"
  local work_dir="${2:-$PROJECT_ROOT}"

  if [ "$NO_CREATE" = true ]; then
    log WARN "Skipping create (--no-create): $story_key"
    return 0
  fi

  local log_file="${LOG_DIR}/${TIMESTAMP}-create-${story_key}.log"
  # Pass the story identifier (e.g., "2-8") so the skill knows which story to create
  local story_id="${story_key%%-*}"  # epic num
  local story_num
  story_num=$(echo "$story_key" | sed 's/^[0-9]*-//' | sed 's/-.*//')
  run_claude \
    "Creating story: $story_key" \
    "/${SKILL_PREFIX}-create-story ${story_id}-${story_num}" \
    "$log_file" \
    "$work_dir"
}

phase_dev() {
  local story_key="$1"
  local work_dir="${2:-$PROJECT_ROOT}"
  local impl_dir="$IMPL_ARTIFACTS"
  [ "$work_dir" != "$PROJECT_ROOT" ] && impl_dir="${work_dir}/_bmad-output/implementation-artifacts"

  local story_file
  story_file=$(relpath "${impl_dir}/${story_key}.md" "$work_dir")

  local log_file="${LOG_DIR}/${TIMESTAMP}-dev-${story_key}.log"
  run_claude \
    "Developing: $story_key" \
    "/${SKILL_PREFIX}-dev-story ${story_file}" \
    "$log_file" \
    "$work_dir" || return 1

  # Verify dev produced changes
  if [ "$DRY_RUN" = false ]; then
    if (cd "$work_dir" && git diff --quiet 2>/dev/null && git diff --staged --quiet 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]); then
      log WARN "Dev produced no file changes for: $story_key"
    else
      log OK "Dev produced changes for: $story_key"
    fi
  fi
}

phase_review() {
  local story_key="$1"
  local work_dir="${2:-$PROJECT_ROOT}"
  local impl_dir="$IMPL_ARTIFACTS"
  [ "$work_dir" != "$PROJECT_ROOT" ] && impl_dir="${work_dir}/_bmad-output/implementation-artifacts"

  local story_file
  story_file=$(relpath "${impl_dir}/${story_key}.md" "$work_dir")

  local log_file="${LOG_DIR}/${TIMESTAMP}-review-${story_key}.log"
  run_claude \
    "Code review: $story_key" \
    "/${SKILL_PREFIX}-code-review ${story_file}" \
    "$log_file" \
    "$work_dir" || return 1

  log OK "Code review complete: $story_key"
}

phase_adversarial() {
  local story_key="$1"
  local work_dir="${2:-$PROJECT_ROOT}"
  local impl_dir="$IMPL_ARTIFACTS"
  [ "$work_dir" != "$PROJECT_ROOT" ] && impl_dir="${work_dir}/_bmad-output/implementation-artifacts"

  local story_file
  story_file=$(relpath "${impl_dir}/${story_key}.md" "$work_dir")

  local log_file="${LOG_DIR}/${TIMESTAMP}-adversarial-${story_key}.log"
  run_claude \
    "Adversarial review: $story_key" \
    "/bmad-review-adversarial-general Perform a cynical adversarial review of all code changes for story '${story_file}'. Read the story file for context, then review all source files listed in its File List section. Find 3-10 specific problems. Be ruthless." \
    "$log_file" \
    "$work_dir" || return 1

  log OK "Adversarial review complete: $story_key"
}

phase_commit() {
  local story_key="$1"
  local work_dir="${2:-$PROJECT_ROOT}"

  if [ "$DRY_RUN" = true ]; then
    log INFO "[DRY RUN] Would commit: $story_key"
    return 0
  fi

  cd "$work_dir"

  # Check for changes
  if git diff --quiet 2>/dev/null && git diff --staged --quiet 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    log WARN "No changes to commit for: $story_key"
    return 0
  fi

  # Extract title from story file
  local impl_dir="$IMPL_ARTIFACTS"
  [ "$work_dir" != "$PROJECT_ROOT" ] && impl_dir="${work_dir}/_bmad-output/implementation-artifacts"
  local title
  title=$(grep -m1 '^# ' "${impl_dir}/${story_key}.md" 2>/dev/null \
    | sed 's/^# Story [A-Z0-9.]*: //' \
    | sed 's/^# //' \
    || echo "$story_key")

  local epic_num="${story_key%%-*}"

  git add -A
  git commit -m "$(cat <<EOF
feat(epic-${epic_num}): implement ${title}

Story: _bmad-output/implementation-artifacts/${story_key}.md
EOF
)"
  log OK "Committed: $story_key"
  cd "$PROJECT_ROOT"
}

# Process a single story through the full pipeline based on its status
process_story() {
  local story_key="$1"
  local status="$2"
  local work_dir="${3:-$PROJECT_ROOT}"
  local story_start=$SECONDS

  if [ "$status" = "done" ]; then
    log OK "Already done: $story_key"
    return 0
  fi

  if [ "$status" = "unknown" ] || [ -z "$status" ]; then
    log WARN "Unknown status '$status' for $story_key — skipping"
    return 1
  fi

  # State machine: backlog → create → dev → [adversarial] → review → commit

  # ── CREATE ──
  if [ "$status" = "backlog" ]; then
    local t=$SECONDS
    phase_create "$story_key" "$work_dir" || return 1
    log INFO "Create took $(fmt_duration $((SECONDS - t)))"
    if [ "$DRY_RUN" = false ]; then
      status=$(refresh_status "$story_key")
      log INFO "Status after create: $status"
    fi
    status="ready-for-dev"
  fi

  # ── DEV (with retry) ──
  if [ "$status" = "ready-for-dev" ] || [ "$status" = "in-progress" ]; then
    local attempt=0
    local dev_ok=false
    while [ $attempt -le "$MAX_RETRIES" ]; do
      local t=$SECONDS
      if phase_dev "$story_key" "$work_dir"; then
        log INFO "Dev took $(fmt_duration $((SECONDS - t)))"
        dev_ok=true
        break
      else
        ((attempt++)) || true
        if [ $attempt -le "$MAX_RETRIES" ]; then
          log WARN "Dev failed (attempt $attempt/$((MAX_RETRIES + 1))). Retrying in 5s..."
          sleep 5
        fi
      fi
    done
    if [ "$dev_ok" = false ]; then
      log ERROR "Dev failed after $((MAX_RETRIES + 1)) attempt(s): $story_key"
      return 1
    fi
    status="review"
  fi

  # ── ADVERSARIAL REVIEW (optional) ──
  if [ "$status" = "review" ] && [ "$ADVERSARIAL" = true ]; then
    local t=$SECONDS
    phase_adversarial "$story_key" "$work_dir" || log WARN "Adversarial review had issues: $story_key (continuing)"
    log INFO "Adversarial review took $(fmt_duration $((SECONDS - t)))"
  fi

  # ── CODE REVIEW ──
  if [ "$status" = "review" ]; then
    if [ "$NO_REVIEW" = false ]; then
      local t=$SECONDS
      phase_review "$story_key" "$work_dir" || log WARN "Review had issues: $story_key (continuing)"
      log INFO "Code review took $(fmt_duration $((SECONDS - t)))"
    fi
    phase_commit "$story_key" "$work_dir" || log WARN "Commit failed: $story_key"
  fi

  local elapsed=$((SECONDS - story_start))
  log OK "Story $story_key completed in $(fmt_duration $elapsed)"
}

# ── Sequential Mode ──────────────────────────────────────────────────────────
run_sequential() {
  local total=${#STORY_KEYS[@]}
  local succeeded=0 failed=0

  for i in "${!STORY_KEYS[@]}"; do
    local key="${STORY_KEYS[$i]}"
    local status="${STORY_STATUSES[$i]}"
    local num=$((i + 1))

    separator "[$num/$total] $key ($status)"

    if process_story "$key" "$status"; then
      ((succeeded++)) || true
    else
      log ERROR "Failed: $key"
      ((failed++)) || true
    fi

    # Cooldown between stories
    if [ $num -lt $total ] && [ "$DRY_RUN" = false ]; then
      log INFO "Cooldown: ${COOLDOWN}s..."
      sleep "$COOLDOWN"
    fi
  done

  print_summary $succeeded $failed $total
}

# ── Parallel Mode (git worktrees) ────────────────────────────────────────────
RESULTS_DIR=""

cleanup_worktrees() {
  if [ -d "$WORKTREE_BASE" ]; then
    log INFO "Cleaning up worktrees..."
    for wt in "$WORKTREE_BASE"/*/; do
      [ -d "$wt" ] || continue
      git -C "$PROJECT_ROOT" worktree remove --force "$wt" 2>/dev/null || true
    done
    rmdir "$WORKTREE_BASE" 2>/dev/null || true
  fi
  local unmerged
  unmerged=$(git -C "$PROJECT_ROOT" branch --list 'epic/*' --no-merged "$DEFAULT_BRANCH" 2>/dev/null || true)
  if [ -n "$unmerged" ]; then
    log WARN "Unmerged branches (work preserved):"
    echo "$unmerged" | while read -r b; do echo "  $b"; done
  fi
  [ -n "$RESULTS_DIR" ] && [ -d "$RESULTS_DIR" ] && rm -rf "$RESULTS_DIR"
}

process_story_worktree() {
  local story_key="$1"
  local status="$2"
  local branch="epic/${story_key}"
  local wt_path="${WORKTREE_BASE}/${story_key}"

  if [ "$DRY_RUN" = true ]; then
    log INFO "[DRY RUN] [parallel] $story_key ($status) → $(story_action "$status")"
    echo "0" > "${RESULTS_DIR}/${story_key}.result"
    return 0
  fi

  log STEP "Creating worktree: $story_key → $branch"

  # Create/reset branch
  if git -C "$PROJECT_ROOT" rev-parse --verify "$branch" &>/dev/null; then
    git -C "$PROJECT_ROOT" branch -f "$branch" "$DEFAULT_BRANCH" 2>/dev/null || true
  else
    git -C "$PROJECT_ROOT" branch "$branch" "$DEFAULT_BRANCH" 2>/dev/null || {
      log ERROR "Failed to create branch: $branch"
      echo "1" > "${RESULTS_DIR}/${story_key}.result"
      return 1
    }
  fi

  # Remove stale worktree
  [ -d "$wt_path" ] && (git -C "$PROJECT_ROOT" worktree remove --force "$wt_path" 2>/dev/null || rm -rf "$wt_path")

  git -C "$PROJECT_ROOT" worktree add "$wt_path" "$branch" 2>&1 || {
    log ERROR "Failed to create worktree: $wt_path"
    echo "1" > "${RESULTS_DIR}/${story_key}.result"
    return 1
  }

  # Symlink .claude/ so skills are available
  if [ -d "${PROJECT_ROOT}/.claude" ] && [ ! -e "${wt_path}/.claude" ]; then
    ln -s "${PROJECT_ROOT}/.claude" "${wt_path}/.claude"
    echo ".claude" >> "${wt_path}/.git/info/exclude"
  fi

  # Process the story
  if process_story "$story_key" "$status" "$wt_path"; then
    echo "0" > "${RESULTS_DIR}/${story_key}.result"
    log OK "[parallel] Done: $story_key"
  else
    echo "1" > "${RESULTS_DIR}/${story_key}.result"
    log ERROR "[parallel] Failed: $story_key"
  fi
}

merge_branches() {
  local merged=0 merge_failed=0

  separator "Merging branches into main"
  cd "$PROJECT_ROOT"

  for key in "${STORY_KEYS[@]}"; do
    local branch="epic/${key}"
    local result_file="${RESULTS_DIR}/${key}.result"

    # Skip failed stories
    if [ -f "$result_file" ] && [ "$(cat "$result_file")" != "0" ]; then
      log WARN "Skipping merge (failed): $key"
      continue
    fi

    git rev-parse --verify "$branch" &>/dev/null || continue

    local title
    title=$(grep -m1 '^# ' "${IMPL_ARTIFACTS}/${key}.md" 2>/dev/null \
      | sed 's/^# Story [A-Z0-9.]*: //' | sed 's/^# //' || echo "$key")

    log STEP "Merging: $branch → main"
    if git merge --no-ff "$branch" -m "$(cat <<EOF
feat(epic): implement $title

Story: _bmad-output/implementation-artifacts/${key}.md
EOF
)"; then
      log OK "Merged: $key"
      ((merged++)) || true
      # Cleanup
      local wt_path="${WORKTREE_BASE}/${key}"
      git worktree remove --force "$wt_path" 2>/dev/null || true
      git branch -d "$branch" 2>/dev/null || true
    else
      log ERROR "Merge conflict: $key — aborting"
      git merge --abort 2>/dev/null || true
      ((merge_failed++)) || true
      break
    fi
  done

  log INFO "Merged: $merged, Failed: $merge_failed"
  return $merge_failed
}

run_parallel() {
  local total=${#STORY_KEYS[@]}
  RESULTS_DIR=$(mktemp -d)
  mkdir -p "$WORKTREE_BASE"
  trap cleanup_worktrees EXIT

  # Phase 1: Create stories sequentially (sprint-status race condition prevention)
  local create_count=0
  for i in "${!STORY_KEYS[@]}"; do
    if [ "${STORY_STATUSES[$i]}" = "backlog" ]; then
      separator "Creating story: ${STORY_KEYS[$i]}"
      phase_create "${STORY_KEYS[$i]}" || log WARN "Create failed: ${STORY_KEYS[$i]}"
      ((create_count++)) || true
      # Update status after creation
      STORY_STATUSES[$i]=$(refresh_status "${STORY_KEYS[$i]}")
    fi
  done
  [ $create_count -gt 0 ] && log OK "Created $create_count stories"

  # Phase 2: Dev + review in parallel
  log INFO "Parallel mode: $PARALLEL workers, $total stories"

  local pids=()
  local slots=()
  for ((s=0; s<PARALLEL; s++)); do slots[$s]=0; done

  for i in "${!STORY_KEYS[@]}"; do
    local key="${STORY_KEYS[$i]}"
    local status="${STORY_STATUSES[$i]}"

    # Skip done and backlog (already handled or failed create)
    [ "$status" = "done" ] && continue
    [ "$status" = "backlog" ] && continue

    # Find a free slot
    local found_slot=false
    while [ "$found_slot" = false ]; do
      for ((s=0; s<PARALLEL; s++)); do
        if [ "${slots[$s]}" -eq 0 ]; then
          found_slot=true
          break
        fi
        if ! kill -0 "${slots[$s]}" 2>/dev/null; then
          wait "${slots[$s]}" 2>/dev/null || true
          slots[$s]=0
          found_slot=true
          break
        fi
      done
      [ "$found_slot" = false ] && sleep 1
    done

    log INFO "Launching: $key (slot $s)"
    process_story_worktree "$key" "$status" &
    slots[$s]=$!
    pids+=($!)
  done

  # Wait for all
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Count results
  local succeeded=0 failed=0
  for key in "${STORY_KEYS[@]}"; do
    local rf="${RESULTS_DIR}/${key}.result"
    if [ -f "$rf" ] && [ "$(cat "$rf")" = "0" ]; then
      ((succeeded++)) || true
    elif [ -f "$rf" ]; then
      ((failed++)) || true
    fi
  done

  log OK "Workers done. Succeeded: $succeeded, Failed: $failed"

  # Merge
  [ $succeeded -gt 0 ] && merge_branches

  print_summary $succeeded $failed $total
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  local succeeded=$1 failed=$2 total=$3
  local elapsed=$((SECONDS - PIPELINE_START))
  separator "Pipeline Complete"
  echo -e "  ${GREEN}Succeeded:${NC} $succeeded"
  echo -e "  ${RED}Failed:${NC}    $failed"
  echo -e "  ${BOLD}Total:${NC}     $total"
  echo -e "  ${BOLD}Duration:${NC}  $(fmt_duration $elapsed)"
  [ "$PARALLEL" -gt 1 ] && echo -e "  ${CYAN}Workers:${NC}   $PARALLEL"
  [ "$ADVERSARIAL" = true ] && echo -e "  ${YELLOW}Adversarial:${NC} on"
  [ "$MAX_RETRIES" -gt 0 ] && echo -e "  ${BLUE}Retries:${NC}   up to $MAX_RETRIES"
  echo ""
  log INFO "Logs: $LOG_DIR/"
  [ "$failed" -gt 0 ] && return 1
  return 0
}

# ── Status Dashboard ──────────────────────────────────────────────────────────
show_status() {
  separator "Sprint Dashboard — $(basename "$PROJECT_ROOT")"

  local total=0 done_count=0 review_count=0 in_progress_count=0 ready_count=0 backlog_count=0
  local in_dev_status=false
  local all_keys=() all_statuses=() all_epics=()

  while IFS= read -r line; do
    if [[ "$line" =~ ^development_status: ]]; then
      in_dev_status=true
      continue
    fi
    [ "$in_dev_status" = false ] && continue
    if [ "$in_dev_status" = true ] && [[ ! "$line" =~ ^[[:space:]] ]] && [ -n "$line" ]; then
      break
    fi
    if [[ "$line" =~ ^[[:space:]]+([0-9]+-[0-9]+-[a-z0-9-]+):[[:space:]]*(.*) ]]; then
      local key="${BASH_REMATCH[1]}"
      local status="${BASH_REMATCH[2]}"
      status=$(echo "$status" | sed 's/#.*//' | tr -d ' ')
      local epic="${key%%-*}"
      if [ -n "$EPIC_FILTER" ] && [ "$epic" != "$EPIC_FILTER" ]; then
        continue
      fi
      all_keys+=("$key")
      all_statuses+=("$status")
      all_epics+=("$epic")
      ((total++)) || true
      case "$status" in
        done)          ((done_count++)) || true ;;
        review)        ((review_count++)) || true ;;
        in-progress)   ((in_progress_count++)) || true ;;
        ready-for-dev) ((ready_count++)) || true ;;
        backlog)       ((backlog_count++)) || true ;;
      esac
    fi
  done < "$SPRINT_STATUS"

  # Progress bar
  local pct=0
  [ $total -gt 0 ] && pct=$((done_count * 100 / total))
  local bar_width=40
  local filled=$((pct * bar_width / 100))
  local empty=$((bar_width - filled))
  local bar=""
  for ((b=0; b<filled; b++)); do bar+="█"; done
  for ((b=0; b<empty; b++)); do bar+="░"; done

  echo -e "  ${BOLD}Progress:${NC} [${GREEN}${bar}${NC}] ${BOLD}${pct}%${NC} (${done_count}/${total} stories)"
  echo ""
  echo -e "  ${GREEN}■${NC} Done:          ${BOLD}${done_count}${NC}"
  echo -e "  ${CYAN}■${NC} Review:        ${BOLD}${review_count}${NC}"
  echo -e "  ${YELLOW}■${NC} In Progress:   ${BOLD}${in_progress_count}${NC}"
  echo -e "  ${BLUE}■${NC} Ready for Dev: ${BOLD}${ready_count}${NC}"
  echo -e "  ${DIM}■${NC} Backlog:       ${BOLD}${backlog_count}${NC}"
  echo ""

  # Per-epic summary
  echo -e "  ${BOLD}Per-Epic:${NC}"
  local prev_epic="" epic_total=0 epic_done=0
  for i in "${!all_keys[@]}"; do
    local epic="${all_epics[$i]}"
    if [ "$epic" != "$prev_epic" ]; then
      if [ -n "$prev_epic" ]; then
        local epct=0
        [ $epic_total -gt 0 ] && epct=$((epic_done * 100 / epic_total))
        echo -e "    Epic ${prev_epic}: ${epic_done}/${epic_total} done (${epct}%)"
      fi
      prev_epic="$epic"
      epic_total=0
      epic_done=0
    fi
    ((epic_total++)) || true
    [ "${all_statuses[$i]}" = "done" ] && ((epic_done++)) || true
  done
  if [ -n "$prev_epic" ]; then
    local epct=0
    [ $epic_total -gt 0 ] && epct=$((epic_done * 100 / epic_total))
    echo -e "    Epic ${prev_epic}: ${epic_done}/${epic_total} done (${epct}%)"
  fi
  echo ""

  # Pending stories
  local pending=$((total - done_count))
  if [ $pending -gt 0 ]; then
    echo -e "  ${BOLD}Pending (${pending}):${NC}"
    printf "    ${BOLD}%-35s %-15s${NC}\n" "Story Key" "Status"
    printf "    %-35s %-15s\n" "-----------------------------------" "---------------"
    for i in "${!all_keys[@]}"; do
      [ "${all_statuses[$i]}" = "done" ] && continue
      local sc="$NC"
      case "${all_statuses[$i]}" in
        review)        sc="$CYAN" ;;
        in-progress)   sc="$YELLOW" ;;
        ready-for-dev) sc="$BLUE" ;;
      esac
      printf "    %-35s ${sc}%-15s${NC}\n" "${all_keys[$i]}" "${all_statuses[$i]}"
    done
    echo ""
  else
    echo -e "  ${GREEN}${BOLD}All stories complete!${NC}"
    echo ""
  fi
}

# ── Parse Arguments ───────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --epic)
        EPIC_FILTER="$2"
        shift 2
        ;;
      --from)
        FROM_PREFIX="$2"
        shift 2
        ;;
      --parallel)
        PARALLEL="$2"
        if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [ "$PARALLEL" -lt 1 ]; then
          echo "ERROR: --parallel must be a positive integer"
          exit 1
        fi
        shift 2
        ;;
      --agent)
        AGENT_CLI="$2"
        if [[ "$AGENT_CLI" != "claude" && "$AGENT_CLI" != "codex" ]]; then
          echo "ERROR: Unsupported agent: $AGENT_CLI (use: claude, codex)"
          exit 1
        fi
        shift 2
        ;;
      --model)
        AGENT_MODEL="$2"
        shift 2
        ;;
      --adversarial)
        ADVERSARIAL=true
        shift
        ;;
      --retry)
        MAX_RETRIES="$2"
        if ! [[ "$MAX_RETRIES" =~ ^[0-9]+$ ]]; then
          echo "ERROR: --retry must be a non-negative integer"
          exit 1
        fi
        shift 2
        ;;
      --status)
        STATUS_ONLY=true
        shift
        ;;
      --no-review)
        NO_REVIEW=true
        shift
        ;;
      --no-create)
        NO_CREATE=true
        shift
        ;;
      --force)
        FORCE=true
        shift
        ;;
      --cooldown)
        COOLDOWN="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --merge-only)
        MERGE_ONLY=true
        shift
        ;;
      --log-dir)
        LOG_DIR="$2"
        shift 2
        ;;
      --help|-h)
        usage
        ;;
      *)
        echo "ERROR: Unknown option: $1"
        usage
        ;;
    esac
  done
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  mkdir -p "$LOG_DIR"

  load_bmad_config

  cd "$PROJECT_ROOT"

  # Status dashboard mode
  if [ "$STATUS_ONLY" = true ]; then
    show_status
    exit 0
  fi

  check_prerequisites

  # Detect default branch for git operations (even if not parallel, needed for merge-only)
  if [ -z "$DEFAULT_BRANCH" ] && git -C "$PROJECT_ROOT" rev-parse HEAD &>/dev/null; then
    DEFAULT_BRANCH=$(git -C "$PROJECT_ROOT" symbolic-ref --short HEAD 2>/dev/null || echo "main")
  fi

  PIPELINE_START=$SECONDS

  # Merge-only mode
  if [ "$MERGE_ONLY" = true ]; then
    separator "Merge-only mode"
    local branches
    branches=$(git branch --list 'epic/*' 2>/dev/null | sed 's/^[* ]*//')
    if [ -z "$branches" ]; then
      log OK "No epic/* branches to merge."
      exit 0
    fi
    RESULTS_DIR=$(mktemp -d)
    while IFS= read -r branch; do
      local sn="${branch#epic/}"
      STORY_KEYS+=("$sn")
      echo "0" > "${RESULTS_DIR}/${sn}.result"
    done <<< "$branches"
    merge_branches
    rm -rf "$RESULTS_DIR"
    exit 0
  fi

  # Build story queue from sprint-status.yaml
  build_story_queue

  # Show execution plan
  separator "Pipeline Plan"
  log INFO "Project:    $(basename "$PROJECT_ROOT")"
  log INFO "Agent:      $AGENT_CLI${AGENT_MODEL:+ (model: $AGENT_MODEL)}"
  log INFO "Timestamp:  $TIMESTAMP"
  log INFO "Mode:       $([ "$PARALLEL" -gt 1 ] && echo "parallel ($PARALLEL workers)" || echo "sequential")"
  log INFO "Review:     $([ "$NO_REVIEW" = true ] && echo 'off' || echo 'on')"
  log INFO "Adversarial: $([ "$ADVERSARIAL" = true ] && echo 'on' || echo 'off')"
  [ "$MAX_RETRIES" -gt 0 ] && log INFO "Retries:    up to $MAX_RETRIES"
  [ "$PARALLEL" -eq 1 ] && log INFO "Cooldown:   ${COOLDOWN}s"
  [ -n "$EPIC_FILTER" ] && log INFO "Epic:       $EPIC_FILTER"
  [ -n "$FROM_PREFIX" ] && log INFO "From:       $FROM_PREFIX"
  log INFO "Dry Run:    $DRY_RUN"
  echo ""

  # Print story table
  printf "  ${BOLD}%-4s %-35s %-15s %s${NC}\n" "#" "Story Key" "Status" "Action"
  printf "  %-4s %-35s %-15s %s\n" "---" "-----------------------------------" "---------------" "----------------------------"
  for i in "${!STORY_KEYS[@]}"; do
    local num=$((i + 1))
    local action
    action=$(story_action "${STORY_STATUSES[$i]}")
    printf "  %-4s %-35s %-15s %s\n" "$num" "${STORY_KEYS[$i]}" "${STORY_STATUSES[$i]}" "$action"
  done
  echo ""

  # Run
  if [ "$PARALLEL" -gt 1 ]; then
    run_parallel
  else
    run_sequential
  fi

  exit $?
}

main "$@"
