#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

# Output inventory warnings/notices to stdout so report redirections remain complete
print_warning() {
    print -r -- "${YELLOW}$*${NC}"
}

CLEAN_MODE=0
DRY_RUN_MODE=1
AUTO_YES=0

usage() {
    print -r -- "Usage: $SCRIPT_NAME [--clean] [--dry-run] [--yes]"
    print -r -- ""
    print -r -- "Options:"
    print -r -- "  --clean     Enable cleanup mode to remove detected residual files and receipts."
    print -r -- "  --dry-run   Audit and report orphaned files without deleting anything (default)."
    print -r -- "  -y, --yes   Auto-confirm cleanup prompts (non-interactive mode)."
    print -r -- "  -h, --help  Show this help message."
}

while (( $# > 0 )); do
    case "$1" in
        --clean|--delete)
            CLEAN_MODE=1
            DRY_RUN_MODE=0
        ;;
        -n|--dry-run)
            DRY_RUN_MODE=1
            CLEAN_MODE=0
        ;;
        -y|--yes)
            AUTO_YES=1
        ;;
        -h|--help)
            usage
            exit 0
        ;;
        *)
            print_error "Unknown option: $1"
            usage >&2
            exit 2
        ;;
    esac
    shift
done

format_bytes() {
    local bytes="$1"
    if (( bytes < 1024 )); then
        printf "%d B" "$bytes"
    elif (( bytes < 1048576 )); then
        printf "%.1f KB" "$(( bytes / 1024.0 ))"
    elif (( bytes < 1073741824 )); then
        printf "%.2f MB" "$(( bytes / 1048576.0 ))"
    else
        printf "%.2f GB" "$(( bytes / 1073741824.0 ))"
    fi
}

clear_screen
print_info "=== macOS Residual Application Data Cleaner ==="
if (( DRY_RUN_MODE )); then
    print_info "Mode: AUDIT & PREVIEW (Read-only. Use --clean to remove orphaned items)"
else
    print_info "Mode: CLEANUP (Interactive removal of orphaned files)"
fi

SCAN_SCRIPT='
import os, sys, plistlib, subprocess, re, json

installed_bundles = set()
installed_vendor_prefixes = set()
installed_names = set()
installed_words = set()
installed_raw_apps = []

search_dirs = [
    "/Applications",
    "/System/Applications",
    "/System/Library/CoreServices/Applications",
    os.path.expanduser("~/Applications"),
    "/Library/PreferencePanes",
    "/opt/homebrew/Caskroom"
]

for sdir in search_dirs:
    if not os.path.exists(sdir):
        continue
    for root, dirs, files in os.walk(sdir):
        for d in list(dirs):
            if d.endswith(".app") or d.endswith(".prefPane"):
                app_name = d.rsplit(".", 1)[0]
                installed_raw_apps.append(app_name)
                app_lower = app_name.lower()
                installed_names.add(app_lower)
                installed_names.add(re.sub(r"[^a-z0-9]", "", app_lower))
                for word in re.findall(r"[a-z0-9]+", app_lower):
                    if len(word) >= 3 and word not in {"app", "the", "for", "and", "pro", "lite"}:
                        installed_words.add(word)
                info_plist = os.path.join(root, d, "Contents", "Info.plist")
                if os.path.exists(info_plist):
                    try:
                        with open(info_plist, "rb") as f:
                            pl = plistlib.load(f)
                            bid = pl.get("CFBundleIdentifier")
                            if bid and isinstance(bid, str):
                                bid_lower = bid.lower()
                                installed_bundles.add(bid_lower)
                                for part in bid_lower.split("."):
                                    if len(part) >= 3 and part not in {"com", "org", "net", "io", "app", "mac"}:
                                        installed_words.add(part)
                                parts = bid_lower.split(".")
                                if len(parts) >= 2:
                                    installed_vendor_prefixes.add(".".join(parts[:2]))
                                if len(parts) >= 3:
                                    installed_vendor_prefixes.add(".".join(parts[:3]))
                    except Exception:
                        pass
                dirs.remove(d)

try:
    ps_out = subprocess.check_output(["ps", "-axo", "comm="], text=True)
    for line in ps_out.splitlines():
        base = os.path.basename(line.strip()).lower()
        if base:
            installed_names.add(base)
            installed_names.add(re.sub(r"[^a-z0-9]", "", base))
            for word in re.findall(r"[a-z0-9]+", base):
                if len(word) >= 3:
                    installed_words.add(word)
except Exception:
    pass

SYSTEM_WHITELIST = {
    "apple", "system", "icloud", "cloudkit", "callhistory", "knowledge", "fileprovider",
    "differentialprivacy", "passkit", "animoji", "gamekit", "geoservices", "familycircle",
    "coresimulator", "discrecording", "crashreporter", "baseband", "privacypreservingmeasurement",
    "diskimages", "locationaccess", "locationaccessstored", "amsdatamigrator", "arfilecache",
    "sharedimagecache", "tvapp", "byhost", "cups", "printingprefs", "preferences", "com.apple",
    "syncservices", "addressbook", "calendars", "reminders", "safari", "mail", "photos",
    "messages", "maps", "facetime", "notes", "music", "podcasts", "tv", "news", "stocks",
    "books", "home", "shortcuts", "siri", "voice", "keychain", "security", "quicklook",
    "spotlight", "metadata", "font", "fonts", "audio", "audiocache", "bluetooth", "network",
    "wifi", "sharing", "airdrop", "screentime", "accessibility", "universalaccess", "displays",
    "dock", "finder", "systemsettings", "systempreferences", "controlcenter", "notificationcenter",
    "notification", "distnoted", "cfnetwork", "containermanager", "containermetadata",
    "identityservices", "accounts", "phtphenotype", "menkaure", "trickplay", "lsmimagecache",
    "features_config", "gippseudonymousid", "datadog", "segment", "statsig", "tokenbucketratelimiter",
    "no_backup", "mbuseragent", "aaprofilepicture", "fsck_hfs", "installation", "clouddocs",
    "default.store", "icdd", "askpermissiond", "contextstoreagent", "pbs", "sharedfilelistd",
    "diagnostics_agent", "diagnosticreports", "assistant", "sentrycrash", "io.sentry",
    "kingfisher", "cctclearcutlogger", "electron", "electron-builder", "databases", "websitedata",
    "localstorage", "indexeddb", "gpucache", "code cache", "blob_storage", "default", "crashpad",
    "installer_telemetry"
}

DEV_TOOLS = {
    "pip", "python", "typescript", "swift", "swiftpm", "jedi", "astro", "eas-cli", "eas",
    "yarn", "pnpm", "npm", "node", "bun", "deno", "rust", "cargo", "go", "golang", "docker",
    "git", "github", "gh", "brew", "homebrew", "vscode", "code", "antigravity", "cursor",
    "gemini", "figma", "slack", "discord", "logi", "logitech", "ghub", "g hub", "obs",
    "obs-studio", "temp-init", "simple-vid", "wally", "qt", "qtproject", "plausiblelabs",
    "frontend"
}

def is_safe_or_active(item_name):
    lower = item_name.lower().strip()
    clean = re.sub(r"[^a-z0-9]", "", lower)
    if not clean:
        return True
    for prefix in SYSTEM_WHITELIST | DEV_TOOLS:
        if lower == prefix or lower.startswith(prefix) or prefix in lower or clean.startswith(prefix) or prefix in clean:
            return True
    for vprefix in installed_vendor_prefixes:
        if lower.startswith(vprefix):
            return True
    if lower in installed_bundles:
        return True
    for b in installed_bundles:
        if b in lower:
            return True
    for n in installed_names:
        if len(n) > 3 and (n in lower or n in clean):
            return True
    for w in installed_words:
        if w in lower or w in clean:
            return True
    return False

scan_roots = [
    os.path.expanduser("~/Library/Application Support"),
    os.path.expanduser("~/Library/Caches"),
    os.path.expanduser("~/Library/Preferences"),
    os.path.expanduser("~/Library/Saved Application State"),
    os.path.expanduser("~/Library/HTTPStorages"),
    os.path.expanduser("~/Library/WebKit"),
    os.path.expanduser("~/Library/Logs")
]

orphaned_user_files = []

for uroot in scan_roots:
    if not os.path.exists(uroot):
        continue
    for item in os.listdir(uroot):
        full_path = os.path.join(uroot, item)
        if item.startswith(".") or item.lower().startswith("com.apple."):
            continue
        base_name = item
        for ext in [".savedState", ".plist", ".binarycookies", ".log"]:
            if base_name.endswith(ext):
                base_name = base_name[:-len(ext)]
        if not is_safe_or_active(base_name):
            size_bytes = 0
            try:
                if os.path.islink(full_path):
                    size_bytes = 0
                elif os.path.isdir(full_path):
                    for r, _, fnames in os.walk(full_path):
                        for f in fnames:
                            fp = os.path.join(r, f)
                            if not os.path.islink(fp):
                                size_bytes += os.path.getsize(fp)
                else:
                    size_bytes = os.path.getsize(full_path)
            except Exception:
                size_bytes = 0
            orphaned_user_files.append({
                "path": full_path,
                "name": item,
                "location": uroot.replace(os.path.expanduser("~"), "~"),
                "size_bytes": size_bytes
            })

launch_roots = [
    os.path.expanduser("~/Library/LaunchAgents"),
    "/Library/LaunchAgents",
    "/Library/LaunchDaemons"
]

orphaned_launch_items = []

for lroot in launch_roots:
    if not os.path.exists(lroot):
        continue
    for item in os.listdir(lroot):
        if not item.endswith(".plist") or item.startswith("com.apple."):
            continue
        full_path = os.path.join(lroot, item)
        prog = ""
        try:
            with open(full_path, "rb") as f:
                pl = plistlib.load(f)
                prog = pl.get("Program", "")
                if not prog:
                    args = pl.get("ProgramArguments", [])
                    if args and isinstance(args, list):
                        prog = args[0]
        except Exception:
            continue
        if prog and not os.path.exists(prog) and not prog.startswith("/usr/bin") and not prog.startswith("/bin"):
            orphaned_launch_items.append({
                "path": full_path,
                "name": item,
                "location": lroot.replace(os.path.expanduser("~"), "~"),
                "target": prog
            })

orphaned_receipts = []
try:
    pkgs = subprocess.check_output(["pkgutil", "--pkgs"], text=True).splitlines()
except Exception:
    pkgs = []

for pkg in pkgs:
    if pkg.startswith("com.apple."):
        continue
    try:
        files = subprocess.check_output(["pkgutil", "--only-files", "--files", pkg], text=True).splitlines()
        info = subprocess.check_output(["pkgutil", "--pkg-info", pkg], text=True)
    except Exception:
        continue
    
    vol = "/"
    loc = ""
    for line in info.splitlines():
        if line.startswith("volume:"):
            vol = line.split(":", 1)[1].strip()
        elif line.startswith("location:"):
            loc = line.split(":", 1)[1].strip()
    prefix = os.path.join(vol, loc.lstrip("/"))
    
    app_present = False
    pkg_lower = pkg.lower()
    for app in installed_raw_apps:
        app_stem = app.replace(".app", "").replace(" ", "").lower()
        if (len(app_stem) > 3 and app_stem in pkg_lower) or pkg_lower in app_stem:
            app_present = True
            break
    if "microsoft" in pkg_lower and any(m in [a.lower() for a in installed_raw_apps] for m in ["microsoft word", "microsoft excel", "microsoft powerpoint", "onedrive", "microsoft teams"]):
        app_present = True
    if "docker" in pkg_lower and "docker" in installed_names:
        app_present = True
    if "enpass" in pkg_lower and "enpass" in installed_names:
        app_present = True

    if app_present:
        continue

    sample_files = [f for f in files if not f.endswith(".plist") and not f.endswith(".strings") and not f.endswith("Localizable.strings")]
    if not sample_files:
        sample_files = files[:10]
    else:
        sample_files = sample_files[:10]

    found_count = 0
    for f in sample_files:
        full_p = os.path.join(prefix, f.lstrip("/"))
        if os.path.exists(full_p):
            found_count += 1
            break

    if found_count == 0:
        orphaned_receipts.append(pkg)

output_data = {
    "total_apps": len(installed_raw_apps),
    "total_bundles": len(installed_bundles),
    "orphaned_user_files": orphaned_user_files,
    "orphaned_launch_items": orphaned_launch_items,
    "orphaned_receipts": orphaned_receipts
}

print(json.dumps(output_data))
'

print
print_info "[1/4] Active System & Application Inventory"
if ! command_exists python3; then
    print_error "Python 3 is required to inspect application bundles and package metadata."
    exit 1
fi

SCAN_JSON="$(python3 -c "$SCAN_SCRIPT" 2>/dev/null)"
if [[ -z "$SCAN_JSON" ]]; then
    print_error "Could not complete the system scan."
    exit 1
fi

TOTAL_APPS="$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); print(d.get('total_apps', 0))" "$SCAN_JSON")"
TOTAL_BUNDLES="$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); print(d.get('total_bundles', 0))" "$SCAN_JSON")"

print -r -- "  Active application bundles detected: $TOTAL_APPS"
print -r -- "  Registered bundle identifiers indexed: $TOTAL_BUNDLES"
print -r -- "  System & developer protection rules: Active"
print_success "Inventory discovery completed."

print
print_info "[2/4] Orphaned User Library Data (Caches, App Support, Saved State)"

ORPHAN_FILES_COUNT="$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); print(len(d.get('orphaned_user_files', [])))" "$SCAN_JSON")"
TOTAL_BYTES="$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); print(sum(x.get('size_bytes', 0) for x in d.get('orphaned_user_files', [])))" "$SCAN_JSON")"

if (( ORPHAN_FILES_COUNT > 0 )); then
    printf '  %-50s %-12s %s\n' "Residual Item" "Size" "Location"
    printf '  %-50s %-12s %s\n' "--------------------------------------------------" "------------" "-----------------------------------"
    python3 -c "
import json, sys
d = json.loads(sys.argv[1])
for item in d.get('orphaned_user_files', []):
    size = item.get('size_bytes', 0)
    if size < 1024:
        s_str = f'{size} B'
    elif size < 1048576:
        s_str = f'{size/1024.0:.1f} KB'
    else:
        s_str = f'{size/1048576.0:.2f} MB'
    print(f\"  {item['name'][:48]:<50} {s_str:<12} {item['location']}\")
" "$SCAN_JSON"
    
    FORMATTED_SPACE="$(format_bytes "$TOTAL_BYTES")"
    print_warning "Total residual user items found: $ORPHAN_FILES_COUNT (Reclaimable space: $FORMATTED_SPACE)"
else
    print_success "No orphaned user library files were found. Clean!"
fi

print
print_info "[3/4] Orphaned LaunchAgents & LaunchDaemons"

ORPHAN_LAUNCH_COUNT="$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); print(len(d.get('orphaned_launch_items', [])))" "$SCAN_JSON")"

if (( ORPHAN_LAUNCH_COUNT > 0 )); then
    printf '  %-45s %-20s %s\n' "Service Plist" "Location" "Missing Target Executable"
    printf '  %-45s %-20s %s\n' "---------------------------------------------" "--------------------" "-----------------------------------"
    python3 -c "
import json, sys
d = json.loads(sys.argv[1])
for item in d.get('orphaned_launch_items', []):
    print(f\"  {item['name'][:43]:<45} {item['location']:<20} {item['target']}\")
" "$SCAN_JSON"
    print_warning "Total orphaned background services found: $ORPHAN_LAUNCH_COUNT"
else
    print_success "No orphaned background services or daemons found. Clean!"
fi

print
print_info "[4/4] Orphaned macOS Package Receipts (pkgutil)"

ORPHAN_RECEIPTS_COUNT="$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); print(len(d.get('orphaned_receipts', [])))" "$SCAN_JSON")"

if (( ORPHAN_RECEIPTS_COUNT > 0 )); then
    python3 -c "
import json, sys
d = json.loads(sys.argv[1])
for pkg in d.get('orphaned_receipts', []):
    print(f'  - {pkg}')
" "$SCAN_JSON"
    print_warning "Total orphaned package receipts found: $ORPHAN_RECEIPTS_COUNT"
else
    print_success "No orphaned package receipts found. Clean!"
fi

print
print_info "=== Summary & Action Plan ==="

TOTAL_ITEMS=$(( ORPHAN_FILES_COUNT + ORPHAN_LAUNCH_COUNT + ORPHAN_RECEIPTS_COUNT ))

if (( TOTAL_ITEMS == 0 )); then
    print_success "Your system is completely clean! No residual application data detected."
    exit 0
fi

if (( DRY_RUN_MODE )); then
    print_info "Audit complete: Found $ORPHAN_FILES_COUNT user files/caches, $ORPHAN_LAUNCH_COUNT background services, and $ORPHAN_RECEIPTS_COUNT package receipts."
    print -r -- "To clean these items, run:"
    print -r -- "  ${GREEN}$0 --clean${NC}"
    if (( ORPHAN_RECEIPTS_COUNT > 0 )); then
        print
        print_info "Note on package receipts:"
        print -r -- "  Because package receipts are managed in the system database (/var/db/receipts/),"
        print -r -- "  you can forget them with sudo using the following command:"
        print
        printf "  sudo pkgutil --forget %s\n" "$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); print(' '.join(d.get('orphaned_receipts', [])))" "$SCAN_JSON")"
    fi
    exit 0
fi

# Cleanup mode execution
if (( CLEAN_MODE )); then
    # 1. Clean User Space Residuals
    if (( ORPHAN_FILES_COUNT > 0 )); then
        if confirm "Move $ORPHAN_FILES_COUNT orphaned user files/caches to Trash ($FORMATTED_SPACE)?"; then
            TRASH_DIR="$HOME/.Trash/residual_apps_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$TRASH_DIR" 2>/dev/null
            CLEANED_COUNT=0
            while IFS= read -r item_path; do
                [[ -z "$item_path" || ! -e "$item_path" ]] && continue
                mv "$item_path" "$TRASH_DIR/" 2>/dev/null || rm -rf "$item_path" 2>/dev/null
                (( CLEANED_COUNT++ ))
            done < <(python3 -c "import json, sys; d = json.loads(sys.argv[1]); [print(x['path']) for x in d.get('orphaned_user_files', [])]" "$SCAN_JSON")
            print_success "Moved $CLEANED_COUNT items to Trash ($TRASH_DIR)."
        else
            print_warning "User residual cleanup skipped by user."
        fi
    fi

    # 2. Clean LaunchAgents & LaunchDaemons
    if (( ORPHAN_LAUNCH_COUNT > 0 )); then
        # 2a. User LaunchAgents (~/Library/LaunchAgents)
        USER_LAUNCH_ITEMS="$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); [print(x['path']) for x in d.get('orphaned_launch_items', []) if x['location'].startswith('~')]" "$SCAN_JSON")"
        if [[ -n "$USER_LAUNCH_ITEMS" ]]; then
            if confirm "Move orphaned user LaunchAgents to Trash?"; then
                while IFS= read -r lpath; do
                    [[ -z "$lpath" || ! -e "$lpath" ]] && continue
                    launchctl bootout "gui/$(id -u)" "$lpath" 2>/dev/null
                    mv "$lpath" "$HOME/.Trash/" 2>/dev/null || rm -f "$lpath" 2>/dev/null
                done <<< "$USER_LAUNCH_ITEMS"
                print_success "Orphaned user LaunchAgents moved to Trash."
            fi
        fi

        # 2b. System LaunchAgents/LaunchDaemons (/Library/...) - require admin privileges
        SYSTEM_LAUNCH_ITEMS="$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); [print(x['path']) for x in d.get('orphaned_launch_items', []) if not x['location'].startswith('~')]" "$SCAN_JSON")"
        if [[ -n "$SYSTEM_LAUNCH_ITEMS" ]]; then
            SUDO_CMD=()
            (( EUID != 0 )) && SUDO_CMD=(sudo)
            if confirm "Unload and remove orphaned system LaunchAgents/LaunchDaemons (requires administrator privileges)?"; then
                SYS_REMOVED=0
                SYS_FAILED=0
                while IFS= read -r lpath; do
                    [[ -z "$lpath" || ! -e "$lpath" ]] && continue
                    if [[ "$lpath" == /Library/LaunchDaemons/* ]]; then
                        "${SUDO_CMD[@]}" launchctl bootout system "$lpath" </dev/null 2>/dev/null
                    else
                        launchctl bootout "gui/$(id -u)" "$lpath" </dev/null 2>/dev/null
                    fi
                    if "${SUDO_CMD[@]}" rm -f "$lpath" </dev/null; then
                        (( SYS_REMOVED++ ))
                    else
                        (( SYS_FAILED++ ))
                        print_error "Failed to remove: $lpath"
                    fi
                done <<< "$SYSTEM_LAUNCH_ITEMS"
                if (( SYS_FAILED == 0 )); then
                    print_success "Removed $SYS_REMOVED orphaned system background services."
                else
                    print_warning "Removed $SYS_REMOVED system services; $SYS_FAILED could not be removed."
                fi
            else
                print_warning "System background services cleanup skipped by user."
            fi
        fi
    fi

    # 3. Clean Package Receipts
    if (( ORPHAN_RECEIPTS_COUNT > 0 )); then
        RECEIPTS_LIST="$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); print(' '.join(d.get('orphaned_receipts', [])))" "$SCAN_JSON")"
        if (( EUID == 0 )); then
            if confirm "Forget $ORPHAN_RECEIPTS_COUNT orphaned package receipts from macOS database?"; then
                for r_pkg in ${(z)RECEIPTS_LIST}; do
                    pkgutil --forget "$r_pkg" 2>/dev/null
                done
                print_success "Orphaned package receipts forgotten successfully."
            fi
        else
            print
            print_info "To remove the $ORPHAN_RECEIPTS_COUNT orphaned package receipts (requires administrator privileges), run:"
            print -r -- "  ${GREEN}sudo pkgutil --forget $RECEIPTS_LIST${NC}"
        fi
    fi

    print
    print_success "Cleanup operations completed."
fi
