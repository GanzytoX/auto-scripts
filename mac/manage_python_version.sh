#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

AUTO_YES=0
UPDATE_REQUESTED=0
WITH_PACKAGES=1
JUMP_TARGET=""
JUMP_FROM=""
OLD_CHOICE=""
DRY_RUN=0

usage() {
    print -r -- "Usage: $SCRIPT_NAME [--update] [--yes] [--no-packages]"
    print -r -- "  --update       Offer to install the latest patch of every installed Python series"
    print -r -- "                 that belongs to a supported manager (brew, pyenv, asdf, uv, mise)."
    print -r -- "  --yes          Confirm updates non-interactively (requires --update)."
    print -r -- "  --no-packages  Skip listing installed packages for each interpreter."
    print -r -- "  --jump TARGET  Move to another Python series with the same manager: 'next' (the next"
    print -r -- "                 series), 'latest' (newest stable on python.org) or an explicit series like 3.15."
    print -r -- "                 Afterwards asks whether to keep the previous series or remove it completely."
    print -r -- "  --from SERIES  Series to move away from (e.g. 3.14 or 3.14:brew when several managers hold it)."
    print -r -- "  --keep-old     With --jump: keep the previous series without asking."
    print -r -- "  --remove-old   With --jump: remove the previous series completely (still asks to confirm unless --yes)."
    print -r -- "  --dry-run      With --jump: show everything that would be installed/removed, change nothing."
    print -r -- "Exit status: 0 up to date or updated, 1 error, $EXIT_UPDATE_AVAILABLE update available (not installed)."
}

while (( $# > 0 )); do
    case "$1" in
        -u|--update) UPDATE_REQUESTED=1 ;;
        -y|--yes) AUTO_YES=1 ;;
        --no-packages) WITH_PACKAGES=0 ;;
        --jump) [[ -n "${2:-}" ]] || { print_error "--jump needs a value: next, latest or a series like 3.15."; exit 2; }; JUMP_TARGET="$2"; shift ;;
        --jump=*) JUMP_TARGET="${1#--jump=}" ;;
        --from) [[ -n "${2:-}" ]] || { print_error "--from needs a series like 3.14."; exit 2; }; JUMP_FROM="$2"; shift ;;
        --from=*) JUMP_FROM="${1#--from=}" ;;
        --keep-old) OLD_CHOICE="keep" ;;
        --remove-old) OLD_CHOICE="remove" ;;
        --dry-run|-n) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) print_error "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

if (( AUTO_YES && ! UPDATE_REQUESTED )) && [[ -z "$JUMP_TARGET" ]]; then
    print_error "--yes can only be used together with --update or --jump."
    exit 2
fi
if [[ -n "$JUMP_TARGET" ]] && (( UPDATE_REQUESTED )); then
    print_error "--jump and --update cannot be combined."
    exit 2
fi
if [[ -z "$JUMP_TARGET" ]] && [[ -n "$JUMP_FROM$OLD_CHOICE" || $DRY_RUN -eq 1 ]]; then
    print_error "--from, --keep-old, --remove-old and --dry-run only work together with --jump."
    exit 2
fi
if [[ -n "$JUMP_TARGET" && ! "$JUMP_TARGET" =~ '^(next|latest|[0-9]+\.[0-9]+)$' ]]; then
    print_error "Invalid --jump target '$JUMP_TARGET': use next, latest or a series like 3.15."
    exit 2
fi

# Every failed operation is logged with its real error and printed in a final summary.
typeset -a FAIL_LOG=()
# log_failure <action> <target> <error output>
log_failure() {
    local err="${3//$'\n'/ | }"
    [[ -z "$err" ]] && err="(no error output)"
    FAIL_LOG+=("$1: $2 -> $err")
    print_error "  FAILED: $1: $2"
    print_error "    reason: $err"
}

# step <description> <command...>: run_step (prints the failure) plus an entry in the final summary.
step() {
    run_step "$@"
    local rc=$?
    (( rc != 0 )) && FAIL_LOG+=("$1 -> exit status $rc (command output shown above)")
    return $rc
}

clear_screen
print_info "=== Python Inventory and Update Check ==="

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pyinfo.XXXXXX")" || { print_error "Could not create a temp directory."; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# ------------------------------------------------------------------ Python code (kept out of shell quoting)
read -r -d '' PROBE_PY <<'PYEOF'
import json, os, platform, sys, sysconfig

# Virtual environments are not interpreters of their own: skip them.
if sys.prefix != sys.base_prefix:
    sys.exit(0)

packages = None
if os.environ.get("WITH_PKGS") == "1":
    try:
        from importlib import metadata
        found = {}
        for dist in metadata.distributions():
            name = dist.metadata["Name"]
            if name:
                found[name] = dist.version
        packages = sorted(found.items(), key=lambda item: item[0].lower())
    except Exception:
        packages = None

stdlib = sysconfig.get_path("stdlib") or ""
print(json.dumps({
    "cand": os.environ.get("CAND", ""),
    "version": platform.python_version(),
    "exe": os.path.realpath(sys.executable),
    "arch": platform.machine(),
    "externally_managed": os.path.exists(os.path.join(stdlib, "EXTERNALLY-MANAGED")),
    "free_threaded": bool(sysconfig.get_config_var("Py_GIL_DISABLED")),
    "conda": os.path.isdir(os.path.join(sys.prefix, "conda-meta")),
    "packages": packages,
}))
PYEOF

read -r -d '' REPORT_PY <<'PYEOF'
import datetime, glob, json, os, re, sys

env = os.environ.get

def vkey(v):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)(.*)$", v)
    if not m:
        return (0, 0, 0, 0)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), 0 if m.group(4) else 1)

def load_json(path, what):
    try:
        with open(path) as f:
            txt = f.read().strip()
        return json.loads(txt) if txt else None
    except ValueError as e:
        print("Warning: %s returned unreadable data: %s" % (what, e), file=sys.stderr)
        return None

show_packages = env("WITH_PKGS") == "1"

records = []
files = glob.glob(os.path.join(env("PROBE_DIR"), "*.json"))
for path in sorted(files, key=lambda p: int(os.path.basename(p).split(".")[0])):
    rec = load_json(path, "interpreter probe")
    if rec:
        records.append(rec)

active_cand = env("ACTIVE_CAND", "")
active_exe = next((r["exe"] for r in records if active_cand and r.get("cand") == active_cand), "")

by_exe = {}
for r in records:
    if r.get("exe") and re.match(r"^\d+\.\d+\.\d+", r.get("version", "")):
        by_exe.setdefault(r["exe"], r)
interpreters = sorted(by_exe.values(), key=lambda r: (vkey(r["version"]), r["exe"]))

# Latest stable patch per series, from python.org.
latest = {}
releases = load_json(env("RELEASES_FILE"), "python.org")
releases_ok = isinstance(releases, list)
if releases_ok:
    for rel in releases:
        m = re.fullmatch(r"Python (\d+\.\d+)\.(\d+)", rel.get("name", ""))
        if m and not rel.get("pre_release"):
            ver = rel["name"][len("Python "):]
            if m.group(1) not in latest or vkey(ver) > vkey(latest[m.group(1)]):
                latest[m.group(1)] = ver

# End-of-life dates per series (optional source).
eol = {}
eol_data = load_json(env("EOL_FILE"), "endoflife.date")
if isinstance(eol_data, list):
    for item in eol_data:
        if "cycle" in item:
            eol[str(item["cycle"])] = item.get("eol")
today = datetime.date.today()

brew = env("BREW_PREFIX", "")
def classify(exe, rec):
    if "/Contents/Developer/Library/Frameworks/Python3.framework/" in exe or exe.startswith("/Library/Developer/CommandLineTools/"):
        return ("apple", "Apple (Xcode/Command Line Tools)", "")
    if brew:
        m = re.match(re.escape(brew) + r"/Cellar/(python(?:@\d+\.\d+)?)/", exe)
        if m:
            return ("brew", "Homebrew " + m.group(1), m.group(1))
    for name, base, marker in (("pyenv", env("PYENV_BASE", ""), "/versions/"), ("asdf", env("ASDF_BASE", ""), "/installs/python/")):
        if base and exe.startswith(os.path.realpath(base) + marker):
            return (name, name, exe[len(os.path.realpath(base)) + len(marker):].split("/")[0])
    if "/mise/installs/python/" in exe:
        return ("mise", "mise", exe.split("/mise/installs/python/")[1].split("/")[0])
    uv_dir = env("UV_PY_DIR", "")
    if "/uv/python/" in exe:
        return ("uv", "uv", exe.split("/uv/python/")[1].split("/")[0])
    if uv_dir and exe.startswith(os.path.realpath(uv_dir) + "/"):
        return ("uv", "uv", exe[len(os.path.realpath(uv_dir)) + 1:].split("/")[0])
    if rec.get("conda"):
        return ("conda", "conda", "")
    if exe.startswith("/Library/Frameworks/Python.framework/"):
        return ("python.org", "python.org installer", "")
    return ("unknown", "unknown installer", "")

SUPPORTED = {"brew", "pyenv", "asdf", "uv", "mise"}
actions, seen_actions, all_rows = [], set(), []
outdated = eol_installed = 0

for r in interpreters:
    exe, ver = r["exe"], r["version"]
    series = ".".join(ver.split(".")[:2])
    mgr, mgr_label, key = classify(exe, r)
    tags = [r.get("arch", "")]
    if r.get("externally_managed"): tags.append("externally managed")
    if r.get("free_threaded"): tags.append("free-threaded")
    active = "  (active)" if exe == active_exe else ""
    all_rows.append("\t".join([ver, exe, mgr, key or "-", series, "1" if exe == active_exe else "0", latest.get(series, "-")]))
    print("  - %s%s  [%s]  %s" % (ver, active, ", ".join(t for t in tags if t), exe))
    print("      Installed by: %s" % mgr_label)

    notes = []
    eol_date = eol.get(series)
    if isinstance(eol_date, str):
        try:
            d = datetime.date.fromisoformat(eol_date)
            if d <= today:
                notes.append("series %s is END-OF-LIFE since %s (no security fixes)" % (series, eol_date)); eol_installed += 1
            else:
                notes.append("series %s is supported until %s" % (series, eol_date))
        except ValueError:
            pass
    elif eol_date is True:
        notes.append("series %s is END-OF-LIFE (no security fixes)" % series); eol_installed += 1

    status = None
    if not releases_ok:
        status = "update status unavailable (python.org could not be queried)"
    elif mgr == "apple":
        status = "patch level follows Xcode/Command Line Tools updates, not python.org (upstream %s: %s)" % (series, latest.get(series, "n/a"))
    elif series not in latest:
        status = "no stable %s.x release listed on python.org (series may be unreleased or retired)" % series
    elif vkey(ver) >= vkey(latest[series]):
        status = "up to date (latest %s)" % latest[series]
    else:
        outdated += 1
        status = "UPDATE AVAILABLE: %s -> %s" % (ver, latest[series])
        if mgr in SUPPORTED:
            # brew updates a formula; the other managers just install the new patch next to the old one.
            action_key = key if mgr == "brew" else "-"
            sig = (mgr, action_key if mgr == "brew" else latest[series])
            if sig not in seen_actions:
                seen_actions.add(sig)
                actions.append("\t".join([ver, exe, mgr, action_key, latest[series]]))
        elif mgr == "python.org":
            status += " (download the installer: https://www.python.org/downloads/macos/)"
        elif mgr == "conda":
            status += " (inside that environment run: conda update python)"
        else:
            status += " (installer unknown; update it the same way it was installed)"
    print("      Status: %s" % status)
    for n in notes:
        print("      Note: %s" % n)

    if show_packages:
        packages = r.get("packages")
        if packages is None:
            print("      Packages: unavailable")
        elif not packages:
            print("      Packages: none")
        else:
            width = max(len(name) for name, _ in packages)
            print("      Packages (%d):" % len(packages))
            for name, version in packages:
                print("        %s  %s" % (name.ljust(width), version))

print()
newest = max(latest, key=lambda s: tuple(int(x) for x in s.split("."))) if latest else None
summary = "%d interpreter(s) found, %d outdated, %d in an end-of-life series." % (len(interpreters), outdated, eol_installed)
if newest:
    summary += " Newest stable series on python.org: %s (%s)." % (newest, latest[newest])
print(summary)

with open(env("OUT_TSV"), "w") as f:
    f.write("\n".join(actions) + ("\n" if actions else ""))
with open(env("OUT_ALL"), "w") as f:
    f.write("\n".join(all_rows) + ("\n" if all_rows else ""))
with open(env("OUT_SERIES"), "w") as f:
    ordered = sorted(latest, key=lambda s_: tuple(int(x) for x in s_.split(".")))
    f.write("\n".join("%s\t%s" % (s_, latest[s_]) for s_ in ordered) + ("\n" if ordered else ""))
with open(env("OUT_META"), "w") as f:
    f.write("outdated=%d\nfound=%d\nreleases_ok=%d\n" % (outdated, len(interpreters), 1 if releases_ok else 0))
PYEOF

# ------------------------------------------------------------------ Discover every interpreter
PYENV_BASE="${PYENV_ROOT:-$HOME/.pyenv}"
ASDF_BASE="${ASDF_DATA_DIR:-$HOME/.asdf}"
BREW_PREFIX=""
command_exists brew && BREW_PREFIX="$(brew --prefix 2>/dev/null)"
UV_PY_DIR=""
if command_exists uv; then
    UV_PY_DIR="$(uv python dir 2>&1)" || { print_warning "Warning: 'uv python dir' failed: ${UV_PY_DIR//$'\n'/ | }"; UV_PY_DIR=""; }
fi

# The interpreter the shell would run.
ACTIVE_CAND="$(command -v python3 || command -v python)"

typeset -a RAW_CANDIDATES=()
[[ -n "$ACTIVE_CAND" ]] && RAW_CANDIDATES+=("$ACTIVE_CAND")
# Anything named python / python3 / python3.N on PATH (shims are skipped below).
RAW_CANDIDATES+=( ${^path}/python*(N-*) )
RAW_CANDIDATES+=(
    ${PYENV_BASE}/versions/*/bin/python3(N-*)
    ${ASDF_BASE}/installs/python/*/bin/python3(N-*)
    $HOME/.local/share/mise/installs/python/*/bin/python3(N-*)
    ${UV_PY_DIR:+$UV_PY_DIR}/*/bin/python3(N-*)
    $HOME/.local/share/uv/python/*/bin/python3(N-*)
    /Library/Frameworks/Python.framework/Versions/*/bin/python3(N-*)
    /Applications/Xcode*.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/*/bin/python3(N-*)
    /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/*/bin/python3(N-*)
    $HOME/{miniconda3,anaconda3,miniforge3,mambaforge}/{bin,envs/*/bin}/python(N-*)
    /opt/{miniconda3,anaconda3,miniforge3}/{bin,envs/*/bin}/python(N-*)
    /usr/bin/python3(N-*)
)
[[ -n "$BREW_PREFIX" ]] && RAW_CANDIDATES+=( "$BREW_PREFIX"/opt/python@*/bin/python3(N-*) )
if command_exists uv; then
    UV_LIST="$(uv python list --only-installed 2>&1)" || { print_warning "Warning: 'uv python list' failed: ${UV_LIST//$'\n'/ | }"; UV_LIST=""; }
    RAW_CANDIDATES+=( ${(f)"$(print -r -- "$UV_LIST" | awk '$2 ~ /^\// {print $2}')"} )
fi

typeset -A SEEN_REAL=()
typeset -a CANDIDATES=()
typeset -a SKIPPED=()
for c in "${RAW_CANDIDATES[@]}"; do
    [[ -n "$c" && -x "$c" ]] || continue
    [[ "${c:t}" =~ '^python([0-9]+(\.[0-9]+)?t?)?$' ]] || continue
    [[ "$c" == */shims/* ]] && continue                      # pyenv/asdf/mise shims resolve to real versions listed elsewhere
    if [[ "$c" == /usr/bin/python* ]] && ! xcode-select -p >/dev/null 2>&1; then
        SKIPPED+=("$c (Apple shim; Xcode Command Line Tools are not installed, so it was not run)")
        continue
    fi
    real="${c:A}"
    [[ -n "${SEEN_REAL[$real]:-}" ]] && continue
    SEEN_REAL[$real]=1
    CANDIDATES+=("$c")
done

if (( ${#CANDIDATES[@]} == 0 )); then
    print_error "Error: no Python interpreter was found on this system."
    for s in "${SKIPPED[@]}"; do print_warning "  skipped: $s"; done
    print -r -- "Install it from https://www.python.org/downloads/ or with a version manager."
    exit 1
fi

# Probe all candidates in parallel (20s timeout each); keep stdout/stderr/status per candidate.
mkdir -p "$WORK/probe"
probe_one() {
    local idx="$1" cand="$2"
    (cd / && CAND="$cand" WITH_PKGS="$WITH_PACKAGES" perl -e 'alarm shift; exec @ARGV' 20 "$cand" -c "$PROBE_PY" \
        > "$WORK/probe/$idx.json" 2> "$WORK/probe/$idx.err" </dev/null)
    print -r -- $? > "$WORK/probe/$idx.rc"
}
idx=0
for cand in "${CANDIDATES[@]}"; do
    (( idx++ ))
    probe_one "$idx" "$cand" &
done
wait

PROBE_FAILURES=0
idx=0
for cand in "${CANDIDATES[@]}"; do
    (( idx++ ))
    rc="$(<"$WORK/probe/$idx.rc")"
    if [[ "$rc" != "0" ]]; then
        (( PROBE_FAILURES++ ))
        [[ "$rc" == 142 ]] && reason="timed out after 20s" || reason="exit status $rc: $(tail -3 "$WORK/probe/$idx.err" | tr '\n' ' ')"
        log_failure "probe interpreter" "$cand" "$reason"
        : > "$WORK/probe/$idx.json"
    fi
done

# Interpreter used to aggregate the results: the first one that probed successfully.
ORCH_PY=""
idx=0
for cand in "${CANDIDATES[@]}"; do
    (( idx++ ))
    if [[ -s "$WORK/probe/$idx.json" ]]; then ORCH_PY="$cand"; break; fi
done
if [[ -z "$ORCH_PY" ]]; then
    print_error "No Python interpreter could be probed successfully."
    exit 1
fi

# ------------------------------------------------------------------ Upstream data
NETWORK_OK=1
RELEASES_FILE="$WORK/releases.json"
EOL_FILE="$WORK/eol.json"
: > "$RELEASES_FILE"; : > "$EOL_FILE"
if ! command_exists curl; then
    print_error "Error: curl is required to check Python releases."
    NETWORK_OK=0
else
    print_info "Fetching release information from python.org..."
    if ! fetch_url 'https://www.python.org/api/v2/downloads/release/?is_published=true&show_on_download_page=true&order_by=-release_date' \
            > "$RELEASES_FILE" 2> "$WORK/releases.err"; then
        print_error "Could not fetch Python release information: $(<"$WORK/releases.err")"
        : > "$RELEASES_FILE"
        NETWORK_OK=0
    fi
    # Optional: end-of-life dates (failure is reported but not fatal).
    if ! fetch_url 'https://endoflife.date/api/python.json' > "$EOL_FILE" 2> "$WORK/eol.err"; then
        print_warning "Warning: end-of-life dates unavailable (endoflife.date): $(<"$WORK/eol.err")"
        : > "$EOL_FILE"
    fi
fi

# ------------------------------------------------------------------ Report
print
print -r -- "${BLUE}Active python:${NC} ${ACTIVE_CAND:-none on PATH}"
print_info "Installed Python interpreters detected (${#CANDIDATES[@]} candidates probed):"
OUT_TSV="$WORK/actions.tsv"
OUT_META="$WORK/meta"
OUT_ALL="$WORK/all.tsv"
OUT_SERIES="$WORK/series.tsv"
PROBE_DIR="$WORK/probe" ACTIVE_CAND="$ACTIVE_CAND" WITH_PKGS="$WITH_PACKAGES" RELEASES_FILE="$RELEASES_FILE" EOL_FILE="$EOL_FILE" \
BREW_PREFIX="$BREW_PREFIX" PYENV_BASE="$PYENV_BASE" ASDF_BASE="$ASDF_BASE" UV_PY_DIR="$UV_PY_DIR" OUT_TSV="$OUT_TSV" OUT_META="$OUT_META" OUT_ALL="$OUT_ALL" OUT_SERIES="$OUT_SERIES" \
    "$ORCH_PY" -c "$REPORT_PY" || { print_error "Could not build the Python inventory report."; exit 1; }
for s in "${SKIPPED[@]}"; do print_warning "Skipped: $s"; done

OUTDATED_COUNT="$(sed -nE 's/^outdated=//p' "$OUT_META" 2>/dev/null)"
if (( ! NETWORK_OK )); then
    print_error "Update status could not be determined because python.org could not be reached."
    exit 1
fi

finish() {
    print
    if (( ${#FAIL_LOG[@]} > 0 )); then
        print_error "=== ${#FAIL_LOG[@]} operation(s) FAILED ==="
        local f
        for f in "${FAIL_LOG[@]}"; do print_error "  - $f"; done
        exit 1
    fi
    exit "${1:-0}"
}

# ------------------------------------------------------------------ Jump to another series (--jump)
ask_yes_strict() {
    [[ -t 0 ]] || { print_error "Confirmation needed but stdin is not a terminal."; return 1; }
    printf '%s [y/N] ' "$1"
    local a; read -r a
    [[ "$a" == [yY] || "$a" == [yY][eE][sS] ]]
}

# Prints the directory of every virtual environment whose pyvenv.cfg points into one of the given roots.
find_dependent_envs() {
    local -a roots=("$@") cfgs=()
    cfgs+=( ${(f)"$(mdfind -name pyvenv.cfg 2>/dev/null)"} )
    cfgs+=( $HOME/.local/pipx/venvs/*/pyvenv.cfg(N) $HOME/.virtualenvs/*/pyvenv.cfg(N) \
            $HOME/.cache/pypoetry/virtualenvs/*/pyvenv.cfg(N) $HOME/.local/share/virtualenvs/*/pyvenv.cfg(N) )
    local cfg root content
    for cfg in ${(u)cfgs}; do
        [[ "${cfg:t}" == pyvenv.cfg && -f "$cfg" ]] || continue
        [[ "$cfg" == "$BREW_PREFIX"/Cellar/* || "$cfg" == "$BREW_PREFIX"/opt/* ]] && continue   # formula-internal environments
        content="$(<"$cfg")"
        for root in "${roots[@]}"; do
            [[ -n "$root" && "$content" == *"$root"* ]] && { print -r -- "${cfg:h}"; break; }
        done
    done
}

do_jump() {
    local -a rows=( ${(f)"$(<"$OUT_ALL")"} )
    local -a f
    typeset -A jumpable=()
    local row
    for row in "${rows[@]}"; do
        f=("${(@ps:\t:)row}")
        [[ " brew pyenv asdf uv mise " == *" ${f[3]} "* ]] && jumpable+=("${f[5]}:${f[3]}" 1)
    done
    if (( ${#jumpable} == 0 )); then
        print_error "No installed Python belongs to a manager this script can move between series (brew, pyenv, asdf, uv, mise)."
        print_warning "Apple, python.org and conda installs are not supported for --jump."
        return 1
    fi

    # --- source series
    local -a opts=( ${(on)${(k)jumpable}} ) matches=()
    local o
    if [[ -n "$JUMP_FROM" ]]; then
        for o in "${opts[@]}"; do [[ "$o" == "$JUMP_FROM" || "$o" == "$JUMP_FROM":* ]] && matches+=("$o"); done
    else
        matches=("${opts[@]}")
    fi
    if (( ${#matches[@]} == 0 )); then
        print_error "No supported install matches --from '$JUMP_FROM'. Available: ${(j:, :)opts}"
        return 1
    fi
    if (( ${#matches[@]} > 1 )); then
        if [[ -t 0 && -z "$JUMP_FROM" ]] || [[ -t 0 && -n "$JUMP_FROM" ]]; then
            print_info "Several installs can be moved:"
            local i=1
            for o in "${matches[@]}"; do print -r -- "  $i) ${o%%:*}  (${o#*:})"; (( i++ )); done
            local pick; printf 'Choose one [1-%d]: ' "${#matches[@]}"; read -r pick
            [[ "$pick" == <-> ]] && (( pick >= 1 && pick <= ${#matches[@]} )) || { print_error "Invalid choice."; return 1; }
            matches=("${matches[$pick]}")
        else
            print_error "Several installs can be moved (${(j:, :)matches}); choose one with --from SERIES:MANAGER."
            return 1
        fi
    fi
    local src_series="${matches[1]%%:*}" src_mgr="${matches[1]#*:}"

    # --- target series
    local -a series_list=( ${(f)"$(cut -f1 "$OUT_SERIES")"} )
    local target=""
    case "$JUMP_TARGET" in
        latest) target="${series_list[-1]}" ;;
        next)
            local s_
            for s_ in "${series_list[@]}"; do
                if version_is_newer "$s_.0" "$src_series.0"; then target="$s_"; break; fi
            done ;;
        *) target="$JUMP_TARGET" ;;
    esac
    if [[ -z "$target" ]]; then
        print_error "There is no stable Python series after $src_series on python.org."
        return 1
    fi
    if (( ${series_list[(Ie)$target]} == 0 )); then
        print_error "Python $target has no stable release on python.org (known series: ${(j:, :)series_list})."
        return 1
    fi
    if [[ "$target" == "$src_series" ]] || ! version_is_newer "$target.0" "$src_series.0"; then
        print_error "Python $target is not newer than $src_series; --jump only moves forward."
        return 1
    fi
    local target_latest="$(awk -F'\t' -v s="$target" '$1 == s {print $2}' "$OUT_SERIES")"

    # --- old installs (every patch of the source series held by that manager)
    local -a old_vers=() old_exes=() old_keys=() remaining_series_exes=()
    for row in "${rows[@]}"; do
        f=("${(@ps:\t:)row}")
        if [[ "${f[5]}" == "$src_series" && "${f[3]}" == "$src_mgr" ]]; then
            old_vers+=("${f[1]}"); old_exes+=("${f[2]}"); old_keys+=("${f[4]}")
        elif [[ "${f[5]}" == "$src_series" ]]; then
            remaining_series_exes+=("${f[2]}")
        fi
    done
    local already_installed=0
    for row in "${rows[@]}"; do
        f=("${(@ps:\t:)row}")
        [[ "${f[5]}" == "$target" && "${f[3]}" == "$src_mgr" ]] && already_installed=1
    done

    print
    print_info "=== Jump: Python $src_series ($src_mgr) -> $target (latest patch $target_latest) ==="
    local active_old=0 oe
    for oe in "${old_exes[@]}"; do [[ -n "$ACTIVE_CAND" && "$oe" == "${ACTIVE_CAND:A}" ]] && active_old=1; done
    (( active_old )) && print_warning "The Python $src_series being replaced is the one your shell runs as 'python3'."

    # --- install plan
    local formula="python@$target" new_exe=""
    case "$src_mgr" in
        brew)  print -r -- "  Install:  brew install $formula" ;;
        pyenv) print -r -- "  Install:  pyenv install -s $target_latest" ;;
        asdf)  print -r -- "  Install:  asdf install python $target_latest" ;;
        uv)    print -r -- "  Install:  uv python install $target_latest" ;;
        mise)  print -r -- "  Install:  mise install python@$target_latest" ;;
    esac
    (( already_installed )) && print_warning "  Python $target is already installed with $src_mgr; the install step will be skipped."

    # --- removal plan (computed now so --dry-run can show it)
    local -a rm_paths=() rm_roots=()
    local -a rm_cmds=()
    local k i
    case "$src_mgr" in
        brew)
            local old_formula="python@$src_series"
            rm_cmds+=("brew uninstall $old_formula")
            rm_paths+=( "$BREW_PREFIX/lib/python$src_series"(N) "$BREW_PREFIX/Cellar/$old_formula"(N) )
            rm_roots+=("$BREW_PREFIX/Cellar/$old_formula/" "$BREW_PREFIX/opt/$old_formula")
            local cache; cache="$(brew --cache 2>/dev/null)"
            [[ -n "$cache" ]] && rm_paths+=( "$cache"/downloads/*--${old_formula}--*(N) "$cache"/${old_formula}--*(N) )
            ;;
        pyenv)  for k in "${old_keys[@]}"; do rm_cmds+=("pyenv uninstall -f $k"); rm_roots+=("${PYENV_BASE:A}/versions/$k"); done ;;
        asdf)   for k in "${old_keys[@]}"; do rm_cmds+=("asdf uninstall python $k"); rm_roots+=("${ASDF_BASE:A}/installs/python/$k"); done ;;
        mise)   for k in "${old_keys[@]}"; do rm_cmds+=("mise uninstall python@$k"); done; for oe in "${old_exes[@]}"; do rm_roots+=("${oe%/bin/*}"); done ;;
        uv)     for k in "${old_keys[@]}"; do rm_cmds+=("uv python uninstall $k"); done; for oe in "${old_exes[@]}"; do rm_roots+=("${oe%/bin/*}"); done ;;
    esac
    # Per-user data of that series, only when no other interpreter of the series remains.
    if (( ${#remaining_series_exes[@]} == 0 )); then
        rm_paths+=( "$HOME/Library/Python/$src_series"(N) "$HOME/.local/lib/python$src_series"(N) )
    fi
    local -a dep_envs=( ${(f)"$(find_dependent_envs "${rm_roots[@]}")"} )

    print
    print_info "If you remove Python $src_series ($src_mgr), this is everything that goes away:"
    for k in "${rm_cmds[@]}"; do print -r -- "  - run: $k   (interpreter, standard library and every package installed in it)"; done
    for k in "${rm_paths[@]}"; do print -r -- "  - delete: ${k/#$HOME/~}"; done
    for oe in "${old_exes[@]}"; do
        local pk; pk="$("$oe" -m pip list --format=freeze 2>/dev/null | wc -l | tr -d ' ')"
        print -r -- "  - ${pk:-?} installed package(s) of $oe will be lost"
    done
    if (( ${#dep_envs[@]} )); then
        print_warning "  Virtual environments built on it (they stop working; they are asked about separately):"
        for k in "${dep_envs[@]}"; do print -r -- "      ${k/#$HOME/~}"; done
    fi
    if [[ "$src_mgr" == brew ]]; then
        local deps; deps="$(brew uses --installed "python@$src_series" 2>/dev/null | paste -sd' ' -)"
        [[ -n "$deps" ]] && print_warning "  Homebrew formulae that depend on python@$src_series: $deps (removal will be refused while they exist)"
    fi

    if (( DRY_RUN )); then
        print
        print_success "Dry run: nothing was changed."
        return 0
    fi

    print
    # --yes approves the install; it never approves deleting (that has its own confirmation below).
    if (( ! already_installed )); then
        confirm "Install Python $target_latest with $src_mgr now?" || { print_success "No changes were made."; return 0; }
    fi
    if (( ! already_installed )); then
        case "$src_mgr" in
            brew)
                if ! brew info --json=v2 "$formula" >/dev/null 2>&1; then
                    print_error "Homebrew has no formula '$formula' yet (python.org has Python $target)."
                    return 1
                fi
                step "brew install $formula" brew install "$formula" || return 1
                new_exe="$BREW_PREFIX/opt/$formula/bin/python$target" ;;
            pyenv)
                command_exists pyenv || { print_error "pyenv is not available in this shell."; return 1; }
                step "pyenv install -s $target_latest" pyenv install -s "$target_latest" || return 1
                new_exe="$PYENV_BASE/versions/$target_latest/bin/python3" ;;
            asdf)
                command_exists asdf || { print_error "asdf is not available in this shell."; return 1; }
                step "asdf install python $target_latest" asdf install python "$target_latest" || return 1
                new_exe="$ASDF_BASE/installs/python/$target_latest/bin/python3" ;;
            uv)
                command_exists uv || { print_error "uv is not available in this shell."; return 1; }
                step "uv python install $target_latest" uv python install "$target_latest" || return 1
                new_exe="$(uv python find "$target_latest" 2>&1)" || { log_failure "uv python find" "$target_latest" "$new_exe"; return 1; } ;;
            mise)
                command_exists mise || { print_error "mise is not available in this shell."; return 1; }
                step "mise install python@$target_latest" mise install "python@$target_latest" || return 1
                new_exe="$(mise where "python@$target_latest" 2>&1)/bin/python3" ;;
        esac
        # Verify the new interpreter really runs and is the series we asked for.
        local got; got="$("$new_exe" --version 2>&1)"
        if [[ "$got" != "Python $target."* ]]; then
            log_failure "verify new interpreter" "$new_exe" "expected Python $target.x, got: ${got:-no output}"
            return 1
        fi
        print_success "$got is installed and working ($new_exe)."
    else
        print_success "Python $target is already installed; nothing to install."
    fi

    # --- keep or remove the previous series
    local choice="$OLD_CHOICE"
    if [[ -z "$choice" ]]; then
        if [[ -t 0 ]]; then
            local ans
            printf 'Keep Python %s or remove it completely? [K]eep / [r]emove: ' "$src_series"
            read -r ans
            [[ "$ans" == [rR]* ]] && choice="remove" || choice="keep"
        else
            print_warning "Not interactive and neither --keep-old nor --remove-old was given: keeping Python $src_series."
            choice="keep"
        fi
    fi
    if [[ "$choice" == keep ]]; then
        print_success "Python $src_series was kept next to Python $target."
        return 0
    fi

    if [[ "$src_mgr" == brew ]]; then
        local blockers; blockers="$(brew uses --installed "python@$src_series" 2>/dev/null | paste -sd' ' -)"
        if [[ -n "$blockers" ]]; then
            log_failure "remove python@$src_series" "dependents" "still required by: $blockers; nothing was removed"
            return 1
        fi
    fi
    if ! (( AUTO_YES )) || [[ "$OLD_CHOICE" != remove ]]; then
        ask_yes_strict "Permanently delete ALL of the items listed above for Python $src_series? This cannot be undone." || { print_success "Python $src_series was kept."; return 0; }
    fi

    # --- remove
    local rc
    for k in "${rm_cmds[@]}"; do
        print_info "Running: $k"
        step "$k" ${=k} || continue
    done
    local was_global=""
    if [[ "$src_mgr" == pyenv && -f "${PYENV_BASE}/version" ]]; then
        for k in "${old_keys[@]}"; do [[ "$(<"${PYENV_BASE}/version")" == "$k" ]] && was_global="$k"; done
        if [[ -n "$was_global" ]]; then
            print_warning "pyenv's global version was $was_global; switching it to $target_latest so it does not point to a removed version."
            step "pyenv global $target_latest" pyenv global "$target_latest"
        fi
    fi
    for k in "${rm_paths[@]}"; do
        [[ -e "$k" || -L "$k" ]] || continue
        local err; err="$(rm -rf -- "$k" 2>&1)"
        [[ -e "$k" || -L "$k" ]] && log_failure "rm -rf" "$k" "$err" || print -r -- "  removed: ${k/#$HOME/~}"
    done
    if (( ${#dep_envs[@]} )); then
        if ask_yes_strict "Also delete the ${#dep_envs[@]} virtual environment(s) built on Python $src_series (they no longer work)?"; then
            for k in "${dep_envs[@]}"; do
                [[ -f "$k/pyvenv.cfg" ]] || continue
                err="$(rm -rf -- "$k" 2>&1)"
                [[ -e "$k" ]] && log_failure "rm -rf" "$k" "$err" || print -r -- "  removed: ${k/#$HOME/~}"
            done
        else
            print_warning "Virtual environments were left in place and are now broken: recreate them with Python $target."
        fi
    fi

    # --- verify nothing is left
    print_info "Checking for leftovers of Python $src_series..."
    local -a leftovers=()
    for oe in "${old_exes[@]}"; do [[ -e "$oe" ]] && leftovers+=("$oe"); done
    for k in "${rm_paths[@]}"; do [[ -e "$k" || -L "$k" ]] && leftovers+=("$k"); done
    for k in "${rm_roots[@]}"; do [[ -e "${k%/}" ]] && leftovers+=("${k%/}"); done
    if [[ "$src_mgr" == brew ]]; then
        brew list --versions "python@$src_series" >/dev/null 2>&1 && leftovers+=("brew still lists python@$src_series")
        for k in "$BREW_PREFIX"/bin/*(N@); do
            [[ ! -e "$k" && "${k:A}" == *"python@$src_series"* ]] && leftovers+=("broken link: $k")
        done
    fi
    if (( ${#leftovers[@]} == 0 )); then
        print_success "Python $src_series was removed completely: no interpreter, packages, caches or links remain."
    else
        for k in "${leftovers[@]}"; do log_failure "leftover" "$k" "still present after removal"; done
    fi
    return 0
}

if [[ -n "$JUMP_TARGET" ]]; then
    do_jump
    finish $?
fi

if [[ ! -s "$OUT_TSV" ]]; then
    if (( ${OUTDATED_COUNT:-0} > 0 )); then
        print_warning "Outdated interpreters were found, but none belongs to a manager this script can update (see notes above)."
        finish $EXIT_UPDATE_AVAILABLE
    fi
    print_success "All detected Python interpreters are up to date."
    finish 0
fi

if (( ! UPDATE_REQUESTED )); then
    print_warning "Updates are available for $(wc -l < "$OUT_TSV" | tr -d ' ') installation(s)."
    print_info "Run '${0:A} --update' to install them with each detected manager."
    finish $EXIT_UPDATE_AVAILABLE
fi

# ------------------------------------------------------------------ Update every outdated interpreter that has a supported manager
if grep -q $'\tbrew\t' "$OUT_TSV"; then
    print_info "Refreshing Homebrew metadata..."
    step "brew update-if-needed" brew update-if-needed
fi

while IFS=$'\t' read -r -u3 u_ver u_exe u_mgr u_key u_latest; do
    [[ -z "$u_mgr" ]] && continue
    [[ "$u_key" == "-" ]] && u_key=""   # "-" is a placeholder: an empty tab field would shift the columns
    if ! confirm "Update Python $u_ver -> $u_latest using $u_mgr${u_key:+ ($u_key)}?"; then
        print_success "Skipped $u_ver ($u_mgr)."
        continue
    fi
    case "$u_mgr" in
        brew)
            print_info "Upgrading $u_key with Homebrew..."
            if step "brew upgrade $u_key" brew upgrade "$u_key"; then
                new_ver="$(brew list --versions "$u_key" 2>/dev/null | awk '{print $NF}')"
                new_ver="${new_ver%_*}"
                if [[ -z "$new_ver" ]]; then
                    log_failure "verify brew $u_key" "$u_key" "formula not listed after upgrade"
                elif ! version_is_newer "$new_ver" "$u_ver"; then
                    print_warning "Homebrew's $u_key is still $new_ver; python.org has $u_latest but Homebrew has not published it yet."
                elif version_is_newer "$u_latest" "$new_ver"; then
                    print_success "$u_key upgraded to $new_ver (python.org has $u_latest; Homebrew is one step behind)."
                else
                    print_success "$u_key upgraded to $new_ver."
                fi
            fi
        ;;
        pyenv)
            if ! command_exists pyenv; then log_failure "pyenv" "$u_latest" "pyenv is not available in this shell"; continue; fi
            step "pyenv install -s $u_latest" pyenv install -s "$u_latest" \
                && print_warning "Installed but not activated. Run: pyenv global $u_latest"
        ;;
        asdf)
            if ! command_exists asdf; then log_failure "asdf" "$u_latest" "asdf is not available in this shell"; continue; fi
            step "asdf install python $u_latest" asdf install python "$u_latest" \
                && print_warning "Installed but not activated. Select it with your asdf configuration."
        ;;
        uv)
            if ! command_exists uv; then log_failure "uv" "$u_latest" "uv is not available in this shell"; continue; fi
            step "uv python install $u_latest" uv python install "$u_latest" \
                && print_success "Python $u_latest installed with uv."
        ;;
        mise)
            if ! command_exists mise; then log_failure "mise" "$u_latest" "mise is not available in this shell"; continue; fi
            step "mise install python@$u_latest" mise install "python@$u_latest" \
                && print_success "Python $u_latest installed with mise."
        ;;
    esac
done 3< "$OUT_TSV"

if (( ${#FAIL_LOG[@]} == 0 )); then
    print_success "Python update run completed."
fi
finish 0
