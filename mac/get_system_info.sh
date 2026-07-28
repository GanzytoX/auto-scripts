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

# Basic System & User
COMPUTER_NAME="$(scutil --get ComputerName 2>/dev/null || hostname)"
LOCAL_HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || hostname)"
CURRENT_USER="$(whoami)"
CURRENT_SHELL="${SHELL:-/bin/zsh}"

# OS Details
PRODUCT_NAME="$(sw_vers -productName 2>/dev/null || echo 'macOS')"
PRODUCT_VERSION="$(sw_vers -productVersion 2>/dev/null)"
BUILD_VERSION="$(sw_vers -buildVersion 2>/dev/null)"
OS_FULL="$PRODUCT_NAME $PRODUCT_VERSION ($BUILD_VERSION)"
KERNEL_VER="$(uname -srm)"
UPTIME_RAW="$(uptime 2>/dev/null)"
UPTIME_INFO="$(print -r -- "$UPTIME_RAW" | sed -E 's/.*up[[:space:]]+([^,]+(,[[:space:]]+[^,]+)?).*/\1/' | sed 's/  */ /g')"

# Hardware Specs via sysctl
MODEL_NAME="$(sysctl -n hw.model 2>/dev/null)"
CPU_BRAND="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
CPU_CORES="$(sysctl -n hw.ncpu 2>/dev/null)"
ARCH_TYPE="$(uname -m)"
TOTAL_MEM_BYTES="$(sysctl -n hw.memsize 2>/dev/null)"
if [[ -n "$TOTAL_MEM_BYTES" ]]; then
    TOTAL_MEM_GB=$(( TOTAL_MEM_BYTES / 1024 / 1024 / 1024 ))
    TOTAL_MEM_STR="${TOTAL_MEM_GB} GB"
else
    TOTAL_MEM_STR="Unknown"
fi

# Rich Hardware Profiler Info
DETAILED_MODEL=""
MODEL_ID=""
CHIP_TYPE=""
SERIAL_NUM=""
HW_UUID=""
HW_JSON="$(system_profiler SPHardwareDataType -json 2>/dev/null)"

if command_exists python3 && [[ -n "$HW_JSON" ]]; then
    eval "$(print -rn -- "$HW_JSON" | python3 -c "import json, sys; d = json.load(sys.stdin).get('SPHardwareDataType', [{}])[0]; print('DETAILED_MODEL=' + repr(str(d.get('machine_name', '')))); print('MODEL_ID=' + repr(str(d.get('machine_model', '')))); print('CHIP_TYPE=' + repr(str(d.get('chip_type', '')))); print('SERIAL_NUM=' + repr(str(d.get('serial_number', '')))); print('HW_UUID=' + repr(str(d.get('platform_UUID', ''))))" 2>/dev/null)"
fi

DISPLAY_MODEL="${DETAILED_MODEL:-$MODEL_NAME}"
[[ -n "$MODEL_ID" ]] && DISPLAY_MODEL="$DISPLAY_MODEL ($MODEL_ID)"
DISPLAY_CHIP="${CHIP_TYPE:-${CPU_BRAND:-$ARCH_TYPE}}"
[[ -n "$CPU_CORES" ]] && DISPLAY_CHIP="$DISPLAY_CHIP ($CPU_CORES Cores)"

# Power & Battery Info
BATT_SOC=""
BATT_CHARGING=""
BATT_HEALTH=""
BATT_CYCLES=""
BATT_MAX_CAP=""
BATT_SOURCE=""
POWER_JSON="$(system_profiler SPPowerDataType -json 2>/dev/null)"

if command_exists python3 && [[ -n "$POWER_JSON" ]]; then
    eval "$(print -rn -- "$POWER_JSON" | python3 -c "import json, sys
data = json.load(sys.stdin).get('SPPowerDataType', [])
info = {}
for item in data:
    if item.get('_name') == 'spbattery_information':
        chg = item.get('sppower_battery_charge_info', {})
        hlth = item.get('sppower_battery_health_info', {})
        info['soc'] = str(chg.get('sppower_battery_state_of_charge', ''))
        info['charging'] = 'Yes' if str(chg.get('sppower_battery_is_charging', '')).upper() == 'TRUE' else 'No'
        info['health'] = str(hlth.get('sppower_battery_health', ''))
        info['cycles'] = str(hlth.get('sppower_battery_cycle_count', ''))
        info['max_cap'] = str(hlth.get('sppower_battery_health_maximum_capacity', ''))
    elif item.get('_name') == 'sppower_information':
        pwr = item.get('Battery Power', {})
        if str(pwr.get('Current Power Source', '')).upper() == 'TRUE':
            info['source'] = 'Battery'
        else:
            info['source'] = 'AC Power'
for k, v in info.items():
    print(f'BATT_{k.upper()}={repr(v)}')
" 2>/dev/null)"
fi

# Graphics Info
GPU_NAME=""
GPU_CORES=""
DISPLAY_NAME=""
DISPLAY_RES=""
DISP_JSON="$(system_profiler SPDisplaysDataType -json 2>/dev/null)"

if command_exists python3 && [[ -n "$DISP_JSON" ]]; then
    eval "$(print -rn -- "$DISP_JSON" | python3 -c "import json, sys
data = json.load(sys.stdin).get('SPDisplaysDataType', [])
if data:
    gpu = data[0]
    print('GPU_NAME=' + repr(str(gpu.get('_name', ''))))
    print('GPU_CORES=' + repr(str(gpu.get('sppci_cores', ''))))
    ndrvs = gpu.get('spdisplays_ndrvs', [])
    if ndrvs:
        print('DISPLAY_NAME=' + repr(str(ndrvs[0].get('_name', ''))))
        print('DISPLAY_RES=' + repr(str(ndrvs[0].get('spdisplays_pixelresolution', ''))))
" 2>/dev/null)"
fi

# Storage Info
ROOT_DISK="$(df -h / 2>/dev/null | awk 'NR==2 {print $1}')"
DISK_TOTAL="$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')"
DISK_USED="$(df -h / 2>/dev/null | awk 'NR==2 {print $3}')"
DISK_AVAIL="$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')"
DISK_PCT="$(df -h / 2>/dev/null | awk 'NR==2 {print $5}')"

# Network Info
WIFI_IP="$(ipconfig getifaddr en0 2>/dev/null)"
WIFI_MAC="$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2}')"
WIFI_SSID="$(ipconfig getsummary en0 2>/dev/null | grep 'SSID : ' | awk -F': ' '{print $2}')"

# Key Developer Runtimes
get_tool_version() {
    local cmd="$1"
    local version_flag="${2:---version}"
    if command_exists "$cmd"; then
        local ver
        ver="$("$cmd" $version_flag 2>/dev/null | head -n 1)"
        print -r -- "${ver:-Installed}"
    else
        print -r -- "Not installed"
    fi
}

BREW_VER="$(get_tool_version brew)"
NODE_VER="$(get_tool_version node)"
NPM_VER="$(get_tool_version npm)"
PNPM_VER="$(get_tool_version pnpm)"
PYTHON_VER="$(get_tool_version python3)"
GIT_VER="$(get_tool_version git)"
DOCKER_VER="$(get_tool_version docker)"

# Output Modes

if (( BRIEF_OUTPUT )); then
    print -r -- "${COMPUTER_NAME} | ${DISPLAY_MODEL} | ${DISPLAY_CHIP} | ${TOTAL_MEM_STR} RAM | ${OS_FULL}"
    exit 0
fi

if (( JSON_OUTPUT )); then
    if command_exists python3; then
        python3 -c "import json, sys
data = {
    'device': {'computer_name': sys.argv[1], 'local_hostname': sys.argv[2], 'user': sys.argv[3], 'shell': sys.argv[4]},
    'hardware': {'model': sys.argv[5], 'chip': sys.argv[6], 'architecture': sys.argv[7], 'memory': sys.argv[8], 'serial_number': sys.argv[9], 'uuid': sys.argv[10]},
    'os': {'name': sys.argv[11], 'kernel': sys.argv[12], 'uptime': sys.argv[13]},
    'power': {'source': sys.argv[14], 'charge_percent': sys.argv[15], 'charging': sys.argv[16], 'health': sys.argv[17], 'cycle_count': sys.argv[18], 'max_capacity': sys.argv[19]},
    'graphics': {'gpu': sys.argv[20], 'gpu_cores': sys.argv[21], 'display': sys.argv[22], 'resolution': sys.argv[23]},
    'storage': {'mount': sys.argv[24], 'total': sys.argv[25], 'used': sys.argv[26], 'available': sys.argv[27], 'use_percent': sys.argv[28]},
    'network': {'ip': sys.argv[29], 'mac': sys.argv[30], 'wifi_ssid': sys.argv[31]},
    'runtimes': {'homebrew': sys.argv[32], 'node': sys.argv[33], 'npm': sys.argv[34], 'pnpm': sys.argv[35], 'python': sys.argv[36], 'git': sys.argv[37], 'docker': sys.argv[38]}
}
print(json.dumps(data, indent=2))" "$COMPUTER_NAME" "$LOCAL_HOSTNAME" "$CURRENT_USER" "$CURRENT_SHELL" \
  "$DISPLAY_MODEL" "$DISPLAY_CHIP" "$ARCH_TYPE" "$TOTAL_MEM_STR" "$SERIAL_NUM" "$HW_UUID" \
  "$OS_FULL" "$KERNEL_VER" "$UPTIME_INFO" \
  "$BATT_SOURCE" "$BATT_SOC" "$BATT_CHARGING" "$BATT_HEALTH" "$BATT_CYCLES" "$BATT_MAX_CAP" \
  "$GPU_NAME" "$GPU_CORES" "$DISPLAY_NAME" "$DISPLAY_RES" \
  "$ROOT_DISK" "$DISK_TOTAL" "$DISK_USED" "$DISK_AVAIL" "$DISK_PCT" \
  "$WIFI_IP" "$WIFI_MAC" "$WIFI_SSID" \
  "$BREW_VER" "$NODE_VER" "$NPM_VER" "$PNPM_VER" "$PYTHON_VER" "$GIT_VER" "$DOCKER_VER"
    else
        print_error "Python 3 is required for --json output."
        exit 1
    fi
    exit 0
fi

# Default Pretty Terminal Report

print_info "==================================================================="
print_info "                     🍎 macOS Device Information                   "
print_info "==================================================================="
print

print -r -- "${BLUE}💻 Hardware Overview${NC}"
printf "  %-18s %s\n" "Computer Name:"   "$COMPUTER_NAME"
printf "  %-18s %s\n" "Model:"           "$DISPLAY_MODEL"
printf "  %-18s %s\n" "Chip / CPU:"      "$DISPLAY_CHIP"
printf "  %-18s %s\n" "Architecture:"    "$ARCH_TYPE"
printf "  %-18s %s\n" "Memory (RAM):"    "$TOTAL_MEM_STR"
[[ -n "$SERIAL_NUM" ]] && printf "  %-18s %s\n" "Serial Number:"   "$SERIAL_NUM"
[[ -n "$HW_UUID" ]]    && printf "  %-18s %s\n" "Hardware UUID:"   "$HW_UUID"
print

print -r -- "${BLUE}🖥️  Operating System${NC}"
printf "  %-18s %s\n" "OS Version:"      "$OS_FULL"
printf "  %-18s %s\n" "Kernel:"          "$KERNEL_VER"
printf "  %-18s %s\n" "Uptime:"          "${UPTIME_INFO:-Unknown}"
printf "  %-18s %s\n" "Active User:"     "$CURRENT_USER @ $LOCAL_HOSTNAME"
printf "  %-18s %s\n" "Default Shell:"   "$CURRENT_SHELL"
print

if [[ -n "$BATT_SOURCE" || -n "$BATT_SOC" ]]; then
    print -r -- "${BLUE}🔋 Power & Battery${NC}"
    [[ -n "$BATT_SOURCE" ]]   && printf "  %-18s %s\n" "Power Source:"   "$BATT_SOURCE"
    [[ -n "$BATT_SOC" ]]      && printf "  %-18s %s%% (Charging: %s)\n" "Battery Level:" "$BATT_SOC" "$BATT_CHARGING"
    [[ -n "$BATT_HEALTH" ]]   && printf "  %-18s %s (Max Capacity: %s, Cycles: %s)\n" "Battery Health:" "$BATT_HEALTH" "$BATT_MAX_CAP" "$BATT_CYCLES"
    print
fi

if [[ -n "$GPU_NAME" || -n "$DISPLAY_NAME" ]]; then
    print -r -- "${BLUE}🎮 Graphics & Display${NC}"
    [[ -n "$GPU_NAME" ]]        && printf "  %-18s %s\n" "GPU:"             "$GPU_NAME ($GPU_CORES Cores)"
    [[ -n "$DISPLAY_NAME" ]]    && printf "  %-18s %s\n" "Display:"         "$DISPLAY_NAME ($DISPLAY_RES)"
    print
fi

print -r -- "${BLUE}💾 Storage (Primary Volume)${NC}"
printf "  %-18s %s\n" "Volume Mount:"    "$ROOT_DISK on /"
printf "  %-18s %s Total | %s Used | %s Available (%s Used)\n" "Disk Capacity:" "$DISK_TOTAL" "$DISK_USED" "$DISK_AVAIL" "$DISK_PCT"
print

print -r -- "${BLUE}🌐 Network Interfaces${NC}"
printf "  %-18s %s\n" "Local IP (en0):"  "${WIFI_IP:-Not connected}"
[[ -n "$WIFI_MAC" ]]  && printf "  %-18s %s\n" "MAC Address:"     "$WIFI_MAC"
[[ -n "$WIFI_SSID" ]] && printf "  %-18s %s\n" "Wi-Fi Network:"   "$WIFI_SSID"
print

print -r -- "${BLUE}📦 Developer Runtimes & Tools${NC}"
printf "  %-18s %s\n" "Homebrew:"        "$BREW_VER"
printf "  %-18s %s\n" "Node.js:"         "$NODE_VER"
printf "  %-18s %s\n" "npm:"             "$NPM_VER"
printf "  %-18s %s\n" "pnpm:"            "$PNPM_VER"
printf "  %-18s %s\n" "Python 3:"        "$PYTHON_VER"
printf "  %-18s %s\n" "Git:"             "$GIT_VER"
printf "  %-18s %s\n" "Docker:"          "$DOCKER_VER"
print

print_success "Device information report complete."
