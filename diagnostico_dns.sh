#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS - COMPLETE DASHBOARD
# Versão: 9.26
# "Enhancements and Fixes"
# ==============================================

# --- CONFIGURAÇÕES GERAIS ---
SCRIPT_VERSION="9.26"


# Carrega configurações externas
CONFIG_FILE="diagnostico.conf"
SCRIPT_DIR="$(dirname "$0")"

# Tenta carregar do diretório atual ou do diretório do script
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
elif [[ -f "$SCRIPT_DIR/$CONFIG_FILE" ]]; then
    source "$SCRIPT_DIR/$CONFIG_FILE"
else
    echo "ERRO CRÍTICO: Arquivo de configuração '$CONFIG_FILE' não encontrado!"
    echo "Por favor, certifique-se de que o arquivo 'diagnostico.conf' esteja no mesmo diretório."
    exit 1
fi


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

# Setup Arquivos
mkdir -p logs
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HTML_FILE="logs/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}.html"
LOG_FILE_TEXT="logs/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}.log"

init_html_parts() {
    TEMP_HEADER="logs/temp_header_$$.html"
    TEMP_STATS="logs/temp_stats_$$.html"
    TEMP_MATRIX="logs/temp_matrix_$$.html"
    TEMP_DETAILS="logs/temp_details_$$.html"
    TEMP_PING="logs/temp_ping_$$.html"
    TEMP_TRACE="logs/temp_trace_$$.html"
    TEMP_CONFIG="logs/temp_config_$$.html"
    TEMP_TIMING="logs/temp_timing_$$.html"
    TEMP_MODAL="logs/temp_modal_$$.html"
    TEMP_DISCLAIMER="logs/temp_disclaimer_$$.html"
    TEMP_SERVICES="logs/temp_services_$$.html"

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
    echo -e "  ${GREEN}-y${NC}            Bypassa o menu interativo (Non-interactive/Batch execution)."
    echo -e ""
    echo -e "  ${GREEN}-s${NC}            Modo Simplificado (Gera HTML sem logs técnicos para redução de tamanho)."
    echo -e "  ${GREEN}-j${NC}            Gera saída em JSON estruturado (.json)."
    echo -e "  ${GRAY}Nota: O uso de -s ou -j desabilita o Relatório Completo padrão, a menos que configurado o contrário.${NC}"
    echo -e ""
    echo -e "  ${GREEN}-t${NC}            Habilita testes de conectividade TCP."
    echo -e "  ${GREEN}-d${NC}            Habilita validação DNSSEC."
    echo -e "  ${GREEN}-x${NC}            Habilita teste de transferência de zona (AXFR)."
    echo -e "  ${GREEN}-r${NC}            Habilita teste de recursão aberta."
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
    echo -e "  ${CYAN}CONSISTENCY_CHECKS${NC} (Padrão: 10)"
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
    echo -e "  ${GREEN}HIDDEN/DENIED/CLOSED${NC} = Seguro (OK)"
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
            <div class="modal-body" style="background: #1e293b; color: #cbd5e1; padding: 20px; font-family: 'Fira Code', monospace; font-size: 0.85rem; overflow-x: auto;">
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
    echo -e "  🎨 Color Output   : ${CYAN}${COLOR_OUTPUT}${NC}"
    echo ""
    echo -e "${PURPLE}[SAÍDA]${NC}"
    [[ "$GENERATE_FULL_REPORT" == "true" ]] && echo -e "  📄 Relatório Completo: ${GREEN}$HTML_FILE${NC}"
    [[ "$GENERATE_SIMPLE_REPORT" == "true" ]] && echo -e "  📄 Relatório Simplificado: ${GREEN}${HTML_FILE%.html}_simple.html${NC}"
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
        ask_variable "Tentativas por Teste (Consistência)" "CONSISTENCY_CHECKS"
        ask_variable "Timeout Global (segundos)" "TIMEOUT"
        ask_variable "Sleep entre queries (segundos)" "SLEEP"
        ask_boolean "Validar conectividade porta 53?" "VALIDATE_CONNECTIVITY"
        ask_boolean "Checar versão BIND (chaos)?" "CHECK_BIND_VERSION"
        ask_boolean "Verbose Debug?" "VERBOSE"
        ask_boolean "Gerar log texto?" "GENERATE_LOG_TEXT"
        ask_boolean "Gerar relatório HTML Detalhado?" "ENABLE_FULL_REPORT"
        ask_boolean "Gerar relatório HTML Simplificado?" "ENABLE_SIMPLE_REPORT"
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
        # JSON is already direct
        
        # Fallback Logic (Prevent user from disabling everything without realizing)
        if [[ "$GENERATE_FULL_REPORT" == "false" && "$GENERATE_SIMPLE_REPORT" == "false" && "$GENERATE_JSON_REPORT" == "false" ]]; then
             echo -e "\n${YELLOW}⚠️  Aviso: Nenhum relatório foi selecionado. Reativando Relatório Completo por padrão.${NC}"
             GENERATE_FULL_REPORT="true"
             ENABLE_FULL_REPORT="true"
        fi

        print_execution_summary
    fi
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
            var el = document.getElementById(id + '_content');
            if (!el) {
                alert("Detalhes técnicos não disponíveis neste relatório simplificado.");
                return;
            }
            var rawContent = el.innerHTML;
            var titleEl = document.getElementById(id + '_title');
            var title = titleEl ? titleEl.innerText : 'Detalhes';
            
            document.getElementById('modalTitle').innerText = title;
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

    local mode_hv="$1"
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
    
    <div class="dashboard" style="grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));">
EOF

    if [[ "$ENABLE_TCP_CHECK" == "true" ]]; then
        cat >> "$TEMP_STATS" << EOF
            <div class="card" style="border-left: 4px solid var(--accent-info);">
                <div style="display:flex; justify-content:space-between; align-items:center;">
                     <span class="card-label">TCP Checks</span>
                     <span style="font-size:1.5rem;">🔌</span>
                </div>
                <div style="margin-top:10px;">
                     <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${TCP_SUCCESS}</span> <span style="font-size:0.85em; color:var(--accent-success);">OK</span>
                     <span style="color:#666;">/</span>
                     <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${TCP_FAIL}</span> <span style="font-size:0.85em; color:var(--accent-danger);">Fail</span>
                </div>
            </div>
EOF
    fi

    if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
        cat >> "$TEMP_STATS" << EOF
            <div class="card" style="border-left: 4px solid #8b5cf6;">
                <div style="display:flex; justify-content:space-between; align-items:center;">
                     <span class="card-label">DNSSEC Checks</span>
                     <span style="font-size:1.5rem;">🔐</span>
                </div>
                <div style="margin-top:10px;">
                     <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${DNSSEC_SUCCESS}</span> <span style="font-size:0.85em; color:var(--accent-success);">Valid</span>
                     <span style="color:#666;">/</span>
                     <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${DNSSEC_ABSENT}</span> <span style="font-size:0.85em; color:var(--text-secondary);">Absent</span>
                     <span style="color:#666;">/</span>
                     <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${DNSSEC_FAIL}</span> <span style="font-size:0.85em; color:var(--accent-danger);">Fail</span>
                </div>
            </div>
EOF
    fi

    cat >> "$TEMP_STATS" << EOF
        </div>
EOF
    
    # Adding Security Cards Row
    cat >> "$TEMP_STATS" << EOF
    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px;">
        <div class="card" style="border-left: 4px solid var(--accent-primary);">
            <div style="display:flex; justify-content:space-between; align-items:center;">
                 <span class="card-label">Version Privacy</span>
                 <span style="font-size:1.5rem;">🕵️</span>
            </div>
            <div style="margin-top:10px;">
                 <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${SEC_HIDDEN}</span> <span style="font-size:0.85em; color:var(--accent-success);">Hidden</span>
                 <span style="color:#666;">/</span>
                 <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${SEC_REVEALED}</span> <span style="font-size:0.85em; color:var(--accent-danger);">Revealed</span>
            </div>
        </div>
        <div class="card" style="border-left: 4px solid var(--accent-warning);">
            <div style="display:flex; justify-content:space-between; align-items:center;">
                 <span class="card-label">Zone Transfer</span>
                 <span style="font-size:1.5rem;">📂</span>
            </div>
            <div style="margin-top:10px;">
                 <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${SEC_AXFR_OK}</span> <span style="font-size:0.85em; color:var(--accent-success);">Denied</span>
                 <span style="color:#666;">/</span>
                 <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${SEC_AXFR_RISK}</span> <span style="font-size:0.85em; color:var(--accent-danger);">Allowed</span>
            </div>
        </div>
        <div class="card" style="border-left: 4px solid var(--accent-danger);">
             <div style="display:flex; justify-content:space-between; align-items:center;">
                 <span class="card-label">Recursion</span>
                 <span style="font-size:1.5rem;">🔄</span>
            </div>
            <div style="margin-top:10px;">
                 <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${SEC_REC_OK}</span> <span style="font-size:0.85em; color:var(--accent-success);">Closed</span>
                 <span style="color:#666;">/</span>
                 <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${SEC_REC_RISK}</span> <span style="font-size:0.85em; color:var(--accent-danger);">Open</span>
            </div>
        </div>
EOF
    # SOA Sync Card
    if [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" ]]; then
    cat >> "$TEMP_STATS" << EOF
        <div class="card" style="border-left: 4px solid var(--accent-divergent);">
            <div style="display:flex; justify-content:space-between; align-items:center;">
                 <span class="card-label">SOA Sync</span>
                 <span style="font-size:1.5rem;">⚖️</span>
            </div>
            <div style="margin-top:10px;">
                 <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${SOA_SYNC_OK}</span> <span style="font-size:0.85em; color:var(--accent-success);">Synced</span>
                 <span style="color:#666;">/</span>
                 <span style="font-weight:700; font-size:1.2rem; color:var(--text-primary);">${SOA_SYNC_FAIL}</span> <span style="font-size:0.85em; color:var(--accent-danger);">Divergent</span>
            </div>
        </div>
EOF
    fi

    cat >> "$TEMP_STATS" << EOF
    </div>
EOF
}

generate_object_summary() {
    cat > "logs/temp_obj_summary_$$.html" << EOF
        <details class="section-details" style="margin-top: 20px; border-left: 4px solid var(--accent-primary);">
            <summary style="font-size: 1.1rem; font-weight: 600;">📋 Testes DNS TCP e DNS SEC</summary>
            <div style="padding: 20px;">
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
                <pre id="modalText"></pre>
            </div>
        </div>
    </div>
EOF
}

assemble_html() {
    local mode="$1"
    local target_file="$HTML_FILE"
    
    if [[ "$mode" == "simple" ]]; then
        target_file="${HTML_FILE%.html}_simple.html"
    fi
    
    generate_stats_block
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
    
    cat "$TEMP_DISCLAIMER" >> "$target_file"
    
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

    # ADD SECURITY SECTION
    # Only if TEMP_SECURITY has content (it was populated by generate_security_html which reads from the raw log buffer)
    # Actually wait, run_security_diagnostics populates a buffer, then we wrap it. 
    # Let's adjust: run_security_diagnostics writes rows to TEMP_SECURITY_ROWS.
    # Then generate_security_html wraps it into TEMP_SECURITY (block).
    
    if [[ -s "$TEMP_SECURITY" ]]; then
        if [[ "$mode" == "simple" ]]; then
             cat "$TEMP_SECURITY_SIMPLE" >> "$target_file"
        else
             cat "$TEMP_SECURITY" >> "$target_file"
        fi
    fi

    if [[ -s "$TEMP_TRACE" ]]; then
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

    if [[ -s "$TEMP_SERVICES" ]]; then
         cat >> "$target_file" << EOF
        <details class="section-details" style="margin-top: 20px; border-left: 4px solid #8b5cf6;">
             <summary style="font-size: 1.1rem; font-weight: 600;">🛡️ Serviços DNS & Capabilities (TCP/DNSSEC)</summary>
             <div class="table-responsive" style="padding:15px;">
EOF
        if [[ "$mode" == "simple" ]]; then
             cat "$TEMP_SERVICES_SIMPLE" >> "$target_file"
        else
             cat "$TEMP_SERVICES" >> "$target_file"
        fi
        echo "</div></details>" >> "$target_file"
    fi

    # Mover Resumo da Execução para cá (após os resultados, antes das configs)
    cat "logs/temp_obj_summary_$$.html" >> "$target_file"

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
            echo "$1" | grep -q -E -i "connection timed out|communications error|no servers could be reached|couldn't get address|network is unreachable"
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
                target_axfr=$(head -1 "$FILE_DOMAINS" | awk -F';' '{print $1}')
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
            
            if is_network_error "$axfr_out"; then
                 axfr_res="TIMEOUT"
                 axfr_class="status-neutral"
                 SEC_AXFR_TIMEOUT+=1
                 if [[ "$VERBOSE" == "true" ]]; then echo -ne "${GRAY}AXFR:TIMEOUT${NC} "; fi
            elif echo "$axfr_out" | grep -q -i -E "Transfer failed|REFUSED|SERVFAIL|communications error|timed out|no servers"; then
                 if echo "$axfr_out" | grep -q -E "REFUSED|Transfer failed"; then
                     axfr_res="DENIED (OK)"
                     axfr_class="status-ok"
                     SEC_AXFR_OK+=1
                     [[ "$VERBOSE" == "true" ]] && echo -ne "${GREEN}AXFR:OK${NC} "
                 else 
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
               # If v_res=TIMEOUT and axfr_res=TIMEOUT and rec_res=TIMEOUT, then it's not "Secure", it's "Unreachable"
               if [[ "$v_res" == "TIMEOUT" || "$axfr_res" == "TIMEOUT" || "$rec_res" == "TIMEOUT" ]]; then
                    echo -e "${GRAY}⚠️ Timeouts${NC}"
               else
                    echo -e "${GREEN}✅ Secure${NC}"
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
        local start_p=$(date +%s%N)
        local output; output=$($ping_cmd -c $PING_COUNT -W $PING_TIMEOUT $ip 2>&1); local ret=$?
        TOTAL_PING_SENT+=$PING_COUNT
        local end_p=$(date +%s%N); local dur_p=$(( (end_p - start_p) / 1000000 ))
        
        log_cmd_result "PING $ip" "$ping_cmd -c $PING_COUNT -W $PING_TIMEOUT $ip" "$output" "$dur_p"
        
        local loss=$(echo "$output" | grep "packet loss" | awk -F'%' '{print $1}' | awk '{print $NF}')
        [[ -z "$loss" ]] && loss=100
        local rtt_avg=$(echo "$output" | awk -F '/' '/rtt/ {print $5}')
        [[ -z "$rtt_avg" ]] && rtt_avg="N/A"
        
        local status_html=""; local class_html=""; local console_res=""
        if [[ "$ret" -ne 0 ]] || [[ "$loss" == "100" ]]; then status_html="❌ DOWN"; class_html="status-fail"; console_res="${RED}DOWN${NC}"
        elif [[ "$loss" != "0" ]]; then status_html="⚠️ UNSTABLE"; class_html="status-warning"; console_res="${YELLOW}${loss}% Loss${NC}"
        else status_html="✅ UP"; class_html="status-ok"; console_res="${GREEN}${rtt_avg}ms${NC}"; fi
        
        echo -e "$console_res"
        if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
            echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td class=\"$class_html\">$status_html</td><td>${loss}%</td><td>${rtt_avg}ms</td></tr>" >> "$TEMP_PING"
            local safe_output=$(echo "$output" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            echo "<tr><td colspan=\"5\" style=\"padding:0; border:none;\"><details style=\"margin:5px;\"><summary style=\"font-size:0.8em; color:#888;\">Ver output ping #$ping_id</summary><pre>$safe_output</pre></details></td></tr>" >> "$TEMP_PING"
        fi

        if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
            echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td class=\"$class_html\">$status_html</td><td>${loss}%</td><td>${rtt_avg}ms</td></tr>" >> "$TEMP_PING_SIMPLE"
        fi
        
        if [[ "$GENERATE_JSON_REPORT" == "true" ]]; then
            # Clean RTT for JSON (remove 'ms' if exists, though awk above likely kept it pure numbers or N/A)
            # JSON format: { "ip": "...", "groups": "...", "status": "...", "loss_percent": ..., "rtt_avg_ms": ... },
            # We handle the trailing comma later or use a list join strategy
            echo "{ \"ip\": \"$ip\", \"groups\": \"$(echo $groups_str | xargs)\", \"status\": \"$(echo $status_html | sed 's/.* //')\", \"loss_percent\": \"$loss\", \"rtt_avg_ms\": \"$rtt_avg\" }," >> "$TEMP_JSON_Ping"
        fi
    done
}

run_trace_diagnostics() {
    [[ "$ENABLE_TRACE_CHECK" != "true" ]] && return
    echo -e "\n${BLUE}=== INICIANDO TRACEROUTE ===${NC}"
    log_section "TRACEROUTE NETWORK PATH"
    
    local cmd_trace=""
    if command -v traceroute &> /dev/null; then cmd_trace="traceroute -n -w $TIMEOUT -q 1 -m 15"
    elif command -v tracepath &> /dev/null; then cmd_trace="tracepath -n"
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

    echo "<table><thead><tr><th>Grupo</th><th>Servidor</th><th>Hops</th><th>Caminho (Resumo)</th></tr></thead><tbody>" >> "$TEMP_TRACE"
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
        
        # Check if output looks valid (contains hops)
        if [[ $ret -eq 0 ]] && echo "$output" | grep -qE "^[ ]*[0-9]+"; then
            hops=$(echo "$output" | grep -E "^[ ]*[0-9]+" | wc -l)
            last_hop=$(echo "$output" | tail -1 | xargs)
        else
            # Try to extract error message if short enough, otherwise specific message
            if [[ ${#output} -lt 50 && -n "$output" ]]; then
                 last_hop="Error: $output"
            elif [[ -n "$output" ]]; then
                 last_hop="Trace failed (See expanded log)"
            fi
        fi
        
        echo -e "${CYAN}${hops} hops${NC}"
        
        if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
            echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td>${hops}</td><td><span style=\"font-size:0.85em; color:#888;\">$last_hop</span></td></tr>" >> "$TEMP_TRACE"
            local safe_output=$(echo "$output" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            echo "<tr><td colspan=\"4\" style=\"padding:0; border:none;\"><details style=\"margin:5px;\"><summary style=\"font-size:0.8em; color:#888;\">Ver rota completa #$trace_id</summary><pre>$safe_output</pre></details></td></tr>" >> "$TEMP_TRACE"
        fi

        if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
            echo "<tr><td><span class=\"badge\">$groups_str</span></td><td><strong>$ip</strong></td><td>${hops}</td><td><span style=\"font-size:0.85em; color:#888;\">$last_hop</span></td></tr>" >> "$TEMP_TRACE_SIMPLE"
        fi
        
        if [[ "$GENERATE_JSON_REPORT" == "true" ]]; then
            # Clean output for JSON string to avoid breaking json
            local j_out=$(echo "$output" | tr '"' "'" | tr '\n' ' ' | sed 's/\\/\\\\/g')
            local j_hops="$hops" # string or number
            if [[ "$hops" == "-" ]]; then j_hops=0; fi
            local clean_last_hop=$(echo "$last_hop" | tr '"' "'")
            echo "{ \"ip\": \"$ip\", \"groups\": \"$groups_str\", \"hops\": $j_hops, \"last_hop\": \"$clean_last_hop\" }," >> "$TEMP_JSON_Trace"
        fi
    done
    echo "</tbody></table>" >> "$TEMP_TRACE"
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
    echo -e "$legend"
    
    # Temp files for buffering
    local TEMP_DOMAIN_BODY="logs/temp_domain_body_$$.html"
    local TEMP_GROUP_BODY="logs/temp_group_body_$$.html"
    local TEMP_DOMAIN_BODY_SIMPLE="logs/temp_domain_body_simple_$$.html"
    local TEMP_GROUP_BODY_SIMPLE="logs/temp_group_body_simple_$$.html"
    
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
        > "$TEMP_DOMAIN_BODY_SIMPLE"

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
            > "$TEMP_GROUP_BODY"
            > "$TEMP_GROUP_BODY_SIMPLE"

            echo "<div class=\"table-responsive\"><table><thead><tr><th style=\"width:30%\">Target (Record)</th>" >> "$TEMP_GROUP_BODY"
            echo "<div class=\"table-responsive\"><table><thead><tr><th style=\"width:30%\">Target (Record)</th>" >> "$TEMP_GROUP_BODY_SIMPLE"
            for srv in "${srv_list[@]}"; do 
                echo "<th>$srv</th>" >> "$TEMP_GROUP_BODY"
                echo "<th>$srv</th>" >> "$TEMP_GROUP_BODY_SIMPLE"
            done
            echo "</tr></thead><tbody>" >> "$TEMP_GROUP_BODY"
            echo "</tr></thead><tbody>" >> "$TEMP_GROUP_BODY_SIMPLE"
            
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
                             [[ "$IP_VERSION" == "ipv4" ]] && opts_tcp+=" -4"
                             opts_tcp+=" +tcp +time=$TIMEOUT"
                             local out_tcp=$(dig $opts_tcp @$srv $target A 2>&1)
                             log_cmd_result "TCP CHECK $srv -> $target" "dig $opts_tcp @$srv $target A" "$out_tcp" "0"
                             
                             if [[ "$GENERATE_FULL_REPORT" == "true" ]]; then
                                 local safe_tcp=$(echo "$out_tcp" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                                 echo "<div id=\"${tcp_id}_content\" style=\"display:none\"><pre>$safe_tcp</pre></div>" >> "$TEMP_DETAILS"
                                 echo "<div id=\"${tcp_id}_title\" style=\"display:none\">TCP Check | $srv &rarr; $target</div>" >> "$TEMP_DETAILS"
                             fi

                             if echo "$out_tcp" | grep -q -E "connection timed out|communications error|no servers could be reached"; then
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
                        echo "<tr><td><span class=\"badge badge-type\">$mode</span> <strong>$target</strong> <span style=\"color:var(--text-secondary)\">($rec)</span></td>" >> "$TEMP_GROUP_BODY"
                        echo "<tr><td><span class=\"badge badge-type\">$mode</span> <strong>$target</strong> <span style=\"color:var(--text-secondary)\">($rec)</span></td>" >> "$TEMP_GROUP_BODY_SIMPLE"
                        
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

                            for (( iter=1; iter<=CONSISTENCY_CHECKS; iter++ )); do
                                local opts_str; [[ "$mode" == "iterative" ]] && opts_str="$DEFAULT_DIG_OPTIONS" || opts_str="$RECURSIVE_DIG_OPTIONS"
                                local opts_arr; read -ra opts_arr <<< "$opts_str"
                                local cur_timeout="${DNS_GROUP_TIMEOUT[$grp]}"; [[ -z "$cur_timeout" ]] && cur_timeout=$TIMEOUT
                                opts_arr+=("+time=$cur_timeout")
                                local cmd_arr=("dig" "${opts_arr[@]}" "@$srv" "$target" "$rec")
                                
                                [[ "$VERBOSE" == "true" ]] && echo -e "\n     ${GRAY}[VERBOSE] #${iter} Running: ${cmd_arr[*]}${NC}"
                                
                                local start_ts=$(date +%s%N); local output; output=$("${cmd_arr[@]}" 2>&1); local ret=$?
                                local end_ts=$(date +%s%N); local dur=$(( (end_ts - start_ts) / 1000000 )); final_dur=$dur
                                log_cmd_result "QUERY #$iter $srv -> $target ($rec)" "${cmd_arr[*]}" "$output" "$dur"

                                local normalized=$(normalize_dig_output "$output")
                                if [[ $iter -gt 1 ]]; then
                                    if [[ "$normalized" != "$last_normalized" ]]; then is_divergent="true"; else consistent_count=$((consistent_count + 1)); fi
                                else last_normalized="$normalized"; consistent_count=1; fi

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

                                [[ "$SLEEP" != "0" && $iter -lt $CONSISTENCY_CHECKS ]] && { sleep "$SLEEP"; TOTAL_SLEEP_TIME=$(LC_NUMERIC=C awk "BEGIN {print $TOTAL_SLEEP_TIME + $SLEEP}"); }
                            done
                            
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
                                [[ "$final_class" == "status-fail" ]] && { FAILED_TESTS+=1; g_fail=$((g_fail+1)); echo -ne "${RED}x${NC}"; }
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
                                  echo -ne " ${RED}[${warning_msg}]${NC}"
                                  log_entry "SOA SERIAL DIVERGENCE: Domain=$target Group=$grp Serials=${unique_serials[*]}"
                             else
                                  SOA_SYNC_OK+=1
                                  echo -ne " ${GREEN}[SOA: ${unique_serials[0]}]${NC}"
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
                                  echo "<tr><td colspan='$(( ${#srv_list[@]} + 1 ))' style='background:rgba(239, 68, 68, 0.1); color:var(--accent-warning); font-weight:bold; text-align:center;'>⚠️ SOA Serial Divergence Detected: ${unique_serials[@]}</td></tr>" >> "$TEMP_GROUP_BODY"
                                  echo "<tr><td colspan='$(( ${#srv_list[@]} + 1 ))' style='background:rgba(239, 68, 68, 0.1); color:var(--accent-warning); font-weight:bold; text-align:center;'>⚠️ SOA Serial Divergence Detected: ${unique_serials[@]}</td></tr>" >> "$TEMP_GROUP_BODY_SIMPLE"
                        fi

                        

                        echo "</tr>" >> "$TEMP_GROUP_BODY"
                        echo "</tr>" >> "$TEMP_GROUP_BODY_SIMPLE"
                    done
                done
            done
            # Close table AFTER all modes and targets are done
            echo "</tbody></table></div>" >> "$TEMP_GROUP_BODY"
            echo "</tbody></table></div>" >> "$TEMP_GROUP_BODY_SIMPLE"

            d_total=$((d_total + g_total)); d_ok=$((d_ok + g_ok)); d_warn=$((d_warn + g_warn))
            d_fail=$((d_fail + g_fail)); d_div=$((d_div + g_div))

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

            echo "<details class=\"group-level\"><summary>📂 Grupo: $grp $g_stats_html</summary>" >> "$TEMP_DOMAIN_BODY_SIMPLE"
            cat "$TEMP_GROUP_BODY_SIMPLE" >> "$TEMP_DOMAIN_BODY_SIMPLE"
            echo "</details>" >> "$TEMP_DOMAIN_BODY_SIMPLE"
            
            echo "" 
        done
        
        local d_stats_html="<span style=\"font-size:0.85em; margin-left:15px; font-weight:normal; opacity:0.9;\">"
        d_stats_html+="Tests: <strong>$d_total</strong> | "
        [[ $d_ok -gt 0 ]] && d_stats_html+="<span class=\"st-ok\">✅ $d_ok</span> "
        [[ $d_warn -gt 0 ]] && d_stats_html+="<span class=\"st-warn\">⚠️ $d_warn</span> "
        [[ $d_fail -gt 0 ]] && d_stats_html+="<span class=\"st-fail\">❌ $d_fail</span> "
        [[ $d_div -gt 0 ]] && d_stats_html+="<span class=\"st-div\">🔀 $d_div</span>"
        d_stats_html+="</span>"

        echo "<details class=\"domain-level\"><summary>🌐 $domain $d_stats_html <span style=\"font-size:0.8em; color:var(--text-secondary); margin-left:10px;\">[Recs: $record_types]</span> <span class=\"badge\" style=\"margin-left:auto\">$test_types</span></summary>" >> "$TEMP_MATRIX"
        cat "$TEMP_DOMAIN_BODY" >> "$TEMP_MATRIX"
        echo "</details>" >> "$TEMP_MATRIX"

        if [[ "$GENERATE_SIMPLE_REPORT" == "true" ]]; then
            echo "<details class=\"domain-level\"><summary>🌐 $domain $d_stats_html <span style=\"font-size:0.8em; color:var(--text-secondary); margin-left:10px;\">[Recs: $record_types]</span> <span class=\"badge\" style=\"margin-left:auto\">$test_types</span></summary>" >> "$TEMP_MATRIX_SIMPLE"
            cat "$TEMP_DOMAIN_BODY_SIMPLE" >> "$TEMP_MATRIX_SIMPLE"
            echo "</details>" >> "$TEMP_MATRIX_SIMPLE"
        fi
        
        echo ""
    done < "$FILE_DOMAINS"
    
    rm -f "$TEMP_DOMAIN_BODY" "$TEMP_GROUP_BODY" "$TEMP_DOMAIN_BODY_SIMPLE" "$TEMP_GROUP_BODY_SIMPLE"
}

assemble_json() {
    [[ "$GENERATE_JSON_REPORT" != "true" ]] && return
    
    local JSON_FILE="${HTML_FILE%.html}.json"
    
    # Helper to clean trailing comma from file content for valid JSON array
    # If file is empty, this results in empty string, which is fine for empty array
    local dns_data=""; [[ -f "$TEMP_JSON_DNS" ]] && dns_data=$(sed '$ s/,$//' "$TEMP_JSON_DNS")
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
    "total_pings_sent": $TOTAL_PING_SENT
  },
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
    # Print direct to terminal with colors
    echo -e "\n${BLUE}======================================================${NC}"
    echo -e "${BLUE}       RESUMO DA EXECUÇÃO (DASHBOARD TERMINAL)${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "  🔢 Total de Testes : ${TOTAL_TESTS}"
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
    
    echo -e "  🕒 Início          : ${START_TIME_HUMAN}"
    echo -e "  🕒 Final           : ${END_TIME_HUMAN}"
    echo -e "  🔄 Tentativas      : ${CONSISTENCY_CHECKS}x (Por check)"
    echo -e "  📡 Pings Enviados  : ${TOTAL_PING_SENT}"
    echo -e "  💤 Sleep Total     : ${TOTAL_SLEEP_TIME}s"
    echo -e "  ⏳ Duração Total   : ${TOTAL_DURATION}s"

    echo -e "\n${BLUE}--- SECURITY SCAN ---${NC}"
    echo -e "  PRIVACY   : ${GREEN}${SEC_HIDDEN}${NC} Hidden / ${RED}${SEC_REVEALED}${NC} Revealed / ${GRAY}${SEC_VER_TIMEOUT}${NC} Error"
    echo -e "  AXFR      : ${GREEN}${SEC_AXFR_OK}${NC} Denied / ${RED}${SEC_AXFR_RISK}${NC} Allowed  / ${GRAY}${SEC_AXFR_TIMEOUT}${NC} Error"
    echo -e "  RECURSION : ${GREEN}${SEC_REC_OK}${NC} Closed / ${RED}${SEC_REC_RISK}${NC} Open    / ${GRAY}${SEC_REC_TIMEOUT}${NC} Error"
    echo -e "  SOA SYNC  : ${GREEN}${SOA_SYNC_OK}${NC} Synced / ${RED}${SOA_SYNC_FAIL}${NC} Divergent"
    
    echo -e "${BLUE}======================================================${NC}"

    # Log to File (Strip ANSI codes)
    if [[ "$GENERATE_LOG_TEXT" == "true" ]]; then
         {
             echo ""
             echo "======================================================"
             echo "       RESUMO DA EXECUÇÃO (DASHBOARD TERMINAL)"
             echo "======================================================"
             echo "  Total de Testes : ${TOTAL_TESTS}"
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
             echo "  PRIVACY   : ${SEC_HIDDEN} Hidden / ${SEC_REVEALED} Revealed / ${SEC_VER_TIMEOUT} Error"
             echo "  AXFR      : ${SEC_AXFR_OK} Denied / ${SEC_AXFR_RISK} Allowed  / ${SEC_AXFR_TIMEOUT} Error"
             echo "  RECURSION : ${SEC_REC_OK} Closed / ${SEC_REC_RISK} Open    / ${SEC_REC_TIMEOUT} Error"
             echo "  SOA SYNC  : ${SOA_SYNC_OK} Synced / ${SOA_SYNC_FAIL} Divergent"
             echo "======================================================"
         } >> "$LOG_FILE_TEXT"
    fi
}

main() {
    START_TIME_EPOCH=$(date +%s); START_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S")

    # Define cleanup trap
    # Define cleanup trap
    trap 'rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS" "$TEMP_PING" "$TEMP_TRACE" "$TEMP_CONFIG" "$TEMP_TIMING" "$TEMP_MODAL" "$TEMP_DISCLAIMER" "$TEMP_SERVICES" "logs/temp_help_$$.html" "logs/temp_obj_summary_$$.html" "logs/temp_svc_table_$$.html" "$TEMP_TRACE_SIMPLE" "$TEMP_PING_SIMPLE" "$TEMP_MATRIX_SIMPLE" "$TEMP_SERVICES_SIMPLE" "logs/temp_domain_body_simple_$$.html" "logs/temp_group_body_simple_$$.html" "logs/temp_security_$$.html" "logs/temp_security_simple_$$.html" "logs/temp_sec_rows_$$.html" "$TEMP_JSON_Ping" "$TEMP_JSON_DNS" "$TEMP_JSON_Sec" "$TEMP_JSON_Trace" 2>/dev/null' EXIT

    # Initialize Flags based on Config
    GENERATE_FULL_REPORT="${ENABLE_FULL_REPORT:-true}"
    GENERATE_SIMPLE_REPORT="${ENABLE_SIMPLE_REPORT:-false}"
    # JSON Default comes from config file now (GENERATE_JSON_REPORT)

    while getopts ":n:g:lhyjstdxr" opt; do case ${opt} in 
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
    init_log_file
    validate_csv_files
    interactive_configuration
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
