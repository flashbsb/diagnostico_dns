#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS - COMPLETE DASHBOARD
# Versão: 9.9.4 (Visual Fix Edition)
# "Correção das quebras de linha nas tentativas (Logs)."
# ==============================================

# --- CONFIGURAÇÕES GERAIS ---
SCRIPT_VERSION="9.9.4"

DEFAULT_DIG_OPTIONS="+norecurse +time=2 +tries=1 +nocookie +cd +bufsize=512"
RECURSIVE_DIG_OPTIONS="+time=2 +tries=1 +nocookie +cd +bufsize=512"

# Prefixo e Arquivos
LOG_PREFIX="dnsdiag"
FILE_DOMAINS="domains_tests.csv"
FILE_GROUPS="dns_groups.csv"

# Configurações de Comportamento
TIMEOUT=2                     
VALIDATE_CONNECTIVITY="true"  
GENERATE_HTML="true"
GENERATE_LOG_TEXT="false"     
SLEEP=0.05                    
VERBOSE="false"               
IP_VERSION="ipv4"             
CHECK_BIND_VERSION="false"    

# --- CONFIGURAÇÃO DE CONSISTÊNCIA ---
CONSISTENCY_CHECKS=10          # Quantas vezes perguntar?

# --- CRITÉRIOS DE DIVERGÊNCIA (TOLERÂNCIA) ---
# "true" = Qualquer alteração causa DIVERGÊNCIA (Rigoroso)
# "false" = Ignora alterações neste campo (Permissivo/Padrão)
STRICT_IP_CHECK="false"       # Se false: Ignora se o IP mudou (Round Robin)
STRICT_ORDER_CHECK="false"    # Se false: Ordena as respostas antes de comparar
STRICT_TTL_CHECK="false"      # Se false: Ignora diferenças de TTL (recomendado)

# Configurações de Ping
ENABLE_PING=true
PING_COUNT=10       
PING_TIMEOUT=2      

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
declare -i DIVERGENT_TESTS=0

# Setup Arquivos
mkdir -p logs
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HTML_FILE="logs/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}.html"
LOG_FILE_TEXT="logs/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}.log"

# Arquivos Temporários
TEMP_HEADER="logs/temp_header_${TIMESTAMP}.html"
TEMP_STATS="logs/temp_stats_${TIMESTAMP}.html"
TEMP_TIMING="logs/temp_timing_${TIMESTAMP}.html"
TEMP_MATRIX="logs/temp_matrix_${TIMESTAMP}.html"
TEMP_PING="logs/temp_ping_${TIMESTAMP}.html"
TEMP_DETAILS="logs/temp_details_${TIMESTAMP}.html"
TEMP_CONFIG="logs/temp_config_${TIMESTAMP}.html"
TEMP_MODAL="logs/temp_modal_${TIMESTAMP}.html"
TEMP_DISCLAIMER="logs/temp_disclaimer_${TIMESTAMP}.html"

# ==============================================
# HELP & BANNER
# ==============================================

show_help() {
    echo -e "${BLUE}==========================================================${NC}"
    echo -e "${BLUE}       🔍 DIAGNÓSTICO DNS AVANÇADO - v${SCRIPT_VERSION}        ${NC}"
    echo -e "${BLUE}==========================================================${NC}"
    echo -e "Ferramenta de automação com verificação de consistência inteligente."
    echo -e ""
    echo -e "${PURPLE}USO:${NC}"
    echo -e "  $0 [opções]"
    echo -e ""
    echo -e "${PURPLE}OPÇÕES:${NC}"
    echo -e "  ${GREEN}-n <arquivo>${NC}   CSV de domínios (Default: domains_tests.csv)"
    echo -e "  ${GREEN}-g <arquivo>${NC}   CSV de grupos DNS (Default: dns_groups.csv)"
    echo -e "  ${GREEN}-y${NC}            Modo Silencioso (Não interativo)"
    echo -e "  ${GREEN}-h${NC}            Exibe ajuda"
    echo -e ""
}

print_execution_summary() {
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}       DIAGNÓSTICO DNS - DASHBOARD DE EXECUÇÃO        ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${PURPLE}[GERAL]${NC}"
    echo -e "  🏷️  Versão        : ${YELLOW}v${SCRIPT_VERSION}${NC}"
    echo -e "  📂 Domínios      : ${YELLOW}$FILE_DOMAINS${NC}"
    echo -e "  📂 Grupos DNS    : ${YELLOW}$FILE_GROUPS${NC}"
    echo ""
    echo -e "${PURPLE}[REDE & PERFORMANCE]${NC}"
    echo -e "  ⏱️  Timeout Global: ${CYAN}${TIMEOUT}s${NC}"
    echo -e "  💤 Sleep (Interv): ${CYAN}${SLEEP}s${NC}"
    echo -e "  🔄 Consistência  : ${YELLOW}${CONSISTENCY_CHECKS} tentativas${NC}"
    echo -e "  📡 Valida Conexão: ${CYAN}${VALIDATE_CONNECTIVITY}${NC}"
    echo -e "  🌐 Versão IP     : ${CYAN}${IP_VERSION}${NC}"
    echo -e "  🏓 Ping Check    : ${CYAN}${ENABLE_PING} (Count: $PING_COUNT, Timeout: ${PING_TIMEOUT}s)${NC}"
    echo ""
    echo -e "${PURPLE}[CRITÉRIOS DE DIVERGÊNCIA]${NC}"
    echo -e "  🔢 Strict IP     : ${CYAN}${STRICT_IP_CHECK}${NC} (True = IP diferente diverge)"
    echo -e "  🔃 Strict Order  : ${CYAN}${STRICT_ORDER_CHECK}${NC} (True = Ordem diferente diverge)"
    echo -e "  ⏱️  Strict TTL    : ${CYAN}${STRICT_TTL_CHECK}${NC} (True = TTL diferente diverge)"
    echo ""
    echo -e "${PURPLE}[DEBUG & CONTROLE]${NC}"
    echo -e "  📢 Verbose Mode  : ${CYAN}${VERBOSE}${NC}"
    echo -e "  📝 Gerar Log TXT : ${CYAN}${GENERATE_LOG_TEXT}${NC}"
    echo -e "  🛠️  Dig Options   : ${GRAY}${DEFAULT_DIG_OPTIONS}${NC}"
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
    [[ "$GENERATE_LOG_TEXT" != "true" ]] && return
    local msg="$1"
    local ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[$ts] $msg" >> "$LOG_FILE_TEXT"
}

log_section() {
    [[ "$GENERATE_LOG_TEXT" != "true" ]] && return
    local title="$1"
    {
        echo ""
        echo "================================================================================"
        echo ">>> $title"
        echo "================================================================================"
    } >> "$LOG_FILE_TEXT"
}

log_cmd_result() {
    [[ "$GENERATE_LOG_TEXT" != "true" ]] && return
    local context="$1"; local cmd="$2"; local output="$3"; local time="$4"
    {
        echo "--------------------------------------------------------------------------------"
        echo "CTX: $context | CMD: $cmd | TIME: ${time}ms"
        echo "OUTPUT:"
        echo "$output"
        echo "--------------------------------------------------------------------------------"
    } >> "$LOG_FILE_TEXT"
}

init_log_file() {
    [[ "$GENERATE_LOG_TEXT" != "true" ]] && return
    {
        echo "DNS DIAGNOSTIC TOOL v$SCRIPT_VERSION - FORENSIC LOG"
        echo "Date: $START_TIME_HUMAN"
        echo "Config Dump:"
        echo "  Timeout: $TIMEOUT, Sleep: $SLEEP, IP: $IP_VERSION, ConnCheck: $VALIDATE_CONNECTIVITY"
        echo "  Consistency: $CONSISTENCY_CHECKS attempts"
        echo "  Criteria: StrictIP=$STRICT_IP_CHECK, StrictOrder=$STRICT_ORDER_CHECK, StrictTTL=$STRICT_TTL_CHECK"
        echo "  Dig Opts: $DEFAULT_DIG_OPTIONS"
        echo ""
    } > "$LOG_FILE_TEXT"
}

# ==============================================
# INTERATIVIDADE & CONFIGURAÇÃO
# ==============================================

ask_variable() {
    local prompt_text="$1"; local var_name="$2"; local current_val="${!var_name}"
    echo -ne "  🔹 $prompt_text [${CYAN}$current_val${NC}]: "
    read -r user_input
    if [[ -n "$user_input" ]]; then 
        printf -v "$var_name" "%s" "$user_input"
        echo -e "     ${YELLOW}>> Atualizado para: $user_input${NC}"
    fi
}

ask_boolean() {
    local prompt_text="$1"; local var_name="$2"; local current_val="${!var_name}"
    echo -ne "  🔹 $prompt_text (0=false, 1=true) [${CYAN}$current_val${NC}]: "
    read -r user_input
    if [[ -n "$user_input" ]]; then
        case "$user_input" in
            1|true|True|TRUE|s|S) 
                printf -v "$var_name" "true"
                echo -e "     ${YELLOW}>> Definido como: true${NC}" ;;
            0|false|False|FALSE|n|N) 
                printf -v "$var_name" "false"
                echo -e "     ${YELLOW}>> Definido como: false${NC}" ;;
            *) echo -e "     ${RED}⚠️  Entrada inválida.${NC}" ;;
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
        echo -e "\n${BLUE}--- CRITÉRIOS DE DIVERGÊNCIA (TOLERÂNCIA) ---${NC}"
        echo -e "${GRAY}(Se 'true', qualquer variação é marcada como divergente)${NC}"
        ask_boolean "Considerar mudança de IP como divergência?" "STRICT_IP_CHECK"
        ask_boolean "Considerar mudança de Ordem como divergência?" "STRICT_ORDER_CHECK"
        ask_boolean "Considerar mudança de TTL como divergência?" "STRICT_TTL_CHECK"
        
        echo -e "\n${BLUE}--- GERAL ---${NC}"
        ask_variable "Tentativas por Teste (Consistência)" "CONSISTENCY_CHECKS"
        ask_variable "Timeout Global (segundos)" "TIMEOUT"
        ask_variable "Sleep entre queries (segundos)" "SLEEP"
        ask_boolean "Validar conectividade porta 53?" "VALIDATE_CONNECTIVITY"
        ask_variable "Versão IP (ipv4/ipv6)" "IP_VERSION"
        ask_boolean "Verbose Debug?" "VERBOSE"
        ask_boolean "Gerar log texto?" "GENERATE_LOG_TEXT"
        ask_boolean "Ativar Ping ICMP?" "ENABLE_PING"
        
        echo -e "\n${GREEN}Configurações atualizadas!${NC}"
        print_execution_summary
    fi
}

# ==============================================
# INFRA & DEBUG
# ==============================================

check_port_bash() { timeout "$3" bash -c "cat < /dev/tcp/$1/$2" &>/dev/null; return $?; }

validate_connectivity() {
    local server="$1"; local timeout="${2:-$TIMEOUT}"
    [[ -n "${CONNECTIVITY_CACHE[$server]}" ]] && return ${CONNECTIVITY_CACHE[$server]}
    
    local status=1
    if command -v nc &> /dev/null; then nc -z -w "$timeout" "$server" 53 2>/dev/null; status=$?
    else check_port_bash "$server" 53 "$timeout"; status=$?; fi
    
    CONNECTIVITY_CACHE[$server]=$status
    return $status
}

# ==============================================
# LÓGICA DE COMPARAÇÃO NORMALIZADA
# ==============================================

normalize_dig_output() {
    local raw_input="$1"
    
    # 1. Limpeza Básica (Headers, Timestamps, Cookies, IDs)
    local clean=$(echo "$raw_input" | grep -vE "^;; (WHEN|Query time|MSG SIZE|SERVER|COOKIE|Identifier|OPT)")
    clean=$(echo "$clean" | sed 's/id: [0-9]*/id: XXX/')

    # 2. Tratamento de TTL
    if [[ "$STRICT_TTL_CHECK" == "false" ]]; then
        clean=$(echo "$clean" | awk '/IN/ {$2="TTL_IGN"; print $0} !/IN/ {print $0}')
    fi

    # 3. Tratamento de IPs/Dados
    if [[ "$STRICT_IP_CHECK" == "false" ]]; then
        clean=$(echo "$clean" | awk '/IN/ {$NF="DATA_IGN"; print $0} !/IN/ {print $0}')
    fi

    # 4. Tratamento de Ordem
    if [[ "$STRICT_ORDER_CHECK" == "false" ]]; then
        clean=$(echo "$clean" | sort)
    fi
    
    echo "$clean"
}

# ==============================================
# GERAÇÃO HTML
# ==============================================

init_html_parts() { > "$TEMP_HEADER"; > "$TEMP_STATS"; > "$TEMP_MATRIX"; > "$TEMP_PING"; > "$TEMP_DETAILS"; > "$TEMP_CONFIG"; > "$TEMP_TIMING"; > "$TEMP_MODAL"; > "$TEMP_DISCLAIMER"; }

write_html_header() {
cat > "$TEMP_HEADER" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>DNS Report v$SCRIPT_VERSION - $TIMESTAMP</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #1e1e1e; color: #d4d4d4; margin: 0; padding: 20px; }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { color: #ce9178; text-align: center; margin-bottom: 20px; }
        
        /* Modal Styles */
        .modal { display: none; position: fixed; z-index: 999; left: 0; top: 0; width: 100%; height: 100%; overflow: auto; background-color: rgba(0,0,0,0.8); backdrop-filter: blur(2px); }
        .modal-content { background-color: #252526; margin: 5% auto; padding: 0; border: 1px solid #444; width: 80%; max-width: 1000px; border-radius: 8px; box-shadow: 0 0 30px rgba(0,0,0,0.7); animation: slideDown 0.3s; }
        @keyframes slideDown { from { transform: translateY(-50px); opacity: 0; } to { transform: translateY(0); opacity: 1; } }
        .modal-header { padding: 15px 20px; background: #333; border-bottom: 1px solid #444; border-radius: 8px 8px 0 0; display: flex; justify-content: space-between; align-items: center; }
        .modal-body { padding: 20px; max-height: 70vh; overflow-y: auto; }
        .close-btn { color: #aaa; font-size: 28px; font-weight: bold; cursor: pointer; transition: 0.2s; line-height: 1; }
        .close-btn:hover { color: #f44747; }
        #modalTitle { font-weight: bold; font-family: monospace; color: #9cdcfe; font-size: 1.1em; }
        #modalText { font-family: 'Consolas', 'Courier New', monospace; white-space: pre-wrap; color: #d4d4d4; background: #1e1e1e; padding: 15px; border-radius: 4px; border: 1px solid #333; font-size: 0.9em; margin: 0; }
        
        .dashboard { display: grid; grid-template-columns: repeat(5, 1fr); gap: 15px; margin-bottom: 10px; }
        .card { background: #252526; padding: 15px; border-radius: 6px; text-align: center; border-bottom: 3px solid #444; }
        .card-num { font-size: 2em; font-weight: bold; display: block; }
        .card-label { font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; color: #888; }
        .st-total { border-color: #007acc; } .st-total .card-num { color: #007acc; }
        .st-ok { border-color: #4ec9b0; } .st-ok .card-num { color: #4ec9b0; }
        .st-warn { border-color: #ffcc02; } .st-warn .card-num { color: #ffcc02; }
        .st-fail { border-color: #f44747; } .st-fail .card-num { color: #f44747; }
        .st-div { border-color: #d16d9e; } .st-div .card-num { color: #d16d9e; }
        
        .timing-strip { background: #252526; padding: 10px; border-radius: 6px; border-left: 5px solid #666; margin-bottom: 20px; display: flex; justify-content: space-around; font-family: monospace; }
        .timing-item { text-align: center; }
        .timing-label { display: block; font-size: 0.8em; color: #888; margin-bottom: 3px; }
        .timing-val { font-weight: bold; color: #fff; }

        
        /* Legenda de Criterios */
        .criteria-legend { margin-top: 10px; background: rgba(0,0,0,0.2); padding: 10px; border-radius: 4px; border: 1px dashed #444; }
        .criteria-item { margin-bottom: 5px; font-family: monospace; }
        .crit-true { color: #f44747; font-weight: bold; }
        .crit-false { color: #4ec9b0; font-weight: bold; }
        
        /* Disclaimer Collapsible */
        details.disclaimer-details { margin-bottom: 30px; border: 1px solid #ffcc02; border-left: 5px solid #ffcc02; border-radius: 4px; background: rgba(50, 40, 0, 0.4); }
        summary.disclaimer-summary { background: rgba(50, 40, 0, 0.6); color: #ffcc02; font-weight: bold; padding: 15px; cursor: pointer; list-style: none; display: flex; align-items: center; }
        summary.disclaimer-summary:hover { background: rgba(50, 40, 0, 0.8); }
        summary.disclaimer-summary::after { content: '+'; margin-left: auto; font-size: 1.2em; }
        details.disclaimer-details[open] summary.disclaimer-summary::after { content: '-'; }
        .disclaimer-content { padding: 15px; font-size: 0.95em; line-height: 1.5; color: #e0e0e0; border-top: 1px solid rgba(255, 204, 2, 0.3); }
        .disclaimer-content strong { color: #ffcc02; }
        .disclaimer-content ul { margin: 5px 0; padding-left: 20px; color: #ccc; }
        .disclaimer-content li { margin-bottom: 3px; }

        
        .domain-block { background: #252526; margin-bottom: 20px; border-radius: 6px; box-shadow: 0 4px 6px rgba(0,0,0,0.2); overflow: hidden; }
        .domain-header { background: #333; padding: 10px 15px; font-weight: bold; border-left: 5px solid #007acc; display: flex; justify-content: space-between; align-items: center; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid #3e3e42; font-size: 0.9em; }
        th { background: #2d2d30; color: #dcdcaa; }
        .cell-link { text-decoration: none; display: block; width: 100%; height: 100%; cursor: pointer; }
        .cell-link:hover { background: rgba(255,255,255,0.05); }
        .status-ok { color: #4ec9b0; }
        .status-warning { color: #ffcc02; }
        .status-fail { color: #f44747; font-weight: bold; background: rgba(244, 71, 71, 0.1); }
        .status-divergent { color: #d16d9e; font-weight: bold; }
        .time-badge { font-size: 0.75em; color: #808080; margin-left: 5px; }
        .consistency-badge { font-size: 0.75em; padding: 1px 4px; border-radius: 3px; background: #333; border: 1px solid #555; margin-left: 5px; color: #fff; }
        .consistency-bad { background: #5a1d1d; border-color: #f44747; color: #f44747; }
        
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
        .scroll-top { position: fixed; bottom: 20px; right: 20px; background: #007acc; color: white; padding: 10px; border-radius: 50%; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.5); }
    </style>
    <script>
        function toggleDetails(state) {
            const elements = document.querySelectorAll('details');
            elements.forEach(el => el.open = state);
        }
        function showLog(id) {
            var logDetails = document.getElementById(id);
            if (!logDetails) { console.error("Log ID not found: " + id); return; }
            var rawText = logDetails.querySelector('pre').innerHTML;
            var headerText = logDetails.querySelector('summary').innerText;
            document.getElementById('modalTitle').innerText = headerText;
            document.getElementById('modalText').innerHTML = rawText;
            document.getElementById('logModal').style.display = "block";
        }
        function closeModal() { document.getElementById('logModal').style.display = "none"; }
        window.onclick = function(event) { if (event.target == document.getElementById('logModal')) { closeModal(); } }
        document.addEventListener('keydown', function(event){ if(event.key === "Escape"){ closeModal(); } });
    </script>
</head>
<body>
    <div class="container">
        <h1>📊 Relatório de Diagnóstico DNS (v$SCRIPT_VERSION)</h1>
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
                <span class="card-label">Alertas</span>
            </div>
            <div class="card st-fail">
                <span class="card-num">$FAILED_TESTS</span>
                <span class="card-label">Falhas Críticas</span>
            </div>
            <div class="card st-div">
                <span class="card-num">$DIVERGENT_TESTS</span>
                <span class="card-label">Divergências</span>
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
                <span class="timing-label">Tentativas p/ Teste</span>
                <span class="timing-val">${CONSISTENCY_CHECKS}x</span>
            </div>
            <div class="timing-item">
                <span class="timing-label">Duração Total</span>
                <span class="timing-val">${TOTAL_DURATION}s</span>
            </div>
        </div>
EOF
}

generate_disclaimer_html() {
    # Cores para o HTML baseadas no valor da variável
    local ip_color="crit-false"; [[ "$STRICT_IP_CHECK" == "true" ]] && ip_color="crit-true"
    local order_color="crit-false"; [[ "$STRICT_ORDER_CHECK" == "true" ]] && order_color="crit-true"
    local ttl_color="crit-false"; [[ "$STRICT_TTL_CHECK" == "true" ]] && ttl_color="crit-true"

cat > "$TEMP_DISCLAIMER" << EOF
        <details class="disclaimer-details">
            <summary class="disclaimer-summary">⚠️ AVISO DE ISENÇÃO DE RESPONSABILIDADE (CLIQUE PARA EXPANDIR) ⚠️</summary>
            <div class="disclaimer-content">
                Este relatório reflete apenas o que <strong>sobreviveu</strong> à viagem de volta para este script, e não necessariamente a Verdade Absoluta do Universo™.<br>
                Lembre-se que entre o seu terminal e o servidor DNS existe uma selva hostil habitada por:
                <ul>
                    <li><strong>Firewalls Paranoicos:</strong> Que bloqueiam até pensamento positivo (e pacotes UDP legítimos).</li>
                    <li><strong>Middleboxes Criativos:</strong> Filtros de segurança que acham que sua query DNS é um ataque nuclear.</li>
                    <li><strong>Rate Limits:</strong> Porque ninguém gosta de <em>spam</em>, nem mesmo o servidor.</li>
                    <li><strong>Balanceamento de Carga:</strong> Onde servidores diferentes respondem com humores diferentes.</li>
                </ul>
                
                <hr style="border: 0; border-top: 1px solid #ffcc02; margin: 15px 0;">
                
                <strong>🧐 CRITÉRIOS DE DIVERGÊNCIA ATIVOS (v$SCRIPT_VERSION):</strong><br>
                Além dos erros padrões, este relatório aplicou as seguintes regras de consistência (${CONSISTENCY_CHECKS} tentativas):
                <div class="criteria-legend">
                    <div class="criteria-item">Strict IP Check: <span class="$ip_color">$STRICT_IP_CHECK</span> (True = Requer mesmo IP sempre)</div>
                    <div class="criteria-item">Strict Order Check: <span class="$order_color">$STRICT_ORDER_CHECK</span> (True = Requer mesma ordem)</div>
                    <div class="criteria-item">Strict TTL Check: <span class="$ttl_color">$STRICT_TTL_CHECK</span> (True = Requer mesmo TTL)</div>
                </div>
                <div style="margin-top:5px; font-size:0.85em; font-style:italic;">
                    (Se <strong>false</strong>, variações no campo foram ignoradas para evitar divergências irrelevantes em cenários dinâmicos).
                </div>
            </div>
        </details>
EOF

}

generate_config_html() {
cat > "$TEMP_CONFIG" << EOF
        <div class="config-section">
             <h2>⚙️ Bastidores da Execução (Inventário & Configs)</h2>
             <p style="color: #808080; margin-bottom: 20px;">Para fins de auditoria (e para provar que você configurou o teste corretamente).</p>
             
             <table class="config-table" style="margin-bottom:30px;">
                <tbody>
                    <tr><th>Versão do Script</th><td>v${SCRIPT_VERSION}</td></tr>
                    <tr><th>Timeout Global</th><td>${TIMEOUT}s</td></tr>
                    <tr><th>Sleep (Intervalo)</th><td>${SLEEP}s</td></tr>
                    <tr><th>Valida Conectividade</th><td>${VALIDATE_CONNECTIVITY}</td></tr>
                    <tr><th>Versão IP</th><td>${IP_VERSION}</td></tr>
                    <tr><th>Check BIND Version</th><td>${CHECK_BIND_VERSION}</td></tr>
                    <tr><th>Ping Enabled</th><td>${ENABLE_PING} (Count: ${PING_COUNT}, Timeout: ${PING_TIMEOUT}s)</td></tr>
                    <tr><th>Consistency Checks</th><td>${CONSISTENCY_CHECKS} tentativas</td></tr>
                    <tr><th>Strict Criteria</th><td>IP=${STRICT_IP_CHECK} | Order=${STRICT_ORDER_CHECK} | TTL=${STRICT_TTL_CHECK}</td></tr>
                    <tr><th>Iterative DIG Options</th><td>${DEFAULT_DIG_OPTIONS}</td></tr>
                    <tr><th>Recursive DIG Options</th><td>${RECURSIVE_DIG_OPTIONS}</td></tr>
                </tbody>
             </table>
EOF
    # Inventário de grupos removido do código principal para encurtar, mas mantido o fechamento da div
    echo "</div>" >> "$TEMP_CONFIG"
}

# Gera a estrutura oculta do Modal
generate_modal_html() {
cat > "$TEMP_MODAL" << EOF
    <div id="logModal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <div id="modalTitle">Detalhes do Log</div>
                <span class="close-btn" onclick="closeModal()">&times;</span>
            </div>
            <div class="modal-body">
                <pre id="modalText"></pre>
            </div>
        </div>
    </div>
EOF
}

assemble_html() {
    generate_stats_block
    generate_timing_html
    generate_disclaimer_html 
    generate_config_html
    generate_modal_html
    
    cat "$TEMP_HEADER" >> "$HTML_FILE"
    cat "$TEMP_MODAL" >> "$HTML_FILE"
    cat "$TEMP_STATS" >> "$HTML_FILE"
    cat "$TEMP_TIMING" >> "$HTML_FILE"
    cat "$TEMP_DISCLAIMER" >> "$HTML_FILE"
    cat "$TEMP_MATRIX" >> "$HTML_FILE"
    
    if [[ -s "$TEMP_PING" ]]; then
        cat >> "$HTML_FILE" << EOF
        <div class="ping-section">
             <h2>📡 Latência e Disponibilidade (ICMP)</h2>
             <table><thead><tr><th>Grupo</th><th>Servidor</th><th>Status</th><th>Perda (%)</th><th>Latência Média</th></tr></thead><tbody>
EOF
        cat "$TEMP_PING" >> "$HTML_FILE"
        echo "</tbody></table></div>" >> "$HTML_FILE"
    fi

    cat >> "$HTML_FILE" << EOF
        <div class="tech-section">
            <div style="display:flex; justify-content:space-between; align-items:center;">
                <h2>🛠️ Logs Técnicos Detalhados</h2>
                <div class="tech-controls">
                    <button class="btn-ctrl" onclick="toggleDetails(true)">➕ Expandir Todos</button>
                    <button class="btn-ctrl" onclick="toggleDetails(false)">➖ Recolher Todos</button>
                </div>
            </div>
            <p style="color: #808080;">Logs brutos de execução. Mesmo em testes consistentes, variações ignoradas (IP/TTL) podem ser vistas aqui.</p>
EOF
    cat "$TEMP_DETAILS" >> "$HTML_FILE"
    echo "</div>" >> "$HTML_FILE"
    cat "$TEMP_CONFIG" >> "$HTML_FILE"

    cat >> "$HTML_FILE" << EOF
        <div class="footer">
            Gerado automaticamente por <strong>DNS Diagnostic Tool (v$SCRIPT_VERSION)</strong><br>
            Repositório Oficial: <a href="https://github.com/flashbsb/diagnostico_dns" target="_blank">github.com/flashbsb/diagnostico_dns</a><br>
            <br>
            <span style="font-size:0.8em; border:1px solid #444; padding:5px; border-radius:4px;">
            Critérios Ativos: IP[${STRICT_IP_CHECK}] | Order[${STRICT_ORDER_CHECK}] | TTL[${STRICT_TTL_CHECK}]
            </span>
        </div>
    </div>
    <a href="#top" class="scroll-top">⬆️</a>
</body>
</html>
EOF
    rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS" "$TEMP_PING" "$TEMP_CONFIG" "$TEMP_TIMING" "$TEMP_MODAL" "$TEMP_DISCLAIMER"
    # Trap will handle final cleanup, but we can keep explicit removal here too to be sure
}

# ==============================================
# LÓGICA PRINCIPAL (CORE)
# ==============================================

load_dns_groups() {
    declare -gA DNS_GROUPS; declare -gA DNS_GROUP_DESC; declare -gA DNS_GROUP_TYPE; declare -gA DNS_GROUP_TIMEOUT
    [[ ! -f "$FILE_GROUPS" ]] && { echo -e "${RED}ERRO: $FILE_GROUPS não encontrado!${NC}"; exit 1; }
    while IFS=';' read -r name desc type timeout servers || [ -n "$name" ]; do
        [[ "$name" =~ ^# || -z "$name" ]] && continue
        name=$(echo "$name" | xargs); servers=$(echo "$servers" | tr -d '[:space:]')
        [[ -z "$timeout" ]] && timeout=$TIMEOUT
        IFS=',' read -ra srv_arr <<< "$servers"
        DNS_GROUPS["$name"]="${srv_arr[@]}"; DNS_GROUP_DESC["$name"]="$desc"; DNS_GROUP_TYPE["$name"]="$type"; DNS_GROUP_TIMEOUT["$name"]="$timeout"
    done < "$FILE_GROUPS"
}

run_ping_diagnostics() {
    [[ "$ENABLE_PING" != "true" ]] && return
    echo -e "\n${BLUE}=== INICIANDO PING ===${NC}"
    log_section "PING TEST"
    
    # Mantida a correção aqui
    ! command -v ping &> /dev/null && { echo "Ping not found"; return; }
    
    declare -A CHECKED_IPS; declare -A IP_GROUPS_MAP; local unique_ips=()
    for grp in "${!DNS_GROUPS[@]}"; do
        for ip in ${DNS_GROUPS[$grp]}; do
            local grp_label="[$grp]"
            [[ -z "${IP_GROUPS_MAP[$ip]}" ]] && IP_GROUPS_MAP[$ip]="$grp_label" || { [[ "${IP_GROUPS_MAP[$ip]}" != *"$grp_label"* ]] && IP_GROUPS_MAP[$ip]="${IP_GROUPS_MAP[$ip]} $grp_label"; }
            if [[ -z "${CHECKED_IPS[$ip]}" ]]; then CHECKED_IPS[$ip]=1; unique_ips+=("$ip"); fi
        done
    done
    
    local ping_id=0
    for ip in "${unique_ips[@]}"; do
        ping_id=$((ping_id + 1))
        local groups_str="${IP_GROUPS_MAP[$ip]}"
        echo -ne "   📡 $ip ... "
        local output; output=$(ping -c $PING_COUNT -W $PING_TIMEOUT $ip 2>&1); local ret=$?
        local loss=$(echo "$output" | grep -oP '\d+(?=% packet loss)' | head -1)
        [[ -z "$loss" ]] && loss=100
        local rtt_avg=$(echo "$output" | awk -F '/' '/rtt/ {print $5}')
        [[ -z "$rtt_avg" ]] && rtt_avg="N/A"
        
        local status_html=""; local class_html=""; local console_res=""
        if [[ "$ret" -ne 0 ]] || [[ "$loss" == "100" ]]; then status_html="❌ DOWN"; class_html="status-fail"; console_res="${RED}DOWN${NC}"
        elif [[ "$loss" != "0" ]]; then status_html="⚠️ UNSTABLE"; class_html="status-warning"; console_res="${YELLOW}${loss}% Loss${NC}"
        else status_html="✅ UP"; class_html="status-ok"; console_res="${GREEN}${rtt_avg}ms${NC}"; fi
        
        echo -e "$console_res"
        echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td class=\"$class_html\">$status_html</td><td>${loss}%</td><td>${rtt_avg}ms</td></tr>" >> "$TEMP_PING"
        local safe_output=$(echo "$output" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        echo "<tr><td colspan=\"5\" style=\"padding:0; border:none;\"><details style=\"margin:5px;\"><summary style=\"font-size:0.8em; color:#888;\">Ver output ping #$ping_id</summary><pre>$safe_output</pre></details></td></tr>" >> "$TEMP_PING"
    done
}

process_tests() {
    [[ ! -f "$FILE_DOMAINS" ]] && { echo -e "${RED}ERRO: $FILE_DOMAINS não encontrado!${NC}"; exit 1; }
    echo -e "LEGENDA: ${GREEN}.${NC}=OK ${YELLOW}!${NC}=Alert ${PURPLE}~${NC}=Div ${RED}x${NC}=Fail"
    
    local test_id=0
    while IFS=';' read -r domain groups test_types record_types extra_hosts || [ -n "$domain" ]; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs); groups=$(echo "$groups" | tr -d '[:space:]')
        IFS=',' read -ra group_list <<< "$groups"; IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
        
        echo -e "${CYAN}>> ${domain} ${PURPLE}[${record_types}] ${YELLOW}(${test_types})${NC}"
        
        echo "<div class=\"domain-block\"><div class=\"domain-header\"><span>🌐 $domain</span><span class=\"badge\">$test_types</span></div>" >> "$TEMP_MATRIX"
        
        local calc_modes=(); if [[ "$test_types" == *"both"* ]]; then calc_modes=("iterative" "recursive"); elif [[ "$test_types" == *"recursive"* ]]; then calc_modes=("recursive"); else calc_modes=("iterative"); fi
        local targets=("$domain"); for ex in "${extra_list[@]}"; do targets+=("$ex.$domain"); done

        for grp in "${group_list[@]}"; do
            [[ -z "${DNS_GROUPS[$grp]}" ]] && continue
            local srv_list=(${DNS_GROUPS[$grp]})
            echo -ne "   [${PURPLE}${grp}${NC}] "
            echo "<div style=\"padding:10px; border-bottom:1px solid #333; background:#2d2d30; color:#9cdcfe;\">Grupo: $grp</div>" >> "$TEMP_MATRIX"
            echo "<table><thead><tr><th style=\"width:30%\">Target (Record)</th>" >> "$TEMP_MATRIX"
            for srv in "${srv_list[@]}"; do echo "<th>$srv</th>" >> "$TEMP_MATRIX"; done
            echo "</tr></thead><tbody>" >> "$TEMP_MATRIX"
            
            for mode in "${calc_modes[@]}"; do
                for target in "${targets[@]}"; do
                    for rec in "${rec_list[@]}"; do
                        echo "<tr><td><span class=\"badge\">$mode</span> <strong>$target</strong> <span style=\"color:#666\">($rec)</span></td>" >> "$TEMP_MATRIX"
                        for srv in "${srv_list[@]}"; do
                            test_id=$((test_id + 1)); TOTAL_TESTS+=1
                            
                            # Connectivity
                            if [[ "$VALIDATE_CONNECTIVITY" == "true" ]]; then
                                if ! validate_connectivity "$srv" "${DNS_GROUP_TIMEOUT[$grp]}"; then
                                    FAILED_TESTS+=1; echo -ne "${RED}x${NC}"; 
                                    echo "<td><a href=\"#\" class=\"cell-link status-fail\">❌ DOWN</a></td>" >> "$TEMP_MATRIX"
                                    continue
                                fi
                            fi
                            
                            # Consistency Loop
                            local unique_id="test_${test_id}"; local attempts_log=""; local last_normalized=""
                            local is_divergent="false"; local consistent_count=0
                            local final_status="OK"; local final_dur=0; local final_class=""
                            
                            for (( iter=1; iter<=CONSISTENCY_CHECKS; iter++ )); do
                                local opts_str; [[ "$mode" == "iterative" ]] && opts_str="$DEFAULT_DIG_OPTIONS" || opts_str="$RECURSIVE_DIG_OPTIONS"
                                local opts_arr; read -ra opts_arr <<< "$opts_str"
                                [[ "$IP_VERSION" == "ipv4" ]] && opts_arr+=("-4")
                                
                                local cmd_arr=("dig" "${opts_arr[@]}" "@$srv" "$target" "$rec")
                                
                                local start_ts=$(date +%s%N); local output; output=$("${cmd_arr[@]}" 2>&1); local ret=$?
                                local end_ts=$(date +%s%N); local dur=$(( (end_ts - start_ts) / 1000000 )); final_dur=$dur
                                
                                # --- NORMALIZAÇÃO PARA COMPARAÇÃO ---
                                local normalized=$(normalize_dig_output "$output")
                                
                                if [[ $iter -gt 1 ]]; then
                                    if [[ "$normalized" != "$last_normalized" ]]; then is_divergent="true"; else consistent_count=$((consistent_count + 1)); fi
                                else last_normalized="$normalized"; consistent_count=1; fi
                                
                                # Status Check
                                local iter_status="OK"; local answer_count=$(echo "$output" | grep -oE ", ANSWER: [0-9]+" | sed 's/[^0-9]*//g')
                                [[ -z "$answer_count" ]] && answer_count=0
                                if [[ $ret -ne 0 ]]; then iter_status="ERR:$ret"
                                elif echo "$output" | grep -q "status: SERVFAIL"; then iter_status="SERVFAIL"
                                elif echo "$output" | grep -q "status: NXDOMAIN"; then iter_status="NXDOMAIN"
                                elif echo "$output" | grep -q "status: REFUSED"; then iter_status="REFUSED"
                                elif echo "$output" | grep -q "connection timed out"; then iter_status="TIMEOUT"
                                elif echo "$output" | grep -q "status: NOERROR"; then
                                    [[ "$answer_count" -eq 0 ]] && iter_status="NOANSWER" || iter_status="NOERROR"
                                fi
                                
                                # CORREÇÃO VISUAL: Uso de ANSI C quoting para garantir newlines reais
                                attempts_log="${attempts_log}"$'\n\n'"=== TENTATIVA #$iter ($iter_status) === "$'\n'"[Normalized Check: $(echo "$normalized" | tr '\n' ' ')]"$'\n'"$output"
                                final_status="$iter_status"
                                [[ "$iter_status" == "NOERROR" ]] && final_class="status-ok" || { [[ "$iter_status" == "SERVFAIL" || "$iter_status" == "NXDOMAIN" || "$iter_status" == "NOANSWER" ]] && final_class="status-warning" || final_class="status-fail"; }
                                
                                [[ "$SLEEP" != "0" && $iter -lt $CONSISTENCY_CHECKS ]] && sleep "$SLEEP"
                            done
                            
                            local badge=""
                            if [[ "$is_divergent" == "true" ]]; then
                                DIVERGENT_TESTS+=1; final_status="DIVERGENTE"; final_class="status-divergent"
                                badge="<span class=\"consistency-badge consistency-bad\">${consistent_count}/${CONSISTENCY_CHECKS}</span>"
                                echo -ne "${PURPLE}~${NC}"
                            else
                                [[ "$final_class" == "status-ok" ]] && { SUCCESS_TESTS+=1; echo -ne "${GREEN}.${NC}"; }
                                [[ "$final_class" == "status-warning" ]] && { WARNING_TESTS+=1; echo -ne "${YELLOW}!${NC}"; }
                                [[ "$final_class" == "status-fail" ]] && { FAILED_TESTS+=1; echo -ne "${RED}x${NC}"; }
                                badge="<span class=\"consistency-badge\">${CONSISTENCY_CHECKS}/${CONSISTENCY_CHECKS}</span>"
                            fi

                            local icon=""; [[ "$final_class" == "status-ok" ]] && icon="✅"; [[ "$final_class" == "status-warning" ]] && icon="⚠️"
                            [[ "$final_class" == "status-fail" ]] && icon="❌"; [[ "$final_class" == "status-divergent" ]] && icon="🔀"

                            echo "<td><a href=\"#\" onclick=\"showLog('$unique_id'); return false;\" class=\"cell-link $final_class\">$icon $final_status <span class=\"time-badge\">${final_dur}ms</span>$badge</a></td>" >> "$TEMP_MATRIX"
                            local safe_log=$(echo "$attempts_log" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                            echo "<details id=\"$unique_id\"><summary class=\"log-header\"><span class=\"log-id\">#$test_id</span> <span class=\"badge\">$final_status</span> <strong>$srv</strong> &rarr; $target ($rec)</summary><pre>$safe_log</pre></details>" >> "$TEMP_DETAILS"
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
    START_TIME_EPOCH=$(date +%s); START_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S")

    # Define cleanup trap
    trap 'rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS" "$TEMP_PING" "$TEMP_CONFIG" "$TEMP_TIMING" "$TEMP_MODAL" "$TEMP_DISCLAIMER" 2>/dev/null' EXIT

    while getopts ":n:g:lhy" opt; do case ${opt} in n) FILE_DOMAINS=$OPTARG ;; g) FILE_GROUPS=$OPTARG ;; l) GENERATE_LOG_TEXT="true" ;; y) INTERACTIVE_MODE="false" ;; h) show_help; exit 0 ;; *) echo "Opção inválida"; exit 1 ;; esac; done
    if ! command -v dig &> /dev/null; then echo "Erro: 'dig' nao encontrado."; exit 1; fi
    init_log_file
    interactive_configuration
    [[ "$INTERACTIVE_MODE" == "false" ]] && print_execution_summary
    init_html_parts; write_html_header; load_dns_groups; process_tests; run_ping_diagnostics
    END_TIME_EPOCH=$(date +%s); END_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S"); TOTAL_DURATION=$((END_TIME_EPOCH - START_TIME_EPOCH))
    assemble_html
    [[ "$GENERATE_LOG_TEXT" == "true" ]] && echo "Execution finished" >> "$LOG_FILE_TEXT"
    echo -e "\n${GREEN}=== CONCLUÍDO ===${NC} Relatório: $HTML_FILE"
}

main "$@"
