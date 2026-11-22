#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

JSON_OUTPUT=0
BRIEF_OUTPUT=0

usage() {
    print -r -- "Usage: $SCRIPT_NAME [--json] [--brief]"
    print -r -- "  --json   Output hardware and system information in JSON format."
    print -r -- "  --brief  Output a compact 1-line system summary."
    print -r -- "  --help   Show this help message."
    print -r -- "Warnings about data sources that could not be read go to stderr."
}

while (( $# > 0 )); do
    case "$1" in
        -j|--json) JSON_OUTPUT=1 ;;
        -b|--brief) BRIEF_OUTPUT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) print_error "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

if (( JSON_OUTPUT && BRIEF_OUTPUT )); then
    print_error "--json cannot be combined with --brief."
    exit 2
fi

if (( ! BRIEF_OUTPUT && ! JSON_OUTPUT )); then
    clear_screen
fi

HAVE_PYTHON=0
if command_exists python3; then
    HAVE_PYTHON=1
else
    print_warning "Warning: python3 not found; hardware, battery and display details are unavailable."
fi

# get_profiler_json <DataType>: prints system_profiler JSON; on failure warns (stderr) with the real error.
get_profiler_json() {
    local out
    if ! out="$(system_profiler "$1" -json 2>&1)"; then
        print_warning "Warning: system_profiler $1 failed: ${out//$'\n'/ | }"
        return 1
    fi
    print -r -- "$out"
}

# py_eval <python code>: runs python on stdin and evals its KEY='quoted value' output.
# Values are shell-quoted by python (shlex.quote), so odd characters cannot break or inject into the shell.
py_eval() {
    local code="$1" out
    out="$(python3 -c "$code")" || { print_warning "Warning: parsing step failed (see error above)."; return 1; }
    eval "$out"
}

# ---------------------------------------------------------------- Basic System & User
COMPUTER_NAME="$(scutil --get ComputerName 2>/dev/null || hostname)"
LOCAL_HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || hostname)"
CURRENT_USER="$(whoami)"
CURRENT_SHELL="${SHELL:-/bin/zsh}"

# ---------------------------------------------------------------- OS
PRODUCT_NAME="$(sw_vers -productName 2>/dev/null || echo 'macOS')"
PRODUCT_VERSION="$(sw_vers -productVersion 2>/dev/null)"
BUILD_VERSION="$(sw_vers -buildVersion 2>/dev/null)"
OS_FULL="$PRODUCT_NAME $PRODUCT_VERSION ($BUILD_VERSION)"
KERNEL_VER="$(uname -srm)"

# Uptime from the boot time (the `uptime` text format changes below 1 day and breaks regexes).
BOOT_EPOCH="$(sysctl -n kern.boottime 2>/dev/null | sed -nE 's/^\{ sec = ([0-9]+),.*/\1/p')"
if [[ -n "$BOOT_EPOCH" ]]; then
    UP_SECS=$(( $(date +%s) - BOOT_EPOCH ))
    UP_D=$(( UP_SECS / 86400 )); UP_H=$(( UP_SECS % 86400 / 3600 )); UP_M=$(( UP_SECS % 3600 / 60 ))
    if (( UP_D > 0 )); then UPTIME_INFO="${UP_D}d ${UP_H}h ${UP_M}m"; else UPTIME_INFO="${UP_H}h ${UP_M}m"; fi
else
    UPTIME_INFO="Unknown"
    print_warning "Warning: could not read kern.boottime; uptime unavailable."
fi

# ---------------------------------------------------------------- CPU / memory
MODEL_NAME="$(sysctl -n hw.model 2>/dev/null)"
CPU_BRAND="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
CPU_CORES="$(sysctl -n hw.physicalcpu 2>/dev/null)"
ARCH_TYPE="$(uname -m)"
P_CORES="$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null)"
E_CORES="$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null)"
TOTAL_MEM_BYTES="$(sysctl -n hw.memsize 2>/dev/null)"
if [[ -n "$TOTAL_MEM_BYTES" ]]; then
    TOTAL_MEM_STR="$(( TOTAL_MEM_BYTES / 1024 / 1024 / 1024 )) GB"
else
    TOTAL_MEM_STR="Unknown"
fi

# Memory in use (Activity Monitor style: app memory + wired + compressed), swap and pressure.
MEM_USED_STR=""
SWAP_STR=""
MEM_FREE_PCT=""
PAGE_SIZE="$(sysctl -n hw.pagesize 2>/dev/null)"
VM_OUT="$(vm_stat 2>/dev/null)"
if [[ -n "$VM_OUT" && -n "$PAGE_SIZE" ]]; then
    vm_pages() { print -r -- "$VM_OUT" | awk -F: -v k="$1" '$1 == k {gsub(/[ .]/, "", $2); print $2}'; }
    ANON="$(vm_pages 'Anonymous pages')"; PURG="$(vm_pages 'Pages purgeable')"
    WIRED="$(vm_pages 'Pages wired down')"; COMP="$(vm_pages 'Pages occupied by compressor')"
    if [[ -n "$ANON" && -n "$WIRED" && -n "$COMP" ]]; then
        USED_BYTES=$(( (ANON - ${PURG:-0} + WIRED + COMP) * PAGE_SIZE ))
        MEM_USED_STR="$(printf '%.1f' "$(( USED_BYTES / 1073741824.0 ))") GB"
    fi
else
    print_warning "Warning: vm_stat/hw.pagesize unavailable; memory usage not shown."
fi
SWAP_STR="$(sysctl -n vm.swapusage 2>/dev/null | sed -nE 's/.*used = ([0-9.]+[A-Z]).*/\1/p')"
MEM_FREE_PCT="$(memory_pressure 2>/dev/null | sed -nE 's/.*free percentage: ([0-9]+)%.*/\1/p')"

DETAILED_MODEL=""; MODEL_ID=""; CHIP_TYPE=""; SERIAL_NUM=""; HW_UUID=""; FIRMWARE_VER=""
HW_JSON="$(get_profiler_json SPHardwareDataType)"
if (( HAVE_PYTHON )) && [[ -n "$HW_JSON" ]]; then
    print -rn -- "$HW_JSON" | py_eval '
import json, sys, shlex
d = (json.load(sys.stdin).get("SPHardwareDataType") or [{}])[0]
def out(k, v): print(k + "=" + shlex.quote("" if v is None else str(v)))
out("DETAILED_MODEL", d.get("machine_name"))
out("MODEL_ID", d.get("machine_model"))
out("CHIP_TYPE", d.get("chip_type"))
out("SERIAL_NUM", d.get("serial_number"))
out("HW_UUID", d.get("platform_UUID"))
out("FIRMWARE_VER", d.get("boot_rom_version"))
'
fi

DISPLAY_MODEL="${DETAILED_MODEL:-$MODEL_NAME}"
[[ -n "$MODEL_ID" ]] && DISPLAY_MODEL="$DISPLAY_MODEL ($MODEL_ID)"
DISPLAY_CHIP="${CHIP_TYPE:-${CPU_BRAND:-$ARCH_TYPE}}"
if [[ -n "$P_CORES" && -n "$E_CORES" ]]; then
    DISPLAY_CHIP="$DISPLAY_CHIP ($CPU_CORES Cores: $P_CORES Performance + $E_CORES Efficiency)"
elif [[ -n "$CPU_CORES" ]]; then
    DISPLAY_CHIP="$DISPLAY_CHIP ($CPU_CORES Cores)"
fi

# ---------------------------------------------------------------- Power & battery
BATT_SOC=""; BATT_CHARGING=""; BATT_HEALTH=""; BATT_CYCLES=""; BATT_MAX_CAP=""; BATT_SOURCE=""; BATT_CHARGER_WATTS=""
POWER_JSON="$(get_profiler_json SPPowerDataType)"
if (( HAVE_PYTHON )) && [[ -n "$POWER_JSON" ]]; then
    print -rn -- "$POWER_JSON" | py_eval '
import json, sys, shlex
data = json.load(sys.stdin).get("SPPowerDataType", [])
info = {}
for item in data:
    name = item.get("_name")
    if name == "spbattery_information":
        chg = item.get("sppower_battery_charge_info", {})
        hlth = item.get("sppower_battery_health_info", {})
        info["soc"] = chg.get("sppower_battery_state_of_charge", "")
        info["charging"] = "Yes" if str(chg.get("sppower_battery_is_charging", "")).upper() == "TRUE" else "No"
        info["health"] = hlth.get("sppower_battery_health", "")
        info["cycles"] = hlth.get("sppower_battery_cycle_count", "")
        info["max_cap"] = hlth.get("sppower_battery_health_maximum_capacity", "")
    elif name == "sppower_information":
        pwr = item.get("Battery Power", {})
        info["source"] = "Battery" if str(pwr.get("Current Power Source", "")).upper() == "TRUE" else "AC Power"
    elif name == "sppower_ac_charger_information":
        info["charger_watts"] = item.get("sppower_ac_charger_watts", "")
for k, v in info.items():
    print("BATT_" + k.upper() + "=" + shlex.quote(str(v)))
'
fi
BATT_TIME_LEFT="$(pmset -g batt 2>/dev/null | sed -nE 's/.*[[:space:]]([0-9]+:[0-9]+) remaining.*/\1/p')"
case "$(pmset -g 2>/dev/null | awk '$1 == "lowpowermode" {print $2}')" in
    1) LOW_POWER_MODE="On" ;;
    0) LOW_POWER_MODE="Off" ;;
    *) LOW_POWER_MODE="" ;;
esac

# ---------------------------------------------------------------- Graphics & displays (with refresh rate)
GPU_NAME=""; GPU_CORES=""; DISPLAY_NAME=""; DISPLAY_RES=""; DISPLAYS_JSON="[]"
DISP_JSON="$(get_profiler_json SPDisplaysDataType)"
if (( HAVE_PYTHON )) && [[ -n "$DISP_JSON" ]]; then
    print -rn -- "$DISP_JSON" | py_eval '
import json, re, shlex, subprocess, sys

def out(k, v): print(k + "=" + shlex.quote("" if v is None else str(v)))

def pretty(token):
    t = re.sub(r"^spdisplays_", "", str(token or ""))
    return t.replace("-", " ").replace("_", " ").strip().title()

# Highest refresh rate macOS currently offers per screen (NSScreen.maximumFramesPerSecond), keyed by size.
max_hz = {}
js = ("ObjC.import(\"AppKit\"); var o=[]; var s=$.NSScreen.screens;"
      "for (var i=0;i<s.count;i++){var x=s.objectAtIndex(i);"
      "o.push([x.frame.size.width,x.frame.size.height,x.maximumFramesPerSecond].join(\"x\"));} o.join(\",\")")
try:
    r = subprocess.run(["osascript", "-l", "JavaScript", "-e", js], capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        print("Warning: osascript could not read the max refresh rate: " + r.stderr.strip(), file=sys.stderr)
    else:
        for part in r.stdout.strip().split(","):
            w, h, hz = part.split("x")
            max_hz[(int(float(w)), int(float(h)))] = int(float(hz))
except Exception as e:
    print("Warning: max refresh rate unavailable: " + str(e), file=sys.stderr)

data = json.load(sys.stdin).get("SPDisplaysDataType", [])
gpus, displays = [], []
for g in data:
    gpus.append({"name": g.get("sppci_model") or g.get("_name", ""), "cores": g.get("sppci_cores", "")})
    for n in g.get("spdisplays_ndrvs", []):
        res_raw = n.get("_spdisplays_resolution", "")
        m = re.search(r"(\d+)\s*x\s*(\d+).*?@\s*([\d.]+)\s*Hz", res_raw)
        w = h = hz = None
        if m:
            w, h, hz = int(m.group(1)), int(m.group(2)), float(m.group(3))
        pixels = n.get("_spdisplays_pixels") or re.sub(r"(spdisplays_|Retina)", "", n.get("spdisplays_pixelresolution", ""))
        displays.append({
            "name": n.get("_name", ""),
            "type": pretty(n.get("spdisplays_display_type")),
            "connection": pretty(n.get("spdisplays_connection_type")),
            "main": n.get("spdisplays_main") == "spdisplays_yes",
            "resolution": ("%d x %d" % (w, h)) if m else res_raw,
            "native_pixels": pixels,
            "refresh_hz": (int(hz) if hz == int(hz) else hz) if m else None,
            "max_refresh_hz": max_hz.get((w, h)) if m else None,
        })

out("GPU_NAME", " + ".join(x["name"] for x in gpus if x["name"]))
out("GPU_CORES", gpus[0]["cores"] if gpus else "")
if displays:
    d0 = displays[0]
    out("DISPLAY_NAME", d0["name"])
    hz = (" @ %sHz" % d0["refresh_hz"]) if d0["refresh_hz"] else ""
    out("DISPLAY_RES", d0["resolution"] + hz)
out("DISPLAYS_JSON", json.dumps(displays))
'
fi

# ---------------------------------------------------------------- Storage (user data lives on the Data volume, not the sealed system snapshot)
ROOT_DISK="$(df -h /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $1}')"
DATA_MOUNT="/System/Volumes/Data"
if [[ -z "$ROOT_DISK" ]]; then
    DATA_MOUNT="/"
    ROOT_DISK="$(df -h / 2>/dev/null | awk 'NR==2 {print $1}')"
    print_warning "Warning: could not read /System/Volumes/Data; showing the root volume instead."
fi
DISK_INFO="$(diskutil info "$DATA_MOUNT" 2>&1)"
cont_bytes() { print -r -- "$DISK_INFO" | sed -nE "s/^ *$1:.*\(([0-9]+) Bytes\).*/\1/p" | head -1; }
CONT_TOTAL="$(cont_bytes 'Container Total Space')"
CONT_FREE="$(cont_bytes 'Container Free Space')"
if [[ -n "$CONT_TOTAL" && -n "$CONT_FREE" ]]; then
    fmt_gb() { printf '%.0f GB' "$(( $1 / 1000000000.0 ))"; }
    DISK_TOTAL="$(fmt_gb "$CONT_TOTAL")"
    DISK_USED="$(fmt_gb $(( CONT_TOTAL - CONT_FREE )))"
    DISK_AVAIL="$(fmt_gb "$CONT_FREE")"
    DISK_PCT="$(( (CONT_TOTAL - CONT_FREE) * 100 / CONT_TOTAL ))%"
else
    print_warning "Warning: diskutil info $DATA_MOUNT gave no container sizes; falling back to df."
    DISK_TOTAL="$(df -h "$DATA_MOUNT" 2>/dev/null | awk 'NR==2 {print $2}')"
    DISK_USED="$(df -h "$DATA_MOUNT" 2>/dev/null | awk 'NR==2 {print $3}')"
    DISK_AVAIL="$(df -h "$DATA_MOUNT" 2>/dev/null | awk 'NR==2 {print $4}')"
    DISK_PCT="$(df -h "$DATA_MOUNT" 2>/dev/null | awk 'NR==2 {print $5}')"
fi
DISK_SSD="$(print -r -- "$DISK_INFO" | sed -nE 's/^ *Solid State: *//p' | head -1)"
DISK_PROTOCOL="$(print -r -- "$DISK_INFO" | sed -nE 's/^ *Protocol: *//p' | head -1)"

# ---------------------------------------------------------------- Network (detect the real interfaces instead of assuming en0)
PRIMARY_IF="$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')"
GATEWAY="$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2}')"
WIFI_DEV="$(networksetup -listallhardwareports 2>/dev/null | awk '/Hardware Port: Wi-Fi/ {getline; print $2; exit}')"
WIFI_DEV="${WIFI_DEV:-en0}"
NET_IF="${PRIMARY_IF:-$WIFI_DEV}"
WIFI_IP="$(ipconfig getifaddr "$NET_IF" 2>/dev/null)"
WIFI_MAC="$(ifconfig "$NET_IF" 2>/dev/null | awk '/ether/ {print $2}')"
# First exact "SSID :" line only (the BSSID line also contains "SSID : ").
WIFI_SSID="$(ipconfig getsummary "$WIFI_DEV" 2>/dev/null | awk -F' : ' '/^ *SSID : / {print $2; exit}')"
DNS_SERVERS="$(scutil --dns 2>/dev/null | awk '/nameserver\[/ {print $3}' | sort -u | paste -sd, - | sed 's/,/, /g')"

# ---------------------------------------------------------------- Security posture
FILEVAULT="$(fdesetup status 2>&1 | head -1 | sed -E 's/^FileVault is //; s/\.$//')"
SIP_STATUS="$(csrutil status 2>&1 | sed -E 's/^System Integrity Protection status: //; s/\.$//' | head -1)"
FIREWALL="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1 | sed -E 's/^Firewall is //; s/ \(State = [0-9]\)\.?$//; s/\.$//' | head -1)"
GATEKEEPER="$(spctl --status 2>&1 | head -1)"

# ---------------------------------------------------------------- Output modes
if (( BRIEF_OUTPUT )); then
    print -r -- "${COMPUTER_NAME} | ${DISPLAY_MODEL} | ${DISPLAY_CHIP} | ${TOTAL_MEM_STR} RAM | ${DISPLAY_RES:+$DISPLAY_RES | }${OS_FULL}"
    exit 0
fi

# ---------------------------------------------------------------- Developer tools (auto-detected)
# Catalog of well-known developer CLIs: "Category|command|version args". Only the ones found in PATH
# are probed (in parallel, 8s timeout each) and shown; nothing is hard-wired into the report.
# Unknown executables are never run: they are only listed by name (Homebrew packages, user bin dirs).
TOOL_CATALOG=(
  "Languages & Runtimes|node|--version"       "Languages & Runtimes|bun|--version"
  "Languages & Runtimes|deno|--version"       "Languages & Runtimes|python3|--version"
  "Languages & Runtimes|python|--version"     "Languages & Runtimes|ruby|--version"
  "Languages & Runtimes|go|version"           "Languages & Runtimes|rustc|--version"
  "Languages & Runtimes|java|-version"        "Languages & Runtimes|kotlin|-version"
  "Languages & Runtimes|swift|--version"      "Languages & Runtimes|php|--version"
  "Languages & Runtimes|perl|--version"       "Languages & Runtimes|lua|-v"
  "Languages & Runtimes|dotnet|--version"     "Languages & Runtimes|dart|--version"
  "Languages & Runtimes|flutter|--version"    "Languages & Runtimes|zig|version"
  "Languages & Runtimes|elixir|--version"     "Languages & Runtimes|R|--version"
  "Package Managers|brew|--version"           "Package Managers|npm|--version"
  "Package Managers|pnpm|--version"           "Package Managers|yarn|--version"
  "Package Managers|pip3|--version"           "Package Managers|pipx|--version"
  "Package Managers|uv|--version"             "Package Managers|poetry|--version"
  "Package Managers|conda|--version"          "Package Managers|cargo|--version"
  "Package Managers|gem|--version"            "Package Managers|bundle|--version"
  "Package Managers|composer|--version"       "Package Managers|pod|--version"
  "Package Managers|mas|version"
  "Version Managers|fnm|--version"            "Version Managers|volta|--version"
  "Version Managers|asdf|--version"           "Version Managers|mise|--version"
  "Version Managers|pyenv|--version"          "Version Managers|rbenv|--version"
  "Version Managers|nodenv|--version"         "Version Managers|n|--version"
  "Version Managers|rustup|--version"
  "Build & Source Tools|git|--version"        "Build & Source Tools|gh|--version"
  "Build & Source Tools|glab|--version"       "Build & Source Tools|git-lfs|--version"
  "Build & Source Tools|make|--version"       "Build & Source Tools|cmake|--version"
  "Build & Source Tools|ninja|--version"      "Build & Source Tools|clang|--version"
  "Build & Source Tools|gcc|--version"        "Build & Source Tools|xcodebuild|-version"
  "Build & Source Tools|fastlane|--version"
  "Containers & Cloud|docker|--version"       "Containers & Cloud|docker-compose|version"
  "Containers & Cloud|podman|--version"       "Containers & Cloud|kubectl|version --client"
  "Containers & Cloud|helm|version --short"   "Containers & Cloud|minikube|version --short"
  "Containers & Cloud|kind|--version"         "Containers & Cloud|terraform|version"
  "Containers & Cloud|tofu|version"           "Containers & Cloud|aws|--version"
  "Containers & Cloud|gcloud|--version"       "Containers & Cloud|az|--version"
  "Containers & Cloud|vercel|--version"       "Containers & Cloud|netlify|--version"
  "Containers & Cloud|supabase|--version"     "Containers & Cloud|wrangler|--version"
  "Containers & Cloud|flyctl|version"         "Containers & Cloud|firebase|--version"
  "Containers & Cloud|stripe|version"         "Containers & Cloud|cloudflared|--version"
  "Containers & Cloud|tailscale|version"      "Containers & Cloud|ngrok|--version"
  "AI & Editors|claude|--version"             "AI & Editors|codex|--version"
  "AI & Editors|gemini|--version"             "AI & Editors|ollama|--version"
  "AI & Editors|code|--version"               "AI & Editors|cursor|--version"
  "AI & Editors|zed|--version"                "AI & Editors|nvim|--version"
  "AI & Editors|vim|--version"
  "Databases|psql|--version"                  "Databases|mysql|--version"
  "Databases|sqlite3|--version"               "Databases|redis-cli|--version"
  "Databases|mongosh|--version"
  "CLI Utilities|jq|--version"                "CLI Utilities|yq|--version"
  "CLI Utilities|curl|--version"              "CLI Utilities|wget|--version"
  "CLI Utilities|rg|--version"                "CLI Utilities|fd|--version"
  "CLI Utilities|fzf|--version"               "CLI Utilities|bat|--version"
  "CLI Utilities|eza|--version"               "CLI Utilities|tmux|-V"
  "CLI Utilities|htop|--version"              "CLI Utilities|btop|--version"
  "CLI Utilities|tree|--version"              "CLI Utilities|starship|--version"
  "CLI Utilities|ffmpeg|-version"             "CLI Utilities|magick|--version"
  "CLI Utilities|pandoc|--version"            "CLI Utilities|shellcheck|--version"
  "Mobile|adb|version"                        "Mobile|eas|--version"
)
TOOL_CATEGORY_ORDER=("Languages & Runtimes" "Package Managers" "Version Managers" "Build & Source Tools" "Containers & Cloud" "AI & Editors" "Databases" "CLI Utilities" "Mobile")

# Shims in /usr/bin that pop up an installer dialog when the Command Line Tools are missing.
typeset -A APPLE_SHIMS=(git 1 python3 1 python 1 make 1 gcc 1 clang 1 swift 1 xcodebuild 1)

# probe_tool <result file> <category> <command> <args...>  (writes one TSV line if the tool exists)
probe_tool() {
    local outfile="$1" category="$2" cmd="$3"; shift 3
    local bin out ver rc
    bin="$(whence -p "$cmd" 2>/dev/null)"
    [[ -z "$bin" ]] && return 0
    if [[ "$bin" == /usr/bin/* && -n "${APPLE_SHIMS[$cmd]:-}" ]] && ! xcode-select -p >/dev/null 2>&1; then
        printf '%s\t%s\t%s\t%s\n' "$category" "$cmd" "(needs Xcode Command Line Tools)" "$bin" > "$outfile"; return 0
    fi
    if [[ "$cmd" == java && "$bin" == /usr/bin/java ]] && ! /usr/libexec/java_home >/dev/null 2>&1; then
        printf '%s\t%s\t%s\t%s\n' "$category" "$cmd" "(no JDK installed)" "$bin" > "$outfile"; return 0
    fi
    out="$(perl -e 'alarm shift; exec @ARGV' 8 "$bin" ${=1} 2>&1 </dev/null)"
    rc=$?
    # Prefer the number after the last word "version"; otherwise the first version-looking token.
    ver="$(print -r -- "$out" | sed -nE 's/.*[Vv]ersion[: ]+"?[vV]?([0-9]+(\.[0-9]+)+([-+][0-9A-Za-z.]+)?).*/\1/p' | head -1)"
    [[ -z "$ver" ]] && ver="$(print -r -- "$out" | grep -oE '[0-9]+(\.[0-9]+)+([-+][0-9A-Za-z.]+)?' | head -1)"
    if [[ -z "$ver" ]]; then
        (( rc == 142 )) && ver="(timed out after 8s)" || ver="(version not detected)"
    fi
    printf '%s\t%s\t%s\t%s\n' "$category" "$cmd" "$ver" "$bin" > "$outfile"
}

TOOLS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/sysinfo-tools.XXXXXX")" || { print_error "Could not create a temp directory for tool detection."; exit 1; }
trap 'rm -rf "$TOOLS_TMP"' EXIT
idx=0
for entry in "${TOOL_CATALOG[@]}"; do
    (( idx++ ))
    IFS='|' read -r t_cat t_cmd t_args <<< "$entry"
    probe_tool "$TOOLS_TMP/$idx" "$t_cat" "$t_cmd" "$t_args" &
done
# nvm is a shell function, not an executable on PATH.
NVM_HOME="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_HOME/nvm.sh" ]]; then
    NVM_VER="$(sed -nE 's/.*"version": *"([^"]+)".*/\1/p' "$NVM_HOME/package.json" 2>/dev/null | head -1)"
    printf '%s\t%s\t%s\t%s\n' "Version Managers" nvm "${NVM_VER:-(version not detected)}" "$NVM_HOME" > "$TOOLS_TMP/nvm"
fi
wait

TOOLS_TSV=""
for c in "${TOOL_CATEGORY_ORDER[@]}"; do
    for f in "$TOOLS_TMP"/*(Nn); do
        line="$(<"$f")"
        [[ "${line%%$'\t'*}" == "$c" ]] && TOOLS_TSV+="$line"$'\n'
    done
done
# Within a category keep catalog order (files are numbered), nvm last of its category.

# Names already covered by the catalog, so the dynamic lists below only show what is new.
typeset -A KNOWN_CMDS=()
for entry in "${TOOL_CATALOG[@]}"; do KNOWN_CMDS[${${entry#*|}%%|*}]=1; done
typeset -A BREW_ALIAS=(ripgrep rg imagemagick magick awscli aws google-cloud-sdk gcloud azure-cli az openjdk java python python3 fd fd gh gh git-lfs git-lfs vercel-cli vercel)

BREW_FORMULAE=""; BREW_CASKS=""
if command_exists brew; then
    leaves="$(brew leaves --installed-on-request 2>&1)" || { print_warning "Warning: brew leaves failed: ${leaves//$'\n'/ | }"; leaves=""; }
    for leaf in ${(f)leaves}; do
        base="${leaf%%@*}"; base="${leaf:t}"; base="${base%%@*}"
        [[ -n "${KNOWN_CMDS[$base]:-}" || -n "${KNOWN_CMDS[${BREW_ALIAS[$base]:-}]:-}" ]] && continue
        ver="$(brew list --versions "$leaf" 2>/dev/null | awk '{print $2}')"
        BREW_FORMULAE+="$leaf${ver:+ $ver}"$'\n'
    done
    casks="$(brew list --cask --versions 2>&1)" || { print_warning "Warning: brew list --cask failed: ${casks//$'\n'/ | }"; casks=""; }
    BREW_CASKS="$(print -r -- "$casks" | awk 'NF {printf "%s %s\n", $1, $2}')"
fi

# Executables dropped in common user bin dirs that are not in the catalog (listed by name only, never executed).
USER_BINS=""
for d in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin" "$HOME/go/bin" "$HOME/.deno/bin" "$HOME/.volta/bin"; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*(N-*:t); do
        [[ -n "${KNOWN_CMDS[$f]:-}" ]] && continue
        USER_BINS+="$f (${d/#$HOME/~})"$'\n'
    done
done

if (( JSON_OUTPUT )); then
    if (( ! HAVE_PYTHON )); then
        print_error "Python 3 is required for --json output."
        exit 1
    fi
    export COMPUTER_NAME LOCAL_HOSTNAME CURRENT_USER CURRENT_SHELL DISPLAY_MODEL DISPLAY_CHIP ARCH_TYPE \
        TOTAL_MEM_STR MEM_USED_STR SWAP_STR MEM_FREE_PCT SERIAL_NUM HW_UUID FIRMWARE_VER OS_FULL KERNEL_VER UPTIME_INFO \
        BATT_SOURCE BATT_SOC BATT_CHARGING BATT_HEALTH BATT_CYCLES BATT_MAX_CAP BATT_TIME_LEFT BATT_CHARGER_WATTS LOW_POWER_MODE \
        GPU_NAME GPU_CORES DISPLAY_NAME DISPLAY_RES DISPLAYS_JSON \
        ROOT_DISK DISK_TOTAL DISK_USED DISK_AVAIL DISK_PCT DISK_SSD DISK_PROTOCOL \
        NET_IF WIFI_IP WIFI_MAC WIFI_SSID GATEWAY DNS_SERVERS \
        FILEVAULT SIP_STATUS FIREWALL GATEKEEPER \
        TOOLS_TSV BREW_FORMULAE BREW_CASKS USER_BINS
    python3 -c '
import json, os
e = lambda k: os.environ.get(k, "")
tools = []
for line in e("TOOLS_TSV").splitlines():
    parts = line.split("\t")
    if len(parts) == 4:
        tools.append({"category": parts[0], "name": parts[1], "version": parts[2], "path": parts[3]})
data = {
    "device": {"computer_name": e("COMPUTER_NAME"), "local_hostname": e("LOCAL_HOSTNAME"), "user": e("CURRENT_USER"), "shell": e("CURRENT_SHELL")},
    "hardware": {"model": e("DISPLAY_MODEL"), "chip": e("DISPLAY_CHIP"), "architecture": e("ARCH_TYPE"), "memory": e("TOTAL_MEM_STR"),
                 "memory_used": e("MEM_USED_STR"), "swap_used": e("SWAP_STR"), "memory_free_percent": e("MEM_FREE_PCT"),
                 "serial_number": e("SERIAL_NUM"), "uuid": e("HW_UUID"), "firmware": e("FIRMWARE_VER")},
    "os": {"name": e("OS_FULL"), "kernel": e("KERNEL_VER"), "uptime": e("UPTIME_INFO")},
    "power": {"source": e("BATT_SOURCE"), "charge_percent": e("BATT_SOC"), "charging": e("BATT_CHARGING"), "health": e("BATT_HEALTH"),
              "cycle_count": e("BATT_CYCLES"), "max_capacity": e("BATT_MAX_CAP"), "time_remaining": e("BATT_TIME_LEFT"),
              "charger_watts": e("BATT_CHARGER_WATTS"), "low_power_mode": e("LOW_POWER_MODE")},
    "graphics": {"gpu": e("GPU_NAME"), "gpu_cores": e("GPU_CORES"), "display": e("DISPLAY_NAME"), "resolution": e("DISPLAY_RES"),
                 "displays": json.loads(e("DISPLAYS_JSON") or "[]")},
    "storage": {"mount": e("ROOT_DISK"), "total": e("DISK_TOTAL"), "used": e("DISK_USED"), "available": e("DISK_AVAIL"),
                "use_percent": e("DISK_PCT"), "solid_state": e("DISK_SSD"), "protocol": e("DISK_PROTOCOL")},
    "network": {"interface": e("NET_IF"), "ip": e("WIFI_IP"), "mac": e("WIFI_MAC"), "wifi_ssid": e("WIFI_SSID"),
                "gateway": e("GATEWAY"), "dns": e("DNS_SERVERS")},
    "security": {"filevault": e("FILEVAULT"), "sip": e("SIP_STATUS"), "firewall": e("FIREWALL"), "gatekeeper": e("GATEKEEPER")},
    "developer_tools": tools,
    "homebrew_other": {"formulae": [l for l in e("BREW_FORMULAE").splitlines() if l],
                       "casks": [l for l in e("BREW_CASKS").splitlines() if l]},
    "user_bin_other": [l for l in e("USER_BINS").splitlines() if l],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
' || { print_error "Could not build the JSON report."; exit 1; }
    exit 0
fi

# ---------------------------------------------------------------- Default pretty terminal report
row() { printf "  %-18s %s\n" "$1" "$2"; }

print_info "==================================================================="
print_info "                     🍎 macOS Device Information                   "
print_info "==================================================================="
print

print -r -- "${BLUE}💻 Hardware Overview${NC}"
row "Computer Name:"   "$COMPUTER_NAME"
row "Model:"           "$DISPLAY_MODEL"
row "Chip / CPU:"      "$DISPLAY_CHIP"
row "Architecture:"    "$ARCH_TYPE"
row "Memory (RAM):"    "$TOTAL_MEM_STR"
[[ -n "$MEM_USED_STR" ]] && row "Memory In Use:" "$MEM_USED_STR${MEM_FREE_PCT:+ ($MEM_FREE_PCT% free)}${SWAP_STR:+, swap used: $SWAP_STR}"
[[ -n "$SERIAL_NUM" ]]   && row "Serial Number:" "$SERIAL_NUM"
[[ -n "$HW_UUID" ]]      && row "Hardware UUID:" "$HW_UUID"
[[ -n "$FIRMWARE_VER" ]] && row "Firmware:"      "$FIRMWARE_VER"
print

print -r -- "${BLUE}🖥️  Operating System${NC}"
row "OS Version:"      "$OS_FULL"
row "Kernel:"          "$KERNEL_VER"
row "Uptime:"          "${UPTIME_INFO:-Unknown}"
row "Active User:"     "$CURRENT_USER @ $LOCAL_HOSTNAME"
row "Default Shell:"   "$CURRENT_SHELL"
print

if [[ -n "$BATT_SOURCE" || -n "$BATT_SOC" ]]; then
    print -r -- "${BLUE}🔋 Power & Battery${NC}"
    [[ -n "$BATT_SOURCE" ]]  && row "Power Source:" "$BATT_SOURCE${BATT_CHARGER_WATTS:+ (${BATT_CHARGER_WATTS}W adapter)}"
    [[ -n "$BATT_SOC" ]]     && row "Battery Level:" "${BATT_SOC}% (Charging: $BATT_CHARGING)${BATT_TIME_LEFT:+, $BATT_TIME_LEFT remaining}"
    [[ -n "$BATT_HEALTH" ]]  && row "Battery Health:" "$BATT_HEALTH (Max Capacity: $BATT_MAX_CAP, Cycles: $BATT_CYCLES)"
    [[ -n "$LOW_POWER_MODE" ]] && row "Low Power Mode:" "$LOW_POWER_MODE"
    print
fi

if [[ -n "$GPU_NAME" || "$DISPLAYS_JSON" != "[]" ]]; then
    print -r -- "${BLUE}🎮 Graphics & Display${NC}"
    [[ -n "$GPU_NAME" ]] && row "GPU:" "$GPU_NAME${GPU_CORES:+ ($GPU_CORES Cores)}"
    if (( HAVE_PYTHON )) && [[ "$DISPLAYS_JSON" != "[]" ]]; then
        print -rn -- "$DISPLAYS_JSON" | python3 -c '
import json, sys
ds = json.load(sys.stdin)
for i, d in enumerate(ds, 1):
    tags = [t for t in (d["type"], d["connection"], "main" if d["main"] else "") if t]
    label = "Display %d:" % i if len(ds) > 1 else "Display:"
    print("  %-18s %s%s" % (label, d["name"], (" (" + ", ".join(tags) + ")") if tags else ""))
    print("  %-18s %s%s" % ("  Resolution:", d["resolution"], " (native " + d["native_pixels"] + " px)" if d["native_pixels"] else ""))
    if d["refresh_hz"]:
        mx = d["max_refresh_hz"]
        extra = " (max available now: %s Hz)" % mx if mx else ""
        print("  %-18s %s Hz%s" % ("  Refresh Rate:", d["refresh_hz"], extra))
' || print_warning "Warning: could not render display details."
    fi
    print
fi

print -r -- "${BLUE}💾 Storage (Data volume)${NC}"
row "Volume:"          "$ROOT_DISK ($DATA_MOUNT)${DISK_SSD:+, SSD: $DISK_SSD}${DISK_PROTOCOL:+, $DISK_PROTOCOL}"
printf "  %-18s %s Total | %s Used | %s Available (%s Used)\n" "Disk Capacity:" "$DISK_TOTAL" "$DISK_USED" "$DISK_AVAIL" "$DISK_PCT"
print

print -r -- "${BLUE}🌐 Network${NC}"
row "Local IP ($NET_IF):" "${WIFI_IP:-Not connected}"
[[ -n "$GATEWAY" ]]     && row "Gateway:"      "$GATEWAY"
[[ -n "$DNS_SERVERS" ]] && row "DNS:"          "$DNS_SERVERS"
[[ -n "$WIFI_MAC" ]]    && row "MAC Address:"  "$WIFI_MAC"
[[ -n "$WIFI_SSID" ]]   && row "Wi-Fi Network:" "$WIFI_SSID"
print

print -r -- "${BLUE}🔒 Security${NC}"
row "FileVault:"       "$FILEVAULT"
row "SIP:"             "$SIP_STATUS"
row "Firewall:"        "$FIREWALL"
row "Gatekeeper:"      "$GATEKEEPER"
print

print -r -- "${BLUE}📦 Developer Tools (auto-detected)${NC}"
if [[ -z "$TOOLS_TSV" ]]; then
    print -r -- "  No known developer tools found in PATH."
else
    prev_cat=""
    while IFS=$'\t' read -r t_cat t_name t_ver t_path; do
        [[ -z "$t_name" ]] && continue
        if [[ "$t_cat" != "$prev_cat" ]]; then
            print -r -- "  ${YELLOW}$t_cat${NC}"
            prev_cat="$t_cat"
        fi
        printf "    %-16s %-26s %s\n" "$t_name" "$t_ver" "${t_path/#$HOME/~}"
    done <<< "$TOOLS_TSV"
fi
if [[ -n "$BREW_FORMULAE" ]]; then
    print -r -- "  ${YELLOW}Other Homebrew formulae (installed on request)${NC}"
    print -r -- "${BREW_FORMULAE//$'\n'/, }" | sed -E 's/, $//' | fold -s -w 88 | sed 's/^/    /'
fi
if [[ -n "$BREW_CASKS" ]]; then
    print -r -- "  ${YELLOW}Homebrew casks${NC}"
    print -r -- "${BREW_CASKS//$'\n'/, }" | sed -E 's/, $//' | fold -s -w 88 | sed 's/^/    /'
fi
if [[ -n "$USER_BINS" ]]; then
    print -r -- "  ${YELLOW}Other executables in user bin dirs${NC}"
    print -r -- "${USER_BINS//$'\n'/, }" | sed -E 's/, $//' | fold -s -w 88 | sed 's/^/    /'
fi
print

print_success "Device information report complete."
