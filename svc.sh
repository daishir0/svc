#!/bin/bash
# svc.sh - 対話型systemctlコントローラ（矢印キー操作対応）
# 使い方: svc [サービス名]

# ========================================
# 設定: リストから除外するサービス（正規表現パターン）
# ========================================
EXCLUDE_PATTERNS="^dbus|^ttyd|^firewalld"

# ========================================
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
BG_CYAN='\033[46m'
WHITE='\033[1;37m'

trap 'tput cnorm; echo; exit 0' INT EXIT

get_status_raw() {
    systemctl is-active "$1" 2>/dev/null
}

status_colored() {
    case "$1" in
        active)   printf "${GREEN}active${RESET}" ;;
        inactive) printf "${YELLOW}inactive${RESET}" ;;
        failed)   printf "${RED}failed${RESET}" ;;
        *)        printf "$1" ;;
    esac
}

get_term_lines() {
    tput lines 2>/dev/null || echo 24
}

has_timer() {
    local name="${1%.service}"
    [ -f "/etc/systemd/system/${name}.timer" ]
}

_clear_menu() {
    local lines="$1"
    local i
    for ((i=0; i<lines; i++)); do
        echo -ne "\033[2K"
        [ "$i" -lt $((lines - 1)) ] && echo
    done
    echo -ne "\033[${lines}A"
}

# ========================================
# 汎用カーソルメニュー
# ========================================
MENU_DELETE_IDX=-1

arrow_menu() {
    local _result_var="$1"
    local _allow_delete="$2"
    shift 2
    local items=("$@")
    local total=${#items[@]}
    local cur=0
    local scroll=0
    local max_visible=$(( $(get_term_lines) - 4 ))
    [ "$max_visible" -lt 5 ] && max_visible=5
    [ "$max_visible" -gt "$total" ] && max_visible=$total

    tput civis

    _draw_menu() {
        local i
        for ((i=0; i<max_visible+1; i++)); do
            echo -ne "\033[2K"
            [ "$i" -lt "$max_visible" ] && echo
        done
        echo -ne "\033[$((max_visible+1))A"

        for ((i=0; i<max_visible; i++)); do
            local idx=$((scroll + i))
            [ "$idx" -ge "$total" ] && break
            if [ "$idx" -eq "$cur" ]; then
                echo -e "\033[2K  ${BG_CYAN}${WHITE}▶ ${items[$idx]}${RESET}"
            else
                echo -e "\033[2K    ${items[$idx]}"
            fi
        done

        local hint="↑↓:移動 Enter:選択"
        [ "$_allow_delete" = "1" ] && hint="$hint d:削除"
        hint="$hint ESC/q:戻る"
        if [ "$total" -gt "$max_visible" ]; then
            echo -ne "\033[2K  ${DIM}[$((cur+1))/${total}] ${hint}${RESET}"
        else
            echo -ne "\033[2K  ${DIM}${hint}${RESET}"
        fi
        echo -ne "\033[$((max_visible + 1))A\r"
    }

    _draw_menu

    while true; do
        IFS= read -rsn1 key
        case "$key" in
            $'\x1b')
                read -rsn2 -t 0.1 seq
                if [ -z "$seq" ]; then
                    _clear_menu $((max_visible + 1))
                    tput cnorm
                    eval "$_result_var=-1"
                    return 0
                fi
                case "$seq" in
                    '[A')
                        if [ "$cur" -gt 0 ]; then
                            ((cur--))
                            [ "$cur" -lt "$scroll" ] && ((scroll--))
                        fi
                        ;;
                    '[B')
                        if [ "$cur" -lt $((total - 1)) ]; then
                            ((cur++))
                            [ "$cur" -ge $((scroll + max_visible)) ] && ((scroll++))
                        fi
                        ;;
                    '[5')
                        read -rsn1 -t 0.1
                        cur=$((cur - max_visible))
                        [ "$cur" -lt 0 ] && cur=0
                        scroll=$cur
                        [ "$scroll" -lt 0 ] && scroll=0
                        ;;
                    '[6')
                        read -rsn1 -t 0.1
                        cur=$((cur + max_visible))
                        [ "$cur" -ge "$total" ] && cur=$((total - 1))
                        scroll=$((cur - max_visible + 1))
                        [ "$scroll" -lt 0 ] && scroll=0
                        ;;
                    '[3')
                        read -rsn1 -t 0.1
                        if [ "$_allow_delete" = "1" ]; then
                            _clear_menu $((max_visible + 1))
                            tput cnorm
                            MENU_DELETE_IDX=$cur
                            eval "$_result_var=-2"
                            return 0
                        fi
                        ;;
                esac
                _draw_menu
                ;;
            '')
                _clear_menu $((max_visible + 1))
                tput cnorm
                eval "$_result_var=$cur"
                return 0
                ;;
            d|D)
                if [ "$_allow_delete" = "1" ]; then
                    _clear_menu $((max_visible + 1))
                    tput cnorm
                    MENU_DELETE_IDX=$cur
                    eval "$_result_var=-2"
                    return 0
                fi
                ;;
            q|Q)
                _clear_menu $((max_visible + 1))
                tput cnorm
                eval "$_result_var=-1"
                return 0
                ;;
        esac
    done
}

# ========================================
# サービス一覧（状態順+名前順）
# ========================================
build_service_list() {
    local all_svcs
    all_svcs=$(ls /etc/systemd/system/*.service 2>/dev/null | xargs -I{} basename {} | grep -vE "$EXCLUDE_PATTERNS" | sort)

    for s in $all_svcs; do
        [ ! -f "/etc/systemd/system/$s" ] && continue
        local st
        st=$(systemctl is-active "$s" 2>/dev/null)
        case "$st" in
            active)   echo "1 $s" ;;
            failed)   echo "2 $s" ;;
            inactive) echo "3 $s" ;;
            *)        echo "4 $s" ;;
        esac
    done | sort -k1,1n -k2,2 | awk '{print $2}'
}

# ========================================
# ポート情報キャッシュ構築（PID→ポート）
# ========================================
declare -A PORT_CACHE

build_port_cache() {
    PORT_CACHE=()
    local line pid ports
    while IFS= read -r line; do
        # ss出力からPIDとポートを抽出
        pid=$(echo "$line" | grep -oP 'pid=\K[0-9]+' | head -1)
        port=$(echo "$line" | grep -oP ':\K[0-9]+(?=\s)' | head -1)
        [ -z "$pid" ] || [ -z "$port" ] && continue
        if [ -n "${PORT_CACHE[$pid]}" ]; then
            # 重複チェック
            echo "${PORT_CACHE[$pid]}" | grep -q "\b${port}\b" || PORT_CACHE[$pid]="${PORT_CACHE[$pid]},${port}"
        else
            PORT_CACHE[$pid]="$port"
        fi
    done < <(ss -tlnp 2>/dev/null; ss -ulnp 2>/dev/null)
}

# サービスのPIDからポート取得
get_service_ports() {
    local svc="$1"
    local main_pid
    main_pid=$(systemctl show -p MainPID --value "$svc" 2>/dev/null)
    [ -z "$main_pid" ] || [ "$main_pid" = "0" ] && return

    # MainPIDとその子プロセスのポートを集約
    local all_ports=""
    local pid
    for pid in $main_pid $(pgrep -P "$main_pid" 2>/dev/null); do
        if [ -n "${PORT_CACHE[$pid]}" ]; then
            if [ -z "$all_ports" ]; then
                all_ports="${PORT_CACHE[$pid]}"
            else
                all_ports="${all_ports},${PORT_CACHE[$pid]}"
            fi
        fi
    done

    # 重複排除してソート
    if [ -n "$all_ports" ]; then
        echo "$all_ports" | tr ',' '\n' | sort -un | tr '\n' ',' | sed 's/,$//'
    fi
}

# ========================================
# サービス表示ラベル生成
# ========================================
build_labels() {
    build_port_cache

    local svc st tag timer_mark port_info
    for svc in "${SVC_LIST[@]}"; do
        st=$(get_status_raw "$svc")
        case "$st" in
            active)   tag="${GREEN}active${RESET}" ;;
            inactive) tag="${YELLOW}inactive${RESET}" ;;
            failed)   tag="${RED}failed${RESET}" ;;
            *)        tag="$st" ;;
        esac
        timer_mark=""
        if has_timer "$svc"; then
            local tname="${svc%.service}.timer"
            local tst ten
            tst=$(get_status_raw "$tname")
            ten=$(systemctl is-enabled "$tname" 2>/dev/null)
            # スケジュール定義を取得
            local sched
            sched=$(grep -oP '^(OnCalendar|OnBootSec|OnUnitActiveSec|OnActiveSec)=\K.*' "/etc/systemd/system/$tname" 2>/dev/null | paste -sd',' -)

            if [ "$tst" = "active" ]; then
                timer_mark=" ${GREEN}⏱running${RESET}"
            elif [ "$ten" = "enabled" ]; then
                timer_mark=" ${YELLOW}⏱enabled${RESET}"
            else
                timer_mark=" ${DIM}⏱disabled${RESET}"
            fi
            [ -n "$sched" ] && timer_mark="${timer_mark} ${DIM}${sched}${RESET}"
        fi
        port_info=""
        if [ "$st" = "active" ]; then
            local ports
            ports=$(get_service_ports "$svc")
            [ -n "$ports" ] && port_info=" ${CYAN}:${ports}${RESET}"
        fi
        printf '%-38s [%b]%b%b\n' "$svc" "$tag" "$port_info" "$timer_mark"
    done
}

# ========================================
# サービス削除
# ========================================
delete_service() {
    local svc="$1"
    local name="${svc%.service}"

    echo ""
    echo -e "${RED}${BOLD}⚠ 削除: ${svc}${RESET}"
    if has_timer "$svc"; then
        echo -e "  対象: ${svc} + ${name}.timer"
    else
        echo -e "  対象: ${svc}"
    fi
    echo -e "  処理: stop → disable → ファイル削除 → daemon-reload"
    echo ""
    echo -ne "${BOLD}本当に削除しますか？ (y/N): ${RESET}"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${DIM}キャンセルしました${RESET}"
        read -rsn1 -p "$(echo -e "${DIM}Enterで続行...${RESET}")"
        return 1
    fi

    echo ""
    if has_timer "$svc"; then
        echo -e "  ${DIM}stop ${name}.timer ...${RESET}"
        sudo systemctl stop "${name}.timer" 2>/dev/null
        echo -e "  ${DIM}disable ${name}.timer ...${RESET}"
        sudo systemctl disable "${name}.timer" 2>/dev/null
    fi

    echo -e "  ${DIM}stop ${svc} ...${RESET}"
    sudo systemctl stop "$svc" 2>/dev/null
    echo -e "  ${DIM}disable ${svc} ...${RESET}"
    sudo systemctl disable "$svc" 2>/dev/null

    echo -e "  ${DIM}rm /etc/systemd/system/${svc} ...${RESET}"
    sudo rm -f "/etc/systemd/system/${svc}"
    if [ -f "/etc/systemd/system/${name}.timer" ]; then
        echo -e "  ${DIM}rm /etc/systemd/system/${name}.timer ...${RESET}"
        sudo rm -f "/etc/systemd/system/${name}.timer"
    fi

    echo -e "  ${DIM}daemon-reload ...${RESET}"
    sudo systemctl daemon-reload

    echo ""
    echo -e "${GREEN}削除完了${RESET}"
    read -rsn1 -p "$(echo -e "${DIM}Enterで続行...${RESET}")"
    return 0
}

# ========================================
# アクション実行
# ========================================
do_action() {
    local svc="$1"

    while true; do
        local raw_st timer_info=""
        raw_st=$(get_status_raw "$svc")

        if has_timer "$svc"; then
            local tname="${svc%.service}.timer"
            local tst
            tst=$(get_status_raw "$tname")
            timer_info=" ⏱timer:$(status_colored "$tst")"
        fi

        local enabled_st
        enabled_st=$(systemctl is-enabled "$svc" 2>/dev/null)
        local enabled_label
        if [ "$enabled_st" = "enabled" ]; then
            enabled_label="${GREEN}enabled${RESET}"
        else
            enabled_label="${DIM}disabled${RESET}"
        fi

        echo ""
        echo -e "${BOLD}--- ${CYAN}${svc}${RESET} [$(status_colored "$raw_st")] [${enabled_label}]${timer_info} ${BOLD}---${RESET}"
        echo ""
        local enable_action=""
        if [ "$enabled_st" = "enabled" ]; then
            enable_action="disable (自動起動OFF)"
        else
            enable_action="enable (自動起動ON)"
        fi

        local actions=()
        case "$raw_st" in
            active)   actions=("stop" "restart" "status" "log" "$enable_action") ;;
            inactive) actions=("start" "status" "log" "$enable_action") ;;
            failed)   actions=("start" "restart" "status" "log" "$enable_action") ;;
            *)        actions=("start" "stop" "restart" "status" "log" "$enable_action") ;;
        esac

        if has_timer "$svc"; then
            local tst
            tst=$(get_status_raw "${svc%.service}.timer")
            case "$tst" in
                active)   actions+=("timer stop" "timer status") ;;
                *)        actions+=("timer start" "timer status") ;;
            esac
        fi

        actions+=("戻る")

        local choice
        arrow_menu choice 0 "${actions[@]}"

        if [ "$choice" -eq -1 ]; then
            return
        fi

        local act="${actions[$choice]}"
        case "$act" in
            enable\ *|disable\ *)
                local cmd="${act%% *}"
                echo -e "${BOLD}sudo systemctl ${cmd} ${svc}${RESET}"
                sudo systemctl "$cmd" "$svc"
                if [ $? -eq 0 ]; then
                    local new_en
                    new_en=$(systemctl is-enabled "$svc" 2>/dev/null)
                    echo -e "${GREEN}OK${RESET} → ${new_en}"
                else
                    echo -e "${RED}FAILED${RESET}"
                fi
                echo ""
                read -rsn1 -p "$(echo -e "${DIM}Enterで続行...${RESET}")"
                ;;
            start|stop|restart)
                echo -e "${BOLD}sudo systemctl ${act} ${svc}${RESET}"
                sudo systemctl "$act" "$svc"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}OK${RESET} → $(status_colored "$(get_status_raw "$svc")")"
                else
                    echo -e "${RED}FAILED${RESET}"
                fi
                echo ""
                read -rsn1 -p "$(echo -e "${DIM}Enterで続行...${RESET}")"
                ;;
            status)
                echo ""
                systemctl status "$svc" --no-pager -l 2>/dev/null | head -20
                echo ""
                read -rsn1 -p "$(echo -e "${DIM}Enterで続行...${RESET}")"
                ;;
            log)
                echo ""
                echo -e "${BOLD}journalctl -u ${svc} (最新50行)${RESET}"
                echo ""
                journalctl -u "$svc" --no-pager -n 50 2>/dev/null
                echo ""
                read -rsn1 -p "$(echo -e "${DIM}Enterで続行...${RESET}")"
                ;;
            timer\ start|timer\ stop)
                local tname="${svc%.service}.timer"
                local tact="${act#timer }"
                echo -e "${BOLD}sudo systemctl ${tact} ${tname}${RESET}"
                sudo systemctl "$tact" "$tname"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}OK${RESET} → $(status_colored "$(get_status_raw "$tname")")"
                else
                    echo -e "${RED}FAILED${RESET}"
                fi
                echo ""
                read -rsn1 -p "$(echo -e "${DIM}Enterで続行...${RESET}")"
                ;;
            timer\ status)
                local tname="${svc%.service}.timer"
                echo ""
                systemctl status "$tname" --no-pager -l 2>/dev/null | head -20
                echo ""
                echo -e "${DIM}次回実行:${RESET}"
                systemctl list-timers "$tname" --no-pager 2>/dev/null | head -3
                echo ""
                read -rsn1 -p "$(echo -e "${DIM}Enterで続行...${RESET}")"
                ;;
            "戻る")
                return
                ;;
        esac
    done
}

# ========================================
# メイン
# ========================================

if [ -n "$1" ]; then
    svc="$1"
    [[ "$svc" != *.service ]] && svc="${svc}.service"
    if [ -f "/etc/systemd/system/$svc" ]; then
        do_action "$svc"
        exit 0
    else
        echo -e "${RED}サービスが見つかりません: ${svc}${RESET}"
        exit 1
    fi
fi

while true; do
    clear
    echo -e "${BOLD}===== svc - サービスコントローラ =====${RESET}"
    echo -e "${DIM}読み込み中...${RESET}"

    mapfile -t SVC_LIST < <(build_service_list)
    mapfile -t LABELS < <(build_labels)
    total=${#SVC_LIST[@]}

    clear
    echo -e "${BOLD}===== svc - サービスコントローラ =====${RESET}"
    echo -e "${DIM}${total}個のサービス${RESET}"
    echo ""

    choice=""
    arrow_menu choice 1 "${LABELS[@]}"

    if [ "$choice" -eq -1 ]; then
        echo "終了します"
        exit 0
    fi

    if [ "$choice" -eq -2 ]; then
        if [ "$MENU_DELETE_IDX" -ge 0 ] && [ "$MENU_DELETE_IDX" -lt "$total" ]; then
            delete_service "${SVC_LIST[$MENU_DELETE_IDX]}"
        fi
        continue
    fi

    if [ "$choice" -ge 0 ] && [ "$choice" -lt "$total" ]; then
        do_action "${SVC_LIST[$choice]}"
    fi
done
