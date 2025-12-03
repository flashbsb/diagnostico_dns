#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS - COMPLETE DASHBOARD
# Versão: 8.9 (Log Edition)
# "Agora com provas em .txt para quem não gosta de HTML"
# ==============================================

# --- CONFIGURAÇÕES PADRÃO ---

# Opções padrão do DIG (Iterativo/Authoritative)
DEFAULT_DIG_OPTIONS="+norecurse +time=1 +tries=1 +nocookie +cd +bufsize=512"

# Opções para testes Recursivos
RECURSIVE_DIG_OPTIONS="+time=1 +tries=1 +nocookie +cd +bufsize=512"

# Prefixo e Arquivos
LOG_PREFIX="dnsdiag"
FILE_DOMAINS="domains_tests.csv"
FILE_GROUPS="dns_groups.csv"

# Configurações de Comportamento
TIMEOUT=5                     # Timeout global de conexão (segundos)
VALIDATE_CONNECTIVITY="true"  # Validar porta 53 antes do dig?
GENERATE_HTML="true"
GENERATE_LOG_TEXT="false"     # Default: não gerar log de texto (ativado com -l)
SLEEP=0.05                    # Intervalo entre testes
VERBOSE="false"               # Exibir logs detalhados na tela
IP_VERSION="ipv4"             # ipv4, ipv6 ou both
MAX_RETRIES=3                 # Número de tentativas lógicas
CHECK_BIND_VERSION="false"    # Tentar descobrir versão do BIND

# Configurações de Ping
ENABLE_PING=true
PING_COUNT=10       # Quantos pacotes enviar
PING_TIMEOUT=2      # Timeout por pacote (segundos)

# Controle de Interatividade
INTERACTIVE_MODE="true"

# Variáveis de Tempo
START_TIME_EPOCH=0
START_TIME_HUMAN=""
END_TIME_EPOCH=0
END_TIME_HUMAN=""
TOTAL_SLEEP_TIME=0
TOTAL_DURATION=0

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
declare -i TOTAL_TESTS=0
declare -i SUCCESS_TESTS=0
declare -i FAILED_TESTS=0
declare -i WARNING_TESTS=0

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

# ==============================================
# HELP & BANNER
# ==============================================

show_help() {
    echo -e "${BLUE}Diagnóstico DNS Avançado - v8.9${NC}"
    echo -e "Uso: $0 [opções]"
    echo -e "Opções:"
    echo -e "  ${GREEN}-n <arquivo>${NC}   Arquivo de domínios (Default: domains_tests.csv)"
    echo -e "  ${GREEN}-g <arquivo>${NC}   Arquivo de grupos (Default: dns_groups.csv)"
    echo -e "  ${GREEN}-l${NC}            Gerar log de texto detalhado (.log)"
    echo -e "  ${GREEN}-y${NC}            Execução não interativa (Aceita defaults)"
    echo -e "  ${GREEN}-h${NC}            Ajuda"
}

print_execution_summary() {
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}       DIAGNÓSTICO DNS - DASHBOARD DE EXECUÇÃO        ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${PURPLE}[ARQUIVOS]${NC}"
    echo -e "  📂 Domínios      : ${YELLOW}$FILE_DOMAINS${NC}"
    echo -e "  📂 Grupos DNS    : ${YELLOW}$FILE_GROUPS${NC}"
    echo ""
    echo -e "${PURPLE}[REDE & PERFORMANCE]${NC}"
    echo -e "  ⏱️  Timeout Global: ${CYAN}${TIMEOUT}s${NC}"
    echo -e "  💤 Sleep (Interv): ${CYAN}${SLEEP}s${NC}"
    echo -e "  📡 Valida Conexão: ${CYAN}${VALIDATE_CONNECTIVITY}${NC}"
    echo -e "  🌐 Versão IP     : ${CYAN}${IP_VERSION}${NC}"
    echo -e "  🏓 Ping Check    : ${CYAN}${ENABLE_PING} (Count: $PING_COUNT, Timeout: ${PING_TIMEOUT}s)${NC}"
    echo ""
    echo -e "${PURPLE}[DEBUG & CONTROLE]${NC}"
    echo -e "  📢 Verbose Mode  : ${CYAN}${VERBOSE}${NC}"
    echo -e "  📝 Gerar Log TXT : ${CYAN}${GENERATE_LOG_TEXT}${NC}"
    echo -e "  🛠️  Dig Options   : ${GRAY}${DEFAULT_DIG_OPTIONS}${NC}"
    echo -e "  🔁 Rec Dig Opts  : ${GRAY}${RECURSIVE_DIG_OPTIONS}${NC}"
    echo ""
    echo -e "${PURPLE}[SAÍDA]${NC}"
    echo -e "  📄 Relatório HTML: ${GREEN}$HTML_FILE${NC}"
    [[ "$GENERATE_LOG_TEXT" == "true" ]] && echo -e "  📄 Log Texto     : ${GREEN}$LOG_FILE_TEXT${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo ""
}

# ==============================================
# LOGGING (TEXTO)
# ==============================================

log_entry() {
    # Só escreve se a flag -l foi ativada
    [[ "$GENERATE_LOG_TEXT" != "true" ]] && return
    
    local msg="$1"
    local ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[$ts] $msg" >> "$LOG_FILE_TEXT"
}

log_cmd_result() {
    # Helper para logar comando + output + tempo
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

# ==============================================
# INTERATIVIDADE & CONFIGURAÇÃO
# ==============================================

ask_variable() {
    local prompt_text="$1"
    local var_name="$2"
    local current_val="${!var_name}"
    echo -ne "  🔹 $prompt_text [${CYAN}$current_val${NC}]: "
    read -r user_input
    if [[ -n "$user_input" ]]; then
        eval "$var_name=\"$user_input\""
        echo -e "     ${YELLOW}>> Atualizado para: $user_input${NC}"
    fi
}

ask_boolean() {
    local prompt_text="$1"
    local var_name="$2"
    local current_val="${!var_name}"
    echo -ne "  🔹 $prompt_text (0=false, 1=true) [${CYAN}$current_val${NC}]: "
    read -r user_input
    if [[ -n "$user_input" ]]; then
        case "$user_input" in
            1|true|True|TRUE|s|S) eval "$var_name=\"true\""; echo -e "     ${YELLOW}>> Atualizado para: true${NC}" ;;
            0|false|False|FALSE|n|N) eval "$var_name=\"false\""; echo -e "     ${YELLOW}>> Atualizado para: false${NC}" ;;
            *) echo -e "     ${RED}⚠️  Entrada inválida. Mantendo valor atual: $current_val${NC}" ;;
        esac
    fi
}

interactive_configuration() {
    if [[ "$INTERACTIVE_MODE" == "false" ]]; then return; fi
    print_execution_summary
    echo -ne "${YELLOW}❓ Deseja iniciar com as configurações acima? [S/n]: ${NC}"
    read -r response
    response=${response,,}
    if [[ "$response" == "n" || "$response" == "nao" || "$response" == "não" ]]; then
        echo -e "\n${BLUE}--- DEFINIÇÃO DE VARIÁVEIS DE EXECUÇÃO ---${NC}"
        echo -e "${GRAY}(Pressione ENTER para manter o valor padrão)${NC}\n"
        ask_variable "Timeout Global (segundos)" "TIMEOUT"
        ask_variable "Sleep entre testes (segundos)" "SLEEP"
        ask_boolean "Validar conectividade porta 53?" "VALIDATE_CONNECTIVITY"
        ask_variable "Versão IP (ipv4/ipv6/both)" "IP_VERSION"
        ask_boolean "Verbose Debug no terminal?" "VERBOSE"
        ask_boolean "Gerar arquivo .log (texto)?" "GENERATE_LOG_TEXT"
        ask_boolean "Tentar descobrir versão BIND?" "CHECK_BIND_VERSION"
        ask_boolean "Ativar Ping ICMP?" "ENABLE_PING"
        if [[ "$ENABLE_PING" == "true" ]]; then
            ask_variable "Qtd Pacotes Ping" "PING_COUNT"
            ask_variable "Timeout do Ping (segundos)" "PING_TIMEOUT"
        fi
        echo -e "\n${GREEN}Configurações atualizadas!${NC}"
        echo -e "${BLUE}------------------------------------------${NC}\n"
        print_execution_summary
    fi
}

# ==============================================
# INFRA & DEBUG PRINT
# ==============================================

check_port_bash() { timeout "$3" bash -c "cat < /dev/tcp/$1/$2" &>/dev/null; return $?; }

validate_connectivity() {
    local server="$1"
    local timeout="${2:-$TIMEOUT}"
    
    # Se já logou no cache, retorna direto
    [[ -n "${CONNECTIVITY_CACHE[$server]}" ]] && return ${CONNECTIVITY_CACHE[$server]}
    
    local status=1
    local cmd_used=""
    
    if command -v nc &> /dev/null; then 
        cmd_used="nc -z -w $timeout $server 53"
        nc -z -w "$timeout" "$server" 53 2>/dev/null; status=$?
    else 
        cmd_used="bash /dev/tcp/$server/53 (timeout $timeout)"
        check_port_bash "$server" 53 "$timeout"; status=$?
    fi
    
    CONNECTIVITY_CACHE[$server]=$status
    
    if [[ "$status" -ne 0 ]]; then
        log_entry "FALHA CONECTIVIDADE: $server:53 (CMD: $cmd_used) - Retorno: $status"
    fi
    
    return $status
}

print_verbose_debug() {
    local type="$1"; local msg="$2"; local srv="$3"; local target="$4"; local raw_output="$5"; local dur="$6"
    local color=$NC; local label=""
    case "$type" in "FAIL") color=$RED; label="FALHA CRÍTICA" ;; "WARN") color=$YELLOW; label="ALERTA/ATENÇÃO" ;; *) color=$CYAN; label="INFO" ;; esac
    echo -e "\n${color}    ┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${color}    │ [DEBUG] $label: $msg ${NC}"
    echo -e "${color}    ├─────────────────────────────────────────────────────────────┤${NC}"
    echo -e "    │ 🎯 Alvo    : $target"
    echo -e "    │ 🖥️  Server  : $srv"
    echo -e "    │ ⏱️  Tempo   : ${dur}ms"
    
    # Loga no arquivo também se estiver verbose
    log_entry "[VERBOSE] $label - $msg - Server: $srv - Target: $target - Dur: ${dur}ms"
    
    echo -e "${color}    └─────────────────────────────────────────────────────────────┘${NC}"
}

# ==============================================
# GERAÇÃO HTML (Mantida Igual)
# ==============================================

init_html_parts() { > "$TEMP_HEADER"; > "$TEMP_STATS"; > "$TEMP_MATRIX"; > "$TEMP_PING"; > "$TEMP_DETAILS"; > "$TEMP_CONFIG"; > "$TEMP_TIMING"; }

write_html_header() {
cat > "$TEMP_HEADER" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>DNS Report - $TIMESTAMP</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #1e1e1e; color: #d4d4d4; margin: 0; padding: 20px; }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { color: #ce9178; text-align: center; margin-bottom: 20px; }
        .dashboard { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 10px; }
        .card { background: #252526; padding: 15px; border-radius: 6px; text-align: center; border-bottom: 3px solid #444; }
        .card-num { font-size: 2em; font-weight: bold; display: block; }
        .card-label { font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; color: #888; }
        .st-total { border-color: #007acc; } .st-total .card-num { color: #007acc; }
        .st-ok { border-color: #4ec9b0; } .st-ok .card-num { color: #4ec9b0; }
        .st-warn { border-color: #ffcc02; } .st-warn .card-num { color: #ffcc02; }
        .st-fail { border-color: #f44747; } .st-fail .card-num { color: #f44747; }
        
        .timing-strip { background: #252526; padding: 10px; border-radius: 6px; border-left: 5px solid #666; margin-bottom: 30px; display: flex; justify-content: space-around; font-family: monospace; }
        .timing-item { text-align: center; }
        .timing-label { display: block; font-size: 0.8em; color: #888; margin-bottom: 3px; }
        .timing-val { font-weight: bold; color: #fff; }
        
        .domain-block { background: #252526; margin-bottom: 20px; border-radius: 6px; box-shadow: 0 4px 6px rgba(0,0,0,0.2); overflow: hidden; }
        .domain-header { background: #333; padding: 10px 15px; font-weight: bold; border-left: 5px solid #007acc; display: flex; justify-content: space-between; align-items: center; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid #3e3e42; font-size: 0.9em; }
        th { background: #2d2d30; color: #dcdcaa; }
        .cell-link { text-decoration: none; display: block; width: 100%; height: 100%; }
        .status-ok { color: #4ec9b0; }
        .status-warning { color: #ffcc02; }
        .status-fail { color: #f44747; font-weight: bold; background: rgba(244, 71, 71, 0.1); }
        .time-badge { font-size: 0.75em; color: #808080; margin-left: 5px; }
        
        .tech-section, .ping-section, .config-section { margin-top: 50px; border-top: 3px dashed #3e3e42; padding-top: 20px; }
        .tech-controls { margin-bottom: 15px; }
        .btn-ctrl { background: #3e3e42; color: white; border: none; padding: 5px 10px; border-radius: 3px; cursor: pointer; margin-right: 10px; font-size: 0.9em; }
        .btn-ctrl:hover { background: #007acc; }
        
        .config-table td { font-family: monospace; color: #9cdcfe; word-break: break-all; }
        .config-table th { width: 250px; }
        
        details { background: #1e1e1e; margin-bottom: 10px; border: 1px solid #333; border-radius: 4px; }
        summary { cursor: pointer; padding: 10px; background: #252526; list-style: none; font-family: monospace; }
        summary:hover { background: #2a2d2e; }
        summary::-webkit-details-marker { display: none; }
        .log-header { display: flex; align-items: center; gap: 10px; }
        .log-id { background: #007acc; color: white; padding: 2px 6px; border-radius: 3px; font-size: 0.8em; }
        pre { background: #000; color: #ccc; padding: 15px; margin: 0; overflow-x: auto; border-top: 1px solid #333; font-family: 'Consolas', monospace; font-size: 0.85em; }
        .badge { padding: 2px 5px; border-radius: 3px; font-size: 0.8em; border: 1px solid #444; }
        
        .conn-error-block summary { background: #2d0e0e; border-left: 3px solid #f44747; }
        .conn-error-block summary:hover { background: #3d1414; }
        
        .footer { margin-top: 40px; padding: 20px; border-top: 1px solid #333; text-align: center; color: #666; font-size: 0.9em; }
        .footer a { color: #007acc; text-decoration: none; transition: color 0.3s; }
        .footer a:hover { color: #4ec9b0; }
        .scroll-top { position: fixed; bottom: 20px; right: 20px; background: #007acc; color: white; padding: 10px; border-radius: 50%; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.5); }
    </style>
    <script>
        function toggleDetails(state) {
            const elements = document.querySelectorAll('details');
            elements.forEach(el => el.open = state);
        }
    </script>
</head>
<body>
    <div class="container">
        <h1>📊 Relatório de Diagnóstico DNS Executivo</h1>
        <a name="top"></a>
EOF
}

generate_stats_block() {
    local p_succ=0
    [[ $TOTAL_TESTS -gt 0 ]] && p_succ=$(( (SUCCESS_TESTS * 100) / TOTAL_TESTS ))
    
cat > "$TEMP_STATS" << EOF
        <div class="dashboard">
            <div class="card st-total">
                <span class="card-num">$TOTAL_TESTS</span>
                <span class="card-label">Total Testes</span>
            </div>
            <div class="card st-ok">
                <span class="card-num">$SUCCESS_TESTS</span>
                <span class="card-label">Sucesso ($p_succ%)</span>
            </div>
            <div class="card st-warn">
                <span class="card-num">$WARNING_TESTS</span>
                <span class="card-label">Alertas (NX/ServFail)</span>
            </div>
            <div class="card st-fail">
                <span class="card-num">$FAILED_TESTS</span>
                <span class="card-label">Falhas Críticas</span>
            </div>
        </div>
EOF
}

generate_timing_html() {
cat > "$TEMP_TIMING" << EOF
        <div class="timing-strip">
            <div class="timing-item">
                <span class="timing-label">Início</span>
                <span class="timing-val">$START_TIME_HUMAN</span>
            </div>
            <div class="timing-item">
                <span class="timing-label">Final</span>
                <span class="timing-val">$END_TIME_HUMAN</span>
            </div>
            <div class="timing-item">
                <span class="timing-label">Delay (Sleep) Adicionado</span>
                <span class="timing-val">${TOTAL_SLEEP_TIME}s</span>
            </div>
            <div class="timing-item">
                <span class="timing-label">Duração Total</span>
                <span class="timing-val">${TOTAL_DURATION}s</span>
            </div>
        </div>
EOF
}

generate_config_html() {
cat > "$TEMP_CONFIG" << EOF
        <div class="config-section">
             <h2>⚙️ Parâmetros de Execução</h2>
             <p style="color: #808080; margin-bottom: 20px;">Variáveis definidas durante o runtime.</p>
             <table class="config-table">
                <tbody>
                    <tr><th>Timeout Global</th><td>${TIMEOUT}s</td></tr>
                    <tr><th>Sleep (Intervalo)</th><td>${SLEEP}s</td></tr>
                    <tr><th>Valida Conectividade</th><td>${VALIDATE_CONNECTIVITY}</td></tr>
                    <tr><th>Versão IP</th><td>${IP_VERSION}</td></tr>
                    <tr><th>Check BIND Version</th><td>${CHECK_BIND_VERSION}</td></tr>
                    <tr><th>Iterative/Auth DIG Options</th><td>${DEFAULT_DIG_OPTIONS}</td></tr>
                    <tr><th>Recursive DIG Options</th><td>${RECURSIVE_DIG_OPTIONS}</td></tr>
                    <tr><th>Ping Enabled</th><td>${ENABLE_PING} (Count: ${PING_COUNT}, Timeout: ${PING_TIMEOUT}s)</td></tr>
                </tbody>
             </table>
        </div>
EOF
}

assemble_html() {
    generate_stats_block
    generate_timing_html
    generate_config_html
    
    cat "$TEMP_HEADER" >> "$HTML_FILE"
    cat "$TEMP_STATS" >> "$HTML_FILE"
    cat "$TEMP_TIMING" >> "$HTML_FILE" 
    cat "$TEMP_MATRIX" >> "$HTML_FILE"
    cat "$TEMP_CONFIG" >> "$HTML_FILE"
    
    if [[ -s "$TEMP_PING" ]]; then
        cat >> "$HTML_FILE" << EOF
        <div class="ping-section">
             <h2>📡 Latência e Disponibilidade (ICMP)</h2>
             <p style="color: #808080; margin-bottom: 20px;">Testes de ping realizados após a coleta DNS. Grupos identificados para facilitar sua vida.</p>
             <table><thead><tr><th>Grupo</th><th>Servidor</th><th>Status</th><th>Perda (%)</th><th>Latência Média</th></tr></thead><tbody>
EOF
        cat "$TEMP_PING" >> "$HTML_FILE"
        echo "</tbody></table></div>" >> "$HTML_FILE"
    fi

    cat >> "$HTML_FILE" << EOF
        <div class="tech-section">
            <div style="display:flex; justify-content:space-between; align-items:center;">
                <h2>🛠️ Logs Técnicos Detalhados (DNS)</h2>
                <div class="tech-controls">
                    <button class="btn-ctrl" onclick="toggleDetails(true)">➕ Expandir Todos</button>
                    <button class="btn-ctrl" onclick="toggleDetails(false)">➖ Recolher Todos</button>
                </div>
            </div>
            <p style="color: #808080; margin-bottom: 20px;">Clique nos itens da matriz (acima) ou use os botões para ver o output bruto.</p>
EOF
    cat "$TEMP_DETAILS" >> "$HTML_FILE"
    cat >> "$HTML_FILE" << EOF
        </div>
        <div class="footer">
            Gerado automaticamente por <strong>DNS Diagnostic Tool</strong><br>
            Repositório Oficial: <a href="https://github.com/flashbsb/diagnostico_dns" target="_blank">github.com/flashbsb/diagnostico_dns</a>
        </div>
    </div>
    <a href="#top" class="scroll-top">⬆️</a>
</body>
</html>
EOF
    rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS" "$TEMP_PING" "$TEMP_CONFIG" "$TEMP_TIMING"
}

# ==============================================
# LÓGICA PRINCIPAL (CORE)
# ==============================================

load_dns_groups() {
    declare -gA DNS_GROUPS
    declare -gA DNS_GROUP_DESC
    declare -gA DNS_GROUP_TYPE
    declare -gA DNS_GROUP_TIMEOUT
    
    [[ ! -f "$FILE_GROUPS" ]] && { echo -e "${RED}ERRO: $FILE_GROUPS não encontrado!${NC}"; exit 1; }

    while IFS=';' read -r name desc type timeout servers || [ -n "$name" ]; do
        [[ "$name" =~ ^# || -z "$name" ]] && continue
        name=$(echo "$name" | xargs); servers=$(echo "$servers" | tr -d '[:space:]')
        [[ -z "$timeout" ]] && timeout=$TIMEOUT
        IFS=',' read -ra srv_arr <<< "$servers"
        DNS_GROUPS["$name"]="${srv_arr[@]}"
        DNS_GROUP_DESC["$name"]="$desc"
        DNS_GROUP_TYPE["$name"]="$type"
        DNS_GROUP_TIMEOUT["$name"]="$timeout"
    done < "$FILE_GROUPS"
}

run_ping_diagnostics() {
    [[ "$ENABLE_PING" != "true" ]] && return
    
    echo -e "\n${BLUE}===========================================${NC}"
    echo -e "${BLUE}   INICIANDO TESTES DE LATÊNCIA (PING)   ${NC}"
    echo -e "${BLUE}===========================================${NC}"
    
    log_entry "--- INICIANDO TESTES DE LATENCIA (PING) ---"

    if ! command -v ping &> /dev/null; then
        echo -e "${RED}ERRO: Comando 'ping' não encontrado. Pulando etapa.${NC}"
        log_entry "ERRO: Comando 'ping' não encontrado."
        return
    fi

    declare -A CHECKED_IPS
    declare -A IP_GROUPS_MAP
    local unique_ips=()
    
    for grp in "${!DNS_GROUPS[@]}"; do
        for ip in ${DNS_GROUPS[$grp]}; do
            local grp_label="[$grp]"
            if [[ -z "${IP_GROUPS_MAP[$ip]}" ]]; then
                IP_GROUPS_MAP[$ip]="$grp_label"
            else
                if [[ "${IP_GROUPS_MAP[$ip]}" != *"$grp_label"* ]]; then
                    IP_GROUPS_MAP[$ip]="${IP_GROUPS_MAP[$ip]} $grp_label"
                fi
            fi
            if [[ -z "${CHECKED_IPS[$ip]}" ]]; then
                CHECKED_IPS[$ip]=1
                unique_ips+=("$ip")
            fi
        done
    done
    
    local ping_id=0
    for ip in "${unique_ips[@]}"; do
        ping_id=$((ping_id + 1))
        local groups_str="${IP_GROUPS_MAP[$ip]}"
        
        echo -ne "   📡 Pinging ${YELLOW}${groups_str}${NC} ${CYAN}$ip${NC}... "
        local output
        local ping_cmd="ping -c $PING_COUNT -W $PING_TIMEOUT $ip"
        local start_ts=$(date +%s%N)
        
        output=$(eval "$ping_cmd" 2>&1)
        local ret=$?
        
        local end_ts=$(date +%s%N)
        local dur=$(( (end_ts - start_ts) / 1000000 ))
        
        # Loga resultado no arquivo
        log_cmd_result "PING TEST $groups_str" "$ping_cmd" "$output" "$dur"
        
        local loss=$(echo "$output" | grep -oP '\d+(?=% packet loss)' | head -1)
        local rtt_avg=$(echo "$output" | awk -F '/' '/rtt/ {print $5}')
        
        if [[ -z "$loss" ]]; then loss=$(echo "$output" | grep -o "[0-9.]*% packet loss" | awk '{print $1}' | tr -d '%'); fi
        if [[ -z "$rtt_avg" ]]; then rtt_avg="N/A"; fi
        
        local status_html=""; local class_html=""; local console_res=""
        if [[ "$ret" -ne 0 ]] || [[ "$loss" == "100" ]]; then
            status_html="❌ DOWN"; class_html="status-fail"; loss="100"; console_res="${RED}DOWN (100% Loss)${NC}"
        elif [[ "$loss" != "0" ]]; then
            status_html="⚠️ UNSTABLE"; class_html="status-warning"; console_res="${YELLOW}${rtt_avg}ms (${loss}% Loss)${NC}"
        else
            status_html="✅ UP"; class_html="status-ok"; console_res="${GREEN}${rtt_avg}ms${NC}"
        fi
        
        echo -e "$console_res"
        echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td class=\"$class_html\">$status_html</td><td>${loss}%</td><td>${rtt_avg}ms</td></tr>" >> "$TEMP_PING"
        local safe_output=$(echo "$output" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        echo "<tr><td colspan=\"5\" style=\"padding:0; border:none;\"><details style=\"margin:5px;\"><summary style=\"font-size:0.8em; color:#888;\">Ver output bruto do ping #$ping_id</summary><pre>$safe_output</pre></details></td></tr>" >> "$TEMP_PING"
    done
    echo ""
}

process_tests() {
    [[ ! -f "$FILE_DOMAINS" ]] && { echo -e "${RED}ERRO: $FILE_DOMAINS não encontrado!${NC}"; exit 1; }

    echo -e "LEGENDA DE EXECUÇÃO:"
    echo -e "  ${GREEN}.${NC} = Sucesso (NOERROR)"
    echo -e "  ${YELLOW}!${NC} = Alerta (NXDOMAIN / SERVFAIL)"
    echo -e "  ${RED}x${NC} = Falha Crítica (TIMEOUT / REFUSED)"
    echo ""
    
    log_entry "--- INICIANDO TESTES DNS ---"
    local test_id=0
    
    while IFS=';' read -r domain groups test_types record_types extra_hosts || [ -n "$domain" ]; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        
        domain=$(echo "$domain" | xargs)
        groups=$(echo "$groups" | tr -d '[:space:]')
        IFS=',' read -ra group_list <<< "$groups"
        IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
        
        echo -e "${CYAN}>> Domínio: ${WHITE}${domain} ${PURPLE}[${record_types}] ${YELLOW}(${test_types})${NC}"
        log_entry "DOMINIO: $domain (Testes: $test_types | Rec: $record_types | Grupos: $groups)"

        local calc_count=0
        local calc_targets=("$domain")
        for ex in "${extra_list[@]}"; do calc_targets+=("$ex.$domain"); done
        
        local calc_modes=()
        if [[ "$test_types" == *"both"* ]]; then calc_modes=("iterative" "recursive")
        elif [[ "$test_types" == *"recursive"* ]]; then calc_modes=("recursive")
        else calc_modes=("iterative"); fi
        
        for grp in "${group_list[@]}"; do
            [[ -z "${DNS_GROUPS[$grp]}" ]] && continue
            local srv_list=(${DNS_GROUPS[$grp]})
            local num_srv=${#srv_list[@]}
            for mode in "${calc_modes[@]}"; do
                 for t in "${calc_targets[@]}"; do
                     for r in "${rec_list[@]}"; do calc_count=$((calc_count + num_srv)); done
                 done
            done
        done
        
        local start_id=$((test_id + 1))
        local end_id=$((test_id + calc_count))
        local range_txt="(Tests #$start_id - #$end_id)"
        [[ $calc_count -eq 0 ]] && range_txt=""
        
        echo "<div class=\"domain-block\"><div class=\"domain-header\"><span>🌐 $domain <span style=\"font-size:0.8em; color:#bbb; font-weight:normal; margin-left:10px;\">$range_txt</span></span><span class=\"badge\">$test_types</span></div>" >> "$TEMP_MATRIX"
        local modes=("${calc_modes[@]}")
        
        for grp in "${group_list[@]}"; do
            [[ -z "${DNS_GROUPS[$grp]}" ]] && continue
            local srv_list=(${DNS_GROUPS[$grp]})
            echo -ne "   [${PURPLE}${grp}${NC}] "
            echo "<div style=\"padding:10px; border-bottom:1px solid #333; background:#2d2d30; color:#9cdcfe;\">Grupo: $grp</div>" >> "$TEMP_MATRIX"
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
                            TOTAL_TESTS+=1
                            
                            # === VALIDAÇÃO CONEXÃO ===
                            if [[ "$VALIDATE_CONNECTIVITY" == "true" ]]; then
                                if ! validate_connectivity "$srv" "${DNS_GROUP_TIMEOUT[$grp]}"; then
                                    FAILED_TESTS+=1
                                    
                                    local conn_err_id="conn_err_${srv//./_}"
                                    echo "<td><a href=\"#$conn_err_id\" class=\"cell-link status-fail\">❌ DOWN</a></td>" >> "$TEMP_MATRIX"
                                    
                                    if [[ -z "${HTML_CONN_ERR_LOGGED[$srv]}" ]]; then
                                        echo "<details id=\"$conn_err_id\" class=\"conn-error-block\"><summary class=\"log-header\" style=\"color:#f44747\"><span class=\"log-id\">GLOBAL</span> <strong>FALHA DE CONEXÃO</strong> - Servidor: $srv</summary><pre style=\"border-top:1px solid #f44747; color:#f44747\">ERRO CRÍTICO DE CONECTIVIDADE:\n\nO servidor $srv não respondeu na porta 53 (TCP/UDP) durante o teste inicial.\nO script abortou todos os testes subsequentes para este servidor para economizar tempo.\n\nTimeout definido: ${DNS_GROUP_TIMEOUT[$grp]}s</pre></details>" >> "$TEMP_DETAILS"
                                        HTML_CONN_ERR_LOGGED[$srv]=1
                                    fi
                                    
                                    echo -ne "${RED}x${NC}"
                                    if [[ "$VERBOSE" == "true" ]]; then print_verbose_debug "FAIL" "Servidor não responde na porta 53" "$srv" "$target ($rec)" "" "N/A"; fi
                                    continue
                                fi
                            fi
                            
                            # === EXECUÇÃO DO DIG ===
                            local unique_id="test_${test_id}"
                            local bind_version_info=""
                            [[ "$CHECK_BIND_VERSION" == "true" ]] && bind_version_info=" (Ver: $(dig +short +time=1 @$srv chaos txt version.bind 2>/dev/null))"
                            local opts
                            [[ "$mode" == "iterative" ]] && opts="$DEFAULT_DIG_OPTIONS" || opts="$RECURSIVE_DIG_OPTIONS"
                            [[ "$IP_VERSION" == "ipv4" ]] && opts="$opts -4"
                            local cmd="dig $opts @$srv $target $rec"
                            local start_ts=$(date +%s%N)
                            local output
                            output=$(eval "$cmd" 2>&1)
                            local ret=$?
                            local end_ts=$(date +%s%N)
                            local dur=$(( (end_ts - start_ts) / 1000000 ))
                            
                            # Grava no log de texto se ativado
                            log_cmd_result "TEST #$test_id ($mode)" "$cmd" "$output" "$dur"
                            
                            local status_txt="OK"; local css_class="status-ok"; local icon="✅"
                            if [[ $ret -ne 0 ]]; then
                                status_txt="ERR:$ret"; css_class="status-fail"; icon="❌"; FAILED_TESTS+=1; echo -ne "${RED}x${NC}"
                                [[ "$VERBOSE" == "true" ]] && print_verbose_debug "FAIL" "Erro de Execução DIG (Code $ret)" "$srv" "$target ($rec)" "$output" "$dur"
                            elif echo "$output" | grep -q "status: SERVFAIL"; then
                                status_txt="SERVFAIL"; css_class="status-warning"; icon="⚠️"; WARNING_TESTS+=1; echo -ne "${YELLOW}!${NC}"
                                [[ "$VERBOSE" == "true" ]] && print_verbose_debug "WARN" "SERVFAIL (Falha no servidor)" "$srv" "$target ($rec)" "$output" "$dur"
                            elif echo "$output" | grep -q "status: NXDOMAIN"; then
                                status_txt="NXDOMAIN"; css_class="status-warning"; icon="🔸"; WARNING_TESTS+=1; echo -ne "${YELLOW}!${NC}"
                            elif echo "$output" | grep -q "status: REFUSED"; then
                                status_txt="REFUSED"; css_class="status-fail"; icon="⛔"; FAILED_TESTS+=1; echo -ne "${RED}x${NC}"
                                [[ "$VERBOSE" == "true" ]] && print_verbose_debug "FAIL" "REFUSED (Acesso negado/ACL)" "$srv" "$target ($rec)" "$output" "$dur"
                            elif echo "$output" | grep -q "connection timed out"; then
                                status_txt="TIMEOUT"; css_class="status-fail"; icon="⏳"; FAILED_TESTS+=1; echo -ne "${RED}x${NC}"
                                [[ "$VERBOSE" == "true" ]] && print_verbose_debug "FAIL" "TIMEOUT (Sem resposta)" "$srv" "$target ($rec)" "$output" "$dur"
                            else
                                SUCCESS_TESTS+=1; echo -ne "${GREEN}.${NC}"
                            fi
                            
                            echo "<td><a href=\"#$unique_id\" class=\"cell-link $css_class\">$icon $status_txt <span class=\"time-badge\">${dur}ms</span></a></td>" >> "$TEMP_MATRIX"
                            local safe_output=$(echo "$output" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                            local log_color_style=""
                            [[ "$css_class" == "status-fail" ]] && log_color_style="color:#f44747"
                            [[ "$css_class" == "status-warning" ]] && log_color_style="color:#ffcc02"
                            echo "<details id=\"$unique_id\"><summary class=\"log-header\"><span class=\"log-id\">#$test_id</span> <span style=\"$log_color_style\">$status_txt</span> <strong>$srv</strong> &rarr; $target ($rec) <span class=\"badge\">${dur}ms</span>$bind_version_info</summary><pre>$cmd"$'\n\n'"$safe_output</pre></details>" >> "$TEMP_DETAILS"
                            [[ "$SLEEP" != "0" ]] && sleep "$SLEEP"
                        done
                        echo "</tr>" >> "$TEMP_MATRIX"
                    done
                done
            done
            echo "</tbody></table>" >> "$TEMP_MATRIX"
            echo "" 
        done
        echo "</div>" >> "$TEMP_MATRIX"
        echo ""
    done < "$FILE_DOMAINS"
}

main() {
    START_TIME_EPOCH=$(date +%s)
    START_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S")

    # Adicionado opção -l
    while getopts ":n:g:lhy" opt; do
        case ${opt} in
            n) FILE_DOMAINS=$OPTARG ;;
            g) FILE_GROUPS=$OPTARG ;;
            l) GENERATE_LOG_TEXT="true" ;;
            y) INTERACTIVE_MODE="false" ;;
            h) show_help; exit 0 ;;
            \?) echo -e "${RED}Opção inválida: -$OPTARG${NC}" >&2; show_help; exit 1 ;;
        esac
    done

    if ! command -v dig &> /dev/null; then echo "Erro: 'dig' nao encontrado."; exit 1; fi
    
    # Se gerou log, inicializa o arquivo
    if [[ "$GENERATE_LOG_TEXT" == "true" ]]; then
        echo "=============================================" > "$LOG_FILE_TEXT"
        echo " DNS DIAGNOSTIC TOOL - EXECUTION LOG" >> "$LOG_FILE_TEXT"
        echo " Started: $START_TIME_HUMAN" >> "$LOG_FILE_TEXT"
        echo "=============================================" >> "$LOG_FILE_TEXT"
    fi

    interactive_configuration
    if [[ "$INTERACTIVE_MODE" == "false" ]]; then print_execution_summary; fi
    
    init_html_parts
    write_html_header
    load_dns_groups
    process_tests
    run_ping_diagnostics
    
    END_TIME_EPOCH=$(date +%s)
    END_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S")
    TOTAL_DURATION=$((END_TIME_EPOCH - START_TIME_EPOCH))
    
    TOTAL_SLEEP_TIME=$(awk "BEGIN {print $TOTAL_TESTS * $SLEEP}")

    assemble_html
    
    # Finaliza o log de texto
    if [[ "$GENERATE_LOG_TEXT" == "true" ]]; then
        {
            echo "============================================="
            echo " EXECUTION FINISHED: $END_TIME_HUMAN"
            echo " DURATION: ${TOTAL_DURATION}s"
            echo " TOTAL TESTS: $TOTAL_TESTS (Success: $SUCCESS_TESTS / Fail: $FAILED_TESTS)"
            echo "============================================="
        } >> "$LOG_FILE_TEXT"
    fi
    
    echo -e "\n${GREEN}=== DIAGNÓSTICO CONCLUÍDO ===${NC}"
    echo -e "  📅 Início    : $START_TIME_HUMAN"
    echo -e "  🏁 Fim       : $END_TIME_HUMAN"
    echo -e "  ⏱️  Duração   : ${TOTAL_DURATION}s"
    echo -e "  💤 Sleep Add : ${TOTAL_SLEEP_TIME}s (Total)"
    echo -e "  📊 Stats     : Total: $TOTAL_TESTS | Sucesso: $SUCCESS_TESTS | Alertas: $WARNING_TESTS | Falhas: $FAILED_TESTS"
    echo -e "  📄 Relatório HTML: ${CYAN}$HTML_FILE${NC}"
    [[ "$GENERATE_LOG_TEXT" == "true" ]] && echo -e "  📄 Relatório LOG : ${CYAN}$LOG_FILE_TEXT${NC}"
}

main "$@"
