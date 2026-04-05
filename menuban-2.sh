#!/bin/bash

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_UL=$'\033[4m'

# Premium Color Palette
C_RED=$'\033[38;5;196m'      # Bright Red
C_GREEN=$'\033[38;5;46m'     # Neon Green
C_YELLOW=$'\033[38;5;226m'   # Bright Yellow
C_BLUE=$'\033[38;5;39m'      # Deep Sky Blue
C_PURPLE=$'\033[38;5;135m'   # Light Purple
C_CYAN=$'\033[38;5;51m'      # Cyan
C_WHITE=$'\033[38;5;255m'    # Bright White
C_GRAY=$'\033[38;5;245m'     # Gray
C_ORANGE=$'\033[38;5;208m'   # Orange

# Semantic Aliases
C_TITLE=$C_PURPLE
C_CHOICE=$C_CYAN
C_PROMPT=$C_BLUE
C_WARN=$C_YELLOW
C_DANGER=$C_RED
C_STATUS_A=$C_GREEN
C_STATUS_I=$C_GRAY
C_ACCENT=$C_ORANGE

DB_DIR="/etc/firewallfalcon"
DB_FILE="$DB_DIR/users.db"
INSTALL_FLAG_FILE="$DB_DIR/.install"
BADVPN_SERVICE_FILE="/etc/systemd/system/badvpn.service"
BADVPN_BUILD_DIR="/root/badvpn-build"
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
NGINX_CONFIG_FILE="/etc/nginx/sites-available/default"
SSL_CERT_DIR="/etc/firewallfalcon/ssl"
SSL_CERT_FILE="$SSL_CERT_DIR/firewallfalcon.pem"
SSL_CERT_CHAIN_FILE="$SSL_CERT_DIR/firewallfalcon.crt"
SSL_CERT_KEY_FILE="$SSL_CERT_DIR/firewallfalcon.key"
EDGE_CERT_INFO_FILE="$DB_DIR/edge_cert.conf"
NGINX_PORTS_FILE="$DB_DIR/nginx_ports.conf"
EDGE_PUBLIC_HTTP_PORT="80"
EDGE_PUBLIC_TLS_PORT="443"
NGINX_INTERNAL_HTTP_PORT="8880"
NGINX_INTERNAL_TLS_PORT="8443"
HAPROXY_INTERNAL_DECRYPT_PORT="10443"
DNSTT_SERVICE_FILE="/etc/systemd/system/dnstt.service"
DNSTT_BINARY="/usr/local/bin/dnstt-server"
DNSTT_KEYS_DIR="/etc/firewallfalcon/dnstt"
DNSTT_CONFIG_FILE="$DB_DIR/dnstt_info.conf"
DNS_INFO_FILE="$DB_DIR/dns_info.conf"
UDP_CUSTOM_DIR="/root/udp"
UDP_CUSTOM_SERVICE_FILE="/etc/systemd/system/udp-custom.service"
SSH_BANNER_FILE="/etc/bannerssh"
FALCONPROXY_SERVICE_FILE="/etc/systemd/system/falconproxy.service"
FALCONPROXY_BINARY="/usr/local/bin/falconproxy"
FALCONPROXY_CONFIG_FILE="$DB_DIR/falconproxy_config.conf"
LIMITER_SCRIPT="/usr/local/bin/firewallfalcon-limiter.sh"
LIMITER_SERVICE="/etc/systemd/system/firewallfalcon-limiter.service"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
BANDWIDTH_SCRIPT="/usr/local/bin/firewallfalcon-bandwidth.sh"
BANDWIDTH_SERVICE="/etc/systemd/system/firewallfalcon-bandwidth.service"
TRIAL_CLEANUP_SCRIPT="/usr/local/bin/firewallfalcon-trial-cleanup.sh"
LOGIN_INFO_SCRIPT="/usr/local/bin/firewallfalcon-login-info.sh"
SSHD_FF_CONFIG="/etc/ssh/sshd_config.d/firewallfalcon.conf"

# --- ZiVPN Variables ---
ZIVPN_DIR="/etc/zivpn"
ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE_FILE="/etc/systemd/system/zivpn.service"
ZIVPN_CONFIG_FILE="$ZIVPN_DIR/config.json"
ZIVPN_CERT_FILE="$ZIVPN_DIR/zivpn.crt"
ZIVPN_KEY_FILE="$ZIVPN_DIR/zivpn.key"

DESEC_TOKEN="V55cFY8zTictLCPfviiuX5DHjs15"
DESEC_DOMAIN="manager.firewallfalcon.qzz.io"

TELEGRAM_CONFIG_FILE="$DB_DIR/telegram.conf"
FAIL2BAN_FF_JAIL="/etc/fail2ban/jail.d/firewallfalcon-ssh.conf"
FAIL2BAN_FF_FILTER="/etc/fail2ban/filter.d/firewallfalcon-ssh.conf"
WARP_CONFIG_FILE="$DB_DIR/warp.conf"
SELECTED_USER=""
UNINSTALL_MODE="interactive"
BANNER_CACHE_TTL=15
BANNER_CACHE_TS=0
BANNER_CACHE_OS_NAME=""
BANNER_CACHE_UP_TIME=""
BANNER_CACHE_RAM_USAGE=""
BANNER_CACHE_CPU_LOAD=""
BANNER_CACHE_ONLINE_USERS=0
BANNER_CACHE_TOTAL_USERS=0
SSH_SESSION_CACHE_TTL=10
SSH_SESSION_CACHE_TS=0
SSH_SESSION_CACHE_DB_MTIME=0
SSH_SESSION_TOTAL=0
FF_USERS_GROUP="ffusers"
declare -A SSH_SESSION_COUNTS=()
declare -A SSH_SESSION_PIDS=()

if [[ $EUID -ne 0 ]]; then
   echo -e "${C_RED}❌ Error: This script requires root privileges to run.${C_RESET}"
   exit 1
fi

# Mandatory Dependency Check (Added jq and curl)
check_environment() {
    # Mandatory Dependency Check (Added jq and curl)
    for cmd in bc jq curl wget; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${C_YELLOW}⚠️ Warning: '$cmd' not found. Installing...${C_RESET}"
            apt-get update > /dev/null 2>&1 && apt-get install -y $cmd || {
                echo -e "${C_RED}❌ Error: Failed to install '$cmd'. Please install it manually.${C_RESET}"
                exit 1
            }
        fi
    done
}

ensure_firewallfalcon_dirs() {
    mkdir -p "$DB_DIR" "$SSL_CERT_DIR" "$BANDWIDTH_DIR" /etc/ssh/sshd_config.d
    touch "$DB_FILE"
}

ensure_firewallfalcon_system_group() {
    getent group "$FF_USERS_GROUP" >/dev/null 2>&1 || groupadd "$FF_USERS_GROUP" >/dev/null 2>&1 || true
}

db_has_user() {
    [[ -f "$DB_FILE" ]] || return 1
    awk -F: -v target="$1" '$1 == target { found=1; exit } END { exit(found ? 0 : 1) }' "$DB_FILE"
}

is_firewallfalcon_orphan_user() {
    local username="$1"
    local passwd_line system_user _ uid _ home shell

    passwd_line=$(getent passwd "$username" 2>/dev/null) || return 1
    IFS=: read -r system_user _ uid _ _ home shell <<< "$passwd_line"
    [[ "$uid" =~ ^[0-9]+$ ]] || return 1
    db_has_user "$username" && return 1

    if id -nG "$username" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$FF_USERS_GROUP"; then
        return 0
    fi

    (( uid >= 1000 )) || return 1
    [[ "$home" == "/home/$username" || "$home" == /home/* ]] || return 1

    case "$shell" in
        /usr/sbin/nologin|/usr/bin/false|/bin/false) return 0 ;;
    esac

    return 1
}

get_firewallfalcon_orphan_users() {
    local username
    while IFS=: read -r username _rest; do
        [[ -n "$username" ]] || continue
        if is_firewallfalcon_orphan_user "$username"; then
            echo "$username"
        fi
    done < /etc/passwd
}

get_firewallfalcon_known_users() {
    local username
    local -A seen_users=()

    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r username _rest; do
            [[ -n "$username" && "$username" != \#* ]] || continue
            seen_users["$username"]=1
        done < "$DB_FILE"
    fi

    while IFS= read -r username; do
        [[ -n "$username" ]] && seen_users["$username"]=1
    done < <(get_firewallfalcon_orphan_users)

    (( ${#seen_users[@]} > 0 )) || return 0
    printf "%s\n" "${!seen_users[@]}" | sort
}

delete_firewallfalcon_user_accounts() {
    local -a users_to_delete=("$@")
    local username

    [[ ${#users_to_delete[@]} -gt 0 ]] || return 0

    for username in "${users_to_delete[@]}"; do
        [[ -n "$username" ]] || continue
        killall -u "$username" -9 &>/dev/null
        if id "$username" &>/dev/null; then
            if userdel -r "$username" &>/dev/null; then
                echo -e " ✅ System user '${C_YELLOW}$username${C_RESET}' deleted."
            else
                echo -e " ❌ Failed to delete system user '${C_YELLOW}$username${C_RESET}'."
            fi
        else
            echo -e " ℹ️ System user '${C_YELLOW}$username${C_RESET}' was already missing. Removing manager data only."
        fi
        rm -f "$BANDWIDTH_DIR/${username}.usage"
        rm -rf "$BANDWIDTH_DIR/pidtrack/${username}"
    done

    if [[ -f "$DB_FILE" ]]; then
        local db_tmp
        db_tmp=$(mktemp)
        awk -F: 'NR==FNR { drop[$1]=1; next } !($1 in drop)' <(printf "%s\n" "${users_to_delete[@]}") "$DB_FILE" > "$db_tmp" && mv "$db_tmp" "$DB_FILE"
        rm -f "$db_tmp" 2>/dev/null
    fi

    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

require_interactive_terminal() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo -e "${C_RED}❌ Error: The FirewallFalcon menu must be run from an interactive terminal.${C_RESET}"
        exit 1
    fi
}

initial_setup() {
    echo -e "${C_BLUE}⚙️ Initializing FirewallFalcon Manager setup...${C_RESET}"
    check_environment
    
    ensure_firewallfalcon_dirs
    ensure_firewallfalcon_system_group
    
    echo -e "${C_BLUE}🔹 Configuring user limiter service...${C_RESET}"
    setup_limiter_service
    
    echo -e "${C_BLUE}🔹 Configuring bandwidth monitoring service...${C_RESET}"
    setup_bandwidth_service
    
    echo -e "${C_BLUE}🔹 Installing trial account cleanup script...${C_RESET}"
    setup_trial_cleanup_script
    
    echo -e "${C_BLUE}🔹 Cleaning legacy dynamic SSH banner hooks...${C_RESET}"
    disable_dynamic_ssh_banner_system
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    
    if [ ! -f "$INSTALL_FLAG_FILE" ]; then
        touch "$INSTALL_FLAG_FILE"
    fi
    echo -e "${C_GREEN}✅ Setup finished.${C_RESET}"
}

_is_valid_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

check_and_open_firewall_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local firewall_detected=false

    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        firewall_detected=true
        if ! ufw status | grep -qw "$port/$protocol"; then
            echo -e "${C_YELLOW}🔥 UFW firewall is active and port ${port}/${protocol} is closed.${C_RESET}"
            read -p "👉 Do you want to open this port now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                ufw allow "$port/$protocol"
                echo -e "${C_GREEN}✅ Port ${port}/${protocol} has been opened in UFW.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Port ${port}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
             echo -e "${C_GREEN}✅ Port ${port}/${protocol} is already open in UFW.${C_RESET}"
        fi
    fi

    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall_detected=true
        if ! firewall-cmd --list-ports --permanent | grep -qw "$port/$protocol"; then
            echo -e "${C_YELLOW}🔥 firewalld is active and port ${port}/${protocol} is not open.${C_RESET}"
            read -p "👉 Do you want to open this port now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                firewall-cmd --add-port="$port/$protocol" --permanent
                firewall-cmd --reload
                echo -e "${C_GREEN}✅ Port ${port}/${protocol} has been opened in firewalld.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Port ${port}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Port ${port}/${protocol} is already open in firewalld.${C_RESET}"
        fi
    fi

    if ! $firewall_detected; then
        echo -e "${C_BLUE}ℹ️ No active firewall (UFW or firewalld) detected. Assuming ports are open.${C_RESET}"
    fi
    return 0
}

check_and_free_ports() {
    local ports_to_check=("$@")
    for port in "${ports_to_check[@]}"; do
        echo -e "\n${C_BLUE}🔎 Checking if port $port is available...${C_RESET}"
        local conflicting_process_info
        conflicting_process_info=$(
            ss -H -lntp "( sport = :$port )" 2>/dev/null
            ss -H -lunp "( sport = :$port )" 2>/dev/null
        )
        
        if [[ -n "$conflicting_process_info" ]]; then
            local conflicting_pid
            conflicting_pid=$(echo "$conflicting_process_info" | grep -oP 'pid=\K[0-9]+' | head -n 1)
            local conflicting_name
            conflicting_name=$(echo "$conflicting_process_info" | grep -oP 'users:\(\("(\K[^"]+)' | head -n 1)
            
            echo -e "${C_YELLOW}⚠️ Warning: Port $port is in use by process '${conflicting_name:-unknown}' (PID: ${conflicting_pid:-N/A}).${C_RESET}"
            read -p "👉 Do you want to attempt to stop this process? (y/n): " kill_confirm
            if [[ "$kill_confirm" == "y" || "$kill_confirm" == "Y" ]]; then
                if [[ -z "$conflicting_pid" ]]; then
                    echo -e "${C_RED}❌ Could not determine which PID owns port $port. Please free it manually.${C_RESET}"
                    return 1
                fi
                echo -e "${C_GREEN}🛑 Stopping process PID $conflicting_pid...${C_RESET}"
                systemctl stop "$(ps -p "$conflicting_pid" -o comm=)" &>/dev/null || kill -9 "$conflicting_pid"
                sleep 2
                
                if ss -H -lntp "( sport = :$port )" 2>/dev/null | grep -q . || ss -H -lunp "( sport = :$port )" 2>/dev/null | grep -q .; then
                     echo -e "${C_RED}❌ Failed to free port $port. Please handle it manually. Aborting.${C_RESET}"
                     return 1
                else
                     echo -e "${C_GREEN}✅ Port $port has been successfully freed.${C_RESET}"
                fi
            else
                echo -e "${C_RED}❌ Cannot proceed without freeing port $port. Aborting.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Port $port is free to use.${C_RESET}"
        fi
    done
    return 0
}

setup_limiter_service() {
    # Combined limiter + bandwidth monitoring
    cat > "$LIMITER_SCRIPT" << 'EOF'
#!/bin/bash
# FirewallFalcon limiter version 2026-04-04.1
DB_FILE="/etc/firewallfalcon/users.db"
BW_DIR="/etc/firewallfalcon/bandwidth"
PID_DIR="$BW_DIR/pidtrack"
BANNER_DIR="/etc/firewallfalcon/banners"
SCAN_INTERVAL=30

mkdir -p "$BW_DIR" "$PID_DIR"
shopt -s nullglob

write_banner_if_changed() {
    local user="$1"
    local content="$2"
    local banner_file="$BANNER_DIR/${user}.txt"
    local tmp_file="${banner_file}.tmp"

    printf "%s" "$content" > "$tmp_file"
    if ! cmp -s "$tmp_file" "$banner_file" 2>/dev/null; then
        mv "$tmp_file" "$banner_file"
    else
        rm -f "$tmp_file"
    fi
}

while true; do
    if [[ ! -s "$DB_FILE" ]]; then
        sleep "$SCAN_INTERVAL"
        continue
    fi

    current_ts=$(date +%s)
    dynamic_banners_enabled=false
    declare -A session_pids=()
    declare -A locked_users=()
    declare -A uid_to_user=()
    declare -A loginuid_pids=()

    while IFS=: read -r username _ uid _rest; do
        [[ -n "$username" && "$uid" =~ ^[0-9]+$ ]] && uid_to_user["$uid"]="$username"
    done < /etc/passwd

    while read -r ssh_pid ssh_owner; do
        [[ "$ssh_pid" =~ ^[0-9]+$ ]] || continue

        if [[ -n "$ssh_owner" && "$ssh_owner" != "root" && "$ssh_owner" != "sshd" ]]; then
            session_pids["$ssh_owner"]+="$ssh_pid "
        fi
    done < <(ps -C sshd -o pid=,user= 2>/dev/null)

    for p in /proc/[0-9]*/loginuid; do
        [[ -f "$p" ]] || continue
        login_uid=""
        read -r login_uid < "$p" || login_uid=""
        [[ "$login_uid" =~ ^[0-9]+$ && "$login_uid" != "4294967295" ]] || continue

        session_user="${uid_to_user[$login_uid]}"
        [[ -n "$session_user" ]] || continue

        pid_dir=$(dirname "$p")
        pid_num=$(basename "$pid_dir")
        comm=""
        read -r comm < "$pid_dir/comm" || comm=""
        [[ "$comm" == "sshd" ]] || continue
        grep -q "^State:.*Z" "$pid_dir/status" 2>/dev/null && continue

        ppid_val=""
        while read -r key value; do
            if [[ "$key" == "PPid:" ]]; then
                ppid_val="${value:-}"
                break
            fi
        done < "$pid_dir/status"
        [[ "$ppid_val" == "1" ]] && continue

        loginuid_pids["$session_user"]+="$pid_num "
    done

    while read -r passwd_user _ passwd_status _rest; do
        [[ "$passwd_status" == "L" ]] && locked_users["$passwd_user"]=1
    done < <(passwd -Sa 2>/dev/null)

    if [[ -f "/etc/firewallfalcon/banners_enabled" ]]; then
        mkdir -p "$BANNER_DIR"
        dynamic_banners_enabled=true
    fi

    while IFS=: read -r user pass expiry limit bandwidth_gb _extra; do
        [[ -z "$user" || "$user" == \#* ]] && continue

        declare -A unique_pids=()
        for pid in ${session_pids["$user"]} ${loginuid_pids["$user"]}; do
            [[ "$pid" =~ ^[0-9]+$ ]] && unique_pids["$pid"]=1
        done

        online_count=${#unique_pids[@]}
        user_locked=false
        if [[ -n "${locked_users[$user]+x}" ]]; then
            user_locked=true
        fi

        expiry_ts=0
        if [[ "$expiry" != "Never" && -n "$expiry" ]]; then
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ "$expiry_ts" =~ ^[0-9]+$ ]] && (( expiry_ts > 0 && expiry_ts < current_ts )); then
                if ! $user_locked; then
                    usermod -L "$user" &>/dev/null
                    killall -u "$user" -9 &>/dev/null
                    locked_users["$user"]=1
                fi
                continue
            fi
        fi

        [[ "$limit" =~ ^[0-9]+$ ]] || limit=1
        if (( online_count > limit )); then
            if ! $user_locked; then
                usermod -L "$user" &>/dev/null
                killall -u "$user" -9 &>/dev/null
                touch "/run/ff_sessionban_${user}" 2>/dev/null
                # Telegram alert for session ban
                if [[ -f "/etc/firewallfalcon/telegram.conf" ]]; then
                    source /etc/firewallfalcon/telegram.conf
                    tg_alert_ban="${tg_alert_ban:-true}"
                    if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" && "$tg_alert_ban" == "true" ]]; then
                        hostname=$(hostname -f 2>/dev/null || hostname)
                        msg="🚫 *BAN sesyjny*%0A👤 Użytkownik: ${user}%0A🔢 Sesje: ${online_count}/${limit}%0A⏱️ Ban na 120 sekund"
                        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" -d chat_id="${TG_CHAT_ID}" -d parse_mode="Markdown" -d text="🖥️ *${hostname}*%0A${msg}" -o /dev/null --max-time 5 &
                    fi
                fi
                (sleep 120; usermod -U "$user" &>/dev/null; rm -f "/run/ff_sessionban_${user}" 2>/dev/null) &
                locked_users["$user"]=1
                user_locked=true
            else
                killall -u "$user" -9 &>/dev/null
            fi
        fi

        if $dynamic_banners_enabled; then
            days_left="N/A"
            if [[ "$expiry" != "Never" && -n "$expiry" && "$expiry_ts" =~ ^[0-9]+$ && $expiry_ts -gt 0 ]]; then
                diff_secs=$((expiry_ts - current_ts))
                if (( diff_secs <= 0 )); then
                    days_left="EXPIRED"
                else
                    d_l=$(( diff_secs / 86400 ))
                    h_l=$(( (diff_secs % 86400) / 3600 ))
                    if (( d_l == 0 )); then
                        days_left="${h_l}h left"
                    else
                        days_left="${d_l}d ${h_l}h"
                    fi
                fi
            fi

            bw_info="Unlimited"
            if [[ "$bandwidth_gb" != "0" && -n "$bandwidth_gb" ]]; then
                usagefile="$BW_DIR/${user}.usage"
                accum_disp=0
                if [[ -f "$usagefile" ]]; then
                    read -r accum_disp < "$usagefile"
                    [[ "$accum_disp" =~ ^[0-9]+$ ]] || accum_disp=0
                fi
                used_gb=$(awk "BEGIN {printf \"%.2f\", $accum_disp / 1073741824}")
                remain_gb=$(awk "BEGIN {r=$bandwidth_gb - $used_gb; if(r<0) r=0; printf \"%.2f\", r}")
                bw_info="${used_gb}/${bandwidth_gb} GB used | ${remain_gb} GB left"
            fi

            banner_content="<br><font color=\"yellow\"><b>      ✨ ACCOUNT STATUS ✨      </b></font><br><br>"
            banner_content+="<font color=\"white\">👤 <b>Username   :</b> $user</font><br>"
            banner_content+="<font color=\"white\">📅 <b>Expiration :</b> $expiry ($days_left)</font><br>"
            banner_content+="<font color=\"white\">📊 <b>Bandwidth  :</b> $bw_info</font><br>"
            banner_content+="<font color=\"white\">🔌 <b>Sessions   :</b> $online_count/$limit</font><br><br>"
            write_banner_if_changed "$user" "$banner_content"
        fi

        [[ -z "$bandwidth_gb" || "$bandwidth_gb" == "0" ]] && continue

        usagefile="$BW_DIR/${user}.usage"
        accumulated=0
        if [[ -f "$usagefile" ]]; then
            read -r accumulated < "$usagefile"
            [[ "$accumulated" =~ ^[0-9]+$ ]] || accumulated=0
        fi

        if (( ${#unique_pids[@]} == 0 )); then
            rm -f "$PID_DIR/${user}__"*.last 2>/dev/null
            continue
        fi

        delta_total=0
        for pid in "${!unique_pids[@]}"; do
            io_file="/proc/$pid/io"
            cur=0
            if [[ -r "$io_file" ]]; then
                rchar=0
                wchar=0
                while read -r key value; do
                    case "$key" in
                        rchar:) rchar=${value:-0} ;;
                        wchar:) wchar=${value:-0} ;;
                    esac
                done < "$io_file"
                cur=$((rchar + wchar))
            fi

            pidfile="$PID_DIR/${user}__${pid}.last"
            if [[ -f "$pidfile" ]]; then
                read -r prev < "$pidfile"
                [[ "$prev" =~ ^[0-9]+$ ]] || prev=0
                if (( cur >= prev )); then
                    d=$((cur - prev))
                else
                    d=$cur
                fi
                delta_total=$((delta_total + d))
            fi
            printf "%s\n" "$cur" > "$pidfile"
        done

        for f in "$PID_DIR/${user}__"*.last; do
            [[ -f "$f" ]] || continue
            fpid=${f##*__}
            fpid=${fpid%.last}
            [[ -d "/proc/$fpid" ]] || rm -f "$f"
        done

        new_total=$((accumulated + delta_total))
        printf "%s\n" "$new_total" > "$usagefile"

        quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
        if [[ "$quota_bytes" =~ ^[0-9]+$ ]] && (( new_total >= quota_bytes )); then
            if ! $user_locked; then
                usermod -L "$user" &>/dev/null
                killall -u "$user" -9 &>/dev/null
                locked_users["$user"]=1
            fi
        fi
    done < "$DB_FILE"

    sleep "$SCAN_INTERVAL"
done
EOF
    chmod +x "$LIMITER_SCRIPT"
    # Strip DOS line endings in case menu.sh was uploaded from Windows
    sed -i 's/\r$//' "$LIMITER_SCRIPT" 2>/dev/null

    cat > "$LIMITER_SERVICE" << EOF
[Unit]
Description=FirewallFalcon Active User Limiter
After=network.target

[Service]
Type=simple
ExecStart=$LIMITER_SCRIPT
Restart=always
RestartSec=10
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7

[Install]
WantedBy=multi-user.target
EOF
    sed -i 's/\r$//' "$LIMITER_SERVICE" 2>/dev/null

    pkill -f "firewallfalcon-limiter" 2>/dev/null

    if ! systemctl is-active --quiet firewallfalcon-limiter; then
        systemctl daemon-reload
        systemctl enable firewallfalcon-limiter &>/dev/null
        systemctl start firewallfalcon-limiter --no-block &>/dev/null
        
    else
        systemctl restart firewallfalcon-limiter --no-block &>/dev/null
        
    fi
}

sync_runtime_components_if_needed() {
    local limiter_marker="# FirewallFalcon limiter version 2026-04-04.1"
    if [[ ! -f "$LIMITER_SCRIPT" ]] || ! grep -Fqx "$limiter_marker" "$LIMITER_SCRIPT" 2>/dev/null; then
        setup_limiter_service >/dev/null 2>&1
    fi
    if [[ -f "$BADVPN_SERVICE_FILE" ]]; then
        ensure_badvpn_service_is_quiet
    fi
    if [[ -f "/etc/firewallfalcon/banners_enabled" ]]; then
        update_ssh_banners_config
    elif [[ -f "$SSHD_FF_CONFIG" ]]; then
        disable_dynamic_ssh_banner_system
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    fi
}

setup_bandwidth_service() {
    mkdir -p "$BANDWIDTH_DIR"
    # Bandwidth monitoring is now integrated into the limiter service above.
    # Stop the old standalone bandwidth service if it exists.
    if systemctl is-active --quiet firewallfalcon-bandwidth 2>/dev/null; then
        systemctl stop firewallfalcon-bandwidth &>/dev/null
        systemctl disable firewallfalcon-bandwidth &>/dev/null
    fi
    rm -f "$BANDWIDTH_SERVICE" "$BANDWIDTH_SCRIPT" 2>/dev/null
}

setup_trial_cleanup_script() {
    cat > "$TRIAL_CLEANUP_SCRIPT" << 'TREOF'
#!/bin/bash
# FirewallFalcon Trial Account Auto-Cleanup
# Usage: firewallfalcon-trial-cleanup.sh <username>
DB_FILE="/etc/firewallfalcon/users.db"
BW_DIR="/etc/firewallfalcon/bandwidth"

username="$1"
if [[ -z "$username" ]]; then exit 1; fi

# Kill active sessions
killall -u "$username" -9 &>/dev/null
sleep 1

# Delete system user
userdel -r "$username" &>/dev/null

# Remove from DB
sed -i "/^${username}:/d" "$DB_FILE"

# Remove bandwidth tracking
rm -f "$BW_DIR/${username}.usage"
rm -rf "$BW_DIR/pidtrack/${username}"
TREOF
    chmod +x "$TRIAL_CLEANUP_SCRIPT"
}

disable_dynamic_ssh_banner_system() {
    rm -f "/etc/firewallfalcon/banners_enabled" "$SSHD_FF_CONFIG" /usr/local/bin/firewallfalcon-login-info.sh 2>/dev/null
    rm -rf "/etc/firewallfalcon/banners" 2>/dev/null
    invalidate_banner_cache
}

disable_static_ssh_banner_in_sshd_config() {
    sed -i.bak -E "s|^[[:space:]]*Banner[[:space:]]+$SSH_BANNER_FILE[[:space:]]*$|# Banner $SSH_BANNER_FILE|" /etc/ssh/sshd_config 2>/dev/null
}

is_static_ssh_banner_enabled() {
    grep -q -E "^[[:space:]]*Banner[[:space:]]+$SSH_BANNER_FILE[[:space:]]*$" /etc/ssh/sshd_config 2>/dev/null && [ -f "$SSH_BANNER_FILE" ]
}

is_dynamic_ssh_banner_enabled() {
    [[ -f "/etc/firewallfalcon/banners_enabled" && -f "$SSHD_FF_CONFIG" ]]
}

get_ssh_banner_mode() {
    if is_dynamic_ssh_banner_enabled; then
        echo "dynamic"
    elif is_static_ssh_banner_enabled; then
        echo "static"
    else
        echo "disabled"
    fi
}

refresh_dynamic_banner_routing_if_enabled() {
    if is_dynamic_ssh_banner_enabled; then
        update_ssh_banners_config
    fi
}

update_ssh_banners_config() {
    local tmp_conf

    if [[ ! -f "/etc/firewallfalcon/banners_enabled" ]]; then
        if [[ -f "$SSHD_FF_CONFIG" ]]; then
            rm -f "$SSHD_FF_CONFIG" 2>/dev/null
            systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
        fi
        return
    fi

    ensure_firewallfalcon_dirs
    tmp_conf="/tmp/ff_banners_new.conf"
    echo "# FirewallFalcon - Dynamic per-user SSH banners" > "$tmp_conf"

    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r u _rest; do
            [[ -z "$u" || "$u" == \#* ]] && continue
            echo "Match User $u" >> "$tmp_conf"
            echo "    Banner /etc/firewallfalcon/banners/${u}.txt" >> "$tmp_conf"
        done < "$DB_FILE"
    fi

    if ! cmp -s "$tmp_conf" "$SSHD_FF_CONFIG" 2>/dev/null; then
        mv "$tmp_conf" "$SSHD_FF_CONFIG"
        if ! grep -q "^Include /etc/ssh/sshd_config.d/" /etc/ssh/sshd_config 2>/dev/null; then
            echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
        fi
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    else
        rm -f "$tmp_conf"
    fi
}

setup_ssh_login_info() {
    ensure_firewallfalcon_dirs || return 1
    if ! touch "/etc/firewallfalcon/banners_enabled"; then
        echo -e "${C_RED}❌ Failed to enable dynamic SSH banners.${C_RESET}"
        return 1
    fi
    disable_static_ssh_banner_in_sshd_config
    update_ssh_banners_config
    return 0
}


generate_dns_record() {
    echo -e "\n${C_BLUE}⚙️ Generating a random domain...${C_RESET}"
    if ! command -v jq &> /dev/null; then
        echo -e "${C_YELLOW}⚠️ jq not found, attempting to install...${C_RESET}"
        apt-get update > /dev/null 2>&1 && apt-get install -y jq || {
            echo -e "${C_RED}❌ Failed to install jq. Cannot manage DNS records.${C_RESET}"
            return 1
        }
    fi
    local SERVER_IPV4
    SERVER_IPV4=$(curl -s -4 icanhazip.com)
    if ! _is_valid_ipv4 "$SERVER_IPV4"; then
        echo -e "\n${C_RED}❌ Error: Could not retrieve a valid public IPv4 address from icanhazip.com.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Please check your server's network connection and DNS resolver settings.${C_RESET}"
        echo -e "   Output received: '$SERVER_IPV4'"
        return 1
    fi

    local SERVER_IPV6
    SERVER_IPV6=$(curl -s -6 icanhazip.com --max-time 5)

    local RANDOM_SUBDOMAIN="vps-$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
    local FULL_DOMAIN="$RANDOM_SUBDOMAIN.$DESEC_DOMAIN"
    local HAS_IPV6="false"

    local API_DATA
    API_DATA=$(printf '[{"subname": "%s", "type": "A", "ttl": 3600, "records": ["%s"]}]' "$RANDOM_SUBDOMAIN" "$SERVER_IPV4")

    if [[ -n "$SERVER_IPV6" ]]; then
        local aaaa_record
        aaaa_record=$(printf ',{"subname": "%s", "type": "AAAA", "ttl": 3600, "records": ["%s"]}' "$RANDOM_SUBDOMAIN" "$SERVER_IPV6")
        API_DATA="${API_DATA%?}${aaaa_record}]"
        HAS_IPV6="true"
    fi

    local CREATE_RESPONSE
    CREATE_RESPONSE=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" \
        --data "$API_DATA")
    
    local HTTP_CODE=${CREATE_RESPONSE: -3}
    local RESPONSE_BODY=${CREATE_RESPONSE:0:${#CREATE_RESPONSE}-3}

    if [[ "$HTTP_CODE" -ne 201 ]]; then
        echo -e "${C_RED}❌ Failed to create DNS records. API returned HTTP $HTTP_CODE.${C_RESET}"
        if ! echo "$RESPONSE_BODY" | jq . > /dev/null 2>&1; then
            echo "Raw Response: $RESPONSE_BODY"
        else
            echo "Response: $RESPONSE_BODY" | jq
        fi
        return 1
    fi
    
    cat > "$DNS_INFO_FILE" <<-EOF
SUBDOMAIN="$RANDOM_SUBDOMAIN"
FULL_DOMAIN="$FULL_DOMAIN"
HAS_IPV6="$HAS_IPV6"
EOF
    echo -e "\n${C_GREEN}✅ Successfully created domain: ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
}

delete_dns_record() {
    if [ ! -f "$DNS_INFO_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ No domain to delete.${C_RESET}"
        return
    fi
    echo -e "\n${C_BLUE}🗑️ Deleting DNS records...${C_RESET}"
    source "$DNS_INFO_FILE"
    if [[ -z "$SUBDOMAIN" ]]; then
        echo -e "${C_RED}❌ Could not read record details from config file. Skipping deletion.${C_RESET}"
        return
    fi

    curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$SUBDOMAIN/A/" \
         -H "Authorization: Token $DESEC_TOKEN" > /dev/null

    if [[ "$HAS_IPV6" == "true" ]]; then
        curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$SUBDOMAIN/AAAA/" \
             -H "Authorization: Token $DESEC_TOKEN" > /dev/null
    fi

    echo -e "\n${C_GREEN}✅ Deleted domain: ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
    rm -f "$DNS_INFO_FILE"
}

dns_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🌐 DNS Domain Management ---${C_RESET}"
    if [ -f "$DNS_INFO_FILE" ]; then
        source "$DNS_INFO_FILE"
        echo -e "\nℹ️ A domain already exists for this server:"
        echo -e "  - ${C_CYAN}Domain:${C_RESET} ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
        echo
        read -p "👉 Do you want to DELETE this domain? (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            delete_dns_record
        else
            echo -e "\n${C_YELLOW}❌ Action cancelled.${C_RESET}"
        fi
    else
        echo -e "\nℹ️ No domain has been generated for this server yet."
        echo
        read -p "👉 Do you want to generate a new random domain now? (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            generate_dns_record
        else
            echo -e "\n${C_YELLOW}❌ Action cancelled.${C_RESET}"
        fi
    fi
}

_select_user_interface() {
    local title="$1"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}${title}${C_RESET}\n"
    if [[ ! -s $DB_FILE ]]; then
        echo -e "${C_YELLOW}ℹ️ No users found in the database.${C_RESET}"
        SELECTED_USER="NO_USERS"; return
    fi
    
    mapfile -t all_users < <(cut -d: -f1 "$DB_FILE" | sort)
    local -A all_user_lookup=()
    local username
    for username in "${all_users[@]}"; do
        all_user_lookup["$username"]=1
    done
    
    if [ ${#all_users[@]} -ge 15 ]; then
        read -p "👉 Enter a search term (or press Enter to list all): " search_term
        if [[ -n "$search_term" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -i "$search_term")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ No users found matching your criteria.${C_RESET}"
        SELECTED_USER="NO_USERS"; return
    fi
    echo -e "\nPlease select a user:\n"
    for i in "${!users[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${users[$i]}"
    done
    echo -e "\n  ${C_RED} [ 0]${C_RESET} ↩️ Cancel and return to main menu"
    echo -e "${C_CYAN}💡 Tip: you can also type the exact username directly.${C_RESET}"
    echo
    local choice
    while true; do
        if ! read -r -p "👉 Enter the number or exact username: " choice; then
            echo
            SELECTED_USER=""
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le "${#users[@]}" ]; then
            if [ "$choice" -eq 0 ]; then
                SELECTED_USER=""; return
            else
                SELECTED_USER="${users[$((choice-1))]}"; return
            fi
        elif [[ -n "${all_user_lookup[$choice]+x}" ]]; then
            SELECTED_USER="$choice"; return
        else
            echo -e "${C_RED}❌ Invalid selection. Please try again.${C_RESET}"
        fi
    done
}

_select_multi_user_interface() {
    local title="$1"
    local include_orphan_users="${2:-false}"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}${title}${C_RESET}\n"
    SELECTED_USERS=()
    local -a all_users=()
    local -a orphan_users=()
    local -A all_user_lookup=()
    local -A orphan_user_lookup=()
    local username

    if [[ -s $DB_FILE ]]; then
        mapfile -t all_users < <(cut -d: -f1 "$DB_FILE" | sort)
    fi

    if [[ "$include_orphan_users" == "true" ]]; then
        mapfile -t orphan_users < <(get_firewallfalcon_orphan_users)
        for username in "${orphan_users[@]}"; do
            orphan_user_lookup["$username"]=1
            if ! printf "%s\n" "${all_users[@]}" | grep -Fxq "$username"; then
                all_users+=("$username")
            fi
        done
        if [[ ${#all_users[@]} -gt 0 ]]; then
            mapfile -t all_users < <(printf "%s\n" "${all_users[@]}" | sort)
        fi
    fi

    if [[ ${#all_users[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}ℹ️ No users found in the manager database.${C_RESET}"
        if [[ "$include_orphan_users" == "true" ]]; then
            echo -e "${C_DIM}No orphan FirewallFalcon system users were found either.${C_RESET}"
        fi
        SELECTED_USERS=("NO_USERS"); return
    fi

    for username in "${all_users[@]}"; do
        all_user_lookup["$username"]=1
    done
    
    if [ ${#all_users[@]} -ge 15 ]; then
        read -p "👉 Enter a search term (or press Enter to list all): " search_term
        if [[ -n "$search_term" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -i "$search_term")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ No users found matching your criteria.${C_RESET}"
        SELECTED_USERS=("NO_USERS"); return
    fi
    echo -e "\nPlease select users:\n"
    for i in "${!users[@]}"; do
        local display_user="${users[$i]}"
        if [[ "$include_orphan_users" == "true" && -n "${orphan_user_lookup[${users[$i]}]+x}" ]]; then
            display_user="${display_user} ${C_DIM}(system-only)${C_RESET}"
        fi
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "$display_user"
    done
    echo -e "\n  ${C_GREEN}[all]${C_RESET} Select ALL listed users"
    echo -e "  ${C_RED}  [0]${C_RESET} ↩️ Cancel and return to main menu"
    echo -e "\n${C_CYAN}💡 You can select multiple by number, range, or exact username.${C_RESET}"
    echo -e "${C_CYAN}   Examples: '1 3 5' or '1,3' or '1-4' or 'alice bob'${C_RESET}"
    if [[ "$include_orphan_users" == "true" ]]; then
        echo -e "${C_CYAN}   Users marked '(system-only)' are old accounts still on the VPS but missing from users.db${C_RESET}"
    fi
    echo
    local choice
    while true; do
        if ! read -r -p "👉 Enter user numbers or usernames: " choice; then
            echo
            SELECTED_USERS=()
            return
        fi
        choice=$(echo "$choice" | tr ',' ' ') # Replace commas with spaces
        
        if [[ -z "$choice" ]]; then
            echo -e "${C_RED}❌ Invalid selection. Please try again.${C_RESET}"
            continue
        fi

        if [[ "$choice" == "0" ]]; then
            SELECTED_USERS=(); return
        fi
        
        if [[ "${choice,,}" == "all" ]]; then
            SELECTED_USERS=("${users[@]}")
            return
        fi
        
        local valid=true
        local selected_indices=()
        local selected_names=()
        for token in $choice; do
            if [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
                local start=${token%-*}
                local end=${token#*-}
                if [ "$start" -le "$end" ]; then
                    for (( idx=start; idx<=end; idx++ )); do
                        if [ "$idx" -ge 1 ] && [ "$idx" -le "${#users[@]}" ]; then
                            selected_indices+=($idx)
                        else
                            valid=false; break
                        fi
                    done
                else
                    valid=false; break
                fi
            elif [[ "$token" =~ ^[0-9]+$ ]]; then
                if [ "$token" -ge 1 ] && [ "$token" -le "${#users[@]}" ]; then
                    selected_indices+=($token)
                elif [[ -n "${all_user_lookup[$token]+x}" ]]; then
                    selected_names+=("$token")
                else
                    valid=false; break
                fi
            elif [[ -n "${all_user_lookup[$token]+x}" ]]; then
                selected_names+=("$token")
            else
                valid=false; break
            fi
        done
        
        if [[ "$valid" == true && ( ${#selected_indices[@]} -gt 0 || ${#selected_names[@]} -gt 0 ) ]]; then
            mapfile -t unique_indices < <(printf "%s\n" "${selected_indices[@]}" | sort -u -n)
            for idx in "${unique_indices[@]}"; do
                SELECTED_USERS+=("${users[$((idx-1))]}")
            done
            mapfile -t unique_names < <(printf "%s\n" "${selected_names[@]}" | sort -u)
            for username in "${unique_names[@]}"; do
                if ! printf "%s\n" "${SELECTED_USERS[@]}" | grep -Fxq "$username"; then
                    SELECTED_USERS+=("$username")
                fi
            done
            return
        else
            echo -e "${C_RED}❌ Invalid selection. Please check your numbers or usernames.${C_RESET}"
            SELECTED_USERS=()
            selected_indices=()
            selected_names=()
        fi
    done
}

get_user_status() {
    local username="$1"
    if ! id "$username" &>/dev/null; then echo -e "${C_RED}Not Found${C_RESET}"; return; fi
    local expiry_date=$(grep "^$username:" "$DB_FILE" | cut -d: -f3)
    if passwd -S "$username" 2>/dev/null | grep -q " L "; then echo -e "${C_YELLOW}🔒 Locked${C_RESET}"; return; fi
    local expiry_ts=$(date -d "$expiry_date" +%s 2>/dev/null || echo 0)
    local current_ts=$(date +%s)
    if [[ $expiry_ts -lt $current_ts ]]; then echo -e "${C_RED}🗓️ Expired${C_RESET}"; return; fi
    echo -e "${C_GREEN}🟢 Active${C_RESET}"
}

create_user() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✨ Create New SSH User ---${C_RESET}"
    read -p "👉 Enter username (or '0' to cancel): " username
    local adopt_existing=false
    if [[ "$username" == "0" ]]; then
        echo -e "\n${C_YELLOW}❌ User creation cancelled.${C_RESET}"
        return
    fi
    if [[ -z "$username" ]]; then
        echo -e "\n${C_RED}❌ Error: Username cannot be empty.${C_RESET}"
        return
    fi
    if db_has_user "$username"; then
        echo -e "\n${C_RED}❌ Error: User '$username' already exists in FirewallFalcon.${C_RESET}"
        return
    fi
    if id "$username" &>/dev/null; then
        if is_firewallfalcon_orphan_user "$username"; then
            echo -e "\n${C_YELLOW}⚠️ User '$username' already exists on the system but is missing from users.db.${C_RESET}"
            echo -e "${C_DIM}This usually happens after uninstalling the script without deleting the SSH users.${C_RESET}"
            read -p "👉 Do you want to take control of this existing user and manage it with FirewallFalcon? (y/n): " adopt_confirm
            if [[ "$adopt_confirm" == "y" || "$adopt_confirm" == "Y" ]]; then
                adopt_existing=true
            else
                echo -e "\n${C_YELLOW}❌ User creation cancelled.${C_RESET}"
                return
            fi
        else
            echo -e "\n${C_RED}❌ Error: System user '$username' already exists and does not look like a FirewallFalcon SSH account.${C_RESET}"
            return
        fi
    fi
    local password=""
    while true; do
        read -p "🔑 Enter password (or press Enter for auto-generated): " password
        if [[ -z "$password" ]]; then
            password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
            echo -e "${C_GREEN}🔑 Auto-generated password: ${C_YELLOW}$password${C_RESET}"
            break
        else
            break
        fi
    done
    read -p "🗓️ Enter account duration (in days) [30]: " days
    days=${days:-30}
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    read -p "📶 Enter simultaneous connection limit [1]: " limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    read -p "📦 Enter bandwidth limit in GB (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    local expire_date
    expire_date=$(date -d "+$days days" +%Y-%m-%d)
    ensure_firewallfalcon_system_group
    if [[ "$adopt_existing" == "true" ]]; then
        usermod -s /usr/sbin/nologin "$username" &>/dev/null
    else
        useradd -m -s /usr/sbin/nologin "$username"
    fi
    usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
    echo "$username:$password" | chpasswd; chage -E "$expire_date" "$username"
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb" >> "$DB_FILE"
    
    local bw_display="Unlimited"
    if [[ "$bandwidth_gb" != "0" ]]; then bw_display="${bandwidth_gb} GB"; fi
    
    clear; show_banner
    if [[ "$adopt_existing" == "true" ]]; then
        echo -e "${C_GREEN}✅ Existing system user '$username' has been imported into FirewallFalcon!${C_RESET}\n"
    else
        echo -e "${C_GREEN}✅ User '$username' created successfully!${C_RESET}\n"
    fi
    echo -e "  - 👤 Username:          ${C_YELLOW}$username${C_RESET}"
    echo -e "  - 🔑 Password:          ${C_YELLOW}$password${C_RESET}"
    echo -e "  - 🗓️ Expires on:        ${C_YELLOW}$expire_date${C_RESET}"
    echo -e "  - 📶 Connection Limit:  ${C_YELLOW}$limit${C_RESET}"
    echo -e "  - 📦 Bandwidth Limit:   ${C_YELLOW}$bw_display${C_RESET}"
    echo -e "    ${C_DIM}(Active monitoring service will enforce these limits)${C_RESET}"

    # Auto-ask for config generation
    echo
    read -p "👉 Do you want to generate a client connection config for this user? (y/n): " gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_client_config "$username" "$password"
    fi
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

delete_user() {
    _select_multi_user_interface "--- 🗑️ Delete FirewallFalcon Users ---" "true"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_RED}⚠️ You selected ${#SELECTED_USERS[@]} user(s) to delete: ${C_YELLOW}${SELECTED_USERS[*]}${C_RESET}"
    read -p "👉 Are you sure you want to PERMANENTLY delete them? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo -e "\n${C_YELLOW}❌ Deletion cancelled.${C_RESET}"; return; fi
    
    echo -e "\n${C_BLUE}🗑️ Deleting selected users...${C_RESET}"
    delete_firewallfalcon_user_accounts "${SELECTED_USERS[@]}"
}

edit_user() {
    _select_user_interface "--- ✏️ Edit a User ---"
    local username=$SELECTED_USER
    if [[ "$username" == "NO_USERS" ]] || [[ -z "$username" ]]; then return; fi
    while true; do
        clear; show_banner; echo -e "${C_BOLD}${C_PURPLE}--- Editing User: ${C_YELLOW}$username${C_PURPLE} ---${C_RESET}"
        
        # Show current user details
        local current_line; current_line=$(grep "^$username:" "$DB_FILE")
        local cur_pass; cur_pass=$(echo "$current_line" | cut -d: -f2)
        local cur_expiry; cur_expiry=$(echo "$current_line" | cut -d: -f3)
        local cur_limit; cur_limit=$(echo "$current_line" | cut -d: -f4)
        local cur_bw; cur_bw=$(echo "$current_line" | cut -d: -f5)
        [[ -z "$cur_bw" ]] && cur_bw="0"
        local cur_bw_display="Unlimited"; [[ "$cur_bw" != "0" ]] && cur_bw_display="${cur_bw} GB"
        
        # Show bandwidth usage
        local bw_used_display="N/A"
        if [[ -f "$BANDWIDTH_DIR/${username}.usage" ]]; then
            local used_bytes; used_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null)
            if [[ -n "$used_bytes" && "$used_bytes" != "0" ]]; then
                bw_used_display=$(awk "BEGIN {printf \"%.2f GB\", $used_bytes / 1073741824}")
            else
                bw_used_display="0.00 GB"
            fi
        fi
        
        echo -e "\n  ${C_DIM}Current: Pass=${C_YELLOW}$cur_pass${C_RESET}${C_DIM} Exp=${C_YELLOW}$cur_expiry${C_RESET}${C_DIM} Conn=${C_YELLOW}$cur_limit${C_RESET}${C_DIM} BW=${C_YELLOW}$cur_bw_display${C_RESET}${C_DIM} Used=${C_CYAN}$bw_used_display${C_RESET}"
        echo -e "\nSelect a detail to edit:\n"
        printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "🔑 Change Password"
        printf "  ${C_GREEN}[ 2]${C_RESET} %-35s\n" "🗓️ Change Expiration Date"
        printf "  ${C_GREEN}[ 3]${C_RESET} %-35s\n" "📶 Change Connection Limit"
        printf "  ${C_GREEN}[ 4]${C_RESET} %-35s\n" "📦 Change Bandwidth Limit"
        printf "  ${C_GREEN}[ 5]${C_RESET} %-35s\n" "🔄 Reset Bandwidth Counter"
        echo -e "\n  ${C_RED}[ 0]${C_RESET} ✅ Finish Editing"
        echo
        if ! read -r -p "👉 Enter your choice: " edit_choice; then
            echo
            return
        fi
        case $edit_choice in
            1)
               local new_pass=""
               read -p "Enter new password (or press Enter for auto-generated): " new_pass
               if [[ -z "$new_pass" ]]; then
                   new_pass=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
                   echo -e "${C_GREEN}🔑 Auto-generated: ${C_YELLOW}$new_pass${C_RESET}"
               fi
               echo "$username:$new_pass" | chpasswd
               sed -i "s/^$username:.*/$username:$new_pass:$cur_expiry:$cur_limit:$cur_bw/" "$DB_FILE"
               echo -e "\n${C_GREEN}✅ Password for '$username' changed to: ${C_YELLOW}$new_pass${C_RESET}"
               ;;
            2) read -p "Enter new duration (in days from today): " days
               if [[ "$days" =~ ^[0-9]+$ ]]; then
                   local new_expire_date; new_expire_date=$(date -d "+$days days" +%Y-%m-%d); chage -E "$new_expire_date" "$username"
                   sed -i "s/^$username:.*/$username:$cur_pass:$new_expire_date:$cur_limit:$cur_bw/" "$DB_FILE"
                   echo -e "\n${C_GREEN}✅ Expiration for '$username' set to ${C_YELLOW}$new_expire_date${C_RESET}."
               else echo -e "\n${C_RED}❌ Invalid number of days.${C_RESET}"; fi ;;
            3) read -p "Enter new simultaneous connection limit: " new_limit
               if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
                   sed -i "s/^$username:.*/$username:$cur_pass:$cur_expiry:$new_limit:$cur_bw/" "$DB_FILE"
                   echo -e "\n${C_GREEN}✅ Connection limit for '$username' set to ${C_YELLOW}$new_limit${C_RESET}."
               else echo -e "\n${C_RED}❌ Invalid limit.${C_RESET}"; fi ;;
            4) read -p "Enter new bandwidth limit in GB (0 = unlimited): " new_bw
               if [[ "$new_bw" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                   sed -i "s/^$username:.*/$username:$cur_pass:$cur_expiry:$cur_limit:$new_bw/" "$DB_FILE"
                   local bw_msg="Unlimited"; [[ "$new_bw" != "0" ]] && bw_msg="${new_bw} GB"
                   echo -e "\n${C_GREEN}✅ Bandwidth limit for '$username' set to ${C_YELLOW}$bw_msg${C_RESET}."
                   # Unlock user if they were locked due to bandwidth
                   if [[ "$new_bw" == "0" ]] || [[ -f "$BANDWIDTH_DIR/${username}.usage" ]]; then
                       local used_bytes; used_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || echo 0)
                       local new_quota_bytes; new_quota_bytes=$(awk "BEGIN {printf \"%.0f\", $new_bw * 1073741824}")
                       if [[ "$new_bw" == "0" ]] || [[ "$used_bytes" -lt "$new_quota_bytes" ]]; then
                           usermod -U "$username" &>/dev/null
                       fi
                   fi
               else echo -e "\n${C_RED}❌ Invalid bandwidth value.${C_RESET}"; fi ;;
            5)
               echo "0" > "$BANDWIDTH_DIR/${username}.usage"
               # Unlock user if they were locked due to bandwidth
               usermod -U "$username" &>/dev/null
               echo -e "\n${C_GREEN}✅ Bandwidth counter for '$username' has been reset to 0.${C_RESET}"
               ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" ;;
        esac
        echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to continue editing..." && read -r || return
    done
}

lock_user() {
    _select_multi_user_interface "--- 🔒 Lock Users (from DB) ---"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_BLUE}🔒 Locking selected users...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        if ! id "$u" &>/dev/null; then
             echo -e " ❌ User '${C_YELLOW}$u${C_RESET}' does not exist on this system."
             continue
        fi
        
        usermod -L "$u"
        if [ $? -eq 0 ]; then
            killall -u "$u" -9 &>/dev/null
            echo -e " ✅ ${C_YELLOW}$u${C_RESET} locked and active sessions killed."
        else
            echo -e " ❌ Failed to lock ${C_YELLOW}$u${C_RESET}."
        fi
    done
}

unlock_user() {
    _select_multi_user_interface "--- 🔓 Unlock Users (from DB) ---"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_BLUE}🔓 Unlocking selected users...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        if ! id "$u" &>/dev/null; then
             echo -e " ❌ User '${C_YELLOW}$u${C_RESET}' does not exist on this system."
             continue
        fi
        
        usermod -U "$u"
        if [ $? -eq 0 ]; then
            echo -e " ✅ ${C_YELLOW}$u${C_RESET} unlocked."
        else
            echo -e " ❌ Failed to unlock ${C_YELLOW}$u${C_RESET}."
        fi
    done
}

list_users() {
    clear; show_banner
    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_YELLOW}ℹ️ Brak zarządzanych użytkowników.${C_RESET}"
        return
    fi

    local current_ts
    current_ts=$(date +%s)
    local -A system_user_lookup=()
    local -A locked_user_lookup=()

    while IFS=: read -r system_user _rest; do
        [[ -n "$system_user" ]] && system_user_lookup["$system_user"]=1
    done < /etc/passwd

    while read -r passwd_user _ passwd_status _rest; do
        [[ -z "$passwd_user" ]] && continue
        [[ "$passwd_status" == "L" ]] && locked_user_lookup["$passwd_user"]=1
    done < <(passwd -Sa 2>/dev/null)
    refresh_ssh_session_cache

    # Collect rows: sort_key|user|expiry|sessions|plain_status|status_label
    local -a rows=()
    while IFS=: read -r user pass expiry limit _rest; do
        local online_count="${SSH_SESSION_COUNTS[$user]:-0}"
        local plain_status="Active"
        local status_label="🟢 Aktywny"

        if [[ -z "${system_user_lookup[$user]+x}" ]]; then
            plain_status="Not Found"; status_label="❌ Brak"
        elif [[ -n "$expiry" && "$expiry" != "Never" ]]; then
            local expiry_ts
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ "$expiry_ts" =~ ^[0-9]+$ ]] && (( expiry_ts > 0 && expiry_ts < current_ts )); then
                plain_status="Expired"; status_label="🗓️ Wygasł"
            fi
        fi

        # Check for active session ban (temp lock by limiter)
        if [[ "$plain_status" == "Active" || "$plain_status" == "Locked" ]]; then
            if [[ -f "/run/ff_sessionban_${user}" ]]; then
                plain_status="Banned"; status_label="🚫 BAN (sesje)"
            elif [[ -n "${locked_user_lookup[$user]+x}" ]]; then
                plain_status="Locked"; status_label="🔒 Zablok."
            fi
        fi

        rows+=("$(printf '%010d' "$online_count")|$user|$expiry|$online_count/$limit|$plain_status|$status_label")
    done < "$DB_FILE"

    local total="${#rows[@]}"
    local div="${C_BLUE}  ──────────────────────────────────────────────────${C_RESET}"

    echo -e "  ${C_BOLD}${C_WHITE}📋 LISTA UŻYTKOWNIKÓW${C_RESET}  ${C_DIM}(wg aktywnych sesji)${C_RESET}"
    echo -e "$div"
    printf "  ${C_BOLD}${C_WHITE}%-16s  %-12s  %-8s  %s${C_RESET}\n" "UŻYTKOWNIK" "WYGASA" "SESJE" "STATUS"
    echo -e "$div"

    while IFS='|' read -r _key user expiry sessions plain_status status_label; do
        local uc="$C_WHITE" sc="$C_GREEN"
        case "$plain_status" in
            Banned)    uc="$C_RED";    sc="$C_RED" ;;
            Locked)    uc="$C_YELLOW"; sc="$C_YELLOW" ;;
            Expired)   uc="$C_RED";    sc="$C_RED" ;;
            Not\ Found) uc="$C_DIM";  sc="$C_DIM" ;;
        esac
        printf "  ${uc}%-16s${C_RESET}  ${C_YELLOW}%-12s${C_RESET}  ${C_CYAN}%-8s${C_RESET}  ${sc}%s${C_RESET}\n" \
            "$user" "$expiry" "$sessions" "$status_label"
    done < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1rn)

    echo -e "$div"
    echo -e "  ${C_DIM}Razem: ${total} użytkowników  •  Sesje online: ${SSH_SESSION_TOTAL}${C_RESET}"
    echo -e "  ${C_DIM}${C_RED}BAN${C_RESET}${C_DIM}=tymczasowy ban za sesje (mija po ~120s)  ${C_YELLOW}Zablok.${C_RESET}${C_DIM}=ręczna blokada${C_RESET}\n"
}

renew_user() {
    _select_multi_user_interface "--- 🔄 Renew Users ---"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    read -p "👉 Enter number of days to extend the account(s): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi

    local today; today=$(date +%Y-%m-%d)

    echo -e "\n${C_BLUE}🔄 Renewing selected users for $days days...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        local line; line=$(grep "^$u:" "$DB_FILE")
        local pass; pass=$(echo "$line" | cut -d: -f2)
        local cur_expire; cur_expire=$(echo "$line" | cut -d: -f3)
        local limit; limit=$(echo "$line" | cut -d: -f4)
        local bw; bw=$(echo "$line" | cut -d: -f5)
        [[ -z "$bw" ]] && bw="0"

        # Jeśli konto ważne (data wygaśnięcia >= dzisiaj) → dodaj do istniejącej daty
        # W przeciwnym razie → dodaj od dzisiaj
        local base_date
        if [[ -n "$cur_expire" ]] && [[ "$cur_expire" > "$today" || "$cur_expire" == "$today" ]]; then
            base_date="$cur_expire"
        else
            base_date="$today"
        fi

        local new_expire_date
        new_expire_date=$(date -d "$base_date +$days days" +%Y-%m-%d)

        chage -E "$new_expire_date" "$u"
        sed -i "s/^$u:.*/$u:$pass:$new_expire_date:$limit:$bw/" "$DB_FILE"
        echo -e " ✅ ${C_YELLOW}$u${C_RESET} renewed until ${C_GREEN}${new_expire_date}${C_RESET} (+${days}d from ${base_date})."
    done
}

cleanup_expired() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🧹 Cleanup Expired Users ---${C_RESET}"
    
    local expired_users=()
    local current_ts
    current_ts=$(date +%s)

    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_GREEN}✅ User database is empty. No expired users found.${C_RESET}"
        return
    fi
    
    while IFS=: read -r user pass expiry limit bandwidth_gb _extra; do
        local expiry_ts
        expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
        
        if [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
            expired_users+=("$user")
        fi
    done < "$DB_FILE"

    if [ ${#expired_users[@]} -eq 0 ]; then
        echo -e "\n${C_GREEN}✅ No expired users found.${C_RESET}"
        return
    fi

    echo -e "\nThe following users have expired: ${C_RED}${expired_users[*]}${C_RESET}"
    read -p "👉 Do you want to delete all of them? (y/n): " confirm

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        for user in "${expired_users[@]}"; do
            echo " - Deleting ${C_YELLOW}$user...${C_RESET}"
            killall -u "$user" -9 &>/dev/null
            # Clean up bandwidth tracking
            rm -f "$BANDWIDTH_DIR/${user}.usage"
            rm -rf "$BANDWIDTH_DIR/pidtrack/${user}"
            userdel -r "$user" &>/dev/null
            sed -i "/^$user:/d" "$DB_FILE"
        done
        echo -e "\n${C_GREEN}✅ Expired users have been cleaned up.${C_RESET}"
        invalidate_banner_cache
        refresh_dynamic_banner_routing_if_enabled
    else
        echo -e "\n${C_YELLOW}❌ Cleanup cancelled.${C_RESET}"
    fi
}


backup_user_data() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 💾 Backup User Data ---${C_RESET}"
    read -p "👉 Enter path for backup file [/root/firewallfalcon_users.tar.gz]: " backup_path
    backup_path=${backup_path:-/root/firewallfalcon_users.tar.gz}
    if [ ! -d "$DB_DIR" ] || [ ! -s "$DB_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ No user data found to back up.${C_RESET}"
        return
    fi
    echo -e "\n${C_BLUE}⚙️ Backing up user database and settings to ${C_YELLOW}$backup_path${C_RESET}..."
    tar -czf "$backup_path" -C "$(dirname "$DB_DIR")" "$(basename "$DB_DIR")"
    if [ $? -eq 0 ]; then
        echo -e "\n${C_GREEN}✅ SUCCESS: User data backup created at ${C_YELLOW}$backup_path${C_RESET}"
    else
        echo -e "\n${C_RED}❌ ERROR: Backup failed.${C_RESET}"
    fi
}

restore_user_data() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📥 Restore User Data ---${C_RESET}"
    read -p "👉 Enter the full path to the user data backup file [/root/firewallfalcon_users.tar.gz]: " backup_path
    backup_path=${backup_path:-/root/firewallfalcon_users.tar.gz}
    if [ ! -f "$backup_path" ]; then
        echo -e "\n${C_RED}❌ ERROR: Backup file not found at '$backup_path'.${C_RESET}"
        return
    fi
    echo -e "\n${C_RED}${C_BOLD}⚠️ WARNING:${C_RESET} This will overwrite all current users and settings."
    echo -e "It will restore user accounts, passwords, limits, and expiration dates from the backup file."
    read -p "👉 Are you absolutely sure you want to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo -e "\n${C_YELLOW}❌ Restore cancelled.${C_RESET}"; return; fi
    local temp_dir
    temp_dir=$(mktemp -d)
    echo -e "\n${C_BLUE}⚙️ Extracting backup file to a temporary location...${C_RESET}"
    tar -xzf "$backup_path" -C "$temp_dir"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ ERROR: Failed to extract backup file. Aborting.${C_RESET}"
        rm -rf "$temp_dir"
        return
    fi
    local restored_db_file="$temp_dir/firewallfalcon/users.db"
    if [ ! -f "$restored_db_file" ]; then
        echo -e "\n${C_RED}❌ ERROR: users.db not found in the backup. Cannot restore user accounts.${C_RESET}"
        rm -rf "$temp_dir"
        return
    fi
    echo -e "${C_BLUE}⚙️ Overwriting current user database...${C_RESET}"
    mkdir -p "$DB_DIR"
    cp "$restored_db_file" "$DB_FILE"
    if [ -d "$temp_dir/firewallfalcon/ssl" ]; then
        cp -r "$temp_dir/firewallfalcon/ssl" "$DB_DIR/"
    fi
    if [ -d "$temp_dir/firewallfalcon/dnstt" ]; then
        cp -r "$temp_dir/firewallfalcon/dnstt" "$DB_DIR/"
    fi
    if [ -f "$temp_dir/firewallfalcon/dns_info.conf" ]; then
        cp "$temp_dir/firewallfalcon/dns_info.conf" "$DB_DIR/"
    fi
    if [ -f "$temp_dir/firewallfalcon/dnstt_info.conf" ]; then
        cp "$temp_dir/firewallfalcon/dnstt_info.conf" "$DB_DIR/"
    fi
    if [ -f "$temp_dir/firewallfalcon/falconproxy_config.conf" ]; then
        cp "$temp_dir/firewallfalcon/falconproxy_config.conf" "$DB_DIR/"
    fi
    
    echo -e "${C_BLUE}⚙️ Re-synchronizing system accounts with the restored database...${C_RESET}"
    ensure_firewallfalcon_system_group
    
    while IFS=: read -r user pass expiry limit; do
        echo "Processing user: ${C_YELLOW}$user${C_RESET}"
        if ! id "$user" &>/dev/null; then
            echo " - User does not exist in system. Creating..."
            useradd -m -s /usr/sbin/nologin "$user"
        fi
        usermod -aG "$FF_USERS_GROUP" "$user" 2>/dev/null
        echo " - Setting password..."
        echo "$user:$pass" | chpasswd
        echo " - Setting expiration to $expiry..."
        chage -E "$expiry" "$user"
        echo " - Connection limit is $limit (enforced by PAM)"
    done < "$DB_FILE"
    rm -rf "$temp_dir"
    echo -e "\n${C_GREEN}✅ SUCCESS: User data restore completed.${C_RESET}"
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

_enable_banner_in_sshd_config() {
    echo -e "\n${C_BLUE}⚙️ Configuring sshd_config...${C_RESET}"
    disable_dynamic_ssh_banner_system
    sed -i.bak -E 's/^( *Banner *).*/#\1/' /etc/ssh/sshd_config
    if ! grep -q -E "^Banner $SSH_BANNER_FILE" /etc/ssh/sshd_config; then
        echo -e "\n# FirewallFalcon SSH Banner\nBanner $SSH_BANNER_FILE" >> /etc/ssh/sshd_config
    fi
    echo -e "${C_GREEN}✅ sshd_config updated.${C_RESET}"
}

_restart_ssh() {
    echo -e "\n${C_BLUE}🔄 Restarting SSH service to apply changes...${C_RESET}"
    local ssh_service_name=""
    if [ -f /lib/systemd/system/sshd.service ]; then
        ssh_service_name="sshd.service"
    elif [ -f /lib/systemd/system/ssh.service ]; then
        ssh_service_name="ssh.service"
    else
        echo -e "${C_RED}❌ Could not find sshd.service or ssh.service. Cannot restart SSH.${C_RESET}"
        return 1
    fi

    systemctl restart "${ssh_service_name}"
    if [ $? -eq 0 ]; then
        echo -e "${C_GREEN}✅ SSH service ('${ssh_service_name}') restarted successfully.${C_RESET}"
    else
        echo -e "${C_RED}❌ Failed to restart SSH service ('${ssh_service_name}'). Please check 'journalctl -u ${ssh_service_name}' for errors.${C_RESET}"
    fi
}

set_ssh_banner_paste() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📋 Paste Static SSH Banner ---${C_RESET}"
    echo -e "Paste your custom banner below. Press ${C_YELLOW}[Ctrl+D]${C_RESET} when you are finished."
    echo -e "${C_DIM}This will be shown to all SSH users through 'Banner $SSH_BANNER_FILE'.${C_RESET}"
    echo -e "${C_DIM}The current banner (if any) will be overwritten.${C_RESET}"
    echo -e "--------------------------------------------------"
    cat > "$SSH_BANNER_FILE"
    chmod 644 "$SSH_BANNER_FILE"
    echo -e "\n--------------------------------------------------"
    echo -e "\n${C_GREEN}✅ Static banner content saved.${C_RESET}"
    _enable_banner_in_sshd_config
    _restart_ssh
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

view_ssh_banner() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 👁️ Current SSH Banner ---${C_RESET}"
    if [ -f "$SSH_BANNER_FILE" ]; then
        echo -e "\n${C_CYAN}--- BEGIN BANNER ---${C_RESET}"
        cat "$SSH_BANNER_FILE"
        echo -e "${C_CYAN}---- END BANNER ----${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ No banner file found at $SSH_BANNER_FILE.${C_RESET}"
    fi
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

remove_ssh_banner() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Disable SSH Banners ---${C_RESET}"
    read -p "👉 Are you sure you want to disable all SSH banners? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "\n${C_YELLOW}❌ Action cancelled.${C_RESET}"
        echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
        return
    fi
    if [ -f "$SSH_BANNER_FILE" ]; then
        rm -f "$SSH_BANNER_FILE"
        echo -e "\n${C_GREEN}✅ Removed banner file: $SSH_BANNER_FILE${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ No banner file to remove.${C_RESET}"
    fi
    disable_dynamic_ssh_banner_system
    echo -e "\n${C_BLUE}⚙️ Disabling banner in sshd_config...${C_RESET}"
    disable_static_ssh_banner_in_sshd_config
    echo -e "${C_GREEN}✅ Banner disabled in configuration.${C_RESET}"
    _restart_ssh
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

preview_dynamic_ssh_banner() {
    if ! is_dynamic_ssh_banner_enabled; then
        echo -e "\n${C_RED}❌ Dynamic banners are not enabled right now.${C_RESET}"
        press_enter
        return
    fi

    echo -e "${C_DIM}Refreshing dynamic banner worker...${C_RESET}"
    setup_limiter_service >/dev/null 2>&1
    _select_user_interface "--- 📝 Preview Dynamic Banner ---"
    local u=$SELECTED_USER
    if [[ -z "$u" || "$u" == "NO_USERS" ]]; then
        return
    fi

    echo -e "\n${C_CYAN}--- Dynamic Banner Preview for user '$u' ---${C_RESET}\n"
    if [[ -f "/etc/firewallfalcon/banners/${u}.txt" ]]; then
        cat "/etc/firewallfalcon/banners/${u}.txt"
    else
        echo -e "${C_RED}Banner file not generated yet. Waiting up to 10s for the worker...${C_RESET}"
        sleep 5
        if ! cat "/etc/firewallfalcon/banners/${u}.txt" 2>/dev/null; then
            echo -e "\n${C_RED}Still not generated. Here are the last limiter logs:${C_RESET}"
            echo -e "----------------------------------------------------------------------"
            journalctl -u firewallfalcon-limiter -n 15 --no-pager
            echo -e "----------------------------------------------------------------------"
        fi
    fi
    press_enter
}

ssh_banner_menu() {
    while true; do
        show_banner
        local banner_status
        if grep -q -E "^\s*Banner\s+$SSH_BANNER_FILE" /etc/ssh/sshd_config && [ -f "$SSH_BANNER_FILE" ]; then
            banner_status="${C_STATUS_A}(Active)${C_RESET}"
        else
            banner_status="${C_STATUS_I}(Inactive)${C_RESET}"
        fi
        
        echo -e "\n   ${C_TITLE}═════════════════[ ${C_BOLD}🎨 SSH Banner Management ${banner_status} ${C_RESET}${C_TITLE}]═════════════════${C_RESET}"
        printf "     ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "📋 Paste or Edit Banner"
        printf "     ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "👁️ View Current Banner"
        printf "     ${C_DANGER}[ 3]${C_RESET} %-40s\n" "🗑️ Disable and Remove Banner"
        echo -e "   ${C_DIM}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${C_RESET}"
        echo -e "     ${C_WARN}[ 0]${C_RESET} ↩️ Return to Main Menu"
        echo
        read -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice
        case $choice in
            1) set_ssh_banner_paste ;;
            2) view_ssh_banner ;;
            3) remove_ssh_banner ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" && sleep 2 ;;
        esac
    done
}

install_udp_custom() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing udp-custom ---${C_RESET}"
    if [ -f "$UDP_CUSTOM_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ udp-custom is already installed.${C_RESET}"
        return
    fi

    echo -e "\n${C_GREEN}⚙️ Creating directory for udp-custom...${C_RESET}"
    rm -rf "$UDP_CUSTOM_DIR"
    mkdir -p "$UDP_CUSTOM_DIR"

    echo -e "\n${C_GREEN}⚙️ Detecting system architecture...${C_RESET}"
    local arch
    arch=$(uname -m)
    local binary_url=""
    if [[ "$arch" == "x86_64" ]]; then
        binary_url="https://github.com/firewallfalcons/FirewallFalcon-Manager/raw/main/udp/udp-custom-linux-amd64"
        echo -e "${C_BLUE}ℹ️ Detected x86_64 (amd64) architecture.${C_RESET}"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        binary_url="https://github.com/firewallfalcons/FirewallFalcon-Manager/raw/main/udp/udp-custom-linux-arm"
        echo -e "${C_BLUE}ℹ️ Detected ARM64 architecture.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Unsupported architecture: $arch. Cannot install udp-custom.${C_RESET}"
        rm -rf "$UDP_CUSTOM_DIR"
        return
    fi

    echo -e "\n${C_GREEN}📥 Downloading udp-custom binary...${C_RESET}"
    wget -q --show-progress -O "$UDP_CUSTOM_DIR/udp-custom" "$binary_url"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Failed to download the udp-custom binary.${C_RESET}"
        rm -rf "$UDP_CUSTOM_DIR"
        return
    fi
    chmod +x "$UDP_CUSTOM_DIR/udp-custom"

    echo -e "\n${C_GREEN}📝 Creating default config.json...${C_RESET}"
    cat > "$UDP_CUSTOM_DIR/config.json" <<EOF
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF
    chmod 644 "$UDP_CUSTOM_DIR/config.json"

    echo -e "\n${C_GREEN}📝 Creating systemd service file...${C_RESET}"
    cat > "$UDP_CUSTOM_SERVICE_FILE" <<EOF
[Unit]
Description=UDP Custom by FirewallFalcon
After=network.target

[Service]
User=root
Type=simple
ExecStart=$UDP_CUSTOM_DIR/udp-custom server -exclude 53,5300
WorkingDirectory=$UDP_CUSTOM_DIR/
Restart=always
RestartSec=2s

[Install]
WantedBy=default.target
EOF

    echo -e "\n${C_GREEN}▶️ Enabling and starting udp-custom service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable udp-custom.service
    systemctl start udp-custom.service
    sleep 2
    if systemctl is-active --quiet udp-custom; then
        echo -e "\n${C_GREEN}✅ SUCCESS: udp-custom is installed and active.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ ERROR: udp-custom service failed to start.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Displaying last 15 lines of the service log for diagnostics:${C_RESET}"
        journalctl -u udp-custom.service -n 15 --no-pager
    fi
}

uninstall_udp_custom() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling udp-custom ---${C_RESET}"
    if [ ! -f "$UDP_CUSTOM_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ udp-custom is not installed, skipping.${C_RESET}"
        return
    fi
    echo -e "${C_GREEN}🛑 Stopping and disabling udp-custom service...${C_RESET}"
    systemctl stop udp-custom.service >/dev/null 2>&1
    systemctl disable udp-custom.service >/dev/null 2>&1
    echo -e "${C_GREEN}🗑️ Removing systemd service file...${C_RESET}"
    rm -f "$UDP_CUSTOM_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${C_GREEN}🗑️ Removing udp-custom directory and files...${C_RESET}"
    rm -rf "$UDP_CUSTOM_DIR"
    echo -e "${C_GREEN}✅ udp-custom has been uninstalled successfully.${C_RESET}"
}


ensure_badvpn_service_is_quiet() {
    if [[ ! -f "$BADVPN_SERVICE_FILE" ]] || grep -q "^StandardOutput=null$" "$BADVPN_SERVICE_FILE" 2>/dev/null; then
        return
    fi

    local tmp_service
    tmp_service=$(mktemp)
    awk '
        /^\[Service\]$/ {
            print
            print "StandardOutput=null"
            print "StandardError=null"
            next
        }
        { print }
    ' "$BADVPN_SERVICE_FILE" > "$tmp_service" && mv "$tmp_service" "$BADVPN_SERVICE_FILE"
    rm -f "$tmp_service" 2>/dev/null
    systemctl daemon-reload
    systemctl restart badvpn.service >/dev/null 2>&1 || true
}

install_badvpn() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing badvpn (udpgw) ---${C_RESET}"
    if [ -f "$BADVPN_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ badvpn is already installed.${C_RESET}"
        return
    fi
    check_and_open_firewall_port 7300 udp || return
    echo -e "\n${C_GREEN}🔄 Updating package lists...${C_RESET}"
    apt-get update
    echo -e "\n${C_GREEN}📦 Installing all required packages...${C_RESET}"
    apt-get install -y cmake g++ make screen git build-essential libssl-dev libnspr4-dev libnss3-dev pkg-config
    echo -e "\n${C_GREEN}📥 Cloning badvpn from github...${C_RESET}"
    git clone https://github.com/ambrop72/badvpn.git "$BADVPN_BUILD_DIR"
    cd "$BADVPN_BUILD_DIR" || { echo -e "${C_RED}❌ Failed to change directory to build folder.${C_RESET}"; return; }
    echo -e "\n${C_GREEN}⚙️ Running CMake...${C_RESET}"
    cmake . || { echo -e "${C_RED}❌ CMake configuration failed.${C_RESET}"; rm -rf "$BADVPN_BUILD_DIR"; return; }
    echo -e "\n${C_GREEN}🛠️ Compiling source...${C_RESET}"
    make || { echo -e "${C_RED}❌ Compilation (make) failed.${C_RESET}"; rm -rf "$BADVPN_BUILD_DIR"; return; }
    local badvpn_binary
    badvpn_binary=$(find "$BADVPN_BUILD_DIR" -name "badvpn-udpgw" -type f | head -n 1)
    if [[ -z "$badvpn_binary" || ! -f "$badvpn_binary" ]]; then
        echo -e "${C_RED}❌ ERROR: Could not find the compiled 'badvpn-udpgw' binary after compilation.${C_RESET}"
        rm -rf "$BADVPN_BUILD_DIR"
        return
    fi
    echo -e "${C_GREEN}ℹ️ Found binary at: $badvpn_binary${C_RESET}"
    chmod +x "$badvpn_binary"
    echo -e "\n${C_GREEN}📝 Creating systemd service file...${C_RESET}"
    cat > "$BADVPN_SERVICE_FILE" <<-EOF
[Unit]
Description=BadVPN UDP Gateway
After=network.target
[Service]
ExecStart=$badvpn_binary --listen-addr 0.0.0.0:7300 --max-clients 1000 --max-connections-for-client 8
User=root
Restart=always
RestartSec=3
StandardOutput=null
StandardError=null
[Install]
WantedBy=multi-user.target
EOF
    echo -e "\n${C_GREEN}▶️ Enabling and starting badvpn service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable badvpn.service
    systemctl start badvpn.service
    sleep 2
    if systemctl is-active --quiet badvpn; then
        echo -e "\n${C_GREEN}✅ SUCCESS: badvpn (udpgw) is installed and active on port 7300.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ ERROR: badvpn service failed to start.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Displaying last 15 lines of the service log for diagnostics:${C_RESET}"
        journalctl -u badvpn.service -n 15 --no-pager
    fi
}

uninstall_badvpn() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling badvpn (udpgw) ---${C_RESET}"
    if [ ! -f "$BADVPN_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ badvpn is not installed, skipping.${C_RESET}"
        return
    fi
    echo -e "${C_GREEN}🛑 Stopping and disabling badvpn service...${C_RESET}"
    systemctl stop badvpn.service >/dev/null 2>&1
    systemctl disable badvpn.service >/dev/null 2>&1
    echo -e "${C_GREEN}🗑️ Removing systemd service file...${C_RESET}"
    rm -f "$BADVPN_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${C_GREEN}🗑️ Removing badvpn build directory...${C_RESET}"
    rm -rf "$BADVPN_BUILD_DIR"
    echo -e "${C_GREEN}✅ badvpn has been uninstalled successfully.${C_RESET}"
}

load_edge_cert_info() {
    EDGE_CERT_MODE=""
    EDGE_DOMAIN=""
    EDGE_EMAIL=""
    if [ -f "$EDGE_CERT_INFO_FILE" ]; then
        source "$EDGE_CERT_INFO_FILE"
    fi
}

save_edge_cert_info() {
    local cert_mode="$1"
    local cert_domain="$2"
    local cert_email="$3"
    mkdir -p "$DB_DIR"
    cat > "$EDGE_CERT_INFO_FILE" <<EOF
EDGE_CERT_MODE="$cert_mode"
EDGE_DOMAIN="$cert_domain"
EDGE_EMAIL="$cert_email"
EOF
}

detect_preferred_host() {
    local host_domain=""
    load_edge_cert_info
    if [[ -n "$EDGE_DOMAIN" ]]; then
        host_domain="$EDGE_DOMAIN"
    fi
    if [[ -z "$host_domain" && -f "$DNS_INFO_FILE" ]]; then
        host_domain=$(grep 'FULL_DOMAIN' "$DNS_INFO_FILE" | cut -d'"' -f2)
    fi
    if [[ -z "$host_domain" && -f "$NGINX_CONFIG_FILE" ]]; then
        local nginx_domain
        nginx_domain=$(grep -oP 'server_name \K[^\s;]+' "$NGINX_CONFIG_FILE" 2>/dev/null | head -n 1)
        if [[ "$nginx_domain" != "_" && -n "$nginx_domain" ]]; then
            host_domain="$nginx_domain"
        fi
    fi
    if [[ -z "$host_domain" ]]; then
        host_domain=$(curl -s -4 icanhazip.com)
    fi
    echo "$host_domain"
}

backup_edge_configs() {
    if [ -f "$NGINX_CONFIG_FILE" ] && [ ! -f "${NGINX_CONFIG_FILE}.bak.firewallfalcon" ]; then
        cp "$NGINX_CONFIG_FILE" "${NGINX_CONFIG_FILE}.bak.firewallfalcon" 2>/dev/null
    fi
    if [ -f "$HAPROXY_CONFIG" ] && [ ! -f "${HAPROXY_CONFIG}.bak.firewallfalcon" ]; then
        cp "$HAPROXY_CONFIG" "${HAPROXY_CONFIG}.bak.firewallfalcon" 2>/dev/null
    fi
}

ensure_edge_stack_packages() {
    local missing_packages=()
    command -v haproxy &> /dev/null || missing_packages+=("haproxy")
    command -v nginx &> /dev/null || missing_packages+=("nginx")
    command -v openssl &> /dev/null || missing_packages+=("openssl")

    if (( ${#missing_packages[@]} > 0 )); then
        echo -e "\n${C_BLUE}📦 Installing required packages: ${missing_packages[*]}${C_RESET}"
        apt-get update && apt-get install -y "${missing_packages[@]}" || {
            echo -e "${C_RED}❌ Failed to install the required packages.${C_RESET}"
            return 1
        }
    fi
    return 0
}

build_shared_tls_bundle() {
    if [ ! -s "$SSL_CERT_CHAIN_FILE" ] || [ ! -s "$SSL_CERT_KEY_FILE" ]; then
        echo -e "${C_RED}❌ Certificate chain or key is missing.${C_RESET}"
        return 1
    fi
    cat "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" > "$SSL_CERT_FILE" || return 1
    chmod 644 "$SSL_CERT_CHAIN_FILE"
    chmod 600 "$SSL_CERT_KEY_FILE" "$SSL_CERT_FILE"
    return 0
}

generate_self_signed_edge_cert() {
    local common_name="$1"
    mkdir -p "$SSL_CERT_DIR"
    echo -e "\n${C_GREEN}🔐 Generating a shared self-signed certificate...${C_RESET}"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$SSL_CERT_KEY_FILE" \
        -out "$SSL_CERT_CHAIN_FILE" \
        -subj "/CN=$common_name" \
        >/dev/null 2>&1 || {
            echo -e "${C_RED}❌ Failed to generate the self-signed certificate.${C_RESET}"
            return 1
        }
    build_shared_tls_bundle || return 1
    save_edge_cert_info "self-signed" "$common_name" ""
    echo -e "${C_GREEN}✅ Shared certificate created for ${C_YELLOW}$common_name${C_RESET}"
    return 0
}

_install_certbot() {
    if command -v certbot &> /dev/null; then
        echo -e "${C_GREEN}✅ Certbot is already installed.${C_RESET}"
        return 0
    fi
    echo -e "${C_BLUE}📦 Installing Certbot...${C_RESET}"
    apt-get update > /dev/null 2>&1
    apt-get install -y certbot || {
        echo -e "${C_RED}❌ Failed to install Certbot.${C_RESET}"
        return 1
    }
    echo -e "${C_GREEN}✅ Certbot installed successfully.${C_RESET}"
    return 0
}

obtain_certbot_edge_cert() {
    local domain_name="$1"
    local email="$2"
    local restart_haproxy=0
    local restart_nginx=0

    mkdir -p "$SSL_CERT_DIR"
    _install_certbot || return 1

    if systemctl is-active --quiet haproxy; then restart_haproxy=1; fi
    if systemctl is-active --quiet nginx; then restart_nginx=1; fi

    echo -e "\n${C_BLUE}🛑 Stopping HAProxy and Nginx for Certbot validation...${C_RESET}"
    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 2

    check_and_free_ports "$EDGE_PUBLIC_HTTP_PORT" "$EDGE_PUBLIC_TLS_PORT" || {
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    }

    echo -e "\n${C_BLUE}🚀 Requesting a Certbot certificate for ${C_YELLOW}$domain_name${C_RESET}"
    certbot certonly --standalone -d "$domain_name" --non-interactive --agree-tos -m "$email"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Certbot failed to obtain a certificate.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Make sure the domain points to this server and port 80 is reachable.${C_RESET}"
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    fi

    local certbot_chain="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    local certbot_key="/etc/letsencrypt/live/$domain_name/privkey.pem"
    if [ ! -f "$certbot_chain" ] || [ ! -f "$certbot_key" ]; then
        echo -e "\n${C_RED}❌ Certbot completed, but the certificate files were not found.${C_RESET}"
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    fi

    cp "$certbot_chain" "$SSL_CERT_CHAIN_FILE"
    cp "$certbot_key" "$SSL_CERT_KEY_FILE"
    build_shared_tls_bundle || {
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    }
    save_edge_cert_info "certbot" "$domain_name" "$email"
    echo -e "${C_GREEN}✅ Certbot certificate copied into ${C_YELLOW}$SSL_CERT_DIR${C_RESET}"
    return 0
}

select_edge_certificate() {
    local preferred_host
    local cert_choice
    local has_existing_cert=false

    preferred_host=$(detect_preferred_host)
    if [[ -z "$preferred_host" ]]; then
        preferred_host="firewallfalcon.local"
    fi

    if [ -s "$SSL_CERT_FILE" ] && [ -s "$SSL_CERT_CHAIN_FILE" ] && [ -s "$SSL_CERT_KEY_FILE" ]; then
        has_existing_cert=true
    fi

    load_edge_cert_info

    echo -e "\n${C_BOLD}${C_PURPLE}--- 🔐 Shared TLS Certificate ---${C_RESET}"
    echo -e "${C_DIM}The same certificate will be used by HAProxy and the internal Nginx proxy.${C_RESET}"

    if $has_existing_cert; then
        local existing_label="${EDGE_CERT_MODE:-existing}"
        if [[ -n "$EDGE_DOMAIN" ]]; then
            existing_label="$existing_label - $EDGE_DOMAIN"
        fi
        printf "  ${C_CHOICE}[ 1]${C_RESET} %-52s\n" "Reuse existing certificate (${existing_label})"
        printf "  ${C_CHOICE}[ 2]${C_RESET} %-52s\n" "Replace with a new self-signed certificate"
        printf "  ${C_CHOICE}[ 3]${C_RESET} %-52s\n" "Replace with a Certbot certificate"
        echo
        read -p "👉 Enter choice [1]: " cert_choice
        cert_choice=${cert_choice:-1}
    else
        printf "  ${C_CHOICE}[ 1]${C_RESET} %-52s\n" "Generate a self-signed certificate"
        printf "  ${C_CHOICE}[ 2]${C_RESET} %-52s\n" "Use a Certbot certificate"
        echo
        read -p "👉 Enter choice [1]: " cert_choice
        cert_choice=${cert_choice:-1}
    fi

    case "$cert_choice" in
        1)
            if $has_existing_cert; then
                echo -e "${C_GREEN}✅ Reusing the existing shared certificate.${C_RESET}"
                return 0
            fi
            local common_name
            read -p "👉 Enter the certificate Common Name / SNI label [$preferred_host]: " common_name
            common_name=${common_name:-$preferred_host}
            generate_self_signed_edge_cert "$common_name"
            ;;
        2)
            if $has_existing_cert; then
                local common_name
                read -p "👉 Enter the certificate Common Name / SNI label [$preferred_host]: " common_name
                common_name=${common_name:-$preferred_host}
                generate_self_signed_edge_cert "$common_name"
            else
                local default_domain=""
                local domain_name
                local email
                if ! _is_valid_ipv4 "$preferred_host"; then
                    default_domain="$preferred_host"
                fi
                if [[ -n "$default_domain" ]]; then
                    read -p "👉 Enter your domain name [$default_domain]: " domain_name
                    domain_name=${domain_name:-$default_domain}
                else
                    read -p "👉 Enter your domain name (e.g. vpn.example.com): " domain_name
                fi
                if [[ -z "$domain_name" ]]; then
                    echo -e "${C_RED}❌ Domain name cannot be empty.${C_RESET}"
                    return 1
                fi
                if _is_valid_ipv4 "$domain_name"; then
                    echo -e "${C_RED}❌ Certbot requires a real domain name, not a raw IP address.${C_RESET}"
                    return 1
                fi
                read -p "👉 Enter your email for Let's Encrypt: " email
                if [[ -z "$email" ]]; then
                    echo -e "${C_RED}❌ Email cannot be empty.${C_RESET}"
                    return 1
                fi
                obtain_certbot_edge_cert "$domain_name" "$email"
            fi
            ;;
        3)
            if ! $has_existing_cert; then
                echo -e "${C_RED}❌ Invalid option.${C_RESET}"
                return 1
            fi
            local default_domain=""
            local domain_name
            local email
            if [[ -n "$EDGE_DOMAIN" ]] && ! _is_valid_ipv4 "$EDGE_DOMAIN"; then
                default_domain="$EDGE_DOMAIN"
            fi
            if [[ -z "$default_domain" ]] && ! _is_valid_ipv4 "$preferred_host"; then
                default_domain="$preferred_host"
            fi
            if [[ -n "$default_domain" ]]; then
                read -p "👉 Enter your domain name [$default_domain]: " domain_name
                domain_name=${domain_name:-$default_domain}
            else
                read -p "👉 Enter your domain name (e.g. vpn.example.com): " domain_name
            fi
            if [[ -z "$domain_name" ]]; then
                echo -e "${C_RED}❌ Domain name cannot be empty.${C_RESET}"
                return 1
            fi
            if _is_valid_ipv4 "$domain_name"; then
                echo -e "${C_RED}❌ Certbot requires a real domain name, not a raw IP address.${C_RESET}"
                return 1
            fi
            read -p "👉 Enter your email for Let's Encrypt [${EDGE_EMAIL}]: " email
            email=${email:-$EDGE_EMAIL}
            if [[ -z "$email" ]]; then
                echo -e "${C_RED}❌ Email cannot be empty.${C_RESET}"
                return 1
            fi
            obtain_certbot_edge_cert "$domain_name" "$email"
            ;;
        *)
            echo -e "${C_RED}❌ Invalid option.${C_RESET}"
            return 1
            ;;
    esac
}

write_internal_nginx_config() {
    local server_name="$1"
    [[ -z "$server_name" ]] && server_name="_"
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    cat > "$NGINX_CONFIG_FILE" <<EOF
server {
    listen 127.0.0.1:${NGINX_INTERNAL_HTTP_PORT} default_server;
    listen 127.0.0.1:${NGINX_INTERNAL_TLS_PORT} ssl http2 default_server;
    server_tokens off;
    server_name ${server_name};

    ssl_certificate ${SSL_CERT_CHAIN_FILE};
    ssl_certificate_key ${SSL_CERT_KEY_FILE};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
    resolver 1.1.1.1 8.8.8.8 ipv6=off valid=300s;

    location ~ ^/(?<fwdport>\d+)/(?<fwdpath>.*)$ {
        client_max_body_size 0;
        client_body_timeout 1d;
        grpc_read_timeout 1d;
        grpc_socket_keepalive on;
        proxy_read_timeout 1d;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        if (\$content_type ~* "GRPC") { grpc_pass grpc://127.0.0.1:\$fwdport\$is_args\$args; break; }
        proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
        break;
    }

    location / {
        proxy_read_timeout 3600s;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_socket_keepalive on;
        tcp_nodelay on;
        tcp_nopush off;
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    ln -sf "$NGINX_CONFIG_FILE" /etc/nginx/sites-enabled/default
}

write_haproxy_edge_config() {
    mkdir -p /etc/haproxy
    cat > "$HAPROXY_CONFIG" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  24h
    timeout server  24h

# ====================================================================
# TIER 1: PORT ${EDGE_PUBLIC_HTTP_PORT} (Cleartext Payloads & Raw SSH)
# ====================================================================
frontend port_80_edge
    bind *:${EDGE_PUBLIC_HTTP_PORT}
    mode tcp
    tcp-request inspect-delay 2s

    acl is_ssh payload(0,7) -m bin 5353482d322e30

    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP

    use_backend direct_ssh if is_ssh
    default_backend nginx_cleartext

# ====================================================================
# TIER 1: PORT ${EDGE_PUBLIC_TLS_PORT} (TLS v2ray, SSL Payloads, Raw SSH)
# ====================================================================
frontend port_443_edge
    bind *:${EDGE_PUBLIC_TLS_PORT}
    mode tcp
    tcp-request inspect-delay 2s

    acl is_ssh payload(0,7) -m bin 5353482d322e30
    acl is_tls req.ssl_hello_type 1
    acl has_web_alpn req.ssl_alpn -m sub h2 http/1.1

    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP
    tcp-request content accept if is_tls

    use_backend direct_ssh if is_ssh
    use_backend nginx_cleartext if HTTP
    use_backend nginx_tls if is_tls has_web_alpn
    default_backend loopback_ssl_terminator

# ====================================================================
# TIER 2: INTERNAL DECRYPTOR (Only for Any-SNI SSH-TLS)
# ====================================================================
frontend internal_decryptor
    bind 127.0.0.1:${HAPROXY_INTERNAL_DECRYPT_PORT} ssl crt ${SSL_CERT_FILE}
    mode tcp
    tcp-request inspect-delay 2s

    acl is_ssh payload(0,7) -m bin 5353482d322e30
    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP

    use_backend direct_ssh if is_ssh
    default_backend nginx_cleartext

# ====================================================================
# DESTINATION BACKENDS (Clean handoffs, no proxy headers)
# ====================================================================
backend direct_ssh
    mode tcp
    server ssh_server 127.0.0.1:22

backend nginx_cleartext
    mode tcp
    server nginx_8880 127.0.0.1:${NGINX_INTERNAL_HTTP_PORT}

backend nginx_tls
    mode tcp
    server nginx_8443 127.0.0.1:${NGINX_INTERNAL_TLS_PORT}

backend loopback_ssl_terminator
    mode tcp
    server haproxy_ssl 127.0.0.1:${HAPROXY_INTERNAL_DECRYPT_PORT}
EOF
}

save_edge_ports_info() {
    cat > "$NGINX_PORTS_FILE" <<EOF
EDGE_HTTP_PORT="${EDGE_PUBLIC_HTTP_PORT}"
EDGE_TLS_PORT="${EDGE_PUBLIC_TLS_PORT}"
HTTP_PORTS="${NGINX_INTERNAL_HTTP_PORT}"
TLS_PORTS="${NGINX_INTERNAL_TLS_PORT}"
EOF
}

configure_edge_stack() {
    local server_name="$1"
    [[ -z "$server_name" ]] && server_name="_"

    backup_edge_configs

    echo -e "\n${C_BLUE}📝 Writing internal Nginx config (127.0.0.1:${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT})...${C_RESET}"
    write_internal_nginx_config "$server_name"

    echo -e "${C_BLUE}📝 Writing HAProxy edge config (${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT})...${C_RESET}"
    write_haproxy_edge_config

    echo -e "\n${C_BLUE}🧪 Validating Nginx configuration...${C_RESET}"
    if ! nginx -t >/dev/null 2>&1; then
        echo -e "${C_RED}❌ Nginx configuration validation failed.${C_RESET}"
        nginx -t
        return 1
    fi

    echo -e "${C_BLUE}🧪 Validating HAProxy configuration...${C_RESET}"
    if ! haproxy -c -f "$HAPROXY_CONFIG" >/dev/null 2>&1; then
        echo -e "${C_RED}❌ HAProxy configuration validation failed.${C_RESET}"
        haproxy -c -f "$HAPROXY_CONFIG"
        return 1
    fi

    systemctl daemon-reload
    systemctl enable nginx >/dev/null 2>&1
    systemctl enable haproxy >/dev/null 2>&1

    echo -e "\n${C_BLUE}▶️ Restarting internal Nginx...${C_RESET}"
    systemctl restart nginx || {
        echo -e "${C_RED}❌ Nginx failed to restart.${C_RESET}"
        systemctl status nginx --no-pager
        return 1
    }

    echo -e "${C_BLUE}▶️ Restarting HAProxy edge...${C_RESET}"
    systemctl restart haproxy || {
        echo -e "${C_RED}❌ HAProxy failed to restart.${C_RESET}"
        systemctl status haproxy --no-pager
        return 1
    }

    sleep 2
    if ! systemctl is-active --quiet nginx; then
        echo -e "${C_RED}❌ Nginx is not active after restart.${C_RESET}"
        systemctl status nginx --no-pager
        return 1
    fi
    if ! systemctl is-active --quiet haproxy; then
        echo -e "${C_RED}❌ HAProxy is not active after restart.${C_RESET}"
        systemctl status haproxy --no-pager
        return 1
    fi

    save_edge_ports_info
    return 0
}

install_ssl_tunnel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing HAProxy Edge Stack (80/443 -> 8880/8443) ---${C_RESET}"
    echo -e "\n${C_CYAN}This installer will configure:${C_RESET}"
    echo -e "   • HAProxy on ${C_WHITE}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx on ${C_WHITE}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    echo -e "   • Loopback SSL decryptor on ${C_WHITE}${HAPROXY_INTERNAL_DECRYPT_PORT}${C_RESET}"

    if [ -f "$HAPROXY_CONFIG" ] || [ -f "$NGINX_CONFIG_FILE" ]; then
        echo -e "\n${C_YELLOW}⚠️ Existing HAProxy/Nginx configs will be replaced with the FirewallFalcon edge layout.${C_RESET}"
        read -p "👉 Continue with the replacement? (y/n): " confirm_replace
        if [[ "$confirm_replace" != "y" && "$confirm_replace" != "Y" ]]; then
            echo -e "${C_RED}❌ Installation cancelled.${C_RESET}"
            return
        fi
    fi

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"

    ensure_edge_stack_packages || return

    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 1

    check_and_free_ports \
        "$EDGE_PUBLIC_HTTP_PORT" \
        "$EDGE_PUBLIC_TLS_PORT" \
        "$NGINX_INTERNAL_HTTP_PORT" \
        "$NGINX_INTERNAL_TLS_PORT" \
        "$HAPROXY_INTERNAL_DECRYPT_PORT" || return

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    select_edge_certificate || return

    load_edge_cert_info
    local server_name="${EDGE_DOMAIN:-$(detect_preferred_host)}"
    [[ -z "$server_name" ]] && server_name="_"

    configure_edge_stack "$server_name" || return

    echo -e "\n${C_GREEN}✅ SUCCESS: HAProxy edge stack is active.${C_RESET}"
    echo -e "   • Public edge ports: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx ports: ${C_YELLOW}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    echo -e "   • Shared certificate: ${C_YELLOW}${EDGE_CERT_MODE:-unknown}${C_RESET}"
}

uninstall_ssl_tunnel() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling HAProxy Edge Stack ---${C_RESET}"
    if ! command -v haproxy &> /dev/null; then
        echo -e "${C_YELLOW}ℹ️ HAProxy is not installed, skipping service removal.${C_RESET}"
    else
        echo -e "${C_GREEN}🛑 Stopping and disabling HAProxy...${C_RESET}"
        systemctl stop haproxy >/dev/null 2>&1
        systemctl disable haproxy >/dev/null 2>&1
    fi

    if [ -f "$HAPROXY_CONFIG" ]; then
        cat > "$HAPROXY_CONFIG" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice

defaults
    log     global
EOF
    fi

    local delete_cert="n"
    if [[ "$UNINSTALL_MODE" == "silent" ]]; then
        delete_cert="y"
    elif [ -f "$SSL_CERT_FILE" ] || [ -f "$SSL_CERT_CHAIN_FILE" ] || [ -f "$SSL_CERT_KEY_FILE" ]; then
        if systemctl is-active --quiet nginx; then
            echo -e "${C_YELLOW}⚠️ The shared certificate is also used by the internal Nginx proxy.${C_RESET}"
        fi
        read -p "👉 Delete the shared TLS certificate too? (y/n): " delete_cert
    fi

    if [[ "$delete_cert" == "y" || "$delete_cert" == "Y" ]]; then
        if systemctl is-active --quiet nginx; then
            echo -e "${C_GREEN}🛑 Stopping Nginx because the shared certificate is being removed...${C_RESET}"
            systemctl stop nginx >/dev/null 2>&1
        fi
        rm -f "$SSL_CERT_FILE" "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" "$EDGE_CERT_INFO_FILE"
        rm -f "$NGINX_PORTS_FILE"
        echo -e "${C_GREEN}🗑️ Shared certificate files removed.${C_RESET}"
    fi

    echo -e "${C_GREEN}✅ HAProxy edge stack has been removed.${C_RESET}"
    if systemctl is-active --quiet nginx; then
        echo -e "${C_DIM}The internal Nginx proxy is still installed on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"
    fi
}

show_dnstt_details() {
    if [ -f "$DNSTT_CONFIG_FILE" ]; then
        source "$DNSTT_CONFIG_FILE"
        echo -e "\n${C_GREEN}=====================================================${C_RESET}"
        echo -e "${C_GREEN}            📡 DNSTT Connection Details             ${C_RESET}"
        echo -e "${C_GREEN}=====================================================${C_RESET}"
        echo -e "\n${C_WHITE}Your connection details:${C_RESET}"
        echo -e "  - ${C_CYAN}Tunnel Domain:${C_RESET} ${C_YELLOW}$TUNNEL_DOMAIN${C_RESET}"
        echo -e "  - ${C_CYAN}Public Key:${C_RESET}    ${C_YELLOW}$PUBLIC_KEY${C_RESET}"
        if [[ -n "$FORWARD_DESC" ]]; then
            echo -e "  - ${C_CYAN}Forwarding To:${C_RESET} ${C_YELLOW}$FORWARD_DESC${C_RESET}"
        else
            echo -e "  - ${C_CYAN}Forwarding To:${C_RESET} ${C_YELLOW}Unknown (config_missing)${C_RESET}"
        fi
        if [[ -n "$MTU_VALUE" ]]; then
            echo -e "  - ${C_CYAN}MTU Value:${C_RESET}     ${C_YELLOW}$MTU_VALUE${C_RESET}"
        fi
        if [[ "$DNSTT_RECORDS_MANAGED" == "false" && -n "$NS_DOMAIN" ]]; then
             echo -e "  - ${C_CYAN}NS Record:${C_RESET}     ${C_YELLOW}$NS_DOMAIN${C_RESET}"
        fi
        
        if [[ "$FORWARD_DESC" == *"V2Ray"* ]]; then
             echo -e "  - ${C_CYAN}Action Required:${C_RESET} ${C_YELLOW}Ensure a V2Ray service (vless/vmess/trojan) listens on port 8787 (no TLS)${C_RESET}"
        elif [[ "$FORWARD_DESC" == *"SSH"* ]]; then
             echo -e "  - ${C_CYAN}Action Required:${C_RESET} ${C_YELLOW}Ensure your SSH client is configured to use the DNS tunnel.${C_RESET}"
        fi
        
        echo -e "\n${C_DIM}Use these details in your client configuration.${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ DNSTT configuration file not found. Details are unavailable.${C_RESET}"
    fi
}

install_dnstt() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📡 DNSTT (DNS Tunnel) Management ---${C_RESET}"
    if [ -f "$DNSTT_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ DNSTT is already installed.${C_RESET}"
        show_dnstt_details
        return
    fi
    
    # --- FIX: Force release of Port 53 / Disable systemd-resolved ---
    echo -e "${C_GREEN}⚙️ Forcing release of Port 53 (stopping systemd-resolved)...${C_RESET}"
    systemctl stop systemd-resolved >/dev/null 2>&1
    systemctl disable systemd-resolved >/dev/null 2>&1
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" | tee /etc/resolv.conf > /dev/null
    # ----------------------------------------------------------------
    
    echo -e "\n${C_BLUE}🔎 Checking if port 53 (UDP) is available...${C_RESET}"
    if ss -lunp | grep -q ':53\s'; then
        if [[ $(ps -p $(ss -lunp | grep ':53\s' | grep -oP 'pid=\K[0-9]+') -o comm=) == "systemd-resolve" ]]; then
            echo -e "${C_YELLOW}⚠️ Warning: Port 53 is in use by 'systemd-resolved'.${C_RESET}"
            echo -e "${C_YELLOW}This is the system's DNS stub resolver. It must be disabled to run DNSTT.${C_RESET}"
            read -p "👉 Allow the script to automatically disable it and reconfigure DNS? (y/n): " resolve_confirm
            if [[ "$resolve_confirm" == "y" || "$resolve_confirm" == "Y" ]]; then
                echo -e "${C_GREEN}⚙️ Stopping and disabling systemd-resolved to free port 53...${C_RESET}"
                systemctl stop systemd-resolved
                systemctl disable systemd-resolved
                chattr -i /etc/resolv.conf &>/dev/null
                rm -f /etc/resolv.conf
                echo "nameserver 8.8.8.8" > /etc/resolv.conf
                chattr +i /etc/resolv.conf
                echo -e "${C_GREEN}✅ Port 53 has been freed and DNS set to 8.8.8.8.${C_RESET}"
            else
                echo -e "${C_RED}❌ Cannot proceed without freeing port 53. Aborting.${C_RESET}"
                return
            fi
        else
            check_and_free_ports "53" || return
        fi
    else
        echo -e "${C_GREEN}✅ Port 53 (UDP) is free to use.${C_RESET}"
    fi

    check_and_open_firewall_port 53 udp || return



    local forward_port=""
    local forward_desc=""
    echo -e "\n${C_BLUE}Please choose where DNSTT should forward traffic:${C_RESET}"
    echo -e "  ${C_GREEN}[ 1]${C_RESET} ➡️ Forward to local SSH service (port 22)"
    echo -e "  ${C_GREEN}[ 2]${C_RESET} ➡️ Forward to local V2Ray backend (port 8787)"
    read -p "👉 Enter your choice [2]: " fwd_choice
    fwd_choice=${fwd_choice:-2}
    if [[ "$fwd_choice" == "1" ]]; then
        forward_port="22"
        forward_desc="SSH (port 22)"
        echo -e "${C_GREEN}ℹ️ DNSTT will forward to SSH on 127.0.0.1:22.${C_RESET}"
        

        
    elif [[ "$fwd_choice" == "2" ]]; then
        forward_port="8787"
        forward_desc="V2Ray (port 8787)"
        echo -e "${C_GREEN}ℹ️ DNSTT will forward to V2Ray on 127.0.0.1:8787.${C_RESET}"
    else
        echo -e "${C_RED}❌ Invalid choice. Aborting.${C_RESET}"
        return
    fi
    local FORWARD_TARGET="127.0.0.1:$forward_port"
    
    local NS_DOMAIN=""
    local TUNNEL_DOMAIN=""
    local DNSTT_RECORDS_MANAGED="true"
    local NS_SUBDOMAIN=""
    local TUNNEL_SUBDOMAIN=""
    local HAS_IPV6="false"

    read -p "👉 Auto-generate DNS records or use custom ones? (auto/custom) [auto]: " dns_choice
    dns_choice=${dns_choice:-auto}

    if [[ "$dns_choice" == "custom" ]]; then
        DNSTT_RECORDS_MANAGED="false"
        read -p "👉 Enter your full nameserver domain (e.g., ns1.yourdomain.com): " NS_DOMAIN
        if [[ -z "$NS_DOMAIN" ]]; then echo -e "\n${C_RED}❌ Nameserver domain cannot be empty. Aborting.${C_RESET}"; return; fi
        read -p "👉 Enter your full tunnel domain (e.g., tun.yourdomain.com): " TUNNEL_DOMAIN
        if [[ -z "$TUNNEL_DOMAIN" ]]; then echo -e "\n${C_RED}❌ Tunnel domain cannot be empty. Aborting.${C_RESET}"; return; fi
    else
        echo -e "\n${C_BLUE}⚙️ Configuring DNS records for DNSTT...${C_RESET}"
        local SERVER_IPV4
        SERVER_IPV4=$(curl -s -4 icanhazip.com)
        if ! _is_valid_ipv4 "$SERVER_IPV4"; then
            echo -e "\n${C_RED}❌ Error: Could not retrieve a valid public IPv4 address from icanhazip.com.${C_RESET}"
            echo -e "${C_YELLOW}ℹ️ Please check your server's network connection and DNS resolver settings.${C_RESET}"
            echo -e "   Output received: '$SERVER_IPV4'"
            return 1
        fi
        
        local SERVER_IPV6
        SERVER_IPV6=$(curl -s -6 icanhazip.com --max-time 5)
        
        local RANDOM_STR
        RANDOM_STR=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)
        NS_SUBDOMAIN="ns-$RANDOM_STR"
        TUNNEL_SUBDOMAIN="tun-$RANDOM_STR"
        NS_DOMAIN="$NS_SUBDOMAIN.$DESEC_DOMAIN"
        TUNNEL_DOMAIN="$TUNNEL_SUBDOMAIN.$DESEC_DOMAIN"

        local API_DATA
        API_DATA=$(printf '[{"subname": "%s", "type": "A", "ttl": 3600, "records": ["%s"]}, {"subname": "%s", "type": "NS", "ttl": 3600, "records": ["%s."]}]' \
            "$NS_SUBDOMAIN" "$SERVER_IPV4" "$TUNNEL_SUBDOMAIN" "$NS_DOMAIN")

        if [[ -n "$SERVER_IPV6" ]]; then
            local aaaa_record
            aaaa_record=$(printf ',{"subname": "%s", "type": "AAAA", "ttl": 3600, "records": ["%s"]}' "$NS_SUBDOMAIN" "$SERVER_IPV6")
            API_DATA="${API_DATA%?}${aaaa_record}]"
            HAS_IPV6="true"
        fi

        local CREATE_RESPONSE
        CREATE_RESPONSE=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
            -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" \
            --data "$API_DATA")
        
        local HTTP_CODE=${CREATE_RESPONSE: -3}
        local RESPONSE_BODY=${CREATE_RESPONSE:0:${#CREATE_RESPONSE}-3}

        if [[ "$HTTP_CODE" -ne 201 ]]; then
            echo -e "${C_RED}❌ Failed to create DNSTT records. API returned HTTP $HTTP_CODE.${C_RESET}"
            echo "Response: $RESPONSE_BODY" | jq
            return 1
        fi
    fi
    
    read -p "👉 Enter MTU value (e.g., 512, 1200) or press [Enter] for default: " mtu_value
    local mtu_string=""
    if [[ "$mtu_value" =~ ^[0-9]+$ ]]; then
        mtu_string=" -mtu $mtu_value"
        echo -e "${C_GREEN}ℹ️ Using MTU: $mtu_value${C_RESET}"
    else
        mtu_value=""
        echo -e "${C_YELLOW}ℹ️ Using default MTU.${C_RESET}"
    fi

    echo -e "\n${C_BLUE}📥 Downloading pre-compiled DNSTT server binary...${C_RESET}"
    local arch
    arch=$(uname -m)
    local binary_url=""
    if [[ "$arch" == "x86_64" ]]; then
        binary_url="https://dnstt.network/dnstt-server-linux-amd64"
        echo -e "${C_BLUE}ℹ️ Detected x86_64 (amd64) architecture.${C_RESET}"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        binary_url="https://dnstt.network/dnstt-server-linux-arm64"
        echo -e "${C_BLUE}ℹ️ Detected ARM64 architecture.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Unsupported architecture: $arch. Cannot install DNSTT.${C_RESET}"
        return
    fi
    
    curl -sL "$binary_url" -o "$DNSTT_BINARY"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Failed to download the DNSTT binary.${C_RESET}"
        return
    fi
    chmod +x "$DNSTT_BINARY"

    echo -e "${C_BLUE}🔐 Generating cryptographic keys...${C_RESET}"
    mkdir -p "$DNSTT_KEYS_DIR"
    "$DNSTT_BINARY" -gen-key -privkey-file "$DNSTT_KEYS_DIR/server.key" -pubkey-file "$DNSTT_KEYS_DIR/server.pub"
    if [[ ! -f "$DNSTT_KEYS_DIR/server.key" ]]; then echo -e "${C_RED}❌ Failed to generate DNSTT keys.${C_RESET}"; return; fi
    
    local PUBLIC_KEY
    PUBLIC_KEY=$(cat "$DNSTT_KEYS_DIR/server.pub")
    
    echo -e "\n${C_BLUE}📝 Creating systemd service...${C_RESET}"
    cat > "$DNSTT_SERVICE_FILE" <<-EOF
[Unit]
Description=DNSTT (DNS Tunnel) Server for $forward_desc
After=network.target
[Service]
Type=simple
User=root
ExecStart=$DNSTT_BINARY -udp :53$mtu_string -privkey-file $DNSTT_KEYS_DIR/server.key $TUNNEL_DOMAIN $FORWARD_TARGET
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    echo -e "\n${C_BLUE}💾 Saving configuration and starting service...${C_RESET}"
    cat > "$DNSTT_CONFIG_FILE" <<-EOF
NS_SUBDOMAIN="$NS_SUBDOMAIN"
TUNNEL_SUBDOMAIN="$TUNNEL_SUBDOMAIN"
NS_DOMAIN="$NS_DOMAIN"
TUNNEL_DOMAIN="$TUNNEL_DOMAIN"
PUBLIC_KEY="$PUBLIC_KEY"
FORWARD_DESC="$forward_desc"
DNSTT_RECORDS_MANAGED="$DNSTT_RECORDS_MANAGED"
HAS_IPV6="$HAS_IPV6"
MTU_VALUE="$mtu_value"
EOF
    systemctl daemon-reload
    systemctl enable dnstt.service
    systemctl start dnstt.service
    sleep 2
    if systemctl is-active --quiet dnstt.service; then
        echo -e "\n${C_GREEN}✅ SUCCESS: DNSTT has been installed and started!${C_RESET}"
        show_dnstt_details
    else
        echo -e "\n${C_RED}❌ ERROR: DNSTT service failed to start.${C_RESET}"
        journalctl -u dnstt.service -n 15 --no-pager
    fi
}

uninstall_dnstt() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling DNSTT ---${C_RESET}"
    if [ ! -f "$DNSTT_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ DNSTT does not appear to be installed, skipping.${C_RESET}"
        return
    fi
    local confirm="y"
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        read -p "👉 Are you sure you want to uninstall DNSTT? This will delete DNS records if they were auto-generated. (y/n): " confirm
    fi
    if [[ "$confirm" != "y" ]]; then
        echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
        return
    fi
    echo -e "${C_BLUE}🛑 Stopping and disabling DNSTT service...${C_RESET}"
    systemctl stop dnstt.service > /dev/null 2>&1
    systemctl disable dnstt.service > /dev/null 2>&1
    if [ -f "$DNSTT_CONFIG_FILE" ]; then
        source "$DNSTT_CONFIG_FILE"
        if [[ "$DNSTT_RECORDS_MANAGED" == "true" ]]; then
            echo -e "${C_BLUE}🗑️ Removing auto-generated DNS records...${C_RESET}"
            curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$TUNNEL_SUBDOMAIN/NS/" \
                 -H "Authorization: Token $DESEC_TOKEN" > /dev/null
            curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$NS_SUBDOMAIN/A/" \
                 -H "Authorization: Token $DESEC_TOKEN" > /dev/null
            if [[ "$HAS_IPV6" == "true" ]]; then
                curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$NS_SUBDOMAIN/AAAA/" \
                     -H "Authorization: Token $DESEC_TOKEN" > /dev/null
            fi
            echo -e "${C_GREEN}✅ DNS records have been removed.${C_RESET}"
        else
            echo -e "${C_YELLOW}⚠️ DNS records were manually configured. Please delete them from your DNS provider.${C_RESET}"
        fi
    fi
    echo -e "${C_BLUE}🗑️ Removing service files and binaries...${C_RESET}"
    rm -f "$DNSTT_SERVICE_FILE"
    rm -f "$DNSTT_BINARY"
    rm -rf "$DNSTT_KEYS_DIR"
    rm -f "$DNSTT_CONFIG_FILE"
    systemctl daemon-reload
    
    echo -e "${C_YELLOW}ℹ️ Making /etc/resolv.conf writable again...${C_RESET}"
    chattr -i /etc/resolv.conf &>/dev/null

    echo -e "\n${C_GREEN}✅ DNSTT has been successfully uninstalled.${C_RESET}"
}

install_falcon_proxy() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🦅 Installing Falcon Proxy (Websockets/Socks) ---${C_RESET}"
    
    if [ -f "$FALCONPROXY_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ Falcon Proxy is already installed.${C_RESET}"
        if [ -f "$FALCONPROXY_CONFIG_FILE" ]; then
            source "$FALCONPROXY_CONFIG_FILE"
            echo -e "   It is configured to run on port(s): ${C_YELLOW}$PORTS${C_RESET}"
            echo -e "   Installed Version: ${C_YELLOW}${INSTALLED_VERSION:-Unknown}${C_RESET}"
        fi
        read -p "👉 Do you want to reinstall/update? (y/n): " confirm_reinstall
        if [[ "$confirm_reinstall" != "y" ]]; then return; fi
    fi

    echo -e "\n${C_BLUE}🌐 Fetching available versions from GitHub...${C_RESET}"
    local releases_json=$(curl -s "https://api.github.com/repos/firewallfalcons/FirewallFalcon-Manager/releases")
    if [[ -z "$releases_json" || "$releases_json" == "[]" ]]; then
        echo -e "${C_RED}❌ Error: Could not fetch releases. Check internet or API limits.${C_RESET}"
        return
    fi

    # Extract tag names
    mapfile -t versions < <(echo "$releases_json" | jq -r '.[].tag_name')
    
    if [ ${#versions[@]} -eq 0 ]; then
        echo -e "${C_RED}❌ No releases found in the repository.${C_RESET}"
        return
    fi

    echo -e "\n${C_CYAN}Select a version to install:${C_RESET}"
    for i in "${!versions[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${versions[$i]}"
    done
    echo -e "  ${C_RED} [ 0]${C_RESET} ↩️ Cancel"
    
    local choice
    while true; do
        if ! read -r -p "👉 Enter version number [1]: " choice; then
            echo
            return
        fi
        choice=${choice:-1}
        if [[ "$choice" == "0" ]]; then return; fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#versions[@]}" ]; then
            SELECTED_VERSION="${versions[$((choice-1))]}"
            break
        else
            echo -e "${C_RED}❌ Invalid selection.${C_RESET}"
        fi
    done

    local ports
    read -p "👉 Enter port(s) for Falcon Proxy (e.g., 8080 or 8080 8888) [8080]: " ports
    ports=${ports:-8080}

    local port_array=($ports)
    for port in "${port_array[@]}"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            echo -e "\n${C_RED}❌ Invalid port number: $port. Aborting.${C_RESET}"
            return
        fi
        check_and_free_ports "$port" || return
        check_and_open_firewall_port "$port" tcp || return
    done

    echo -e "\n${C_GREEN}⚙️ Detecting system architecture...${C_RESET}"
    local arch=$(uname -m)
    local binary_name=""
    if [[ "$arch" == "x86_64" ]]; then
        binary_name="falconproxy"
        echo -e "${C_BLUE}ℹ️ Detected x86_64 (amd64) architecture.${C_RESET}"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        binary_name="falconproxyarm"
        echo -e "${C_BLUE}ℹ️ Detected ARM64 architecture.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Unsupported architecture: $arch. Cannot install Falcon Proxy.${C_RESET}"
        return
    fi
    
    # Construct download URL based on selected version
    local download_url="https://github.com/firewallfalcons/FirewallFalcon-Manager/releases/download/$SELECTED_VERSION/$binary_name"

    echo -e "\n${C_GREEN}📥 Downloading Falcon Proxy $SELECTED_VERSION ($binary_name)...${C_RESET}"
    wget -q --show-progress -O "$FALCONPROXY_BINARY" "$download_url"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Failed to download the binary. Please ensure version $SELECTED_VERSION has asset '$binary_name'.${C_RESET}"
        return
    fi
    chmod +x "$FALCONPROXY_BINARY"

    echo -e "\n${C_GREEN}📝 Creating systemd service file...${C_RESET}"
    cat > "$FALCONPROXY_SERVICE_FILE" <<EOF
[Unit]
Description=Falcon Proxy ($SELECTED_VERSION)
After=network.target

[Service]
User=root
Type=simple
ExecStart=$FALCONPROXY_BINARY -p $ports
Restart=always
RestartSec=2s

[Install]
WantedBy=default.target
EOF

    echo -e "\n${C_GREEN}💾 Saving configuration...${C_RESET}"
    cat > "$FALCONPROXY_CONFIG_FILE" <<EOF
PORTS="$ports"
INSTALLED_VERSION="$SELECTED_VERSION"
EOF

    echo -e "\n${C_GREEN}▶️ Enabling and starting Falcon Proxy service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable falconproxy.service
    systemctl restart falconproxy.service
    sleep 2
    
    if systemctl is-active --quiet falconproxy; then
        echo -e "\n${C_GREEN}✅ SUCCESS: Falcon Proxy $SELECTED_VERSION is installed and active.${C_RESET}"
        echo -e "   Listening on port(s): ${C_YELLOW}$ports${C_RESET}"
    else
        echo -e "\n${C_RED}❌ ERROR: Falcon Proxy service failed to start.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Displaying last 15 lines of the service log for diagnostics:${C_RESET}"
        journalctl -u falconproxy.service -n 15 --no-pager
    fi
}

uninstall_falcon_proxy() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling Falcon Proxy ---${C_RESET}"
    if [ ! -f "$FALCONPROXY_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ Falcon Proxy is not installed, skipping.${C_RESET}"
        return
    fi
    echo -e "${C_GREEN}🛑 Stopping and disabling Falcon Proxy service...${C_RESET}"
    systemctl stop falconproxy.service >/dev/null 2>&1
    systemctl disable falconproxy.service >/dev/null 2>&1
    echo -e "${C_GREEN}🗑️ Removing service file...${C_RESET}"
    rm -f "$FALCONPROXY_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${C_GREEN}🗑️ Removing binary and config files...${C_RESET}"
    rm -f "$FALCONPROXY_BINARY"
    rm -f "$FALCONPROXY_CONFIG_FILE"
    echo -e "${C_GREEN}✅ Falcon Proxy has been uninstalled successfully.${C_RESET}"
}

# --- ZiVPN Installation Logic ---
install_zivpn() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing ZiVPN (UDP/VPN) ---${C_RESET}"
    
    if [ -f "$ZIVPN_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ ZiVPN is already installed.${C_RESET}"
        return
    fi

    echo -e "\n${C_GREEN}⚙️ Checking system architecture...${C_RESET}"
    local arch=$(uname -m)
    local zivpn_url=""
    
    if [[ "$arch" == "x86_64" ]]; then
        zivpn_url="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
        echo -e "${C_BLUE}ℹ️ Detected AMD64/x86_64 architecture.${C_RESET}"
    elif [[ "$arch" == "aarch64" ]]; then
        zivpn_url="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64"
        echo -e "${C_BLUE}ℹ️ Detected ARM64 architecture.${C_RESET}"
    elif [[ "$arch" == "armv7l" || "$arch" == "arm" ]]; then
         zivpn_url="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm"
         echo -e "${C_BLUE}ℹ️ Detected ARM architecture.${C_RESET}"
    else
        echo -e "${C_RED}❌ Unsupported architecture: $arch${C_RESET}"
        return
    fi

    echo -e "\n${C_GREEN}📦 Downloading ZiVPN binary...${C_RESET}"
    if ! wget -q --show-progress -O "$ZIVPN_BIN" "$zivpn_url"; then
        echo -e "${C_RED}❌ Download failed. Check internet connection.${C_RESET}"
        return
    fi
    chmod +x "$ZIVPN_BIN"

    echo -e "\n${C_GREEN}⚙️ Configuring ZIVPN...${C_RESET}"
    mkdir -p "$ZIVPN_DIR"
    
    # Generate Certificates
    echo -e "${C_BLUE}🔐 Generating self-signed certificates...${C_RESET}"
    if ! command -v openssl &>/dev/null; then apt-get install -y openssl &>/dev/null; fi
    
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "$ZIVPN_KEY_FILE" -out "$ZIVPN_CERT_FILE" 2>/dev/null

    if [ ! -f "$ZIVPN_CERT_FILE" ]; then
        echo -e "${C_RED}❌ Failed to generate certificates.${C_RESET}"
        return
    fi

    # System Tuning
    echo -e "${C_BLUE}🔧 Tuning system network parameters...${C_RESET}"
    sysctl -w net.core.rmem_max=16777216 >/dev/null
    sysctl -w net.core.wmem_max=16777216 >/dev/null

    # Create Service
    echo -e "${C_BLUE}📝 Creating systemd service file...${C_RESET}"
    cat <<EOF > "$ZIVPN_SERVICE_FILE"
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$ZIVPN_DIR
ExecStart=$ZIVPN_BIN server -c $ZIVPN_CONFIG_FILE
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    # Configure Passwords
    echo -e "\n${C_YELLOW}🔑 ZiVPN Password Setup${C_RESET}"
    read -p "👉 Enter passwords separated by commas (e.g., user1,user2) [Default: 'zi']: " input_config
    
    if [ -n "$input_config" ]; then
        IFS=',' read -r -a config_array <<< "$input_config"
        # Ensure array format for JSON
        json_passwords=$(printf '"%s",' "${config_array[@]}")
        json_passwords="[${json_passwords%,}]"
    else
        json_passwords='["zi"]'
    fi

    # Create Config File
    cat <<EOF > "$ZIVPN_CONFIG_FILE"
{
  "listen": ":5667",
   "cert": "$ZIVPN_CERT_FILE",
   "key": "$ZIVPN_KEY_FILE",
   "obfs":"zivpn",
   "auth": {
    "mode": "passwords", 
    "config": $json_passwords
  }
}
EOF

    echo -e "\n${C_GREEN}🚀 Starting ZiVPN Service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service

    # Port Forwarding / Firewall
    echo -e "${C_BLUE}🔥 Configuring Firewall Rules (Redirecting 6000-19999 -> 5667)...${C_RESET}"
    
    # Determine primary interface
    local iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    
    if [ -n "$iface" ]; then
        iptables -t nat -A PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
        # Note: IPTables rules are not persistent by default without iptables-persistent package
    else
        echo -e "${C_YELLOW}⚠️ Could not detect default interface for IPTables redirection.${C_RESET}"
    fi

    if command -v ufw &>/dev/null; then
        ufw allow 6000:19999/udp >/dev/null
        ufw allow 5667/udp >/dev/null
    fi

    # Cleanup
    rm -f zi.sh zi2.sh 2>/dev/null

    if systemctl is-active --quiet zivpn.service; then
        echo -e "\n${C_GREEN}✅ ZiVPN Installed Successfully!${C_RESET}"
        echo -e "   - UDP Port: 5667 (Direct)"
        echo -e "   - UDP Ports: 6000-19999 (Forwarded)"
    else
        echo -e "\n${C_RED}❌ ZiVPN Service failed to start. Check logs: journalctl -u zivpn.service${C_RESET}"
    fi
}

uninstall_zivpn() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Uninstall ZiVPN ---${C_RESET}"
    
    if [ ! -f "$ZIVPN_SERVICE_FILE" ] && [ ! -f "$ZIVPN_BIN" ]; then
        echo -e "\n${C_YELLOW}ℹ️ ZiVPN does not appear to be installed.${C_RESET}"
        return
    fi

    read -p "👉 Are you sure you want to uninstall ZiVPN? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo -e "${C_YELLOW}Cancelled.${C_RESET}"; return; fi

    echo -e "\n${C_BLUE}🛑 Stopping services...${C_RESET}"
    systemctl stop zivpn.service 2>/dev/null
    systemctl disable zivpn.service 2>/dev/null
    
    echo -e "${C_BLUE}🗑️ Removing files...${C_RESET}"
    rm -f "$ZIVPN_SERVICE_FILE"
    rm -rf "$ZIVPN_DIR"
    rm -f "$ZIVPN_BIN"
    
    systemctl daemon-reload
    
    # Clean cache (from original uninstall script logic)
    echo -e "${C_BLUE}🧹 Cleaning memory cache...${C_RESET}"
    sync; echo 3 > /proc/sys/vm/drop_caches

    echo -e "\n${C_GREEN}✅ ZiVPN Uninstalled Successfully.${C_RESET}"
}

purge_nginx() {
    local mode="$1"
    if [[ "$mode" != "silent" ]]; then
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🔥 Purge Internal Nginx Proxy ---${C_RESET}"
        if ! command -v nginx &> /dev/null; then
            rm -f "$NGINX_PORTS_FILE"
            echo -e "\n${C_YELLOW}ℹ️ Nginx is not installed. Nothing to do.${C_RESET}"
            return
        fi
        echo -e "\n${C_YELLOW}⚠️ This removes the internal Nginx proxy on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"
        if systemctl is-active --quiet haproxy; then
            echo -e "${C_YELLOW}⚠️ HAProxy will stay installed, but web payload routing from ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} will stop until you reinstall the stack.${C_RESET}"
        fi
        read -p "👉 Continue and purge Nginx? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
            return
        fi
    fi
    echo -e "\n${C_BLUE}🛑 Stopping Nginx service...${C_RESET}"
    systemctl stop nginx >/dev/null 2>&1
    systemctl disable nginx >/dev/null 2>&1
    echo -e "\n${C_BLUE}🗑️ Purging Nginx packages...${C_RESET}"
    apt-get purge -y nginx nginx-common >/dev/null 2>&1
    apt-get autoremove -y >/dev/null 2>&1
    echo -e "\n${C_BLUE}🗑️ Removing leftover files...${C_RESET}"
    rm -f /etc/ssl/certs/nginx-selfsigned.pem
    rm -f /etc/ssl/private/nginx-selfsigned.key
    rm -rf /etc/nginx
    rm -f "${NGINX_CONFIG_FILE}.bak"
    rm -f "${NGINX_CONFIG_FILE}.bak.certbot"
    rm -f "${NGINX_CONFIG_FILE}.bak.selfsigned"
    rm -f "${NGINX_CONFIG_FILE}.bak.firewallfalcon"
    rm -f "$NGINX_PORTS_FILE"
    if [[ "$mode" != "silent" ]]; then
        echo -e "\n${C_GREEN}✅ Internal Nginx proxy purged. Shared FirewallFalcon certificates were kept.${C_RESET}"
    fi
}

install_nginx_proxy() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Reconfiguring Internal Nginx Proxy (8880/8443) ---${C_RESET}"
    echo -e "\n${C_CYAN}This keeps HAProxy on ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} and rewrites the internal Nginx proxy on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"

    if [ ! -s "$SSL_CERT_FILE" ] || [ ! -s "$SSL_CERT_CHAIN_FILE" ] || [ ! -s "$SSL_CERT_KEY_FILE" ]; then
        echo -e "\n${C_YELLOW}⚠️ No shared FirewallFalcon certificate was found.${C_RESET}"
        echo -e "${C_DIM}Running the full HAProxy edge installer so the certificate and both services stay aligned.${C_RESET}"
        install_ssl_tunnel
        return
    fi

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"
    ensure_edge_stack_packages || return

    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 1

    check_and_free_ports \
        "$EDGE_PUBLIC_HTTP_PORT" \
        "$EDGE_PUBLIC_TLS_PORT" \
        "$NGINX_INTERNAL_HTTP_PORT" \
        "$NGINX_INTERNAL_TLS_PORT" \
        "$HAPROXY_INTERNAL_DECRYPT_PORT" || return

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    load_edge_cert_info
    local server_name="${EDGE_DOMAIN:-$(detect_preferred_host)}"
    [[ -z "$server_name" ]] && server_name="_"

    configure_edge_stack "$server_name" || return

    echo -e "\n${C_GREEN}✅ Internal Nginx proxy reconfigured successfully.${C_RESET}"
    echo -e "   • Public HAProxy edge: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx: ${C_YELLOW}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
}

request_certbot_ssl() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔒 Shared Certbot Certificate (HAProxy + Nginx) ---${C_RESET}"
    echo -e "\n${C_DIM}This will replace the shared certificate used by HAProxy on ${EDGE_PUBLIC_TLS_PORT} and internal Nginx on ${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"
    ensure_edge_stack_packages || return
    load_edge_cert_info

    local preferred_host
    local default_domain=""
    local domain_name
    local email

    preferred_host=$(detect_preferred_host)
    if [[ -n "$EDGE_DOMAIN" ]] && ! _is_valid_ipv4 "$EDGE_DOMAIN"; then
        default_domain="$EDGE_DOMAIN"
    elif [[ -n "$preferred_host" ]] && ! _is_valid_ipv4 "$preferred_host"; then
        default_domain="$preferred_host"
    fi

    if [[ -n "$default_domain" ]]; then
        read -p "👉 Enter your domain name [$default_domain]: " domain_name
        domain_name=${domain_name:-$default_domain}
    else
        read -p "👉 Enter your domain name (e.g. vpn.example.com): " domain_name
    fi
    if [[ -z "$domain_name" ]]; then
        echo -e "\n${C_RED}❌ Domain name cannot be empty.${C_RESET}"
        return
    fi
    if _is_valid_ipv4 "$domain_name"; then
        echo -e "\n${C_RED}❌ Certbot requires a real domain name, not a raw IP address.${C_RESET}"
        return
    fi

    read -p "👉 Enter your email for Let's Encrypt [${EDGE_EMAIL}]: " email
    email=${email:-$EDGE_EMAIL}
    if [[ -z "$email" ]]; then
        echo -e "\n${C_RED}❌ Email address cannot be empty.${C_RESET}"
        return
    fi

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    obtain_certbot_edge_cert "$domain_name" "$email" || return
    configure_edge_stack "$domain_name" || return

    echo -e "\n${C_GREEN}✅ Shared Certbot certificate applied successfully.${C_RESET}"
    echo -e "   • Domain: ${C_YELLOW}${domain_name}${C_RESET}"
    echo -e "   • Public edge: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
}

nginx_proxy_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🌐 Internal Nginx Proxy Management ---${C_RESET}"

    local nginx_status="${C_STATUS_I}Inactive${C_RESET}"
    local haproxy_status="${C_STATUS_I}Inactive${C_RESET}"
    if systemctl is-active --quiet nginx; then
        nginx_status="${C_STATUS_A}Active${C_RESET}"
    fi
    if systemctl is-active --quiet haproxy; then
        haproxy_status="${C_STATUS_A}Active${C_RESET}"
    fi

    load_edge_cert_info
    local cert_info="${EDGE_CERT_MODE:-Not configured}"
    if [[ -n "$EDGE_DOMAIN" ]]; then
        cert_info="${cert_info} - ${EDGE_DOMAIN}"
    fi

    echo -e "\n${C_WHITE}Nginx:${C_RESET} ${nginx_status}"
    echo -e "${C_WHITE}HAProxy:${C_RESET} ${haproxy_status}"
    echo -e "${C_DIM}Public Edge: ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} | Internal Nginx: ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    echo -e "${C_DIM}Shared Certificate: ${cert_info}${C_RESET}"

    echo -e "\n${C_BOLD}Select an action:${C_RESET}\n"
    
    if systemctl is-active --quiet nginx; then
         printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "🛑 Stop Nginx Service"
         printf "  ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "🔄 Restart HAProxy + Nginx Stack"
         printf "  ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "⚙️ Re-install/Re-configure Edge Stack"
         printf "  ${C_CHOICE}[ 4]${C_RESET} %-40s\n" "🔒 Switch/Renew Shared SSL (Certbot)"
         printf "  ${C_CHOICE}[ 5]${C_RESET} %-40s\n" "🔥 Uninstall/Purge Nginx"
    else
         printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "▶️ Start Nginx Service"
         printf "  ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "⚙️ Install/Configure Edge Stack"
         printf "  ${C_CHOICE}[ 4]${C_RESET} %-40s\n" "🔒 Switch/Renew Shared SSL (Certbot)"
         printf "  ${C_CHOICE}[ 5]${C_RESET} %-40s\n" "🔥 Uninstall/Purge Nginx"
    fi

    echo -e "\n  ${C_WARN}[ 0]${C_RESET} ↩️ Return to previous menu"
    echo
    read -p "👉 Enter your choice: " choice
    
    case $choice in
        1) 
            if systemctl is-active --quiet nginx; then
                echo -e "\n${C_BLUE}🛑 Stopping Nginx...${C_RESET}"
                systemctl stop nginx
                echo -e "${C_GREEN}✅ Nginx stopped.${C_RESET}"
                if systemctl is-active --quiet haproxy; then
                    echo -e "${C_YELLOW}⚠️ HAProxy is still running, but web traffic that depends on internal Nginx will not work until Nginx starts again.${C_RESET}"
                fi
            else
                echo -e "\n${C_BLUE}▶️ Starting Nginx...${C_RESET}"
                systemctl start nginx
                if systemctl is-active --quiet nginx; then
                    echo -e "${C_GREEN}✅ Nginx started.${C_RESET}"
                else
                    echo -e "${C_RED}❌ Failed to start Nginx.${C_RESET}"
                fi
            fi
            press_enter
            ;;
        2)
            echo -e "\n${C_BLUE}🔄 Restarting Nginx and HAProxy...${C_RESET}"
            local restart_ok=true
            systemctl restart nginx || restart_ok=false
            if command -v haproxy &> /dev/null; then
                systemctl restart haproxy || restart_ok=false
            else
                restart_ok=false
            fi
            if $restart_ok && systemctl is-active --quiet nginx && systemctl is-active --quiet haproxy; then
                echo -e "${C_GREEN}✅ HAProxy + Nginx stack restarted.${C_RESET}"
            else
                echo -e "${C_RED}❌ One or more services failed to restart.${C_RESET}"
            fi
            press_enter
            ;;
        3) 
             install_nginx_proxy; press_enter
             ;;
        4)
             request_certbot_ssl; press_enter
             ;;
        5)
             purge_nginx; press_enter
             ;;
        0) return ;;
        *) invalid_option ;;
    esac
}

install_xui_panel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Install X-UI Panel ---${C_RESET}"
    echo -e "\nThis will download and run the official installation script for X-UI."
    echo -e "Choose an installation option:\n"
    echo -e "Choose an installation option:\n"
    printf "  ${C_GREEN}[ 1]${C_RESET} %-40s\n" "Install the latest version of X-UI"
    printf "  ${C_GREEN}[ 2]${C_RESET} %-40s\n" "Install a specific version of X-UI"
    echo -e "\n  ${C_RED}[ 0]${C_RESET} ❌ Cancel Installation"
    echo
    read -p "👉 Select an option: " choice
    case $choice in
        1)
            echo -e "\n${C_BLUE}⚙️ Installing the latest version...${C_RESET}"
            bash <(curl -Ls https://raw.githubusercontent.com/alireza0/x-ui/master/install.sh)
            ;;
        2)
            read -p "👉 Enter the version to install (e.g., 1.8.0): " version
            if [[ -z "$version" ]]; then
                echo -e "\n${C_RED}❌ Version number cannot be empty.${C_RESET}"
                return
            fi
            echo -e "\n${C_BLUE}⚙️ Installing version ${C_YELLOW}$version...${C_RESET}"
            VERSION=$version bash <(curl -Ls "https://raw.githubusercontent.com/alireza0/x-ui/$version/install.sh") "$version"
            ;;
        0)
            echo -e "\n${C_YELLOW}❌ Installation cancelled.${C_RESET}"
            ;;
        *)
            echo -e "\n${C_RED}❌ Invalid option.${C_RESET}"
            ;;
    esac
}

uninstall_xui_panel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Uninstall X-UI Panel ---${C_RESET}"
    if ! command -v x-ui &> /dev/null; then
        echo -e "\n${C_YELLOW}ℹ️ X-UI does not appear to be installed.${C_RESET}"
        return
    fi
    read -p "👉 Are you sure you want to thoroughly uninstall X-UI? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        echo -e "\n${C_BLUE}⚙️ Running the default X-UI uninstaller first...${C_RESET}"
        x-ui uninstall >/dev/null 2>&1
        echo -e "\n${C_BLUE}🧹 Performing a full cleanup to ensure complete removal...${C_RESET}"
        echo " - Stopping and disabling x-ui service..."
        systemctl stop x-ui >/dev/null 2>&1
        systemctl disable x-ui >/dev/null 2>&1
        echo " - Removing x-ui files and directories..."
        rm -f /etc/systemd/system/x-ui.service
        rm -f /usr/local/bin/x-ui
        rm -rf /usr/local/x-ui/
        rm -rf /etc/x-ui/
        echo " - Reloading systemd daemon..."
        systemctl daemon-reload
        echo -e "\n${C_GREEN}✅ X-UI has been thoroughly uninstalled.${C_RESET}"
    else
        echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
    fi
}

refresh_ssh_session_cache() {
    local now db_mtime
    now=$(date +%s)
    db_mtime=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo 0)

    if (( SSH_SESSION_CACHE_TS > 0 && now - SSH_SESSION_CACHE_TS < SSH_SESSION_CACHE_TTL && db_mtime == SSH_SESSION_CACHE_DB_MTIME )); then
        return
    fi

    SSH_SESSION_COUNTS=()
    SSH_SESSION_PIDS=()
    SSH_SESSION_TOTAL=0
    SSH_SESSION_CACHE_DB_MTIME=$db_mtime

    if [[ ! -s "$DB_FILE" ]]; then
        SSH_SESSION_CACHE_TS=$now
        return
    fi

    local -A managed_user_lookup=()
    local -A uid_user_lookup=()
    local -A seen_sessions=()
    local managed_user system_user system_uid ssh_pid ssh_owner candidate_user login_uid

    while IFS=: read -r managed_user _rest; do
        [[ -n "$managed_user" && "$managed_user" != \#* ]] && managed_user_lookup["$managed_user"]=1
    done < "$DB_FILE"

    while IFS=: read -r system_user _ system_uid _rest; do
        [[ -n "$system_user" && "$system_uid" =~ ^[0-9]+$ ]] && uid_user_lookup["$system_uid"]="$system_user"
    done < /etc/passwd

    while read -r ssh_pid ssh_owner; do
        [[ "$ssh_pid" =~ ^[0-9]+$ ]] || continue

        candidate_user=""
        if [[ -n "$ssh_owner" && "$ssh_owner" != "root" && "$ssh_owner" != "sshd" && -n "${managed_user_lookup[$ssh_owner]+x}" ]]; then
            candidate_user="$ssh_owner"
        elif [[ -r "/proc/$ssh_pid/loginuid" ]]; then
            login_uid=""
            read -r login_uid < "/proc/$ssh_pid/loginuid" || login_uid=""
            if [[ "$login_uid" =~ ^[0-9]+$ && "$login_uid" != "4294967295" ]]; then
                candidate_user="${uid_user_lookup[$login_uid]}"
            fi
        fi

        [[ -n "$candidate_user" && -n "${managed_user_lookup[$candidate_user]+x}" ]] || continue
        [[ -z "${seen_sessions[$candidate_user:$ssh_pid]+x}" ]] || continue

        seen_sessions["$candidate_user:$ssh_pid"]=1
        ((SSH_SESSION_COUNTS["$candidate_user"]++))
        SSH_SESSION_PIDS["$candidate_user"]+="$ssh_pid "
        ((SSH_SESSION_TOTAL++))
    done < <(ps -C sshd -o pid=,user= 2>/dev/null)

    SSH_SESSION_CACHE_TS=$now
}

count_managed_online_sessions() {
    refresh_ssh_session_cache
    echo "$SSH_SESSION_TOTAL"
}

invalidate_banner_cache() {
    BANNER_CACHE_TS=0
    SSH_SESSION_CACHE_TS=0
}

refresh_banner_cache() {
    local now
    now=$(date +%s)
    if (( BANNER_CACHE_TS > 0 && now - BANNER_CACHE_TS < BANNER_CACHE_TTL )); then
        return
    fi

    if [[ -z "$BANNER_CACHE_OS_NAME" ]]; then
        BANNER_CACHE_OS_NAME=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo "Linux")
    fi
    BANNER_CACHE_UP_TIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
    BANNER_CACHE_RAM_USAGE=$(free -m | awk '/^Mem:/{if($2>0){printf "%.2f", $3*100/$2}else{print "0.00"}}')
    BANNER_CACHE_CPU_LOAD=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    if [[ -s "$DB_FILE" ]]; then
        BANNER_CACHE_TOTAL_USERS=$(grep -c . "$DB_FILE")
    else
        BANNER_CACHE_TOTAL_USERS=0
    fi
    BANNER_CACHE_ONLINE_USERS=$(count_managed_online_sessions)
    BANNER_CACHE_TS=$now
}

show_banner() {
    refresh_banner_cache
    [[ -t 1 ]] && clear
    echo
    echo -e "${C_TITLE}   FirewallFalcon Manager ${C_RESET}${C_DIM}| v4.0.0 Premium Edition${C_RESET}"
    echo -e "${C_BLUE}   ─────────────────────────────────────────────────────────${C_RESET}"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "OS" "$BANNER_CACHE_OS_NAME" "Uptime: $BANNER_CACHE_UP_TIME"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "Memory" "${BANNER_CACHE_RAM_USAGE}% Used" "Online Sessions: ${C_WHITE}${BANNER_CACHE_ONLINE_USERS}${C_RESET}"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "Users" "${BANNER_CACHE_TOTAL_USERS} Managed Accounts" "Sys Load (1m): ${C_GREEN}${BANNER_CACHE_CPU_LOAD}${C_RESET}"
    echo -e "${C_BLUE}   ─────────────────────────────────────────────────────────${C_RESET}"
}

protocol_menu() {
    while true; do
        show_banner
        local badvpn_status; if systemctl is-active --quiet badvpn; then badvpn_status="${C_STATUS_A}(Active)${C_RESET}"; else badvpn_status="${C_STATUS_I}(Inactive)${C_RESET}"; fi
        local udp_custom_status; if systemctl is-active --quiet udp-custom; then udp_custom_status="${C_STATUS_A}(Active)${C_RESET}"; else udp_custom_status="${C_STATUS_I}(Inactive)${C_RESET}"; fi
        local zivpn_status; if systemctl is-active --quiet zivpn.service; then zivpn_status="${C_STATUS_A}(Active)${C_RESET}"; else zivpn_status="${C_STATUS_I}(Inactive)${C_RESET}"; fi
        
        local ssl_tunnel_text="HAProxy Edge Stack (80/443)"
        local ssl_tunnel_status="${C_STATUS_I}(Inactive)${C_RESET}"
        if systemctl is-active --quiet haproxy; then
            ssl_tunnel_status="${C_STATUS_A}(Active)${C_RESET}"
        fi
        
        local dnstt_status; if systemctl is-active --quiet dnstt.service; then dnstt_status="${C_STATUS_A}(Active)${C_RESET}"; else dnstt_status="${C_STATUS_I}(Inactive)${C_RESET}"; fi
        
        local falconproxy_status="${C_STATUS_I}(Inactive)${C_RESET}"
        local falconproxy_ports=""
        if systemctl is-active --quiet falconproxy; then
            if [ -f "$FALCONPROXY_CONFIG_FILE" ]; then source "$FALCONPROXY_CONFIG_FILE"; fi
            falconproxy_ports=" ($PORTS)"
            falconproxy_status="${C_STATUS_A}(Active - ${INSTALLED_VERSION:-latest})${C_RESET}"
        fi

        local nginx_status; if systemctl is-active --quiet nginx; then nginx_status="${C_STATUS_A}(Active)${C_RESET}"; else nginx_status="${C_STATUS_I}(Inactive)${C_RESET}"; fi
        local xui_status; if command -v x-ui &> /dev/null; then xui_status="${C_STATUS_A}(Installed)${C_RESET}"; else xui_status="${C_STATUS_I}(Not Installed)${C_RESET}"; fi
        
        echo -e "\n   ${C_TITLE}══════════════[ ${C_BOLD}🔌 PROTOCOL & PANEL MANAGEMENT ${C_RESET}${C_TITLE}]══════════════${C_RESET}"
        echo -e "     ${C_ACCENT}--- TUNNELLING PROTOCOLS---${C_RESET}"
        printf "     ${C_CHOICE}[ 1]${C_RESET} %-45s %s\n" "🚀 Install badvpn (UDP 7300)" "$badvpn_status"
        printf "     ${C_CHOICE}[ 2]${C_RESET} %-45s\n" "🗑️ Uninstall badvpn"
        printf "     ${C_CHOICE}[ 3]${C_RESET} %-45s %s\n" "🚀 Install udp-custom" "$udp_custom_status"
        printf "     ${C_CHOICE}[ 4]${C_RESET} %-45s\n" "🗑️ Uninstall udp-custom"
        printf "     ${C_CHOICE}[ 5]${C_RESET} %-45s %s\n" "🔒 Install ${ssl_tunnel_text}" "$ssl_tunnel_status"
        printf "     ${C_CHOICE}[ 6]${C_RESET} %-45s\n" "🗑️ Uninstall HAProxy Edge Stack"
        printf "     ${C_CHOICE}[ 7]${C_RESET} %-45s %s\n" "📡 Install/View DNSTT (Port 53)" "$dnstt_status"
        printf "     ${C_CHOICE}[ 8]${C_RESET} %-45s\n" "🗑️ Uninstall DNSTT"
        printf "     ${C_CHOICE}[ 9]${C_RESET} %-45s %s\n" "🦅 Install Falcon Proxy (Select Version)" "$falconproxy_status"
        printf "     ${C_CHOICE}[10]${C_RESET} %-45s\n" "🗑️ Uninstall Falcon Proxy"
        printf "     ${C_CHOICE}[11]${C_RESET} %-45s %s\n" "🌐 Install/Manage Internal Nginx (8880/8443)" "$nginx_status"
        printf "     ${C_CHOICE}[16]${C_RESET} %-45s %s\n" "🛡️ Install ZiVPN (UDP 5667)" "$zivpn_status"
        printf "     ${C_CHOICE}[17]${C_RESET} %-45s\n" "🗑️ Uninstall ZiVPN"
        
        echo -e "     ${C_ACCENT}--- 💻 MANAGEMENT PANELS ---${C_RESET}"
        printf "     ${C_CHOICE}[12]${C_RESET} %-45s %s\n" "💻 Install X-UI Panel" "$xui_status"
        printf "     ${C_CHOICE}[13]${C_RESET} %-45s\n" "🗑️ Uninstall X-UI Panel"
        
        echo -e "   ${C_DIM}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${C_RESET}"
        echo -e "     ${C_WARN}[ 0]${C_RESET} ↩️ Return to Main Menu"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice; then
            echo
            return
        fi
        case $choice in
            1) install_badvpn; press_enter ;; 2) uninstall_badvpn; press_enter ;;
            3) install_udp_custom; press_enter ;; 4) uninstall_udp_custom; press_enter ;;
            5) install_ssl_tunnel; press_enter ;; 6) uninstall_ssl_tunnel; press_enter ;;
            7) install_dnstt; press_enter ;; 8) uninstall_dnstt; press_enter ;;
            9) install_falcon_proxy; press_enter ;; 10) uninstall_falcon_proxy; press_enter ;;
            11) nginx_proxy_menu ;;
            12) install_xui_panel; press_enter ;; 13) uninstall_xui_panel; press_enter ;;
            16) install_zivpn; press_enter ;; 17) uninstall_zivpn; press_enter ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

uninstall_script() {
    clear; show_banner
    echo -e "${C_RED}=====================================================${C_RESET}"
    echo -e "${C_RED}       🔥 DANGER: UNINSTALL SCRIPT & ALL DATA 🔥      ${C_RESET}"
    echo -e "${C_RED}=====================================================${C_RESET}"
    echo -e "${C_YELLOW}This will PERMANENTLY remove this script and all its components, including:"
    echo -e " - The main command ($(command -v menu))"
    echo -e " - All configuration and user data ($DB_DIR)"
    echo -e " - The active limiter service ($LIMITER_SERVICE)"
    echo -e " - All installed services (badvpn, udp-custom, HAProxy Edge Stack, Nginx, DNSTT)"
    echo -e "\n${C_RED}This action is irreversible.${C_RESET}"
    echo ""
    read -p "👉 Type 'yes' to confirm and proceed with uninstallation: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "\n${C_GREEN}✅ Uninstallation cancelled.${C_RESET}"
        return
    fi
    local -a removable_users=()
    local remove_users_confirm
    local remove_users_on_uninstall=false
    mapfile -t removable_users < <(get_firewallfalcon_known_users)
    if [[ ${#removable_users[@]} -gt 0 ]]; then
        echo -e "\n${C_YELLOW}FirewallFalcon SSH users detected on this VPS:${C_RESET} ${removable_users[*]}"
        read -p "👉 Do you also want to permanently delete these SSH users before uninstalling? (y/n): " remove_users_confirm
        if [[ "$remove_users_confirm" == "y" || "$remove_users_confirm" == "Y" ]]; then
            remove_users_on_uninstall=true
        fi
    fi
    export UNINSTALL_MODE="silent"
    echo -e "\n${C_BLUE}--- 💥 Starting Uninstallation 💥 ---${C_RESET}"
    
    if [[ "$remove_users_on_uninstall" == "true" ]]; then
        echo -e "\n${C_BLUE}🗑️ Removing FirewallFalcon SSH users before uninstall...${C_RESET}"
        delete_firewallfalcon_user_accounts "${removable_users[@]}"
    fi
    
    echo -e "\n${C_BLUE}🗑️ Removing active limiter service...${C_RESET}"
    systemctl stop firewallfalcon-limiter &>/dev/null
    systemctl disable firewallfalcon-limiter &>/dev/null
    rm -f "$LIMITER_SERVICE"
    rm -f "$LIMITER_SCRIPT"
    
    echo -e "\n${C_BLUE}🗑️ Removing bandwidth monitoring service...${C_RESET}"
    systemctl stop firewallfalcon-bandwidth &>/dev/null
    systemctl disable firewallfalcon-bandwidth &>/dev/null
    rm -f "$BANDWIDTH_SERVICE"
    rm -f "$BANDWIDTH_SCRIPT"
    rm -f "$TRIAL_CLEANUP_SCRIPT"
    
    echo -e "\n${C_BLUE}\ud83d\uddd1\ufe0f Removing SSH login banner...${C_RESET}"
    rm -f "$LOGIN_INFO_SCRIPT"
    rm -f "$SSHD_FF_CONFIG"
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    
    chattr -i /etc/resolv.conf &>/dev/null

    purge_nginx "silent"
    uninstall_dnstt
    uninstall_badvpn
    uninstall_udp_custom
    uninstall_ssl_tunnel
    uninstall_falcon_proxy
    uninstall_zivpn
    delete_dns_record
    
    echo -e "\n${C_BLUE}🔄 Reloading systemd daemon...${C_RESET}"
    systemctl daemon-reload
    
    echo -e "\n${C_BLUE}🗑️ Removing script and configuration files...${C_RESET}"
    rm -rf "$BADVPN_BUILD_DIR"
    rm -rf "$UDP_CUSTOM_DIR"
    rm -rf "$DB_DIR"
    rm -f "$(command -v menu)"
    
    echo -e "\n${C_GREEN}=============================================${C_RESET}"
    echo -e "${C_GREEN}      Script has been successfully uninstalled.     ${C_RESET}"
    echo -e "${C_GREEN}=============================================${C_RESET}"
    echo -e "\nAll associated files and services have been removed."
    echo "The 'menu' command will no longer work."
    exit 0
}

# --- NEW FEATURES ---

create_trial_account() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ⏱️ Create Trial/Test Account ---${C_RESET}"
    
    # Ensure 'at' daemon is available
    if ! command -v at &>/dev/null; then
        echo -e "${C_YELLOW}⚠️ 'at' command not found. Installing...${C_RESET}"
        apt-get update > /dev/null 2>&1 && apt-get install -y at || {
            echo -e "${C_RED}❌ Failed to install 'at'. Cannot schedule auto-expiry.${C_RESET}"
            return
        }
        systemctl enable atd &>/dev/null
        systemctl start atd &>/dev/null
    fi
    
    # Ensure atd is running
    if ! systemctl is-active --quiet atd; then
        systemctl start atd &>/dev/null
    fi
    
    echo -e "\n${C_CYAN}Select trial duration:${C_RESET}\n"
    printf "  ${C_GREEN}[ 1]${C_RESET} ⏱️  1 Hour\n"
    printf "  ${C_GREEN}[ 2]${C_RESET} ⏱️  2 Hours\n"
    printf "  ${C_GREEN}[ 3]${C_RESET} ⏱️  3 Hours\n"
    printf "  ${C_GREEN}[ 4]${C_RESET} ⏱️  6 Hours\n"
    printf "  ${C_GREEN}[ 5]${C_RESET} ⏱️  12 Hours\n"
    printf "  ${C_GREEN}[ 6]${C_RESET} 📅  1 Day\n"
    printf "  ${C_GREEN}[ 7]${C_RESET} 📅  3 Days\n"
    printf "  ${C_GREEN}[ 8]${C_RESET} ⚙️  Custom (enter hours)\n"
    echo -e "\n  ${C_RED}[ 0]${C_RESET} ↩️ Cancel"
    echo
    read -p "👉 Select duration: " dur_choice
    
    local duration_hours=0
    local duration_label=""
    case $dur_choice in
        1) duration_hours=1;   duration_label="1 Hour" ;;
        2) duration_hours=2;   duration_label="2 Hours" ;;
        3) duration_hours=3;   duration_label="3 Hours" ;;
        4) duration_hours=6;   duration_label="6 Hours" ;;
        5) duration_hours=12;  duration_label="12 Hours" ;;
        6) duration_hours=24;  duration_label="1 Day" ;;
        7) duration_hours=72;  duration_label="3 Days" ;;
        8) read -p "👉 Enter custom duration in hours: " custom_hours
           if ! [[ "$custom_hours" =~ ^[0-9]+$ ]] || [[ "$custom_hours" -lt 1 ]]; then
               echo -e "\n${C_RED}❌ Invalid number of hours.${C_RESET}"; return
           fi
           duration_hours=$custom_hours
           duration_label="$custom_hours Hours"
           ;;
        0) echo -e "\n${C_YELLOW}❌ Cancelled.${C_RESET}"; return ;;
        *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}"; return ;;
    esac
    
    # Username
    local rand_suffix=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 5)
    local default_username="trial_${rand_suffix}"
    read -p "👤 Username [${default_username}]: " username
    username=${username:-$default_username}
    
    if id "$username" &>/dev/null || grep -q "^$username:" "$DB_FILE"; then
        echo -e "\n${C_RED}❌ Error: User '$username' already exists.${C_RESET}"; return
    fi
    
    # Password
    local password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
    read -p "🔑 Password [${password}]: " custom_pass
    password=${custom_pass:-$password}
    
    # Connection limit
    read -p "📶 Connection limit [1]: " limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    # Bandwidth limit
    read -p "📦 Bandwidth limit in GB (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    # Calculate expiry
    local expire_date
    if [[ "$duration_hours" -ge 24 ]]; then
        local days=$((duration_hours / 24))
        expire_date=$(date -d "+$days days" +%Y-%m-%d)
    else
        # For sub-day durations, set expiry to tomorrow to be safe (at job does the real cleanup)
        expire_date=$(date -d "+1 day" +%Y-%m-%d)
    fi
    local expiry_timestamp
    expiry_timestamp=$(date -d "+${duration_hours} hours" '+%Y-%m-%d %H:%M:%S')
    
    # Create the system user
    ensure_firewallfalcon_system_group
    useradd -m -s /usr/sbin/nologin "$username"
    usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
    echo "$username:$password" | chpasswd
    chage -E "$expire_date" "$username"
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb" >> "$DB_FILE"
    
    # Schedule auto-cleanup via 'at'
    echo "$TRIAL_CLEANUP_SCRIPT $username" | at now + ${duration_hours} hours 2>/dev/null
    
    local bw_display="Unlimited"
    if [[ "$bandwidth_gb" != "0" ]]; then bw_display="${bandwidth_gb} GB"; fi
    
    clear; show_banner
    echo -e "${C_GREEN}✅ Trial account created successfully!${C_RESET}\n"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "  ⏱️  ${C_BOLD}TRIAL ACCOUNT${C_RESET}"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "  - 👤 Username:          ${C_YELLOW}$username${C_RESET}"
    echo -e "  - 🔑 Password:          ${C_YELLOW}$password${C_RESET}"
    echo -e "  - ⏱️ Duration:          ${C_CYAN}$duration_label${C_RESET}"
    echo -e "  - 🕐 Auto-expires at:   ${C_RED}$expiry_timestamp${C_RESET}"
    echo -e "  - 📶 Connection Limit:  ${C_YELLOW}$limit${C_RESET}"
    echo -e "  - 📦 Bandwidth Limit:   ${C_YELLOW}$bw_display${C_RESET}"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "\n${C_DIM}The account will be automatically deleted when the trial expires.${C_RESET}"
    
    # Auto-ask for config generation
    echo
    read -p "👉 Generate client config for this trial user? (y/n): " gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_client_config "$username" "$password"
    fi
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

view_user_bandwidth() {
    _select_user_interface "--- 📊 View User Bandwidth ---"
    local u=$SELECTED_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi
    
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📊 Bandwidth Details: ${C_YELLOW}$u${C_PURPLE} ---${C_RESET}\n"
    
    local line; line=$(grep "^$u:" "$DB_FILE")
    local bandwidth_gb; bandwidth_gb=$(echo "$line" | cut -d: -f5)
    [[ -z "$bandwidth_gb" ]] && bandwidth_gb="0"
    
    local used_bytes=0
    if [[ -f "$BANDWIDTH_DIR/${u}.usage" ]]; then
        used_bytes=$(cat "$BANDWIDTH_DIR/${u}.usage" 2>/dev/null)
        [[ -z "$used_bytes" ]] && used_bytes=0
    fi
    
    local used_mb; used_mb=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1048576}")
    local used_gb; used_gb=$(awk "BEGIN {printf \"%.3f\", $used_bytes / 1073741824}")
    
    echo -e "  ${C_CYAN}Data Used:${C_RESET}        ${C_WHITE}${used_gb} GB${C_RESET} (${used_mb} MB)"
    
    if [[ "$bandwidth_gb" == "0" ]]; then
        echo -e "  ${C_CYAN}Bandwidth Limit:${C_RESET}  ${C_GREEN}Unlimited${C_RESET}"
        echo -e "  ${C_CYAN}Status:${C_RESET}           ${C_GREEN}No quota restrictions${C_RESET}"
    else
        local quota_bytes; quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
        local percentage; percentage=$(awk "BEGIN {printf \"%.1f\", ($used_bytes / $quota_bytes) * 100}")
        local remaining_bytes; remaining_bytes=$((quota_bytes - used_bytes))
        if [[ "$remaining_bytes" -lt 0 ]]; then remaining_bytes=0; fi
        local remaining_gb; remaining_gb=$(awk "BEGIN {printf \"%.3f\", $remaining_bytes / 1073741824}")
        
        echo -e "  ${C_CYAN}Bandwidth Limit:${C_RESET}  ${C_YELLOW}${bandwidth_gb} GB${C_RESET}"
        echo -e "  ${C_CYAN}Remaining:${C_RESET}        ${C_WHITE}${remaining_gb} GB${C_RESET}"
        echo -e "  ${C_CYAN}Usage:${C_RESET}            ${C_WHITE}${percentage}%${C_RESET}"
        
        # Progress bar
        local bar_width=30
        local filled; filled=$(awk "BEGIN {printf \"%.0f\", ($percentage / 100) * $bar_width}")
        if [[ "$filled" -gt "$bar_width" ]]; then filled=$bar_width; fi
        local empty=$((bar_width - filled))
        local bar_color="$C_GREEN"
        if (( $(awk "BEGIN {print ($percentage > 80)}" ) )); then bar_color="$C_RED"
        elif (( $(awk "BEGIN {print ($percentage > 50)}" ) )); then bar_color="$C_YELLOW"
        fi
        printf "  ${C_CYAN}Progress:${C_RESET}         ${bar_color}["
        for ((i=0; i<filled; i++)); do printf "█"; done
        for ((i=0; i<empty; i++)); do printf "░"; done
        printf "]${C_RESET} ${percentage}%%\n"
        
        if [[ "$used_bytes" -ge "$quota_bytes" ]]; then
            echo -e "\n  ${C_RED}⚠️ USER HAS EXCEEDED BANDWIDTH QUOTA — ACCOUNT LOCKED${C_RESET}"
        fi
    fi
}

bulk_create_users() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 👥 Bulk Create Users ---${C_RESET}"
    
    read -p "👉 Enter username prefix (e.g., 'user'): " prefix
    if [[ -z "$prefix" ]]; then echo -e "\n${C_RED}❌ Prefix cannot be empty.${C_RESET}"; return; fi
    
    read -p "🔢 How many users to create? " count
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]] || [[ "$count" -gt 100 ]]; then
        echo -e "\n${C_RED}❌ Invalid count (1-100).${C_RESET}"; return
    fi
    
    read -p "🗓️ Account duration (in days) [30]: " days
    days=${days:-30}
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    read -p "📶 Connection limit per user [1]: " limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    read -p "📦 Bandwidth limit in GB per user (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    local expire_date
    expire_date=$(date -d "+$days days" +%Y-%m-%d)
    local bw_display="Unlimited"; [[ "$bandwidth_gb" != "0" ]] && bw_display="${bandwidth_gb} GB"
    ensure_firewallfalcon_system_group
    
    echo -e "\n${C_BLUE}⚙️ Creating $count users with prefix '${prefix}'...${C_RESET}\n"
    echo -e "${C_YELLOW}================================================================${C_RESET}"
    printf "${C_BOLD}${C_WHITE}%-20s | %-15s | %-12s${C_RESET}\n" "USERNAME" "PASSWORD" "EXPIRES"
    echo -e "${C_YELLOW}----------------------------------------------------------------${C_RESET}"
    
    local created=0
    for ((i=1; i<=count; i++)); do
        local username="${prefix}${i}"
        if id "$username" &>/dev/null || grep -q "^$username:" "$DB_FILE"; then
            echo -e "${C_RED}  ⚠️ Skipping '$username' — already exists${C_RESET}"
            continue
        fi
        local password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
        useradd -m -s /usr/sbin/nologin "$username"
        usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
        echo "$username:$password" | chpasswd
        chage -E "$expire_date" "$username"
        echo "$username:$password:$expire_date:$limit:$bandwidth_gb" >> "$DB_FILE"
        printf "  ${C_GREEN}%-20s${C_RESET} | ${C_YELLOW}%-15s${C_RESET} | ${C_CYAN}%-12s${C_RESET}\n" "$username" "$password" "$expire_date"
        created=$((created + 1))
    done
    
    echo -e "${C_YELLOW}================================================================${C_RESET}"
    echo -e "\n${C_GREEN}✅ Created $created users. Conn Limit: ${limit} | BW: ${bw_display}${C_RESET}"
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

generate_client_config() {
    local user=$1
    local pass=$2
    
    local host_ip=$(curl -s -4 icanhazip.com)
    local host_domain
    host_domain=$(detect_preferred_host)
    [[ -z "$host_domain" ]] && host_domain="$host_ip"

    echo -e "\n${C_BOLD}${C_PURPLE}--- 📱 Client Connection Configuration ---${C_RESET}"
    echo -e "${C_CYAN}Copy the details below to your clipboard:${C_RESET}\n"

    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "👤 ${C_BOLD}User Details${C_RESET}"
    echo -e "   • Username: ${C_WHITE}$user${C_RESET}"
    echo -e "   • Password: ${C_WHITE}$pass${C_RESET}"
    echo -e "   • Host/IP : ${C_WHITE}$host_domain${C_RESET}"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    
    # 1. SSH Direct
    echo -e "\n🔹 ${C_BOLD}SSH Direct${C_RESET}:"
    echo -e "   • Host: $host_domain"
    echo -e "   • Port: 22"
    echo -e "   • payload: (Standard SSH)"

    # 2. HAProxy edge stack
    if systemctl is-active --quiet haproxy; then
        echo -e "\n🔹 ${C_BOLD}HAProxy Edge Stack${C_RESET}:"
        echo -e "   • Host: $host_domain"
        echo -e "   • Port 80: HTTP payloads / raw SSH"
        echo -e "   • Port 443: TLS / SNI / SSL payloads"
        echo -e "   • Internal handoff: Nginx ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}"
        echo -e "   • SNI (BugHost): $host_domain (or your preferred SNI)"
    elif systemctl is-active --quiet nginx; then
        echo -e "\n🔹 ${C_BOLD}Internal Nginx Proxy${C_RESET}:"
        echo -e "   • Internal only: ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}"
        echo -e "   • Public clients should connect through HAProxy on ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}"
    fi

    # 3. UDP Custom
    if systemctl is-active --quiet udp-custom; then
        echo -e "\n🔹 ${C_BOLD}UDP Custom${C_RESET}:"
        echo -e "   • IP: $host_ip (Must use numeric IP)"
        echo -e "   • Port: 1-65535 (Exclude 53, 5300)"
        echo -e "   • Obfs: (None/Plain)"
    fi

    # 4. DNSTT
    if systemctl is-active --quiet dnstt; then
        if [ -f "$DNSTT_CONFIG_FILE" ]; then
            source "$DNSTT_CONFIG_FILE"
            echo -e "\n🔹 ${C_BOLD}DNSTT (SlowDNS)${C_RESET}:"
            echo -e "   • Nameserver: $TUNNEL_DOMAIN"
            echo -e "   • PubKey: $PUBLIC_KEY"
            echo -e "   • DNS IP: 1.1.1.1 / 8.8.8.8"
        fi
    fi
    
    # 5. ZiVPN
    if systemctl is-active --quiet zivpn; then
        echo -e "\n🔹 ${C_BOLD}ZiVPN${C_RESET}:"
        echo -e "   • UDP Port: 5667"
        echo -e "   • Forwarded Ports: 6000-19999"
    fi
    
    echo -e "${C_YELLOW}========================================${C_RESET}"
    press_enter
}

client_config_menu() {
    _select_user_interface "--- 📱 Generate Client Config ---"
    local u=$SELECTED_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi
    
    # We need to find the password. It's in the DB.
    local pass=$(grep "^$u:" "$DB_FILE" | cut -d: -f2)
    generate_client_config "$u" "$pass"
}

format_rate_from_kbps() {
    local kbps=${1:-0}
    if (( kbps >= 1024 )); then
        printf "%d.%02d MB/s" $((kbps / 1024)) $((((kbps % 1024) * 100) / 1024))
    else
        printf "%d KB/s" "$kbps"
    fi
}

# Lightweight Bash Monitor (No vnStat required)
simple_live_monitor() {
    local iface=$1
    local rx_file="/sys/class/net/$iface/statistics/rx_bytes"
    local tx_file="/sys/class/net/$iface/statistics/tx_bytes"
    local interval=2
    local stop_monitor=0
    local rx1 tx1 rx2 tx2 rx_diff tx_diff rx_kbs tx_kbs rx_fmt tx_fmt

    if [[ -z "$iface" || ! -r "$rx_file" || ! -r "$tx_file" ]]; then
        echo -e "\n${C_RED}❌ Could not read interface statistics for '${iface:-unknown}'.${C_RESET}"
        return
    fi

    echo -e "\n${C_BLUE}⚡ Starting Lightweight Traffic Monitor for $iface...${C_RESET}"
    echo -e "${C_DIM}Press [Ctrl+C] to stop.${C_RESET}\n"

    read -r rx1 < "$rx_file"
    read -r tx1 < "$tx_file"

    printf "%-15s | %-15s\n" "⬇️ Download" "⬆️ Upload"
    echo "-----------------------------------"

    trap 'stop_monitor=1' INT TERM
    while (( ! stop_monitor )); do
        sleep "$interval"
        read -r rx2 < "$rx_file" || break
        read -r tx2 < "$tx_file" || break

        rx_diff=$((rx2 - rx1))
        tx_diff=$((tx2 - tx1))
        (( rx_diff < 0 )) && rx_diff=0
        (( tx_diff < 0 )) && tx_diff=0

        rx_kbs=$((rx_diff / 1024 / interval))
        tx_kbs=$((tx_diff / 1024 / interval))
        rx_fmt=$(format_rate_from_kbps "$rx_kbs")
        tx_fmt=$(format_rate_from_kbps "$tx_kbs")

        printf "\r%-15s | %-15s" "$rx_fmt" "$tx_fmt"

        rx1=$rx2
        tx1=$tx2
    done
    trap - INT TERM
    echo
}

traffic_monitor_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📈 Network Traffic Monitor ---${C_RESET}"
    
    # Find active interface
    local iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    
    echo -e "\nInterface: ${C_CYAN}${iface}${C_RESET}"
    
    echo -e "\n${C_BOLD}Select a monitoring option:${C_RESET}\n"
    printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "⚡ Live Monitor ${C_DIM}(Lightweight, No Install)${C_RESET}"
    printf "  ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "📊 View Total Traffic Since Boot"
    printf "  ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "📅 Daily/Monthly Logs ${C_DIM}(Requires vnStat)${C_RESET}"
    
    echo -e "\n  ${C_WARN}[ 0]${C_RESET} ↩️ Return"
    echo
    read -p "👉 Enter choice: " t_choice
    case $t_choice in
        1) 
           simple_live_monitor "$iface"
           ;;
        2)
            local rx_total=$(cat /sys/class/net/$iface/statistics/rx_bytes)
            local tx_total=$(cat /sys/class/net/$iface/statistics/tx_bytes)
            local rx_mb=$((rx_total / 1024 / 1024))
            local tx_mb=$((tx_total / 1024 / 1024))
            echo -e "\n${C_BLUE}📊 Total Traffic (Since Boot):${C_RESET}"
            echo -e "   ⬇️ Download: ${C_WHITE}${rx_mb} MB${C_RESET}"
            echo -e "   ⬆️ Upload:   ${C_WHITE}${tx_mb} MB${C_RESET}"
            press_enter
            ;;
        3) 
           # vnStat Logic
           if ! command -v vnstat &> /dev/null; then
               echo -e "\n${C_YELLOW}⚠️ vnStat is not installed.${C_RESET}"
               echo -e "   This tool provides persistent history (Daily/Monthly reports)."
               echo -e "   It is lightweight but requires installation."
               read -p "👉 Install vnStat now? (y/n): " confirm
               if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    echo -e "\n${C_BLUE}📦 Installing vnStat...${C_RESET}"
                    apt-get update >/dev/null 2>&1
                    apt-get install -y vnstat >/dev/null 2>&1
                    systemctl enable vnstat >/dev/null 2>&1
                    systemctl restart vnstat >/dev/null 2>&1
                    local default_iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
                    vnstat --add -i "$default_iface" >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ Installed.${C_RESET}"
                    sleep 1
               else
                    return
               fi
           fi
           echo
           vnstat -i "$iface"
           echo -e "\n${C_DIM}Run 'vnstat -d' or 'vnstat -m' manually for specific views.${C_RESET}"
           press_enter
           ;;
        *) return ;;
    esac
}

torrent_block_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚫 Torrent Blocking (Anti-Torrent) ---${C_RESET}"
    
    # Check status
    local torrent_status="${C_STATUS_I}Disabled${C_RESET}"
    if iptables -L FORWARD | grep -q "ipp2p"; then
         torrent_status="${C_STATUS_A}Enabled${C_RESET}"
    elif iptables -L OUTPUT | grep -q "BitTorrent"; then
         # Fallback check for string matching
         torrent_status="${C_STATUS_A}Enabled${C_RESET}"
    fi
    
    echo -e "\n${C_WHITE}Current Status: ${torrent_status}${C_RESET}"
    echo -e "${C_DIM}This feature uses iptables string matching to block common torrent keywords.${C_RESET}"
    
    echo -e "\n${C_BOLD}Select an action:${C_RESET}\n"
    printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "🔒 Enable Torrent Blocking"
    printf "  ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "🔓 Disable Torrent Blocking"
    echo -e "\n  ${C_WARN}[ 0]${C_RESET} ↩️ Return"
    echo
    read -p "👉 Enter choice: " b_choice
    
    case $b_choice in
        1)
            echo -e "\n${C_BLUE}🛡️ Applying Anti-Torrent rules...${C_RESET}"
            # Clean old rules first to avoid duplicates
            _flush_torrent_rules
            
            # Block Common Torrent Ports/Keywords
            # String matching using iptables extension
            iptables -A FORWARD -m string --string "BitTorrent" --algo bm -j DROP
            iptables -A FORWARD -m string --string "BitTorrent protocol" --algo bm -j DROP
            iptables -A FORWARD -m string --string "peer_id=" --algo bm -j DROP
            iptables -A FORWARD -m string --string ".torrent" --algo bm -j DROP
            iptables -A FORWARD -m string --string "announce.php?passkey=" --algo bm -j DROP
            iptables -A FORWARD -m string --string "torrent" --algo bm -j DROP
            iptables -A FORWARD -m string --string "info_hash" --algo bm -j DROP
            iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP
            iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP
            
            # Same for OUTPUT to be safe
            iptables -A OUTPUT -m string --string "BitTorrent" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "BitTorrent protocol" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "peer_id=" --algo bm -j DROP
            iptables -A OUTPUT -m string --string ".torrent" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "announce.php?passkey=" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "torrent" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "info_hash" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "get_peers" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "find_node" --algo bm -j DROP
            
            # Attempt to save if iptables-persistent exists
            if dpkg -s iptables-persistent &>/dev/null; then
                netfilter-persistent save &>/dev/null
            fi
            
            echo -e "${C_GREEN}✅ Torrent Blocking Enabled.${C_RESET}"
            press_enter
            ;;
        2)
            echo -e "\n${C_BLUE}🔓 Removing Anti-Torrent rules...${C_RESET}"
            _flush_torrent_rules
            if dpkg -s iptables-persistent &>/dev/null; then
                netfilter-persistent save &>/dev/null
            fi
            echo -e "${C_GREEN}✅ Torrent Blocking Disabled.${C_RESET}"
            press_enter
            ;;
        *) return ;;
    esac
}

_flush_torrent_rules() {
    # Helper to remove rules containing specific strings
    # This is a bit brute-force but effective for this script's scope
    iptables -D FORWARD -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "BitTorrent protocol" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "peer_id=" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string ".torrent" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "announce.php?passkey=" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "torrent" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "info_hash" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "get_peers" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "find_node" --algo bm -j DROP 2>/dev/null

    iptables -D OUTPUT -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "BitTorrent protocol" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "peer_id=" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string ".torrent" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "announce.php?passkey=" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "torrent" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "info_hash" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "get_peers" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "find_node" --algo bm -j DROP 2>/dev/null
}

ssh_banner_menu() {
    while true; do
        show_banner
        local banner_mode
        local banner_status
        banner_mode=$(get_ssh_banner_mode)
        case "$banner_mode" in
            dynamic) banner_status="${C_STATUS_A}Dynamic${C_RESET}" ;;
            static) banner_status="${C_STATUS_A}Static${C_RESET}" ;;
            *) banner_status="${C_STATUS_I}Disabled${C_RESET}" ;;
        esac

        echo -e "\n   ${C_TITLE}═════════════════[ ${C_BOLD}🎨 SSH BANNER MODE: ${banner_status} ${C_RESET}${C_TITLE}]═════════════════${C_RESET}"
        echo -e "${C_DIM}Static mode uses 'Banner $SSH_BANNER_FILE'. Dynamic mode shows per-user account info.${C_RESET}"
        printf "     ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "✨ Enable Dynamic Account Banner"
        printf "     ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "📋 Paste or Replace Static Banner"
        printf "     ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "👁️ View Current Static Banner"
        printf "     ${C_CHOICE}[ 4]${C_RESET} %-40s\n" "📝 Preview Dynamic Banner"
        printf "     ${C_DANGER}[ 5]${C_RESET} %-40s\n" "🗑️ Disable All SSH Banners"
        echo -e "   ${C_DIM}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${C_RESET}"
        echo -e "     ${C_WARN}[ 0]${C_RESET} ↩️ Return to Main Menu"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice; then
            echo
            return
        fi
        case $choice in
            1)
                if setup_ssh_login_info; then
                    echo -e "\n${C_GREEN}✅ Dynamic account banner enabled.${C_RESET}"
                    echo -e "${C_DIM}Users will now see their account info banner instead of the static banner.${C_RESET}"
                fi
                press_enter
                ;;
            2) set_ssh_banner_paste ;;
            3) view_ssh_banner ;;
            4) preview_dynamic_ssh_banner ;;
            5) remove_ssh_banner ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" && sleep 1 ;;
        esac
    done
}

auto_reboot_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Auto-Reboot Management ---${C_RESET}"
    
    # Check status
    local cron_check=$(crontab -l 2>/dev/null | grep "systemctl reboot")
    local status="${C_STATUS_I}Disabled${C_RESET}"
    if [[ -n "$cron_check" ]]; then
        status="${C_STATUS_A}Active (Midnight)${C_RESET}"
    fi
    
    echo -e "\n${C_WHITE}Current Status: ${status}${C_RESET}"
    
    echo -e "\n${C_BOLD}Select an action:${C_RESET}\n"
    printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "🕐 Enable Daily Reboot (00:00 midnight)"
    printf "  ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "❌ Disable Auto-Reboot"
    echo -e "\n  ${C_WARN}[ 0]${C_RESET} ↩️ Return"
    echo
    read -p "👉 Enter choice: " r_choice
    
    case $r_choice in
        1)
            # Remove existing to prevent duplicates
            (crontab -l 2>/dev/null | grep -v "systemctl reboot") | crontab -
            # Add new job
            (crontab -l 2>/dev/null; echo "0 0 * * * systemctl reboot") | crontab -
            echo -e "\n${C_GREEN}✅ Auto-reboot scheduled for every day at 00:00.${C_RESET}"
            press_enter
            ;;
        2)
            (crontab -l 2>/dev/null | grep -v "systemctl reboot") | crontab -
            echo -e "\n${C_GREEN}✅ Auto-reboot disabled.${C_RESET}"
            press_enter
            ;;
        *) return ;;
    esac
}



# ─────────────────────────────────────────────
# TELEGRAM NOTIFICATIONS
# ─────────────────────────────────────────────

tg_load_config() {
    TG_BOT_TOKEN=""
    TG_CHAT_ID=""
    TG_ENABLED=false
    if [[ -f "$TELEGRAM_CONFIG_FILE" ]]; then
        source "$TELEGRAM_CONFIG_FILE"
        [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]] && TG_ENABLED=true
    fi
}

tg_send() {
    local msg="$1"
    tg_load_config
    [[ "$TG_ENABLED" != true ]] && return 0
    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)
    local full_msg="🖥️ *${hostname}*
${msg}"
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"         -d chat_id="${TG_CHAT_ID}"         -d parse_mode="Markdown"         --data-urlencode "text=${full_msg}"         -o /dev/null --max-time 8 &
}

tg_test_message() {
    tg_load_config
    [[ "$TG_ENABLED" != true ]] && echo -e "${C_RED}❌ Telegram nie jest skonfigurowany.${C_RESET}" && return 1
    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)
    local msg="✅ Połączenie działa!

🖥️ Serwer: *${hostname}*
📅 Czas: $(date '+%d-%m-%Y %H:%M:%S')
👥 Użytkownicy: $(grep -c . "$DB_FILE" 2>/dev/null || echo 0)
🔗 Sesje online: ${SSH_SESSION_TOTAL}"
    local response
    response=$(curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"         -d chat_id="${TG_CHAT_ID}"         -d parse_mode="Markdown"         --data-urlencode "text=${msg}"         --max-time 10)
    if echo "$response" | grep -q '"ok":true'; then
        echo -e "${C_GREEN}✅ Wiadomość testowa wysłana pomyślnie!${C_RESET}"
    else
        echo -e "${C_RED}❌ Błąd wysyłania. Sprawdź token i chat ID.${C_RESET}"
        echo -e "${C_DIM}Odpowiedź API: $response${C_RESET}"
    fi
}

telegram_menu() {
    while true; do
        clear; show_banner
        tg_load_config

        local tg_status
        if [[ "$TG_ENABLED" == true ]]; then
            tg_status="${C_GREEN}✅ Aktywny${C_RESET}"
        else
            tg_status="${C_RED}❌ Nieaktywny${C_RESET}"
        fi

        echo -e "  ${C_BOLD}${C_WHITE}📨 TELEGRAM POWIADOMIENIA${C_RESET}  —  Status: ${tg_status}"
        local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
        echo -e "$SEP"

        if [[ "$TG_ENABLED" == true ]]; then
            echo -e "  ${C_DIM}Token : ${TG_BOT_TOKEN:0:10}...${C_RESET}"
            echo -e "  ${C_DIM}Chat  : ${TG_CHAT_ID}${C_RESET}"
            echo -e "$SEP"
        fi

        printf "  ${C_CHOICE}[ 1]${C_RESET}  %-2s %s
" "⚙️ " "Skonfiguruj bota (token + chat ID)"
        printf "  ${C_CHOICE}[ 2]${C_RESET}  %-2s %s
" "📨" "Wyślij wiadomość testową"
        printf "  ${C_CHOICE}[ 3]${C_RESET}  %-2s %s
" "🔔" "Zarządzaj alertami"
        if [[ "$TG_ENABLED" == true ]]; then
            printf "  ${C_DANGER}[ 4]${C_RESET}  %-2s %s
" "🗑️ " "Usuń konfigurację"
        fi
        echo -e "$SEP"
        printf "  ${C_WARN}[ 0]${C_RESET}  %-2s %s
" "↩️ " "Powrót"
        echo

        read -r -p "$(echo -e ${C_PROMPT}"  👉 Wybierz opcję: "${C_RESET})" choice
        case $choice in
            1) _tg_setup_bot ;;
            2) tg_test_message; press_enter ;;
            3) _tg_alerts_menu ;;
            4) [[ "$TG_ENABLED" == true ]] && _tg_remove_config ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

_tg_setup_bot() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}⚙️  KONFIGURACJA BOTA TELEGRAM${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo -e "$SEP"
    echo -e "  ${C_DIM}Jak uzyskać token:${C_RESET}"
    echo -e "  ${C_DIM}1. Napisz do @BotFather na Telegramie${C_RESET}"
    echo -e "  ${C_DIM}2. Wyślij /newbot i postępuj zgodnie z instrukcjami${C_RESET}"
    echo -e "  ${C_DIM}3. Skopiuj token (format: 123456789:ABCdef...)${C_RESET}"
    echo -e "$SEP"
    echo -e "  ${C_DIM}Jak uzyskać Chat ID:${C_RESET}"
    echo -e "  ${C_DIM}1. Napisz cokolwiek do swojego bota${C_RESET}"
    echo -e "  ${C_DIM}2. Otwórz: https://api.telegram.org/bot<TOKEN>/getUpdates${C_RESET}"
    echo -e "  ${C_DIM}3. Znajdź pole "id" w sekcji "chat"${C_RESET}"
    echo -e "$SEP"
    echo

    local token chat_id
    read -r -p "$(echo -e "  ${C_PROMPT}🤖 Wklej token bota: ${C_RESET}")" token
    if [[ -z "$token" ]]; then
        echo -e "
  ${C_YELLOW}❌ Anulowano.${C_RESET}"; press_enter; return
    fi
    if ! [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        echo -e "
  ${C_RED}❌ Nieprawidłowy format tokenu.${C_RESET}"; press_enter; return
    fi

    read -r -p "$(echo -e "  ${C_PROMPT}💬 Wklej Chat ID: ${C_RESET}")" chat_id
    if [[ -z "$chat_id" ]]; then
        echo -e "
  ${C_YELLOW}❌ Anulowano.${C_RESET}"; press_enter; return
    fi
    if ! [[ "$chat_id" =~ ^-?[0-9]+$ ]]; then
        echo -e "
  ${C_RED}❌ Chat ID musi być liczbą (może być ujemna dla grup).${C_RESET}"; press_enter; return
    fi

    echo -e "
  ${C_BLUE}🔄 Weryfikuję połączenie...${C_RESET}"
    local test_resp
    test_resp=$(curl -s "https://api.telegram.org/bot${token}/getMe" --max-time 10)
    if ! echo "$test_resp" | grep -q '"ok":true'; then
        echo -e "  ${C_RED}❌ Nieprawidłowy token — bot nie odpowiada.${C_RESET}"
        echo -e "  ${C_DIM}Odpowiedź: $test_resp${C_RESET}"
        press_enter; return
    fi
    local bot_name
    bot_name=$(echo "$test_resp" | grep -oP '"username":"\K[^"]+' || echo "unknown")
    echo -e "  ${C_GREEN}✅ Bot znaleziony: @${bot_name}${C_RESET}"

    # Load existing alerts config if present, preserve it
    local tg_alert_ban tg_alert_expiry tg_alert_expiry_days tg_alert_reboot tg_alert_high_load
    tg_load_config
    tg_alert_ban="${tg_alert_ban:-true}"
    tg_alert_expiry="${tg_alert_expiry:-true}"
    tg_alert_expiry_days="${tg_alert_expiry_days:-3}"
    tg_alert_reboot="${tg_alert_reboot:-true}"
    tg_alert_high_load="${tg_alert_high_load:-false}"

    mkdir -p "$DB_DIR"
    cat > "$TELEGRAM_CONFIG_FILE" << EOF
TG_BOT_TOKEN="${token}"
TG_CHAT_ID="${chat_id}"
tg_alert_ban="${tg_alert_ban}"
tg_alert_expiry="${tg_alert_expiry}"
tg_alert_expiry_days="${tg_alert_expiry_days}"
tg_alert_reboot="${tg_alert_reboot}"
tg_alert_high_load="${tg_alert_high_load}"
EOF
    chmod 600 "$TELEGRAM_CONFIG_FILE"
    echo -e "  ${C_GREEN}✅ Konfiguracja zapisana.${C_RESET}"

    _tg_install_cron
    press_enter
}

_tg_remove_config() {
    read -r -p "$(echo -e "  ${C_WARN}❓ Na pewno usunąć konfigurację Telegrama? (t/n): ${C_RESET}")" confirm
    if [[ "$confirm" == "t" || "$confirm" == "T" ]]; then
        rm -f "$TELEGRAM_CONFIG_FILE"
        _tg_remove_cron
        echo -e "  ${C_GREEN}✅ Konfiguracja usunięta.${C_RESET}"
        press_enter
    fi
}

_tg_alerts_menu() {
    tg_load_config
    if [[ "$TG_ENABLED" != true ]]; then
        echo -e "
  ${C_RED}❌ Najpierw skonfiguruj bota (opcja 1).${C_RESET}"
        press_enter; return
    fi

    # Load alert settings
    local tg_alert_ban tg_alert_expiry tg_alert_expiry_days tg_alert_reboot tg_alert_high_load
    [[ -f "$TELEGRAM_CONFIG_FILE" ]] && source "$TELEGRAM_CONFIG_FILE"
    tg_alert_ban="${tg_alert_ban:-true}"
    tg_alert_expiry="${tg_alert_expiry:-true}"
    tg_alert_expiry_days="${tg_alert_expiry_days:-3}"
    tg_alert_reboot="${tg_alert_reboot:-true}"
    tg_alert_high_load="${tg_alert_high_load:-false}"

    _bool_label() { [[ "$1" == "true" ]] && echo "${C_GREEN}[ON]${C_RESET}" || echo "${C_RED}[OFF]${C_RESET}"; }

    while true; do
        clear; show_banner
        echo -e "  ${C_BOLD}${C_WHITE}🔔 ZARZĄDZANIE ALERTAMI${C_RESET}"
        local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_CHOICE}[ 1]${C_RESET}  🚫 Ban za sesje          %s
" "$(_bool_label $tg_alert_ban)"
        printf "  ${C_CHOICE}[ 2]${C_RESET}  🗓️  Wygasające konta       %s  ${C_DIM}(${tg_alert_expiry_days} dni przed)${C_RESET}
" "$(_bool_label $tg_alert_expiry)"
        printf "  ${C_CHOICE}[ 3]${C_RESET}  🔄 Restart serwera       %s
" "$(_bool_label $tg_alert_reboot)"
        printf "  ${C_CHOICE}[ 4]${C_RESET}  🔥 Wysokie obciążenie    %s
" "$(_bool_label $tg_alert_high_load)"
        echo -e "$SEP"
        printf "  ${C_WARN}[ 0]${C_RESET}  ↩️  Powrót
"
        echo

        read -r -p "$(echo -e ${C_PROMPT}"  👉 Wybierz opcję: "${C_RESET})" ch
        case $ch in
            1) [[ "$tg_alert_ban" == "true" ]] && tg_alert_ban="false" || tg_alert_ban="true" ;;
            2)
                if [[ "$tg_alert_expiry" == "true" ]]; then
                    tg_alert_expiry="false"
                else
                    tg_alert_expiry="true"
                    read -r -p "  Ile dni przed wygaśnięciem? [${tg_alert_expiry_days}]: " nd
                    [[ "$nd" =~ ^[0-9]+$ ]] && tg_alert_expiry_days="$nd"
                fi
                ;;
            3) [[ "$tg_alert_reboot" == "true" ]] && tg_alert_reboot="false" || tg_alert_reboot="true" ;;
            4) [[ "$tg_alert_high_load" == "true" ]] && tg_alert_high_load="false" || tg_alert_high_load="true" ;;
            0) break ;;
            *) invalid_option; continue ;;
        esac

        # Save updated alerts
        cat > "$TELEGRAM_CONFIG_FILE" << EOF
TG_BOT_TOKEN="${TG_BOT_TOKEN}"
TG_CHAT_ID="${TG_CHAT_ID}"
tg_alert_ban="${tg_alert_ban}"
tg_alert_expiry="${tg_alert_expiry}"
tg_alert_expiry_days="${tg_alert_expiry_days}"
tg_alert_reboot="${tg_alert_reboot}"
tg_alert_high_load="${tg_alert_high_load}"
EOF
        chmod 600 "$TELEGRAM_CONFIG_FILE"
        _tg_install_cron
    done
}

_tg_install_cron() {
    local cron_script="/usr/local/bin/firewallfalcon-tg-monitor.sh"
    cat > "$cron_script" << 'TGEOF'
#!/bin/bash
# FirewallFalcon Telegram Monitor
DB_FILE="/etc/firewallfalcon/users.db"
TG_CONF="/etc/firewallfalcon/telegram.conf"
[[ -f "$TG_CONF" ]] || exit 0
source "$TG_CONF"
[[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]] || exit 0

_send() {
    local msg="$1"
    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"         -d chat_id="${TG_CHAT_ID}"         -d parse_mode="Markdown"         --data-urlencode "text=🖥️ *${hostname}*
${msg}" -o /dev/null --max-time 8
}

# Check reboot alert (marker file)
if [[ "${tg_alert_reboot}" == "true" ]]; then
    marker="/run/ff_tg_boot_sent"
    if [[ ! -f "$marker" ]]; then
        touch "$marker"
        uptime_str=$(uptime -p 2>/dev/null | sed 's/up //' || echo "nieznany")
        _send "🔄 *Serwer uruchomiony ponownie*
⏱️ Uptime: ${uptime_str}"
    fi
fi

# Check expiring accounts
if [[ "${tg_alert_expiry}" == "true" && -s "$DB_FILE" ]]; then
    days_warn="${tg_alert_expiry_days:-3}"
    warn_ts=$(( $(date +%s) + days_warn * 86400 ))
    current_ts=$(date +%s)
    expiry_msg=""
    while IFS=: read -r user pass expiry _rest; do
        [[ -z "$user" || "$user" == \#* || -z "$expiry" || "$expiry" == "Never" ]] && continue
        exp_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
        [[ "$exp_ts" -le 0 ]] && continue
        if (( exp_ts > current_ts && exp_ts <= warn_ts )); then
            days_left=$(( (exp_ts - current_ts) / 86400 ))
            expiry_msg+="  • ${user} — ${days_left} dni
"
        fi
    done < "$DB_FILE"
    if [[ -n "$expiry_msg" ]]; then
        # Throttle: send once per day per set of users
        hash=$(echo "$expiry_msg" | md5sum | cut -c1-8)
        marker="/run/ff_tg_expiry_${hash}"
        if [[ ! -f "$marker" ]]; then
            touch "$marker"
            _send "🗓️ *Wygasające konta (≤${days_warn} dni):*
$(echo -e "$expiry_msg")"
        fi
    fi
fi

# Check high load
if [[ "${tg_alert_high_load}" == "true" ]]; then
    load=$(awk '{print $1}' /proc/loadavg)
    cpus=$(nproc)
    threshold=$(awk "BEGIN {printf "%.1f", $cpus * 0.9}")
    if awk "BEGIN {exit !($load > $threshold)}"; then
        marker="/run/ff_tg_load_sent"
        if [[ ! -f "$marker" ]]; then
            touch "$marker"
            _send "🔥 *Wysokie obciążenie serwera!*
📊 Load: ${load} (próg: ${threshold})
💻 CPU: ${cpus} rdzeni"
        fi
    else
        rm -f "/run/ff_tg_load_sent" 2>/dev/null
    fi
fi
TGEOF
    chmod +x "$cron_script"

    # Install cron every 5 minutes
    local cron_line="*/5 * * * * $cron_script"
    if ! crontab -l 2>/dev/null | grep -Fq "$cron_script"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    fi
}

_tg_remove_cron() {
    local cron_script="/usr/local/bin/firewallfalcon-tg-monitor.sh"
    (crontab -l 2>/dev/null | grep -Fv "$cron_script") | crontab -
    rm -f "$cron_script" 2>/dev/null
}

# ─────────────────────────────────────────────
# FAIL2BAN
# ─────────────────────────────────────────────

fail2ban_menu() {
    while true; do
        clear; show_banner

        local f2b_installed=false
        local f2b_active=false
        local f2b_ff_enabled=false
        local f2b_status_label="${C_RED}Niezainstalowany${C_RESET}"

        command -v fail2ban-client &>/dev/null && f2b_installed=true
        if $f2b_installed; then
            systemctl is-active --quiet fail2ban && f2b_active=true
            if $f2b_active; then
                f2b_status_label="${C_GREEN}Aktywny${C_RESET}"
            else
                f2b_status_label="${C_YELLOW}Zainstalowany / Zatrzymany${C_RESET}"
            fi
            [[ -f "$FAIL2BAN_FF_JAIL" ]] && f2b_ff_enabled=true
        fi

        local banned_count="—"
        local ff_banned_count="—"
        if $f2b_active; then
            banned_count=$(fail2ban-client status 2>/dev/null | grep -oP 'Number of jail:\s*\K\d+' || echo "?")
            if $f2b_ff_enabled; then
                ff_banned_count=$(fail2ban-client status firewallfalcon-ssh 2>/dev/null                     | grep -oP 'Currently banned:\s*\K\d+' || echo "0")
            fi
        fi

        echo -e "  ${C_BOLD}${C_WHITE}🛡️  FAIL2BAN — OCHRONA PRZED BRUTEFORCE${C_RESET}"
        local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
        echo -e "$SEP"
        echo -e "  Status:          ${f2b_status_label}"
        if $f2b_active; then
            echo -e "  Aktywne jails:   ${C_WHITE}${banned_count}${C_RESET}"
            if $f2b_ff_enabled; then
                echo -e "  Aktualnie zbanowanych (SSH): ${C_RED}${ff_banned_count}${C_RESET}"
            fi
        fi
        echo -e "$SEP"

        if ! $f2b_installed; then
            printf "  ${C_CHOICE}[ 1]${C_RESET}  %-2s %s
" "📦" "Zainstaluj Fail2Ban"
        else
            printf "  ${C_CHOICE}[ 2]${C_RESET}  %-2s %s
" "⚙️ " "Skonfiguruj ochronę SSH (FF jail)"
            printf "  ${C_CHOICE}[ 3]${C_RESET}  %-2s %s
" "📋" "Pokaż zbanowane IP"
            printf "  ${C_CHOICE}[ 4]${C_RESET}  %-2s %s
" "🔓" "Odbanuj IP"
            printf "  ${C_CHOICE}[ 5]${C_RESET}  %-2s %s
" "📊" "Status wszystkich jail"
            if $f2b_active; then
                printf "  ${C_DANGER}[ 6]${C_RESET}  %-2s %s
" "⏹️ " "Zatrzymaj Fail2Ban"
            else
                printf "  ${C_CHOICE}[ 6]${C_RESET}  %-2s %s
" "▶️ " "Uruchom Fail2Ban"
            fi
            printf "  ${C_DANGER}[ 9]${C_RESET}  %-2s %s
" "🗑️ " "Odinstaluj Fail2Ban"
        fi
        echo -e "$SEP"
        printf "  ${C_WARN}[ 0]${C_RESET}  %-2s %s
" "↩️ " "Powrót"
        echo

        read -r -p "$(echo -e ${C_PROMPT}"  👉 Wybierz opcję: "${C_RESET})" choice
        case $choice in
            1) _f2b_install; press_enter ;;
            2) $f2b_installed && { _f2b_setup_jail; press_enter; } ;;
            3) $f2b_installed && { _f2b_show_banned; press_enter; } ;;
            4) $f2b_installed && { _f2b_unban_ip; press_enter; } ;;
            5) $f2b_installed && { _f2b_full_status; press_enter; } ;;
            6)
                if $f2b_active; then
                    systemctl stop fail2ban && echo -e "  ${C_GREEN}✅ Fail2Ban zatrzymany.${C_RESET}"
                else
                    systemctl start fail2ban && echo -e "  ${C_GREEN}✅ Fail2Ban uruchomiony.${C_RESET}"
                fi
                press_enter ;;
            9) $f2b_installed && { _f2b_uninstall; press_enter; } ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

_f2b_install() {
    echo -e "
  ${C_BLUE}📦 Instaluję Fail2Ban...${C_RESET}"
    apt-get update -qq && apt-get install -y fail2ban || {
        echo -e "  ${C_RED}❌ Błąd instalacji.${C_RESET}"; return 1
    }
    systemctl enable fail2ban &>/dev/null
    systemctl start fail2ban &>/dev/null
    echo -e "  ${C_GREEN}✅ Fail2Ban zainstalowany i uruchomiony.${C_RESET}"
    echo -e "  ${C_DIM}Teraz skonfiguruj ochronę SSH (opcja 2).${C_RESET}"
    _f2b_setup_jail
}

_f2b_setup_jail() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}⚙️  KONFIGURACJA OCHRONY SSH${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo -e "$SEP"

    # Current values if jail exists
    local cur_maxretry=4 cur_findtime=300 cur_bantime=3600
    if [[ -f "$FAIL2BAN_FF_JAIL" ]]; then
        cur_maxretry=$(grep -oP 'maxretry\s*=\s*\K\d+' "$FAIL2BAN_FF_JAIL" 2>/dev/null || echo 4)
        cur_findtime=$(grep -oP 'findtime\s*=\s*\K\d+' "$FAIL2BAN_FF_JAIL" 2>/dev/null || echo 300)
        cur_bantime=$(grep -oP 'bantime\s*=\s*\K\d+' "$FAIL2BAN_FF_JAIL" 2>/dev/null || echo 3600)
    fi

    echo -e "  ${C_DIM}Parametry ochrony:${C_RESET}"
    echo

    local maxretry findtime bantime
    read -r -p "  Maks. prób logowania przed banem [${cur_maxretry}]: " maxretry
    maxretry=${maxretry:-$cur_maxretry}
    if ! [[ "$maxretry" =~ ^[0-9]+$ && "$maxretry" -ge 1 ]]; then
        echo -e "  ${C_RED}❌ Nieprawidłowa wartość.${C_RESET}"; return
    fi

    read -r -p "  Okno czasowe (sekundy) [${cur_findtime}]: " findtime
    findtime=${findtime:-$cur_findtime}
    if ! [[ "$findtime" =~ ^[0-9]+$ && "$findtime" -ge 30 ]]; then
        echo -e "  ${C_RED}❌ Minimum 30 sekund.${C_RESET}"; return
    fi

    read -r -p "  Czas bana (sekundy, -1=permanentny) [${cur_bantime}]: " bantime
    bantime=${bantime:-$cur_bantime}
    if ! [[ "$bantime" =~ ^-?[0-9]+$ ]]; then
        echo -e "  ${C_RED}❌ Nieprawidłowa wartość.${C_RESET}"; return
    fi

    # SSH port detection
    local ssh_port
    ssh_port=$(ss -tlnp | grep sshd | grep -oP ':\K[0-9]+' | head -1)
    ssh_port=${ssh_port:-22}

    # Write filter
    mkdir -p /etc/fail2ban/filter.d
    cat > "$FAIL2BAN_FF_FILTER" << 'FILTEREOF'
[Definition]
failregex = ^.*sshd\[<\d+>\]: Failed \S+ for .* from <HOST>.*$
            ^.*sshd\[<\d+>\]: Invalid user .* from <HOST>.*$
            ^.*sshd\[<\d+>\]: Connection closed by authenticating user .* <HOST>.*\[preauth\]$
ignoreregex =
FILTEREOF

    # Write jail
    mkdir -p /etc/fail2ban/jail.d
    cat > "$FAIL2BAN_FF_JAIL" << EOF
[firewallfalcon-ssh]
enabled  = true
port     = ${ssh_port}
filter   = firewallfalcon-ssh
logpath  = /var/log/auth.log
           /var/log/syslog
maxretry = ${maxretry}
findtime = ${findtime}
bantime  = ${bantime}
action   = iptables-multiport[name=SSH, port="${ssh_port}", protocol=tcp]
EOF

    systemctl restart fail2ban 2>/dev/null
    sleep 2
    if fail2ban-client status firewallfalcon-ssh &>/dev/null; then
        echo -e "
  ${C_GREEN}✅ Jail aktywny! Ochrona SSH włączona.${C_RESET}"
        local bantime_human
        if [[ "$bantime" == "-1" ]]; then
            bantime_human="permanentny"
        else
            bantime_human="${bantime}s ($(( bantime / 60 )) min)"
        fi
        echo -e "  ${C_DIM}Port SSH: ${ssh_port}  •  Próby: ${maxretry}  •  Okno: ${findtime}s  •  Ban: ${bantime_human}${C_RESET}"

        # Send Telegram alert if configured
        tg_load_config
        if [[ "$TG_ENABLED" == true ]]; then
            tg_send "🛡️ *Fail2Ban aktywny*
✅ Ochrona SSH włączona
🔌 Port: ${ssh_port} | Próby: ${maxretry} | Ban: ${bantime}s"
        fi
    else
        echo -e "
  ${C_RED}❌ Błąd aktywacji jail. Sprawdź logi: journalctl -u fail2ban${C_RESET}"
    fi
}

_f2b_show_banned() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}📋 AKTUALNIE ZBANOWANE IP${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo -e "$SEP"

    if ! fail2ban-client status firewallfalcon-ssh &>/dev/null; then
        echo -e "  ${C_YELLOW}ℹ️ Jail firewallfalcon-ssh nie jest aktywny.${C_RESET}"
        return
    fi

    local banned_ips
    banned_ips=$(fail2ban-client status firewallfalcon-ssh 2>/dev/null         | grep "Banned IP list:" | sed 's/.*Banned IP list://' | tr ' ' '
' | grep -v '^$')

    if [[ -z "$banned_ips" ]]; then
        echo -e "  ${C_GREEN}✅ Brak zbanowanych adresów IP.${C_RESET}"
        return
    fi

    local count=0
    while read -r ip; do
        [[ -z "$ip" ]] && continue
        (( count++ ))
        printf "  ${C_RED}%-3d${C_RESET}  ${C_WHITE}%s${C_RESET}
" "$count" "$ip"
    done <<< "$banned_ips"
    echo -e "$SEP"
    echo -e "  ${C_DIM}Łącznie: ${count} zbanowanych IP${C_RESET}"
}

_f2b_unban_ip() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}🔓 ODBANUJ IP${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo -e "$SEP"

    # Show currently banned
    local banned_ips
    banned_ips=$(fail2ban-client status firewallfalcon-ssh 2>/dev/null         | grep "Banned IP list:" | sed 's/.*Banned IP list://' | tr ' ' '
' | grep -v '^$')

    if [[ -z "$banned_ips" ]]; then
        echo -e "  ${C_GREEN}✅ Brak zbanowanych adresów IP.${C_RESET}"
        return
    fi

    local -a ip_arr=()
    local i=0
    while read -r ip; do
        [[ -z "$ip" ]] && continue
        (( i++ ))
        ip_arr+=("$ip")
        printf "  ${C_CHOICE}[%2d]${C_RESET}  %s
" "$i" "$ip"
    done <<< "$banned_ips"
    echo -e "$SEP"
    echo -e "  ${C_WARN}[  0]${C_RESET}  Anuluj"
    echo

    local target_ip
    read -r -p "  Podaj numer lub wpisz IP bezpośrednio: " sel
    if [[ "$sel" == "0" || -z "$sel" ]]; then return; fi

    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#ip_arr[@]} )); then
        target_ip="${ip_arr[$((sel-1))]}"
    else
        target_ip="$sel"
    fi

    if fail2ban-client set firewallfalcon-ssh unbanip "$target_ip" &>/dev/null; then
        echo -e "  ${C_GREEN}✅ IP ${target_ip} zostało odbanowane.${C_RESET}"
    else
        echo -e "  ${C_RED}❌ Nie udało się odbanować ${target_ip}.${C_RESET}"
    fi
}

_f2b_full_status() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}📊 STATUS FAIL2BAN${C_RESET}"
    echo -e "${C_BLUE}  ────────────────────────────────────${C_RESET}"
    fail2ban-client status 2>/dev/null || echo -e "  ${C_RED}❌ Fail2Ban nie odpowiada.${C_RESET}"
    echo
    if fail2ban-client status firewallfalcon-ssh &>/dev/null; then
        echo -e "  ${C_BOLD}${C_WHITE}Szczegóły jail firewallfalcon-ssh:${C_RESET}"
        echo -e "${C_BLUE}  ────────────────────────────────────${C_RESET}"
        fail2ban-client status firewallfalcon-ssh 2>/dev/null
    fi
}

_f2b_uninstall() {
    read -r -p "  ${C_WARN}❓ Na pewno odinstalować Fail2Ban? (t/n): ${C_RESET}" confirm
    if [[ "$confirm" != "t" && "$confirm" != "T" ]]; then
        echo -e "  ${C_YELLOW}❌ Anulowano.${C_RESET}"; return
    fi
    rm -f "$FAIL2BAN_FF_JAIL" "$FAIL2BAN_FF_FILTER" 2>/dev/null
    systemctl stop fail2ban &>/dev/null
    systemctl disable fail2ban &>/dev/null
    apt-get remove -y fail2ban &>/dev/null
    echo -e "  ${C_GREEN}✅ Fail2Ban odinstalowany.${C_RESET}"
}



# ─────────────────────────────────────────────
# CLOUDFLARE WARP
# ─────────────────────────────────────────────

WARP_CONFIG_FILE="$DB_DIR/warp.conf"
WARP_RT_TABLE=51820
WARP_MARK=51820
WARP_IFACE="CloudflareWARP"

warp_load_config() {
    WARP_MODE="proxy"
    WARP_PROXY_PORT=40000
    WARP_ROUTING_ENABLED=false
    [[ -f "$WARP_CONFIG_FILE" ]] && source "$WARP_CONFIG_FILE"
}

warp_is_installed() {
    command -v warp-cli &>/dev/null
}

warp_is_connected() {
    warp-cli status 2>/dev/null | grep -qi "connected"
}

warp_get_status_label() {
    if ! warp_is_installed; then
        echo "${C_RED}Niezainstalowany${C_RESET}"
    elif warp_is_connected; then
        echo "${C_GREEN}Połączony${C_RESET}"
    else
        echo "${C_YELLOW}Rozłączony${C_RESET}"
    fi
}

warp_get_current_ip() {
    curl -s --max-time 6 https://cloudflare.com/cdn-cgi/trace 2>/dev/null \
        | grep "^ip=" | cut -d= -f2
}

warp_menu() {
    while true; do
        clear; show_banner
        warp_load_config

        local status_label
        status_label=$(warp_get_status_label)
        local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"

        echo -e "  ${C_BOLD}${C_WHITE}🌀 CLOUDFLARE WARP${C_RESET}  —  Status: ${status_label}"
        echo -e "$SEP"

        if warp_is_installed; then
            # Show current IP and mode
            local cur_ip
            cur_ip=$(warp_get_current_ip)
            echo -e "  ${C_DIM}Aktualne IP:  ${C_WHITE}${cur_ip:-nieznane}${C_RESET}"
            echo -e "  ${C_DIM}Tryb:         ${C_WHITE}${WARP_MODE}${C_RESET}"
            if [[ "$WARP_MODE" == "proxy" ]]; then
                echo -e "  ${C_DIM}Port SOCKS5:  ${C_WHITE}${WARP_PROXY_PORT}${C_RESET}"
            fi
            local warp_account
            warp_account=$(warp-cli account 2>/dev/null | grep -oP 'Account type:\s*\K\S+' || echo "Free")
            echo -e "  ${C_DIM}Konto:        ${C_WHITE}${warp_account}${C_RESET}"
            echo -e "$SEP"

            if warp_is_connected; then
                printf "  ${C_DANGER}[ 1]${C_RESET}  %-2s %s\n" "🔌" "Rozłącz WARP"
            else
                printf "  ${C_CHOICE}[ 1]${C_RESET}  %-2s %s\n" "🔗" "Połącz WARP"
            fi
            printf "  ${C_CHOICE}[ 2]${C_RESET}  %-2s %s\n" "🔄" "Zmień tryb (proxy / pełny routing)"
            printf "  ${C_CHOICE}[ 3]${C_RESET}  %-2s %s\n" "🌐" "Sprawdź aktualne IP (przed/po)"
            printf "  ${C_CHOICE}[ 4]${C_RESET}  %-2s %s\n" "📊" "Szczegółowy status"
            printf "  ${C_CHOICE}[ 5]${C_RESET}  %-2s %s\n" "🔁" "Obróć IP (reconnect)"
            printf "  ${C_DANGER}[ 9]${C_RESET}  %-2s %s\n" "🗑️ " "Odinstaluj WARP"
        else
            echo -e "$SEP"
            printf "  ${C_CHOICE}[ 1]${C_RESET}  %-2s %s\n" "📦" "Zainstaluj Cloudflare WARP"
            echo -e "\n  ${C_DIM}WARP pozwala zmienić IP wyjściowe serwera${C_RESET}"
            echo -e "  ${C_DIM}na adres Cloudflare — ukrywa oryginalny IP.${C_RESET}"
        fi

        echo -e "$SEP"
        printf "  ${C_WARN}[ 0]${C_RESET}  %-2s %s\n" "↩️ " "Powrót"
        echo

        read -r -p "$(echo -e ${C_PROMPT}"  👉 Wybierz opcję: "${C_RESET})" choice
        case $choice in
            1)
                if warp_is_installed; then
                    if warp_is_connected; then
                        _warp_disconnect
                    else
                        _warp_connect
                    fi
                else
                    _warp_install
                fi
                press_enter
                ;;
            2) warp_is_installed && { _warp_change_mode; press_enter; } ;;
            3) warp_is_installed && { _warp_check_ip; press_enter; } ;;
            4) warp_is_installed && { _warp_full_status; press_enter; } ;;
            5) warp_is_installed && warp_is_connected && { _warp_rotate_ip; press_enter; } ;;
            9) warp_is_installed && { _warp_uninstall; press_enter; } ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

_warp_install() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}📦 INSTALACJA CLOUDFLARE WARP${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo -e "$SEP"

    # Detect distro
    local distro codename
    distro=$(grep -oP '^ID=\K\S+' /etc/os-release 2>/dev/null | tr -d '"')
    codename=$(lsb_release -cs 2>/dev/null || grep -oP 'VERSION_CODENAME=\K\S+' /etc/os-release | tr -d '"')

    if [[ -z "$codename" ]]; then
        echo -e "  ${C_RED}❌ Nie można wykryć wersji systemu.${C_RESET}"
        return 1
    fi

    echo -e "  ${C_DIM}System: ${distro} ${codename}${C_RESET}"
    echo -e "  ${C_BLUE}🔄 Dodawanie repozytorium Cloudflare...${C_RESET}"

    # Add Cloudflare GPG key
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
        | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "  ${C_RED}❌ Błąd pobierania klucza GPG.${C_RESET}"
        return 1
    fi

    # Add repo
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${codename} main" \
        > /etc/apt/sources.list.d/cloudflare-client.list

    echo -e "  ${C_BLUE}🔄 Aktualizacja pakietów...${C_RESET}"
    apt-get update -qq 2>/dev/null

    echo -e "  ${C_BLUE}🔄 Instalacja cloudflare-warp...${C_RESET}"
    if ! apt-get install -y cloudflare-warp 2>/dev/null; then
        echo -e "  ${C_RED}❌ Błąd instalacji. Sprawdź połączenie internetowe.${C_RESET}"
        return 1
    fi

    # Start warp-svc
    systemctl enable warp-svc &>/dev/null
    systemctl start warp-svc &>/dev/null
    sleep 3

    echo -e "  ${C_BLUE}🔄 Rejestracja klienta WARP...${C_RESET}"
    warp-cli --accept-tos registration new 2>/dev/null
    sleep 2

    # Default: proxy mode (safe for VPS - SSH stays on original IP)
    echo -e "  ${C_BLUE}🔄 Konfiguracja trybu proxy (bezpieczny dla VPS)...${C_RESET}"
    warp-cli tunnel protocol set Userspace 2>/dev/null
    warp-cli proxy enable --port 40000 2>/dev/null

    mkdir -p "$DB_DIR"
    cat > "$WARP_CONFIG_FILE" << EOF
WARP_MODE="proxy"
WARP_PROXY_PORT=40000
WARP_ROUTING_ENABLED=false
EOF

    echo -e "  ${C_BLUE}🔄 Łączenie...${C_RESET}"
    warp-cli connect 2>/dev/null
    sleep 4

    if warp_is_connected; then
        echo -e "\n  ${C_GREEN}✅ WARP zainstalowany i połączony!${C_RESET}"
        echo -e "\n  ${C_BOLD}Tryb: SOCKS5 Proxy na porcie 40000${C_RESET}"
        echo -e "  ${C_DIM}Ruch SSH i serwera NIE zmienia IP — bezpieczne.${C_RESET}"
        echo -e "  ${C_DIM}Aby cały ruch szedł przez WARP, zmień tryb na 'pełny routing'.${C_RESET}"
        local warp_ip
        warp_ip=$(warp_get_current_ip)
        echo -e "\n  ${C_DIM}IP wyjściowe (przez WARP): ${C_WHITE}${warp_ip}${C_RESET}"
    else
        echo -e "\n  ${C_YELLOW}⚠️ WARP zainstalowany ale nie połączony.${C_RESET}"
        echo -e "  ${C_DIM}Spróbuj ręcznie: warp-cli connect${C_RESET}"
    fi
}

_warp_connect() {
    echo -e "\n  ${C_BLUE}🔄 Łączenie z WARP...${C_RESET}"
    warp_load_config

    if [[ "$WARP_MODE" == "full" ]]; then
        _warp_connect_full_routing
        return
    fi

    # Proxy mode - always safe
    warp-cli proxy enable --port "${WARP_PROXY_PORT}" 2>/dev/null
    warp-cli connect 2>/dev/null
    sleep 3

    if warp_is_connected; then
        echo -e "  ${C_GREEN}✅ WARP połączony (proxy SOCKS5 na porcie ${WARP_PROXY_PORT}).${C_RESET}"
        local ip; ip=$(warp_get_current_ip)
        echo -e "  ${C_DIM}IP: ${ip}${C_RESET}"
    else
        echo -e "  ${C_RED}❌ Nie udało się połączyć. Sprawdź: warp-cli status${C_RESET}"
    fi
}

_warp_connect_full_routing() {
    echo -e "  ${C_YELLOW}⚠️ Tryb pełnego routingu — SSH zostanie zabezpieczone przed rozłączeniem.${C_RESET}"

    # Detect current SSH port
    local ssh_port
    ssh_port=$(ss -tlnp | grep sshd | grep -oP ':\K[0-9]+' | head -1)
    ssh_port=${ssh_port:-22}

    # Detect default gateway and interface BEFORE connecting WARP
    local orig_gw orig_iface orig_ip
    orig_gw=$(ip route show default | awk '/default/ {print $3; exit}')
    orig_iface=$(ip route show default | awk '/default/ {print $5; exit}')
    orig_ip=$(ip addr show "$orig_iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)

    if [[ -z "$orig_gw" || -z "$orig_iface" ]]; then
        echo -e "  ${C_RED}❌ Nie można wykryć domyślnej bramy. Przerywam.${C_RESET}"
        return 1
    fi

    echo -e "  ${C_DIM}Brama: ${orig_gw} | Interfejs: ${orig_iface} | IP: ${orig_ip}${C_RESET}"

    # CRITICAL: Keep SSH traffic on original interface using routing rules
    # Rule: packets FROM original IP go via original gateway (table main)
    ip rule add from "${orig_ip}/32" table main priority 100 2>/dev/null || true
    # Rule: SSH incoming connections (established) go back via original route
    ip rule add fwmark "${WARP_MARK}" table "${WARP_RT_TABLE}" priority 200 2>/dev/null || true

    # Mark SSH return traffic to go via original route
    iptables -t mangle -A OUTPUT -p tcp --sport "${ssh_port}" -j MARK --set-mark "${WARP_MARK}" 2>/dev/null || true
    iptables -t mangle -A OUTPUT -p tcp --dport "${ssh_port}" -j MARK --set-mark "${WARP_MARK}" 2>/dev/null || true

    # Add original gateway as fallback table
    ip route add default via "${orig_gw}" dev "${orig_iface}" table "${WARP_RT_TABLE}" 2>/dev/null || true

    # Save original gateway for cleanup
    cat >> "$WARP_CONFIG_FILE" << EOF
WARP_ORIG_GW="${orig_gw}"
WARP_ORIG_IFACE="${orig_iface}"
WARP_ORIG_IP="${orig_ip}"
WARP_SSH_PORT="${ssh_port}"
EOF

    # Now connect WARP
    warp-cli tunnel protocol set Userspace 2>/dev/null
    warp-cli connect 2>/dev/null
    sleep 5

    if ! warp_is_connected; then
        echo -e "  ${C_RED}❌ WARP nie połączył się. Cofam zmiany routingu.${C_RESET}"
        _warp_cleanup_routing
        return 1
    fi

    # Verify SSH is still reachable by checking our own connection
    echo -e "  ${C_GREEN}✅ WARP połączony w trybie pełnego routingu.${C_RESET}"
    local warp_ip; warp_ip=$(warp_get_current_ip)
    echo -e "  ${C_GREEN}🌐 Nowe IP wyjściowe: ${C_WHITE}${warp_ip}${C_RESET}"
    echo -e "  ${C_DIM}SSH nadal działa na oryginalnym IP: ${orig_ip}${C_RESET}"

    # Persist routing rules across reboots
    _warp_install_routing_service
}

_warp_disconnect() {
    echo -e "\n  ${C_BLUE}🔄 Rozłączanie WARP...${C_RESET}"
    warp_load_config
    warp-cli disconnect 2>/dev/null
    sleep 2

    if [[ "$WARP_MODE" == "full" ]]; then
        _warp_cleanup_routing
    fi

    if ! warp_is_connected; then
        echo -e "  ${C_GREEN}✅ WARP rozłączony.${C_RESET}"
        local ip; ip=$(warp_get_current_ip)
        echo -e "  ${C_DIM}Aktualne IP: ${ip}${C_RESET}"
    else
        echo -e "  ${C_RED}❌ Problem z rozłączeniem. Spróbuj: warp-cli disconnect${C_RESET}"
    fi
}

_warp_cleanup_routing() {
    warp_load_config
    local ssh_port="${WARP_SSH_PORT:-22}"
    local orig_ip="${WARP_ORIG_IP}"
    local orig_gw="${WARP_ORIG_GW}"
    local orig_iface="${WARP_ORIG_IFACE}"

    iptables -t mangle -D OUTPUT -p tcp --sport "${ssh_port}" -j MARK --set-mark "${WARP_MARK}" 2>/dev/null || true
    iptables -t mangle -D OUTPUT -p tcp --dport "${ssh_port}" -j MARK --set-mark "${WARP_MARK}" 2>/dev/null || true
    ip rule del from "${orig_ip}/32" table main priority 100 2>/dev/null || true
    ip rule del fwmark "${WARP_MARK}" table "${WARP_RT_TABLE}" priority 200 2>/dev/null || true
    ip route del default table "${WARP_RT_TABLE}" 2>/dev/null || true

    # Remove persistence service
    systemctl stop warp-routing 2>/dev/null
    systemctl disable warp-routing 2>/dev/null
    rm -f /etc/systemd/system/warp-routing.service /usr/local/bin/warp-routing-setup.sh 2>/dev/null
    systemctl daemon-reload 2>/dev/null
}

_warp_install_routing_service() {
    warp_load_config
    local ssh_port="${WARP_SSH_PORT:-22}"
    local orig_ip="${WARP_ORIG_IP}"
    local orig_gw="${WARP_ORIG_GW}"
    local orig_iface="${WARP_ORIG_IFACE}"

    cat > /usr/local/bin/warp-routing-setup.sh << ROUTEOF
#!/bin/bash
# FirewallFalcon WARP routing persistence
MARK=${WARP_MARK}
RT_TABLE=${WARP_RT_TABLE}
SSH_PORT=${ssh_port}
ORIG_IP="${orig_ip}"
ORIG_GW="${orig_gw}"
ORIG_IFACE="${orig_iface}"

# Wait for WARP interface
for i in {1..15}; do
    ip link show CloudflareWARP &>/dev/null && break
    sleep 2
done

ip rule add from "\${ORIG_IP}/32" table main priority 100 2>/dev/null || true
ip rule add fwmark "\${MARK}" table "\${RT_TABLE}" priority 200 2>/dev/null || true
ip route add default via "\${ORIG_GW}" dev "\${ORIG_IFACE}" table "\${RT_TABLE}" 2>/dev/null || true
iptables -t mangle -A OUTPUT -p tcp --sport "\${SSH_PORT}" -j MARK --set-mark "\${MARK}" 2>/dev/null || true
iptables -t mangle -A OUTPUT -p tcp --dport "\${SSH_PORT}" -j MARK --set-mark "\${MARK}" 2>/dev/null || true
ROUTEOF
    chmod +x /usr/local/bin/warp-routing-setup.sh

    cat > /etc/systemd/system/warp-routing.service << SVCEOF
[Unit]
Description=FirewallFalcon WARP Routing Rules
After=network-online.target warp-svc.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/warp-routing-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable warp-routing &>/dev/null
}

_warp_change_mode() {
    clear; show_banner
    warp_load_config
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"

    echo -e "  ${C_BOLD}${C_WHITE}🔄 ZMIANA TRYBU WARP${C_RESET}"
    echo -e "$SEP"
    echo -e "  ${C_DIM}Aktualny tryb: ${C_WHITE}${WARP_MODE}${C_RESET}"
    echo -e "$SEP"
    echo
    printf "  ${C_CHOICE}[ 1]${C_RESET}  🔵 %s\n" "Tryb PROXY (SOCKS5 port 40000)"
    echo -e "  ${C_DIM}       • SSH i serwer zachowują oryginalne IP${C_RESET}"
    echo -e "  ${C_DIM}       • Bezpieczny — nie zerwie połączenia${C_RESET}"
    echo -e "  ${C_DIM}       • Ruch VPN można kierować przez proxy${C_RESET}"
    echo
    printf "  ${C_CHOICE}[ 2]${C_RESET}  🟠 %s\n" "Tryb PEŁNY ROUTING (zmienia IP całego serwera)"
    echo -e "  ${C_DIM}       • Całe wyjście serwera idzie przez Cloudflare${C_RESET}"
    echo -e "  ${C_DIM}       • SSH chronione przez osobne reguły routingu${C_RESET}"
    echo -e "  ${C_DIM}       • Zalecane: zrób backup SSH przed włączeniem${C_RESET}"
    echo
    echo -e "$SEP"
    printf "  ${C_WARN}[ 0]${C_RESET}  ↩️  Anuluj\n"
    echo

    read -r -p "$(echo -e ${C_PROMPT}"  👉 Wybierz tryb: "${C_RESET})" ch
    case $ch in
        1)
            if warp_is_connected && [[ "$WARP_MODE" == "full" ]]; then
                echo -e "  ${C_BLUE}🔄 Przełączam na tryb proxy...${C_RESET}"
                warp-cli disconnect 2>/dev/null
                _warp_cleanup_routing
                sleep 2
            fi
            warp-cli tunnel protocol set Userspace 2>/dev/null
            warp-cli proxy enable --port "${WARP_PROXY_PORT}" 2>/dev/null
            sed -i 's/^WARP_MODE=.*/WARP_MODE="proxy"/' "$WARP_CONFIG_FILE"
            warp-cli connect 2>/dev/null
            sleep 3
            echo -e "  ${C_GREEN}✅ Tryb proxy aktywny (SOCKS5 port ${WARP_PROXY_PORT}).${C_RESET}"
            ;;
        2)
            echo -e "\n  ${C_YELLOW}⚠️ UWAGA: Ten tryb zmienia routing całego serwera.${C_RESET}"
            echo -e "  ${C_YELLOW}   Upewnij się że masz dostęp do konsoli VPS na wypadek problemów.${C_RESET}"
            read -r -p "  Kontynuować? (t/n): " confirm
            if [[ "$confirm" != "t" && "$confirm" != "T" ]]; then
                echo -e "  ${C_YELLOW}❌ Anulowano.${C_RESET}"; return
            fi
            if warp_is_connected; then
                warp-cli disconnect 2>/dev/null
                sleep 2
            fi
            sed -i 's/^WARP_MODE=.*/WARP_MODE="full"/' "$WARP_CONFIG_FILE"
            _warp_connect_full_routing
            ;;
        0) return ;;
        *) invalid_option ;;
    esac
}

_warp_check_ip() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}🌐 SPRAWDZANIE IP${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo -e "$SEP"

    echo -e "  ${C_DIM}Pobieranie informacji...${C_RESET}"

    # Get IP via cloudflare trace
    local cf_data
    cf_data=$(curl -s --max-time 8 https://cloudflare.com/cdn-cgi/trace 2>/dev/null)
    local current_ip warp_status cf_colo
    current_ip=$(echo "$cf_data" | grep "^ip=" | cut -d= -f2)
    warp_status=$(echo "$cf_data" | grep "^warp=" | cut -d= -f2)
    cf_colo=$(echo "$cf_data" | grep "^colo=" | cut -d= -f2)

    # Get IP via ipinfo for geolocation
    local geo_data country city org
    geo_data=$(curl -s --max-time 6 https://ipinfo.io/json 2>/dev/null)
    country=$(echo "$geo_data" | grep -oP '"country":\s*"\K[^"]+' 2>/dev/null)
    city=$(echo "$geo_data" | grep -oP '"city":\s*"\K[^"]+' 2>/dev/null)
    org=$(echo "$geo_data" | grep -oP '"org":\s*"\K[^"]+' 2>/dev/null)

    echo
    printf "  ${C_GRAY}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Aktualne IP:" "${current_ip:-nieznane}"
    printf "  ${C_GRAY}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Kraj:" "${country:-nieznany}"
    printf "  ${C_GRAY}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Miasto:" "${city:-nieznane}"
    printf "  ${C_GRAY}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Operator:" "${org:-nieznany}"

    if [[ "$warp_status" == "on" ]]; then
        printf "  ${C_GRAY}%-18s${C_RESET} ${C_GREEN}%s${C_RESET}\n" "WARP:" "Aktywny ✅"
        printf "  ${C_GRAY}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "CF Datacenter:" "${cf_colo:-nieznany}"
    else
        printf "  ${C_GRAY}%-18s${C_RESET} ${C_RED}%s${C_RESET}\n" "WARP:" "Nieaktywny ❌"
    fi

    echo -e "$SEP"
    echo -e "  ${C_DIM}warp-cli status:${C_RESET}"
    warp-cli status 2>/dev/null | sed 's/^/  /'
}

_warp_full_status() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}📊 SZCZEGÓŁOWY STATUS WARP${C_RESET}"
    echo -e "${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo
    warp-cli status 2>/dev/null | sed 's/^/  /'
    echo
    echo -e "  ${C_DIM}Konto:${C_RESET}"
    warp-cli account 2>/dev/null | sed 's/^/  /'
    echo
    echo -e "  ${C_DIM}Protokół tunelu:${C_RESET}"
    warp-cli tunnel protocol show 2>/dev/null | sed 's/^/  /'
    echo
    echo -e "  ${C_DIM}Interfejs sieciowy:${C_RESET}"
    ip addr show CloudflareWARP 2>/dev/null | sed 's/^/  /' || echo "  (brak interfejsu WARP)"
    echo
    echo -e "  ${C_DIM}Reguły routingu:${C_RESET}"
    ip rule list | grep -E "100:|200:|${WARP_MARK}" | sed 's/^/  /' || echo "  (brak reguł WARP)"
}

_warp_rotate_ip() {
    echo -e "\n  ${C_BLUE}🔁 Obracam IP (reconnect)...${C_RESET}"
    warp_load_config
    warp-cli disconnect 2>/dev/null
    sleep 3
    warp-cli connect 2>/dev/null
    sleep 4
    if warp_is_connected; then
        local new_ip; new_ip=$(warp_get_current_ip)
        echo -e "  ${C_GREEN}✅ Nowe IP: ${C_WHITE}${new_ip}${C_RESET}"
    else
        echo -e "  ${C_RED}❌ Reconnect nie powiódł się.${C_RESET}"
    fi
}

_warp_uninstall() {
    echo -e "\n  ${C_YELLOW}⚠️ To rozłączy WARP i usunie pakiet.${C_RESET}"
    read -r -p "  Na pewno? (t/n): " confirm
    [[ "$confirm" != "t" && "$confirm" != "T" ]] && { echo -e "  ${C_YELLOW}❌ Anulowano.${C_RESET}"; return; }

    echo -e "  ${C_BLUE}🔄 Rozłączam...${C_RESET}"
    warp-cli disconnect 2>/dev/null
    warp-cli registration delete 2>/dev/null
    sleep 2

    warp_load_config
    [[ "$WARP_MODE" == "full" ]] && _warp_cleanup_routing

    echo -e "  ${C_BLUE}🔄 Zatrzymuję serwis...${C_RESET}"
    systemctl stop warp-svc 2>/dev/null
    systemctl disable warp-svc 2>/dev/null

    echo -e "  ${C_BLUE}🔄 Usuwam pakiet...${C_RESET}"
    apt-get remove -y cloudflare-warp 2>/dev/null
    rm -f /etc/apt/sources.list.d/cloudflare-client.list \
          /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
          "$WARP_CONFIG_FILE" 2>/dev/null
    apt-get autoremove -y 2>/dev/null

    echo -e "  ${C_GREEN}✅ WARP odinstalowany.${C_RESET}"
}




# ─────────────────────────────────────────────────────────────
# WireGuard + WARP VPN SERVER
# ─────────────────────────────────────────────────────────────

WG_CLIENTS_DIR="/etc/wireguard/clients"
WG_CONFIG="/etc/wireguard/wg0.conf"
WG_PORT="51820"
WG_SUBNET="10.8.0.0/24"
WG_SERVER_IP="10.8.0.1"
WG_RT_TABLE=200
WG_FWMARK=200
WG_DNS_PRIMARY="1.1.1.1"
WG_DNS_SECONDARY="1.0.0.1"

_wgw_is_wg_installed()   { command -v wg &>/dev/null; }
_wgw_is_warp_installed() { command -v warp-cli &>/dev/null; }
_wgw_is_wg_running()     { systemctl is-active --quiet wg-quick@wg0 2>/dev/null; }
_wgw_is_warp_connected() { warp-cli status 2>/dev/null | grep -qi "connected"; }

_wgw_get_public_ip() {
    curl -s --max-time 6 https://cloudflare.com/cdn-cgi/trace | grep "^ip=" | cut -d= -f2
}

_wgw_get_warp_iface() {
    ip link show 2>/dev/null | grep -oP '^\d+: \K[^:@]+' \
        | grep -i "warp\|CloudflareWARP" | head -1
}

_wgw_detect_wan() {
    ip route show default table main | awk '/default/ {print $5; exit}'
}

_wgw_detect_gw() {
    ip route show default table main | awk '/default/ {print $3; exit}'
}

wgwarp_menu() {
    while true; do
        clear; show_banner

        local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
        local wg_ok=false warp_ok=false warp_conn=false
        _wgw_is_wg_installed   && wg_ok=true
        _wgw_is_warp_installed && warp_ok=true
        _wgw_is_warp_connected && warp_conn=true

        # Status labels
        local wg_label warp_label
        if $wg_ok && _wgw_is_wg_running; then
            wg_label="${C_GREEN}Aktywny ✅${C_RESET}"
        elif $wg_ok; then
            wg_label="${C_YELLOW}Zainstalowany / Zatrzymany${C_RESET}"
        else
            wg_label="${C_RED}Niezainstalowany${C_RESET}"
        fi

        if $warp_conn; then
            warp_label="${C_GREEN}Połączony ✅${C_RESET}"
        elif $warp_ok; then
            warp_label="${C_YELLOW}Zainstalowany / Rozłączony${C_RESET}"
        else
            warp_label="${C_RED}Niezainstalowany${C_RESET}"
        fi

        local client_count=0
        [[ -d "$WG_CLIENTS_DIR" ]] && \
            client_count=$(find "$WG_CLIENTS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)

        echo -e "  ${C_BOLD}${C_WHITE}🔐 WIREGUARD + WARP VPN${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_GRAY}%-18s${C_RESET} %b\n" "WireGuard:" "$wg_label"
        printf "  ${C_GRAY}%-18s${C_RESET} %b\n" "Cloudflare WARP:" "$warp_label"
        printf "  ${C_GRAY}%-18s${C_RESET} ${C_WHITE}%s klientów${C_RESET}\n" "Klienci:" "$client_count"
        if $warp_conn; then
            local curr_ip; curr_ip=$(_wgw_get_public_ip)
            printf "  ${C_GRAY}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "IP wyjściowe:" "${curr_ip:-nieznane}"
        fi
        echo -e "$SEP"

        if ! $wg_ok || ! $warp_ok; then
            printf "  ${C_CHOICE}[ 1]${C_RESET}  %-2s %s\n" "🚀" "Zainstaluj WireGuard + WARP (pełna instalacja)"
        fi

        if $wg_ok && $warp_ok; then
            printf "  ${C_CHOICE}[ 2]${C_RESET}  %-2s %s\n" "👤" "Dodaj klienta (+ QR kod)"
            printf "  ${C_CHOICE}[ 3]${C_RESET}  %-2s %s\n" "🗑️ " "Usuń klienta"
            printf "  ${C_CHOICE}[ 4]${C_RESET}  %-2s %s\n" "📋" "Lista klientów"
            printf "  ${C_CHOICE}[ 5]${C_RESET}  %-2s %s\n" "📱" "Pokaż QR klienta"
            printf "  ${C_CHOICE}[ 6]${C_RESET}  %-2s %s\n" "📊" "Pełny status + diagnostyka"
            printf "  ${C_CHOICE}[ 7]${C_RESET}  %-2s %s\n" "🔁" "Restart wszystkiego"
            printf "  ${C_CHOICE}[ 8]${C_RESET}  %-2s %s\n" "🌐" "Sprawdź IP + test WARP"
            printf "  ${C_DANGER}[ 9]${C_RESET}  %-2s %s\n" "🗑️ " "Odinstaluj WireGuard + WARP"
        fi

        echo -e "$SEP"
        printf "  ${C_WARN}[ 0]${C_RESET}  %-2s %s\n" "↩️ " "Powrót"
        echo

        read -r -p "$(echo -e ${C_PROMPT}"  👉 Wybierz opcję: "${C_RESET})" choice
        case $choice in
            1) _wgw_full_install; press_enter ;;
            2) $wg_ok && $warp_ok && { _wgw_add_client; press_enter; } ;;
            3) $wg_ok && $warp_ok && { _wgw_remove_client; press_enter; } ;;
            4) $wg_ok && $warp_ok && { _wgw_list_clients; press_enter; } ;;
            5) $wg_ok && $warp_ok && { _wgw_show_qr; press_enter; } ;;
            6) $wg_ok && $warp_ok && { _wgw_full_status; press_enter; } ;;
            7) $wg_ok && $warp_ok && { _wgw_restart_all; press_enter; } ;;
            8) $wg_ok && $warp_ok && { _wgw_check_ip; press_enter; } ;;
            9) ($wg_ok || $warp_ok) && { _wgw_uninstall; press_enter; } ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

_wgw_full_install() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}🚀 INSTALACJA WIREGUARD + WARP${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo -e "$SEP"

    # Zbierz dane
    local vps_ip wan_iface orig_gw
    vps_ip=$(curl -s --max-time 8 -4 icanhazip.com || echo "")
    wan_iface=$(_wgw_detect_wan)
    orig_gw=$(_wgw_detect_gw)

    if [[ -z "$vps_ip" || -z "$wan_iface" || -z "$orig_gw" ]]; then
        echo -e "  ${C_RED}❌ Nie można wykryć sieci. Sprawdź połączenie.${C_RESET}"
        return 1
    fi

    echo -e "  ${C_DIM}VPS IP:     ${C_WHITE}${vps_ip}${C_RESET}"
    echo -e "  ${C_DIM}Interfejs:  ${C_WHITE}${wan_iface}${C_RESET}"
    echo -e "  ${C_DIM}Brama:      ${C_WHITE}${orig_gw}${C_RESET}"
    echo -e "$SEP"
    echo -e "  ${C_YELLOW}⚠️  Instalacja zajmie 2-3 minuty.${C_RESET}"
    echo -e "  ${C_YELLOW}   SSH nie wypadnie — routing chroniony.${C_RESET}"
    echo
    read -r -p "  Kontynuować? (t/n): " confirm
    [[ "$confirm" != "t" && "$confirm" != "T" ]] && \
        echo -e "  ${C_YELLOW}❌ Anulowano.${C_RESET}" && return

    echo

    # ── Krok 1: Zależności ──────────────────────────────────
    echo -e "  ${C_BLUE}[1/7] Instalacja pakietów...${C_RESET}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq \
        wireguard wireguard-tools \
        iptables iptables-persistent \
        curl wget gnupg lsb-release \
        qrencode iproute2 2>/dev/null \
        && echo -e "  ${C_GREEN}✅ Pakiety zainstalowane${C_RESET}" \
        || { echo -e "  ${C_RED}❌ Błąd instalacji pakietów${C_RESET}"; return 1; }

    # ── Krok 2: Sysctl ──────────────────────────────────────
    echo -e "  ${C_BLUE}[2/7] Konfiguracja systemu (forwarding, BBR)...${C_RESET}"
    cat > /etc/sysctl.d/99-wg-warp.conf << 'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
EOF
    sysctl -p /etc/sysctl.d/99-wg-warp.conf -q
    echo -e "  ${C_GREEN}✅ Forwarding + BBR aktywne${C_RESET}"

    # ── Krok 3: WARP ────────────────────────────────────────
    echo -e "  ${C_BLUE}[3/7] Instalacja Cloudflare WARP...${C_RESET}"
    if ! command -v warp-cli &>/dev/null; then
        local codename
        codename=$(lsb_release -cs 2>/dev/null || \
            grep -oP 'VERSION_CODENAME=\K\S+' /etc/os-release | tr -d '"')
        if [[ -z "$codename" ]]; then
            echo -e "  ${C_RED}❌ Nie można wykryć wersji systemu${C_RESET}"; return 1
        fi
        curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
            | gpg --yes --dearmor \
            -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null \
            || { echo -e "  ${C_RED}❌ Błąd pobierania klucza GPG${C_RESET}"; return 1; }
        echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] \
https://pkg.cloudflareclient.com/ ${codename} main" \
            > /etc/apt/sources.list.d/cloudflare-client.list
        apt-get update -qq 2>/dev/null
        apt-get install -y -qq cloudflare-warp 2>/dev/null \
            || { echo -e "  ${C_RED}❌ Błąd instalacji WARP${C_RESET}"; return 1; }
    fi
    systemctl enable warp-svc --now &>/dev/null
    sleep 3

    if ! warp-cli account 2>/dev/null | grep -q "Account type"; then
        warp-cli --accept-tos registration new 2>/dev/null
        sleep 3
    fi

    warp-cli tunnel protocol set Userspace 2>/dev/null || true
    warp-cli mode warp 2>/dev/null || true
    warp-cli proxy disable 2>/dev/null || true
    warp-cli connect 2>/dev/null
    sleep 6
    echo -e "  ${C_GREEN}✅ WARP zainstalowany i połączony${C_RESET}"

    # ── Krok 4: Routing tablica ──────────────────────────────
    echo -e "  ${C_BLUE}[4/7] Konfiguracja routingu (SSH bezpieczny)...${C_RESET}"
    grep -q "^${WG_RT_TABLE} wg_warp" /etc/iproute2/rt_tables 2>/dev/null || \
        echo "${WG_RT_TABLE} wg_warp" >> /etc/iproute2/rt_tables

    local warp_iface
    warp_iface=$(_wgw_get_warp_iface)
    warp_iface="${warp_iface:-CloudflareWARP}"
    echo -e "  ${C_GREEN}✅ Tablica wg_warp gotowa (interfejs WARP: ${warp_iface})${C_RESET}"

    # ── Krok 5: Klucze i config WG ──────────────────────────
    echo -e "  ${C_BLUE}[5/7] Generowanie kluczy WireGuard...${C_RESET}"
    mkdir -p "$WG_CLIENTS_DIR"
    chmod 700 /etc/wireguard "$WG_CLIENTS_DIR"

    if [[ ! -f /etc/wireguard/server_private.key ]]; then
        wg genkey | tee /etc/wireguard/server_private.key \
            | wg pubkey > /etc/wireguard/server_public.key
        chmod 600 /etc/wireguard/server_private.key
    fi
    local srv_priv srv_pub
    srv_priv=$(cat /etc/wireguard/server_private.key)
    srv_pub=$(cat /etc/wireguard/server_public.key)

    cat > "$WG_CONFIG" << EOF
[Interface]
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${srv_priv}
DNS = ${WG_DNS_PRIMARY}, ${WG_DNS_SECONDARY}

# Routing: klienci WG → WARP → Internet
PostUp   = ip rule add from ${vps_ip}/32 table main priority 50 2>/dev/null || true
PostUp   = ip rule add to ${vps_ip}/32 table main priority 51 2>/dev/null || true
PostUp   = ip rule add fwmark ${WG_FWMARK} table wg_warp priority 100 2>/dev/null || true
PostUp   = ip route add default dev ${warp_iface} table wg_warp 2>/dev/null || ip route add default via ${orig_gw} dev ${wan_iface} table wg_warp 2>/dev/null || true
PostUp   = iptables -t mangle -A FORWARD -i wg0 -j MARK --set-mark ${WG_FWMARK}
PostUp   = iptables -t nat -A POSTROUTING -o ${warp_iface} -j MASQUERADE
PostUp   = iptables -t nat -A POSTROUTING -o ${wan_iface} -j MASQUERADE
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp   = iptables -A FORWARD -o wg0 -j ACCEPT

PostDown = ip rule del from ${vps_ip}/32 table main priority 50 2>/dev/null || true
PostDown = ip rule del to ${vps_ip}/32 table main priority 51 2>/dev/null || true
PostDown = ip rule del fwmark ${WG_FWMARK} table wg_warp 2>/dev/null || true
PostDown = ip route flush table wg_warp 2>/dev/null || true
PostDown = iptables -t mangle -D FORWARD -i wg0 -j MARK --set-mark ${WG_FWMARK} 2>/dev/null || true
PostDown = iptables -t nat -D POSTROUTING -o ${warp_iface} -j MASQUERADE 2>/dev/null || true
PostDown = iptables -t nat -D POSTROUTING -o ${wan_iface} -j MASQUERADE 2>/dev/null || true
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true
EOF
    chmod 600 "$WG_CONFIG"
    echo -e "  ${C_GREEN}✅ Konfiguracja WireGuard gotowa${C_RESET}"

    # ── Krok 6: Watchdog WARP ───────────────────────────────
    echo -e "  ${C_BLUE}[6/7] Instalacja watchdog (auto-reconnect WARP)...${C_RESET}"
    _wgw_install_watchdog "$vps_ip" "$wan_iface" "$orig_gw"
    echo -e "  ${C_GREEN}✅ Watchdog aktywny${C_RESET}"

    # ── Krok 7: Uruchomienie WG ─────────────────────────────
    echo -e "  ${C_BLUE}[7/7] Uruchamianie WireGuard...${C_RESET}"
    iptables -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    netfilter-persistent save 2>/dev/null || true

    systemctl stop wg-quick@wg0 2>/dev/null || true
    sleep 1
    systemctl enable wg-quick@wg0 --now
    sleep 3

    if _wgw_is_wg_running; then
        echo -e "  ${C_GREEN}✅ WireGuard uruchomiony${C_RESET}"
    else
        echo -e "  ${C_RED}❌ WireGuard nie uruchomił się${C_RESET}"
        echo -e "  ${C_DIM}Sprawdź: journalctl -u wg-quick@wg0 -n 20${C_RESET}"
        return 1
    fi

    echo
    echo -e "  ${C_GREEN}${C_BOLD}✅ Instalacja zakończona!${C_RESET}"
    echo -e "  ${C_DIM}Publiczny klucz serwera: ${C_WHITE}${srv_pub}${C_RESET}"
    echo

    # Automatycznie dodaj pierwszego klienta
    read -r -p "  Podaj nazwę pierwszego klienta [laptop]: " first_name
    first_name="${first_name:-laptop}"
    first_name="${first_name// /_}"
    _wgw_add_client_named "$first_name" "$vps_ip"
}

_wgw_install_watchdog() {
    local vps_ip="$1" wan_iface="$2" orig_gw="$3"

    cat > /usr/local/bin/warp-watchdog.sh << WDEOF
#!/bin/bash
LOG="/var/log/warp-watchdog.log"
log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" >> "\$LOG"; }
[ -f "\$LOG" ] && [ \$(stat -c%s "\$LOG" 2>/dev/null || echo 0) -gt 5242880 ] && \
    mv "\$LOG" "\${LOG}.1" && touch "\$LOG"

log "Watchdog uruchomiony"
fails=0
while true; do
    if warp-cli status 2>/dev/null | grep -qi "connected"; then
        fails=0
    else
        (( fails++ ))
        log "WARP rozłączony (próba \${fails})"
        if (( fails >= 2 )); then
            log "Reconnect..."
            warp-cli disconnect 2>/dev/null || true
            sleep 3
            warp-cli connect 2>/dev/null
            sleep 8
            if warp-cli status 2>/dev/null | grep -qi "connected"; then
                log "Reconnect OK"
                fails=0
                # Odśwież trasę w tablicy wg_warp
                WARP_IF=\$(ip link show 2>/dev/null \
                    | grep -oP '^\d+: \K[^:@]+' \
                    | grep -i "warp\|CloudflareWARP" | head -1)
                if [[ -n "\$WARP_IF" ]]; then
                    ip route replace default dev "\$WARP_IF" table wg_warp 2>/dev/null || true
                else
                    ip route replace default via "${orig_gw}" dev "${wan_iface}" table wg_warp 2>/dev/null || true
                fi
            else
                log "Reconnect nieudany"
            fi
        fi
    fi
    sleep 30
done
WDEOF
    chmod +x /usr/local/bin/warp-watchdog.sh

    cat > /etc/systemd/system/warp-watchdog.service << 'SVCEOF'
[Unit]
Description=Cloudflare WARP Watchdog
After=network-online.target warp-svc.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/warp-watchdog.sh
Restart=always
RestartSec=10
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable warp-watchdog --now &>/dev/null
}

_wgw_add_client() {
    local vps_ip
    vps_ip=$(curl -s --max-time 6 -4 icanhazip.com || echo "")
    if [[ -z "$vps_ip" ]]; then
        # Fallback: odczytaj z konfigu
        vps_ip=$(grep -oP 'Endpoint = \K[^:]+' "$WG_CLIENTS_DIR"/*//*.conf 2>/dev/null | head -1 || echo "")
    fi
    read -r -p "  Podaj nazwę klienta (np. telefon, laptop): " name
    [[ -z "$name" ]] && echo -e "  ${C_RED}❌ Nazwa nie może być pusta${C_RESET}" && return
    name="${name// /_}"
    _wgw_add_client_named "$name" "$vps_ip"
}

_wgw_add_client_named() {
    local name="$1"
    local vps_ip="${2:-}"
    local client_dir="$WG_CLIENTS_DIR/$name"

    if [[ -d "$client_dir" ]]; then
        echo -e "  ${C_RED}❌ Klient '$name' już istnieje${C_RESET}"
        return 1
    fi

    [[ -z "$vps_ip" ]] && vps_ip=$(curl -s --max-time 6 -4 icanhazip.com || echo "127.0.0.1")

    # Znajdź wolne IP
    local client_ip=""
    for i in $(seq 2 254); do
        local candidate="10.8.0.${i}"
        if ! grep -q "$candidate" "$WG_CONFIG" 2>/dev/null; then
            client_ip="$candidate"
            break
        fi
    done
    if [[ -z "$client_ip" ]]; then
        echo -e "  ${C_RED}❌ Brak wolnych adresów IP${C_RESET}"
        return 1
    fi

    mkdir -p "$client_dir"
    chmod 700 "$client_dir"

    local srv_pub cli_priv cli_pub cli_psk
    srv_pub=$(cat /etc/wireguard/server_public.key)
    cli_priv=$(wg genkey)
    cli_pub=$(echo "$cli_priv" | wg pubkey)
    cli_psk=$(wg genpsk)

    echo "$cli_priv" > "$client_dir/private.key"
    echo "$cli_pub"  > "$client_dir/public.key"
    echo "$cli_psk"  > "$client_dir/psk.key"
    echo "$client_ip" > "$client_dir/ip.txt"
    chmod 600 "$client_dir"/*.key

    cat > "$client_dir/${name}.conf" << EOF
[Interface]
PrivateKey = ${cli_priv}
Address = ${client_ip}/24
DNS = ${WG_DNS_PRIMARY}, ${WG_DNS_SECONDARY}

[Peer]
PublicKey = ${srv_pub}
PresharedKey = ${cli_psk}
Endpoint = ${vps_ip}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    chmod 600 "$client_dir/${name}.conf"

    # Dodaj peer do pliku serwera
    printf '\n[Peer]\n# %s\nPublicKey = %s\nPresharedKey = %s\nAllowedIPs = %s/32\n' \
        "$name" "$cli_pub" "$cli_psk" "$client_ip" >> "$WG_CONFIG"

    # Załaduj live bez restartu
    if _wgw_is_wg_running; then
        wg set wg0 peer "$cli_pub" \
            preshared-key "$client_dir/psk.key" \
            allowed-ips "${client_ip}/32" 2>/dev/null || true
    fi

    echo -e "\n  ${C_GREEN}${C_BOLD}✅ Klient '${name}' dodany — IP: ${client_ip}${C_RESET}"
    echo -e "\n  ${C_CYAN}QR kod (zeskanuj w aplikacji WireGuard):${C_RESET}\n"
    qrencode -t ansiutf8 < "$client_dir/${name}.conf" 2>/dev/null || \
        echo -e "  ${C_DIM}(qrencode niedostępne — config: $client_dir/${name}.conf)${C_RESET}"
    echo
    echo -e "  ${C_DIM}Config zapisany: ${C_WHITE}${client_dir}/${name}.conf${C_RESET}"
}

_wgw_remove_client() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}🗑️  USUŃ KLIENTA${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo -e "$SEP"

    if [[ ! -d "$WG_CLIENTS_DIR" ]] || \
       [[ -z "$(ls -A "$WG_CLIENTS_DIR" 2>/dev/null)" ]]; then
        echo -e "  ${C_YELLOW}ℹ️ Brak klientów${C_RESET}"; return
    fi

    local -a names=()
    local i=0
    for dir in "$WG_CLIENTS_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local n; n=$(basename "$dir")
        local ip; ip=$(cat "$dir/ip.txt" 2>/dev/null || echo "?")
        (( i++ ))
        names+=("$n")
        printf "  ${C_CHOICE}[%2d]${C_RESET}  %-18s %s\n" "$i" "$n" "$ip"
    done

    echo -e "$SEP"
    printf "  ${C_WARN}[ 0]${C_RESET}  Anuluj\n"
    echo
    read -r -p "  Wybierz numer: " sel
    [[ "$sel" == "0" || -z "$sel" ]] && return
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#names[@]} )); then
        echo -e "  ${C_RED}❌ Nieprawidłowy wybór${C_RESET}"; return
    fi

    local name="${names[$((sel-1))]}"
    local client_dir="$WG_CLIENTS_DIR/$name"
    local cli_pub; cli_pub=$(cat "$client_dir/public.key" 2>/dev/null || echo "")

    # Usuń live
    [[ -n "$cli_pub" ]] && _wgw_is_wg_running && \
        wg set wg0 peer "$cli_pub" remove 2>/dev/null || true

    # Usuń blok z konfigu serwera
    if [[ -n "$cli_pub" ]]; then
        python3 - "$WG_CONFIG" "$cli_pub" << 'PYEOF'
import sys
conf, pub = sys.argv[1], sys.argv[2]
with open(conf) as f:
    lines = f.readlines()
new, i = [], 0
while i < len(lines):
    if lines[i].strip() == '[Peer]':
        block, j = [], i
        while j < len(lines) and (j == i or not lines[j].strip().startswith('[')):
            block.append(lines[j]); j += 1
        if any(pub in l for l in block):
            i = j; continue
        else:
            new.extend(block); i = j; continue
    new.append(lines[i]); i += 1
with open(conf, 'w') as f:
    f.writelines(new)
PYEOF
    fi

    rm -rf "$client_dir"
    echo -e "  ${C_GREEN}✅ Klient '${name}' usunięty${C_RESET}"
}

_wgw_list_clients() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}📋 LISTA KLIENTÓW WIREGUARD${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────────────────${C_RESET}"
    echo -e "$SEP"

    if [[ ! -d "$WG_CLIENTS_DIR" ]] || \
       [[ -z "$(ls -A "$WG_CLIENTS_DIR" 2>/dev/null)" ]]; then
        echo -e "  ${C_YELLOW}ℹ️ Brak klientów. Dodaj przez opcję [2].${C_RESET}"
        return
    fi

    printf "  ${C_BOLD}${C_WHITE}%-16s %-14s %-10s %s${C_RESET}\n" \
        "NAZWA" "IP" "STATUS" "OSTATNI HANDSHAKE"
    echo -e "$SEP"

    # Pobierz aktywne peery
    declare -A hs_map=()
    if _wgw_is_wg_running; then
        while read -r pub ts; do
            hs_map["$pub"]="$ts"
        done < <(wg show wg0 latest-handshakes 2>/dev/null)
    fi

    local count=0
    for dir in "$WG_CLIENTS_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local name; name=$(basename "$dir")
        local ip; ip=$(cat "$dir/ip.txt" 2>/dev/null || echo "?")
        local pub; pub=$(cat "$dir/public.key" 2>/dev/null || echo "")
        local status_str="offline" hs_str="—"

        if [[ -n "$pub" && -n "${hs_map[$pub]+x}" ]]; then
            local ts="${hs_map[$pub]}"
            if [[ "$ts" != "0" ]]; then
                local age=$(( $(date +%s) - ts ))
                if (( age < 180 )); then
                    status_str="${C_GREEN}online${C_RESET}"
                    hs_str="${age}s temu"
                else
                    status_str="${C_YELLOW}nieaktywny${C_RESET}"
                    hs_str="$(( age/60 ))min temu"
                fi
            fi
        fi

        printf "  %-16s ${C_CYAN}%-14s${C_RESET} %-10b %s\n" \
            "$name" "$ip" "$status_str" "$hs_str"
        (( count++ ))
    done

    echo -e "$SEP"
    echo -e "  ${C_DIM}Razem: ${count} klientów${C_RESET}"
}

_wgw_show_qr() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}📱 QR KOD KLIENTA${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo -e "$SEP"

    if [[ ! -d "$WG_CLIENTS_DIR" ]] || \
       [[ -z "$(ls -A "$WG_CLIENTS_DIR" 2>/dev/null)" ]]; then
        echo -e "  ${C_YELLOW}ℹ️ Brak klientów${C_RESET}"; return
    fi

    local -a names=()
    local i=0
    for dir in "$WG_CLIENTS_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        (( i++ ))
        names+=("$(basename "$dir")")
        printf "  ${C_CHOICE}[%2d]${C_RESET}  %s\n" "$i" "$(basename "$dir")"
    done

    echo -e "$SEP"
    read -r -p "  Wybierz klienta: " sel
    [[ "$sel" == "0" || -z "$sel" ]] && return
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#names[@]} )); then
        echo -e "  ${C_RED}❌ Nieprawidłowy wybór${C_RESET}"; return
    fi

    local name="${names[$((sel-1))]}"
    local conf="$WG_CLIENTS_DIR/$name/${name}.conf"
    if [[ ! -f "$conf" ]]; then
        echo -e "  ${C_RED}❌ Plik konfiguracyjny nie istnieje${C_RESET}"; return
    fi

    echo -e "\n  ${C_CYAN}QR kod dla klienta '${name}':${C_RESET}\n"
    qrencode -t ansiutf8 < "$conf" 2>/dev/null || \
        echo -e "  ${C_DIM}qrencode niedostępne. Config: ${conf}${C_RESET}"
    echo
    echo -e "  ${C_DIM}Config: ${C_WHITE}${conf}${C_RESET}"
}

_wgw_full_status() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}📊 PEŁNY STATUS VPN${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────────────────${C_RESET}"

    # WARP
    echo -e "\n  ${C_BOLD}🌀 WARP:${C_RESET}"
    echo -e "$SEP"
    local cf_data curr_ip warp_on colo
    cf_data=$(curl -s --max-time 6 https://cloudflare.com/cdn-cgi/trace 2>/dev/null)
    curr_ip=$(echo "$cf_data" | grep "^ip=" | cut -d= -f2)
    warp_on=$(echo "$cf_data" | grep "^warp=" | cut -d= -f2)
    colo=$(echo "$cf_data" | grep "^colo=" | cut -d= -f2)

    printf "  %-20s ${C_WHITE}%s${C_RESET}\n" "IP wyjściowe:" "${curr_ip:-nieznane}"
    if [[ "$warp_on" == "on" ]]; then
        printf "  %-20s ${C_GREEN}%s${C_RESET}\n" "WARP:" "Aktywny ✅ (datacenter: ${colo})"
    else
        printf "  %-20s ${C_RED}%s${C_RESET}\n" "WARP:" "Nieaktywny ❌"
    fi
    warp-cli status 2>/dev/null | sed 's/^/  /'

    # WireGuard
    echo -e "\n  ${C_BOLD}🔑 WireGuard:${C_RESET}"
    echo -e "$SEP"
    if _wgw_is_wg_running; then
        echo -e "  ${C_GREEN}Status: Aktywny ✅${C_RESET}"
        wg show wg0 2>/dev/null | sed 's/^/  /'
    else
        echo -e "  ${C_RED}Status: Nieaktywny ❌${C_RESET}"
    fi

    # Routing
    echo -e "\n  ${C_BOLD}🗺️  Routing:${C_RESET}"
    echo -e "$SEP"
    echo -e "  ${C_DIM}Trasa główna:${C_RESET}"
    ip route show default 2>/dev/null | sed 's/^/    /'
    echo -e "  ${C_DIM}Tablica wg_warp (ruch klientów WG):${C_RESET}"
    ip route show table wg_warp 2>/dev/null | sed 's/^/    /' || echo "    (pusta)"
    echo -e "  ${C_DIM}Reguły (ip rule):${C_RESET}"
    ip rule list 2>/dev/null | grep -E "50:|51:|100:|wg_warp|fwmark" \
        | sed 's/^/    /' || echo "    (brak reguł WARP)"

    # DNS
    echo -e "\n  ${C_BOLD}🔍 DNS:${C_RESET}"
    echo -e "$SEP"
    local dns_ip
    dns_ip=$(dig +short @1.1.1.1 whoami.cloudflare TXT 2>/dev/null | tr -d '"')
    printf "  %-20s ${C_WHITE}%s${C_RESET}\n" "DNS (Cloudflare):" "${dns_ip:-niedostępny}"

    # Watchdog
    echo -e "\n  ${C_BOLD}🐕 Watchdog:${C_RESET}"
    echo -e "$SEP"
    printf "  %-20s " "warp-watchdog:"
    systemctl is-active warp-watchdog 2>/dev/null || echo "nieaktywny"
    echo -e "  ${C_DIM}Log: tail /var/log/warp-watchdog.log${C_RESET}"
}

_wgw_restart_all() {
    echo -e "\n  ${C_BLUE}🔄 Restart WireGuard + WARP...${C_RESET}"

    echo -n "  Zatrzymuję WireGuard...  "
    systemctl stop wg-quick@wg0 2>/dev/null \
        && echo -e "${C_GREEN}OK${C_RESET}" || echo "pominięty"

    echo -n "  Zatrzymuję watchdog...   "
    systemctl stop warp-watchdog 2>/dev/null \
        && echo -e "${C_GREEN}OK${C_RESET}" || echo "pominięty"

    echo -n "  Rozłączam WARP...        "
    warp-cli disconnect 2>/dev/null \
        && echo -e "${C_GREEN}OK${C_RESET}" || echo "pominięty"
    sleep 2

    echo -n "  Łączę WARP...            "
    warp-cli connect 2>/dev/null
    sleep 6
    _wgw_is_warp_connected \
        && echo -e "${C_GREEN}OK${C_RESET}" \
        || echo -e "${C_YELLOW}oczekuje (watchdog ponowi)${C_RESET}"

    # Odśwież trasę w tablicy wg_warp
    local warp_if; warp_if=$(_wgw_get_warp_iface)
    if [[ -n "$warp_if" ]]; then
        ip route replace default dev "$warp_if" table wg_warp 2>/dev/null || true
    fi

    echo -n "  Startuję WireGuard...    "
    systemctl start wg-quick@wg0 2>/dev/null
    sleep 2
    _wgw_is_wg_running \
        && echo -e "${C_GREEN}OK${C_RESET}" \
        || echo -e "${C_RED}błąd — sprawdź journalctl -u wg-quick@wg0${C_RESET}"

    echo -n "  Startuję watchdog...     "
    systemctl start warp-watchdog 2>/dev/null \
        && echo -e "${C_GREEN}OK${C_RESET}" || echo "błąd"

    echo
    local curr_ip; curr_ip=$(_wgw_get_public_ip)
    echo -e "  ${C_GREEN}✅ Restart zakończony${C_RESET}"
    echo -e "  Aktualne IP: ${C_WHITE}${curr_ip:-nieznane}${C_RESET}"
}

_wgw_check_ip() {
    clear; show_banner
    echo -e "  ${C_BOLD}${C_WHITE}🌐 TEST IP I WARP${C_RESET}"
    local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"
    echo -e "$SEP"
    echo -e "  ${C_DIM}Pobieranie danych...${C_RESET}"

    local cf_data curr_ip warp_on colo country city org
    cf_data=$(curl -s --max-time 8 https://cloudflare.com/cdn-cgi/trace 2>/dev/null)
    curr_ip=$(echo "$cf_data" | grep "^ip=" | cut -d= -f2)
    warp_on=$(echo "$cf_data" | grep "^warp=" | cut -d= -f2)
    colo=$(echo "$cf_data"    | grep "^colo=" | cut -d= -f2)

    local geo
    geo=$(curl -s --max-time 6 https://ipinfo.io/json 2>/dev/null)
    country=$(echo "$geo" | grep -oP '"country":\s*"\K[^"]+' 2>/dev/null || echo "?")
    city=$(echo "$geo"    | grep -oP '"city":\s*"\K[^"]+' 2>/dev/null    || echo "?")
    org=$(echo "$geo"     | grep -oP '"org":\s*"\K[^"]+' 2>/dev/null     || echo "?")

    echo
    printf "  ${C_GRAY}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "IP wyjściowe:"  "${curr_ip:-nieznane}"
    printf "  ${C_GRAY}%-20s${C_RESET} ${C_WHITE}%s, %s${C_RESET}\n" "Lokalizacja:" "$city" "$country"
    printf "  ${C_GRAY}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Operator:"      "$org"
    printf "  ${C_GRAY}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "CF Datacenter:" "${colo:-?}"

    echo
    if [[ "$warp_on" == "on" ]]; then
        echo -e "  ${C_GREEN}${C_BOLD}✅ WARP AKTYWNY — ruch idzie przez Cloudflare${C_RESET}"
    else
        echo -e "  ${C_RED}${C_BOLD}❌ WARP nieaktywny — sprawdź watchdog${C_RESET}"
    fi

    echo
    echo -e "  ${C_DIM}Test DNS (Cloudflare whoami):${C_RESET}"
    local dns_ip
    dns_ip=$(dig +short @1.1.1.1 whoami.cloudflare TXT 2>/dev/null | tr -d '"')
    printf "  ${C_GRAY}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "DNS odpowiada:" "${dns_ip:-błąd}"
}

_wgw_uninstall() {
    echo -e "\n  ${C_YELLOW}⚠️  To usunie WireGuard, WARP, wszystkie klucze i klientów.${C_RESET}"
    read -r -p "  Na pewno? (t/n): " confirm
    [[ "$confirm" != "t" && "$confirm" != "T" ]] && \
        echo -e "  ${C_YELLOW}❌ Anulowano.${C_RESET}" && return

    systemctl stop wg-quick@wg0 2>/dev/null || true
    systemctl disable wg-quick@wg0 2>/dev/null || true
    systemctl stop warp-watchdog 2>/dev/null || true
    systemctl disable warp-watchdog 2>/dev/null || true
    warp-cli disconnect 2>/dev/null || true
    warp-cli registration delete 2>/dev/null || true
    systemctl stop warp-svc 2>/dev/null || true
    systemctl disable warp-svc 2>/dev/null || true

    # Wyczyść routing
    ip rule del priority 50 2>/dev/null || true
    ip rule del priority 51 2>/dev/null || true
    ip rule del priority 100 2>/dev/null || true
    ip route flush table wg_warp 2>/dev/null || true
    iptables -t mangle -F FORWARD 2>/dev/null || true
    iptables -t nat -F POSTROUTING 2>/dev/null || true

    apt-get remove -y wireguard wireguard-tools cloudflare-warp 2>/dev/null || true
    rm -rf /etc/wireguard \
           /etc/apt/sources.list.d/cloudflare-client.list \
           /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
           /usr/local/bin/warp-watchdog.sh \
           /etc/systemd/system/warp-watchdog.service \
           /etc/sysctl.d/99-wg-warp.conf \
           /var/log/warp-watchdog.log \
           2>/dev/null || true

    sed -i '/^200 wg_warp/d' /etc/iproute2/rt_tables 2>/dev/null || true
    systemctl daemon-reload
    netfilter-persistent save 2>/dev/null || true

    echo -e "  ${C_GREEN}✅ WireGuard + WARP odinstalowane.${C_RESET}"
}



press_enter() {
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return to the menu..." && read -r || true
}
invalid_option() {
    echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" && sleep 1
}

list_all_accounts() {
    clear; show_banner
    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_YELLOW}ℹ️ Brak użytkowników w bazie danych.${C_RESET}"
        return
    fi

    local current_ts
    current_ts=$(date +%s)

    # Build sortable rows: sort_key|user|pass|expiry_display|days_display
    local -a rows=()
    while IFS=: read -r user pass expiry limit _rest; do
        [[ -z "$user" || "$user" == \#* ]] && continue

        local expiry_display days_display sort_key

        if [[ -z "$expiry" || "$expiry" == "Never" ]]; then
            expiry_display="Never"
            days_display="∞"
            sort_key="9999999"
        else
            local expiry_ts
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            expiry_display=$(date -d "$expiry" +"%d-%m-%Y" 2>/dev/null || echo "$expiry")

            if [[ "$expiry_ts" -le 0 ]]; then
                days_display="N/D"
                sort_key="9999998"
            elif (( expiry_ts < current_ts )); then
                local diff_past=$(( (current_ts - expiry_ts) / 86400 ))
                days_display="-${diff_past}d WYGAS."
                sort_key="$(printf '%010d' 0)"
            else
                local diff_secs=$(( expiry_ts - current_ts ))
                local days_left=$(( diff_secs / 86400 ))
                days_display="${days_left} dni"
                sort_key="$(printf '%010d' "$days_left")"
            fi
        fi

        # Truncate long passwords to 18 chars to keep layout tight
        local pass_display="$pass"
        if (( ${#pass} > 18 )); then
            pass_display="${pass:0:15}..."
        fi

        rows+=("${sort_key}|${user}|${pass_display}|${expiry_display}|${days_display}")
    done < "$DB_FILE"

    local total="${#rows[@]}"
    local div="${C_BLUE}  ──────────────────────────────────────────────────${C_RESET}"

    echo -e "  ${C_BOLD}${C_WHITE}🗂️  LISTA KONT${C_RESET}  ${C_DIM}(od najkrótszego do najdłuższego)${C_RESET}"
    echo -e "$div"
    printf "  ${C_BOLD}${C_WHITE}%-14s  %-18s  %-12s  %s${C_RESET}\n" "UŻYTKOWNIK" "HASŁO" "WYGASA" "DNI"
    echo -e "$div"

    while IFS='|' read -r _sortkey user pass_display expiry_display days_display; do
        local rc="$C_WHITE"
        if [[ "$days_display" == *"WYGAS."* ]]; then
            rc="$C_RED"
        elif [[ "$days_display" =~ ^([0-9]+)\ dni$ ]]; then
            (( BASH_REMATCH[1] <= 7 )) && rc="$C_YELLOW"
        elif [[ "$days_display" == "∞" ]]; then
            rc="$C_CYAN"
        fi
        printf "  ${rc}%-14s${C_RESET}  ${C_WHITE}%-18s${C_RESET}  ${C_YELLOW}%-12s${C_RESET}  ${rc}%s${C_RESET}\n" \
            "$user" "$pass_display" "$expiry_display" "$days_display"
    done < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1n)

    echo -e "$div"
    echo -e "  ${C_DIM}Razem: ${total} kont  •  ${C_RED}Czerwony${C_RESET}${C_DIM}=wygasłe  ${C_YELLOW}Żółty${C_RESET}${C_DIM}=≤7 dni  ${C_CYAN}Cyjan${C_RESET}${C_DIM}=bez limitu${C_RESET}\n"
}

main_menu() {
    while true; do
        export UNINSTALL_MODE="interactive"
        show_banner

        # Single-column layout — works on any terminal width ≥ 50 chars
        local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"

        echo
        echo -e "  ${C_TITLE}${C_BOLD}👤 ZARZĄDZANIE UŻYTKOWNIKAMI${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_CHOICE}[ 1]${C_RESET}  %-2s %-26s  ${C_CHOICE}[ 2]${C_RESET}  %-2s %s\n" "✨" "Utwórz użytkownika"     "🗑️ " "Usuń użytkownika"
        printf "  ${C_CHOICE}[ 3]${C_RESET}  %-2s %-26s  ${C_CHOICE}[ 4]${C_RESET}  %-2s %s\n" "🔄" "Odnów konto"            "🔒" "Zablokuj konto"
        printf "  ${C_CHOICE}[ 5]${C_RESET}  %-2s %-26s  ${C_CHOICE}[ 6]${C_RESET}  %-2s %s\n" "🔓" "Odblokuj konto"         "✏️ " "Edytuj użytkownika"
        printf "  ${C_CHOICE}[ 7]${C_RESET}  %-2s %-26s  ${C_CHOICE}[ 8]${C_RESET}  %-2s %s\n" "📋" "Lista sesji (aktywne)"  "📱" "Konfiguracja klienta"
        printf "  ${C_CHOICE}[10]${C_RESET}  %-2s %-26s  ${C_CHOICE}[21]${C_RESET}  %-2s %s\n" "📊" "Pasmo użytkownika"       "🗂️ " "Lista kont (hasła/daty)"

        echo
        echo -e "  ${C_TITLE}${C_BOLD}🌐 VPN I PROTOKOŁY${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_CHOICE}[12]${C_RESET}  %-2s %-26s  ${C_CHOICE}[13]${C_RESET}  %-2s %s\n" "🔌" "Menedżer protokołów"    "📈" "Monitor ruchu"
        printf "  ${C_CHOICE}[14]${C_RESET}  %-2s %s\n"                                        "🚫" "Blokuj torrenty (P2P)"

        echo
        echo -e "  ${C_TITLE}${C_BOLD}⚙️  USTAWIENIA SYSTEMU${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_CHOICE}[15]${C_RESET}  %-2s %-26s  ${C_CHOICE}[16]${C_RESET}  %-2s %s\n" "☁️ " "Domena CloudFlare"      "🎨" "Banner SSH"
        printf "  ${C_CHOICE}[17]${C_RESET}  %-2s %-26s  ${C_CHOICE}[18]${C_RESET}  %-2s %s\n" "🔄" "Auto-restart"           "💾" "Kopia zapasowa"
        printf "  ${C_CHOICE}[19]${C_RESET}  %-2s %-26s  ${C_CHOICE}[20]${C_RESET}  %-2s %s\n" "📥" "Przywróć kopię"         "🧹" "Wyczyść wygasłe"
        printf "  ${C_CHOICE}[22]${C_RESET}  %-2s %-26s  ${C_CHOICE}[23]${C_RESET}  %-2s %s\n" "🛡️ " "Fail2Ban (bruteforce)"   "📨" "Telegram powiadomienia"
        printf "  ${C_CHOICE}[24]${C_RESET}  %-2s %s\n" "🌀" "Cloudflare WARP (zmiana IP)"
        printf "  ${C_CHOICE}[25]${C_RESET}  %-2s %s\n" "🔐" "WireGuard + WARP VPN Server"

        echo
        echo -e "  ${C_DANGER}${C_BOLD}🔥 STREFA NIEBEZPIECZNA${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_DANGER}[99]${C_RESET}  %-2s %-26s  ${C_WARN}[ 0]${C_RESET}  %-2s %s\n"   "🗑️ " "Odinstaluj skrypt"      "🚪" "Wyjście"
        echo

        if ! read -r -p "$(echo -e ${C_PROMPT}"  👉 Wybierz opcję: "${C_RESET})" choice; then
            echo
            exit 0
        fi
        case $choice in
            1) create_user; press_enter ;;
            2) delete_user; press_enter ;;
            3) renew_user; press_enter ;;
            4) lock_user; press_enter ;;
            5) unlock_user; press_enter ;;
            6) edit_user; press_enter ;;
            7) list_users; press_enter ;;
            8) client_config_menu; press_enter ;;
            10) view_user_bandwidth; press_enter ;;
            21) list_all_accounts; press_enter ;;

            12) protocol_menu ;;
            13) traffic_monitor_menu ;;
            14) torrent_block_menu ;;

            15) dns_menu; press_enter ;;
            16) ssh_banner_menu ;;
            17) auto_reboot_menu ;;
            18) backup_user_data; press_enter ;;
            19) restore_user_data; press_enter ;;
            20) cleanup_expired; press_enter ;;
            22) fail2ban_menu ;;
            23) telegram_menu ;;
            24) warp_menu ;;
            25) wgwarp_menu ;;

            99) uninstall_script ;;
            0) exit 0 ;;
            *) invalid_option ;;
        esac
    done
}

if [[ "$1" == "--install-setup" ]]; then
    initial_setup
    exit 0
fi

require_interactive_terminal
sync_runtime_components_if_needed
main_menu
