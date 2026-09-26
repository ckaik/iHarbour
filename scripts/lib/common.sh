# Shared by the scripts in scripts/. Source it; don't run it.
#
# Expects HARBOUR_ROOT to be set.

harbour_note() {
    echo "note: $*"
}

# The games with a port, one per folder in ports/.
harbour_games() {
    local port
    for port in "$HARBOUR_ROOT"/ports/*/port.sh; do
        basename "$(dirname "$port")"
    done | tr '\n' ' '
}

# Xcode's build environment leaks into child processes (SDKROOT, ARCHS, a PATH
# with Xcode's tool directories, ...) and would steer CMake, including the host
# tools builds that must target macOS. CMake runs in a clean environment
# instead, pinned to the Xcode that runs the script.
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
HARBOUR_CLEAN_ENV=(
    env -i
    HOME="$HOME"
    PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    DEVELOPER_DIR="$DEVELOPER_DIR"
    TERM="${TERM:-dumb}"
    LANG="en_US.UTF-8"
    # Dependencies' checkouts live in build/, inside this repository. Once their
    # history is pruned (see harbour_prune_dependency_history), git run in one
    # of them must not find this repository instead.
    GIT_CEILING_DIRECTORIES="$HARBOUR_ROOT/build"
)
# Plain `cc`/`c++` can resolve to something other than Apple's clang (a wrapper
# in ~/.local/bin, Homebrew's gcc, ...), so name the compilers explicitly.
HARBOUR_CC="$(DEVELOPER_DIR="$DEVELOPER_DIR" xcrun -f clang)"
HARBOUR_CXX="$(DEVELOPER_DIR="$DEVELOPER_DIR" xcrun -f clang++)"
HARBOUR_CLEAN_ENV+=(CC="$HARBOUR_CC" CXX="$HARBOUR_CXX")

harbour_require_tools() {
    local tool
    for tool in cmake ninja git python3; do
        if ! "${HARBOUR_CLEAN_ENV[@]}" which "$tool" > /dev/null; then
            echo "error: $tool not found. Install it with: brew install cmake ninja python git" >&2
            exit 1
        fi
    done
}

# harbour_apply_patch <checkout> <patch>
#
# Applies <patch> to the git checkout <checkout> unless it's applied already.
# Patches stay applied in the submodules' working trees;
# scripts/unapply-patches.sh takes them out again.
harbour_apply_patch() {
    local dir="$1" patch="$2"
    if [[ ! -f "$patch" ]]; then
        echo "error: $patch is missing" >&2
        exit 1
    fi
    # git apply run in a subfolder of another repository silently skips every
    # file outside that subfolder, so <checkout> must be a checkout of its own
    # (an uninitialized nested submodule is just an empty folder).
    local top
    top="$(git -C "$dir" rev-parse --show-toplevel 2> /dev/null || true)"
    if [[ -z "$top" || "$(cd "$top" && pwd -P)" != "$(cd "$dir" && pwd -P)" ]]; then
        echo "error: ${dir#"$HARBOUR_ROOT"/} is not a checkout. Run: git submodule update --init --recursive" >&2
        exit 1
    fi
    if git -C "$dir" apply --reverse --check "$patch" 2> /dev/null; then
        return 0
    fi
    if git -C "$dir" apply --check "$patch" 2> /dev/null; then
        harbour_note "applying ${patch#"$HARBOUR_ROOT"/} to ${dir#"$HARBOUR_ROOT"/}"
        git -C "$dir" apply "$patch"
        return 0
    fi
    echo "error: ${patch#"$HARBOUR_ROOT"/} neither applies to ${dir#"$HARBOUR_ROOT"/} nor is applied already." >&2
    echo "error: The submodule has probably moved on; see docs/MAINTENANCE.md." >&2
    exit 1
}

# The arguments a build directory was last configured with.
HARBOUR_CONFIGURE_STAMP="harbour-configure-arguments.txt"

# harbour_needs_configure <build dir> <configure arguments...>
#
# Whether the CMake build in <build dir> needs (re)configuring: never
# configured, a configure that failed before writing build.ninja, or other
# arguments than last time (another Xcode, deployment target, recipe change).
harbour_needs_configure() {
    local dir="$1"
    shift
    [[ -f "$dir/CMakeCache.txt" && -f "$dir/build.ninja" ]] || return 0
    [[ "$(cat "$dir/$HARBOUR_CONFIGURE_STAMP" 2> /dev/null)" == "$(printf '%s\n' "$@")" ]] || return 0
    return 1
}

harbour_write_configure_stamp() {
    local dir="$1"
    shift
    printf '%s\n' "$@" > "$dir/$HARBOUR_CONFIGURE_STAMP"
}

# harbour_prune_dependency_history <build dir>
#
# FetchContent clones every dependency with its full history, about 1 GB per
# build directory, and seven games on two platforms don't fit on many disks.
# After a successful build the history is no longer needed: the configure step
# passes FETCHCONTENT_UPDATES_DISCONNECTED, so later builds don't touch it.
# Set HARBOUR_KEEP_DEPENDENCY_HISTORY=1 to keep it.
harbour_prune_dependency_history() {
    local dir="$1"
    [[ "${HARBOUR_KEEP_DEPENDENCY_HISTORY:-0}" == "1" ]] && return 0
    local git_dir
    for git_dir in "$dir"/_deps/*-src/.git; do
        [[ -e "$git_dir" ]] || continue
        rm -rf "$git_dir"
    done
}

# harbour_reset_pruned_dependencies <build dir>
#
# Removes the dependencies whose history harbour_prune_dependency_history
# deleted, so the next configure fetches them afresh, and returns 0 if there
# were any. Their checkouts can't be updated or patched again, which a
# configure needs when a game or patch update changes them.
harbour_reset_pruned_dependencies() {
    local dir="$1" source reset=1
    for source in "$dir"/_deps/*-src; do
        [[ -d "$source" && ! -e "$source/.git" ]] || continue
        local name="${source%-src}"
        rm -rf "$source" "$name-subbuild" "$name-build"
        reset=0
    done
    (( reset == 0 )) && rm -f "$dir/$HARBOUR_CONFIGURE_STAMP"
    return $reset
}
