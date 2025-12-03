#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS AVANÇADO (Remastered & Fixed)
# Versão: 2.2
# "Agora com 100% mais funções que funcionam."
# ==============================================

# Configurações padrão (Hardcoded caso o cfg falhe)
DEFAULT_DIG_OPTIONS="+norecurse +time=1 +tries=1 +nocookie +cd +bufsize=512"
RECURSIVE_DIG_OPTIONS="+time=1 +tries=1 +nocookie +cd +bufsize=512"
LOG_PREFIX="dnsdiag"
TIMEOUT=5
VALIDATE_CONNECTIVITY=true
GENERATE_HTML=true
GENERATE_JSON=false
SLEEP=0.5
VERBOSE=true
QUIET=false
MAX_RETRIES=1
RETRY_DELAY=1
IP_VERSION="ipv4"
CHECK_BIND_VERSION=false

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Cache de conectividade
declare -A CONNECTIVITY_CACHE

# Contadores
declare -i TOTAL_TESTS=0
declare -i SUCCESS_TESTS=0
declare -i FAILED_TESTS=0
declare -i TIMEOUT_TESTS=0
TEST_COUNTER=0

# Carregar config
if [[ -f "script_config.cfg" ]]; then
    source script_config.cfg
fi

# ==============================================
# SETUP DE DIRETÓRIOS E LOGS
# ==============================================
mkdir -p logs

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="logs/${LOG_PREFIX}_${TIMESTAMP}.txt"
HTML_FILE="logs/${LOG_PREFIX}_${TIMESTAMP}.html"
JSON_FILE="logs/${LOG_PREFIX}_${TIMESTAMP}.json"

# ==============================================
# FUNÇÕES DE INFRAESTRUTURA
# ==============================================

check_port_bash() {
    local host=$1
    local port=$2
    local timeout=$3
    timeout "$timeout" bash -c "cat < /dev/tcp/$host/$port" &>/dev/null
    return $?
}

validate_connectivity() {
    local server="$1"
    local timeout="${2:-$TIMEOUT}"
    
    if [[ -n "${CONNECTIVITY_CACHE[$server]}" ]]; then
        return ${CONNECTIVITY_CACHE[$server]}
    fi
    
    log_verbose "Testando TCP/53 em $server..."
    
    local status=1
    if command -v nc &> /dev/null; then
        nc -z -w "$timeout" "$server" 53 2>/dev/null
        status=$?
    else
        check_port_bash "$server" 53 "$timeout"
        status=$?
    fi

    if [[ $status -eq 0 ]]; then
        CONNECTIVITY_CACHE[$server]=0
        return 0
    else
        CONNECTIVITY_CACHE[$server]=1
        return 1
    fi
}

validate_csv_file() {
    local csv_file="$1"
    local expected_columns="$2"
    
    if [[ ! -s "$csv_file" ]]; then
        log_color "$RED" "CRÍTICO: O arquivo $csv_file sumiu ou está vazio." "error"
        return 1
    fi
    
    # Pega primeira linha que não seja comentário E não seja vazia
    local first_line=$(grep -vE "^#|^$" "$csv_file" | head -1)
    
    if [[ -z "$first_line" ]]; then
         log_color "$YELLOW" "AVISO: $csv_file parece conter apenas comentários ou linhas vazias." "warning"
         return 0
    fi

    local actual_columns=$(echo "$first_line" | awk -F';' '{print NF}')
    
    if [[ $actual_columns -lt $expected_columns ]]; then
        log_color "$YELLOW" "AVISO: $csv_file parece ter menos colunas ($actual_columns) que o esperado ($expected_columns). Verifique os delimitadores (;)." "warning"
    fi
    return 0
}

json_escape() {
    echo "$1" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g'
}

# ==============================================
# REPORTING E LOGS (Agora completas!)
# ==============================================

# Inicializa HTML Report
init_html_report() {
    [[ "$GENERATE_HTML" != "true" ]] && return
    cat > "$HTML_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>DNS Report - $TIMESTAMP</title>
    <style>
        body { font-family: 'Segoe UI', monospace; background: #1e1e1e; color: #d4d4d4; margin: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        .success { color: #4ec9b0; } .error { color: #f44747; } .warning { color: #ffcc02; }
        .section { border-bottom: 2px solid #ce9178; padding: 10px 0; margin: 20px 0; color: #ce9178; font-weight: bold;}
        .test-header { background: #2d2d30; padding: 10px; margin: 10px 0; border-left: 4px solid #007acc; border-radius: 4px; }
        .dig-output { background: #000; padding: 10px; border: 1px solid #333; font-family: monospace; font-size: 0.85em; white-space: pre-wrap; color: #ccc; }
        .stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin: 20px 0; }
        .stat-box { background: #333; padding: 15px; text-align: center; border-radius: 5px; }
        .stat-val { font-size: 1.5em; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Relatório de Diagnóstico DNS</h1>
        <div class="stats-grid">
            <div class="stat-box">TIMESTAMP<br>$TIMESTAMP</div>
            <div class="stat-box">LOG FILE<br>$(basename "$LOG_FILE")</div>
        </div>
EOF
}

html_log() {
    [[ "$GENERATE_HTML" == "true" ]] && echo "<div class=\"$2\">$1</div>" >> "$HTML_FILE"
}

html_log_section() {
    [[ "$GENERATE_HTML" == "true" ]] && echo "<div class=\"section\">$1</div>" >> "$HTML_FILE"
}

html_log_test() {
    local num=$1; local msg=$2
    [[ "$GENERATE_HTML" == "true" ]] && echo "<div class=\"test-header\"><strong>#$num</strong> - $msg</div>" >> "$HTML_FILE"
}

# Funções de Log do Terminal/Arquivo
log() {
    if [[ "$QUIET" == "false" ]]; then
        local message="$(date '+%H:%M:%S') - $1"
        echo "$message" | tee -a "$LOG_FILE"
        html_log "$message" "info"
    fi
}

log_color() {
    if [[ "$QUIET" == "false" ]]; then
        local color=$1
        local message=$2
        local class=$3
        echo -e "${color}$(date '+%H:%M:%S') - ${message}${NC}" | tee -a "$LOG_FILE"
        html_log "$(date '+%H:%M:%S') - $message" "${class:-info}"
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}[DEBUG] $1${NC}"
    fi
}

# AS FUNÇÕES PERDIDAS FORAM REENCONTRADAS AQUI:
log_section() {
    if [[ "$QUIET" == "false" ]]; then
        echo -e "${YELLOW}================================================================${NC}" | tee -a "$LOG_FILE"
        echo -e "${YELLOW}$(date '+%H:%M:%S') - $1${NC}" | tee -a "$LOG_FILE"
        echo -e "${YELLOW}================================================================${NC}" | tee -a "$LOG_FILE"
    fi
    html_log_section "$(date '+%H:%M:%S') - $1"
}

log_test() {
    local test_num=$1
    local msg=$2
    if [[ "$QUIET" == "false" ]]; then
        echo -e "${BLUE}$(date '+%H:%M:%S') - #${test_num} - ${msg}${NC}" | tee -a "$LOG_FILE"
    fi
    html_log_test "$test_num" "$msg"
}

finalize_html_report() {
    [[ "$GENERATE_HTML" != "true" ]] && return
    
    local p_succ=0
    local p_fail=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        p_succ=$(( (SUCCESS_TESTS * 100) / TOTAL_TESTS ))
        p_fail=$(( (FAILED_TESTS * 100) / TOTAL_TESTS ))
    fi

    cat >> "$HTML_FILE" << EOF
        <div class="section">ESTATÍSTICAS FINAIS</div>
        <div class="stats-grid">
            <div class="stat-box">TOTAL<br><span class="stat-val">$TOTAL_TESTS</span></div>
            <div class="stat-box" style="border-bottom: 3px solid #4ec9b0">SUCESSO<br><span class="stat-val success">$SUCCESS_TESTS</span><br>($p_succ%)</div>
            <div class="stat-box" style="border-bottom: 3px solid #f44747">FALHA<br><span class="stat-val error">$FAILED_TESTS</span><br>($p_fail%)</div>
            <div class="stat-box">TIMEOUT<br><span class="stat-val warning">$TIMEOUT_TESTS</span></div>
        </div>
    </div>
</body>
</html>
EOF
}

update_statistics() {
    local exit_code=$1
    local dig_output="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [[ $exit_code -eq 0 ]]; then
        SUCCESS_TESTS=$((SUCCESS_TESTS + 1))
    elif echo "$dig_output" | grep -q "connection timed out"; then
        TIMEOUT_TESTS=$((TIMEOUT_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# ==============================================
# CORE DO SCRIPT
# ==============================================

load_dns_groups() {
    declare -gA DNS_GROUPS
    declare -gA DNS_GROUP_DESC
    declare -gA DNS_GROUP_TYPE
    declare -gA DNS_GROUP_TIMEOUT
    
    log_section "CARREGANDO GRUPOS DNS"
    
    if ! validate_csv_file "dns_groups.csv" 5; then exit 1; fi
    
    while IFS=';' read -r name description type timeout servers || [ -n "$name" ]; do
        name=$(echo "$name" | xargs)
        [[ "$name" =~ ^# ]] && continue
        [[ -z "$name" ]] && continue
        
        description=$(echo "$description" | xargs)
        type=$(echo "$type" | xargs)
        timeout=$(echo "$timeout" | xargs)
        servers=$(echo "$servers" | tr -d '[:space:]')
        
        [[ -z "$timeout" ]] && timeout=$TIMEOUT
        
        IFS=',' read -ra servers_array <<< "$servers"
        
        DNS_GROUPS["$name"]="${servers_array[@]}"
        DNS_GROUP_DESC["$name"]="$description"
        DNS_GROUP_TYPE["$name"]="$type"
        DNS_GROUP_TIMEOUT["$name"]="$timeout"
        
        log_color "$GREEN" "Grupo [$name]: ${#servers_array[@]} servers | Timeout: ${timeout}s" "success"
    done < dns_groups.csv
}

run_dig() {
    local server="$1"
    local domain="$2"
    local type="$3"
    local mode="$4"
    
    local opts
    [[ "$mode" == "iterative" ]] && opts="$DEFAULT_DIG_OPTIONS" || opts="$RECURSIVE_DIG_OPTIONS"
    
    [[ "$IP_VERSION" == "ipv4" ]] && opts="$opts -4"
    [[ "$IP_VERSION" == "ipv6" ]] && opts="$opts -6"
    
    local cmd="dig $opts @$server $domain $type"
    
    local output
    output=$(eval "$cmd" 2>&1)
    local ret=$?
    
    echo "CMD: $cmd" >> "$LOG_FILE"
    echo "$output" >> "$LOG_FILE"
    echo "RETURN: $ret" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"
    
    if [[ "$GENERATE_HTML" == "true" ]]; then
        echo "<div class=\"dig-output\"><strong>$cmd</strong><br>$output</div>" >> "$HTML_FILE"
    fi
    
    return $ret
}

process_tests() {
    log_section "INICIANDO BATERIA DE TESTES"
    
    if ! validate_csv_file "domains_tests.csv" 4; then exit 1; fi
    
    while IFS=';' read -r domain groups test_types record_types extra_hosts || [ -n "$domain" ]; do
        domain=$(echo "$domain" | xargs)
        [[ "$domain" =~ ^# ]] && continue
        [[ -z "$domain" ]] && continue
        
        groups=$(echo "$groups" | tr -d '[:space:]')
        IFS=',' read -ra group_list <<< "$groups"
        IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
        
        log_color "$BLUE" ">> Alvo: $domain (Grupos: $groups)" "info"
        
        local modes=()
        if [[ "$test_types" == *"both"* ]]; then modes=("iterative" "recursive")
        elif [[ "$test_types" == *"recursive"* ]]; then modes=("recursive")
        else modes=("iterative"); fi
        
        for grp in "${group_list[@]}"; do
            if [[ -z "${DNS_GROUPS[$grp]}" ]]; then
                log_color "$RED" "Erro: Grupo $grp não existe." "error"
                continue
            fi
            
            local srv_list=(${DNS_GROUPS[$grp]})
            local g_type=${DNS_GROUP_TYPE[$grp]}
            local g_time=${DNS_GROUP_TIMEOUT[$grp]}
            
            for mode in "${modes[@]}"; do
                if [[ "$g_type" == "authoritative" && "$mode" == "recursive" ]]; then continue; fi
                if [[ "$g_type" == "recursive" && "$mode" == "iterative" ]]; then continue; fi
                
                for rec in "${rec_list[@]}"; do
                    for srv in "${srv_list[@]}"; do
                        
                        if [[ "$VALIDATE_CONNECTIVITY" == "true" ]]; then
                            if ! validate_connectivity "$srv" "$g_time"; then
                                log_color "$RED" "DOWN: $srv não responde na porta 53." "error"
                                FAILED_TESTS=$((FAILED_TESTS + 1))
                                continue
                            fi
                        fi
                        
                        TEST_COUNTER=$((TEST_COUNTER + 1))
                        log_test "$TEST_COUNTER" "$grp | $mode | $srv -> $domain ($rec)"
                        
                        run_dig "$srv" "$domain" "$rec" "$mode"
                        update_statistics $? "ignored_in_this_context"
                        
                        for extra in "${extra_list[@]}"; do
                            local full="$extra.$domain"
                            TEST_COUNTER=$((TEST_COUNTER + 1))
                            log_test "$TEST_COUNTER" "$grp | $mode | $srv -> $full ($rec)"
                            run_dig "$srv" "$full" "$rec" "$mode"
                            update_statistics $? "ignored_in_this_context"
                        done
                    done
                done
            done
        done
        [[ "$SLEEP" != "0" ]] && sleep "$SLEEP"
    done < domains_tests.csv
}

generate_json_report() {
    [[ "$GENERATE_JSON" != "true" ]] && return
    
    log_color "$CYAN" "Gerando JSON..." "info"
    
    cat > "$JSON_FILE" << EOF
{
    "metadata": {
        "timestamp": "$TIMESTAMP",
        "total_tests": $TOTAL_TESTS
    },
    "statistics": {
        "success": $SUCCESS_TESTS,
        "failed": $FAILED_TESTS,
        "timeout": $TIMEOUT_TESTS
    },
    "groups_config": [
EOF
    
    local first=true
    for grp in "${!DNS_GROUPS[@]}"; do
        $first || echo "," >> "$JSON_FILE"
        first=false
        
        local srvs="${DNS_GROUPS[$grp]}"
        local srv_json=$(echo "$srvs" | sed 's/ /", "/g')
        local desc_safe=$(json_escape "${DNS_GROUP_DESC[$grp]}")
        
        cat >> "$JSON_FILE" << EOF
        {
            "name": "$grp",
            "description": "$desc_safe",
            "servers": ["$srv_json"]
        }
EOF
    done
    echo "    ] }" >> "$JSON_FILE"
}

# ==============================================
# MAIN
# ==============================================

main() {
    if ! command -v dig &> /dev/null; then
        echo -e "${RED}ERRO FATAL: Instale 'dnsutils' ou 'bind-utils'. Sem 'dig', sem festa.${NC}"
        exit 1
    fi

    init_html_report
    load_dns_groups
    process_tests
    generate_json_report
    finalize_html_report
    
    log_section "FIM DO SOFRIMENTO"
    echo -e "${GREEN}Logs salvos em: logs/${NC}"
    echo -e "${WHITE}Relatório HTML: ${HTML_FILE}${NC}"
}

main "$@"