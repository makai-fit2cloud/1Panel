#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CURRENT_DIR=$(
    cd "$(dirname "$0")" || exit
    pwd
)

LANG_FILE=".selected_language"
LANG_DIR="$CURRENT_DIR/lang"
AVAILABLE_LANGS=("en" "zh" "fa" "pt-BR" "ru")

declare -A LANG_NAMES
LANG_NAMES=( ["en"]="English" ["zh"]="Chinese  中文(简体)" ["fa"]="Persian" ["pt-BR"]="Português (Brasil)" ["ru"]="Русский" )

if [ -f "$CURRENT_DIR/$LANG_FILE" ]; then
    selected_lang=$(cat "$CURRENT_DIR/$LANG_FILE")
else
    echo "en" > "$CURRENT_DIR/$LANG_FILE"
    source "$LANG_DIR/en.sh"

    echo "$TXT_LANG_PROMPT_MSG"
    for i in "${!AVAILABLE_LANGS[@]}"; do
        lang_code="${AVAILABLE_LANGS[i]}"
        echo "$((i + 1)). ${LANG_NAMES[$lang_code]}"
    done

    read -p "$TXT_LANG_CHOICE_MSG" lang_choice

    if [[ $lang_choice -ge 1 && $lang_choice -le ${#AVAILABLE_LANGS[@]} ]]; then
        selected_lang=${AVAILABLE_LANGS[$((lang_choice - 1))]}
        echo "$TXT_LANG_SELECTED_CONFIRM_MSG ${LANG_NAMES[$selected_lang]}"
        echo "$selected_lang" > "$CURRENT_DIR/$LANG_FILE"
    else
        echo "$TXT_LANG_INVALID_MSG"
        selected_lang="en"
        echo "$selected_lang" > "$CURRENT_DIR/$LANG_FILE"
    fi
fi

LANGFILE="$LANG_DIR/$selected_lang.sh"
if [ -f "$LANGFILE" ]; then
    source "$LANGFILE"
else
    echo -e "${RED} $TXT_LANG_NOT_FOUND_MSG $LANGFILE${NC}"
    exit 1
fi
clear

function log() {
    message="[1Panel Log]: $1 "
    case "$1" in
        *"$TXT_RUN_AS_ROOT"*)
            echo -e "${RED}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *"$TXT_SUCCESS_MESSAGE"* )
            echo -e "${GREEN}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *"$TXT_IGNORE_MESSAGE"*|*"$TXT_SKIP_MESSAGE"* )
            echo -e "${YELLOW}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        * )
            echo -e "${BLUE}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
    esac
}
cat << EOF
 ██╗    ██████╗  █████╗ ███╗   ██╗███████╗██╗
███║    ██╔══██╗██╔══██╗████╗  ██║██╔════╝██║
╚██║    ██████╔╝███████║██╔██╗ ██║█████╗  ██║
 ██║    ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║
 ██║    ██║     ██║  ██║██║ ╚████║███████╗███████╗
 ╚═╝    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝
EOF

log "$TXT_START_INSTALLATION"

function Check_Root() {
    if [[ $EUID -ne 0 ]]; then
        log "$TXT_RUN_AS_ROOT"
        exit 1
    fi
}

function Prepare_System(){
    if which 1panel >/dev/null 2>&1; then
        log "$TXT_PANEL_ALREADY_INSTALLED"
        exit 1
    fi
}

function Set_Dir(){
    PANEL_BASE_DIR=/opt
    log "$TXT_TIMEOUT_USE_DEFAULT_PATH"
}

function Install_Docker(){
    if which docker >/dev/null 2>&1; then
        docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
        major_version=${docker_version%%.*}
        minor_version=${docker_version##*.}
        if [[ $major_version -lt 20 ]]; then
            log "$TXT_LOW_DOCKER_VERSION"
        fi

        systemctl start docker 2>&1 | tee -a "${CURRENT_DIR}"/install.log
    else
        log "$TXT_DOCKER_INSTALL_ONLINE"

        chmod +x docker/bin/*
        cp docker/bin/* /usr/bin/
        cp docker/service/docker.service /etc/systemd/system/
        chmod 754 /etc/systemd/system/docker.service
        mkdir -p /etc/docker/
        cp docker/conf/daemon.json /etc/docker/daemon.json

        log "$TXT_DOCKER_INSTALL_SUCCESS"
        systemctl enable docker; systemctl daemon-reload; systemctl start docker 2>&1 | tee -a "${CURRENT_DIR}"/install.log
    fi
}


function Set_Port(){
    DEFAULT_PORT=$1

    while true; do
        PANEL_PORT=$DEFAULT_PORT

        if command -v ss >/dev/null 2>&1; then
            if ss -tlun | grep -q ":$PANEL_PORT " >/dev/null 2>&1; then
                log "$TXT_PORT_OCCUPIED $PANEL_PORT"
                continue
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tlun | grep -q ":$PANEL_PORT " >/dev/null 2>&1; then
                log "$TXT_PORT_OCCUPIED $PANEL_PORT"
                continue
            fi
        fi

         log "$TXT_THE_PORT_U_SET $PANEL_PORT"
        break
    done
}

function Set_Firewall(){
    if which firewall-cmd >/dev/null 2>&1; then
        if systemctl status firewalld | grep -q "Active: active" >/dev/null 2>&1;then
            log "$TXT_FIREWALL_OPEN_PORT $PANEL_PORT"
            firewall-cmd --zone=public --add-port="$PANEL_PORT"/tcp --permanent
            firewall-cmd --reload
        else
            log "$TXT_FIREWALL_NOT_ACTIVE_SKIP"
        fi
    fi

    if which ufw >/dev/null 2>&1; then
        if systemctl status ufw | grep -q "Active: active" >/dev/null 2>&1;then
            log "$TXT_FIREWALL_OPEN_PORT $PANEL_PORT"
            ufw allow "$PANEL_PORT"/tcp
            ufw reload
        else
            log "$TXT_FIREWALL_NOT_ACTIVE_IGNORE"
        fi
    fi
}

function Set_Entrance(){
    DEFAULT_ENTRANCE=`cat /dev/urandom | head -n 16 | md5sum | head -c 10`
    PANEL_ENTRANCE=$DEFAULT_ENTRANCE
}



function Set_Username(){
    DEFAULT_USERNAME=$1
    PANEL_USERNAME=$DEFAULT_USERNAME
    log "面板用户为：$PANEL_USERNAME"
}

function Set_Password(){
    DEFAULT_PASSWORD=$1
    PANEL_PASSWORD=$DEFAULT_PASSWORD
    log "面板密码为: $PANEL_PASSWORD"
}

function Init_Panel(){
    log "$TXT_CONFIGURE_PANEL_SERVICE"

    RUN_BASE_DIR=$PANEL_BASE_DIR/1panel
    mkdir -p "$RUN_BASE_DIR"
    rm -rf "$RUN_BASE_DIR:?/*"

    cd "${CURRENT_DIR}" || exit

    cp ./1panel /usr/local/bin && chmod +x /usr/local/bin/1panel
    if [[ ! -f /usr/bin/1panel ]]; then
        ln -s /usr/local/bin/1panel /usr/bin/1panel >/dev/null 2>&1
    fi

    cp ./1pctl /usr/local/bin && chmod +x /usr/local/bin/1pctl
    sed -i -e "s#BASE_DIR=.*#BASE_DIR=${PANEL_BASE_DIR}#g" /usr/local/bin/1pctl
    sed -i -e "s#ORIGINAL_PORT=.*#ORIGINAL_PORT=${PANEL_PORT}#g" /usr/local/bin/1pctl
    sed -i -e "s#ORIGINAL_USERNAME=.*#ORIGINAL_USERNAME=${PANEL_USERNAME}#g" /usr/local/bin/1pctl
    ESCAPED_PANEL_PASSWORD=$(echo "$PANEL_PASSWORD" | sed 's/[!@#$%*_,.?]/\\&/g')
    sed -i -e "s#ORIGINAL_PASSWORD=.*#ORIGINAL_PASSWORD=${ESCAPED_PANEL_PASSWORD}#g" /usr/local/bin/1pctl
    sed -i -e "s#ORIGINAL_ENTRANCE=.*#ORIGINAL_ENTRANCE=${PANEL_ENTRANCE}#g" /usr/local/bin/1pctl
    sed -i -e "s#LANGUAGE=.*#LANGUAGE=${selected_lang}#g" /usr/local/bin/1pctl
    if [[ ! -f /usr/bin/1pctl ]]; then
        ln -s /usr/local/bin/1pctl /usr/bin/1pctl >/dev/null 2>&1
    fi

    mkdir $RUN_BASE_DIR/geo/
    cp -r ./GeoIP.mmdb $RUN_BASE_DIR/geo/

    cp -r ./lang /usr/local/bin
    cp ./1panel.service /etc/systemd/system

    systemctl enable 1panel; systemctl daemon-reload 2>&1 | tee -a "${CURRENT_DIR}"/install.log
    log "$TXT_START_PANEL_SERVICE"
    systemctl start 1panel | tee -a "${CURRENT_DIR}"/install.log

    for b in {1..30}
    do
        sleep 3
        service_status=$(systemctl status 1panel 2>&1 | grep Active)
        if [[ $service_status == *running* ]];then
            log "$TXT_PANEL_SERVICE_START_SUCCESS"
            break;
        else
            log "$TXT_PANEL_SERVICE_START_ERROR"
            exit 1
        fi
    done
    sed -i -e "s#ORIGINAL_PASSWORD=.*#ORIGINAL_PASSWORD=\*\*\*\*\*\*\*\*\*\*#g" /usr/local/bin/1pctl
}

function Get_Ip(){
    active_interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')
    if [[ -z $active_interface ]]; then
        LOCAL_IP="127.0.0.1"
    else
        LOCAL_IP=$(ip -4 addr show dev "$active_interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    fi

    PUBLIC_IP=$(curl -s https://api64.ipify.org)
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP="N/A"
    fi
    if echo "$PUBLIC_IP" | grep -q ":"; then
        PUBLIC_IP=[${PUBLIC_IP}]
        1pctl listen-ip ipv6
    fi
}

function Show_Result(){
    log ""
    log "$TXT_THANK_YOU_WAITING"
    log ""
    log "$TXT_BROWSER_ACCESS_PANEL"
    log "$TXT_EXTERNAL_ADDRESS http://$PUBLIC_IP:$PANEL_PORT/$PANEL_ENTRANCE"
    log "$TXT_INTERNAL_ADDRESS http://$LOCAL_IP:$PANEL_PORT/$PANEL_ENTRANCE"
    log "$TXT_PANEL_USER $PANEL_USERNAME"
    log "$TXT_PANEL_PASSWORD $PANEL_PASSWORD"
    log ""
    log "$TXT_PROJECT_OFFICIAL_WEBSITE"
    log "$TXT_PROJECT_DOCUMENTATION"
    log "$TXT_PROJECT_REPOSITORY"
    log "$TXT_COMMUNITY"
    log ""
    log "$TXT_OPEN_PORT_SECURITY_GROUP $PANEL_PORT"
    log ""
    log "$TXT_REMEMBER_YOUR_PASSWORD"
    log ""
    log "================================================================"
}

function main(){
    Check_Root
    Prepare_System
    Set_Dir
    Install_Docker
    Set_Port $1
    Set_Firewall
    Set_Entrance
    Set_Username $2
    Set_Password $3
    Init_Panel
    Get_Ip
    Show_Result
    1pctl reset entrance
}

main $1 $2 $3