#!/usr/bin/env bash
#
# Skills Install Script
# Symlinks skills from this repo into ~/.claude/skills/
#
# Usage:
#   ./install.sh              # Interactive mode (default)
#   ./install.sh --all        # Install all skills
#   ./install.sh --list       # List skills and status
#   ./install.sh skill1 ...   # Install specific skills
#   ./install.sh --uninstall skill1  # Remove a skill
#   ./install.sh --uninstall-all     # Remove all skills from this repo
#
# Note: Compatible with bash 3.2+ (macOS default)
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude/skills"

# Counters for summary
INSTALLED=0
REMOVED=0
SKIPPED=0
ERRORS=0

# Safe increment (avoids set -e exit on 0++)
inc() { eval "$1=\$((\$$1 + 1))"; }

#------------------------------------------------------------------------------
# Logging functions
#------------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_header() {
    echo -e "\n${BOLD}${CYAN}$1${NC}\n"
}

#------------------------------------------------------------------------------
# Skill discovery
#------------------------------------------------------------------------------

# Find all skill directories (those containing SKILL.md)
# Returns newline-separated list
find_skills() {
    for dir in "$SCRIPT_DIR"/*/; do
        if [[ -f "${dir}SKILL.md" ]]; then
            basename "$dir"
        fi
    done
}

# Check if a skill is installed (symlinked to this repo)
is_installed() {
    local skill="$1"
    local target="$TARGET_DIR/$skill"
    
    if [[ -L "$target" ]]; then
        local link_target
        link_target="$(readlink "$target")"
        if [[ "$link_target" == "$SCRIPT_DIR/$skill" ]]; then
            return 0
        fi
    fi
    return 1
}

# Check if target exists (as anything)
target_exists() {
    local skill="$1"
    [[ -e "$TARGET_DIR/$skill" || -L "$TARGET_DIR/$skill" ]]
}

#------------------------------------------------------------------------------
# Target directory setup
#------------------------------------------------------------------------------

ensure_target_dir() {
    # Check if ~/.claude/skills is itself a symlink
    if [[ -L "$TARGET_DIR" ]]; then
        log_error "~/.claude/skills is a symlink. This may conflict with the install."
        log_error "Please remove or rename it first."
        exit 1
    fi
    
    # Create directories if needed
    if [[ ! -d "$HOME/.claude" ]]; then
        log_info "Creating ~/.claude/"
        mkdir -p "$HOME/.claude"
    fi
    
    if [[ ! -d "$TARGET_DIR" ]]; then
        log_info "Creating ~/.claude/skills/"
        mkdir -p "$TARGET_DIR"
    fi
}

#------------------------------------------------------------------------------
# Install/Uninstall functions
#------------------------------------------------------------------------------

install_skill() {
    local skill="$1"
    local force="${2:-false}"
    local source="$SCRIPT_DIR/$skill"
    local target="$TARGET_DIR/$skill"
    
    # Validate source exists
    if [[ ! -d "$source" ]]; then
        log_error "Skill not found: $skill"
        inc ERRORS
        return 1
    fi
    
    # Check if already installed (same symlink)
    if is_installed "$skill"; then
        log_warning "Skip: $skill (already installed)"
        inc SKIPPED
        return 0
    fi
    
    # Check if target exists as something else
    if target_exists "$skill"; then
        if [[ "$force" == "true" ]]; then
            log_warning "Replacing existing: $skill"
            rm -rf "$target"
        else
            log_error "Exists: $skill (use --force to replace)"
            inc ERRORS
            return 1
        fi
    fi
    
    # Create symlink
    if ln -s "$source" "$target"; then
        log_success "Installed: $skill"
        inc INSTALLED
    else
        log_error "Failed to install: $skill"
        inc ERRORS
        return 1
    fi
}

uninstall_skill() {
    local skill="$1"
    local target="$TARGET_DIR/$skill"
    
    # Only remove if it's a symlink pointing to this repo
    if [[ -L "$target" ]]; then
        local link_target
        link_target="$(readlink "$target")"
        if [[ "$link_target" == "$SCRIPT_DIR/$skill" ]]; then
            rm "$target"
            log_success "Removed: $skill"
            inc REMOVED
            return 0
        else
            log_warning "Skip: $skill (symlink points elsewhere)"
            inc SKIPPED
            return 0
        fi
    elif [[ -e "$target" ]]; then
        log_warning "Skip: $skill (not a symlink, won't remove)"
        inc SKIPPED
        return 0
    else
        log_warning "Skip: $skill (not installed)"
        inc SKIPPED
        return 0
    fi
}

#------------------------------------------------------------------------------
# Commands
#------------------------------------------------------------------------------

cmd_list() {
    log_header "Available skills from $SCRIPT_DIR"
    
    local skills=()
    while IFS= read -r skill; do
        skills+=("$skill")
    done < <(find_skills)
    
    if [[ ${#skills[@]} -eq 0 ]]; then
        log_warning "No skills found"
        return
    fi
    
    for skill in "${skills[@]}"; do
        if is_installed "$skill"; then
            echo -e "  ${GREEN}[x]${NC} $skill ${CYAN}(installed)${NC}"
        elif target_exists "$skill"; then
            echo -e "  ${YELLOW}[!]${NC} $skill ${YELLOW}(exists, not from this repo)${NC}"
        else
            echo -e "  ${NC}[ ]${NC} $skill"
        fi
    done
    echo ""
}

cmd_install_all() {
    local force="${1:-false}"
    
    log_header "Installing all skills"
    ensure_target_dir
    
    local skills=()
    while IFS= read -r skill; do
        skills+=("$skill")
    done < <(find_skills)
    
    for skill in "${skills[@]}"; do
        install_skill "$skill" "$force"
    done
    
    print_summary
}

cmd_install_specific() {
    local force="false"
    local skills=()
    
    for arg in "$@"; do
        if [[ "$arg" == "--force" ]]; then
            force="true"
        else
            skills+=("$arg")
        fi
    done
    
    if [[ ${#skills[@]} -eq 0 ]]; then
        log_error "No skills specified"
        exit 1
    fi
    
    log_header "Installing selected skills"
    ensure_target_dir
    
    for skill in "${skills[@]}"; do
        install_skill "$skill" "$force"
    done
    
    print_summary
}

cmd_uninstall() {
    shift  # Remove --uninstall from args
    
    if [[ $# -eq 0 ]]; then
        log_error "No skills specified for uninstall"
        exit 1
    fi
    
    log_header "Uninstalling skills"
    
    for skill in "$@"; do
        uninstall_skill "$skill"
    done
    
    print_summary
}

cmd_uninstall_all() {
    log_header "Uninstalling all skills from this repo"
    
    local skills=()
    while IFS= read -r skill; do
        skills+=("$skill")
    done < <(find_skills)
    
    for skill in "${skills[@]}"; do
        uninstall_skill "$skill"
    done
    
    print_summary
}

cmd_interactive() {
    log_header "Skills Manager"
    echo -e "Source: ${CYAN}$SCRIPT_DIR${NC}"
    echo -e "Target: ${CYAN}$TARGET_DIR${NC}"
    
    ensure_target_dir
    
    local skills=()
    while IFS= read -r skill; do
        skills+=("$skill")
    done < <(find_skills)
    
    if [[ ${#skills[@]} -eq 0 ]]; then
        log_warning "No skills found in this repo"
        exit 0
    fi
    
    # Track selected state using indexed arrays (bash 3.2 compatible)
    # Index corresponds to position in skills array
    local selected=()
    local original=()
    local i
    for i in "${!skills[@]}"; do
        if is_installed "${skills[$i]}"; then
            selected[$i]=1
            original[$i]=1
        else
            selected[$i]=0
            original[$i]=0
        fi
    done
    
    while true; do
        echo ""
        echo -e "${BOLD}Skills:${NC}"
        local num=1
        for i in "${!skills[@]}"; do
            local skill="${skills[$i]}"
            local status=""
            local marker=""
            
            if [[ ${selected[$i]} -eq 1 ]]; then
                marker="${GREEN}[x]${NC}"
            else
                marker="[ ]"
            fi
            
            # Show what will change
            if [[ ${selected[$i]} -ne ${original[$i]} ]]; then
                if [[ ${selected[$i]} -eq 1 ]]; then
                    status="${GREEN}(will install)${NC}"
                else
                    status="${RED}(will remove)${NC}"
                fi
            elif [[ ${selected[$i]} -eq 1 ]]; then
                status="${CYAN}(installed)${NC}"
            fi
            
            echo -e "  $num) $marker $skill $status"
            num=$((num + 1))
        done
        
        echo ""
        echo -e "Enter number to toggle, ${BOLD}a${NC}=all, ${BOLD}n${NC}=none, ${BOLD}q${NC}=apply & quit, ${BOLD}c${NC}=cancel"
        read -rp "> " input
        
        case "$input" in
            q|Q)
                break
                ;;
            c|C)
                log_info "Cancelled, no changes made"
                exit 0
                ;;
            a|A)
                for i in "${!skills[@]}"; do
                    selected[$i]=1
                done
                ;;
            n|N)
                for i in "${!skills[@]}"; do
                    selected[$i]=0
                done
                ;;
            [0-9]*)
                local idx=$((input - 1))
                if [[ $idx -ge 0 && $idx -lt ${#skills[@]} ]]; then
                    if [[ ${selected[$idx]} -eq 1 ]]; then
                        selected[$idx]=0
                    else
                        selected[$idx]=1
                    fi
                else
                    log_warning "Invalid number: $input"
                fi
                ;;
            *)
                log_warning "Unknown command: $input"
                ;;
        esac
    done
    
    # Apply changes
    echo ""
    log_header "Applying changes"
    
    local changes=0
    for i in "${!skills[@]}"; do
        if [[ ${selected[$i]} -ne ${original[$i]} ]]; then
            if [[ ${selected[$i]} -eq 1 ]]; then
                install_skill "${skills[$i]}" "false"
            else
                uninstall_skill "${skills[$i]}"
            fi
            changes=$((changes + 1))
        fi
    done
    
    if [[ $changes -eq 0 ]]; then
        log_info "No changes to apply"
    else
        print_summary
    fi
}

print_summary() {
    echo ""
    local parts=()
    [[ $INSTALLED -gt 0 ]] && parts+=("${GREEN}$INSTALLED installed${NC}")
    [[ $REMOVED -gt 0 ]] && parts+=("${YELLOW}$REMOVED removed${NC}")
    [[ $SKIPPED -gt 0 ]] && parts+=("${CYAN}$SKIPPED skipped${NC}")
    [[ $ERRORS -gt 0 ]] && parts+=("${RED}$ERRORS errors${NC}")
    
    if [[ ${#parts[@]} -gt 0 ]]; then
        local IFS=', '
        echo -e "${BOLD}Summary:${NC} ${parts[*]}"
    fi
}

show_help() {
    cat << EOF
${BOLD}Skills Install Script${NC}

Symlinks skills from this repo into ~/.claude/skills/

${BOLD}Usage:${NC}
  ./install.sh              Interactive mode (default)
  ./install.sh --all        Install all skills
  ./install.sh --list       List skills and their status
  ./install.sh skill1 ...   Install specific skills
  ./install.sh --uninstall skill1    Remove specific skill
  ./install.sh --uninstall-all       Remove all skills from this repo
  ./install.sh --help       Show this help

${BOLD}Options:${NC}
  --force    Replace existing skills (use with skill names)

${BOLD}Examples:${NC}
  ./install.sh --all
  ./install.sh netgraph-dev netgraph-dsl
  ./install.sh --uninstall omnigraffle-automation

EOF
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --list)
            cmd_list
            ;;
        --all)
            cmd_install_all "${2:-false}"
            ;;
        --uninstall-all)
            cmd_uninstall_all
            ;;
        --uninstall)
            cmd_uninstall "$@"
            ;;
        "")
            cmd_interactive
            ;;
        *)
            # Assume skill names
            cmd_install_specific "$@"
            ;;
    esac
}

main "$@"
