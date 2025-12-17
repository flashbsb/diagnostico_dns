#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS - COMPLETE DASHBOARD
# Versão: 10.6.5    
# "Structural Refactoring and Stability Improvements: fix"
# ==============================================

# --- CONFIGURAÇÕES GERAIS ---
SCRIPT_VERSION="10.6.5"

# Carrega configurações externas
# Carrega configurações externas
CONFIG_FILE_NAME="diagnostico.conf"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Resolução de Path do Config
if [[ -f "$PWD/$CONFIG_FILE_NAME" ]]; then
    CONFIG_FILE="$PWD/$CONFIG_FILE_NAME" 
elif [[ -f "$SCRIPT_DIR/$CONFIG_FILE_NAME" ]]; then
    CONFIG_FILE="$SCRIPT_DIR/$CONFIG_FILE_NAME"
else
    echo "ERRO CRÍTICO: Arquivo de configuração '$CONFIG_FILE_NAME' não encontrado!"
    echo "Por favor, certifique-se de que o arquivo esteja no diretório atual ou do script."
    exit 1
fi
source "$CONFIG_FILE"



# Variáveis de Tempo
START_TIME_EPOCH=0
START_TIME_HUMAN=""
END_TIME_EPOCH=0
END_TIME_HUMAN=""
TOTAL_SLEEP_TIME=0
TOTAL_DURATION=0

# --- CORES DO TERMINAL ---
RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; PURPLE=""; GRAY=""; NC=""
if [[ "$COLOR_OUTPUT" == "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    PURPLE='\033[0;35m'
    GRAY='\033[0;90m'
    NC='\033[0m'
fi

declare -A CONNECTIVITY_CACHE
declare -A HTML_CONN_ERR_LOGGED 
declare -i TOTAL_TESTS=0
declare -i SUCCESS_TESTS=0
declare -i FAILED_TESTS=0
declare -i WARNING_TESTS=0
declare -i DIVERGENT_TESTS=0
declare -i TCP_SUCCESS=0
declare -i TCP_FAIL=0
declare -i DNSSEC_SUCCESS=0
declare -i DNSSEC_FAIL=0
declare -i DNSSEC_ABSENT=0
declare -i SEC_HIDDEN=0
declare -i SEC_REVEALED=0
declare -i SEC_AXFR_OK=0
declare -i SEC_AXFR_RISK=0
declare -i SEC_REC_OK=0
declare -i SEC_REC_RISK=0
declare -i SEC_VER_TIMEOUT=0
declare -i SEC_AXFR_TIMEOUT=0
declare -i SEC_REC_TIMEOUT=0
declare -i SOA_SYNC_FAIL=0
declare -i SOA_SYNC_OK=0
declare -i TOTAL_PING_SENT=0
TOTAL_SLEEP_TIME=0
# Latency Tracking
TOTAL_LATENCY_SUM="0"
declare -i TOTAL_LATENCY_COUNT=0
TOTAL_DNS_DURATION_SUM="0"
declare -i TOTAL_DNS_QUERY_COUNT=0

# Granular Status Counters
declare -i CNT_NOERROR=0
declare -i CNT_NXDOMAIN=0
declare -i CNT_SERVFAIL=0
declare -i CNT_REFUSED=0
declare -i CNT_TIMEOUT=0
declare -i CNT_NOANSWER=0
declare -i CNT_NETWORK_ERROR=0
declare -i CNT_OTHER_ERROR=0

# Per-Group Statistics Accumulators
declare -A GROUP_TOTAL_TESTS
declare -A GROUP_FAIL_TESTS
declare -A IP_RTT_RAW # Store raw RTT for group avg calc
declare -A GROUP_RTT_SUM
declare -A GROUP_RTT_COUNT

# Setup Arquivos
mkdir -p logs
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HTML_FILE="logs/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}.html"
LOG_FILE_TEXT="logs/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}.log"

init_html_parts() {
    TEMP_HEADER="logs/temp_header_$$.html"
    TEMP_STATS="logs/temp_stats_$$.html"
    TEMP_SERVICES="logs/temp_services_$$.html"
    TEMP_CONFIG="logs/temp_config_$$.html"
    TEMP_TIMING="logs/temp_timing_$$.html"
    TEMP_MODAL="logs/temp_modal_$$.html"
    TEMP_DISCLAIMER="logs/temp_disclaimer_$$.html"

    # Full Report Temp Files - Conditional Initialization
    if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
        TEMP_MATRIX="logs/temp_matrix_$$.html"
        TEMP_DETAILS="logs/temp_details_$$.html"
        TEMP_PING="logs/temp_ping_$$.html"
        TEMP_TRACE="logs/temp_trace_$$.html"
    else
        TEMP_MATRIX=""
        TEMP_DETAILS=""
        TEMP_PING=""
        TEMP_TRACE=""
    fi

    # Simple Mode Temp Files - Conditional Creation
    if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
        TEMP_MATRIX_SIMPLE="logs/temp_matrix_simple_$$.html"
        TEMP_PING_SIMPLE="logs/temp_ping_simple_$$.html"
        TEMP_TRACE_SIMPLE="logs/temp_trace_simple_$$.html"
        TEMP_SERVICES_SIMPLE="logs/temp_services_simple_$$.html"
        TEMP_SECURITY_SIMPLE="logs/temp_security_simple_$$.html"
        
        > "$TEMP_MATRIX_SIMPLE"
        > "$TEMP_PING_SIMPLE"
        > "$TEMP_TRACE_SIMPLE"
        > "$TEMP_SERVICES_SIMPLE"
        > "$TEMP_SECURITY_SIMPLE"
    else
        # Define empty vars to avoid unbound variable errors if referenced
        TEMP_MATRIX_SIMPLE=""
        TEMP_PING_SIMPLE=""
        TEMP_TRACE_SIMPLE=""
        TEMP_SERVICES_SIMPLE=""
        TEMP_SECURITY_SIMPLE=""
    fi
    
    # Security Temp Files
    # Security Temp Files
    TEMP_SECURITY="logs/temp_security_$$.html"
    > "$TEMP_SECURITY"
    
    # JSON Temp Files - Conditional Creation
    if [[ "$GENERATE_JSON_REPORT" == "true" ]]; then
        TEMP_JSON_Ping="logs/temp_json_ping_$$.json"
        TEMP_JSON_DNS="logs/temp_json_dns_$$.json"
        TEMP_JSON_Sec="logs/temp_json_sec_$$.json"
        TEMP_JSON_Trace="logs/temp_json_trace_$$.json"
        > "$TEMP_JSON_Ping"
        > "$TEMP_JSON_DNS"
        > "$TEMP_JSON_Sec"
        > "$TEMP_JSON_Trace"
    fi
}
# ==============================================
# HELP & BANNER
# ==============================================

print_help_text() {
    echo -e "${PURPLE}DESCRIÇÃO GERAL:${NC}"
    echo -e "  Esta ferramenta é um auditor de infraestrutura DNS projetado para validar a"
    echo -e "  confiabilidade, consistência e performance de servidores autoritativos e recursivos."
    echo -e ""
    echo -e "  O script executa uma bateria de testes para cada domínio alvo contra um grupo de"
    echo -e "  servidores DNS definidos, identificando:"
    echo -e "   1. ${CYAN}Disponibilidade:${NC} Se os servidores estão alcançáveis (ICMP/TCP)."
    echo -e "   2. ${CYAN}Consistência:${NC} Se múltiplos servidores retornam a mesma resposta (SOAs, IPs)."
    echo -e "   3. ${CYAN}Estabilidade:${NC} Se a resposta varia ao longo de múltiplas consultas (Flapping)."
    echo -e "   4. ${CYAN}Features:${NC} Suporte a TCP (obrigatório RFC 7766) e validação DNSSEC."
    echo -e "   5. ${CYAN}Performance:${NC} Latência de resposta e perda de pacotes."
    echo -e "   6. ${CYAN}Segurança:${NC} Transferência de Zona (AXFR), Recursão Aberta e Versão BIND."
    echo -e ""
    echo -e "${PURPLE}MODOS DE OPERAÇÃO:${NC}"
    echo -e "  ${YELLOW}Modo Interativo (Padrão):${NC} Um wizard guia a configuração das variáveis antes do início."
    echo -e "  ${YELLOW}Modo Silencioso (-y):${NC} Executa imediatamente usando os valores padrão ou editados no script."
    echo -e ""
    echo -e "${PURPLE}OPÇÕES DE LINHA DE COMANDO:${NC}"
    echo -e "  ${GREEN}-n <arquivo>${NC}   Define arquivo CSV de domínios (Padrão: ${GRAY}domains_tests.csv${NC})"
    echo -e "  ${GREEN}-g <arquivo>${NC}   Define arquivo CSV de grupos DNS (Padrão: ${GRAY}dns_groups.csv${NC})"
    echo -e "  ${GREEN}-l${NC}            Habilita geração de log em texto (.log)."
    echo -e "  ${GREEN}-y${NC}            Bypassa o menu interativo (Non-interactive/Batch execution)."
    echo -e ""
    echo -e "  ${GREEN}-s${NC}            Modo Simplificado (Gera HTML sem logs técnicos para redução de tamanho)."
    echo -e "  ${GREEN}-j${NC}            Gera saída em JSON estruturado (.json)."
    echo -e "  ${GRAY}Nota: O uso de -s ou -j desabilita o Relatório Completo padrão, a menos que configurado o contrário.${NC}"
    echo -e ""
    echo -e "  ${GREEN}-t${NC}            Habilita testes de conectividade TCP (Sobrescreve conf)."
    echo -e "  ${GREEN}-d${NC}            Habilita validação DNSSEC (Sobrescreve conf)."
    echo -e "  ${GREEN}-x${NC}            Habilita teste de transferência de zona (AXFR) (Sobrescreve conf)."
    echo -e "  ${GREEN}-r${NC}            Habilita teste de recursão aberta (Sobrescreve conf)."
    echo -e "  ${GREEN}-T${NC}            Habilita traceroute (Rota)."
    echo -e "  ${GREEN}-V${NC}            Habilita verificação de versão BIND (Chaos)."
    echo -e "  ${GREEN}-Z${NC}            Habilita verificação de sincronismo SOA."
    echo -e "  ${GREEN}-h${NC}            Exibe este manual detalhado."
    echo -e ""
    echo -e "${PURPLE}DICIONÁRIO DE VARIÁVEIS (Configuração Fina):${NC}"
    echo -e "  Abaixo estão as variáveis que controlam o comportamento do motor de testes."
    echo -e "  Elas podem ser ajustadas editando o cabeçalho do script ou via menu interativo."
    echo -e ""
    echo -e "  ${CYAN}TIMEOUT${NC}"
    echo -e "      Define o tempo máximo (em segundos) que o script aguarda por respostas de rede."
    echo -e "      Afeta pings, traceroutes e consultas DIG. Default seguro: 4s."
    echo -e ""
    echo -e "  ${CYAN}CONSISTENCY_CHECKS${NC} (Padrão: 3)"
    echo -e "      Define quantas vezes a MESMA consulta será repetida para o MESMO servidor."
    echo -e "      Se o servidor responder IPs diferentes nessas N tentativas, ele é marcado como"
    echo -e "      ${PURPLE}DIVERGENTE (~)${NC}. Isso pega balanceamentos Round-Robin mal configurados."
    echo -e ""
    echo -e "  ${CYAN}SLEEP${NC} (Padrão: 0.05s)"
    echo -e "      Pausa entre cada tentativa do loop de consistência. Aumente se o firewall"
    echo -e "      do alvo estiver bloqueando as requisições por rate-limit."
    echo -e ""
    echo -e "  ${CYAN}STRICT_IP_CHECK${NC} (true/false)"
    echo -e "      ${GREEN}true:${NC} Exige que o IP de resposta seja IDÊNTICO em todas as tentativas."
    echo -e "      ${GREEN}false:${NC} Aceita IPs diferentes (útil para CDNs ou pools de balanceamento)."
    echo -e ""
    echo -e "  ${CYAN}STRICT_ORDER_CHECK${NC} (true/false)"
    echo -e "      ${GREEN}true:${NC} A ordem dos registros (ex: NS1 antes de NS2) deve ser idêntica."
    echo -e "      ${GREEN}false:${NC} A ordem é ignorada, desde que o conteúdo seja o mesmo."
    echo -e ""
    echo -e "  ${CYAN}STRICT_TTL_CHECK${NC} (true/false)"
    echo -e "      ${GREEN}true:${NC} Considera erro se o TTL mudar entre consultas (ex: 300 -> 299)."
    echo -e "      ${GREEN}false:${NC} Ignora variações de TTL (Comportamento recomendado para recursivos)."
    echo -e ""
    echo -e "  ${CYAN}ENABLE_PING / PING_COUNT / PING_TIMEOUT${NC}"
    echo -e "      Módulo de latência ICMP. Executa N pings antes dos testes DNS para verificar"
    echo -e "      a saúde básica da rota e perda de pacotes."
    echo -e ""
    echo -e "  ${CYAN}CHECK_BIND_VERSION${NC}"
    echo -e "      Tenta extrair a versão do software DNS usando consultas CHAOS TXT."
    echo -e "      (Geralmente bloqueado por segurança em servidores de produção)."
    echo -e ""
    echo -e "  ${CYAN}ENABLE_TCP_CHECK / ENABLE_DNSSEC_CHECK${NC}"
    echo -e "      Ativa verificações de conformidade RFC 7766 (TCP) e suporte a DNSSEC."
    echo -e ""
    echo -e "  ${CYAN}ENABLE_AXFR_CHECK / ENABLE_RECURSION_CHECK${NC}"
    echo -e "      Testes de segurança para permissividade de transferência de zona e recursão."
    echo -e "      "
    echo -e "  ${CYAN}ENABLE_SOA_SERIAL_CHECK${NC}"
    echo -e "      Verifica se os números de série SOA são idênticos entre todos os servidores do grupo."
    echo -e ""
    echo -e "  ${CYAN}LATENCY_WARNING_THRESHOLD${NC} (Default: 100ms)"
    echo -e "      Define o limiar para alertas amarelos de lentidão."
    echo -e ""
    echo -e "  ${CYAN}PING_PACKET_LOSS_LIMIT${NC} (Default: 10%)"
    echo -e "      Define a porcentagem aceitável de perda de pacotes antes de marcar como UNSTABLE."
    echo -e ""
    echo -e "  ${CYAN}ENABLE_TRACE_CHECK${NC} (true/false)"
    echo -e "      Executa traceroute para cada IP alvo para identificar o caminho de rede."
    echo -e ""
    echo -e "  ${CYAN}VALIDATE_CONNECTIVITY${NC} (true/false)"
    echo -e "      Testa se a porta 53 (TCP/UDP) está aberta antes de tentar consultas DNS."
    echo -e "      Evita timeouts desnecessários em servidores offline."
    echo -e ""
    echo -e "  ${CYAN}ONLY_TEST_ACTIVE_GROUPS${NC} (true/false)"
    echo -e "      Se true, executa testes de Ping/Trace/Security APENAS nos servidores que"
    echo -e "      estão sendo usados pelos domínios do CSV de testes."
    echo -e ""
    echo -e "  ${CYAN}LOG_PREFIX${NC}"
    echo -e "      Prefixo dos arquivos de log gerados na pasta logs/."
    echo -e ""
    echo -e "  ${CYAN}DIG_OPTIONS (DEFAULT/RECURSIVE)${NC}"
    echo -e "      Opções avançadas passadas ao binário 'dig'. Útil para ajustes de buffer,"
    echo -e "      cookies ou flag +cd."
    echo -e ""
    echo -e "  ${CYAN}GENERATE_LOG_TEXT / VERBOSE${NC}"
    echo -e "      Controle de verbosidade e geração de log forense em texto plano (.log)."
    echo -e ""
    echo -e "  ${CYAN}COLOR_OUTPUT${NC} (true/false)"
    echo -e "      Habilita ou desabilita cores no terminal ANSI."
    echo -e ""
    echo -e "${PURPLE}LEGENDA DE SAÍDA (O que significam os símbolos?):${NC}"
    echo -e "  ${GREEN}.${NC} (Ponto)      = Sucesso (Resposta consistente e válida)."
    echo -e "  ${YELLOW}!${NC} (Exclamação)= Alerta (Sucesso, mas servidor lento ou resposta estranha)."
    echo -e "  ${PURPLE}~${NC} (Til)       = Divergência (O servidor mudou a resposta durante o teste)."
    echo -e "  ${RED}x${NC} (Xis)        = Falha Crítica (Timeout, Erro de Conexão, REFUSED)."
    echo -e "  ${RED}T${NC} / ${GREEN}T${NC}        = Status do Teste TCP (Falha/Sucesso)."
    echo -e "  ${RED}D${NC} / ${GREEN}D${NC} / ${GRAY}D${NC}    = Status do Teste DNSSEC (Falha/Sucesso/Ausente)."
    echo -e ""
    echo -e "  ${BLUE}--- LEGENDAS DE SEGURANÇA ---${NC}"
    echo -e "  ${GREEN}HIDDEN/DENIED/CLOSED${NC} = Restrito (OK)"
    echo -e "  ${RED}REVEALED/ALLOWED/OPEN${NC} = Risco (Falha de Segurança)"
    echo -e "  ${GRAY}TIMEOUT/ERROR${NC}       = Erro de Rede (Inconclusivo)"
    echo -e ""
}

show_help() {
    clear
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}       🔍 DIAGNÓSTICO DNS AVANÇADO - MANUAL DE REFERÊNCIA v${SCRIPT_VERSION}        ${NC}"
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e ""
    print_help_text
    echo -e "${BLUE}==============================================================================${NC}"
}

generate_help_html() {
    local help_content
    # Captura a saída da função show_help, convertendo cores ANSI para HTML
    # Mapa de Cores:
    # BLUE -> #3b82f6 (Accent Primary)
    # GREEN -> #10b981 (Success)
    # YELLOW -> #f59e0b (Warning) 
    # RED -> #ef4444 (Danger)
    # PURPLE -> #d946ef (Divergent/Header)
    # CYAN -> #06b6d4 (Cyan)
    # GRAY -> #94a3b8 (Secondary)
    
    # Define ESC char for cleaner regex
    local ESC=$(printf '\033')
    
    help_content=$(print_help_text | \
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' | \
        sed "s/${ESC}\[0;34m/<span style='color:#3b82f6'>/g" | \
        sed "s/${ESC}\[0;32m/<span style='color:#10b981'>/g" | \
        sed "s/${ESC}\[1;33m/<span style='color:#f59e0b'>/g" | \
        sed "s/${ESC}\[0;31m/<span style='color:#ef4444'>/g" | \
        sed "s/${ESC}\[0;35m/<span style='color:#d946ef'>/g" | \
        sed "s/${ESC}\[0;36m/<span style='color:#06b6d4'>/g" | \
        sed "s/${ESC}\[0;90m/<span style='color:#94a3b8'>/g" | \
        sed "s/${ESC}\[0m/<\/span>/g")
    
    cat > "logs/temp_help_$$.html" << EOF
        <details class="section-details" style="margin-top: 40px; border-left: 4px solid #64748b;">
            <summary style="font-size: 1.1rem; font-weight: 600;">📚 Manual de Referência (Help)</summary>
            <div class="modal-body" style="background: #1e293b; color: #cbd5e1; padding: 20px; font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace; font-size: 0.85rem; overflow-x: auto;">
                <pre style="white-space: pre-wrap;">$help_content</pre>
            </div>
        </details>
EOF
}

print_execution_summary() {
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}       DIAGNÓSTICO DNS - DASHBOARD DE EXECUÇÃO        ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${PURPLE}[GERAL]${NC}"
    echo -e "  🏷️ Versão        : ${YELLOW}v${SCRIPT_VERSION}${NC}"
    echo -e "  📂 Domínios      : ${YELLOW}$FILE_DOMAINS${NC}"
    echo -e "  📂 Grupos DNS    : ${YELLOW}$FILE_GROUPS${NC}"
    echo ""
    echo -e "${PURPLE}[REDE & PERFORMANCE]${NC}"
    echo -e "  ⏱️ Timeout Global: ${CYAN}${TIMEOUT}s${NC}"
    echo -e "  💤 Sleep (Interv): ${CYAN}${SLEEP}s${NC}"
    echo -e "  🔄 Consistência  : ${YELLOW}${CONSISTENCY_CHECKS} tentativas${NC}"
    echo -e "  📡 Valida Conexão: ${CYAN}${VALIDATE_CONNECTIVITY}${NC}"
    echo -e "  🏓 Ping Check    : ${CYAN}${ENABLE_PING} (Count: $PING_COUNT, Timeout: ${PING_TIMEOUT}s)${NC}"
    echo -e "  🔌 TCP Check     : ${CYAN}${ENABLE_TCP_CHECK}${NC}"
    echo -e "  🔐 DNSSEC Check  : ${CYAN}${ENABLE_DNSSEC_CHECK}${NC}"
    echo -e "  🛤️ Trace Check   : ${CYAN}${ENABLE_TRACE_CHECK}${NC}"
    echo -e "  🛡️ Version Check : ${CYAN}${CHECK_BIND_VERSION}${NC}"
    echo -e "  🛡️ AXFR Check    : ${CYAN}${ENABLE_AXFR_CHECK}${NC}"
    echo -e "  🛡️ Recurse Check : ${CYAN}${ENABLE_RECURSION_CHECK}${NC}"
    echo -e "  🛡️ SOA Sync Check: ${CYAN}${ENABLE_SOA_SERIAL_CHECK}${NC}"
    echo -e "  🛡️ Active Groups : ${CYAN}${ONLY_TEST_ACTIVE_GROUPS}${NC}"
    echo ""
    echo -e "${PURPLE}[CRITÉRIOS DE DIVERGÊNCIA]${NC}"
    echo -e "  🔢 Strict IP     : ${CYAN}${STRICT_IP_CHECK}${NC} (True = IP diferente diverge)"
    echo -e "  🔃 Strict Order  : ${CYAN}${STRICT_ORDER_CHECK}${NC} (True = Ordem diferente diverge)"
    echo -e "  ⏱️ Strict TTL    : ${CYAN}${STRICT_TTL_CHECK}${NC} (True = TTL diferente diverge)"
    echo ""
    echo -e "${PURPLE}[DEBUG & CONTROLE]${NC}"
    echo -e "  📢 Verbose Mode  : ${CYAN}${VERBOSE}${NC}"
    echo -e "  📝 Gerar Log TXT : ${CYAN}${GENERATE_LOG_TEXT}${NC}"
    echo -e "  🛠️ Dig Opts (Iter): ${GRAY}${DEFAULT_DIG_OPTIONS}${NC}"
    echo -e "  🛠️ Dig Opts (Rec) : ${GRAY}${RECURSIVE_DIG_OPTIONS}${NC}"
    echo ""
    echo -e "${PURPLE}[ANÁLISE & VISUALIZAÇÃO]${NC}"
    echo -e "  ⚠️ Limiar Latência : ${YELLOW}${LATENCY_WARNING_THRESHOLD}ms${NC}"
    echo -e "  📉 Perda Pcts Max : ${YELLOW}${PING_PACKET_LOSS_LIMIT}%${NC}"
    echo -e "  📊 Gráficos HTML  : ${CYAN}${ENABLE_CHARTS}${NC}"
    echo -e "  🎨 Color Output   : ${CYAN}${COLOR_OUTPUT}${NC}"
    echo ""
    echo -e "${PURPLE}[SAÍDA]${NC}"
    [[ "$GENERATE_FULL_REPORT" == "true" ]] && echo -e "  📄 Relatório Completo: ${GREEN}$HTML_FILE${NC}"
    if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
        echo -e "  📄 Relatório Simplificado: ${GREEN}${HTML_FILE%.html}_simple.html${NC}"
        echo -e "     ${GRAY}ℹ️  Nota: Relatório otimizado para tamanho reduzido (sem logs técnicos/raw data).${NC}"
    fi
    [[ "$GENERATE_FULL_REPORT" == "false" && "$GENERATE_SIMPLE_REPORT" == "false" && "$GENERATE_JSON_REPORT" == "false" ]] && echo -e "  ⚠️  ${YELLOW}Nenhum relatório selecionado? (Configurar e rodar)${NC}"
    [[ "$GENERATE_JSON_REPORT" == "true" ]] && echo -e "  📄 Relatório JSON    : ${GREEN}${HTML_FILE%.html}.json${NC}"
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
        echo "  Files: Domains='$FILE_DOMAINS', Groups='$FILE_GROUPS'"
        echo "  Timeout: $TIMEOUT, Sleep: $SLEEP, ConnCheck: $VALIDATE_CONNECTIVITY"
        echo "  Consistency: $CONSISTENCY_CHECKS attempts"
        echo "  Criteria: StrictIP=$STRICT_IP_CHECK, StrictOrder=$STRICT_ORDER_CHECK, StrictTTL=$STRICT_TTL_CHECK"
        echo "  Special Tests: TCP=$ENABLE_TCP_CHECK, DNSSEC=$ENABLE_DNSSEC_CHECK, Trace=$ENABLE_TRACE_CHECK"
        echo "  Security: Version=$CHECK_BIND_VERSION, AXFR=$ENABLE_AXFR_CHECK, Recursion=$ENABLE_RECURSION_CHECK, SOA_Sync=$ENABLE_SOA_SERIAL_CHECK
"
        echo "  Ping: Enabled=$ENABLE_PING, Count=$PING_COUNT, Timeout=$PING_TIMEOUT, LossLimit=$PING_PACKET_LOSS_LIMIT%"
        echo "  Analysis: LatencyThreshold=${LATENCY_WARNING_THRESHOLD}ms, Color=$COLOR_OUTPUT"
        echo "  Reports: Full=$GENERATE_FULL_REPORT, Simple=$GENERATE_SIMPLE_REPORT"
        echo "  Dig Opts: $DEFAULT_DIG_OPTIONS"
        echo "  Rec Dig Opts: $RECURSIVE_DIG_OPTIONS"
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
        ask_variable "Arquivo de Domínios (CSV)" "FILE_DOMAINS"
        ask_variable "Arquivo de Grupos (CSV)" "FILE_GROUPS"
        ask_variable "Prefixo arquivos Log" "LOG_PREFIX"
        ask_variable "Tentativas por Teste (Consistência)" "CONSISTENCY_CHECKS"
        ask_variable "Timeout Global (segundos)" "TIMEOUT"
        ask_variable "Sleep entre queries (segundos)" "SLEEP"
        ask_boolean "Validar conectividade porta 53?" "VALIDATE_CONNECTIVITY"
        ask_boolean "Verbose Debug?" "VERBOSE"
        ask_boolean "Gerar log texto?" "GENERATE_LOG_TEXT"
        ask_boolean "Gerar relatório HTML Detalhado?" "ENABLE_FULL_REPORT"
        ask_boolean "Gerar relatório HTML Simplificado?" "ENABLE_SIMPLE_REPORT"
        ask_boolean "Habilitar Gráficos no HTML?" "ENABLE_CHARTS"
        ask_boolean "Gerar relatório JSON?" "GENERATE_JSON_REPORT"
        
        echo -e "\n${BLUE}--- TESTES ATIVOS ---${NC}"
        ask_boolean "Ativar Ping ICMP?" "ENABLE_PING"
        if [[ "$ENABLE_PING" == "true" ]]; then
             ask_variable "   ↳ Ping Count" "PING_COUNT"
             ask_variable "   ↳ Ping Timeout (s)" "PING_TIMEOUT"
        fi
        ask_boolean "Ativar Teste TCP (+tcp)?" "ENABLE_TCP_CHECK"
        ask_boolean "Ativar Teste DNSSEC (+dnssec)?" "ENABLE_DNSSEC_CHECK"
        ask_boolean "Executar Traceroute (Rota)?" "ENABLE_TRACE_CHECK"
        ask_boolean "Testar SOMENTE grupos usados?" "ONLY_TEST_ACTIVE_GROUPS"
        
        echo -e "\n${BLUE}--- SECURITY SCAN ---${NC}"
        ask_boolean "Verificar Versão (BIND Privacy)?" "CHECK_BIND_VERSION"
        ask_boolean "Verificar Zone Transfer (AXFR)?" "ENABLE_AXFR_CHECK"
        ask_boolean "Verificar Recursão Aberta?" "ENABLE_RECURSION_CHECK"
        ask_boolean "Verificar Sincronismo SOA?" "ENABLE_SOA_SERIAL_CHECK"
        
        echo -e "\n${BLUE}--- OPÇÕES AVANÇADAS (DIG) ---${NC}"
        ask_variable "Dig Options (Padrão/Iterativo)" "DEFAULT_DIG_OPTIONS"
        ask_variable "Dig Options (Recursivo)" "RECURSIVE_DIG_OPTIONS"
        
        echo -e "\n${BLUE}--- ANÁLISE & VISUALIZAÇÃO ---${NC}"
        ask_variable "Limiar de Alerta de Latência (ms)" "LATENCY_WARNING_THRESHOLD"
        ask_variable "Limite tolerável de Perda de Pacotes (%)" "PING_PACKET_LOSS_LIMIT"
        ask_boolean "Habilitar Cores no Terminal?" "COLOR_OUTPUT"
        
        echo -e "\n${GREEN}Configurações atualizadas!${NC}"
        
        # Apply Logic for Interactive Changes
        GENERATE_FULL_REPORT="${ENABLE_FULL_REPORT}"
        GENERATE_SIMPLE_REPORT="${ENABLE_SIMPLE_REPORT}"
        GENERATE_JSON_REPORT="${GENERATE_JSON_REPORT}" # Ensure this is also synced if variable names differed, but they share name in ask_boolean logic in some versions, checking... 
        # actually ask_boolean uses the variable name passed as 2nd arg.
        # In interactive_configuration, we utilize GENERATE_JSON_REPORT directly in ask_boolean? 
        # Line 506: ask_boolean ... "GENERATE_JSON_REPORT" -> So that one is direct.
        
        # Fallback Logic (Prevent user from disabling everything without realizing)
        if [[ "$GENERATE_FULL_REPORT" == "false" && "$GENERATE_SIMPLE_REPORT" == "false" && "$GENERATE_JSON_REPORT" == "false" ]]; then
             echo -e "\n${YELLOW}⚠️  Aviso: Nenhum relatório foi selecionado. Reativando Relatório Completo por padrão.${NC}"
             GENERATE_FULL_REPORT="true"
             ENABLE_FULL_REPORT="true"
        fi

        # --- SAVE CONFIGURATION ---
        echo -e "\n${BLUE}--- PERSISTÊNCIA ---${NC}"
        SAVE_CONFIG="false"
        ask_boolean "Deseja salvar estas definições no arquivo '$CONFIG_FILE'?" "SAVE_CONFIG"
        if [[ "$SAVE_CONFIG" == "true" ]]; then
            echo -e "\n${RED}${BOLD}⚠️  ATENÇÃO: ISSO IRÁ SOBRESCREVER O ARQUIVO $CONFIG_FILE!${NC}"
            CONFIRM_SAVE="false"
            ask_boolean "TEM CERTEZA QUE DESEJA CONTINUAR?" "CONFIRM_SAVE"
            if [[ "$CONFIRM_SAVE" == "true" ]]; then
                save_config_to_file
            else
                 echo -e "     ${YELLOW}>> Cancelado. As alterações valem apenas para esta execução.${NC}"
            fi
        fi

        print_execution_summary
    fi
}

save_config_to_file() {
    [[ ! -f "$CONFIG_FILE" ]] && { echo "Erro: $CONFIG_FILE não encontrado para escrita."; return; }
    
    # Helper to update key="val" or key=val in conf file
    # Handles quoted and unquoted values, preserves comments
    update_conf_key() {
        local key="$1"
        local val="$2"
        # Escape slashes in value just in case (though mostly simple strings here)
        val="${val//\//\\/}"
        
        # Determine if original was quoted. Actually, we enforce our standard format: KEY="val" or KEY=val
        # Let's try to detect if we should quote it.
        # String values usually quoted, numbers/booleans maybe not.
        # The script uses quotes for most things in defaults.
        
        sed -i "s|^$key=.*|$key=\"$val\"|" "$CONFIG_FILE"
    }
    
    # Batch Update
    update_conf_key "FILE_DOMAINS" "$FILE_DOMAINS"
    update_conf_key "FILE_GROUPS" "$FILE_GROUPS"
    update_conf_key "LOG_PREFIX" "$LOG_PREFIX"
    sed -i "s|^CONSISTENCY_CHECKS=.*|CONSISTENCY_CHECKS=$CONSISTENCY_CHECKS|" "$CONFIG_FILE" # Numeric
    sed -i "s|^TIMEOUT=.*|TIMEOUT=$TIMEOUT|" "$CONFIG_FILE" # Numeric
    sed -i "s|^SLEEP=.*|SLEEP=$SLEEP|" "$CONFIG_FILE" # Numeric
    
    update_conf_key "VALIDATE_CONNECTIVITY" "$VALIDATE_CONNECTIVITY"
    update_conf_key "VERBOSE" "$VERBOSE"
    update_conf_key "GENERATE_LOG_TEXT" "$GENERATE_LOG_TEXT"
    
    # Report Flags
    update_conf_key "ENABLE_FULL_REPORT" "$GENERATE_FULL_REPORT" # Map back internal to config var
    update_conf_key "ENABLE_SIMPLE_REPORT" "$GENERATE_SIMPLE_REPORT"
    update_conf_key "ENABLE_CHARTS" "$ENABLE_CHARTS"
    update_conf_key "GENERATE_JSON_REPORT" "$GENERATE_JSON_REPORT"
    
    # Tests
    sed -i "s|^ENABLE_PING=.*|ENABLE_PING=$ENABLE_PING|" "$CONFIG_FILE"
    if [[ "$ENABLE_PING" == "true" ]]; then
        sed -i "s|^PING_COUNT=.*|PING_COUNT=$PING_COUNT|" "$CONFIG_FILE"
        sed -i "s|^PING_TIMEOUT=.*|PING_TIMEOUT=$PING_TIMEOUT|" "$CONFIG_FILE"
    fi
    update_conf_key "ENABLE_TCP_CHECK" "$ENABLE_TCP_CHECK"
    update_conf_key "ENABLE_DNSSEC_CHECK" "$ENABLE_DNSSEC_CHECK"
    update_conf_key "ENABLE_TRACE_CHECK" "$ENABLE_TRACE_CHECK"
    update_conf_key "ONLY_TEST_ACTIVE_GROUPS" "$ONLY_TEST_ACTIVE_GROUPS"
    
    # Security
    update_conf_key "CHECK_BIND_VERSION" "$CHECK_BIND_VERSION"
    update_conf_key "ENABLE_AXFR_CHECK" "$ENABLE_AXFR_CHECK"
    update_conf_key "ENABLE_RECURSION_CHECK" "$ENABLE_RECURSION_CHECK"
    update_conf_key "ENABLE_SOA_SERIAL_CHECK" "$ENABLE_SOA_SERIAL_CHECK"
    
    # Dig
    update_conf_key "DEFAULT_DIG_OPTIONS" "$DEFAULT_DIG_OPTIONS"
    update_conf_key "RECURSIVE_DIG_OPTIONS" "$RECURSIVE_DIG_OPTIONS"
    
    # Analysis
    sed -i "s|^LATENCY_WARNING_THRESHOLD=.*|LATENCY_WARNING_THRESHOLD=$LATENCY_WARNING_THRESHOLD|" "$CONFIG_FILE"
    sed -i "s|^PING_PACKET_LOSS_LIMIT=.*|PING_PACKET_LOSS_LIMIT=$PING_PACKET_LOSS_LIMIT|" "$CONFIG_FILE"
    update_conf_key "COLOR_OUTPUT" "$COLOR_OUTPUT"

    # Strict Criteria
    update_conf_key "STRICT_IP_CHECK" "$STRICT_IP_CHECK"
    update_conf_key "STRICT_ORDER_CHECK" "$STRICT_ORDER_CHECK"
    update_conf_key "STRICT_TTL_CHECK" "$STRICT_TTL_CHECK"
    
    echo -e "     ${GREEN}✅ Configurações salvas em '$CONFIG_FILE'!${NC}"
}

# ==============================================
# INFRA & DEBUG
# ==============================================

# ==============================================
# INFRA & DEBUG
# ==============================================

validate_csv_files() {
    local error_count=0
    
    # 1. Check Domains File
    if [[ ! -f "$FILE_DOMAINS" ]]; then
         echo -e "${RED}ERRO: Arquivo de domínios '$FILE_DOMAINS' não encontrado!${NC}"; error_count=$((error_count+1))
    else
         # Check columns (Expected 5: DOMAIN;GROUPS;TEST;RECORDS;EXTRA)
         local invalid_lines=$(awk -F';' 'NF!=5 && !/^#/ && !/^$/ {print NR}' "$FILE_DOMAINS")
         if [[ -n "$invalid_lines" ]]; then
             echo -e "${RED}ERRO EM '$FILE_DOMAINS':${NC} Linhas com número incorreto de colunas (Esperado 5):"
             echo -e "${YELLOW}Linhas: $(echo "$invalid_lines" | tr '\n' ',' | sed 's/,$//')${NC}"
             error_count=$((error_count+1))
         fi

         # Validate TEST type (Col 3: iterative|recursive|both)
         local invalid_types=$(grep -vE '^\s*#|^\s*$' "$FILE_DOMAINS" | awk -F';' '$3 !~ /^(iterative|recursive|both)$/ {print NR " (" $3 ")"}')
         if [[ -n "$invalid_types" ]]; then
             echo -e "${RED}ERRO SEMÂNTICO EM '$FILE_DOMAINS':${NC} Campo TEST inválido (Use: iterative, recursive ou both):"
             echo -e "${YELLOW}Linhas: $invalid_types${NC}"
             error_count=$((error_count+1))
         fi
    fi

    # 2. Check Groups File
    if [[ ! -f "$FILE_GROUPS" ]]; then
         echo -e "${RED}ERRO: Arquivo de grupos '$FILE_GROUPS' não encontrado!${NC}"; error_count=$((error_count+1))
    else
         # Check columns (Expected 5: NAME;DESC;TYPE;TIMEOUT;SERVERS)
         local invalid_lines=$(awk -F';' 'NF!=5 && !/^#/ && !/^$/ {print NR}' "$FILE_GROUPS")
         if [[ -n "$invalid_lines" ]]; then
             echo -e "${RED}ERRO EM '$FILE_GROUPS':${NC} Linhas com número incorreto de colunas (Esperado 5):"
             echo -e "${YELLOW}Linhas: $(echo "$invalid_lines" | tr '\n' ',' | sed 's/,$//')${NC}"
             error_count=$((error_count+1))
         fi
         
         # Validate TYPE (Col 3: authoritative|recursive|mixed)
         local invalid_types=$(grep -vE '^\s*#|^\s*$' "$FILE_GROUPS" | awk -F';' '$3 !~ /^(authoritative|recursive|mixed)$/ {print NR " (" $3 ")"}')
         if [[ -n "$invalid_types" ]]; then
             echo -e "${RED}ERRO SEMÂNTICO EM '$FILE_GROUPS':${NC} Campo TYPE inválido (Use: authoritative, recursive ou mixed):"
             echo -e "${YELLOW}Linhas: $invalid_types${NC}"
             error_count=$((error_count+1))
         fi
    fi

    [[ $error_count -gt 0 ]] && exit 1
}

check_port_bash() { timeout "$3" bash -c "cat < /dev/tcp/$1/$2" &>/dev/null; return $?; }

validate_connectivity() {
    local server="$1"; local timeout="${2:-$TIMEOUT}"
    [[ -n "${CONNECTIVITY_CACHE[$server]}" ]] && return ${CONNECTIVITY_CACHE[$server]}
    
    local status=1
    if command -v nc &> /dev/null; then 
        nc -z -w "$timeout" "$server" 53 2>/dev/null; status=$?
        log_cmd_result "CONNECTIVITY $server" "nc -z -w $timeout $server 53" "Exit Code: $status" "0"
    else 
        check_port_bash "$server" 53 "$timeout"; status=$?
        log_cmd_result "CONNECTIVITY $server" "timeout $timeout bash -c 'cat < /dev/tcp/$server/53'" "Exit Code: $status" "0"
    fi
    
    CONNECTIVITY_CACHE[$server]=$status
    return $status
}

prepare_chart_resources() {
    if [[ "$ENABLE_CHARTS" != "true" ]]; then return 1; fi
    
    # Define location for temporary chart.js
    TEMP_CHART_JS="logs/temp_chart_$$.js"
    
    local chart_url="https://cdn.jsdelivr.net/npm/chart.js"
    
    echo -ne "  ⏳ Baixando biblioteca gráfica (Chart.js)... "
    
    if command -v curl &>/dev/null; then
         if curl -s -f -o "$TEMP_CHART_JS" "$chart_url"; then
             # Validate file size AND content (must contain 'Chart')
             if [[ -s "$TEMP_CHART_JS" ]] && grep -q "Chart" "$TEMP_CHART_JS"; then
                 echo -e "${GREEN}OK${NC}"
                 return 0
             fi
         fi
    elif command -v wget &>/dev/null; then
         if wget -q -O "$TEMP_CHART_JS" "$chart_url"; then
             if [[ -s "$TEMP_CHART_JS" ]] && grep -q "Chart" "$TEMP_CHART_JS"; then
                 echo -e "${GREEN}OK${NC}"
                 return 0
             fi
         fi
    fi
    
    echo -e "${YELLOW}FALHA${NC}"
    echo -e "${YELLOW}⚠️  Aviso: Não foi possível baixar Chart.js (Arquivo inválido ou erro de rede). Gráficos desabilitados.${NC}"
    ENABLE_CHARTS="false"
    rm -f "$TEMP_CHART_JS"
    return 1
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
        # Only mask IP addresses (A/AAAA) to allow Round Robin.
        # Preserve content for TXT, MX, NS, SOA, CNAME, etc.
        # Check column 4 (Type) in standard dig output (Name TTL IN Type Data)
        clean=$(echo "$clean" | awk '$3=="IN" && ($4=="A" || $4=="AAAA") {$NF="DATA_IGN"} {print $0}')
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



write_html_header() {
cat > "$TEMP_HEADER" << EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Relatório DNS v$SCRIPT_VERSION - $TIMESTAMP</title>
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
            font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", "lohit-devanagari", sans-serif;
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
            padding: 24px;
            display: flex;
            flex-direction: column;
            align-items: center;
            text-align: center;
            justify-content: center;
            position: relative;
            overflow: hidden;
            transition: transform 0.2s, box-shadow 0.2s;
            min-height: 120px;
        }
        .card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 4px;
            background: var(--card-accent, #64748b);
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
            font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
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
            font-family: system-ui, -apple-system, sans-serif;
            text-transform: uppercase;
            letter-spacing: 0.02em;
        }
        .badge-type { background: rgba(59, 130, 246, 0.15); color: #60a5fa; border: 1px solid rgba(59, 130, 246, 0.3); }
        .badge.consistent { background: #1e293b; color: #94a3b8; border: 1px solid #334155; }
        
        .badge-mini {
            display: inline-block;
            width: 16px;
            height: 16px;
            text-align: center;
            line-height: 16px;
            border-radius: 4px;
            font-size: 9px;
            font-weight: bold;
            margin-right: 3px;
            color: #0f172a;
            vertical-align: middle;
            cursor: help;
        }
        .badge-mini.success { background-color: var(--accent-success); }
        .badge-mini.fail { background-color: var(--accent-danger); color: #fff; }
        .badge-mini.neutral { background-color: var(--text-secondary); opacity: 0.5; color: #000; }
                
        .status-cell { font-weight: 600; display: flex; align-items: center; gap: 8px; text-decoration: none; transition: opacity 0.2s; }
        .status-cell:hover { opacity: 0.8; }
        .st-ok { color: var(--accent-success); }
        .st-warn { color: var(--accent-warning); }
        .st-fail { color: var(--accent-danger); }
        .st-div { color: var(--accent-divergent); }
        
        /* Aliases for script usage */
        .status-ok { color: var(--accent-success) !important; }
        .status-warn { color: var(--accent-warning) !important; } /* Warning alias */
        .status-warning { color: var(--accent-warning) !important; }
        .status-fail { color: var(--accent-danger) !important; }
        .status-divergent { color: var(--accent-divergent) !important; }
        .status-neutral { color: var(--text-secondary) !important; }
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
            margin: 0; padding: 20px; color: #e5e5e5; font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace; font-size: 0.85rem; line-height: 1.6;
            white-space: pre-wrap; word-break: break-all;
        }

        /* --- New Modal Styles for Rich Info --- */
        .modal-info-content {
            padding: 30px;
            color: var(--text-primary);
            font-family: system-ui, -apple-system, sans-serif;
            line-height: 1.6;
            font-size: 1rem;
            background: linear-gradient(to bottom right, var(--bg-card), rgba(0,0,0,0.5));
        }
        .modal-info-content strong { color: #fff; font-weight: 600; }
        .modal-info-content b { color: #fff; font-weight: 600; }
        
        .modal-log-content {
            padding: 0;
            background: #000;
            font-family: monospace;
        }
        
        .info-header {
            display: flex;
            align-items: center;
            gap: 15px;
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 1px solid var(--border-color);
        }
        .info-icon {
            font-size: 2rem;
            background: rgba(255,255,255,0.05);
            width: 50px; height: 50px;
            display: flex; align-items: center; justify-content: center;
            border-radius: 12px;
        }
        .info-title {
            font-size: 1.4rem;
            font-weight: 700;
            letter-spacing: -0.02em;
            color: #fff;
        }
        .info-body p { margin-bottom: 15px; color: #cbd5e1; }
        .info-meta {
            margin-top: 25px;
            padding: 15px;
            background: rgba(59, 130, 246, 0.1);
            border: 1px solid rgba(59, 130, 246, 0.2);
            border-radius: 8px;
            font-size: 0.9rem;
            color: #93c5fd;
        }
        
        /* --- Controls & Utilities --- */
        .tech-controls { display: flex; gap: 10px; margin-bottom: 20px; }
        .btn {
            background: var(--bg-card-hover); border: 1px solid var(--border-color);
            color: var(--text-primary); padding: 8px 16px; border-radius: 6px;
            cursor: pointer; font-family: system-ui, -apple-system, sans-serif; font-size: 0.9rem;
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
            var el = document.getElementById(id + '_content');
            if (!el) {
                alert("Detalhes técnicos não disponíveis neste relatório simplificado.");
                return;
            }
            var rawContent = el.innerHTML;
            var titleEl = document.getElementById(id + '_title');
            var title = titleEl ? titleEl.innerText : 'Detalhes Técnicos';
            
            document.getElementById('modalTitle').innerText = title;
            
            var modalText = document.getElementById('modalText');
            modalText.innerHTML = '<pre>' + rawContent + '</pre>';
            modalText.className = 'modal-log-content';
            
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

    if [[ "$mode_hv" == "simple" ]]; then
        cat >> "$TEMP_HEADER" << EOF
        <div style="background-color: rgba(59, 130, 246, 0.1); border: 1px solid rgba(59, 130, 246, 0.3); color: var(--text-primary); padding: 12px; border-radius: 8px; margin-bottom: 25px; display: flex; align-items: center; gap: 10px; font-size: 0.9rem;">
            <span style="font-size: 1.2rem;">ℹ️</span>
            <div>
                <strong>Modo Simplificado Ativo:</strong> 
                Este relatório foi gerado em modo compacto. Logs técnicos detalhados (outputs de dig, traceroute e ping) foram suprimidos para reduzir o tamanho do arquivo.
            </div>
        </div>
EOF
    fi

    if [[ "$ENABLE_CHARTS" == "true" && -f "$TEMP_CHART_JS" ]]; then
         # Only embed if logic for empty data permits? 
         # The JS library is needed even if we show "No Data" message? No, if we show "No Data" we skip canvas code.
         # But the logic above was inside generate_stats_block.
         # We can include the library safely, it doesn't hurt.
         
         cat >> "$TEMP_HEADER" << EOF
         <script>
            /* Chart.js Library Embedded */
EOF
         cat "$TEMP_CHART_JS" >> "$TEMP_HEADER"
         cat >> "$TEMP_HEADER" << EOF
         </script>
EOF
    fi

}

generate_stats_block() {
    local p_succ=0
    [[ $TOTAL_TESTS -gt 0 ]] && p_succ=$(( (SUCCESS_TESTS * 100) / TOTAL_TESTS ))
    
    # Calculate Stats for HTML
    local domain_count=0
    [[ -f "$FILE_DOMAINS" ]] && domain_count=$(grep -vE '^\s*#|^\s*$' "$FILE_DOMAINS" | wc -l)
    local group_count=${#ACTIVE_GROUPS[@]}
    declare -A _uniq_srv_html
    for g in "${!ACTIVE_GROUPS[@]}"; do
        for ip in ${DNS_GROUPS[$g]}; do _uniq_srv_html[$ip]=1; done
    done
    local server_count=${#_uniq_srv_html[@]}
    local avg_lat="N/A"
    local avg_lat_suffix=""
    if [[ $TOTAL_LATENCY_COUNT -gt 0 ]]; then
        local calc_val
        calc_val=$(awk "BEGIN {printf \"%.0f\", $TOTAL_LATENCY_SUM / $TOTAL_LATENCY_COUNT}")
        if [[ "$calc_val" =~ ^[0-9]+$ ]]; then
            avg_lat="$calc_val"
            avg_lat_suffix="<small style=\"font-size:0.4em;\">ms</small>"
        fi
    fi

cat > "$TEMP_STATS" << EOF
        <h2>📊 Estatísticas Gerais</h2>
        <!-- General Inventory Row -->
        <div class="dashboard" style="grid-template-columns: 1fr 1fr 1fr 1fr;">
            <div class="card" style="--card-accent: #64748b; cursor:pointer;" onclick="showInfoModal('DOMÍNIOS', 'Total de domínios únicos carregados do arquivo de entrada.<br><br><b>Fonte:</b> $FILE_DOMAINS')">
                <span class="card-num">${domain_count}</span>
                <span class="card-label">Domínios</span>
            </div>
             <div class="card" style="--card-accent: #64748b; cursor:pointer;" onclick="showInfoModal('GRUPOS DNS', 'Total de grupos de servidores configurados para teste.<br><br><b>Fonte:</b> $FILE_GROUPS')">
                <span class="card-num">${group_count}</span>
                <span class="card-label">Grupos DNS</span>
            </div>
             <div class="card" style="--card-accent: #64748b; cursor:pointer;" onclick="showInfoModal('SERVIDORES', 'Total de endereços IP únicos testados nesta execução.<br>Inclui todos os servidores listados nos grupos ativos.')">
                <span class="card-num">${server_count}</span>
                <span class="card-label">Servidores</span>
            </div>
            <div class="card" style="--card-accent: #64748b; cursor:pointer;" onclick="showInfoModal('LATÊNCIA MÉDIA', 'Média de tempo de resposta (RTT) de todos os servidores.<br><br><b>Cálculo:</b> Soma de todos os RTTs / Total de respostas.<br>Valores altos podem indicar congestionamento de rede ou servidores distantes.')">
                <span class="card-num">${avg_lat}${avg_lat_suffix}</span>
                <span class="card-label">Latência Média</span>
            </div>
        </div>
        
EOF




    if [[ "$ENABLE_CHARTS" == "true" ]]; then
        if [[ $SUCCESS_TESTS -eq 0 && $WARNING_TESTS -eq 0 ]]; then
             # No valid data to show charts
             cat >> "$TEMP_STATS" << EOF
             <div class="disclaimer-box" style="text-align:center;">
                <span style="font-size:1.2rem;">📉 Sem dados para exibir gráficos</span><br>
                <span style="font-size:0.9rem; color:var(--text-secondary);">Todos os testes falharam ou nenhum dado foi coletado.</span>
             </div>
EOF
        else
             cat >> "$TEMP_STATS" << EOF
        <div style="display: flex; gap: 20px; align-items: flex-start; margin-bottom: 30px;">
             <!-- Overview Chart Container -->
             <div class="card" style="flex: 1; min-height: 350px; --card-accent: var(--accent-primary); align-items: center; justify-content: center;">
                 <h3 style="margin-top:0; color:var(--text-secondary); font-size:1rem; margin-bottom:10px;">Visão Geral de Execução</h3>
                 <div style="position: relative; height: 300px; width: 100%;">
                    <canvas id="chartOverview"></canvas>
                 </div>
                 <div style="margin-top:10px;">
                    <button class="btn" style="font-size:0.8rem; padding:4px 10px;" onclick="updateChartType('chartOverview', 'doughnut')">Doughnut</button>
                    <button class="btn" style="font-size:0.8rem; padding:4px 10px;" onclick="updateChartType('chartOverview', 'pie')">Pie</button>
                    <button class="btn" style="font-size:0.8rem; padding:4px 10px;" onclick="updateChartType('chartOverview', 'bar')">Bar</button>
                 </div>
             </div>
             <!-- Latency Chart Container (Placeholder) -->
             <div class="card" style="flex: 1; min-height: 350px; --card-accent: var(--accent-warning); align-items: center; justify-content: center;">
                 <h3 style="margin-top:0; color:var(--text-secondary); font-size:1rem; margin-bottom:10px;">Top Latência (Médias)</h3>
                 <div style="position: relative; height: 300px; width: 100%;">
                    <canvas id="chartLatency"></canvas>
                 </div>
             </div>
        </div>
EOF
        fi
    fi

    cat >> "$TEMP_STATS" << EOF
    <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap:20px; margin-bottom:30px;">
        <div class="card" style="--card-accent: var(--accent-success); cursor:pointer;" onclick="showInfoModal('SUCESSO', 'Testes concluídos sem erros.<br><br><b>Critério:</b> Resposta NOERROR, latência abaixo do limite (<${LATENCY_WARNING_THRESHOLD}ms) e consistência entre as tentativas.')">
            <div style="font-size:1.5rem; margin-bottom:5px;">✅</div>
            <span class="card-label">Sucesso</span>
            <span class="card-value" style="color:var(--accent-success);">${SUCCESS_TESTS}</span>
        </div>
        
        <div class="card" style="--card-accent: var(--accent-warning); cursor:pointer;" onclick="showInfoModal('ALERTAS', 'Testes com avisos ou performance degradada.<br><br><b>Critério:</b> Resposta válida mas lenta (> ${LATENCY_WARNING_THRESHOLD}ms), ou status não-crítico como NXDOMAIN (domínio não existe).')">
            <div style="font-size:1.5rem; margin-bottom:5px;">⚠️</div>
            <span class="card-label">Alertas</span>
            <span class="card-value" style="color:var(--accent-warning);">${WARNING_TESTS}</span>
        </div>

        <div class="card" style="--card-accent: var(--accent-danger); cursor:pointer;" onclick="showInfoModal('FALHAS CRÍTICAS', 'O servidor falhou em responder corretamente.<br><br><b>Critério:</b> Timeout (sem resposta), Erro de Rede, SERVFAIL (erro interno) ou REFUSED (bloqueio).')">
            <div style="font-size:1.5rem; margin-bottom:5px;">❌</div>
            <span class="card-label">Falhas</span>
            <span class="card-value" style="color:var(--accent-danger);">${FAILED_TESTS}</span>
        </div>

        <div class="card" style="--card-accent: var(--accent-divergent); cursor:pointer;" onclick="showInfoModal('DIVERGÊNCIAS', 'Inconsistência nas respostas do mesmo servidor.<br><br><b>Critério:</b> O servidor retornou IPs ou dados diferentes entre as ${CONSISTENCY_CHECKS} tentativas consecutivas.<br>Pode indicar balanceamento de carga instável ou problemas de sincronização.')">
            <div style="font-size:1.5rem; margin-bottom:5px;">🔀</div>
            <span class="card-label">Divergências</span>
            <span class="card-value" style="color:var(--accent-divergent);">${DIVERGENT_TESTS}</span>
        </div>
    </div>
        <div class="dashboard" style="grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));">
EOF

    if [[ "$ENABLE_TCP_CHECK" == "true" ]]; then
        cat >> "$TEMP_STATS" << EOF
            <div class="card" style="--card-accent: var(--accent-info); cursor:pointer;" onclick="showInfoModal('TCP COMPLIANCE', 'Verifica se o servidor suporta consultas DNS via TCP (Porta 53).<br><br><b>Importância:</b> Obrigatório pela RFC 7766. Essencial para respostas grandes (>512 bytes) e DNSSEC.<br>Falha aqui pode indicar bloqueio de firewall na porta 53/TCP.')">
                <div style="font-size:1.5rem; margin-bottom:5px;">🔌</div>
                <span class="card-label">TCP Compliance</span>
                <div style="margin-top:10px; font-size:1.1rem;">
                     <span style="font-weight:700; color:var(--text-primary);">${TCP_SUCCESS}</span> <span style="font-size:0.8em; color:var(--accent-success);">OK</span>
                     <span style="color:#666; margin:0 5px;">|</span>
                     <span style="font-weight:700; color:var(--text-primary);">${TCP_FAIL}</span> <span style="font-size:0.8em; color:var(--accent-danger);">Fail</span>
                </div>
            </div>
EOF
    fi

    if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
        cat >> "$TEMP_STATS" << EOF
            <div class="card" style="--card-accent: #8b5cf6; cursor:pointer;" onclick="showInfoModal('DNSSEC STATUS', 'Validação da cadeia de confiança DNSSEC (RRSIG).<br><br><b>Valid:</b> Assinatura correta e validada.<br><b>Absent:</b> Domínio não assinado (inseguro, mas funcional).<br><b>Fail:</b> Assinatura inválida (BOGUS) ou expirada. Risco de segurança!')">
                <div style="font-size:1.5rem; margin-bottom:5px;">🔐</div>
                <span class="card-label">DNSSEC Status</span>
                <div style="margin-top:10px; font-size:1.1rem;">
                     <span style="font-weight:700; color:var(--text-primary);">${DNSSEC_SUCCESS}</span> <span style="font-size:0.8em; color:var(--accent-success);">Valid</span>
                     <span style="color:#666; margin:0 5px;">|</span>
                     <span style="font-weight:700; color:var(--text-primary);">${DNSSEC_ABSENT}</span> <span style="font-size:0.8em; color:var(--text-secondary);">Absent</span>
                     <span style="color:#666; margin:0 5px;">|</span>
                     <span style="font-weight:700; color:var(--text-primary);">${DNSSEC_FAIL}</span> <span style="font-size:0.8em; color:var(--accent-danger);">Fail</span>
                </div>
            </div>
EOF
    fi

    # Security Cards (Unified in same grid)
    # Adding Counts for Timeouts/Errors to ensure totals match
    cat >> "$TEMP_STATS" << EOF
        <div class="card" style="--card-accent: var(--accent-primary); cursor:pointer;" onclick="showInfoModal('VERSION PRIVACY', 'Verifica se o servidor revela sua versão de software (BIND, etc).<br><br><b>Hide (Ideal):</b> O servidor esconde a versão ou retorna REFUSED.<br><b>Revealed (Risco):</b> O servidor informa a versão exata, facilitando exploração de CVEs.')">
            <div style="font-size:1.5rem; margin-bottom:5px;">🕵️</div>
            <span class="card-label">Version Privacy</span>
            <div style="margin-top:10px; font-size:0.95rem;">
                 <span style="color:var(--accent-success);">Hide:</span> <strong>${SEC_HIDDEN}</strong> <span style="color:#444">|</span>
                 <span style="color:var(--accent-danger);">Rev:</span> <strong>${SEC_REVEALED}</strong> <span style="color:#444">|</span>
                 <span style="color:var(--text-secondary);">Err:</span> <strong>${SEC_VER_TIMEOUT}</strong>
            </div>
        </div>
        <div class="card" style="--card-accent: var(--accent-warning); cursor:pointer;" onclick="showInfoModal('ZONE TRANSFER (AXFR)', 'Tenta realizar uma transferência de zona completa (AXFR) do domínio raiz.<br><br><b>Deny (Ideal):</b> A transferência foi recusada.<br><b>Allow (Crítico):</b> O servidor permitiu o download de toda a zona (vazamento de topologia).')">
            <div style="font-size:1.5rem; margin-bottom:5px;">📂</div>
            <span class="card-label">Zone Transfer</span>
            <div style="margin-top:10px; font-size:0.95rem;">
                 <span style="color:var(--accent-success);">Deny:</span> <strong>${SEC_AXFR_OK}</strong> <span style="color:#444">|</span>
                 <span style="color:var(--accent-danger);">Allow:</span> <strong>${SEC_AXFR_RISK}</strong> <span style="color:#444">|</span>
                 <span style="color:var(--text-secondary);">Err:</span> <strong>${SEC_AXFR_TIMEOUT}</strong>
            </div>
        </div>
        <div class="card" style="--card-accent: var(--accent-danger); cursor:pointer;" onclick="showInfoModal('RECURSION', 'Verifica se o servidor aceita consultas recursivas para domínios externos (ex: google.com).<br><br><b>Close (Ideal para Autoritativo):</b> Recusa recursão.<br><b>Open (Risco):</b> Aceita recursão (pode ser usado para ataques de amplificação DNS).')">
            <div style="font-size:1.5rem; margin-bottom:5px;">🔄</div>
            <span class="card-label">Recursion</span>
            <div style="margin-top:10px; font-size:0.95rem;">
                 <span style="color:var(--accent-success);">Close:</span> <strong>${SEC_REC_OK}</strong> <span style="color:#444">|</span>
                 <span style="color:var(--accent-danger);">Open:</span> <strong>${SEC_REC_RISK}</strong> <span style="color:#444">|</span>
                 <span style="color:var(--text-secondary);">Err:</span> <strong>${SEC_REC_TIMEOUT}</strong>
            </div>
        </div>
EOF

    # SOA Sync Card
    if [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" ]]; then
    cat >> "$TEMP_STATS" << EOF
        <div class="card" style="--card-accent: var(--accent-divergent); cursor:pointer;" onclick="showInfoModal('SOA SYNC', 'Verifica a sincronização do Serial Number (SOA) entre os servidores.<br><br><b>Synced:</b> Todos os servidores responderam com o mesmo número serial.<br><b>Div:</b> Servidores retornaram seriais diferentes (problema de propagação).')">
            <div style="font-size:1.5rem; margin-bottom:5px;">⚖️</div>
            <span class="card-label">SOA Sync</span>
            <div style="margin-top:10px; font-size:1.1rem;">
                 <span style="font-weight:700; color:var(--text-primary);">${SOA_SYNC_OK}</span> <span style="font-size:0.8em; color:var(--accent-success);">Synced</span>
                 <span style="color:#666; margin:0 5px;">|</span>
                 <span style="font-weight:700; color:var(--text-primary);">${SOA_SYNC_FAIL}</span> <span style="font-size:0.8em; color:var(--accent-danger);">Div</span>
            </div>
        </div>
EOF
    fi

    cat >> "$TEMP_STATS" << EOF
    </div>
EOF
}

generate_object_summary() {
    if [[ "$ENABLE_CHARTS" == "true" ]]; then
        cat >> "logs/temp_obj_summary_$$.html" << EOF
                <div class="card" style="margin-bottom: 20px; --card-accent: #8b5cf6; cursor: pointer;" onclick="this.nextElementSibling.open = !this.nextElementSibling.open">
                     <h3 style="margin-top:0; font-size:1rem; margin-bottom:15px;">📊 Estatísticas de Serviços</h3>
                     <div style="position: relative; height: 300px; width: 100%;">
                        <canvas id="chartServices"></canvas>
                     </div>
                     <div style="text-align:center; font-size:0.8rem; color:var(--text-secondary); margin-top:5px;">(Clique para expandir/recolher detalhes)</div>
                 </div>
EOF
    fi

    cat >> "logs/temp_obj_summary_$$.html" << EOF
        <details class="section-details" style="margin-top: 20px; border-left: 4px solid var(--accent-primary);">
            <summary style="font-size: 1.1rem; font-weight: 600;">📋 Testes DNS TCP e DNS SEC</summary>
            <div style="padding: 20px;">
EOF
    cat >> "logs/temp_obj_summary_$$.html" << EOF
                <p style="color:var(--text-secondary); margin-bottom:15px; font-size:0.9rem;">
                    Validação de recursos avançados (Transporte TCP e Assinatura DNSSEC) para cada servidor consultado.
                </p>
                <div class="table-responsive">
                    <table>
                        <thead>
                            <tr>
                                <th>Alvo Check</th>
                                <th>Servidor</th>
                                <th>TCP Status</th>
                                <th>DNSSEC Status</th>
                            </tr>
                        </thead>
                        <tbody>
EOF
    
    if [[ -f "logs/temp_svc_table_$$.html" ]]; then
        cat "logs/temp_svc_table_$$.html" >> "logs/temp_obj_summary_$$.html"
    else
        echo "<tr><td colspan='4' style='text-align:center; color:#888;'>Nenhum dado de serviço coletado.</td></tr>" >> "logs/temp_obj_summary_$$.html"
    fi

    cat >> "logs/temp_obj_summary_$$.html" << EOF
                        </tbody>
                    </table>
                </div>
            </div>
        </details>
EOF
}

generate_timing_html() {
cat > "$TEMP_TIMING" << EOF
        <div class="timing-container" style="display:flex; justify-content:center; gap:20px; margin: 40px auto 20px auto; padding: 15px; background:var(--bg-secondary); border-radius:12px; max-width:900px; border:1px solid var(--border-color); flex-wrap: wrap;">
            <div class="timing-item" style="text-align:center; min-width: 100px;">
                <div style="font-size:0.8rem; color:var(--text-secondary); text-transform:uppercase; letter-spacing:1px;">Início</div>
                <div style="font-size:1.1rem; font-weight:600;">$START_TIME_HUMAN</div>
            </div>
            <div class="timing-item" style="text-align:center; min-width: 100px;">
                <div style="font-size:0.8rem; color:var(--text-secondary); text-transform:uppercase; letter-spacing:1px;">Final</div>
                <div style="font-size:1.1rem; font-weight:600;">$END_TIME_HUMAN</div>
            </div>
            <div class="timing-item" style="text-align:center; min-width: 80px;">
                <div style="font-size:0.8rem; color:var(--text-secondary); text-transform:uppercase; letter-spacing:1px;">Tentativas</div>
                <div style="font-size:1.1rem; font-weight:600;">${CONSISTENCY_CHECKS}x</div>
            </div>
             <div class="timing-item" style="text-align:center; min-width: 80px;">
                <div style="font-size:0.8rem; color:var(--text-secondary); text-transform:uppercase; letter-spacing:1px;">Pings</div>
                <div style="font-size:1.1rem; font-weight:600;">${TOTAL_PING_SENT}</div>
            </div>
            <div class="timing-item" style="text-align:center; min-width: 120px;">
                <div style="font-size:0.8rem; color:var(--text-secondary); text-transform:uppercase; letter-spacing:1px;">Duração Total</div>
                <div style="font-size:1.1rem; font-weight:600;"><span id="total_time_footer">${TOTAL_DURATION}s</span></div>
                 <div style="font-size:0.75rem; color:var(--text-secondary); margin-top:2px;">(Sleep: ${TOTAL_SLEEP_TIME}s)</div>
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
                        <tr><td>Prefixo Log</td><td>${LOG_PREFIX}</td><td>Prefixo para geração de arquivos.</td></tr>
                        <tr><td>Timeout Global</td><td>${TIMEOUT}s</td><td>Tempo máximo de espera por resposta do DNS.</td></tr>
                        <tr><td>Sleep (Intervalo)</td><td>${SLEEP}s</td><td>Pausa entre tentativas consecutivas (consistency check).</td></tr>
                        <tr><td>Valida Conectividade</td><td>${VALIDATE_CONNECTIVITY}</td><td>Testa porta 53 antes do envio da query.</td></tr>
                        <tr><td>Check BIND Version</td><td>${CHECK_BIND_VERSION}</td><td>Consulta caos class para versão do BIND.</td></tr>
                        <tr><td>Ping Enabled</td><td>${ENABLE_PING}</td><td>Verificação de latência ICMP (Count: ${PING_COUNT}, Timeout: ${PING_TIMEOUT}s).</td></tr>
                        <tr><td>TCP Check (+tcp)</td><td>${ENABLE_TCP_CHECK}</td><td>Obrigatoriedade de suporte a DNS via TCP.</td></tr>
                        <tr><td>DNSSEC Check (+dnssec)</td><td>${ENABLE_DNSSEC_CHECK}</td><td>Validação da cadeia de confiança DNSSEC.</td></tr>
                        <tr><td>Trace Route Check</td><td>${ENABLE_TRACE_CHECK}</td><td>Mapeamento de rota até o servidor.</td></tr>
                        <tr><td>Consistency Checks</td><td>${CONSISTENCY_CHECKS} tentativas</td><td>Repetições para validar estabilidade da resposta.</td></tr>
                        <tr><td>Strict Criteria</td><td>IP=${STRICT_IP_CHECK} | Order=${STRICT_ORDER_CHECK} | TTL=${STRICT_TTL_CHECK}</td><td>Regras rígidas para considerar divergência.</td></tr>
                        <tr><td>Iterative DIG Options</td><td>${DEFAULT_DIG_OPTIONS}</td><td>Flags RAW enviadas ao DIG (Modo Iterativo).</td></tr>
                        <tr><td>Recursive DIG Options</td><td>${RECURSIVE_DIG_OPTIONS}</td><td>Flags RAW enviadas ao DIG (Modo Recursivo).</td></tr>
                        <tr><td>Latency Threshold</td><td>${LATENCY_WARNING_THRESHOLD}ms</td><td>Acima deste valor, a resposta é marcada como 'Slow' (Alerta).</td></tr>
                        <tr><td>Packet Loss Limit</td><td>${PING_PACKET_LOSS_LIMIT}%</td><td>Tolerância máxima de perda de pacotes antes de falhar o teste.</td></tr>
                        <tr><td>HTML Charts</td><td>${ENABLE_CHARTS}</td><td>Geração de gráficos visuais (Requer Internet).</td></tr>
                        <tr><td>Color Output</td><td>${COLOR_OUTPUT}</td><td>Indica se a saída do terminal utiliza códigos de cores ANSI.</td></tr>
                    </tbody>
                 </table>
                 </div>
                 
                 <!-- Config Files Dump -->
                 <h3 style="margin-top:30px; font-size:1rem; color:var(--text-secondary); border-bottom:1px solid #334155; padding-bottom:5px;">📂 Arquivo de Domínios ($FILE_DOMAINS)</h3>
                 <div class="table-responsive">
                     <table>
                        <thead><tr><th>Domínio</th><th>Grupos</th><th>Tipos Teste</th><th>Records</th><th>Hosts Extras</th></tr></thead>
                        <tbody>
EOF
    if [[ -f "$FILE_DOMAINS" ]]; then
        while IFS=';' read -r col1 col2 col3 col4 col5 || [ -n "$col1" ]; do
             [[ "$col1" =~ ^# || -z "$col1" ]] && continue
             echo "<tr><td>$col1</td><td>$col2</td><td>$col3</td><td>$col4</td><td>$col5</td></tr>" >> "$TEMP_CONFIG"
        done < "$FILE_DOMAINS"
    else
        echo "<tr><td colspan='5'>Arquivo não encontrado.</td></tr>" >> "$TEMP_CONFIG"
    fi

    cat >> "$TEMP_CONFIG" << EOF
                        </tbody>
                     </table>
                 </div>

                 <h3 style="margin-top:30px; font-size:1rem; color:var(--text-secondary); border-bottom:1px solid #334155; padding-bottom:5px;">📂 Arquivo de Grupos DNS ($FILE_GROUPS)</h3>
                 <div class="table-responsive">
                     <table>
                        <thead><tr><th>Nome Grupo</th><th>Descrição</th><th>Tipo</th><th>Timeout</th><th>Servidores</th></tr></thead>
                        <tbody>
EOF
    if [[ -f "$FILE_GROUPS" ]]; then
        while IFS=';' read -r g1 g2 g3 g4 g5 || [ -n "$g1" ]; do
             [[ "$g1" =~ ^# || -z "$g1" ]] && continue
             echo "<tr><td>$g1</td><td>$g2</td><td>$g3</td><td>$g4</td><td>$g5</td></tr>" >> "$TEMP_CONFIG"
        done < "$FILE_GROUPS"
    else
        echo "<tr><td colspan='5'>Arquivo não encontrado.</td></tr>" >> "$TEMP_CONFIG"
    fi

    cat >> "$TEMP_CONFIG" << EOF
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
                <div id="modalText"></div>
            </div>
        </div>
    </div>
    
    <script>
        function showInfoModal(title, description) {
            document.getElementById('modalTitle').innerText = title;
            
            var modalText = document.getElementById('modalText');
            // Construct a nicer layout
            var niceHtml = '<div class="info-header"><div class="info-icon">ℹ️</div><div class="info-title">' + title + '</div></div>';
            niceHtml += '<div class="info-body">' + description + '</div>';
            
            modalText.innerHTML = niceHtml;
            modalText.className = 'modal-info-content';
            
            document.getElementById('logModal').style.display = 'block';
        }

        // Reuse existing closeModal function or ensure it exists in main JS
        // (Assuming main structure has closeModal logic, but we should ensure compatibility)
    </script>
EOF
}



generate_charts_script() {
    cat << EOF
    <script>
        // Chart Configuration
        Chart.defaults.color = '#94a3b8';
        Chart.defaults.borderColor = '#334155';
        Chart.defaults.font.family = "system-ui, -apple-system, sans-serif";

        const ctxOverview = document.getElementById('chartOverview');
        const ctxLatency = document.getElementById('chartLatency');
        const ctxSecurity = document.getElementById('chartSecurity');
        const ctxServices = document.getElementById('chartServices');

        let overviewChart;

        function initOverviewChart(type) {
            if (overviewChart) overviewChart.destroy();
            
            if (ctxOverview) {
                overviewChart = new Chart(ctxOverview, {
                    type: type,
                    data: {
                        labels: ['Sucesso ($SUCCESS_TESTS)', 'Alertas ($WARNING_TESTS)', 'Falhas ($FAILED_TESTS)', 'Divergências ($DIVERGENT_TESTS)'],
                        datasets: [{
                            data: [$SUCCESS_TESTS, $WARNING_TESTS, $FAILED_TESTS, $DIVERGENT_TESTS],
                            backgroundColor: ['#10b981', '#f59e0b', '#ef4444', '#d946ef'],
                            borderWidth: 0
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        plugins: {
                            legend: { 
                                position: 'bottom',
                                labels: { color: '#cbd5e1', padding: 20, font: { size: 11 } }
                            },
                            tooltip: {
                                callbacks: {
                                    label: function(context) {
                                        let label = context.label || '';
                                        let value = context.parsed;
                                        let total = context.chart._metasets[context.datasetIndex].total;
                                        let percentage = ((value / total) * 100).toFixed(1) + '%';
                                        return label.split(' ')[0] + ': ' + value + ' (' + percentage + ')';
                                    }
                                }
                            }
                        }
                    }
                });
            }
        }

        // Initialize with default type
        initOverviewChart('doughnut');

        // Toggle Function
        window.updateChartType = function(id, type) {
            if (id === 'chartOverview') {
                initOverviewChart(type);
            }
        };

        // Latency Chart
        const latencyLabels = [];
        const latencyData = [];

EOF

    # Fix Latency Extraction: Strip HTML tags and handle decimals
    if [[ -f "$TEMP_PING" ]]; then
         sed "s/<\/td><td[^>]*>/|/g" "$TEMP_PING" | awk -F'|' '/<tr><td>/ { 
             server=$2; gsub(/<[^>]*>/, "", server); # Strip HTML tags
             val=$5; sub(/ms.*/, "", val); sub(/<.*/, "", val);
             # Clean any non-numeric except dot
             gsub(/[^0-9.]/, "", val);
             if (val ~ /^[0-9]+(\.[0-9]+)?$/) print server " " val 
         }' | sort -k2 -nr | head -n 12 | while read -r srv lat; do
             echo "        latencyLabels.push('$srv');"
             echo "        latencyData.push($lat);"
         done
    fi

        # Traceroute Chart Data Extraction
        echo "        const traceLabels = [];"
        echo "        const traceData = [];"
    if [[ -f "$TEMP_TRACE" ]]; then
         sed "s/<\/td><td[^>]*>/|/g" "$TEMP_TRACE" | awk -F'|' '/<tr><td>/ {
             server=$2; gsub(/<[^>]*>/, "", server);
             hops=$3; gsub(/<[^>]*>/, "", hops); gsub(/[^0-9]/, "", hops);
             if (hops ~ /^[0-9]+$/) print server " " hops
         }' | head -n 20 | while read -r srv hops; do
             echo "        traceLabels.push('$srv');"
             echo "        traceData.push($hops);"
         done
    fi

cat << EOF
        const colorPalette = ['#3b82f6', '#ef4444', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16', '#f97316', '#6366f1'];

        if (ctxLatency && latencyData.length > 0) {
            new Chart(ctxLatency, {
                type: 'bar',
                data: {
                    labels: latencyLabels,
                    datasets: [{
                        label: 'Latência (ms)',
                        data: latencyData,
                        backgroundColor: colorPalette,
                        borderRadius: 4,
                        barThickness: 15
                    }]
                },
                options: {
                    indexAxis: 'y',
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                         x: { beginAtZero: true, grid: { color: '#334155', drawBorder: false } },
                         y: { grid: { display: false } }
                    },
                     plugins: { legend: { display: false } }
                }
            });
        }

        // Detailed Latency Chart for ICMP Section
        const ctxLatencyDetail = document.getElementById('chartLatencyDetail');
        if (ctxLatencyDetail && latencyData.length > 0) {
            new Chart(ctxLatencyDetail, {
                type: 'bar',
                data: {
                    labels: latencyLabels,
                    datasets: [{
                        label: 'Latência (ms)',
                        data: latencyData,
                        backgroundColor: colorPalette,
                        borderRadius: 4,
                        barThickness: 20
                    }]
                },
                options: {
                    indexAxis: 'y',
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                         x: { beginAtZero: true, grid: { color: '#334155', drawBorder: false } },
                         y: { grid: { display: false } }
                    },
                     plugins: { legend: { display: false } }
                }
            });
        }
        
        // Traceroute Chart
        const ctxTrace = document.getElementById('chartTrace');
        if (ctxTrace && traceData.length > 0) {
            new Chart(ctxTrace, {
                type: 'bar',
                data: {
                    labels: traceLabels,
                    datasets: [{
                        label: 'Saltos (Hops)',
                        data: traceData,
                        backgroundColor: colorPalette,
                        borderRadius: 4,
                        barThickness: 15
                    }]
                },
                options: {
                    indexAxis: 'x', // Vertical bars
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                         y: { beginAtZero: true, grid: { color: '#334155' } },
                         x: { grid: { display: false } }
                    },
                     plugins: { legend: { display: false } }
                }
            });
        }
        
        // Services Chart (TCP / DNSSEC)
        if (ctxServices) {
            new Chart(ctxServices, {
                type: 'bar',
                data: {
                    labels: ['TCP Connection', 'DNSSEC Validation'],
                    datasets: [
                        {
                            label: 'Success',
                            data: [$TCP_SUCCESS, $DNSSEC_SUCCESS],
                            backgroundColor: '#10b981'
                        },
                        {
                            label: 'Fail',
                            data: [$TCP_FAIL, $DNSSEC_FAIL],
                            backgroundColor: '#ef4444'
                        },
                         {
                            label: 'Absent',
                            data: [0, $DNSSEC_ABSENT],
                            backgroundColor: '#94a3b8'
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: { stacked: true, grid: { display: false } },
                        y: { stacked: true, beginAtZero: true, grid: { color: '#334155' } }
                    }
                }
            });
        }

        // Security Chart
        if (ctxSecurity) {
            new Chart(ctxSecurity, {
                type: 'bar',
                data: {
                    labels: ['Version Hiding', 'Zone Transfer', 'Recursion Control'],
                    datasets: [
                        {
                            label: 'Restricted',
                            data: [$SEC_HIDDEN, $SEC_AXFR_OK, $SEC_REC_OK],
                            backgroundColor: '#10b981',
                             stack: 'Stack 0'
                        },
                        {
                            label: 'Risk/Open',
                            data: [$SEC_REVEALED, $SEC_AXFR_RISK, $SEC_REC_RISK],
                            backgroundColor: '#ef4444',
                             stack: 'Stack 0'
                        },
                         {
                            label: 'Error',
                            data: [$SEC_VER_TIMEOUT, $SEC_AXFR_TIMEOUT, $SEC_REC_TIMEOUT],
                            backgroundColor: '#94a3b8',
                             stack: 'Stack 0'
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: {
                        mode: 'index',
                        intersect: false,
                    },
                    scales: {
                        x: { stacked: true, grid: { display: false } },
                        y: { stacked: true, beginAtZero: true, grid: { color: '#334155' } }
                    }
                }
            });
        }
    </script>
EOF
}

generate_group_stats_html() {
    # Appends Group Statistics & Detailed Counters to TEMP_STATS
    # This should be called after generate_stats_block
    
    # 1. Detailed Counters Section
    # Calculate percentages for detailed counters
    local p_noerror=0; [[ $TOTAL_TESTS -gt 0 ]] && p_noerror=$(( (CNT_NOERROR * 100) / TOTAL_TESTS ))
    local p_nxdomain=0; [[ $TOTAL_TESTS -gt 0 ]] && p_nxdomain=$(( (CNT_NXDOMAIN * 100) / TOTAL_TESTS ))
    local p_servfail=0; [[ $TOTAL_TESTS -gt 0 ]] && p_servfail=$(( (CNT_SERVFAIL * 100) / TOTAL_TESTS ))
    local p_refused=0; [[ $TOTAL_TESTS -gt 0 ]] && p_refused=$(( (CNT_REFUSED * 100) / TOTAL_TESTS ))
    local p_timeout=0; [[ $TOTAL_TESTS -gt 0 ]] && p_timeout=$(( (CNT_TIMEOUT * 100) / TOTAL_TESTS ))

    cat >> "$TEMP_STATS" << EOF
    <div style="margin-top: 30px; margin-bottom: 20px;">
        <h3 style="color:var(--text-primary); border-bottom: 2px solid var(--border-color); padding-bottom: 10px; font-size:1.1rem;">📊 Detalhamento de Respostas e Grupos</h3>
        
        <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap:15px; margin-top:15px;">
            <div class="card" style="--card-accent: #10b981; padding:15px; text-align:center; cursor:pointer;" onclick="showInfoModal('NOERROR', 'O servidor processou a consulta com sucesso e retornou uma resposta válida (com ou sem dados).<br><br><b>Significado:</b> Operação normal.<br>Se a contagem for alta, indica saúde do sistema.')">
                <div style="font-size:1.5rem; font-weight:bold;">${CNT_NOERROR}</div>
                <div style="font-size:0.8rem; color:var(--text-secondary);">NOERROR</div>
                <div style="font-size:0.7rem; color:#10b981;">${p_noerror}%</div>
            </div>
            <div class="card" style="--card-accent: #f59e0b; padding:15px; text-align:center; cursor:pointer;" onclick="showInfoModal('NXDOMAIN', 'O domínio consultado NÃO EXISTE no servidor.<br><br><b>Significado:</b> Resposta autoritativa de que o nome é inválido.<br>Comum se houver erros de digitação ou domínios expirados.')">
                <div style="font-size:1.5rem; font-weight:bold;">${CNT_NXDOMAIN}</div>
                <div style="font-size:0.8rem; color:var(--text-secondary);">NXDOMAIN</div>
                <div style="font-size:0.7rem; color:#f59e0b;">${p_nxdomain}%</div>
            </div>
             <div class="card" style="--card-accent: #ef4444; padding:15px; text-align:center; cursor:pointer;" onclick="showInfoModal('SERVFAIL', 'Falha interna no servidor DNS.<br><br><b>Significado:</b> O servidor não conseguiu completar a requisição devido a erros internos (DNSSEC falho, backend down, etc).<br>Isso indica um problema grave no provedor.')">
                <div style="font-size:1.5rem; font-weight:bold;">${CNT_SERVFAIL}</div>
                <div style="font-size:0.8rem; color:var(--text-secondary);">SERVFAIL</div>
                <div style="font-size:0.7rem; color:#ef4444;">${p_servfail}%</div>
            </div>
             <div class="card" style="--card-accent: #ef4444; padding:15px; text-align:center; cursor:pointer;" onclick="showInfoModal('REFUSED', 'O servidor RECUSOU a conexão por política (ACL).<br><br><b>Significado:</b> Você não tem permissão para consultar este servidor (ex: servidor interno exposto, ou rate-limit atingido).')">
                <div style="font-size:1.5rem; font-weight:bold;">${CNT_REFUSED}</div>
                <div style="font-size:0.8rem; color:var(--text-secondary);">REFUSED</div>
                 <div style="font-size:0.7rem; color:#ef4444;">${p_refused}%</div>
            </div>
             <div class="card" style="--card-accent: #b91c1c; padding:15px; text-align:center; cursor:pointer;" onclick="showInfoModal('TIMEOUT', 'O servidor não respondeu dentro do tempo limite (${TIMEOUT}s).<br><br><b>Significado:</b> Perda de pacote ou servidor sobrecarregado/offline.<br>Diferente de REFUSED, aqui não houve resposta alguma.')">
                <div style="font-size:1.5rem; font-weight:bold;">${CNT_TIMEOUT}</div>
                <div style="font-size:0.8rem; color:var(--text-secondary);">TIMEOUT</div>
                 <div style="font-size:0.7rem; color:#b91c1c;">${p_timeout}%</div>
            </div>
             <div class="card" style="--card-accent: #64748b; padding:15px; text-align:center; cursor:pointer;" onclick="showInfoModal('NET ERROR', 'Erros de rede de baixo nível (Socket, Unreachable).<br><br><b>Significado:</b> Falha na camada de transporte antes mesmo do protocolo DNS.')">
                <div style="font-size:1.5rem; font-weight:bold;">${CNT_NETWORK_ERROR}</div>
                <div style="font-size:0.8rem; color:var(--text-secondary);">NET ERROR</div>
            </div>
        </div>
    </div>

    <!-- Group Stats Table -->
    <div class="table-responsive" style="margin-top:20px;">
        <table style="width:100%; border-collapse: collapse; font-size:0.9rem;">
            <thead>
                <tr style="background:var(--bg-secondary); text-align:left;">
                    <th style="padding:10px; cursor:pointer;" onclick="showInfoModal('Grupo DNS', 'Agrupamento lógico dos servidores (ex: Google, Cloudflare).')">Grupo DNS ℹ️</th>
                    <th style="padding:10px; cursor:pointer;" onclick="showInfoModal('Latência Média', 'Média do tempo de resposta (Ping RTT) de todos os servidores deste grupo.<br><br><b>Alta Latência:</b> Indica lentidão na rede ou sobrecarga no servidor.')">Latência Média (Ping) ℹ️</th>
                    <th style="padding:10px; cursor:pointer;" onclick="showInfoModal('Testes Totais', 'Número total de consultas DNS realizadas neste grupo.')">Testes Totais ℹ️</th>
                    <th style="padding:10px; cursor:pointer; color:var(--accent-danger);" onclick="showInfoModal('Falhas (DNS)', 'Contagem de erros não-tratados como SERVFAIL, REFUSED ou TIMEOUT.<br><br><b>Atenção:</b> NXDOMAIN não é falha, é resposta válida.')">Falhas (DNS) ℹ️</th>
                    <th style="padding:10px;">Status</th>
                </tr>
            </thead>
            <tbody>
EOF

    for grp in "${!ACTIVE_GROUPS[@]}"; do
        local g_rtt_sum=0
        local g_rtt_cnt=0
        for ip in ${DNS_GROUPS[$grp]}; do
            if [[ -n "${IP_RTT_RAW[$ip]}" ]]; then
                g_rtt_sum=$(LC_ALL=C awk "BEGIN {print $g_rtt_sum + ${IP_RTT_RAW[$ip]}}")
                g_rtt_cnt=$((g_rtt_cnt + 1))
            fi
        done
        local g_avg="N/A"
        [[ $g_rtt_cnt -gt 0 ]] && g_avg=$(LC_ALL=C awk "BEGIN {printf \"%.1fms\", $g_rtt_sum / $g_rtt_cnt}")
        
        local g_fail_cnt=${GROUP_FAIL_TESTS[$grp]}
        [[ -z "$g_fail_cnt" ]] && g_fail_cnt=0
        local g_total_cnt=${GROUP_TOTAL_TESTS[$grp]}
        [[ -z "$g_total_cnt" ]] && g_total_cnt=0
        
        local fail_rate="0"
        [[ $g_total_cnt -gt 0 ]] && fail_rate="$(( (g_fail_cnt * 100) / g_total_cnt ))"
        
        local row_style=""
        local status_badge="<span class='badge status-ok' style='background:#059669;'>Healthy</span>"
        
        if [[ $fail_rate -gt 0 ]]; then
            row_style="background:rgba(239,68,68,0.05);"
            status_badge="<span class='badge status-fail' style='background:#dc2626;'>Isues (${fail_rate}%)</span>"
        fi
        [[ $g_avg == "N/A" ]] && status_badge="<span class='badge' style='background:#64748b;'>No Data</span>"

        cat >> "$TEMP_STATS" << ROW
            <tr style="border-bottom:1px solid var(--border-color); $row_style">
                <td style="padding:10px; font-weight:600;">$grp</td>
                <td style="padding:10px;">$g_avg</td>
                <td style="padding:10px;">$g_total_cnt</td>
                <td style="padding:10px; color:var(--accent-danger); font-weight:bold; cursor:pointer;" onclick="showInfoModal('Falhas no Grupo $grp', 'Este grupo apresentou <b>$g_fail_cnt</b> falhas durante os testes.<br>Verifique se os IPs estão acessíveis e se o serviço DNS está rodando.')">$g_fail_cnt</td>
                <td style="padding:10px;">$status_badge</td>
            </tr>
ROW
    done

    cat >> "$TEMP_STATS" << EOF
            </tbody>
        </table>
    </div>
EOF
}

assemble_html() {
    local mode="$1"
    local target_file="$HTML_FILE"
    
    if [[ "$mode" == "simple" ]]; then
        target_file="${HTML_FILE%.html}_simple.html"
    fi
    
    
    # Check internet before generation if charts enabled
    prepare_chart_resources
    
    generate_stats_block
    generate_group_stats_html
    generate_object_summary
    generate_timing_html
    generate_disclaimer_html 
    generate_config_html
    generate_modal_html
    generate_help_html

    # Reset header for simple/full difference (banner)
    > "$TEMP_HEADER"
    write_html_header "$mode"

    cat "$TEMP_HEADER" >> "$target_file"
    cat "$TEMP_MODAL" >> "$target_file"
    cat "$TEMP_STATS" >> "$target_file"
    
    
    if [[ "$mode" == "simple" ]]; then
        cat "$TEMP_MATRIX_SIMPLE" >> "$target_file"
    else
        cat "$TEMP_MATRIX" >> "$target_file"
    fi
    
    cat >> "$target_file" << EOF
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
         if [[ "$ENABLE_CHARTS" == "true" ]]; then
              cat >> "$target_file" << EOF
              <!-- Chart Injection for ICMP Section -->
              <div class="card" style="margin-bottom: 20px; --card-accent: var(--accent-warning); cursor: pointer;" onclick="this.nextElementSibling.open = !this.nextElementSibling.open">
                   <h3 style="margin-top:0; font-size:1rem; margin-bottom:15px;">📊 Detalhe de Latência por Servidor</h3>
                   <div style="position: relative; height: 300px; width: 100%;">
                      <canvas id="chartLatencyDetail"></canvas>
                   </div>
                   <div style="text-align:center; font-size:0.8rem; color:var(--text-secondary); margin-top:5px;">(Clique para expandir/recolher detalhes)</div>
              </div>
EOF
         fi

         cat >> "$target_file" << EOF
         <details class="section-details" style="margin-top: 30px; border-left: 4px solid var(--accent-warning);">
              <summary style="font-size: 1.1rem; font-weight: 600;">📡 Latência e Disponibilidade (ICMP)</summary>
              <div class="table-responsive" style="padding:15px;">
              
              <table><thead><tr><th>Grupo</th><th>Servidor</th><th>Status</th><th>Perda (%)</th><th>Latência Média</th></tr></thead><tbody>
EOF
        if [[ "$mode" == "simple" ]]; then
             cat "$TEMP_PING_SIMPLE" >> "$target_file"
        else
             cat "$TEMP_PING" >> "$target_file"
        fi
        echo "</tbody></table></div></details>" >> "$target_file"
    fi

    # SECTION: SECURITY (AXFR, Version, Recursion)
    if [[ -s "$TEMP_SECURITY" ]]; then
        # Inject Chart BEFORE the details block? No, inside description or after title.
        # Ideally inside the details block for clean layout, but standard approach here is appending files.
        # We can construct the header manually here to inject chart.
        
        if [[ "$mode" == "simple" ]]; then
             cat "$TEMP_SECURITY_SIMPLE" >> "$target_file"
        else
             # For Full Mode, TEMP_SECURITY contains the whole block wrapper if generated by generate_security_html?
             # No, generate_security_html wraps it.
             # Let's check generate_security_html (It wraps in <details>).
             # To inject chart inside, we would need to edit generate_security_html.
             # ALTERNATIVE: Place chart ABOVE the table, but we can't edit the temp file easily now.
             # BETTER: Place chart ABOVE the details block.
             if [[ "$ENABLE_CHARTS" == "true" ]]; then
                 cat >> "$target_file" << EOF
                 <div class="card" style="margin-top: 20px; --card-accent: var(--accent-danger); cursor: pointer;" onclick="this.nextElementSibling.open = !this.nextElementSibling.open">
                     <h3 style="margin-top:0; font-size:1rem; margin-bottom:15px;">📊 Gráfico de Conformidade de Segurança</h3>
                     <div style="position: relative; height: 300px; width: 100%;">
                        <canvas id="chartSecurity"></canvas>
                     </div>
                     <div style="text-align:center; font-size:0.8rem; color:var(--text-secondary); margin-top:5px;">(Clique para expandir/recolher detalhes)</div>
                 </div>
EOF
             fi
             cat "$TEMP_SECURITY" >> "$target_file"
        fi
    fi

    if [[ -s "$TEMP_TRACE" ]]; then
         if [[ "$ENABLE_CHARTS" == "true" ]]; then
             cat >> "$target_file" << EOF
                 <div class="card" style="margin-top: 20px; --card-accent: var(--accent-divergent); cursor: pointer;" onclick="this.nextElementSibling.open = !this.nextElementSibling.open">
                     <h3 style="margin-top:0; font-size:1rem; margin-bottom:15px;">📊 Topologia de Rede (Hops)</h3>
                     <div style="position: relative; height: 300px; width: 100%;">
                        <canvas id="chartTrace"></canvas>
                     </div>
                     <div style="text-align:center; font-size:0.8rem; color:var(--text-secondary); margin-top:5px;">(Clique para expandir/recolher detalhes)</div>
                 </div>
EOF
         fi
         
         cat >> "$target_file" << EOF
        <details class="section-details" style="margin-top: 20px; border-left: 4px solid var(--accent-divergent);">
             <summary style="font-size: 1.1rem; font-weight: 600;">🛤️ Rota de Rede (Traceroute)</summary>
             <div class="table-responsive" style="padding:15px;">
EOF
        if [[ "$mode" == "simple" ]]; then
             cat "$TEMP_TRACE_SIMPLE" >> "$target_file"
        else
             cat "$TEMP_TRACE" >> "$target_file"
        fi
        echo "</div></details>" >> "$target_file"
    fi

    # SECTION: SERVICES (TCP, DNSSEC) - Moved to generate_object_summary
    # Content handled by logs/temp_obj_summary_$$.html
    
    # Mover Resumo da Execução para cá (após os resultados, antes das configs)
    cat "logs/temp_obj_summary_$$.html" >> "$target_file"

    if [[ "$ENABLE_CHARTS" == "true" ]]; then
        generate_charts_script >> "$target_file"
    fi

    cat >> "$target_file" << EOF
        <div style="display:none;">
EOF
    if [[ "$mode" != "simple" ]]; then
         cat "$TEMP_DETAILS" >> "$target_file"
    fi
    echo "</div>" >> "$target_file"
    cat "$TEMP_CONFIG" >> "$target_file"
    cat "$TEMP_TIMING" >> "$target_file"
    cat "logs/temp_help_$$.html" >> "$target_file"


    cat "$TEMP_DISCLAIMER" >> "$target_file"

    cat >> "$target_file" << EOF
        <footer>
            Gerado automaticamente por <strong>DNS Diagnostic Tool (v$SCRIPT_VERSION)</strong><br>
        </footer>
    </div>
    <a href="#top" style="position:fixed; bottom:20px; right:20px; background:var(--accent-primary); color:white; width:40px; height:40px; border-radius:50%; display:flex; align-items:center; justify-content:center; text-decoration:none; box-shadow:0 4px 10px rgba(0,0,0,0.3); font-size:1.2rem;">⬆️</a>
    <script>
        document.getElementById('total_time_placeholder').innerText = "${TOTAL_DURATION}s";
    </script>
</body>
</html>
EOF
    # Clean up handled by trap
}

generate_security_html() {
    # Generate HTML block if there is data
    if [[ -s "$TEMP_SEC_ROWS" ]]; then
        local sec_content
        sec_content=$(cat "$TEMP_SEC_ROWS")
        
        # Simple Mode
        if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
            cat >> "$TEMP_SECURITY_SIMPLE" << EOF
            <details class="section-details" style="margin-top: 20px; border-left: 4px solid var(--accent-danger);">
                 <summary style="font-size: 1.1rem; font-weight: 600;">🛡️ Análise de Segurança & Riscos</summary>
                 <div class="table-responsive" style="padding:15px;">
                 <table>
                    <thead>
                        <tr>
                            <th>Servidor</th>
                            <th>Versão (Privacy)</th>
                            <th>AXFR (Zone Transfer)</th>
                            <th>Recursão (Open Relay)</th>
                        </tr>
                    </thead>
                    <tbody>
                        $sec_content
                    </tbody>
                 </table>
                 </div>
            </details>
EOF
        fi

        # Full Mode (Uses same content for now, maybe add raw logs details later if needed)
        # Full Mode: Overwrite TEMP_SECURITY with the final HTML block
        cat > "$TEMP_SECURITY" << EOF
        <details class="section-details" style="margin-top: 20px; border-left: 4px solid var(--accent-danger);">
             <summary style="font-size: 1.1rem; font-weight: 600;">🛡️ Análise de Segurança & Riscos</summary>
             <div class="table-responsive" style="padding:15px;">
             <table>
                <thead>
                    <tr>
                        <th>Servidor</th>
                        <th style="cursor:pointer;" onclick="showInfoModal('BIND Version', '<b>Version Hiding:</b><br>Servidores DNS seguros não devem revelar sua versão de software (BIND, etc) para evitar exploits específicos.<br><br><b>Hidden:</b> Seguro (OK)<br><b>Revealed:</b> Inseguro')">Versão (Privacy) ℹ️</th>
                        <th style="cursor:pointer;" onclick="showInfoModal('AXFR (Zone Transfer)', '<b>Transferência de Zona:</b><br>Permite baixar TODOS os registros do domínio.<br><br><b>Negado/Refused:</b> Seguro (OK)<br><b>Allowed/SOA:</b> Crítico! Vazamento de dados.')">AXFR (Zone Transfer) ℹ️</th>
                        <th style="cursor:pointer;" onclick="showInfoModal('Recursão Aberta', '<b>Open Resolver:</b><br>Servidores autoritativos NÃO devem responder consultas recursivas (ex: google.com) para estranhos.<br><br><b>Closed/Refused:</b> Seguro (OK)<br><b>Open:</b> Risco de ataque DDoS (Amplificação).')">Recursão (Open Relay) ℹ️</th>
                    </tr>
                </thead>
                <tbody>
                    $sec_content
                </tbody>
             </table>
             </div>
        </details>
EOF
    fi
}

# ==============================================
# LÓGICA PRINCIPAL (CORE)
# ==============================================

load_dns_groups() {
    declare -gA DNS_GROUPS; declare -gA DNS_GROUP_DESC; declare -gA DNS_GROUP_TYPE; declare -gA DNS_GROUP_TIMEOUT; declare -gA ACTIVE_GROUPS
    [[ ! -f "$FILE_GROUPS" ]] && { echo -e "${RED}ERRO: $FILE_GROUPS não encontrado!${NC}"; exit 1; }
    while IFS=';' read -r name desc type timeout servers || [ -n "$name" ]; do
        [[ "$name" =~ ^# || -z "$name" ]] && continue
        name=$(echo "$name" | xargs); servers=$(echo "$servers" | tr -d '[:space:]')
        [[ -z "$timeout" ]] && timeout=$TIMEOUT
        IFS=',' read -ra srv_arr <<< "$servers"
        DNS_GROUPS["$name"]="${srv_arr[@]}"; DNS_GROUP_DESC["$name"]="$desc"; DNS_GROUP_TYPE["$name"]="$type"; DNS_GROUP_TIMEOUT["$name"]="$timeout"
    done < "$FILE_GROUPS"
}

run_security_diagnostics() {
    # Check if ANY security check is enabled
    if [[ "$CHECK_BIND_VERSION" != "true" && "$ENABLE_AXFR_CHECK" != "true" && "$ENABLE_RECURSION_CHECK" != "true" ]]; then
         return
    fi
    
    echo -e "\n${BLUE}=== INICIANDO SECURITY SCAN (Version/AXFR/Recurse) ===${NC}"
    log_section "SECURITY SCAN"

    # Temp file for rows
    local TEMP_SEC_ROWS="logs/temp_sec_rows_$$.html"
    > "$TEMP_SEC_ROWS"

    declare -A CHECKED_IPS; declare -A IP_GROUPS_MAP; local unique_ips=()
    for grp in "${!DNS_GROUPS[@]}"; do
        # Filter if ONLY_TEST_ACTIVE_GROUPS is true
        if [[ "$ONLY_TEST_ACTIVE_GROUPS" == "true" && -z "${ACTIVE_GROUPS[$grp]}" ]]; then continue; fi
        for ip in ${DNS_GROUPS[$grp]}; do
            local grp_label="[$grp]"
            [[ -z "${IP_GROUPS_MAP[$ip]}" ]] && IP_GROUPS_MAP[$ip]="$grp_label" || { [[ "${IP_GROUPS_MAP[$ip]}" != *"$grp_label"* ]] && IP_GROUPS_MAP[$ip]="${IP_GROUPS_MAP[$ip]} $grp_label"; }
            if [[ -z "${CHECKED_IPS[$ip]}" ]]; then CHECKED_IPS[$ip]=1; unique_ips+=("$ip"); fi
        done
    done

    for ip in "${unique_ips[@]}"; do
        local groups_str="${IP_GROUPS_MAP[$ip]}"
        echo -ne "   🛡️  Scanning ${groups_str} $ip ... "
        local risk_summary=()
        local error_summary=()
        
        # Helper to detect network errors
        is_network_error() {
            echo "$1" | grep -q -E -i "connection timed out|communications error|no servers could be reached|couldn't get address|network is unreachable|failed: timed out|host is unreachable|connection refused|no route to host"
        }

        # 1. VERSION CHECK
        if [[ "$CHECK_BIND_VERSION" == "true" ]]; then
            local clean_ip=${ip//./_}
            local ver_id="sec_ver_${clean_ip}"
            
            local v_cmd="dig +noall +answer +time=$TIMEOUT @$ip version.bind chaos txt"
            local tfile_ver=$(mktemp)
            /usr/bin/dig +noall +answer +time=$TIMEOUT @$ip version.bind chaos txt > "$tfile_ver" 2>&1
            local v_out=$(cat "$tfile_ver")
            rm -f "$tfile_ver"
            log_cmd_result "VERSION CHECK $ip" "$v_cmd" "$v_out" "0"
            
            if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                local safe_v_out=$(echo "$v_out" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                echo "<div id=\"${ver_id}_content\" style=\"display:none\"><pre>$safe_v_out</pre></div>" >> "$TEMP_DETAILS"
                echo "<div id=\"${ver_id}_title\" style=\"display:none\">Version Check | $ip</div>" >> "$TEMP_DETAILS"
            fi
            
            local v_res=""
            local v_class=""
            
            if is_network_error "$v_out"; then
                 v_res="TIMEOUT"
                 v_class="status-neutral" # Gray
                 SEC_VER_TIMEOUT+=1
                 if [[ "$VERBOSE" == "true" ]]; then echo -ne "${GRAY}Ver:TIMEOUT${NC} "; fi
            elif [[ -z "$v_out" ]] || echo "$v_out" | grep -q -E "REFUSED|SERVFAIL|no servers|timed out"; then
                 v_res="HIDDEN (OK)"
                 v_class="status-ok"
                 SEC_HIDDEN+=1
                 [[ "$VERBOSE" == "true" ]] && echo -ne "${GREEN}Ver:OK${NC} "
            else
                 local ver_str=$(echo "$v_out" | grep "TXT" | cut -d'"' -f2)
                 v_res="REVEALED: ${ver_str:0:15}..."
                 v_class="status-fail"
                 SEC_REVEALED+=1
                 [[ "$VERBOSE" == "true" ]] && echo -ne "${RED}Ver:RISK${NC} "
                 risk_summary+=("Ver")
            fi
            
            if echo "$v_out" | grep -q "connection timed out"; then
                 v_res="TIMEOUT"
                 v_class="status-neutral"
            fi

            local html_ver="<a href=\"#\" onclick=\"showLog('${ver_id}'); return false;\" class=\"status-cell\"><span class=\"badge $v_class\">$v_res</span></a>"
        else
            local html_ver="<span class=\"badge neutral\">N/A</span>"
        fi

        # 2. AXFR CHECK (Zone Transfer)
        if [[ "$ENABLE_AXFR_CHECK" == "true" ]]; then
            local target_axfr=""
            if [[ -f "$FILE_DOMAINS" ]]; then
                target_axfr=$(grep -vE '^\s*#|^\s*$' "$FILE_DOMAINS" | head -1 | awk -F';' '{print $1}')
            fi
            [[ -z "$target_axfr" ]] && target_axfr="example.com"
            
            local axfr_id="sec_axfr_${clean_ip}"
            local axfr_cmd="dig @$ip $target_axfr AXFR +time=$TIMEOUT +tries=1"
            local tfile_axfr=$(mktemp)
            /usr/bin/dig @$ip $target_axfr AXFR +time=$TIMEOUT +tries=1 > "$tfile_axfr" 2>&1
            local axfr_out=$(cat "$tfile_axfr")
            rm -f "$tfile_axfr"
            log_cmd_result "AXFR CHECK $ip ($target_axfr)" "$axfr_cmd" "${axfr_out:0:500}..." "0"
            
            if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                local safe_axfr_out=$(echo "$axfr_out" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                echo "<div id=\"${axfr_id}_content\" style=\"display:none\"><pre>$safe_axfr_out</pre></div>" >> "$TEMP_DETAILS"
                echo "<div id=\"${axfr_id}_title\" style=\"display:none\">AXFR Check | $ip ($target_axfr)</div>" >> "$TEMP_DETAILS"
            fi
            
            local axfr_res=""
            local axfr_class=""
            
            if echo "$axfr_out" | grep -q "SERVFAIL"; then
                 axfr_res="SERVFAIL (OK)"
                 axfr_class="status-ok"
                 SEC_AXFR_OK+=1
                 [[ "$VERBOSE" == "true" ]] && echo -ne "${GREEN}AXFR:OK${NC} "
            elif echo "$axfr_out" | grep -q -E "REFUSED|Transfer failed"; then
                 axfr_res="DENIED (OK)"
                 axfr_class="status-ok"
                 SEC_AXFR_OK+=1
                 [[ "$VERBOSE" == "true" ]] && echo -ne "${GREEN}AXFR:OK${NC} "
            elif is_network_error "$axfr_out"; then
                 axfr_res="TIMEOUT"
                 axfr_class="status-neutral"
                 SEC_AXFR_TIMEOUT+=1
                 if [[ "$VERBOSE" == "true" ]]; then echo -ne "${GRAY}AXFR:TIMEOUT${NC} "; fi
             elif echo "$axfr_out" | grep -q -i -E "Transfer failed|REFUSED|SERVFAIL|communications error|timed out|no servers"; then
                 # Fallback for other errors not caught above (weird timeouts?)
                 if echo "$axfr_out" | grep -q -E "timed out|no servers|communications error"; then
                     axfr_res="TIMEOUT"
                     axfr_class="status-neutral"
                     SEC_AXFR_TIMEOUT+=1
                     [[ "$VERBOSE" == "true" ]] && echo -ne "${GRAY}AXFR:TIMEOUT${NC} "
                 else
                     # Generic denial
                     axfr_res="DENIED (OK)"
                     axfr_class="status-ok"
                     SEC_AXFR_OK+=1
                     [[ "$VERBOSE" == "true" ]] && echo -ne "${GREEN}AXFR:OK${NC} "
                 fi
            elif echo "$axfr_out" | grep -q "SOA"; then
                 axfr_res="ALLOWED (RISK)"
                 axfr_class="status-fail"
                 SEC_AXFR_RISK+=1
                 [[ "$VERBOSE" == "true" ]] && echo -ne "${RED}AXFR:RISK${NC} "
                 risk_summary+=("AXFR(SOA)")
            else
                 axfr_res="NO DATA (OK)"
                 axfr_class="status-ok"
                 SEC_AXFR_OK+=1
                 [[ "$VERBOSE" == "true" ]] && echo -ne "${GREEN}AXFR:OK${NC} "
            fi
            local html_axfr="<a href=\"#\" onclick=\"showLog('${axfr_id}'); return false;\" class=\"status-cell\"><span class=\"badge $axfr_class\">$axfr_res</span></a>"
        else
            local html_axfr="<span class=\"badge neutral\">N/A</span>"
        fi

        # 3. RECURSION CHECK
        if [[ "$ENABLE_RECURSION_CHECK" == "true" ]]; then
            local rec_id="sec_rec_${clean_ip}"
            local rec_cmd="dig @$ip google.com A +recurse +time=$TIMEOUT +tries=1"
            local tfile_rec=$(mktemp)
            /usr/bin/dig @$ip google.com A +recurse +time=$TIMEOUT +tries=1 > "$tfile_rec" 2>&1
            local rec_out=$(cat "$tfile_rec")
            rm -f "$tfile_rec"
            log_cmd_result "RECURSION CHECK $ip" "$rec_cmd" "$rec_out" "0"

            if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                local safe_rec_out=$(echo "$rec_out" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                echo "<div id=\"${rec_id}_content\" style=\"display:none\"><pre>$safe_rec_out</pre></div>" >> "$TEMP_DETAILS"
                echo "<div id=\"${rec_id}_title\" style=\"display:none\">Recursion Check | $ip</div>" >> "$TEMP_DETAILS"
            fi
            
            local rec_res=""
            local rec_class=""
            
            if is_network_error "$rec_out"; then
                 rec_res="TIMEOUT"
                 rec_class="status-neutral"
                 SEC_REC_TIMEOUT+=1
                 if [[ "$VERBOSE" == "true" ]]; then echo -ne "${GRAY}Rec:TIMEOUT${NC}"; fi
            elif echo "$rec_out" | grep -qE "^google\.com\..*IN.*A.*[0-9]"; then
                 rec_res="OPEN (RISK)"
                 rec_class="status-fail"
                 SEC_REC_RISK+=1
                 [[ "$VERBOSE" == "true" ]] && echo -ne "${RED}Rec:RISK${NC}"
                 risk_summary+=("Rec")
            else
                 rec_res="CLOSED (OK)"
                 rec_class="status-ok"
                 SEC_REC_OK+=1
                 [[ "$VERBOSE" == "true" ]] && echo -ne "${GREEN}Rec:OK${NC}"
            fi
            local html_rec="<a href=\"#\" onclick=\"showLog('${rec_id}'); return false;\" class=\"status-cell\"><span class=\"badge $rec_class\">$rec_res</span></a>"
        else
            local html_rec="<span class=\"badge neutral\">N/A</span>"
        fi
        
        if [[ "$VERBOSE" == "true" ]]; then
           echo ""
        else
           if [[ ${#risk_summary[@]} -eq 0 ]]; then
               # Check if all were timeouts (no OKs, no Risks)
               # If v_res=TIMEOUT and axfr_res=TIMEOUT and rec_res=TIMEOUT, then it's not "Restricted", it's "Unreachable"
               if [[ "$v_res" == "TIMEOUT" || "$axfr_res" == "TIMEOUT" || "$rec_res" == "TIMEOUT" ]]; then
                    echo -e "${GRAY}⚠️ Timeouts${NC}"
               else
                    echo -e "${GREEN}✅ Restricted${NC}"
               fi
           else
               local risks=$(IFS=,; echo "${risk_summary[*]}")
               echo -e "${RED}⚠️ Risks: $risks${NC}"
           fi
        fi
        
        # Add Row
        echo "<tr><td><strong>$ip</strong></td><td>$html_ver</td><td>$html_axfr</td><td>$html_rec</td></tr>" >> "$TEMP_SEC_ROWS" 
        
        if [[ "$GENERATE_JSON_REPORT" == "true" ]]; then
            # Clean string values for JSON
            local j_ver=$(echo "$v_res" | sed 's/"/\\"/g')
            local j_axfr=$(echo "$axfr_res" | sed 's/"/\\"/g')
            local j_rec=$(echo "$rec_res" | sed 's/"/\\"/g')
            echo "{ \"ip\": \"$ip\", \"version_check\": \"$j_ver\", \"axfr_check\": \"$j_axfr\", \"recursion_check\": \"$j_rec\" }," >> "$TEMP_JSON_Sec"
        fi 
    done
    
    if [[ -s "$TEMP_SEC_ROWS" ]]; then
        generate_security_html 
    fi
}

run_ping_diagnostics() {
    [[ "$ENABLE_PING" != "true" ]] && return
    echo -e "\n${BLUE}=== INICIANDO PING ===${NC}"
    log_section "PING TEST"
    
    # Mantida a correção aqui
    ! command -v ping &> /dev/null && { echo "Ping not found"; return; }
    
    declare -A CHECKED_IPS; declare -A IP_GROUPS_MAP; local unique_ips=()
    for grp in "${!DNS_GROUPS[@]}"; do
        # Filter if ONLY_TEST_ACTIVE_GROUPS is true
        if [[ "$ONLY_TEST_ACTIVE_GROUPS" == "true" && -z "${ACTIVE_GROUPS[$grp]}" ]]; then continue; fi
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
        echo -ne "   📡 ${groups_str} $ip ... "
        
        # IP Version Auto-detection for Ping
        local ping_cmd="ping"
        if [[ "$ip" == *:* ]]; then
            # IPv6 detected
            if command -v ping6 &> /dev/null; then ping_cmd="ping6"; else ping_cmd="ping -6"; fi
        fi
        
        [[ "$VERBOSE" == "true" ]] && echo -e "\n     ${GRAY}[VERBOSE] Pinging $ip ($ping_cmd, Count=$PING_COUNT, Timeout=$PING_TIMEOUT)...${NC}"
        # Run Ping with LC_ALL=C to ensure dot decimals and standard format
        local start_ts=$(date +%s%N)
        local output
        output=$(LC_ALL=C $ping_cmd -c $PING_COUNT -W $PING_TIMEOUT $ip 2>&1)
        local ret=$?
        local end_ts=$(date +%s%N)
        local dur_p=$(( (end_ts - start_ts) / 1000000 ))
        
        TOTAL_PING_SENT+=$PING_COUNT
        
        log_cmd_result "PING $ip" "$ping_cmd -c $PING_COUNT -W $PING_TIMEOUT $ip" "$output" "$dur_p"
        
        # Parse packet loss more robustly
        local loss=$(echo "$output" | awk -F', ' '/packet loss/ {print $3}' | sed 's/% packet loss//g' | tr -d '\n')
        # If output format is different (some pings say "0% packet loss"), handle it:
        [[ -z "$loss" ]] && loss=$(echo "$output" | grep -oE '[0-9]+% packet loss' | awk '{print $1}' | tr -d '%')
        [[ -z "$loss" ]] && loss=100  # Safe fallback if parsing fails

        # Format: rtt min/avg/max/mdev = 1.2/3.4/5.6/0.1 ms
        local rtt_avg="N/A"
        local rtt_min="N/A"
        local rtt_max="N/A"
        local rtt_mdev="N/A"

        # Check if we have RTT line
        if [[ "$loss" != "100" ]] && echo "$output" | grep -q "rtt"; then
            # Extract the part after "="
            local rtt_vals=$(echo "$output" | grep "rtt" | sed 's/.* = //')
            # rtt_vals should be "val1/val2/val3/val4 ms"
            
            # Ensure commas are dots (redundant with LC_ALL=C but safe)
            rtt_vals=$(echo "$rtt_vals" | tr ',' '.')

            # Use awk with C locale to split by /
            rtt_min=$(echo "$rtt_vals" | LC_ALL=C awk -F '/' '{print $1}' | sed 's/[^0-9.]//g')
            rtt_avg=$(echo "$rtt_vals" | LC_ALL=C awk -F '/' '{print $2}' | sed 's/[^0-9.]//g')
            rtt_max=$(echo "$rtt_vals" | LC_ALL=C awk -F '/' '{print $3}' | sed 's/[^0-9.]//g')
            # mdev often has " ms" attached
            rtt_mdev=$(echo "$rtt_vals" | LC_ALL=C awk -F '/' '{print $4}' | awk '{print $1}' | sed 's/[^0-9.]//g')
        fi
        
        # Accumulate Latency for General Stats
        if [[ "$rtt_avg" != "N/A" && -n "$rtt_avg" ]]; then
             # Use LC_NUMERIC=C for awk addition to handle dots correctly
             TOTAL_LATENCY_SUM=$(LC_NUMERIC=C awk -v s="$TOTAL_LATENCY_SUM" -v v="$rtt_avg" 'BEGIN {print s + v}')
             TOTAL_LATENCY_COUNT=$((TOTAL_LATENCY_COUNT + 1))
             IP_RTT_RAW[$ip]="$rtt_avg"
        fi
        
        local rtt_fmt="${rtt_avg}"
        [[ "$rtt_avg" != "N/A" ]] && rtt_fmt="${rtt_avg}ms"
        # Optional: Detailed format for tooltips or logs could be: "$rtt_min/$rtt_avg/$rtt_max ms"

        local status_html=""; local class_html=""; local console_res=""
        if [[ "$ret" -ne 0 ]] || [[ "$loss" == "100" ]]; then status_html="❌ DOWN"; class_html="status-fail"; console_res="${RED}DOWN${NC}"
        elif [[ "$loss" != "0" ]]; then status_html="⚠️ UNSTABLE"; class_html="status-warning"; console_res="${YELLOW}${loss}% Loss${NC}"
        else status_html="✅ UP"; class_html="status-ok"; console_res="${GREEN}${rtt_fmt}${NC}"; fi
        
        echo -e "$console_res"
        if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
            echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td class=\"$class_html\">$status_html</td><td>${loss}%</td><td>${rtt_fmt}</td></tr>" >> "$TEMP_PING"
            local safe_output=$(echo "$output" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            echo "<tr><td colspan=\"5\" style=\"padding:0; border:none;\"><details style=\"margin:5px;\"><summary style=\"font-size:0.8em; color:#888;\">Ver output ping #$ping_id</summary><pre>$safe_output</pre></details></td></tr>" >> "$TEMP_PING"
        fi

        if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
            echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td class=\"$class_html\">$status_html</td><td>${loss}%</td><td>${rtt_fmt}</td></tr>" >> "$TEMP_PING_SIMPLE"
        fi
        
        if [[ "$GENERATE_JSON_REPORT" == "true" ]]; then
            # Clean RTT for JSON (remove 'ms' if exists, though awk above likely kept it pure numbers or N/A)
            # JSON format: { "ip": "...", "groups": "...", "status": "...", "loss_percent": ..., "rtt_avg_ms": ... },
            # We handle the trailing comma later or use a list join strategy
            local j_min="null"; [[ -n "$rtt_min" ]] && j_min="$rtt_min"
            local j_max="null"; [[ -n "$rtt_max" ]] && j_max="$rtt_max"
            local j_mdev="null"; [[ -n "$rtt_mdev" ]] && j_mdev="$rtt_mdev"
            
            echo "{ \"ip\": \"$ip\", \"groups\": \"$(echo $groups_str | xargs)\", \"status\": \"$(echo $status_html | sed 's/.* //')\", \"loss_percent\": \"$loss\", \"rtt_avg_ms\": \"$rtt_avg\", \"rtt_min_ms\": $j_min, \"rtt_max_ms\": $j_max, \"rtt_mdev_ms\": $j_mdev }," >> "$TEMP_JSON_Ping"
        fi
    done
}

run_trace_diagnostics() {
    [[ "$ENABLE_TRACE_CHECK" != "true" ]] && return
    echo -e "\n${BLUE}=== INICIANDO TRACEROUTE ===${NC}"
    log_section "TRACEROUTE NETWORK PATH"
    
    local cmd_trace=""
    if command -v traceroute &> /dev/null; then cmd_trace="traceroute -n -w $TIMEOUT -q 1 -m 30"
    elif command -v tracepath &> /dev/null; then cmd_trace="tracepath -n -m 30"
    else 
        echo -e "${YELLOW}⚠️ Traceroute/Tracepath não encontrados. Pulando.${NC}"
        echo "<p class=\"status-warning\" style=\"padding:15px;\">Ferramentas de trace não encontradas (instale traceroute ou iputils-tracepath).</p>" > "$TEMP_TRACE"
        return
    fi

    declare -A CHECKED_IPS; declare -A IP_GROUPS_MAP; local unique_ips=()
    for grp in "${!DNS_GROUPS[@]}"; do
        # Filter if ONLY_TEST_ACTIVE_GROUPS is true
        if [[ "$ONLY_TEST_ACTIVE_GROUPS" == "true" && -z "${ACTIVE_GROUPS[$grp]}" ]]; then continue; fi
        for ip in ${DNS_GROUPS[$grp]}; do
            local grp_label="[$grp]"
            [[ -z "${IP_GROUPS_MAP[$ip]}" ]] && IP_GROUPS_MAP[$ip]="$grp_label" || { [[ "${IP_GROUPS_MAP[$ip]}" != *"$grp_label"* ]] && IP_GROUPS_MAP[$ip]="${IP_GROUPS_MAP[$ip]} $grp_label"; }
            if [[ -z "${CHECKED_IPS[$ip]}" ]]; then CHECKED_IPS[$ip]=1; unique_ips+=("$ip"); fi
        done
    done

    if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
        echo "<table><thead><tr><th>Grupo</th><th>Servidor</th><th>Hops</th><th>Caminho (Resumo)</th></tr></thead><tbody>" >> "$TEMP_TRACE"
    fi
    if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
        echo "<table><thead><tr><th>Grupo</th><th>Servidor</th><th>Hops</th><th>Caminho (Resumo)</th></tr></thead><tbody>" >> "$TEMP_TRACE_SIMPLE"
    fi

    local trace_id=0
    for ip in "${unique_ips[@]}"; do
        trace_id=$((trace_id + 1))
        local groups_str="${IP_GROUPS_MAP[$ip]}"
        echo -ne "   🛤️ ${groups_str} $ip ... "
        
        local current_trace_cmd="$cmd_trace"
        if [[ "$ip" == *:* ]]; then
             # If strictly traceroute command, append -6
             if [[ "$cmd_trace" == *"traceroute"* ]]; then current_trace_cmd="$cmd_trace -6"; fi
             # tracepath usually handles detection or needs explicit 6 if distinct binary, 
             # but modern iputils tracepath auto-detects or tracepath6 exists. 
             # simpler to rely on tool auto-detection if not traceroute legacy.
        fi

        [[ "$VERBOSE" == "true" ]] && echo -e "\n     ${GRAY}[VERBOSE] Tracing route to $ip...${NC}"
        local start_t=$(date +%s%N)
        local output; output=$($current_trace_cmd $ip 2>&1); local ret=$?
        local end_t=$(date +%s%N); local dur_t=$(( (end_t - start_t) / 1000000 ))
        log_cmd_result "TRACE $ip" "$current_trace_cmd $ip" "$output" "$dur_t"
        
        # Validation of output
        local hops="-"
        local last_hop="Error/Timeout"
        local reached_dest="false"
        
        # Check if output looks valid (contains hops)
        if [[ $ret -eq 0 ]] && echo "$output" | grep -qE "^[ ]*[0-9]+"; then
            last_hop=$(echo "$output" | tail -1 | xargs)
            
            # Extract IP from last hop (usually 2nd field after hop num)
            local last_ip_extracted=$(echo "$last_hop" | awk '{print $2}')
            if [[ "$last_ip_extracted" == "$ip" ]]; then
                reached_dest="true"
            fi
            
            if [[ "$reached_dest" == "true" ]]; then
                 # If reached, the hop count is the last line's number
                 hops=$(echo "$last_hop" | awk '{print $1}')
            else
                 # If NOT reached, find the last RESPONSIVE hop (containing an IP)
                 # This avoids showing "30" just because it timed out at 30
                 local last_resp=$(echo "$output" | grep -E "^[ ]*[0-9]+.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | tail -1)
                 if [[ -n "$last_resp" ]]; then
                      hops=$(echo "$last_resp" | awk '{print $1}')
                 else
                      hops="0" # No hops responded
                 fi
                 
                 # Check if last hop is timeout stars only
                 if [[ "$last_hop" =~ ^[0-9]+\ +[\*\ ]+$ ]]; then
                    last_hop="Timeout (* * *)"
                 fi
            fi
        else
            # Try to extract error message if short enough, otherwise specific message
            if [[ ${#output} -lt 50 && -n "$output" ]]; then
                 last_hop="Error: $output"
            elif [[ -n "$output" ]]; then
                 last_hop="Trace failed (See expanded log)"
            fi
        fi
        
        local last_hop_clean="$last_hop"
        local last_hop_html=""
        local last_hop_plain=""

        if [[ "$reached_dest" == "true" ]]; then
            echo -e "${CYAN}${hops} hops${NC}"
            # last_hop variable for any legacy use? No, used locally.
            # But let's keep the terminal output correct if we used last_hop there? 
            # Oh, the echo -e above is the terminal output. we don't print LAST HOP to terminal.
            # Wait, line 2726/2728 in previous code did NOT print last hop to terminal, just hops.
            # My logic added last_hop="${GREEN}Reached...".
            # BUT i don't see it being ECHOED to terminal after that assignment.
            # It's only used in HTML generation below.
            
            last_hop_html="<span class='st-ok'>Reached:</span> $last_hop_clean"
            last_hop_plain="Reached: $last_hop_clean"
        else
            echo -e "${RED}${hops} hops (Incompleto)${NC}"
            last_hop_html="<span class='st-fail'>Stopped:</span> $last_hop_clean"
            last_hop_plain="Stopped: $last_hop_clean"
        fi
        
        if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
            local clean_ip=${ip//./_}
            local trace_id="trace_${clean_ip}"
            local safe_output=$(echo "$output" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            
            # Store in Modal Details Area
            echo "<div id=\"${trace_id}_content\" style=\"display:none\"><pre>$safe_output</pre></div>" >> "$TEMP_DETAILS"
            echo "<div id=\"${trace_id}_title\" style=\"display:none\">Traceroute | $ip</div>" >> "$TEMP_DETAILS"
            
            # Clickable Row
            local click_handler="onclick=\"showLog('${trace_id}'); return false;\""
            
            echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td><a href='#' $click_handler style='color:inherit; text-decoration:underline;'>${hops}</a></td><td><span style=\"font-size:0.85em; color:#888;\">$last_hop_html</span></td></tr>" >> "$TEMP_TRACE"
        fi

        if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
            echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td>${hops}</td><td><span style=\"font-size:0.85em; color:#888;\">$last_hop_html</span></td></tr>" >> "$TEMP_TRACE_SIMPLE"
        fi
        
        if [[ "$GENERATE_JSON_REPORT" == "true" ]]; then
            # Clean output for JSON string to avoid breaking json
            local j_out=$(echo "$output" | tr '"' "'" | tr '\n' ' ' | sed 's/\\/\\\\/g')
            local j_hops="$hops" # string or number
            if [[ "$hops" == "-" ]]; then j_hops=0; fi
            local clean_last_hop=$(echo "$last_hop_plain" | tr '"' "'")
            echo "{ \"ip\": \"$ip\", \"groups\": \"$groups_str\", \"hops\": $j_hops, \"last_hop\": \"$clean_last_hop\" }," >> "$TEMP_JSON_Trace"
        fi
    done
    echo "</tbody></table>" >> "$TEMP_TRACE"

    if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
        echo "</tbody></table>" >> "$TEMP_TRACE_SIMPLE"
    fi
}



process_tests() {
    [[ ! -f "$FILE_DOMAINS" ]] && { echo -e "${RED}ERRO: $FILE_DOMAINS não encontrado!${NC}"; exit 1; }
    local legend="LEGENDA: ${GREEN}.${NC}=OK ${YELLOW}!${NC}=Alert ${PURPLE}~${NC}=Div ${RED}x${NC}=Fail"
    [[ "$ENABLE_TCP_CHECK" == "true" ]] && legend+=" ${GREEN}T${NC}=TCP_OK ${RED}T${NC}=TCP_Fail"
    [[ "$ENABLE_DNSSEC_CHECK" == "true" ]] && legend+=" ${GREEN}D${NC}=SEC_OK ${RED}D${NC}=SEC_Fail ${GRAY}D${NC}=SEC_Abs"
    [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" ]] && legend+=" ${GREEN}SOA${NC}=Synced ${RED}SOA${NC}=Div"
    echo -e "$legend"
    
    # Temp files for buffering
    local TEMP_DOMAIN_BODY="logs/temp_domain_body_$$.html"
    local TEMP_GROUP_BODY="logs/temp_group_body_$$.html"
    local TEMP_DOMAIN_BODY_SIMPLE="logs/temp_domain_body_simple_$$.html"
    local TEMP_GROUP_BODY_SIMPLE="logs/temp_group_body_simple_$$.html"
    local TEMP_JSON_DOMAINS="logs/temp_domains_json_$$.json"
    
    local test_id=0
    while IFS=';' read -r domain groups test_types record_types extra_hosts || [ -n "$domain" ]; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs); groups=$(echo "$groups" | tr -d '[:space:]')
        IFS=',' read -ra group_list <<< "$groups"; IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
        
        echo -e "${CYAN}>> ${domain} ${PURPLE}[${record_types}] ${YELLOW}(${test_types})${NC}"
        
        # Reset Domain Stats
        local d_total=0; local d_ok=0; local d_warn=0; local d_fail=0; local d_div=0
        if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
            > "$TEMP_DOMAIN_BODY"
        fi
        if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
            > "$TEMP_DOMAIN_BODY_SIMPLE"
        fi

        local calc_modes=(); if [[ "$test_types" == *"both"* ]]; then calc_modes=("iterative" "recursive"); elif [[ "$test_types" == *"recursive"* ]]; then calc_modes=("recursive"); else calc_modes=("iterative"); fi
        local targets=("$domain"); for ex in "${extra_list[@]}"; do targets+=("$ex.$domain"); done

        # Init Service Table Temp File one time if not exists (checked outside to avoid truncate on every domain)
        [[ ! -f "logs/temp_svc_table_$$.html" ]] && touch "logs/temp_svc_table_$$.html"

        for grp in "${group_list[@]}"; do
            [[ -z "${DNS_GROUPS[$grp]}" ]] && continue
            ACTIVE_GROUPS[$grp]=1 # Mark group as active
            local srv_list=(${DNS_GROUPS[$grp]})
            echo -ne "   [${PURPLE}${grp}${NC}] "
            
            # Reset Group Stats
            local g_total=0; local g_ok=0; local g_warn=0; local g_fail=0; local g_div=0
            if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                > "$TEMP_GROUP_BODY"
                echo "<div class=\"table-responsive\"><table><thead><tr><th style=\"width:30%\">Target (Record)</th>" >> "$TEMP_GROUP_BODY"
            fi
            if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
                > "$TEMP_GROUP_BODY_SIMPLE"
                echo "<div class=\"table-responsive\"><table><thead><tr><th style=\"width:30%\">Target (Record)</th>" >> "$TEMP_GROUP_BODY_SIMPLE"
            fi
            for srv in "${srv_list[@]}"; do 
                [[ "$GENERATE_FULL_REPORT" == "true" ]] && echo "<th>$srv</th>" >> "$TEMP_GROUP_BODY"
                if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
                    echo "<th>$srv</th>" >> "$TEMP_GROUP_BODY_SIMPLE"
                fi
            done
            if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                echo "</tr></thead><tbody>" >> "$TEMP_GROUP_BODY"
            fi
            if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
                echo "</tr></thead><tbody>" >> "$TEMP_GROUP_BODY_SIMPLE"
            fi
            
            for mode in "${calc_modes[@]}"; do
                for target in "${targets[@]}"; do
                    
                    # --- PRE-CHECK SERVICE CAPABILITIES FOR THIS TARGET (TCP/DNSSEC) ---
                    # Cache para badges TCP/DNSSEC (Uma vez por servidor/target)
                    declare -A CACHE_TCP_BADGE
                    declare -A CACHE_SEC_BADGE
                    
                    for srv in "${srv_list[@]}"; do
                        local tcp_res="-"
                        local sec_res="-"

                        # TCP Check
                        if [[ "$ENABLE_TCP_CHECK" == "true" ]]; then
                             local clean_srv=${srv//./_}
                             local clean_tgt=${target//./_}
                             local tcp_id="tcp_${clean_srv}_${clean_tgt}"
                             
                             local opts_tcp; [[ "$mode" == "iterative" ]] && opts_tcp="$DEFAULT_DIG_OPTIONS" || opts_tcp="$RECURSIVE_DIG_OPTIONS"
                             opts_tcp+=" +tcp +time=$TIMEOUT"
                             local out_tcp=$(dig $opts_tcp @$srv $target A 2>&1)
                             log_cmd_result "TCP CHECK $srv -> $target" "dig $opts_tcp @$srv $target A" "$out_tcp" "0"
                             
                             if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                                 local safe_tcp=$(echo "$out_tcp" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                                 echo "<div id=\"${tcp_id}_content\" style=\"display:none\"><pre>$safe_tcp</pre></div>" >> "$TEMP_DETAILS"
                                 echo "<div id=\"${tcp_id}_title\" style=\"display:none\">TCP Check | $srv &rarr; $target</div>" >> "$TEMP_DETAILS"
                             fi

                             if echo "$out_tcp" | grep -q -i -E "connection timed out|communications error|no servers could be reached|failed: timed out|network is unreachable|host is unreachable|connection refused|no route to host"; then
                                 CACHE_TCP_BADGE[$srv]="<a href='#' onclick=\"showLog('${tcp_id}'); return false;\"><span class='badge-mini fail' title='TCP Failed'>T</span></a>"
                                 tcp_res="<a href='#' onclick=\"showLog('${tcp_id}'); return false;\"><span class='badge-mini fail'>FAIL</span></a>"
                                 TCP_FAIL+=1
                                 echo -ne "${RED}T${NC}"
                             else
                                 CACHE_TCP_BADGE[$srv]="<a href='#' onclick=\"showLog('${tcp_id}'); return false;\"><span class='badge-mini success' title='TCP OK'>T</span></a>"
                                 tcp_res="<a href='#' onclick=\"showLog('${tcp_id}'); return false;\"><span class='badge-mini success'>OK</span></a>"
                                 TCP_SUCCESS+=1
                                 echo -ne "${GREEN}T${NC}"
                             fi
                        fi

                        # DNSSEC Check
                        if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
                             local clean_srv=${srv//./_}
                             local clean_tgt=${target//./_}
                             local sec_id="sec_${clean_srv}_${clean_tgt}"

                             local opts_sec; [[ "$mode" == "iterative" ]] && opts_sec="$DEFAULT_DIG_OPTIONS" || opts_sec="$RECURSIVE_DIG_OPTIONS"
                             opts_sec+=" +dnssec +time=$TIMEOUT"
                             local out_sec=$(dig $opts_sec @$srv $target A 2>&1)
                             log_cmd_result "DNSSEC CHECK $srv -> $target" "dig $opts_sec @$srv $target A" "$out_sec" "0"
                             
                             if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                                 local safe_sec=$(echo "$out_sec" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                                 echo "<div id=\"${sec_id}_content\" style=\"display:none\"><pre>$safe_sec</pre></div>" >> "$TEMP_DETAILS"
                                 echo "<div id=\"${sec_id}_title\" style=\"display:none\">DNSSEC Check | $srv &rarr; $target</div>" >> "$TEMP_DETAILS"
                             fi

                             if echo "$out_sec" | grep -q -E "connection timed out|communications error|no servers could be reached"; then
                                 CACHE_SEC_BADGE[$srv]="<a href='#' onclick=\"showLog('${sec_id}'); return false;\"><span class='badge-mini fail' title='DNSSEC Error'>D</span></a>"
                                 sec_res="<a href='#' onclick=\"showLog('${sec_id}'); return false;\"><span class='badge-mini fail'>ERR</span></a>"
                                 DNSSEC_FAIL+=1
                                 echo -ne "${RED}D${NC}"
                             else
                                 if echo "$out_sec" | grep -q ";; flags:.* ad" || echo "$out_sec" | grep -q "RRSIG"; then
                                     CACHE_SEC_BADGE[$srv]="<a href='#' onclick=\"showLog('${sec_id}'); return false;\"><span class='badge-mini success' title='DNSSEC Signed/Supported'>D</span></a>"
                                     sec_res="<a href='#' onclick=\"showLog('${sec_id}'); return false;\"><span class='badge-mini success'>OK</span></a>"
                                     DNSSEC_SUCCESS+=1
                                     echo -ne "${GREEN}D${NC}"
                                 else
                                     # Unsigned zone is Neutral
                                     CACHE_SEC_BADGE[$srv]="<a href='#' onclick=\"showLog('${sec_id}'); return false;\"><span class='badge-mini neutral' title='DNSSEC Unsigned'>D</span></a>"
                                     sec_res="<a href='#' onclick=\"showLog('${sec_id}'); return false;\"><span class='badge-mini neutral'>ABS</span></a>"
                                     DNSSEC_ABSENT+=1
                                     echo -ne "${GRAY}D${NC}"
                                 fi
                             fi
                        fi
                        
                        # Write to Matrix Log
                        if [[ "$ENABLE_TCP_CHECK" == "true" || "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
                             [[ "$GENERATE_FULL_REPORT" == "true" ]] && echo "<tr><td><strong>$target</strong> ($mode)</td><td>$grp / $srv</td><td>$tcp_res</td><td>$sec_res</td></tr>" >> "logs/temp_svc_table_$$.html"
                             [[ "$GENERATE_SIMPLE_REPORT" == "true" ]] && echo "<tr><td><strong>$target</strong> ($mode)</td><td>$grp / $srv</td><td>$tcp_res</td><td>$sec_res</td></tr>" >> "logs/temp_services_simple_$$.html"
                        fi
                    done

                    for rec in "${rec_list[@]}"; do
                        [[ "$GENERATE_FULL_REPORT" == "true" ]] && echo "<tr><td><span class=\"badge badge-type\">$mode</span> <strong>$target</strong> <span style=\"color:var(--text-secondary)\">($rec)</span></td>" >> "$TEMP_GROUP_BODY"
                        if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
                            echo "<tr><td><span class=\"badge badge-type\">$mode</span> <strong>$target</strong> <span style=\"color:var(--text-secondary)\">($rec)</span></td>" >> "$TEMP_GROUP_BODY_SIMPLE"
                        fi
                        
                        # SOA Serial Collection
                        local collected_soa_serials=()
                        local collected_soa_srvs=()
                        
                        # Buffer Arrays (Associative)
                        declare -A RES_FINAL_CLASS; declare -A RES_FINAL_STATUS
                        declare -A RES_BADGE; declare -A RES_DUR
                        declare -A RES_BASE_BADGES; declare -A RES_ICON
                        declare -A RES_UNIQUE_ID; declare -A RES_LOG_CONTENT
                        declare -A RES_SOA_SERIAL

                        
                        for srv in "${srv_list[@]}"; do
                            test_id=$((test_id + 1)); TOTAL_TESTS+=1; g_total=$((g_total+1))
                            GROUP_TOTAL_TESTS[$grp]=$((GROUP_TOTAL_TESTS[$grp] + 1))
                            local unique_id="test_${test_id}"

                            # Connectivity
                            if [[ "$VALIDATE_CONNECTIVITY" == "true" ]]; then
                                if ! validate_connectivity "$srv" "${DNS_GROUP_TIMEOUT[$grp]}"; then
                                    FAILED_TESTS+=1; g_fail=$((g_fail+1)); echo -ne "${RED}x${NC}";
                                    
                                    # Store results for DOWN state instead of writing HTML immediately
                                    RES_FINAL_CLASS[$srv]="status-fail"
                                    RES_FINAL_STATUS[$srv]="DOWN"
                                    RES_ICON[$srv]="❌"
                                    RES_BADGE[$srv]=""
                                    RES_DUR[$srv]=""
                                    RES_BASE_BADGES[$srv]=""
                                    RES_SOA_SERIAL[$srv]=""
                                    
                                    local safe_log=$(echo "Server $srv is unreachable via ping." | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                                    RES_LOG_CONTENT[$srv]="$safe_log"
                                    RES_UNIQUE_ID[$srv]="$unique_id"
                                    
                                    # Skip to next server (do not run dig/check consistency)
                                    continue
                                fi
                            fi

                            # Consistency Loop
                            local attempts_log=""; local last_normalized=""
                            local is_divergent="false"; local consistent_count=0
                            local final_status="OK"; local final_dur=0; local final_class=""
                            local sum_dur_iter=0

                            for (( iter=1; iter<=CONSISTENCY_CHECKS; iter++ )); do
                                local opts_str; [[ "$mode" == "iterative" ]] && opts_str="$DEFAULT_DIG_OPTIONS" || opts_str="$RECURSIVE_DIG_OPTIONS"
                                local opts_arr; read -ra opts_arr <<< "$opts_str"
                                local cur_timeout="${DNS_GROUP_TIMEOUT[$grp]}"; [[ -z "$cur_timeout" ]] && cur_timeout=$TIMEOUT
                                opts_arr+=("+time=$cur_timeout")
                                local cmd_arr=("dig" "${opts_arr[@]}" "@$srv" "$target" "$rec")
                                
                                [[ "$VERBOSE" == "true" ]] && echo -e "\n     ${GRAY}[VERBOSE] #${iter} Running: ${cmd_arr[*]}${NC}"
                                
                                local start_ts=$(date +%s%N); local output; output=$("${cmd_arr[@]}" 2>&1); local ret=$?
                                local end_ts=$(date +%s%N); local dur=$(( (end_ts - start_ts) / 1000000 ))
                                
                                # Accumulate for local average and global stats
                                sum_dur_iter=$((sum_dur_iter + dur))
                                TOTAL_DNS_DURATION_SUM=$((TOTAL_DNS_DURATION_SUM + dur))
                                TOTAL_DNS_QUERY_COUNT=$((TOTAL_DNS_QUERY_COUNT + 1))
                                
                                log_cmd_result "QUERY #$iter $srv -> $target ($rec)" "${cmd_arr[*]}" "$output" "$dur"

                                local normalized=$(normalize_dig_output "$output")
                                if [[ $iter -gt 1 ]]; then
                                    if [[ "$normalized" != "$last_normalized" ]]; then is_divergent="true"; else consistent_count=$((consistent_count + 1)); fi
                                else last_normalized="$normalized"; consistent_count=1; fi

                                local iter_status="OK"; local answer_count=$(echo "$output" | grep -oE ", ANSWER: [0-9]+" | sed 's/[^0-9]*//g')
                                [[ -z "$answer_count" ]] && answer_count=0
                                if [[ $ret -ne 0 ]]; then iter_status="ERR:$ret"; CNT_NETWORK_ERROR+=1
                                elif echo "$output" | grep -q "status: SERVFAIL"; then iter_status="SERVFAIL"; CNT_SERVFAIL+=1
                                elif echo "$output" | grep -q "status: NXDOMAIN"; then iter_status="NXDOMAIN"; CNT_NXDOMAIN+=1
                                elif echo "$output" | grep -q "status: REFUSED"; then iter_status="REFUSED"; CNT_REFUSED+=1
                                elif echo "$output" | grep -q -i -E "connection timed out|failed: timed out|network is unreachable|host is unreachable|connection refused|no route to host"; then iter_status="TIMEOUT"; CNT_TIMEOUT+=1
                                elif echo "$output" | grep -q "status: NOERROR"; then
                                    [[ "$answer_count" -eq 0 ]] && { iter_status="NOANSWER"; CNT_NOANSWER+=1; } || { iter_status="NOERROR"; CNT_NOERROR+=1; }
                                else
                                    CNT_OTHER_ERROR+=1
                                fi

                                attempts_log="${attempts_log}"$'\n\n'"=== TENTATIVA #$iter ($iter_status) === "$'\n'"[Normalized Check: $(echo "$normalized" | tr '\n' ' ')]"$'\n'"$output"
                                final_status="$iter_status"
                                [[ "$iter_status" == "NOERROR" ]] && final_class="status-ok" || { [[ "$iter_status" == "SERVFAIL" || "$iter_status" == "NXDOMAIN" || "$iter_status" == "NOANSWER" ]] && final_class="status-warning" || final_class="status-fail"; }
                                
                                # Decision Logging
                                if [[ "$final_class" != "status-ok" || "$VERBOSE" == "true" ]]; then
                                    log_entry "DECISION: Domain=$target Server=$srv Record=$rec Iteration=$iter Result=$iter_status Class=$final_class"
                                fi

                                [[ "$SLEEP" != "0" && $iter -lt $CONSISTENCY_CHECKS ]] && { sleep "$SLEEP"; TOTAL_SLEEP_TIME=$(LC_NUMERIC=C awk "BEGIN {print $TOTAL_SLEEP_TIME + $SLEEP}"); }
                            done
                            
                            # Calculate Average Duration for this set
                            if [[ $CONSISTENCY_CHECKS -gt 0 ]]; then
                                final_dur=$((sum_dur_iter / CONSISTENCY_CHECKS))
                            fi
                            
                            # Collect SOA Serial if applicable
                            local current_serial=""
                            if [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" && "${rec,,}" == "soa" && "$final_class" == "status-ok" ]]; then
                                 # Robust Extraction Strategy
                                 # 1. Try to find SOA record in ANSWER SECTION
                                 current_serial=$(echo "$output" | awk '{for(i=1;i<=NF;i++) if($i=="SOA") print $(i+3)}' | grep -E '^[0-9]+$' | head -1)
                                 
                                 if [[ -n "$current_serial" ]]; then
                                     collected_soa_serials+=("$current_serial")
                                     collected_soa_srvs+=("$srv")
                                     [[ "$VERBOSE" == "true" ]] && echo -ne "${GRAY}[SOA:$current_serial]${NC}"
                                 fi
                            fi
                            
                            if [[ "$final_class" == "status-ok" && $final_dur -gt $LATENCY_WARNING_THRESHOLD ]]; then
                                final_class="status-warning"; final_status="SLOW"
                            fi

                            local badge=""
                            if [[ "$is_divergent" == "true" ]]; then
                                DIVERGENT_TESTS+=1; g_div=$((g_div+1))
                                final_status="DIV"; final_class="status-divergent"
                                badge="<span class=\"consistency-badge consistency-bad\">${consistent_count}/${CONSISTENCY_CHECKS}</span>"
                                echo -ne "${PURPLE}~${NC}"
                            else
                                [[ "$final_class" == "status-ok" ]] && { SUCCESS_TESTS+=1; g_ok=$((g_ok+1)); echo -ne "${GREEN}.${NC}"; }
                                [[ "$final_class" == "status-warning" ]] && { WARNING_TESTS+=1; g_warn=$((g_warn+1)); echo -ne "${YELLOW}!${NC}"; }
                                [[ "$final_class" == "status-fail" ]] && { FAILED_TESTS+=1; g_fail=$((g_fail+1)); GROUP_FAIL_TESTS[$grp]=$((GROUP_FAIL_TESTS[$grp] + 1)); echo -ne "${RED}x${NC}"; }
                                badge="<span class=\"badge consistent\">${CONSISTENCY_CHECKS}x</span>"
                            fi

                            local icon=""; [[ "$final_class" == "status-ok" ]] && icon="✅"; [[ "$final_class" == "status-warning" ]] && icon="⚠️"
                            [[ "$final_class" == "status-fail" ]] && icon="❌"; [[ "$final_class" == "status-divergent" ]] && icon="🔀"


                            
                            if [[ "$GENERATE_JSON_REPORT" == "true" ]]; then
                                local j_tcp_status="skipped"
                                if [[ "$ENABLE_TCP_CHECK" == "true" ]]; then
                                    if [[ "${CACHE_TCP_BADGE[$srv]}" == *"fail"* ]]; then j_tcp_status="FAIL"; else j_tcp_status="OK"; fi
                                fi
                                local j_sec_status="skipped"
                                if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
                                     if [[ "${CACHE_SEC_BADGE[$srv]}" == *"fail"* ]]; then j_sec_status="FAIL"
                                     elif [[ "${CACHE_SEC_BADGE[$srv]}" == *"neutral"* ]]; then j_sec_status="UNSIGNED"
                                     else j_sec_status="OK"; fi
                                fi
                                # Add serial to JSON
                                local j_serial="null"; [[ -n "$current_serial" ]] && j_serial="\"$current_serial\""

                                echo "{ \"domain\": \"$domain\", \"group\": \"$grp\", \"server\": \"$srv\", \"record\": \"$rec\", \"mode\": \"$mode\", \"status\": \"$final_status\", \"latency_ms\": $final_dur, \"consistent\": \"$consistent_count/$CONSISTENCY_CHECKS\", \"divergent\": $is_divergent, \"tcp_check\": \"$j_tcp_status\", \"dnssec_check\": \"$j_sec_status\", \"soa_serial\": $j_serial }," >> "$TEMP_JSON_DNS"
                            fi

                            # Capture current serial for this server
                            RES_SOA_SERIAL[$srv]=""
                            [[ -n "$current_serial" ]] && RES_SOA_SERIAL[$srv]="$current_serial"

                            # Store individual results for post-processing buffer
                            RES_FINAL_CLASS[$srv]="$final_class"
                            RES_FINAL_STATUS[$srv]="$final_status"
                            RES_BADGE[$srv]="$badge"
                            RES_DUR[$srv]="$final_dur"
                            
                            # Base Badges (TCP/SEC) - exclude SOA for now
                            local base_svc_badges=""
                            [[ -n "${CACHE_TCP_BADGE[$srv]}" ]] && base_svc_badges+=" ${CACHE_TCP_BADGE[$srv]}"
                            [[ -n "${CACHE_SEC_BADGE[$srv]}" ]] && base_svc_badges+=" ${CACHE_SEC_BADGE[$srv]}"
                            RES_BASE_BADGES[$srv]="$base_svc_badges"
                            
                            RES_ICON[$srv]="$icon"
                            RES_UNIQUE_ID[$srv]="$unique_id"
                            RES_LOG_CONTENT[$srv]="$attempts_log"
                            
                            # Clean up old log logic (moved to post-loop)
                            
                        done # End Server Loop
                        
                        # --- POST-LOOP ANALYSIS: SOA DIVERGENCE & HTML GENERATION ---
                        local soa_divergence_detected="false"
                        local unique_serials=()
                        
                        if [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" && "${rec,,}" == "soa" && ${#collected_soa_serials[@]} -ge 1 ]]; then
                             unique_serials=($(echo "${collected_soa_serials[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
                             if [[ ${#unique_serials[@]} -gt 1 ]]; then
                                  soa_divergence_detected="true"
                                  SOA_SYNC_FAIL+=1
                                  local warning_msg="SOA DIV: ${unique_serials[*]}"
                                  echo -ne " ${RED}SOA${NC}"
                                  log_entry "SOA SERIAL DIVERGENCE: Domain=$target Group=$grp Serials=${unique_serials[*]}"
                             else
                                  SOA_SYNC_OK+=1
                                  echo -ne " ${GREEN}SOA${NC}"
                             fi
                        fi
                        
                        # Apply Colors and Write HTML
                        for srv in "${srv_list[@]}"; do
                             local s_badges="${RES_BASE_BADGES[$srv]}"
                             local myserial="${RES_SOA_SERIAL[$srv]}"
                             
                             # Handle SOA Badge Coloring
                             if [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" && "${rec,,}" == "soa" ]]; then
                                  if [[ -n "$myserial" ]]; then
                                      local badge_color="neutral" # Default (Sync OK or Single)
                                      if [[ "$soa_divergence_detected" == "true" ]]; then
                                           badge_color="fail" # Red if divergent
                                      else
                                           badge_color="success" # Green if consistent
                                      fi
                                      
                                      # Make Clickable
                                      local click_handler="onclick=\"showLog('${RES_UNIQUE_ID[$srv]}'); return false;\""
                                      s_badges+=" <a href='#' $click_handler><span class='badge-mini $badge_color' title='SOA Serial: $myserial' style='width:auto; padding:0 4px; font-family:monospace;'>#${myserial: -4}</span></a>"
                                  else
                                      # No Serial Found?
                                      # If status is NOERROR/OK but no serial, show "NO DATA"?
                                      # If status is already fail (e.g. REFUSED), standard status cell handles it.
                                      # But user requested: "caso não tenha o registro soa, informe com o texto o retorno do status do dig"
                                      # The standard status cell ALREADY shows "REFUSED", "SERVFAIL", etc.
                                      # If it is NOERROR but no serial, we might want to highlight "EMPTY".
                                      if [[ "${RES_FINAL_STATUS[$srv]}" == "NOERROR" || "${RES_FINAL_STATUS[$srv]}" == "OK" ]]; then
                                           # It was successful but extraction failed (maybe empty answer)
                                           # Modify final status display for clarity?
                                           # Check if answer count was 0
                                           # Actually, standard logic sets iter_status=NOANSWER if answer=0.
                                           # So if Status is OK/NOERROR, we probably should have a serial.
                                           :
                                      fi
                                  fi
                             fi

                             if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                                # Make Latency Clickable (Conditional "ms")
                                local lat_display=""
                                if [[ -n "${RES_DUR[$srv]}" ]]; then
                                     lat_display="<a href='#' onclick=\"showLog('${RES_UNIQUE_ID[$srv]}'); return false;\" style='color:inherit; text-decoration:none; border-bottom:1px dotted #ccc; cursor:pointer;'>${RES_DUR[$srv]}ms</a>"
                                fi
                                
                                # Status Icon & Text Link
                                local status_display="<a href='#' onclick=\"showLog('${RES_UNIQUE_ID[$srv]}'); return false;\" style='text-decoration:none; color:inherit;'>${RES_ICON[$srv]} ${RES_FINAL_STATUS[$srv]}</a>"
                                
                                echo "<td><div class=\"status-cell ${RES_FINAL_CLASS[$srv]}\">$status_display ${RES_BADGE[$srv]} <div style='margin-top:2px;'>$s_badges <span class=\"time-val\" style='margin-left:4px'>$lat_display</span></div></div></td>" >> "$TEMP_GROUP_BODY"
                                local safe_log=$(echo "${RES_LOG_CONTENT[$srv]}" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                                echo "<div id=\"${RES_UNIQUE_ID[$srv]}_content\" style=\"display:none\"><pre>$safe_log</pre></div>" >> "$TEMP_DETAILS"
                                echo "<div id=\"${RES_UNIQUE_ID[$srv]}_title\" style=\"display:none\">#$test_id ${RES_FINAL_STATUS[$srv]} | $srv &rarr; $target ($rec)</div>" >> "$TEMP_DETAILS"
                             fi
                             
                             if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
                                local simple_lat=""
                                [[ -n "${RES_DUR[$srv]}" ]] && simple_lat="<span class=\"time-val\" style='margin-left:4px'>${RES_DUR[$srv]}ms</span>"
                                echo "<td><div class=\"status-cell ${RES_FINAL_CLASS[$srv]}\">${RES_ICON[$srv]} ${RES_FINAL_STATUS[$srv]} ${RES_BADGE[$srv]} <div style='margin-top:2px;'>$s_badges $simple_lat</div></div></td>" >> "$TEMP_GROUP_BODY_SIMPLE"
                             fi
                        done
                        
                        if [[ "$soa_divergence_detected" == "true" ]]; then
                                  [[ "$GENERATE_FULL_REPORT" == "true" ]] && echo "<tr><td colspan='$(( ${#srv_list[@]} + 1 ))' style='background:rgba(239, 68, 68, 0.1); color:var(--accent-warning); font-weight:bold; text-align:center;'>⚠️ SOA Serial Divergence Detected: ${unique_serials[@]}</td></tr>" >> "$TEMP_GROUP_BODY"
                                  if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
                                      echo "<tr><td colspan='$(( ${#srv_list[@]} + 1 ))' style='background:rgba(239, 68, 68, 0.1); color:var(--accent-warning); font-weight:bold; text-align:center;'>⚠️ SOA Serial Divergence Detected: ${unique_serials[@]}</td></tr>" >> "$TEMP_GROUP_BODY_SIMPLE"
                                  fi
                        fi

                        

                        if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                            echo "</tr>" >> "$TEMP_GROUP_BODY"
                        fi
                        if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
                            echo "</tr>" >> "$TEMP_GROUP_BODY_SIMPLE"
                        fi
                    done
                done
            done
            # Close table AFTER all modes and targets are done
            if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                echo "</tbody></table></div>" >> "$TEMP_GROUP_BODY"
            fi
            if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
                echo "</tbody></table></div>" >> "$TEMP_GROUP_BODY_SIMPLE"
            fi

            d_total=$((d_total + g_total)); d_ok=$((d_ok + g_ok)); d_warn=$((d_warn + g_warn))
            d_fail=$((d_fail + g_fail)); d_div=$((d_div + g_div))

            local g_stats_html="<span style=\"font-size:0.85em; margin-left:10px; font-weight:normal; opacity:0.9;\">"
            g_stats_html+="Total: <strong>$g_total</strong> | "
            [[ $g_ok -gt 0 ]] && g_stats_html+="<span class=\"st-ok\">✅ $g_ok</span> "
            [[ $g_warn -gt 0 ]] && g_stats_html+="<span class=\"st-warn\">⚠️ $g_warn</span> "
            [[ $g_fail -gt 0 ]] && g_stats_html+="<span class=\"st-fail\">❌ $g_fail</span> "
            [[ $g_div -gt 0 ]] && g_stats_html+="<span class=\"st-div\">🔀 $g_div</span>"
            g_stats_html+="</span>"

            if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                echo "<details class=\"group-level\"><summary>📂 Grupo: $grp $g_stats_html</summary>" >> "$TEMP_DOMAIN_BODY"
                cat "$TEMP_GROUP_BODY" >> "$TEMP_DOMAIN_BODY"
                echo "</details>" >> "$TEMP_DOMAIN_BODY"
            fi

            if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
                echo "<details class=\"group-level\"><summary>📂 Grupo: $grp $g_stats_html</summary>" >> "$TEMP_DOMAIN_BODY_SIMPLE"
                cat "$TEMP_GROUP_BODY_SIMPLE" >> "$TEMP_DOMAIN_BODY_SIMPLE"
                echo "</details>" >> "$TEMP_DOMAIN_BODY_SIMPLE"
            fi
            
            echo "" 
        done
        
        local d_stats_html="<span style=\"font-size:0.85em; margin-left:15px; font-weight:normal; opacity:0.9;\">"
        d_stats_html+="Tests: <strong>$d_total</strong> | "
        [[ $d_ok -gt 0 ]] && d_stats_html+="<span class=\"st-ok\">✅ $d_ok</span> "
        [[ $d_warn -gt 0 ]] && d_stats_html+="<span class=\"st-warn\">⚠️ $d_warn</span> "
        [[ $d_fail -gt 0 ]] && d_stats_html+="<span class=\"st-fail\">❌ $d_fail</span> "
        [[ $d_div -gt 0 ]] && d_stats_html+="<span class=\"st-div\">🔀 $d_div</span>"
        d_stats_html+="</span>"

        if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
            echo "<details class=\"domain-level\"><summary>🌐 $domain $d_stats_html <span style=\"font-size:0.8em; color:var(--text-secondary); margin-left:10px;\">[Recs: $record_types]</span> <span class=\"badge\" style=\"margin-left:auto\">$test_types</span></summary>" >> "$TEMP_MATRIX"
            cat "$TEMP_DOMAIN_BODY" >> "$TEMP_MATRIX"
            echo "</details>" >> "$TEMP_MATRIX"
        fi

        if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
            echo "<details class=\"domain-level\"><summary>🌐 $domain $d_stats_html <span style=\"font-size:0.8em; color:var(--text-secondary); margin-left:10px;\">[Recs: $record_types]</span> <span class=\"badge\" style=\"margin-left:auto\">$test_types</span></summary>" >> "$TEMP_MATRIX_SIMPLE"
            cat "$TEMP_DOMAIN_BODY_SIMPLE" >> "$TEMP_MATRIX_SIMPLE"
            echo "</details>" >> "$TEMP_MATRIX_SIMPLE"
        fi
        
        # JSON Domain Summary
        if [[ "$GENERATE_JSON_REPORT" == "true" ]]; then
             echo "{ \"domain\": \"$domain\", \"tests_total\": $d_total, \"tests_ok\": $d_ok, \"tests_warn\": $d_warn, \"tests_fail\": $d_fail, \"tests_div\": $d_div, \"final_state\": \"$( [[ $d_fail -gt 0 ]] && echo 'FAIL' || { [[ $d_warn -gt 0 || $d_div -gt 0 ]] && echo 'WARN' || echo 'OK'; } )\" }," >> "$TEMP_JSON_DOMAINS"
        fi
        
        echo ""
    done < "$FILE_DOMAINS"
    
    rm -f "$TEMP_DOMAIN_BODY" "$TEMP_GROUP_BODY"
    if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
        rm -f "$TEMP_DOMAIN_BODY_SIMPLE" "$TEMP_GROUP_BODY_SIMPLE"
    fi
    
    rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_LOG_MODALS" "$TEMP_CHART_JS"
    rm -f "logs/temp_obj_summary_"*
    
    # Remove empty logic files if they exist
    [[ ! -s "$TEMP_LOG_MODALS" ]] && rm -f "$TEMP_LOG_MODALS"
}

assemble_json() {
    [[ "$GENERATE_JSON_REPORT" != "true" ]] && return
    
    local JSON_FILE="${HTML_FILE%.html}.json"
    
    # Helper to clean trailing comma from file content for valid JSON array
    # If file is empty, this results in empty string, which is fine for empty array
    local dns_data=""; [[ -f "$TEMP_JSON_DNS" ]] && dns_data=$(sed '$ s/,$//' "$TEMP_JSON_DNS")
    local domain_data=""; [[ -f "$TEMP_JSON_DOMAINS" ]] && domain_data=$(sed '$ s/,$//' "$TEMP_JSON_DOMAINS")
    local ping_data=""; [[ -f "$TEMP_JSON_Ping" ]] && ping_data=$(sed '$ s/,$//' "$TEMP_JSON_Ping")
    local sec_data=""; [[ -f "$TEMP_JSON_Sec" ]] && sec_data=$(sed '$ s/,$//' "$TEMP_JSON_Sec")
    local trace_data=""; [[ -f "$TEMP_JSON_Trace" ]] && trace_data=$(sed '$ s/,$//' "$TEMP_JSON_Trace")
    
    # Build complete JSON
    cat > "$JSON_FILE" << EOF
{
  "meta": {
    "script_version": "$SCRIPT_VERSION",
    "timestamp_start": "$START_TIME_HUMAN",
    "timestamp_end": "$END_TIME_HUMAN",
    "duration_seconds": $TOTAL_DURATION,
    "user": "$USER",
    "hostname": "$HOSTNAME"
  },
  "config": {
    "domains_file": "$FILE_DOMAINS",
    "groups_file": "$FILE_GROUPS",
    "timeout": $TIMEOUT,
    "consistency_checks": $CONSISTENCY_CHECKS,
    "strict_mode": {
      "ip": $STRICT_IP_CHECK,
      "order": $STRICT_ORDER_CHECK,
      "ttl": $STRICT_TTL_CHECK
    }
  },
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "success": $SUCCESS_TESTS,
    "warnings": $WARNING_TESTS,
    "failures": $FAILED_TESTS,
    "divergences": $DIVERGENT_TESTS,
    "tcp_checks": { "ok": $TCP_SUCCESS, "fail": $TCP_FAIL },
    "dnssec_checks": { "ok": $DNSSEC_SUCCESS, "fail": $DNSSEC_FAIL },
    "total_sleep_seconds": $TOTAL_SLEEP_TIME,
    "total_pings_sent": $TOTAL_PING_SENT,
    "counters": {
      "noerror": $CNT_NOERROR,
      "nxdomain": $CNT_NXDOMAIN,
      "servfail": $CNT_SERVFAIL,
      "refused": $CNT_REFUSED,
      "timeout": $CNT_TIMEOUT,
      "noanswer": $CNT_NOANSWER,
      "network_error": $CNT_NETWORK_ERROR
    }
  },
  "domain_status": [
    $domain_data
  ],
  "results": [
    $dns_data
  ],
  "ping_results": [
    $ping_data
  ],
  "traceroute_results": [
    $trace_data
  ],
  "security_scan": {
    "summary": {
       "privacy_hidden": $SEC_HIDDEN, "privacy_revealed": $SEC_REVEALED,
       "axfr_denied": $SEC_AXFR_OK, "axfr_allowed": $SEC_AXFR_RISK,
       "recursion_closed": $SEC_REC_OK, "recursion_open": $SEC_REC_RISK
    },
    "details": [
      $sec_data
    ]
  }
}
EOF
    echo -e "  📄 Relatório JSON    : ${GREEN}$JSON_FILE${NC}"
}

print_final_terminal_summary() {
    # Calculate General Stats
    local domain_count=0
    [[ -f "$FILE_DOMAINS" ]] && domain_count=$(grep -vE '^\s*#|^\s*$' "$FILE_DOMAINS" | wc -l)
    
    local group_count=${#ACTIVE_GROUPS[@]}
    
    # Calculate Unique Servers Involved
    declare -A _uniq_srv
    for g in "${!ACTIVE_GROUPS[@]}"; do
        for ip in ${DNS_GROUPS[$g]}; do _uniq_srv[$ip]=1; done
    done
    local server_count=${#_uniq_srv[@]}

    # Calculate Avg Latency
    local avg_lat="N/A"
    local lat_suffix=""
    if [[ $TOTAL_LATENCY_COUNT -gt 0 ]]; then
        local calc_val
        calc_val=$(awk "BEGIN {printf \"%.0f\", $TOTAL_LATENCY_SUM / $TOTAL_LATENCY_COUNT}")
        if [[ "$calc_val" =~ ^[0-9]+$ ]]; then
            avg_lat="$calc_val"
            lat_suffix="ms"
        fi
    fi

    # Print direct to terminal with colors
    echo -e "\n${BLUE}======================================================${NC}"
    echo -e "${BLUE}       ESTATÍSTICAS GERAIS${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "  📂 Domínios      : ${domain_count}"
    echo -e "  👥 Grupos DNS    : ${group_count}"
    echo -e "  🖥️ Servidores    : ${server_count} (Únicos)"
    echo -e "  📡 Total Queries : ${TOTAL_TESTS} (DNS)"
    echo -e "  ⏱️ Latência Média: ${avg_lat}${lat_suffix}"
    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e "  ✅ Sucesso         : ${GREEN}${SUCCESS_TESTS}${NC}"
    echo -e "  ⚠️ Alertas         : ${YELLOW}${WARNING_TESTS}${NC}"
    echo -e "  ❌ Falhas Críticas : ${RED}${FAILED_TESTS}${NC}"
    echo -e "  🔀 Divergências    : ${PURPLE}${DIVERGENT_TESTS}${NC}"
    
    if [[ "$ENABLE_TCP_CHECK" == "true" ]]; then
        echo -e "  🔌 TCP Checks      : ${GREEN}${TCP_SUCCESS}${NC} OK / ${RED}${TCP_FAIL}${NC} Fail"
    fi
    if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
        echo -e "  🔐 DNSSEC Checks   : ${GREEN}${DNSSEC_SUCCESS}${NC} OK / ${GRAY}${DNSSEC_ABSENT}${NC} Absent / ${RED}${DNSSEC_FAIL}${NC} Fail"
    fi
    
    local p_succ=0
    [[ $TOTAL_TESTS -gt 0 ]] && p_succ=$(( (SUCCESS_TESTS * 100) / TOTAL_TESTS ))
    echo -e "  📊 Taxa de Sucesso : ${p_succ}%"
    
    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e "${BLUE}       PERFORMANCE & DETALHES    ${NC}"
    echo -e "  📡 Latência Rede   : ${avg_lat}${lat_suffix} (ICMP Ping)"
    echo -e "  🐢 Resolução DNS   : ${avg_dns} (Dig Total)"
    echo -e "  -------------------------------------"
    echo -e "  ✅ NOERROR         : ${CNT_NOERROR}"
    echo -e "  ⚠️ NXDOMAIN        : ${CNT_NXDOMAIN}"
    echo -e "  ❌ SERVFAIL        : ${CNT_SERVFAIL}"
    echo -e "  ❌ REFUSED         : ${CNT_REFUSED}"
    echo -e "  ❌ TIMEOUT         : ${CNT_TIMEOUT}"
    [[ $CNT_NETWORK_ERROR -gt 0 ]] && echo -e "  ❌ NETWORK ERR     : ${CNT_NETWORK_ERROR}"
    echo -e "${BLUE}------------------------------------------------------${NC}"

    echo -e "${BLUE}       ESTATÍSTICAS POR GRUPO    ${NC}"
    printf "  %-15s | %-13s | %-12s\n" "GRUPO" "LATÊNCIA(AVG)" "FALHAS(DNS)"
    echo -e "  --------------------------------------------"
    for grp in "${!ACTIVE_GROUPS[@]}"; do
        local g_rtt_sum=0
        local g_rtt_cnt=0
        for ip in ${DNS_GROUPS[$grp]}; do
            if [[ -n "${IP_RTT_RAW[$ip]}" ]]; then
                # IP_RTT_RAW can be float "45.2". awk handles it.
                g_rtt_sum=$(LC_NUMERIC=C awk "BEGIN {print $g_rtt_sum + ${IP_RTT_RAW[$ip]}}")
                g_rtt_cnt=$((g_rtt_cnt + 1))
            fi
        done
        local g_avg="N/A"
        [[ $g_rtt_cnt -gt 0 ]] && g_avg=$(LC_NUMERIC=C awk "BEGIN {printf \"%.1fms\", $g_rtt_sum / $g_rtt_cnt}")
        
        local g_fail_cnt=${GROUP_FAIL_TESTS[$grp]}
        [[ -z "$g_fail_cnt" ]] && g_fail_cnt=0
        local g_total_cnt=${GROUP_TOTAL_TESTS[$grp]}
        [[ -z "$g_total_cnt" ]] && g_total_cnt=0
        
        local fail_rate="0%"
        [[ $g_total_cnt -gt 0 ]] && fail_rate="$(( (g_fail_cnt * 100) / g_total_cnt ))%"
        
        local fail_color="${GREEN}"
        [[ $g_fail_cnt -gt 0 ]] && fail_color="${RED}"
        
        printf "  %-15s | %-13s | ${fail_color}%-12s${NC}\n" "$grp" "$g_avg" "${g_fail_cnt} ($fail_rate)"
    done
    echo -e "${BLUE}------------------------------------------------------${NC}"

    echo -e "  🕒 Início          : ${START_TIME_HUMAN}"
    echo -e "  🕒 Final           : ${END_TIME_HUMAN}"
    echo -e "  🔄 Tentativas      : ${CONSISTENCY_CHECKS}x (Por check)"
    echo -e "  📡 Pings Enviados  : ${TOTAL_PING_SENT}"
    echo -e "  💤 Sleep Total     : ${TOTAL_SLEEP_TIME}s"
    echo -e "  ⏳ Duração Total   : ${TOTAL_DURATION}s"

    echo -e "\n${BLUE}--- SECURITY SCAN ---${NC}"
    echo -e "  PRIVACY   : ${GREEN}${SEC_HIDDEN}${NC} Hidden / ${RED}${SEC_REVEALED}${NC} Revealed / ${GRAY}${SEC_VER_TIMEOUT}${NC} Timeout"
    echo -e "  AXFR      : ${GREEN}${SEC_AXFR_OK}${NC} Denied / ${RED}${SEC_AXFR_RISK}${NC} Allowed  / ${GRAY}${SEC_AXFR_TIMEOUT}${NC} Timeout"
    echo -e "  RECURSION : ${GREEN}${SEC_REC_OK}${NC} Closed / ${RED}${SEC_REC_RISK}${NC} Open    / ${GRAY}${SEC_REC_TIMEOUT}${NC} Timeout"
    echo -e "  SOA SYNC  : ${GREEN}${SOA_SYNC_OK}${NC} Synced / ${RED}${SOA_SYNC_FAIL}${NC} Divergent"
    
    echo -e "${BLUE}======================================================${NC}"

    # Log to File (Strip ANSI codes)
    if [[ "$GENERATE_LOG_TEXT" == "true" ]]; then
         {
             echo ""
             echo "======================================================"
             echo "       ESTATÍSTICAS GERAIS"
             echo "======================================================"
             echo "  Domínios      : ${domain_count}"
             echo "  Grupos DNS    : ${group_count}"
             echo "  Servidores    : ${server_count} (Únicos)"
             echo "  Total Queries : ${TOTAL_TESTS} (DNS)"
             echo "  Latência Média: ${avg_lat}${lat_suffix}"
             echo "------------------------------------------------------"
             echo "  Sucesso         : ${SUCCESS_TESTS}"
             echo "  Alertas         : ${WARNING_TESTS}"
             echo "  Falhas Críticas : ${FAILED_TESTS}"
             echo "  Divergências    : ${DIVERGENT_TESTS}"
             [[ "$ENABLE_TCP_CHECK" == "true" ]] && echo "  TCP Checks      : ${TCP_SUCCESS} OK / ${TCP_FAIL} Fail"
             [[ "$ENABLE_DNSSEC_CHECK" == "true" ]] && echo "  DNSSEC Checks   : ${DNSSEC_SUCCESS} OK / ${DNSSEC_ABSENT} Absent / ${DNSSEC_FAIL} Fail"
             echo "  Taxa de Sucesso : ${p_succ}%"
             echo "  Início          : ${START_TIME_HUMAN}"
             echo "  Final           : ${END_TIME_HUMAN}"
             echo "  Tentativas      : ${CONSISTENCY_CHECKS}x (Por check)"
             echo "  Pings Enviados  : ${TOTAL_PING_SENT}"
             echo "  Sleep Total     : ${TOTAL_SLEEP_TIME}s"
             echo "  Duração Total   : ${TOTAL_DURATION}s"
             echo ""
             echo "--- SECURITY SCAN ---"
             echo "  PRIVACY   : ${SEC_HIDDEN} Hidden / ${SEC_REVEALED} Revealed / ${SEC_VER_TIMEOUT} Timeout"
             echo "  AXFR      : ${SEC_AXFR_OK} Denied / ${SEC_AXFR_RISK} Allowed  / ${SEC_AXFR_TIMEOUT} Timeout"
             echo "  RECURSION : ${SEC_REC_OK} Closed / ${SEC_REC_RISK} Open    / ${SEC_REC_TIMEOUT} Timeout"
             echo "  SOA SYNC  : ${SOA_SYNC_OK} Synced / ${SOA_SYNC_FAIL} Divergent"
             echo "======================================================"
         } >> "$LOG_FILE_TEXT"
    fi
    
    # Warning if Charts were disabled due to offline
    if [[ "$INITIAL_ENABLE_CHARTS" == "true" && "$ENABLE_CHARTS" == "false" ]]; then
        echo -e "\n${YELLOW}⚠️  AVISO:${NC} A geração de gráficos foi desabilitada pois não foi possível baixar a biblioteca necessária (Sem Internet)."
    fi
}

main() {
    START_TIME_EPOCH=$(date +%s); START_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S")

    # Define cleanup trap
    trap 'rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS" "$TEMP_PING" "$TEMP_TRACE" "$TEMP_CONFIG" "$TEMP_TIMING" "$TEMP_MODAL" "$TEMP_DISCLAIMER" "$TEMP_SERVICES" "logs/temp_help_$$.html" "logs/temp_obj_summary_$$.html" "logs/temp_svc_table_$$.html" "$TEMP_TRACE_SIMPLE" "$TEMP_PING_SIMPLE" "$TEMP_MATRIX_SIMPLE" "$TEMP_SERVICES_SIMPLE" "logs/temp_domain_body_simple_$$.html" "logs/temp_group_body_simple_$$.html" "logs/temp_security_$$.html" "logs/temp_security_simple_$$.html" "logs/temp_sec_rows_$$.html" "$TEMP_JSON_Ping" "$TEMP_JSON_DNS" "$TEMP_JSON_Sec" "$TEMP_JSON_Trace" "logs/temp_chart_$$.js" 2>/dev/null' EXIT

    # Initialize Flags based on Config
    GENERATE_FULL_REPORT="${ENABLE_FULL_REPORT:-true}"
    GENERATE_SIMPLE_REPORT="${ENABLE_SIMPLE_REPORT:-false}"
    # JSON Default comes from config file now (GENERATE_JSON_REPORT)

    while getopts ":n:g:lhyjstdxrTVZ" opt; do case ${opt} in 
        n) FILE_DOMAINS=$OPTARG ;; 
        g) FILE_GROUPS=$OPTARG ;; 
        l) GENERATE_LOG_TEXT="true" ;; 
        y) INTERACTIVE_MODE="false" ;; 
        s) 
            GENERATE_SIMPLE_REPORT="true" 
            # Per user request: If -s is chosen, disable default full report
            GENERATE_FULL_REPORT="false"
            ;; 
        j) 
            GENERATE_JSON_REPORT="true" 
            # Per user request: If -j is chosen, disable default full report
            GENERATE_FULL_REPORT="false"
            ;;
        t) ENABLE_TCP_CHECK="true" ;;
        d) ENABLE_DNSSEC_CHECK="true" ;;
        x) ENABLE_AXFR_CHECK="true" ;;
        r) ENABLE_RECURSION_CHECK="true" ;;
        T) ENABLE_TRACE_CHECK="true" ;;
        V) CHECK_BIND_VERSION="true" ;;
        Z) ENABLE_SOA_SERIAL_CHECK="true" ;;
        h) show_help; exit 0 ;; 
        *) echo "Opção inválida"; exit 1 ;; 
    esac; done

    # Fallback Logic: If everything is False, Default to Full
    if [[ "$GENERATE_FULL_REPORT" == "false" && "$GENERATE_SIMPLE_REPORT" == "false" && "$GENERATE_JSON_REPORT" == "false" ]]; then
        # Check if it was because of user CLI or Config?
        # User requirement: "caso o usuário deixe as três opções [...] como false ... gera o html detalhado"
        # This covers that.
        [[ "$INTERACTIVE_MODE" == "false" ]] && echo "Info: Nenhum formato selecionado. Gerando HTML Detalhado (Padrão)."
        GENERATE_FULL_REPORT="true"
    fi

    if ! command -v dig &> /dev/null; then echo "Erro: 'dig' nao encontrado."; exit 1; fi
    if ! command -v timeout &> /dev/null; then echo "Erro: 'timeout' nao encontrado (necessario para checks)."; exit 1; fi
    if [[ "$ENABLE_PING" == "true" ]] && ! command -v ping &> /dev/null; then echo "Erro: 'ping' nao encontrado (necessario para -t/Ping)."; exit 1; fi
    if [[ "$ENABLE_TRACE_CHECK" == "true" ]] && ! command -v traceroute &> /dev/null; then echo "Erro: 'traceroute' nao encontrado (necessario para -T)."; exit 1; fi
    init_log_file
    validate_csv_files
    interactive_configuration
    
    # Capture initial preference for charts logic
    INITIAL_ENABLE_CHARTS="$ENABLE_CHARTS"
    
    [[ "$INTERACTIVE_MODE" == "false" ]] && print_execution_summary
    init_html_parts; write_html_header; load_dns_groups; process_tests; run_ping_diagnostics; run_trace_diagnostics; run_security_diagnostics

    END_TIME_EPOCH=$(date +%s); END_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S"); TOTAL_DURATION=$((END_TIME_EPOCH - START_TIME_EPOCH))
    
    # Format Sleep Time (2 decimals, ensure dot)
    if [[ -z "$TOTAL_SLEEP_TIME" ]]; then TOTAL_SLEEP_TIME=0; fi
    TOTAL_SLEEP_TIME=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", $TOTAL_SLEEP_TIME}")

    if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
        assemble_html "full"
    fi
    
    if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
        assemble_html "simple"
    fi
    
    if [[ "$GENERATE_JSON_REPORT" == "true" ]]; then
        assemble_json
    fi

    [[ "$GENERATE_LOG_TEXT" == "true" ]] && echo "Execution finished" >> "$LOG_FILE_TEXT"
    print_final_terminal_summary
    echo -e "\n${GREEN}=== CONCLUÍDO ===${NC}"
    [[ "$GENERATE_FULL_REPORT" == "true" ]] && echo "Relatório Completo: $HTML_FILE"
    [[ "$GENERATE_SIMPLE_REPORT" == "true" ]] && echo "Relatório Simplificado: ${HTML_FILE%.html}_simple.html"
}

main "$@"
