#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS - COMPLETE DASHBOARD
# Versão: 9.11.3 (HTML)
# "Apresentacao HTML."
# ==============================================

# --- CONFIGURAÇÕES GERAIS ---
SCRIPT_VERSION="9.11.3"

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

# Configurações de Testes Especiais
ENABLE_TCP_CHECK="true"
ENABLE_DNSSEC_CHECK="true"
ENABLE_TRACE_CHECK="true"

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
TEMP_TRACE="logs/temp_trace_${TIMESTAMP}.html"

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
    echo -e "  ${GREEN}-t${NC}            Habilita teste TCP"
    echo -e "  ${GREEN}-d${NC}            Habilita teste DNSSEC"
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
    echo -e "  🔌 TCP Check     : ${CYAN}${ENABLE_TCP_CHECK}${NC}"
    echo -e "  🔐 DNSSEC Check  : ${CYAN}${ENABLE_DNSSEC_CHECK}${NC}"
    echo -e "  🛤️ Trace Check   : ${CYAN}${ENABLE_TRACE_CHECK}${NC}"
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
        echo "  Config Dump:"
        echo "  Timeout: $TIMEOUT, Sleep: $SLEEP, IP: $IP_VERSION, ConnCheck: $VALIDATE_CONNECTIVITY"
        echo "  Consistency: $CONSISTENCY_CHECKS attempts"
        echo "  Criteria: StrictIP=$STRICT_IP_CHECK, StrictOrder=$STRICT_ORDER_CHECK, StrictTTL=$STRICT_TTL_CHECK"
        echo "  Special Tests: TCP=$ENABLE_TCP_CHECK, DNSSEC=$ENABLE_DNSSEC_CHECK"
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
        ask_boolean "Ativar Teste TCP (+tcp)?" "ENABLE_TCP_CHECK"
        ask_boolean "Ativar Teste DNSSEC (+dnssec)?" "ENABLE_DNSSEC_CHECK"
        ask_boolean "Executar Traceroute (Rota)?" "ENABLE_TRACE_CHECK"
        
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

init_html_parts() { > "$TEMP_HEADER"; > "$TEMP_STATS"; > "$TEMP_MATRIX"; > "$TEMP_PING"; > "$TEMP_TRACE"; > "$TEMP_DETAILS"; > "$TEMP_CONFIG"; > "$TEMP_TIMING"; > "$TEMP_MODAL"; > "$TEMP_DISCLAIMER"; }

write_html_header() {
cat > "$TEMP_HEADER" << EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Relatório DNS v$SCRIPT_VERSION - $TIMESTAMP</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Fira+Code:wght@400;500&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-body: #0f172a;
            --bg-card: #1e293b;
            --bg-card-hover: #334155;
            --bg-header: #1e293b;
            --border-color: #334155;
            --text-primary: #f1f5f9;
            --text-secondary: #94a3b8;
            --accent-primary: #3b82f6; 
            --accent-success: #10b981;
            --accent-warning: #f59e0b;
            --accent-danger: #ef4444;
            --accent-divergent: #d946ef;
        }

        body {
            font-family: 'Inter', sans-serif;
            background-color: var(--bg-body);
            color: var(--text-primary);
            margin: 0;
            padding: 20px;
            line-height: 1.5;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        /* --- Header & Typography --- */
        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 1px solid var(--border-color);
        }
        
        h1 {
            font-size: 1.8rem;
            font-weight: 700;
            margin: 0;
            color: var(--text-primary);
            display: flex;
            align-items: center;
            gap: 12px;
        }
        h1 small {
            font-size: 0.9rem;
            color: var(--text-secondary);
            font-weight: 400;
            background: var(--bg-card);
            padding: 4px 8px;
            border-radius: 6px;
        }

        h2 {
            font-size: 1.25rem;
            margin-top: 40px;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
            color: var(--text-primary);
            border-left: 4px solid var(--accent-primary);
            padding-left: 10px;
        }

        /* --- Dashboard Cards --- */
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        .card {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 20px;
            display: flex;
            flex-direction: column;
            align-items: flex-start;
            position: relative;
            overflow: hidden;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .card:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            border-color: var(--bg-card-hover);
        }
        .card-num {
            font-size: 2.5rem;
            font-weight: 700;
            line-height: 1;
            margin-bottom: 5px;
        }
        .card-label {
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            color: var(--text-secondary);
            font-weight: 600;
        }
        
        .st-total .card-num { color: var(--accent-primary); }
        .st-ok .card-num { color: var(--accent-success); }
        .st-warn .card-num { color: var(--accent-warning); }
        .st-fail .card-num { color: var(--accent-danger); }
        .st-div .card-num { color: var(--accent-divergent); }

        /* --- Nested Details Structure --- */
        details {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            margin-bottom: 10px;
            overflow: hidden;
            transition: all 0.2s ease;
        }
        
        /* Domain Level (Level 1) */
        details.domain-level {
            border-left: 4px solid var(--accent-primary);
        }
        details.domain-level[open] {
            margin-bottom: 20px;
        }
        details.domain-level > summary {
            background: var(--bg-card);
            padding: 15px 20px;
            font-size: 1.1rem;
            font-weight: 600;
            color: var(--text-primary);
        }
        details.domain-level > summary:hover {
            background: var(--bg-card-hover);
        }

        /* Group Level (Level 2) */
        details.group-level {
            margin: 10px 20px;
            background: rgba(0,0,0,0.2);
            border: 1px solid var(--border-color);
        }
        details.group-level > summary {
            padding: 10px 15px;
            font-size: 0.95rem;
            font-weight: 500;
            color: var(--text-secondary);
        }
        details.group-level > summary:hover {
            color: var(--text-primary);
            background: rgba(255,255,255,0.03);
        }

        summary {
            cursor: pointer;
            list-style: none;
            display: flex;
            align-items: center;
            justify-content: space-between;
            user-select: none;
        }
        summary::-webkit-details-marker { display: none; }
        summary::after {
            content: '+';
            font-size: 1.2rem;
            color: var(--text-secondary);
            font-weight: 300;
            margin-left: 10px;
        }
        details[open] > summary::after { content: '−'; }

        /* --- Tables --- */
        .table-responsive {
            width: 100%;
            overflow-x: auto;
            border-top: 1px solid var(--border-color);
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9rem;
        }
        th, td {
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }
        th {
            background: rgba(0,0,0,0.3);
            color: var(--text-secondary);
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.75rem;
            letter-spacing: 0.05em;
        }
        td {
            font-family: 'Fira Code', monospace;
        }
        tr:hover td {
            background: rgba(255,255,255,0.02);
        }
        
        /* --- Badges & Status --- */
        .badge {
            display: inline-flex;
            align-items: center;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 0.75rem;
            font-weight: 600;
            font-family: 'Inter', sans-serif;
            text-transform: uppercase;
            letter-spacing: 0.02em;
        }
        .badge-type { background: rgba(59, 130, 246, 0.15); color: #60a5fa; border: 1px solid rgba(59, 130, 246, 0.3); }
        .badge.consistent { background: #1e293b; color: #94a3b8; border: 1px solid #334155; }
        
        .status-cell { font-weight: 600; display: flex; align-items: center; gap: 8px; text-decoration: none; transition: opacity 0.2s; }
        .status-cell:hover { opacity: 0.8; }
        .st-ok { color: var(--accent-success); }
        .st-warn { color: var(--accent-warning); }
        .st-fail { color: var(--accent-danger); }
        .st-div { color: var(--accent-divergent); }
        .time-val { font-size: 0.8em; color: var(--text-secondary); font-weight: 400; opacity: 0.7; }

        /* --- Modal & Logs --- */
        .modal {
            display: none; position: fixed; z-index: 2000; left: 0; top: 0; width: 100%; height: 100%;
            background-color: rgba(0,0,0,0.85); backdrop-filter: blur(4px);
        }
        .modal-content {
            background-color: var(--bg-card); margin: 5vh auto; padding: 0;
            border: 1px solid var(--border-color); width: 90%; max-width: 1200px;
            border-radius: 12px; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.5);
            display: flex; flex-direction: column; max-height: 90vh;
        }
        .modal-header {
            padding: 20px; border-bottom: 1px solid var(--border-color);
            display: flex; justify-content: space-between; align-items: center;
        }
        .modal-body {
            padding: 0; overflow-y: auto; flex: 1;
            background: #000;
        }
        pre {
            margin: 0; padding: 20px; color: #e5e5e5; font-family: 'Fira Code', monospace; font-size: 0.85rem; line-height: 1.6;
        }
        
        /* --- Controls & Utilities --- */
        .tech-controls { display: flex; gap: 10px; margin-bottom: 20px; }
        .btn {
            background: var(--bg-card-hover); border: 1px solid var(--border-color);
            color: var(--text-primary); padding: 8px 16px; border-radius: 6px;
            cursor: pointer; font-family: 'Inter', sans-serif; font-size: 0.9rem;
            transition: all 0.2s;
        }
        .btn:hover { background: var(--accent-primary); border-color: var(--accent-primary); color: white; }
        
        .section-header { margin-top: 40px; margin-bottom: 20px; display: flex; align-items: center; justify-content: space-between; }
        
        /* Disclaimer */
        .disclaimer-box {
            background: rgba(245, 158, 11, 0.1); border: 1px solid rgba(245, 158, 11, 0.3);
            border-radius: 8px; padding: 15px; margin-bottom: 30px;
        }
        .disclaimer-box summary { color: var(--accent-warning); font-weight: 600; }
        
        /* Footer */
        footer { margin-top: 60px; padding-top: 20px; border-top: 1px solid var(--border-color); text-align: center; color: var(--text-secondary); font-size: 0.85rem; }
        footer a { color: var(--accent-primary); text-decoration: none; }
        
        /* Animations */
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        .dashboard, .domain-level { animation: fadeIn 0.4s ease-out forwards; }
    </style>
    <script>
        function toggleAll(level, state) {
            const selector = level === 'domain' ? 'details.domain-level' : 'details.group-level';
            document.querySelectorAll(selector).forEach(el => el.open = state);
        }
        
        function showLog(id) {
            var rawContent = document.getElementById(id + '_content').innerHTML;
            document.getElementById('modalTitle').innerText = document.getElementById(id + '_title').innerText;
            document.getElementById('modalText').innerHTML = rawContent;
            document.getElementById('logModal').style.display = "block";
            document.body.style.overflow = 'hidden'; 
        }
        
        function closeModal() {
            document.getElementById('logModal').style.display = "none";
            document.body.style.overflow = 'auto';
        }
        
        window.onclick = function(e) { if (e.target.className === 'modal') closeModal(); }
        document.addEventListener('keydown', function(e) { if(e.key === "Escape") closeModal(); });
    </script>
</head>
<body>
    <div class="container">
        <header>
            <h1>
                🔍 Diagnóstico DNS
                <small>v$SCRIPT_VERSION</small>
            </h1>
            <div style="text-align: right; color: var(--text-secondary); font-size: 0.9rem;">
                <div>Executado em: <strong>$TIMESTAMP</strong></div>
                <div style="font-size: 0.8em; margin-top:4px;">Tempo Total: <span id="total_time_placeholder">...</span></div>
            </div>
        </header>
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
        <details class="section-details" style="margin-top: 30px; border-left: 4px solid #6b7280;">
             <summary style="font-size: 1.1rem; font-weight: 600;">⚙️ Bastidores da Execução (Inventário & Configs)</summary>
             <div style="padding:15px;">
                 <p style="color: #808080; margin-bottom: 20px;">Parâmetros técnicos utilizados nesta bateria de testes.</p>
                 
                 <div class="table-responsive">
                 <table>
                    <thead>
                        <tr>
                            <th>Parâmetro</th>
                            <th>Valor Configurado</th>
                            <th>Descrição / Função</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr><td>Versão do Script</td><td>v${SCRIPT_VERSION}</td><td>Identificação da release utilizada.</td></tr>
                        <tr><td>Timeout Global</td><td>${TIMEOUT}s</td><td>Tempo máximo de espera por resposta do DNS.</td></tr>
                        <tr><td>Sleep (Intervalo)</td><td>${SLEEP}s</td><td>Pausa entre tentativas consecutivas (consistency check).</td></tr>
                        <tr><td>Valida Conectividade</td><td>${VALIDATE_CONNECTIVITY}</td><td>Testa porta 53 antes do envio da query.</td></tr>
                        <tr><td>Versão IP</td><td>${IP_VERSION}</td><td>Protocolo de transporte forçado (IPv4/IPv6).</td></tr>
                        <tr><td>Check BIND Version</td><td>${CHECK_BIND_VERSION}</td><td>Consulta caos class para versão do BIND.</td></tr>
                        <tr><td>Ping Enabled</td><td>${ENABLE_PING} (Count: ${PING_COUNT})</td><td>Verificação de latência ICMP.</td></tr>
                        <tr><td>TCP Check (+tcp)</td><td>${ENABLE_TCP_CHECK}</td><td>Obrigatoriedade de suporte a DNS via TCP.</td></tr>
                        <tr><td>DNSSEC Check (+dnssec)</td><td>${ENABLE_DNSSEC_CHECK}</td><td>Validação da cadeia de confiança DNSSEC.</td></tr>
                        <tr><td>Trace Route Check</td><td>${ENABLE_TRACE_CHECK}</td><td>Mapeamento de rota até o servidor.</td></tr>
                        <tr><td>Consistency Checks</td><td>${CONSISTENCY_CHECKS} tentativas</td><td>Repetições para validar estabilidade da resposta.</td></tr>
                        <tr><td>Strict Criteria</td><td>IP=${STRICT_IP_CHECK} | Order=${STRICT_ORDER_CHECK} | TTL=${STRICT_TTL_CHECK}</td><td>Regras rígidas para considerar divergência.</td></tr>
                        <tr><td>Iterative DIG Options</td><td>${DEFAULT_DIG_OPTIONS}</td><td>Flags RAW enviadas ao DIG (Modo Iterativo).</td></tr>
                        <tr><td>Recursive DIG Options</td><td>${RECURSIVE_DIG_OPTIONS}</td><td>Flags RAW enviadas ao DIG (Modo Recursivo).</td></tr>
                    </tbody>
                 </table>
                 </div>
             </div>
        </details>
EOF
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
    
    cat >> "$HTML_FILE" << EOF
    <div style="display:flex; justify-content:flex-end; margin-bottom: 20px;">
        <div class="tech-controls">
            <button class="btn" onclick="toggleAll('domain', true)">➕ Expandir Domínios</button>
            <button class="btn" onclick="toggleAll('domain', false)">➖ Recolher Domínios</button>
            <button class="btn" onclick="toggleAll('group', true)">➕ Expandir Grupos</button>
            <button class="btn" onclick="toggleAll('group', false)">➖ Recolher Grupos</button>
        </div>
    </div>
EOF

    if [[ -s "$TEMP_PING" ]]; then
        cat >> "$HTML_FILE" << EOF
        <details class="section-details" style="margin-top: 30px; border-left: 4px solid var(--accent-warning);">
             <summary style="font-size: 1.1rem; font-weight: 600;">📡 Latência e Disponibilidade (ICMP)</summary>
             <div class="table-responsive" style="padding:15px;">
             <table><thead><tr><th>Grupo</th><th>Servidor</th><th>Status</th><th>Perda (%)</th><th>Latência Média</th></tr></thead><tbody>
EOF
        cat "$TEMP_PING" >> "$HTML_FILE"
        echo "</tbody></table></div></details>" >> "$HTML_FILE"
    fi

    if [[ -s "$TEMP_TRACE" ]]; then
         cat >> "$HTML_FILE" << EOF
        <details class="section-details" style="margin-top: 20px; border-left: 4px solid var(--accent-divergent);">
             <summary style="font-size: 1.1rem; font-weight: 600;">🛤️ Rota de Rede (Traceroute)</summary>
             <div class="table-responsive" style="padding:15px;">
EOF
        cat "$TEMP_TRACE" >> "$HTML_FILE"
        echo "</div></details>" >> "$HTML_FILE"
    fi

    cat >> "$HTML_FILE" << EOF
        <div style="display:none;">
EOF
    cat "$TEMP_DETAILS" >> "$HTML_FILE"
    echo "</div>" >> "$HTML_FILE"
    cat "$TEMP_CONFIG" >> "$HTML_FILE"

    cat >> "$HTML_FILE" << EOF
        <footer>
            Gerado automaticamente por <strong>DNS Diagnostic Tool (v$SCRIPT_VERSION)</strong><br>
            <div style="margin-top:10px;">
                <span class="badge" style="border:1px solid var(--border-color); color:var(--text-secondary);">
                Critérios: IP[${STRICT_IP_CHECK}] | Order[${STRICT_ORDER_CHECK}] | TTL[${STRICT_TTL_CHECK}]
                </span>
            </div>
        </footer>
    </div>
    <a href="#top" style="position:fixed; bottom:20px; right:20px; background:var(--accent-primary); color:white; width:40px; height:40px; border-radius:50%; display:flex; align-items:center; justify-content:center; text-decoration:none; box-shadow:0 4px 10px rgba(0,0,0,0.3); font-size:1.2rem;">⬆️</a>
    <script>
        document.getElementById('total_time_placeholder').innerText = "${TOTAL_DURATION}s";
    </script>
</body>
</html>
EOF
    rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS" "$TEMP_PING" "$TEMP_TRACE" "$TEMP_CONFIG" "$TEMP_TIMING" "$TEMP_MODAL" "$TEMP_DISCLAIMER"
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

run_trace_diagnostics() {
    [[ "$ENABLE_TRACE_CHECK" != "true" ]] && return
    echo -e "\n${BLUE}=== INICIANDO TRACEROUTE ===${NC}"
    log_section "TRACEROUTE NETWORK PATH"
    
    local cmd_trace=""
    if command -v traceroute &> /dev/null; then cmd_trace="traceroute -n -w 1 -q 1 -m 15"
    elif command -v tracepath &> /dev/null; then cmd_trace="tracepath -n"
    else 
        echo -e "${YELLOW}⚠️ Traceroute/Tracepath não encontrados. Pulando.${NC}"
        echo "<p class=\"status-warning\" style=\"padding:15px;\">Ferramentas de trace não encontradas (instale traceroute ou iputils-tracepath).</p>" > "$TEMP_TRACE"
        return
    fi

    declare -A CHECKED_IPS; declare -A IP_GROUPS_MAP; local unique_ips=()
    for grp in "${!DNS_GROUPS[@]}"; do
        for ip in ${DNS_GROUPS[$grp]}; do
            local grp_label="[$grp]"
            [[ -z "${IP_GROUPS_MAP[$ip]}" ]] && IP_GROUPS_MAP[$ip]="$grp_label" || { [[ "${IP_GROUPS_MAP[$ip]}" != *"$grp_label"* ]] && IP_GROUPS_MAP[$ip]="${IP_GROUPS_MAP[$ip]} $grp_label"; }
            if [[ -z "${CHECKED_IPS[$ip]}" ]]; then CHECKED_IPS[$ip]=1; unique_ips+=("$ip"); fi
        done
    done

    echo "<table><thead><tr><th>Grupo</th><th>Servidor</th><th>Hops</th><th>Caminho (Resumo)</th></tr></thead><tbody>" >> "$TEMP_TRACE"

    local trace_id=0
    for ip in "${unique_ips[@]}"; do
        trace_id=$((trace_id + 1))
        local groups_str="${IP_GROUPS_MAP[$ip]}"
        echo -ne "   🛤️ $ip ... "
        
        local output; output=$($cmd_trace $ip 2>&1); local ret=$?
        local hops=$(echo "$output" | wc -l)
        local last_hop=$(echo "$output" | tail -1 | xargs)
        
        echo -e "${CYAN}${hops} hops${NC}"
        
        echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td>${hops}</td><td><span style=\"font-size:0.85em; color:#888;\">$last_hop</span></td></tr>" >> "$TEMP_TRACE"
        
        local safe_output=$(echo "$output" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        echo "<tr><td colspan=\"4\" style=\"padding:0; border:none;\"><details style=\"margin:5px;\"><summary style=\"font-size:0.8em; color:#888;\">Ver rota completa #$trace_id</summary><pre>$safe_output</pre></details></td></tr>" >> "$TEMP_TRACE"
    done
    echo "</tbody></table>" >> "$TEMP_TRACE"
}

process_tests() {
    [[ ! -f "$FILE_DOMAINS" ]] && { echo -e "${RED}ERRO: $FILE_DOMAINS não encontrado!${NC}"; exit 1; }
    echo -e "LEGENDA: ${GREEN}.${NC}=OK ${YELLOW}!${NC}=Alert ${PURPLE}~${NC}=Div ${RED}x${NC}=Fail ${GREEN}T${NC}=TCP ${GREEN}D${NC}=DNSSEC"
    
    # Temp files for buffering
    local TEMP_DOMAIN_BODY="logs/temp_domain_body_$$.html"
    local TEMP_GROUP_BODY="logs/temp_group_body_$$.html"
    
    local test_id=0
    while IFS=';' read -r domain groups test_types record_types extra_hosts || [ -n "$domain" ]; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs); groups=$(echo "$groups" | tr -d '[:space:]')
        IFS=',' read -ra group_list <<< "$groups"; IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
        
        echo -e "${CYAN}>> ${domain} ${PURPLE}[${record_types}] ${YELLOW}(${test_types})${NC}"
        
        # Reset Domain Stats
        local d_total=0; local d_ok=0; local d_warn=0; local d_fail=0; local d_div=0
        > "$TEMP_DOMAIN_BODY"

        local calc_modes=(); if [[ "$test_types" == *"both"* ]]; then calc_modes=("iterative" "recursive"); elif [[ "$test_types" == *"recursive"* ]]; then calc_modes=("recursive"); else calc_modes=("iterative"); fi
        local targets=("$domain"); for ex in "${extra_list[@]}"; do targets+=("$ex.$domain"); done

        for grp in "${group_list[@]}"; do
            [[ -z "${DNS_GROUPS[$grp]}" ]] && continue
            local srv_list=(${DNS_GROUPS[$grp]})
            echo -ne "   [${PURPLE}${grp}${NC}] "
            
            # Reset Group Stats
            local g_total=0; local g_ok=0; local g_warn=0; local g_fail=0; local g_div=0
            > "$TEMP_GROUP_BODY"

            echo "<div class=\"table-responsive\"><table><thead><tr><th style=\"width:30%\">Target (Record)</th>" >> "$TEMP_GROUP_BODY"
            for srv in "${srv_list[@]}"; do echo "<th>$srv</th>" >> "$TEMP_GROUP_BODY"; done
            echo "</tr></thead><tbody>" >> "$TEMP_GROUP_BODY"
            
            for mode in "${calc_modes[@]}"; do
                for target in "${targets[@]}"; do
                    for rec in "${rec_list[@]}"; do
                        echo "<tr><td><span class=\"badge badge-type\">$mode</span> <strong>$target</strong> <span style=\"color:var(--text-secondary)\">($rec)</span></td>" >> "$TEMP_GROUP_BODY"
                        for srv in "${srv_list[@]}"; do
                            test_id=$((test_id + 1)); TOTAL_TESTS+=1; g_total=$((g_total+1))
                            local unique_id="test_${test_id}"
                            
                            # Connectivity
                            if [[ "$VALIDATE_CONNECTIVITY" == "true" ]]; then
                                if ! validate_connectivity "$srv" "${DNS_GROUP_TIMEOUT[$grp]}"; then
                                    FAILED_TESTS+=1; g_fail=$((g_fail+1)); echo -ne "${RED}x${NC}"; 
                                    echo "<td><a href=\"#\" class=\"status-cell status-fail\">❌ DOWN</a></td>" >> "$TEMP_GROUP_BODY"
                                    continue
                                fi
                            fi
                            
                            # Consistency Loop
                            local attempts_log=""; local last_normalized=""
                            local is_divergent="false"; local consistent_count=0
                            local final_status="OK"; local final_dur=0; local final_class=""
                            
                            for (( iter=1; iter<=CONSISTENCY_CHECKS; iter++ )); do
                                local opts_str; [[ "$mode" == "iterative" ]] && opts_str="$DEFAULT_DIG_OPTIONS" || opts_str="$RECURSIVE_DIG_OPTIONS"
                                local opts_arr; read -ra opts_arr <<< "$opts_str"
                                [[ "$IP_VERSION" == "ipv4" ]] && opts_arr+=("-4")
                                
                                local cmd_arr=("dig" "${opts_arr[@]}" "@$srv" "$target" "$rec")
                                
                                local start_ts=$(date +%s%N); local output; output=$("${cmd_arr[@]}" 2>&1); local ret=$?
                                local end_ts=$(date +%s%N); local dur=$(( (end_ts - start_ts) / 1000000 )); final_dur=$dur
                                
                                # Normalization
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
                                
                                attempts_log="${attempts_log}"$'\n\n'"=== TENTATIVA #$iter ($iter_status) === "$'\n'"[Normalized Check: $(echo "$normalized" | tr '\n' ' ')]"$'\n'"$output"
                                final_status="$iter_status"
                                [[ "$iter_status" == "NOERROR" ]] && final_class="status-ok" || { [[ "$iter_status" == "SERVFAIL" || "$iter_status" == "NXDOMAIN" || "$iter_status" == "NOANSWER" ]] && final_class="status-warning" || final_class="status-fail"; }
                                
                                [[ "$SLEEP" != "0" && $iter -lt $CONSISTENCY_CHECKS ]] && sleep "$SLEEP"
                            done
                            
                            local badge=""
                            if [[ "$is_divergent" == "true" ]]; then
                                DIVERGENT_TESTS+=1; g_div=$((g_div+1))
                                final_status="DIV"; final_class="status-divergent"
                                badge="<span class=\"consistency-badge consistency-bad\">${consistent_count}/${CONSISTENCY_CHECKS}</span>"
                                echo -ne "${PURPLE}~${NC}"
                            else
                                [[ "$final_class" == "status-ok" ]] && { SUCCESS_TESTS+=1; g_ok=$((g_ok+1)); echo -ne "${GREEN}.${NC}"; }
                                [[ "$final_class" == "status-warning" ]] && { WARNING_TESTS+=1; g_warn=$((g_warn+1)); echo -ne "${YELLOW}!${NC}"; }
                                [[ "$final_class" == "status-fail" ]] && { FAILED_TESTS+=1; g_fail=$((g_fail+1)); echo -ne "${RED}x${NC}"; }
                                badge="<span class=\"badge consistent\">${CONSISTENCY_CHECKS}x</span>"
                            fi

                            local icon=""; [[ "$final_class" == "status-ok" ]] && icon="✅"; [[ "$final_class" == "status-warning" ]] && icon="⚠️"
                            [[ "$final_class" == "status-fail" ]] && icon="❌"; [[ "$final_class" == "status-divergent" ]] && icon="🔀"

                            echo "<td><a href=\"#\" onclick=\"showLog('$unique_id'); return false;\" class=\"status-cell $final_class\">$icon $final_status $badge <span class=\"time-val\">${final_dur}ms</span></a></td>" >> "$TEMP_GROUP_BODY"

                            local safe_log=$(echo "$attempts_log" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                            # Hidden divs for Modal
                            echo "<div id=\"${unique_id}_content\" style=\"display:none\"><pre>$safe_log</pre></div>" >> "$TEMP_DETAILS"
                            echo "<div id=\"${unique_id}_title\" style=\"display:none\">#$test_id $final_status | $srv &rarr; $target ($rec)</div>" >> "$TEMP_DETAILS"
                        done
                    done
                    
                    # --- TESTE EXTRA: TCP ---
                    if [[ "$ENABLE_TCP_CHECK" == "true" ]]; then
                         echo "<tr><td><span class=\"badge badge-type\">$mode</span> <strong>$target</strong> <span style=\"color:#f44747\">(TCP)</span></td>" >> "$TEMP_GROUP_BODY"
                         for srv in "${srv_list[@]}"; do
                            test_id=$((test_id + 1)); TOTAL_TESTS+=1; g_total=$((g_total+1))
                            local unique_id="test_tcp_${test_id}"; local attempts_log=""
                            # TCP force +tcp
                            local opts_str; [[ "$mode" == "iterative" ]] && opts_str="$DEFAULT_DIG_OPTIONS" || opts_str="$RECURSIVE_DIG_OPTIONS"; local opts_arr; read -ra opts_arr <<< "$opts_str"
                            [[ "$IP_VERSION" == "ipv4" ]] && opts_arr+=("-4"); opts_arr+=("+tcp")

                            local cmd_arr=("dig" "${opts_arr[@]}" "@$srv" "$target" "A") 
                            local start_ts=$(date +%s%N); local output; output=$("${cmd_arr[@]}" 2>&1); local ret=$?
                            local end_ts=$(date +%s%N); local dur=$(( (end_ts - start_ts) / 1000000 ))
                            
                            local iter_status="OK"; local status_class="status-ok"; local status_icon="✅"
                            if [[ $ret -ne 0 ]] || echo "$output" | grep -q -E "connection timed out|communications error|no servers could be reached"; then
                                iter_status="FAIL"; status_class="status-fail"; status_icon="❌"
                                FAILED_TESTS+=1; g_fail=$((g_fail+1)); echo -ne "${RED}T${NC}"
                            else
                                SUCCESS_TESTS+=1; g_ok=$((g_ok+1)); echo -ne "${GREEN}T${NC}"
                            fi
                            
                            attempts_log="=== TCP TEST === "$'\n'"$output"
                            echo "<td><a href=\"#\" onclick=\"showLog('$unique_id'); return false;\" class=\"status-cell $status_class\">$status_icon $iter_status <span class=\"time-val\">${dur}ms</span></a></td>" >> "$TEMP_GROUP_BODY"
                            
                            local safe_log=$(echo "$attempts_log" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                            echo "<div id=\"${unique_id}_content\" style=\"display:none\"><pre>$safe_log</pre></div>" >> "$TEMP_DETAILS"
                            echo "<div id=\"${unique_id}_title\" style=\"display:none\">TCP CHECK | $srv &rarr; $target</div>" >> "$TEMP_DETAILS"
                         done
                         echo "</tr>" >> "$TEMP_GROUP_BODY"
                    fi

                    # --- TESTE EXTRA: DNSSEC ---
                    if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
                         echo "<tr><td><span class=\"badge badge-type\">$mode</span> <strong>$target</strong> <span style=\"color:#4ec9b0\">(DNSSEC)</span></td>" >> "$TEMP_GROUP_BODY"
                         for srv in "${srv_list[@]}"; do
                            test_id=$((test_id + 1)); TOTAL_TESTS+=1; g_total=$((g_total+1))
                            local unique_id="test_dnssec_${test_id}"; local attempts_log=""
                            local opts_str; [[ "$mode" == "iterative" ]] && opts_str="$DEFAULT_DIG_OPTIONS" || opts_str="$RECURSIVE_DIG_OPTIONS"; local opts_arr; read -ra opts_arr <<< "$opts_str"
                            [[ "$IP_VERSION" == "ipv4" ]] && opts_arr+=("-4"); opts_arr+=("+dnssec")

                            local cmd_arr=("dig" "${opts_arr[@]}" "@$srv" "$target" "A") 
                            local start_ts=$(date +%s%N); local output; output=$("${cmd_arr[@]}" 2>&1); local ret=$?
                            local end_ts=$(date +%s%N); local dur=$(( (end_ts - start_ts) / 1000000 ))
                            
                            local is_secure="false"; local security_note=""
                            if echo "$output" | grep -q ";; flags:.* ad"; then is_secure="true"; security_note="AD Flag";
                            elif echo "$output" | grep -q "RRSIG"; then is_secure="true"; security_note="RRSIG";
                            else security_note="No AD/RRSIG"; fi

                            local iter_status="OK"; local status_class="status-ok"; local status_icon="🔐"
                            if [[ "$is_secure" == "true" ]]; then SUCCESS_TESTS+=1; g_ok=$((g_ok+1)); echo -ne "${GREEN}D${NC}"
                            else iter_status="UNSECURE"; status_class="status-warning"; status_icon="⚠️"; WARNING_TESTS+=1; g_warn=$((g_warn+1)); echo -ne "${YELLOW}D${NC}"; fi
                            
                            attempts_log="=== DNSSEC TEST ($security_note) === "$'\n'"$output"
                            echo "<td><a href=\"#\" onclick=\"showLog('$unique_id'); return false;\" class=\"status-cell $status_class\">$status_icon $iter_status <span class=\"time-val\">${dur}ms</span></a></td>" >> "$TEMP_GROUP_BODY"
                            
                            local safe_log=$(echo "$attempts_log" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                            echo "<div id=\"${unique_id}_content\" style=\"display:none\"><pre>$safe_log</pre></div>" >> "$TEMP_DETAILS"
                            echo "<div id=\"${unique_id}_title\" style=\"display:none\">DNSSEC | $srv &rarr; $target</div>" >> "$TEMP_DETAILS"
                         done
                    fi
                done
            done
            echo "</tbody></table></div>" >> "$TEMP_GROUP_BODY"

            # Accumulate Group Stats to Domain Stats
            d_total=$((d_total + g_total)); d_ok=$((d_ok + g_ok)); d_warn=$((d_warn + g_warn))
            d_fail=$((d_fail + g_fail)); d_div=$((d_div + g_div))

            # Render Group Summary with Stats
            local g_stats_html="<span style=\"font-size:0.85em; margin-left:10px; font-weight:normal; opacity:0.9;\">"
            g_stats_html+="Total: <strong>$g_total</strong> | "
            [[ $g_ok -gt 0 ]] && g_stats_html+="<span class=\"st-ok\">✅ $g_ok</span> "
            [[ $g_warn -gt 0 ]] && g_stats_html+="<span class=\"st-warn\">⚠️ $g_warn</span> "
            [[ $g_fail -gt 0 ]] && g_stats_html+="<span class=\"st-fail\">❌ $g_fail</span> "
            [[ $g_div -gt 0 ]] && g_stats_html+="<span class=\"st-div\">🔀 $g_div</span>"
            g_stats_html+="</span>"

            echo "<details class=\"group-level\"><summary>📂 Grupo: $grp $g_stats_html</summary>" >> "$TEMP_DOMAIN_BODY"
            cat "$TEMP_GROUP_BODY" >> "$TEMP_DOMAIN_BODY"
            echo "</details>" >> "$TEMP_DOMAIN_BODY"
            
            echo "" 
        done
        
        # Render Domain Summary with Stats
        local d_stats_html="<span style=\"font-size:0.85em; margin-left:15px; font-weight:normal; opacity:0.9;\">"
        d_stats_html+="Tests: <strong>$d_total</strong> | "
        [[ $d_ok -gt 0 ]] && d_stats_html+="<span class=\"st-ok\">✅ $d_ok</span> "
        [[ $d_warn -gt 0 ]] && d_stats_html+="<span class=\"st-warn\">⚠️ $d_warn</span> "
        [[ $d_fail -gt 0 ]] && d_stats_html+="<span class=\"st-fail\">❌ $d_fail</span> "
        [[ $d_div -gt 0 ]] && d_stats_html+="<span class=\"st-div\">🔀 $d_div</span>"
        d_stats_html+="</span>"

        echo "<details class=\"domain-level\"><summary>🌐 $domain $d_stats_html <span class=\"badge\" style=\"margin-left:auto\">$test_types</span></summary>" >> "$TEMP_MATRIX"
        cat "$TEMP_DOMAIN_BODY" >> "$TEMP_MATRIX"
        echo "</details>" >> "$TEMP_MATRIX"
        
        echo ""
    done < "$FILE_DOMAINS"
    
    rm -f "$TEMP_DOMAIN_BODY" "$TEMP_GROUP_BODY"
}

main() {
    START_TIME_EPOCH=$(date +%s); START_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S")

    # Define cleanup trap
    trap 'rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS" "$TEMP_PING" "$TEMP_TRACE" "$TEMP_CONFIG" "$TEMP_TIMING" "$TEMP_MODAL" "$TEMP_DISCLAIMER" 2>/dev/null' EXIT

    while getopts ":n:g:lhytd" opt; do case ${opt} in n) FILE_DOMAINS=$OPTARG ;; g) FILE_GROUPS=$OPTARG ;; l) GENERATE_LOG_TEXT="true" ;; y) INTERACTIVE_MODE="false" ;; t) ENABLE_TCP_CHECK="true" ;; d) ENABLE_DNSSEC_CHECK="true" ;; h) show_help; exit 0 ;; *) echo "Opção inválida"; exit 1 ;; esac; done
    if ! command -v dig &> /dev/null; then echo "Erro: 'dig' nao encontrado."; exit 1; fi
    init_log_file
    interactive_configuration
    [[ "$INTERACTIVE_MODE" == "false" ]] && print_execution_summary
    init_html_parts; write_html_header; load_dns_groups; process_tests; run_ping_diagnostics; run_trace_diagnostics
    END_TIME_EPOCH=$(date +%s); END_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S"); TOTAL_DURATION=$((END_TIME_EPOCH - START_TIME_EPOCH))
    assemble_html
    [[ "$GENERATE_LOG_TEXT" == "true" ]] && echo "Execution finished" >> "$LOG_FILE_TEXT"
    echo -e "\n${GREEN}=== CONCLUÍDO ===${NC} Relatório: $HTML_FILE"
}

main "$@"
