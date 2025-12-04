#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS - BASH EDITION
# Versão: 13.0 (Logic Parity with Python v13)
# ==============================================

# --- CONFIGURAÇÕES PADRÃO ---

# [CORREÇÃO] Definição explícita de flags para evitar ambiguidade
DIG_OPTS_ITERATIVE="+norecurse +time=3 +tries=2 +nocookie +cd +bufsize=512"
DIG_OPTS_RECURSIVE="+recurse +time=3 +tries=2 +nocookie +cd +bufsize=512"

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
    echo -e "${BLUE}DNS DIAGNOSTIC TOOL - v13.0 (Bash)${NC}"
    echo -e "Uso: $0 [-n domains.csv] [-g groups.csv] [-l (log)] [-y (yes)]"
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

# ==============================================
# LÓGICA PRINCIPAL (Loop de Testes)
# ==============================================

process_tests() {
    [[ ! -f "$FILE_DOMAINS" ]] && { echo -e "${RED}ERRO: $FILE_DOMAINS não encontrado!${NC}"; exit 1; }
    
    # [CORREÇÃO] Carrega grupos para memória para acesso rápido
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
                            
                            # 3. Análise de Resposta (LÓGICA CORRIGIDA)
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
                                status_txt="TIMEOUT"; css="status-fail"; icon="⏳"; FAILED_TESTS=$((FAILED_TESTS + 1)); echo -ne "${RED}x${NC}"
                            elif echo "$output" | grep -q "status: NOERROR"; then
                                # [CORREÇÃO CRÍTICA] NOERROR com 0 respostas é ALERTA (NOANSWER)
                                if [[ "$answer_count" -eq 0 ]]; then
                                    status_txt="NOANSWER"; css="status-warning"; icon="⚠️"; WARNING_TESTS=$((WARNING_TESTS + 1)); echo -ne "${YELLOW}!${NC}"
                                else
                                    SUCCESS_TESTS=$((SUCCESS_TESTS + 1)); echo -ne "${GREEN}.${NC}"
                                fi
                            else
                                status_txt="UNKNOWN"; css="status-warning"; icon="❓"; WARNING_TESTS=$((WARNING_TESTS + 1)); echo -ne "${YELLOW}?${NC}"
                            fi
                            
                            # Logging
                            echo "<td><a href=\"#\" onclick=\"showLog('$unique_id'); return false;\" class=\"cell-link $css\">$icon $status_txt <span class=\"time-badge\">${dur}ms</span></a></td>" >> "$TEMP_MATRIX"
                            
                            local log_col=""
                            [[ "$css" == "status-fail" ]] && log_col="color:#f44747"
                            [[ "$css" == "status-warning" ]] && log_col="color:#ffcc02"
                            
                            local safe_out=$(echo "$output" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                            echo "<details id=\"$unique_id\"><summary class=\"log-header\"><span class=\"log-id\">#$test_id</span> <span style=\"$log_col\">$status_txt</span> <strong>$srv</strong> &rarr; $target ($rec) <span class=\"badge\">${dur}ms</span></summary><pre>$cmd"$'\n\n'"$safe_out</pre></details>" >> "$TEMP_DETAILS"
                            
                            log_cmd_result "TEST #$test_id ($mode) - $srv -> $target" "$cmd" "$output" "$dur"
                            [[ "$SLEEP" != "0" ]] && sleep "$SLEEP"
                        done
                    done
                done
            done
            echo "</tbody></table>" >> "$TEMP_MATRIX"
        done
        echo "</div>" >> "$TEMP_MATRIX"
    done < "$FILE_DOMAINS"
}

# ==============================================
# PING (IDÊNTICO AO PYTHON)
# ==============================================

run_ping_diagnostics() {
    [[ "$ENABLE_PING" != "true" ]] && return
    echo -e "\n${BLUE}Iniciando Ping Tests...${NC}"
    
    # Coleta IPs únicos
    local ips=""
    while IFS=';' read -r name d t tm servers || [ -n "$name" ]; do
        [[ "$name" =~ ^# ]] && continue
        ips="$ips ${servers//,/ }"
    done < "$FILE_GROUPS"
    local unique_ips=$(echo "$ips" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    
    for ip in $unique_ips; do
        [[ -z "$ip" ]] && continue
        local st="✅ UP"
        local cls="status-ok"
        local ms="0"
        
        # Ping com timeout seguro
        local output
        output=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$ip" 2>&1)
        local ret=$?
        
        if [[ $ret -ne 0 ]]; then
            st="❌ DOWN"; cls="status-fail"
            echo -e "  Ping $ip: ${RED}DOWN${NC}"
        else
            ms=$(echo "$output" | awk -F '/' '/rtt/ {print $5}')
            [[ -z "$ms" ]] && ms="0"
            echo -e "  Ping $ip: ${GREEN}UP${NC}"
        fi
        
        echo "<tr><td>$ip</td><td class=\"$cls\">$st</td><td>${ms}ms</td></tr>" >> "$TEMP_PING"
        log_simple "PING TEST | $ip | $st | ${ms}ms"
    done
}

# ==============================================
# GERAÇÃO HTML & MAIN
# ==============================================

write_html() {
    cat > "$TEMP_HEADER" << EOF
<!DOCTYPE html><html><head><meta charset='UTF-8'><title>DNS Report</title>
<style>
body{font-family:'Segoe UI',sans-serif;background:#1e1e1e;color:#d4d4d4;padding:20px} .container{max-width:1400px;margin:0 auto} 
.card{background:#252526;padding:15px;border-radius:6px;text-align:center;border-bottom:3px solid #444} 
.card-num{font-size:2em;font-weight:bold;display:block} .dashboard{display:grid;grid-template-columns:repeat(4,1fr);gap:15px}
.st-ok .card-num{color:#4ec9b0} .st-fail .card-num{color:#f44747} .st-warn .card-num{color:#ffcc02}
table{width:100%;border-collapse:collapse} th,td{padding:8px;border-bottom:1px solid #3e3e42} th{background:#2d2d30}
.status-ok{color:#4ec9b0} .status-fail{color:#f44747;background:rgba(244,71,71,0.1)} .status-warning{color:#ffcc02}
.modal{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.8);backdrop-filter:blur(2px)} 
.modal-content{background:#252526;margin:5% auto;width:80%;max-width:1000px;border:1px solid #444;padding:0;box-shadow:0 0 30px rgba(0,0,0,0.7)}
.modal-header{padding:15px;background:#333;display:flex;justify-content:space-between} .close-btn{cursor:pointer;font-size:24px}
.modal-body{padding:20px;max-height:70vh;overflow-y:auto}
pre{background:#000;color:#ccc;padding:15px;overflow-x:auto} details{background:#1e1e1e;border:1px solid #333;margin-bottom:5px} summary{padding:10px;cursor:pointer;background:#252526}
.log-header{display:flex;align-items:center;gap:10px} .badge{border:1px solid #444;padding:2px 5px;font-size:0.8em;border-radius:3px}
</style>
<script>
function showLog(id){document.getElementById('modalText').innerHTML=document.getElementById(id).querySelector('pre').innerHTML;document.getElementById('logModal').style.display='block'}
function closeModal(){document.getElementById('logModal').style.display='none'}
window.onclick=function(e){if(e.target==document.getElementById('logModal'))closeModal()}
document.addEventListener('keydown',function(e){if(e.key==='Escape')closeModal()})
</script>
</head><body>
<div id="logModal" class="modal"><div class="modal-content"><div class="modal-header"><strong>Log Detail</strong><span class="close-btn" onclick="closeModal()">&times;</span></div><div class="modal-body"><pre id="modalText"></pre></div></div>
<div class="container"><h1>📊 DNS Report (Bash)</h1>
<div class="dashboard">
<div class="card st-total"><span class="card-num">$TOTAL_TESTS</span>Total</div>
<div class="card st-ok"><span class="card-num">$SUCCESS_TESTS</span>Sucesso</div>
<div class="card st-warn"><span class="card-num">$WARNING_TESTS</span>Alertas</div>
<div class="card st-fail"><span class="card-num">$FAILED_TESTS</span>Falhas</div>
</div>
<div style="background:#252526;padding:10px;margin:20px 0;border-left:4px solid #666;font-family:monospace">
Início: $START_TIME_HUMAN &nbsp;|&nbsp; Fim: $END_TIME_HUMAN &nbsp;|&nbsp; Duração: ${TOTAL_DURATION}s
</div>
EOF

    cat "$TEMP_HEADER" > "$HTML_FILE"
    cat "$TEMP_MATRIX" >> "$HTML_FILE"
    
    if [[ -s "$TEMP_PING" ]]; then
        echo "<h2 style=\"margin-top:40px\">📡 Latência (Ping)</h2><table><thead><tr><th>Host</th><th>Status</th><th>Latência</th></tr></thead><tbody>" >> "$HTML_FILE"
        cat "$TEMP_PING" >> "$HTML_FILE"
        echo "</tbody></table>" >> "$HTML_FILE"
    fi
    
    echo "<h2 style=\"margin-top:40px\">🛠️ Logs Técnicos</h2>" >> "$HTML_FILE"
    cat "$TEMP_DETAILS" >> "$HTML_FILE"
    echo "</div></body></html>" >> "$HTML_FILE"
    
    rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS" "$TEMP_PING" "$TEMP_CONFIG" "$TEMP_TIMING" "$TEMP_MODAL"
}

main() {
    START_TIME_EPOCH=$(date +%s)
    START_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S")

    while getopts ":n:g:lhy" opt; do
        case ${opt} in
            n) FILE_DOMAINS=$OPTARG ;;
            g) FILE_GROUPS=$OPTARG ;;
            l) GENERATE_LOG_TEXT="true" ;;
            y) INTERACTIVE_MODE="false" ;;
            h) show_help; exit 0 ;;
            \?) echo "Opção inválida: -$OPTARG"; exit 1 ;;
        esac
    done
    
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo -e "${BLUE}=== CONFIGURAÇÃO INTERATIVA ===${NC}"
        read -p "  🔹 Gerar Log TXT (-l)? (s/N): " resp
        [[ "$resp" =~ ^[sS] ]] && GENERATE_LOG_TEXT="true"
    fi

    init_log_file
    
    # Limpa temps
    > "$TEMP_MATRIX"; > "$TEMP_DETAILS"; > "$TEMP_PING"

    echo -e "${BLUE}=== INICIANDO TESTES (BASH v13.0) ===${NC}"
    process_tests
    run_ping_diagnostics
    
    END_TIME_EPOCH=$(date +%s)
    END_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S")
    TOTAL_DURATION=$((END_TIME_EPOCH - START_TIME_EPOCH))
    
    write_html
    
    echo -e "\n${GREEN}=== SUCESSO ===${NC}"
    echo -e "Relatório HTML: ${CYAN}$HTML_FILE${NC}"
    [[ "$GENERATE_LOG_TEXT" == "true" ]] && echo -e "Relatório TXT : ${CYAN}$LOG_FILE_TEXT${NC}"
    echo -e "Stats: Total $TOTAL_TESTS | OK $SUCCESS_TESTS | Alertas $WARNING_TESTS | Falhas $FAILED_TESTS"
}

main "$@"
