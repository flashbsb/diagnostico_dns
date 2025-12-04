#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS - BASH EDITION
# Versão: 13.1 (Parity Complete & Bugfix)
# ==============================================

# --- CONFIGURAÇÕES PADRÃO ---

# Flags explícitas para evitar ambiguidade (Igual ao Python)
DIG_OPTS_ITERATIVE="+norecurse +time=1 +tries=1 +nocookie +cd +bufsize=512"
DIG_OPTS_RECURSIVE="+recurse +time=1 +tries=1 +nocookie +cd +bufsize=512"

# Prefixo e Arquivos
LOG_PREFIX="dnsdiag"
FILE_DOMAINS="domains_tests.csv"
FILE_GROUPS="dns_groups.csv"

# Configurações de Comportamento
TIMEOUT=5                     
VALIDATE_CONNECTIVITY="true"  
GENERATE_HTML="true"
GENERATE_LOG_TEXT="false"     
SLEEP=0.05                    
VERBOSE="false"               
IP_VERSION="ipv4"             
CHECK_BIND_VERSION="false"    

# Configurações de Ping
ENABLE_PING=true
PING_COUNT=4       
PING_TIMEOUT=2      

# Controle de Interatividade
INTERACTIVE_MODE="true"

# Variáveis de Tempo e Stats
START_TIME_EPOCH=0
START_TIME_HUMAN=""
TOTAL_TESTS=0
SUCCESS_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# --- CORES DO TERMINAL ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m'

declare -A CONNECTIVITY_CACHE
declare -A HTML_CONN_ERR_LOGGED 

# Setup Arquivos
mkdir -p logs
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HTML_FILE="logs/${LOG_PREFIX}_${TIMESTAMP}.html"
LOG_FILE_TEXT="logs/${LOG_PREFIX}_${TIMESTAMP}.log"

# Arquivos Temporários
TEMP_HEADER="logs/temp_header_${TIMESTAMP}.html"
TEMP_STATS="logs/temp_stats_${TIMESTAMP}.html"
TEMP_TIMING="logs/temp_timing_${TIMESTAMP}.html"
TEMP_MATRIX="logs/temp_matrix_${TIMESTAMP}.html"
TEMP_PING="logs/temp_ping_${TIMESTAMP}.html"
TEMP_DETAILS="logs/temp_details_${TIMESTAMP}.html"
TEMP_CONFIG="logs/temp_config_${TIMESTAMP}.html"
TEMP_MODAL="logs/temp_modal_${TIMESTAMP}.html"

# ==============================================
# HELP & UTILS
# ==============================================

show_help() {
    echo -e "${BLUE}DNS DIAGNOSTIC TOOL - v13.1 (Bash)${NC}"
    echo -e "Uso: $0 [-n domains.csv] [-g groups.csv] [-l (log)] [-y (yes)]"
    echo -e "  -l: Gerar log de texto"
    echo -e "  -y: Modo não interativo"
    echo -e "  -v: Verbose (Debug na tela)"
}

# ==============================================
# LOGGING (TEXTO)
# ==============================================

init_log_file() {
    [[ "$GENERATE_LOG_TEXT" != "true" ]] && return
    local sys_user=$(whoami); local sys_host=$(hostname)
    {
        echo "################################################################################"
        echo "# DNS DIAGNOSTIC TOOL - FORENSIC LOG"
        echo "# Date: $(date +"%d/%m/%Y %H:%M:%S")"
        echo "# User: $sys_user @ $sys_host"
        echo "################################################################################"
        echo "[CONFIG] Timeout: ${TIMEOUT}s | Ping: ${ENABLE_PING} | Conn Check: ${VALIDATE_CONNECTIVITY}"
        echo "================================================================================"
        echo ">>> INICIANDO TESTES DNS"
        echo "================================================================================"
    } > "$LOG_FILE_TEXT"
}

log_cmd_result() {
    [[ "$GENERATE_LOG_TEXT" != "true" ]] && return
    local context="$1"
    local cmd="$2"
    local output="$3"
    local time="$4"
    {
        echo "--------------------------------------------------------------------------------"
        echo "CTX: $context"
        echo "CMD: $cmd"
        echo "TIME: ${time}ms"
        echo "OUTPUT:"
        echo "$output"
        echo "--------------------------------------------------------------------------------"
    } >> "$LOG_FILE_TEXT"
}

log_simple() {
    [[ "$GENERATE_LOG_TEXT" != "true" ]] && return
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >> "$LOG_FILE_TEXT"
}

# ==============================================
# NETWORK CORE
# ==============================================

check_port_bash() { timeout "$3" bash -c "cat < /dev/tcp/$1/$2" &>/dev/null; return $?; }

validate_connectivity() {
    local server="$1"
    local timeout="${2:-$TIMEOUT}"
    
    [[ -n "${CONNECTIVITY_CACHE[$server]}" ]] && return ${CONNECTIVITY_CACHE[$server]}
    
    local status=1
    if command -v nc &> /dev/null; then 
        nc -z -w "$timeout" "$server" 53 2>/dev/null; status=$?
    else 
        check_port_bash "$server" 53 "$timeout"; status=$?
    fi
    CONNECTIVITY_CACHE[$server]=$status
    if [[ "$status" -ne 0 ]]; then
        log_simple "CRITICAL: Falha de Conectividade TCP -> $server:53"
    fi
    return $status
}

# Função que faltava no Bash anterior:
get_bind_version() {
    local server="$1"
    local output
    output=$(dig +short +time=1 +tries=1 @"$server" chaos txt version.bind 2>/dev/null)
    output=$(echo "$output" | tr -d '"')
    if [[ -n "$output" ]]; then
        echo " (Ver: $output)"
    else
        echo ""
    fi
}

# ==============================================
# LÓGICA PRINCIPAL (Loop de Testes)
# ==============================================

process_tests() {
    [[ ! -f "$FILE_DOMAINS" ]] && { echo -e "${RED}ERRO: $FILE_DOMAINS não encontrado!${NC}"; exit 1; }
    
    # Carrega grupos para memória
    declare -A GROUP_SERVERS
    while IFS=';' read -r name desc type timeout servers || [ -n "$name" ]; do
        [[ "$name" =~ ^# || -z "$name" ]] && continue
        name=$(echo "$name" | xargs)
        servers=$(echo "$servers" | tr -d '[:space:]')
        GROUP_SERVERS["$name"]="$servers"
    done < "$FILE_GROUPS"

    local test_id=0
    
    while IFS=';' read -r domain groups test_types record_types extra_hosts || [ -n "$domain" ]; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        
        domain=$(echo "$domain" | xargs)
        groups=$(echo "$groups" | tr -d '[:space:]')
        IFS=',' read -ra group_list <<< "$groups"
        IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
        
        echo "<div class=\"domain-block\"><div class=\"domain-header\"><span>🌐 $domain</span><span class=\"badge\">$test_types</span></div>" >> "$TEMP_MATRIX"
        
        # Define Modos
        local modes=()
        if [[ "$test_types" == *"both"* ]]; then modes=("iterative" "recursive")
        elif [[ "$test_types" == *"recursive"* ]]; then modes=("recursive")
        else modes=("iterative"); fi
        
        for grp in "${group_list[@]}"; do
            [[ -z "${GROUP_SERVERS[$grp]}" ]] && continue
            local srv_list=(${GROUP_SERVERS[$grp]//,/ })
            
            echo "<div style=\"padding:8px; border-bottom:1px solid #444; background:#2d2d30; color:#9cdcfe;\">Grupo: $grp</div>" >> "$TEMP_MATRIX"
            echo "<table><thead><tr><th style=\"width:30%\">Target (Record)</th>" >> "$TEMP_MATRIX"
            for srv in "${srv_list[@]}"; do echo "<th>$srv</th>" >> "$TEMP_MATRIX"; done
            echo "</tr></thead><tbody>" >> "$TEMP_MATRIX"
            
            local targets=("$domain")
            for ex in "${extra_list[@]}"; do targets+=("$ex.$domain"); done
            
            for mode in "${modes[@]}"; do
                for target in "${targets[@]}"; do
                    for rec in "${rec_list[@]}"; do
                        echo "<tr><td><span class=\"badge\">$mode</span> <strong>$target</strong> <span style=\"color:#666\">($rec)</span></td>" >> "$TEMP_MATRIX"
                        
                        for srv in "${srv_list[@]}"; do
                            test_id=$((test_id + 1))
                            TOTAL_TESTS=$((TOTAL_TESTS + 1))
                            local unique_id="test_${test_id}"
                            
                            # 1. Validação Conexão
                            if [[ "$VALIDATE_CONNECTIVITY" == "true" ]]; then
                                if ! validate_connectivity "$srv"; then
                                    FAILED_TESTS=$((FAILED_TESTS + 1))
                                    local conn_id="conn_err_${srv//./_}"
                                    echo "<td><a href=\"#\" onclick=\"showLog('$conn_id'); return false;\" class=\"cell-link status-fail\">❌ DOWN</a></td>" >> "$TEMP_MATRIX"
                                    if [[ -z "${HTML_CONN_ERR_LOGGED[$srv]}" ]]; then
                                        echo "<details id=\"$conn_id\" class=\"conn-error-block\"><summary class=\"log-header\" style=\"color:#f44747\"><strong>FALHA CONEXÃO</strong> - $srv</summary><pre>Porta 53 inalcançável (TCP).</pre></details>" >> "$TEMP_DETAILS"
                                        HTML_CONN_ERR_LOGGED[$srv]=1
                                    fi
                                    echo -ne "${RED}x${NC}"
                                    continue
                                fi
                            fi
                            
                            # 2. Execução DIG
                            local opts=""
                            if [[ "$mode" == "iterative" ]]; then opts="$DIG_OPTS_ITERATIVE"; else opts="$DIG_OPTS_RECURSIVE"; fi
                            [[ "$IP_VERSION" == "ipv4" ]] && opts="$opts -4"
                            
                            local cmd="dig $opts @$srv $target $rec"
                            local start_ts=$(date +%s%N)
                            local output
                            output=$(eval "$cmd" 2>&1)
                            local ret=$?
                            local end_ts=$(date +%s%N)
                            local dur=$(( (end_ts - start_ts) / 1000000 ))

                            # 2.1 Verifica Versão Bind (Se ativado)
                            local bind_ver_str=""
                            if [[ "$CHECK_BIND_VERSION" == "true" ]]; then
                                bind_ver_str=$(get_bind_version "$srv")
                            fi
                            
                            # 3. Análise de Resposta (PARIDADE PYTHON V13)
                            local answer_count=$(echo "$output" | grep -o "ANSWER: [0-9]*" | awk '{print $2}')
                            [[ -z "$answer_count" ]] && answer_count=0
                            
                            local status_txt="OK"; local css="status-ok"; local icon="✅"
                            
                            if [[ $ret -ne 0 ]]; then
                                status_txt="ERR:$ret"; css="status-fail"; icon="❌"; FAILED_TESTS=$((FAILED_TESTS + 1)); echo -ne "${RED}x${NC}"
                            elif echo "$output" | grep -q "status: SERVFAIL"; then
                                status_txt="SERVFAIL"; css="status-warning"; icon="⚠️"; WARNING_TESTS=$((WARNING_TESTS + 1)); echo -ne "${YELLOW}!${NC}"
                            elif echo "$output" | grep -q "status: NXDOMAIN"; then
                                status_txt="NXDOMAIN"; css="status-warning"; icon="🔸"; WARNING_TESTS=$((WARNING_TESTS + 1)); echo -ne "${YELLOW}!${NC}"
                            elif echo "$output" | grep -q "status: REFUSED"; then
                                status_txt="REFUSED"; css="status-fail"; icon="⛔"; FAILED_TESTS=$((FAILED_TESTS + 1)); echo -ne "${RED}x${NC}"
                            elif echo "$output" | grep -q "connection timed out"; then
                                status_txt="TIMEOUT"; css="status-fail"; icon="⏳"; FAILED_TESTS=$((FAILED_TESTS +
