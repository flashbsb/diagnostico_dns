#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS - EXECUTIVE EDITION
# Versão: 12.11.0
# "HTML Active Groups Filter"

# --- CONFIGURAÇÕES GERAIS ---
SCRIPT_VERSION="12.11.0"

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
    RED=$'\e[0;31m'
    GREEN=$'\e[0;32m'
    YELLOW=$'\e[1;33m'
    BLUE=$'\e[0;34m'
    CYAN=$'\e[0;36m'
    PURPLE=$'\e[0;35m'
    GRAY=$'\e[0;90m'
    NC=$'\e[0m'
fi

declare -A CONNECTIVITY_CACHE
declare -A HTML_CONN_ERR_LOGGED 
declare -i TOTAL_TESTS=0
declare -i CNT_TESTS_SRV=0
declare -i CNT_TESTS_ZONE=0
declare -i CNT_TESTS_REC=0
declare -i SUCC_TESTS_SRV=0
declare -i SUCC_TESTS_ZONE=0
declare -i SUCC_TESTS_REC=0
declare -i TOTAL_DNS_QUERY_COUNT=0
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
declare -i SOA_SYNC_FAIL=0
declare -i SOA_SYNC_OK=0
declare -i ZONE_SEC_SIGNED=0
declare -i ZONE_SEC_UNSIGNED=0
declare -i REC_OPEN_COUNT=0

# Modern Features Counters
declare -i EDNS_SUCCESS=0
declare -i EDNS_FAIL=0
declare -i COOKIE_SUCCESS=0
declare -i COOKIE_FAIL=0
declare -i QNAME_SUCCESS=0
declare -i QNAME_FAIL=0
declare -i QNAME_SKIP=0
declare -i TLS_SUCCESS=0
declare -i TLS_FAIL=0
declare -i DOT_SUCCESS=0
declare -i DOT_FAIL=0
declare -i DOH_SUCCESS=0
declare -i DOH_FAIL=0
declare -i TOTAL_PING_SENT=0
TOTAL_SLEEP_TIME=0
# Latency Tracking
TOTAL_LATENCY_SUM=0
declare -i TOTAL_LATENCY_COUNT=0
TOTAL_DNS_DURATION_SUM=0
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
# Record Stats (Global)
declare -gA STATS_REC_TOTAL
declare -gA STATS_REC_OK
declare -gA STATS_REC_FAIL
declare -gA GLOBAL_TCP_STATUS

# Resolve relative paths for input files (Priority: PWD > SCRIPT_DIR)
if [[ "$FILE_DOMAINS" != /* ]]; then
    if [[ -f "$PWD/$FILE_DOMAINS" ]]; then
        FILE_DOMAINS="$PWD/$FILE_DOMAINS"
    else
        FILE_DOMAINS="$SCRIPT_DIR/$FILE_DOMAINS"
    fi
fi

if [[ "$FILE_GROUPS" != /* ]]; then
    if [[ -f "$PWD/$FILE_GROUPS" ]]; then
        FILE_GROUPS="$PWD/$FILE_GROUPS"
    else
        FILE_GROUPS="$SCRIPT_DIR/$FILE_GROUPS"
    fi
fi

# Setup Log Directory
[[ -z "$LOG_DIR" ]] && LOG_DIR="logs"
if [[ "$LOG_DIR" == /* ]]; then
    LOG_OUTPUT_DIR="$LOG_DIR"
else
    LOG_OUTPUT_DIR="$PWD/$LOG_DIR"
fi

mkdir -p "$LOG_OUTPUT_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HTML_FILE="$LOG_OUTPUT_DIR/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}.html"
LOG_FILE_TEXT="$LOG_OUTPUT_DIR/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}.log"
LOG_FILE_JSON="$LOG_OUTPUT_DIR/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}.json"
LOG_FILE_CSV_SRV="$LOG_OUTPUT_DIR/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}_servers.csv"
LOG_FILE_CSV_ZONE="$LOG_OUTPUT_DIR/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}_zones.csv"
LOG_FILE_CSV_REC="$LOG_OUTPUT_DIR/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}_records.csv"

# Default Configuration (Respects Config File)
# 0=Quiet, 1=Summary, 2=Verbose (Cmds), 3=Debug (Outs)
VERBOSE_LEVEL=${VERBOSE_LEVEL:-1}


# Extra Features Defaults
ENABLE_EDNS_CHECK=${ENABLE_EDNS_CHECK:-"true"}
ENABLE_COOKIE_CHECK=${ENABLE_COOKIE_CHECK:-"true"}
ENABLE_QNAME_CHECK=${ENABLE_QNAME_CHECK:-"true"}
ENABLE_TLS_CHECK=${ENABLE_TLS_CHECK:-"true"}
ENABLE_DOT_CHECK=${ENABLE_DOT_CHECK:-"true"}
ENABLE_DOH_CHECK=${ENABLE_DOH_CHECK:-"true"}

# Phases Configuration (Default: All True)
ENABLE_PHASE_SERVER=${ENABLE_PHASE_SERVER:-"true"}
ENABLE_PHASE_ZONE=${ENABLE_PHASE_ZONE:-"true"}
ENABLE_PHASE_RECORD=${ENABLE_PHASE_RECORD:-"true"}

# Traceroute Defaults
ENABLE_TRACE=${ENABLE_TRACE:-"false"}
TRACE_MAX_HOPS=${TRACE_MAX_HOPS:-30}

init_html_parts() {
    # Generate unique session ID for temp files (PID + Random + Timestamp)
    SESSION_ID="${$}_${RANDOM}_$(date +%s%N)"

    TEMP_HEADER="$LOG_OUTPUT_DIR/temp_header_${SESSION_ID}.html"
    TEMP_STATS="$LOG_OUTPUT_DIR/temp_stats_${SESSION_ID}.html"
    TEMP_SERVICES="$LOG_OUTPUT_DIR/temp_services_${SESSION_ID}.html"
    TEMP_CONFIG="$LOG_OUTPUT_DIR/temp_config_${SESSION_ID}.html"
    TEMP_TIMING="$LOG_OUTPUT_DIR/temp_timing_${SESSION_ID}.html"
    TEMP_MODAL="$LOG_OUTPUT_DIR/temp_modal_${SESSION_ID}.html"
    TEMP_DISCLAIMER="$LOG_OUTPUT_DIR/temp_disclaimer_${SESSION_ID}.html"

    # Detailed Report Temp Files
    TEMP_MATRIX="$LOG_OUTPUT_DIR/temp_matrix_${SESSION_ID}.html"
    TEMP_DETAILS="$LOG_OUTPUT_DIR/temp_details_${SESSION_ID}.html"
    TEMP_PING="$LOG_OUTPUT_DIR/temp_ping_${SESSION_ID}.html"
    TEMP_TRACE="$LOG_OUTPUT_DIR/temp_trace_${SESSION_ID}.html"
    
    > "$TEMP_MATRIX"
    > "$TEMP_DETAILS"
    > "$TEMP_PING"
    > "$TEMP_TRACE"

    # Security Temp Files
    TEMP_SECURITY="$LOG_OUTPUT_DIR/temp_security_${SESSION_ID}.html"
    > "$TEMP_SECURITY"
    
    # New Sections Temp Files
    TEMP_SECTION_SERVER="$LOG_OUTPUT_DIR/temp_section_server_${SESSION_ID}.html"
    TEMP_SECTION_ZONE="$LOG_OUTPUT_DIR/temp_section_zone_${SESSION_ID}.html"
    TEMP_SECTION_RECORD="$LOG_OUTPUT_DIR/temp_section_record_${SESSION_ID}.html"
    > "$TEMP_SECTION_SERVER"
    > "$TEMP_SECTION_ZONE"
    > "$TEMP_SECTION_RECORD"

    TEMP_HEALTH_MAP="$LOG_OUTPUT_DIR/temp_health_${SESSION_ID}.html"
    > "$TEMP_HEALTH_MAP"
    
    # JSON Temp Files - Conditional Creation
    if [[ "$ENABLE_JSON_REPORT" == "true" ]]; then
        TEMP_JSON_Ping="$LOG_OUTPUT_DIR/temp_json_ping_${SESSION_ID}.json"
        TEMP_JSON_DNS="$LOG_OUTPUT_DIR/temp_json_dns_${SESSION_ID}.json"
        TEMP_JSON_Sec="$LOG_OUTPUT_DIR/temp_json_sec_${SESSION_ID}.json"
        TEMP_JSON_Trace="$LOG_OUTPUT_DIR/temp_json_trace_${SESSION_ID}.json"
        TEMP_JSON_DOMAINS="$LOG_OUTPUT_DIR/temp_domains_json_${SESSION_ID}.json"
        > "$TEMP_JSON_Ping"
        > "$TEMP_JSON_DNS"
        > "$TEMP_JSON_Sec"
        > "$TEMP_JSON_Trace"
        > "$TEMP_JSON_DOMAINS"
    fi
    
    # Exec Full Log (HTML Embed)
    TEMP_FULL_LOG="$LOG_OUTPUT_DIR/temp_full_log_${SESSION_ID}.txt"
    > "$TEMP_FULL_LOG"
    
    # Init CSV
    if [[ "$ENABLE_CSV_REPORT" == "true" ]]; then
        echo "Timestamp;Server;Groups;PingStatus;Latency;Jitter;Loss;Port53;Port853;Version;Recursion;EDNS;Cookie;DNSSEC;DoH;TLS" > "$LOG_FILE_CSV_SRV"
        echo "Timestamp;Domain;Server;Group;SOA_Serial;AXFR_Status;DNSSEC_Status" > "$LOG_FILE_CSV_ZONE"
        echo "Timestamp;Domain;Type;Group;Server;Status;Latency;Answer_Snippet" > "$LOG_FILE_CSV_REC"
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
    echo -e "  ${GREEN}-v${NC}            Aumenta Verbose (Nível 2: Logs CMD). Use -vv para Nível 3 (Debug total)."
    echo -e "  ${GREEN}-q${NC}            Modo Quieto (Nível 0: Apenas progresso)."
    echo -e ""
    echo -e "  ${GREEN}-j${NC}            Gera saída em JSON estruturado (.json)."
    echo -e "  ${GRAY}Nota: O relatório HTML Detalhado é gerado por padrão.${NC}"
    echo -e ""
    echo -e "  ${GREEN}-t${NC}            Habilita testes de conectividade TCP (Sobrescreve conf)."
    echo -e "  ${GREEN}-d${NC}            Habilita validação DNSSEC (Sobrescreve conf)."
    echo -e "  ${GREEN}-x${NC}            Habilita teste de transferência de zona (AXFR) (Sobrescreve conf)."
    echo -e "  ${GREEN}-r${NC}            Habilita teste de recursão aberta (Sobrescreve conf)."
    echo -e "  ${GREEN}-T${NC}            Habilita traceroute (Rota)."
    echo -e "  ${GREEN}-V${NC}            Habilita verificação de versão BIND (Chaos)."
    echo -e "  ${GREEN}-Z${NC}            Habilita verificação de sincronismo SOA."
    echo -e "  ${GREEN}-M${NC}            Habilita todos os testes Modernos (EDNS, Cookie, TLS, DoT, DoH)."
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
    echo -e "  ${CYAN}SLEEP${NC} (Padrão: 0.01s)"
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
    echo -e "  ${CYAN}ENABLE_JSON_REPORT${NC}
      Controla a geração do JSON. Padrão: false.
      
  ${CYAN}ENABLE_TCP_CHECK / ENABLE_DNSSEC_CHECK${NC}"
    echo -e "      Ativa verificações de conformidade RFC 7766 (TCP) e suporte a DNSSEC."
    echo -e ""
    echo -e "  ${CYAN}ENABLE_AXFR_CHECK / ENABLE_RECURSION_CHECK${NC}"
    echo -e "      Testes de segurança para permissividade de transferência de zona e recursão."
    echo -e "      "
    echo -e "  ${CYAN}ENABLE_SOA_SERIAL_CHECK${NC}
      Verifica se os números de série SOA são idênticos entre todos os servidores do grupo.

  ${CYAN}ENABLE_EDNS_CHECK / ENABLE_COOKIE_CHECK${NC}
      Verificam suporte a EDNS0 (RFC 6891) e DNS Cookies (RFC 7873).

  ${CYAN}ENABLE_TLS_CHECK / ENABLE_DOT_CHECK / ENABLE_DOH_CHECK${NC}
      Verificam suporte a transporte criptografado (TLS/853 e HTTPS/443).
"
    echo -e ""
    echo -e "  ${CYAN}LATENCY_WARNING_THRESHOLD${NC} (Default: 300ms)"
    echo -e "      Define o limiar para alertas amarelos de lentidão."
    echo -e ""
    echo -e "  ${CYAN}PING_PACKET_LOSS_LIMIT${NC} (Default: 10%)"
    echo -e "      Define a porcentagem aceitável de perda de pacotes antes de marcar como UNSTABLE."
    echo -e ""

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
    echo -e "  ${CYAN}ENABLE_LOG_TEXT / VERBOSE${NC}"
    echo -e "      Controle de verbosidade e geração de log forense em texto plano (.log)."
    echo -e "      Níveis: 0 (Quiet), 1 (Summary), 2 (Verbose), 3 (Debug)."
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
    
    cat > "$LOG_OUTPUT_DIR/temp_help_${SESSION_ID}.html" << EOF
        <details class="section-details" style="margin-top: 40px; border-left: 4px solid #64748b;">
            <summary style="font-size: 1.1rem; font-weight: 600;">📚 Manual de Referência (Help)</summary>
            <div class="modal-body" style="background: #1e293b; color: #cbd5e1; padding: 20px; font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace; font-size: 0.85rem; overflow-x: auto;">
                <pre style="white-space: pre-wrap;">$help_content</pre>
            </div>
        </details>
EOF
}

print_execution_summary() {
    clear
    echo -e "${BOLD}======================================================${NC}"
    echo -e "${BOLD}   🔍 DIAGNÓSTICO DNS - EXECUTIVE REPORT (v${SCRIPT_VERSION})   ${NC}"
    echo -e "${BOLD}======================================================${NC}"
    
    echo -e "${BLUE}[1. GERAL]${NC}"
    echo -e "  🏷️  Versão Script   : v${SCRIPT_VERSION}"
    echo -e "  📂 Arq. Domínios   : $FILE_DOMAINS"
    echo -e "  📂 Arq. Grupos     : $FILE_GROUPS"
    echo -e "  📂 Dir Logs        : $LOG_DIR (Prefix: $LOG_PREFIX)"
    echo -e "  ⏱️  Timeout Global  : ${TIMEOUT}s"
    echo -e "  💤 Sleep (Query)   : ${SLEEP}s"
    echo -e "  📡 Valida Conexão  : ${CYAN}${VALIDATE_CONNECTIVITY}${NC}"
    echo -e "  🛡️  Limit. Grupos   : ${CYAN}${ONLY_TEST_ACTIVE_GROUPS}${NC} (Active Only)"
    echo -e "  🎮 Modo Interativo : ${CYAN}${INTERACTIVE_MODE}${NC}"

    echo -e "\n${BLUE}[2. ESCOPO (FASES)]${NC}"
    echo -e "  1️⃣  Fase Servidor   : ${CYAN}${ENABLE_PHASE_SERVER}${NC}"
    echo -e "  2️⃣  Fase Zona       : ${CYAN}${ENABLE_PHASE_ZONE}${NC}"
    echo -e "  3️⃣  Fase Registro   : ${CYAN}${ENABLE_PHASE_RECORD}${NC}"

    if [[ "$ENABLE_PHASE_SERVER" == "true" ]]; then
        echo -e "\n${PURPLE}[3. DETALHES FASE 1: SERVIDORES]${NC}"
        echo -e "  🏓 Ping Check      : ${CYAN}${ENABLE_PING}${NC}"
        [[ "$ENABLE_PING" == "true" ]] && echo -e "     ↳ Count: $PING_COUNT | Timeout: ${PING_TIMEOUT}s | LossLimit: ${PING_PACKET_LOSS_LIMIT}%"
        echo -e "  🗺️  Traceroute     : ${CYAN}${ENABLE_TRACE}${NC}"
        [[ "$ENABLE_TRACE" == "true" ]] && echo -e "     ↳ Max Hops: $TRACE_MAX_HOPS"
        echo -e "  🔌 TCP Check       : ${CYAN}${ENABLE_TCP_CHECK}${NC}"
        echo -e "  🔐 DNSSEC Check    : ${CYAN}${ENABLE_DNSSEC_CHECK}${NC}"
        echo -e "  🛡️  BIND Version    : ${CYAN}${CHECK_BIND_VERSION}${NC}"
        echo -e "  🛡️  Recursion Check : ${CYAN}${ENABLE_RECURSION_CHECK}${NC}"
        echo -e "  🌟 EDNS0 Check     : ${CYAN}${ENABLE_EDNS_CHECK}${NC}"
        echo -e "  🍪 Cookie Check    : ${CYAN}${ENABLE_COOKIE_CHECK}${NC}"
        echo -e "  📉 QNAME Min       : ${CYAN}${ENABLE_QNAME_CHECK}${NC}"
        echo -e "  🔐 TLS Check       : ${CYAN}${ENABLE_TLS_CHECK}${NC}"
        echo -e "  🔒 DoT Check       : ${CYAN}${ENABLE_DOT_CHECK}${NC}"
        echo -e "  🌐 DoH Check       : ${CYAN}${ENABLE_DOH_CHECK}${NC}"
    fi

    if [[ "$ENABLE_PHASE_ZONE" == "true" ]]; then
        echo -e "\n${PURPLE}[4. DETALHES FASE 2: ZONAS]${NC}"
        echo -e "  🔄 SOA Serial Sync : ${CYAN}${ENABLE_SOA_SERIAL_CHECK}${NC}"
        echo -e "  🌍 AXFR Check      : ${CYAN}${ENABLE_AXFR_CHECK}${NC}"
    fi

    if [[ "$ENABLE_PHASE_RECORD" == "true" ]]; then
        echo -e "\n${PURPLE}[5. DETALHES FASE 3: REGISTROS]${NC}"
        echo -e "  🔄 Consistência    : ${CONSISTENCY_CHECKS} queries/servidor"
        echo -e "  ⚖️  Strict IP       : ${CYAN}${STRICT_IP_CHECK}${NC}"
        echo -e "  ⚖️  Strict Ordem    : ${CYAN}${STRICT_ORDER_CHECK}${NC}"
        echo -e "  ⚖️  Strict TTL      : ${CYAN}${STRICT_TTL_CHECK}${NC}"
    fi

    echo -e "\n${PURPLE}[6. CONFIG AVANÇADA]${NC}"
    echo -e "  ⚠️  Limiar Latência : ${LATENCY_WARNING_THRESHOLD}ms"
    echo -e "  🛠️  Dig (Std)       : ${GRAY}${DEFAULT_DIG_OPTIONS}${NC}"
    echo -e "  🛠️  Dig (Rec)       : ${GRAY}${RECURSIVE_DIG_OPTIONS}${NC}"
    echo -e "  📢 Verbose All      : ${VERBOSE_LEVEL} (0-3)"

    echo -e "\n${PURPLE}[7. RELATÓRIOS]${NC}"
    echo -e "  📄 Relatório HTML   : ${GREEN}${ENABLE_HTML_REPORT}${NC} (Charts: ${ENABLE_CHARTS})"
    echo -e "  📄 Relatório JSON   : ${CYAN}${ENABLE_JSON_REPORT}${NC}"
    echo -e "  📄 Relatório CSV    : ${CYAN}${ENABLE_CSV_REPORT}${NC}"
    
    echo -e "\n${PURPLE}[8. LOGS & SAÍDA]${NC}"
    echo -e "  📝 Log Texto (.log) : ${CYAN}${ENABLE_LOG_TEXT}${NC}"

    echo -e "  🎨 Color Output     : ${COLOR_OUTPUT}"
    echo -e "  📂 Output Dir       : $LOG_DIR"
    
    echo -e "${BLUE}======================================================${NC}"
    echo ""
}

# ==============================================
# LOGGING (TEXTO)
# ==============================================

log_entry() {
    local msg="$1"
    local ts=$(date +"%Y-%m-%d %H:%M:%S")
    # Always log to temp buffer for HTML
    echo -e "[$ts] $msg" >> "$TEMP_FULL_LOG"
    
    [[ "$ENABLE_LOG_TEXT" != "true" ]] && return
    echo -e "[$ts] $msg" >> "$LOG_FILE_TEXT"
}

log_section() {
    local title="$1"
    {
        echo ""
        echo "================================================================================"
        echo ">>> $title"
        echo "================================================================================"
    } >> "$TEMP_FULL_LOG"

    [[ "$ENABLE_LOG_TEXT" != "true" ]] && return
    {
        echo ""
        echo "================================================================================"
        echo ">>> $title"
        echo "================================================================================"
    } >> "$LOG_FILE_TEXT"
}

log_cmd_result() {
    local context="$1"; local cmd="$2"; local output="$3"; local time="$4"
    {
        echo "--------------------------------------------------------------------------------"
        echo "CTX: $context | CMD: $cmd | TIME: ${time}ms"
        echo "OUTPUT:"
        echo "$output"
        echo "--------------------------------------------------------------------------------"
    } >> "$TEMP_FULL_LOG"

    [[ "$ENABLE_LOG_TEXT" != "true" ]] && return
    {
        echo "--------------------------------------------------------------------------------"
        echo "CTX: $context | CMD: $cmd | TIME: ${time}ms"
        echo "OUTPUT:"
    echo "$output"
        echo "--------------------------------------------------------------------------------"
    } >> "$LOG_FILE_TEXT"
}

log_rotation() {
    local file="$1"
    local max_size=$((5 * 1024 * 1024)) # 5MB
    if [[ -f "$file" ]]; then
        local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
        if [[ $size -gt $max_size ]]; then
            mv "$file" "${file}.old"
            echo -e "Log rotation: ${file} -> ${file}.old"
        fi
    fi
}

init_log_file() {
    [[ "$ENABLE_LOG_TEXT" != "true" ]] && return
    
    log_rotation "$LOG_FILE_TEXT"
    
    {
        echo "DNS DIAGNOSTIC TOOL v$SCRIPT_VERSION - FORENSIC LOG"
        echo "Date: $START_TIME_HUMAN"
        echo "  Config Dump:"
        echo "  Files: Domains='$FILE_DOMAINS', Groups='$FILE_GROUPS'"
        echo "  Timeout: $TIMEOUT, Sleep: $SLEEP, ConnCheck: $VALIDATE_CONNECTIVITY"
        echo "  Consistency: $CONSISTENCY_CHECKS attempts"
        echo "  Criteria: StrictIP=$STRICT_IP_CHECK, StrictOrder=$STRICT_ORDER_CHECK, StrictTTL=$STRICT_TTL_CHECK"
        echo "  Special Tests: TCP=$ENABLE_TCP_CHECK, DNSSEC=$ENABLE_DNSSEC_CHECK"
        echo "  Security: Version=$CHECK_BIND_VERSION, AXFR=$ENABLE_AXFR_CHECK, Recursion=$ENABLE_RECURSION_CHECK, SOA_Sync=$ENABLE_SOA_SERIAL_CHECK
"
        echo "  Ping: Enabled=$ENABLE_PING, Count=$PING_COUNT, Timeout=$PING_TIMEOUT, LossLimit=$PING_PACKET_LOSS_LIMIT%"
        echo "  Analysis: LatencyThreshold=${LATENCY_WARNING_THRESHOLD}ms, Color=$COLOR_OUTPUT"
        echo "  Reports: Full=$ENABLE_FULL_REPORT, Simple=$ENABLE_SIMPLE_REPORT"
        echo "  Dig Opts: $DEFAULT_DIG_OPTIONS"
        echo "  Rec Dig Opts: $RECURSIVE_DIG_OPTIONS"
        echo "  Verbose Level: $VERBOSE_LEVEL"
        echo ""
    } >> "$LOG_FILE_TEXT" # Append mode due to shared file
    
    if [[ "$ENABLE_JSON_LOG" == "true" ]]; then
        log_rotation "$LOG_FILE_JSON"
        # Init or append JSON log array start? 
        # For simplicity, line-delimited JSON (NDJSON) is better for streaming logs
    fi
}

log_json() {
    [[ "$ENABLE_JSON_LOG" != "true" ]] && return
    local level="$1"
    local msg="$2"
    # Basic JSON construction using string interpolation
    # Escape quotes in msg
    local safe_msg="${msg//\"/\\\"}"
    local ts=$(date -Iseconds)
    echo "{\"timestamp\": \"$ts\", \"level\": \"$level\", \"message\": \"$safe_msg\"}" >> "$LOG_FILE_JSON"
}

log_cmd_result() {
    [[ "$ENABLE_LOG_TEXT" != "true" ]] && return
    local context="$1"; local cmd="$2"; local output="$3"; local time="$4"
    {
        echo "--------------------------------------------------------------------------------"
        echo "CTX: $context | CMD: $cmd | TIME: ${time}ms"
        echo "OUTPUT:"
        echo "$output"
        echo "--------------------------------------------------------------------------------"
    } >> "$LOG_FILE_TEXT"
    
    log_json "INFO" "CTX: $context | TIME: ${time}ms"
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
        
        # --- 1. GLOBAL CONFIGURATION ---
        echo -e "\n${BLUE}--- GERAL (GLOBAL) ---${NC}"
        ask_variable "Arquivo de Domínios (CSV)" "FILE_DOMAINS"
        ask_variable "Arquivo de Grupos (CSV)" "FILE_GROUPS"
        ask_variable "Diretório de Logs" "LOG_DIR"
        ask_variable "Prefixo arquivos Log" "LOG_PREFIX"
        
        ask_variable "Timeout Global (segundos)" "TIMEOUT"
        ask_variable "Sleep entre queries (segundos)" "SLEEP"
        ask_boolean "Validar conectividade porta 53?" "VALIDATE_CONNECTIVITY"
        
        ask_variable "Nível de Verbose log (0-3)?" "VERBOSE_LEVEL"
        ask_boolean "Gerar log texto (.log)?" "ENABLE_LOG_TEXT"
        ask_boolean "Habilitar Gráficos no HTML?" "ENABLE_CHARTS"
        ask_boolean "Gerar relatório Detalhado HTML?" "ENABLE_HTML_REPORT"
        ask_boolean "Gerar relatório JSON (Report)?" "ENABLE_JSON_REPORT"

        ask_boolean "Gerar relatório CSV (Plano)?" "ENABLE_CSV_REPORT"
        
        ask_boolean "Testar SOMENTE grupos usados por domínios?" "ONLY_TEST_ACTIVE_GROUPS"

        # --- 2. PHASE SELECTION ---
        echo -e "\n${BLUE}--- SELEÇÃO DE FASES (ESCOPO) ---${NC}"
        ask_boolean "Executar FASE 1: Testes de Servidores (Infra/Sec/Modern)?" "ENABLE_PHASE_SERVER"
        ask_boolean "Executar FASE 2: Testes de Zona (SOA/AXFR/DNSSEC)?" "ENABLE_PHASE_ZONE"
        ask_boolean "Executar FASE 3: Testes de Registros (Resolução)?" "ENABLE_PHASE_RECORD"

        # --- 3. CONDITIONAL OPTIONS ---

        # FASE 1: SERVIDORES
        if [[ "$ENABLE_PHASE_SERVER" == "true" ]]; then
            echo -e "\n${BLUE}--- OPÇÕES FASE 1 (SERVIDORES) ---${NC}"
            ask_boolean "Ativar Ping ICMP?" "ENABLE_PING"
            if [[ "$ENABLE_PING" == "true" ]]; then
                 ask_variable "   ↳ Ping Count" "PING_COUNT"
                 ask_variable "   ↳ Ping Timeout (s)" "PING_TIMEOUT"
            fi
            
            ask_boolean "Ativar Traceroute?" "ENABLE_TRACE"
            if [[ "$ENABLE_TRACE" == "true" ]]; then
                 ask_variable "   ↳ Max Hops" "TRACE_MAX_HOPS"
            fi

            ask_boolean "Ativar Teste TCP (+tcp)?" "ENABLE_TCP_CHECK"
            ask_boolean "Ativar Teste DNSSEC (+dnssec validation)?" "ENABLE_DNSSEC_CHECK"
            
            ask_boolean "Verificar Versão (BIND Privacy)?" "CHECK_BIND_VERSION"
            ask_boolean "Verificar Recursão Aberta?" "ENABLE_RECURSION_CHECK"
            
            echo -e "${GRAY}   [Modern Standards]${NC}"
            ask_boolean "   Verificar EDNS0?" "ENABLE_EDNS_CHECK"
            ask_boolean "   Verificar DNS Cookies?" "ENABLE_COOKIE_CHECK"
            ask_boolean "   Verificar QNAME Minimization?" "ENABLE_QNAME_CHECK"
            ask_boolean "   Verificar TLS Connection?" "ENABLE_TLS_CHECK"
            ask_boolean "   Verificar DoT (DNS over TLS)?" "ENABLE_DOT_CHECK"
            ask_boolean "   Verificar DoH (DNS over HTTPS)?" "ENABLE_DOH_CHECK"
        fi

        # FASE 2: ZONAS
        if [[ "$ENABLE_PHASE_ZONE" == "true" ]]; then
            echo -e "\n${BLUE}--- OPÇÕES FASE 2 (ZONAS) ---${NC}"
            ask_boolean "Verificar Sincronismo SOA?" "ENABLE_SOA_SERIAL_CHECK"
            ask_boolean "Verificar Zone Transfer (AXFR)?" "ENABLE_AXFR_CHECK"
        fi
        
        # FASE 3: REGISTROS
        if [[ "$ENABLE_PHASE_RECORD" == "true" ]]; then
            echo -e "\n${BLUE}--- OPÇÕES FASE 3 (REGISTROS) ---${NC}"
            ask_variable "Tentativas por Teste (Consistência)" "CONSISTENCY_CHECKS"
            
            echo -e "\n${BLUE}--- CRITÉRIOS DE DIVERGÊNCIA (TOLERÂNCIA) ---${NC}"
            echo -e "${GRAY}(Se 'true', qualquer variação é marcada como divergente)${NC}"
            ask_boolean "Considerar mudança de IP como divergência?" "STRICT_IP_CHECK"
            ask_boolean "Considerar mudança de Ordem como divergência?" "STRICT_ORDER_CHECK"
            ask_boolean "Considerar mudança de TTL como divergência?" "STRICT_TTL_CHECK"
        fi
        
        # --- 4. ADVANCED & ANALYSIS ---
        echo -e "\n${BLUE}--- OPÇÕES AVANÇADAS & ANÁLISE ---${NC}"
        ask_variable "Dig Options (Padrão/Iterativo)" "DEFAULT_DIG_OPTIONS"
        ask_variable "Dig Options (Recursivo)" "RECURSIVE_DIG_OPTIONS"
        
        ask_variable "Limiar de Alerta de Latência (ms)" "LATENCY_WARNING_THRESHOLD"
        ask_variable "Limite tolerável de Perda de Pacotes (%)" "PING_PACKET_LOSS_LIMIT"
        ask_boolean "Habilitar Cores no Terminal?" "COLOR_OUTPUT"
        
        echo -e "\n${GREEN}Configurações atualizadas!${NC}"

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
    
    # Backup existing config
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    echo -e "     ${GRAY}ℹ️  Backup criado: ${CONFIG_FILE}.bak${NC}"
    
    # Helper to update key="val" or key=val in conf file
    # Handles quoted and unquoted values, preserves comments
    update_conf_key() {
        local key="$1"
        local val="$2"
        # Escape slashes in value just in case (though mostly simple strings here)
        val="${val//\//\\/}"
        
        sed -i "s|^$key=.*|$key=\"$val\"|" "$CONFIG_FILE"
    }
    
    # Batch Update
    update_conf_key "FILE_DOMAINS" "$FILE_DOMAINS"
    update_conf_key "FILE_GROUPS" "$FILE_GROUPS"
    update_conf_key "LOG_DIR" "$LOG_DIR"
    update_conf_key "LOG_PREFIX" "$LOG_PREFIX"
    sed -i "s|^CONSISTENCY_CHECKS=.*|CONSISTENCY_CHECKS=$CONSISTENCY_CHECKS|" "$CONFIG_FILE" # Numeric
    sed -i "s|^TIMEOUT=.*|TIMEOUT=$TIMEOUT|" "$CONFIG_FILE" # Numeric
    sed -i "s|^SLEEP=.*|SLEEP=$SLEEP|" "$CONFIG_FILE" # Numeric
    
    update_conf_key "VALIDATE_CONNECTIVITY" "$VALIDATE_CONNECTIVITY"
    sed -i "s|^VERBOSE_LEVEL=.*|VERBOSE_LEVEL=$VERBOSE_LEVEL|" "$CONFIG_FILE" # Numeric

    update_conf_key "ENABLE_LOG_TEXT" "$ENABLE_LOG_TEXT"
    
    # Report Flags
    update_conf_key "ENABLE_CHARTS" "$ENABLE_CHARTS"
    update_conf_key "ENABLE_HTML_REPORT" "$ENABLE_HTML_REPORT"
    update_conf_key "ENABLE_JSON_REPORT" "$ENABLE_JSON_REPORT"
    update_conf_key "ENABLE_CSV_REPORT" "$ENABLE_CSV_REPORT"
    
    # Tests
    update_conf_key "ENABLE_PHASE_SERVER" "$ENABLE_PHASE_SERVER"
    update_conf_key "ENABLE_PHASE_ZONE" "$ENABLE_PHASE_ZONE"
    update_conf_key "ENABLE_PHASE_RECORD" "$ENABLE_PHASE_RECORD"

    sed -i "s|^ENABLE_PING=.*|ENABLE_PING=$ENABLE_PING|" "$CONFIG_FILE"
    if [[ "$ENABLE_PING" == "true" ]]; then
        sed -i "s|^PING_COUNT=.*|PING_COUNT=$PING_COUNT|" "$CONFIG_FILE"
        sed -i "s|^PING_TIMEOUT=.*|PING_TIMEOUT=$PING_TIMEOUT|" "$CONFIG_FILE"
    fi
    update_conf_key "ENABLE_TRACE" "$ENABLE_TRACE"
    if [[ "$ENABLE_TRACE" == "true" ]]; then
        sed -i "s|^TRACE_MAX_HOPS=.*|TRACE_MAX_HOPS=$TRACE_MAX_HOPS|" "$CONFIG_FILE"
    fi
    update_conf_key "ENABLE_TCP_CHECK" "$ENABLE_TCP_CHECK"
    update_conf_key "ENABLE_DNSSEC_CHECK" "$ENABLE_DNSSEC_CHECK"

    update_conf_key "ONLY_TEST_ACTIVE_GROUPS" "$ONLY_TEST_ACTIVE_GROUPS"
    
    # Security
    update_conf_key "CHECK_BIND_VERSION" "$CHECK_BIND_VERSION"
    update_conf_key "ENABLE_AXFR_CHECK" "$ENABLE_AXFR_CHECK"
    update_conf_key "ENABLE_RECURSION_CHECK" "$ENABLE_RECURSION_CHECK"
    update_conf_key "ENABLE_SOA_SERIAL_CHECK" "$ENABLE_SOA_SERIAL_CHECK"
    
    # Modern
    update_conf_key "ENABLE_EDNS_CHECK" "$ENABLE_EDNS_CHECK"
    update_conf_key "ENABLE_COOKIE_CHECK" "$ENABLE_COOKIE_CHECK"
    update_conf_key "ENABLE_QNAME_CHECK" "$ENABLE_QNAME_CHECK"
    update_conf_key "ENABLE_TLS_CHECK" "$ENABLE_TLS_CHECK"
    update_conf_key "ENABLE_DOT_CHECK" "$ENABLE_DOT_CHECK"
    update_conf_key "ENABLE_DOH_CHECK" "$ENABLE_DOH_CHECK"
    
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

         # 1.1 Validate Domain Format (Col 1)
         # Basic FQDN Regex: alphanumeric, dots, hyphens
         local invalid_domains=$(awk -F';' '!/^#/ && !/^$/ && $1 !~ /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/ {print NR " (" $1 ")"}' "$FILE_DOMAINS")
         if [[ -n "$invalid_domains" ]]; then
             echo -e "${RED}ERRO EM '$FILE_DOMAINS':${NC} Domínios com formato inválido:"
             echo -e "${YELLOW}Linhas: $(echo "$invalid_domains" | tr '\n' ', ' | sed 's/, $//')${NC}"
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

         # 2.1 Check for Duplicate Groups
         local duplicates=$(awk -F';' '!/^#/ && !/^$/ {print $1}' "$FILE_GROUPS" | sort | uniq -d)
         if [[ -n "$duplicates" ]]; then
             echo -e "${RED}ERRO EM '$FILE_GROUPS':${NC}  IDs de Grupo DUPLICADOS encontrados:"
             echo -e "${YELLOW}$(echo "$duplicates" | tr '\n' ',' | sed 's/,$//')${NC}"
             error_count=$((error_count+1))
         fi

         # 2.2 Validate IP Addresses (IPv4/IPv6) in Column 5
         # Extract line number and servers column using awk
         while IFS= read -r line_info; do
             local ln=$(echo "$line_info" | awk '{print $1}')
             local servers=$(echo "$line_info" | cut -d' ' -f2- | tr -d '\r')
             
             # Split servers by comma
             IFS=',' read -ra ADDR <<< "$servers"
             for ip in "${ADDR[@]}"; do
                 # Trim whitespace
                 ip=$(echo "$ip" | xargs)
                 if [[ -z "$ip" ]]; then continue; fi

                 # Check 1: IPv4 Regex
                 if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                     continue
                 fi
                 
                 # Check 2: IPv6 (Simple check for colon)
                 if [[ "$ip" =~ : ]]; then
                     continue
                 fi
                 
                 # Check 3: Hostname/FQDN (Alphanumeric, dots, hyphens)
                 if [[ "$ip" =~ ^[a-zA-Z0-9.-]+$ ]]; then
                     continue
                 fi
                 
                 # If we reached here, it's invalid
                 echo -e "${RED}ERRO EM '$FILE_GROUPS' (Linha $ln):${NC} IP/Host Inválido detectado: '$ip'"
                 error_count=$((error_count+1))
                 # (IPv6 detection is loose here [contains :], but better than nothing for now)
             done
         done < <(awk -F';' '!/^#/ && !/^$/ {print NR, $5}' "$FILE_GROUPS")
         
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

check_dnssec_validation() {
    # Check if server validates DNSSEC (AD flag)
    local ip=$1
    local out
    # Some older digs output "flags: qr rd ra ad" on one line, others different.
    # We grep loosely for "ad" in flags line or "ad;" in header.
    out=$(dig @$ip ietf.org A +dnssec +time=3 +tries=1 2>&1)
    if echo "$out" | grep -q -E ";; flags:.* ad[ ;]"; then return 0; fi
    return 1
}

check_doh_avail() {
    # Check if server responds to DoH (port 443 TCP connect)
    # Using true > /dev/tcp... instead of cat < ... to avoid hang waiting for data
    if timeout 2 bash -c "true > /dev/tcp/$1/443" 2>/dev/null; then return 0; fi
    return 1
}

check_tls_handshake() {
    # Check SSL handshake on port 853
    local ip=$1
    if ! command -v openssl &>/dev/null; then return 2; fi
    echo "Q" | timeout 3 openssl s_client -connect $ip:853 -brief &>/dev/null
    return $?
}

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
    TEMP_CHART_JS="$LOG_OUTPUT_DIR/temp_chart_${SESSION_ID}.js"
    
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
            margin-bottom: 40px;
            padding: 30px;
            border-radius: 16px;
            background: linear-gradient(135deg, #1e293b 0%, #0f172a 100%);
            border: 1px solid var(--border-color);
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
        }
        
        h1 {
            font-size: 1.8rem;
            font-weight: 800;
            margin: 0;
            color: #fff;
            display: flex;
            align-items: center;
            gap: 12px;
            letter-spacing: -0.025em;
        }
        h1 small {
            font-size: 0.8rem;
            color: var(--accent-primary);
            font-weight: 600;
            background: rgba(59, 130, 246, 0.1);
            padding: 4px 10px;
            border-radius: 20px;
            border: 1px solid rgba(59, 130, 246, 0.2);
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }

        h2 {
            font-size: 1.25rem;
            margin-top: 50px;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 12px;
            color: #fff;
            padding-bottom: 15px;
            border-bottom: 1px solid var(--border-color);
        }
        h2::before {
            content: '';
            display: block;
            width: 8px;
            height: 24px;
            background: var(--accent-primary);
            border-radius: 4px;
        }

        /* --- Dashboard Cards --- */
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 12px;
            padding: 24px;
            display: flex;
            flex-direction: column;
            align-items: center;
            text-align: center;
            justify-content: center;
            position: relative;
            overflow: hidden;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
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
            opacity: 0.8;
        }
        .card:hover {
            transform: translateY(-4px);
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.3);
            border-color: var(--card-accent, var(--bg-card-hover));
        }
        .card-num {
            font-size: 2.5rem;
            font-weight: 800;
            line-height: 1;
            margin-bottom: 8px;
            letter-spacing: -0.02em;
        }
        .card-label {
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.1em;
            color: var(--text-secondary);
            font-weight: 600;
        }
        
        /* --- Details & Summary --- */
        details {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 12px;
            margin-bottom: 16px;
            overflow: hidden;
            transition: all 0.2s ease;
        }
        details[open] { border-color: var(--text-secondary); }
        
        details > summary {
            background: var(--bg-card);
            padding: 18px 24px;
            font-size: 1rem;
            font-weight: 600;
            color: var(--text-primary);
            cursor: pointer;
            list-style: none;
            display: flex;
            align-items: center;
            justify-content: space-between;
            user-select: none;
            transition: background 0.2s;
        }
        details > summary:hover { background: var(--bg-card-hover); }
        summary::-webkit-details-marker { display: none; }
        summary::after {
            content: '+'; 
            font-size: 1.4rem; 
            color: var(--text-secondary); 
            font-weight: 300;
            transition: transform 0.2s; 
        }
        details[open] > summary::after { transform: rotate(45deg); }

        /* --- Tables --- */
        .table-responsive {
            width: 100%;
            overflow-x: auto;
            background: #162032; /* Slightly darker than card */
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9rem;
        }
        th, td {
            padding: 16px 20px;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }
        th {
            background: rgba(15, 23, 42, 0.5);
            color: var(--text-secondary);
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.7rem;
            letter-spacing: 0.08em;
            white-space: nowrap;
        }
        td {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            color: #e2e8f0;
        }
        tr:last-child td { border-bottom: none; }
        tr:nth-child(even) { background: rgba(255,255,255,0.015); } /* Zebra Striping */
        tr:hover td { background: rgba(255,255,255,0.03); }
        
        /* --- Badges & Status --- */
        .badge {
            display: inline-flex;
            align-items: center;
            padding: 4px 10px;
            border-radius: 6px;
            font-size: 0.7rem;
            font-weight: 700;
            font-family: system-ui, -apple-system, sans-serif;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            white-space: nowrap;
        }
        
        .status-cell { font-weight: 600; display: flex; align-items: center; gap: 8px; text-decoration: none; }
        .st-ok { color: var(--accent-success); }
        .st-warn { color: var(--accent-warning); }
        .st-fail { color: var(--accent-danger); }
        .st-div { color: var(--accent-divergent); }
        
        .status-ok { background: rgba(16, 185, 129, 0.15); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.2); }
        .status-warning, .status-warn { background: rgba(245, 158, 11, 0.15); color: #fbbf24; border: 1px solid rgba(245, 158, 11, 0.2); }
        .status-fail { background: rgba(239, 68, 68, 0.15); color: #f87171; border: 1px solid rgba(239, 68, 68, 0.2); }
        .status-divergent { background: rgba(217, 70, 239, 0.15); color: #e879f9; border: 1px solid rgba(217, 70, 239, 0.2); }
        .status-neutral, .status-skipped { background: rgba(148, 163, 184, 0.1); color: #94a3b8; border: 1px solid rgba(148, 163, 184, 0.2); }

        /* --- Modal & Logs --- */
        .modal {
            display: none; position: fixed; z-index: 2000; left: 0; top: 0; width: 100%; height: 100%;
            background-color: rgba(0,0,0,0.85); backdrop-filter: blur(8px);
        }
        .modal-content {
            background-color: #0f172a; margin: 4vh auto; padding: 0;
            border: 1px solid var(--border-color); width: 90%; max-width: 1000px;
            border-radius: 16px; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.5);
            display: flex; flex-direction: column; max-height: 92vh;
            overflow: hidden;
        }
        .modal-header {
            padding: 20px 30px; border-bottom: 1px solid var(--border-color); background: #1e293b;
            display: flex; justify-content: space-between; align-items: center;
        }
        .modal-body {
            padding: 0; overflow-y: auto; flex: 1; background: #0b1120;
        }
        pre {
            margin: 0; padding: 25px; color: #cbd5e1; 
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace; 
            font-size: 0.85rem; line-height: 1.7;
            white-space: pre-wrap; word-break: break-all;
        }
        
        /* Modal Info Styles */
        .modal-info-content {
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

generate_executive_summary() {
    # --- STATISTICS ---
    local domain_count=0
    [[ -f "$FILE_DOMAINS" ]] && domain_count=$(grep -vE '^\s*#|^\s*$' "$FILE_DOMAINS" | wc -l)
    
    # Calculate unique servers
    local server_count=0
    [[ -n "${!UNIQUE_SERVERS[@]}" ]] && server_count=${#UNIQUE_SERVERS[@]}
    
    # --- GRADING LOGIC ---
    local grade="A"
    local grade_color="var(--accent-success)"
    local grade_text="EXCELENTE"
    
    # Criteria
    local ratio_fail=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        # Calculate failure percentage (int)
        ratio_fail=$(( (FAILED_TESTS * 100) / TOTAL_TESTS ))
    fi
    local security_issues=$((SEC_REVEALED + SEC_AXFR_RISK + SEC_REC_RISK + DNSSEC_FAIL))
    local stability_issues=$((DIVERGENT_TESTS + AVG_JITTER_HIGH_COUNT)) # Conceptual jitter high count, using Divergence for now
    
    if [[ $ratio_fail -ge 10 ]]; then
        grade="C"; grade_color="var(--accent-danger)"; grade_text="CRÍTICO"
    elif [[ $ratio_fail -gt 0 || $security_issues -gt 0 ]]; then
        grade="B"; grade_color="var(--accent-warning)"; grade_text="ATENÇÃO"
    fi
    
    if [[ $SUCCESS_TESTS -eq 0 && $TOTAL_TESTS -gt 0 ]]; then grade="F"; grade_color="#ef4444"; grade_text="FALHA TOTAL"; fi
    if [[ $TOTAL_TESTS -eq 0 ]]; then grade="-"; grade_color="#64748b"; grade_text="SEM DADOS"; fi

    # --- LATENCY ---
    local avg_lat="-"
    local suffix_lat=""
    if [[ $TOTAL_LATENCY_COUNT -gt 0 ]]; then
        local val=$(awk "BEGIN {printf \"%.0f\", $TOTAL_LATENCY_SUM / $TOTAL_LATENCY_COUNT}")
        [[ "$val" =~ ^[0-9]+$ ]] && { avg_lat="$val"; suffix_lat="<small>ms</small>"; }
    fi

cat > "$TEMP_STATS" << EOF
        <div style="margin-top:20px;"></div>
        
        <!-- EXECUTIVE HERO SECTION -->
        <div style="display:grid; grid-template-columns: 250px 1fr; gap:20px; margin-bottom:30px;">
             <!-- GRADE CARD -->
             <div class="card" style="--card-accent: ${grade_color}; background: linear-gradient(145deg, var(--bg-card) 0%, rgba(255,255,255,0.03) 100%);">
                 <div style="font-size:0.9rem; color:var(--text-secondary); text-transform:uppercase; letter-spacing:0.1em; margin-bottom:10px;">Diagnóstico Geral</div>
                 <div style="font-size:5rem; font-weight:800; line-height:1; color:${grade_color}; text-shadow: 0 4px 20px rgba(0,0,0,0.3);">${grade}</div>
                 <div style="font-size:1.2rem; font-weight:600; color:#fff; margin-top:5px; padding: 4px 12px; border-radius:12px; background:rgba(255,255,255,0.1);">${grade_text}</div>
             </div>
             
             <!-- KPI GRID -->
             <div style="display:grid; grid-template-columns: repeat(3, 1fr); gap:15px;">
                 <div class="card" style="--card-accent: #3b82f6;">
                     <span class="card-num">${server_count}</span>
                     <span class="card-label">Servidores Ativos</span>
                     <span style="font-size:0.75rem; color:var(--text-secondary); margin-top:5px;">Infraestrutura Identificada</span>
                 </div>
                 <div class="card" style="--card-accent: ${avg_lat_suffix:+"#eab308"};">
                     <span class="card-num">${avg_lat}${suffix_lat}</span>
                     <span class="card-label">Latência Média</span>
                     <span style="font-size:0.75rem; color:var(--text-secondary); margin-top:5px;">Performance Global</span>
                 </div>
                  <div class="card" style="--card-accent: ${security_issues:+"var(--accent-danger)"};">
                     <div style="display:flex; align-items:baseline; gap:5px;">
                         <span class="card-num" style="color:${security_issues:+"var(--accent-danger)"};">${security_issues}</span>
                     </div>
                     <span class="card-label">Riscos de Segurança</span>
                     <span style="font-size:0.75rem; color:var(--text-secondary); margin-top:5px;">Versão, AXFR, Recursão</span>
                 </div>
                 
                 <div class="card" style="--card-accent: #10b981;">
                     <span class="card-num">${domain_count}</span>
                     <span class="card-label">Domínios</span>
                 </div>
                  <div class="card" style="--card-accent: #8b5cf6;">
                     <span class="card-num">${CNT_TESTS_ZONE:-0}</span>
                     <span class="card-label">Zonas Testadas</span>
                 </div>
                  <div class="card" style="--card-accent: #ec4899;">
                     <span class="card-num">${CNT_TESTS_REC:-0}</span>
                     <span class="card-label">Registros Testados</span>
                 </div>
             </div>
        </div>
EOF

    if [[ "$ENABLE_CHARTS" == "true" ]]; then
         cat >> "$TEMP_STATS" << EOF
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px; align-items: start; margin-bottom: 40px;">
             <!-- Overview Chart Container -->
             <div class="card" style="min-height: 350px; --card-accent: var(--accent-primary); padding:20px;">
                 <h3 style="margin-top:0; color:var(--text-secondary); font-size:0.9rem; text-transform:uppercase; letter-spacing:0.05em; border:none; padding:0;">Visão Geral de Execução</h3>
                 <div style="position: relative; height: 300px; width: 100%; margin-top:15px;">
                    <canvas id="chartOverview"></canvas>
                 </div>
             </div>
             <!-- Latency Chart Container -->
             <div class="card" style="min-height: 350px; --card-accent: var(--accent-warning); padding:20px;">
                 <h3 style="margin-top:0; color:var(--text-secondary); font-size:0.9rem; text-transform:uppercase; letter-spacing:0.05em; border:none; padding:0;">Top Latência (Médias)</h3>
                 <div style="position: relative; height: 300px; width: 100%; margin-top:15px;">
                    <canvas id="chartLatency"></canvas>
                 </div>
             </div>
        </div>
EOF
    fi
}

generate_health_map() {
    cat > "$TEMP_HEALTH_MAP" << EOF
    <div style="margin-top: 40px; margin-bottom: 40px;">
        <h2>🗺️ Mapa de Saúde DNS</h2>
        <div class="table-responsive">
            <table>
                <thead>
                    <tr>
                        <th>Grupo DNS</th>
                        <th>Latência Média</th>
                        <th>Falhas / Total</th>
                        <th>Status Geral</th>
                    </tr>
                </thead>
                <tbody>
EOF
    for grp in "${!ACTIVE_GROUPS[@]}"; do
        local g_rtt_sum=0
        local g_rtt_cnt=0
        for ip in ${DNS_GROUPS[$grp]}; do
            if [[ -n "${IP_RTT_RAW[$ip]}" ]]; then
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
        
        # Status Logic
        local status_html="<span class='badge badge-type' style='color:#10b981; border-color:#10b981; background:rgba(16, 185, 129, 0.1);'>HEALTHY</span>"
        if [[ $g_fail_cnt -gt 0 ]]; then
             status_html="<span class='badge badge-type' style='color:#ef4444; border-color:#ef4444; background:rgba(239, 68, 68, 0.1);'>ISSUES</span>"
        elif [[ "$g_avg" != "N/A" ]]; then
             # Check latency threshold
             local lat_val=${g_avg%ms}
             lat_val=${lat_val%.*} # int
             if [[ $lat_val -gt $LATENCY_WARNING_THRESHOLD ]]; then
                 status_html="<span class='badge badge-type' style='color:#f59e0b; border-color:#f59e0b; background:rgba(245, 158, 11, 0.1);'>SLOW</span>"
             fi
        fi
        
        echo "<tr><td><strong style='color:var(--text-primary);'>$grp</strong></td><td>$g_avg</td><td>${g_fail_cnt} / ${g_total_cnt}</td><td>$status_html</td></tr>" >> "$TEMP_HEALTH_MAP"
    done

    cat >> "$TEMP_HEALTH_MAP" << EOF
                </tbody>
            </table>
        </div>
    </div>
EOF
}

generate_security_cards() {
    # Output Security Cards HTML (without wrapping details, to be used in assembly)
    echo "    <h2>🛡️ Postura de Segurança</h2>"
    echo "    <div class=\"dashboard\" style=\"grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); margin-bottom: 20px;\">"
    
    # Card 1: Version Privacy
    echo "        <div class=\"card\" style=\"--card-accent: var(--accent-primary); cursor:pointer;\" onclick=\"showInfoModal('VERSION PRIVACY', 'Verifica se o servidor revela sua versão de software (BIND, etc).')\">"
    echo "            <div style=\"font-size:1.5rem; margin-bottom:5px;\">🕵️</div>"
    echo "            <span class=\"card-label\">Version Privacy</span>"
    echo "            <div style=\"margin-top:10px; font-size:0.95rem;\">"
    echo "                 <span style=\"color:var(--accent-success);\">Hide:</span> <strong>${SEC_HIDDEN}</strong> <span style=\"color:#444\">|</span>"
    echo "                 <span style=\"color:var(--accent-danger);\">Rev:</span> <strong>${SEC_REVEALED}</strong>"
    echo "            </div>"
    echo "        </div>"
    
    # Card 2: Zone Transfer
    echo "        <div class=\"card\" style=\"--card-accent: var(--accent-warning); cursor:pointer;\" onclick=\"showInfoModal('ZONE TRANSFER (AXFR)', 'Tenta realizar uma transferência de zona completa (AXFR) do domínio raiz.')\">"
    echo "            <div style=\"font-size:1.5rem; margin-bottom:5px;\">📂</div>"
    echo "            <span class=\"card-label\">Zone Transfer</span>"
    echo "            <div style=\"margin-top:10px; font-size:0.95rem;\">"
    echo "                 <span style=\"color:var(--accent-success);\">Deny:</span> <strong>${SEC_AXFR_OK}</strong> <span style=\"color:#444\">|</span>"
    echo "                 <span style=\"color:var(--accent-danger);\">Allow:</span> <strong>${SEC_AXFR_RISK}</strong>"
    echo "            </div>"
    echo "        </div>"
    
    # Card 3: Recursion
    echo "        <div class=\"card\" style=\"--card-accent: var(--accent-danger); cursor:pointer;\" onclick=\"showInfoModal('RECURSION', 'Verifica se o servidor aceita consultas recursivas para domínios externos.')\">"
    echo "            <div style=\"font-size:1.5rem; margin-bottom:5px;\">🔄</div>"
    echo "            <span class=\"card-label\">Recursion</span>"
    echo "            <div style=\"margin-top:10px; font-size:0.95rem;\">"
    echo "                 <span style=\"color:var(--accent-success);\">Close:</span> <strong>${SEC_REC_OK}</strong> <span style=\"color:#444\">|</span>"
    echo "                 <span style=\"color:var(--accent-danger);\">Open:</span> <strong>${SEC_REC_RISK}</strong>"
    echo "            </div>"
    echo "        </div>"
    
    # Card 4: DNSSEC
    echo "        <div class=\"card\" style=\"--card-accent: #8b5cf6; cursor:pointer;\" onclick=\"showInfoModal('DNSSEC', 'Validação da cadeia de confiança DNSSEC (RRSIG).')\">"
    echo "            <div style=\"font-size:1.5rem; margin-bottom:5px;\">🔐</div>"
    echo "            <span class=\"card-label\">DNSSEC Status</span>"
    echo "            <div style=\"margin-top:10px; font-size:0.95rem;\">"
    echo "                 <span style=\"color:var(--accent-success);\">Valid:</span> <strong>${DNSSEC_SUCCESS}</strong> <span style=\"color:#444\">|</span>"
    echo "                 <span style=\"color:var(--accent-danger);\">Fail:</span> <strong>${DNSSEC_FAIL}</strong>"
    echo "            </div>"
    echo "        </div>"
    
    # Card 5: Modern Standards
    echo "        <div class=\"card\" style=\"--card-accent: var(--accent-primary); cursor:pointer;\" onclick=\"showInfoModal('MODERN STANDARDS', 'Suporte a EDNS0, Cookies, QNAME Minimization e Criptografia.')\">"
    echo "            <div style=\"font-size:1.5rem; margin-bottom:5px;\">🛡️</div>"
    echo "            <span class=\"card-label\">Modern Features</span>"
    echo "            <div style=\"margin-top:10px; font-size:0.85rem; display:grid; grid-template-columns: 1fr 1fr; gap:5px;\">"
    echo "                 <div>EDNS: <strong style=\"color:var(--accent-success)\">${EDNS_SUCCESS}</strong></div>"
    echo "                 <div>DoT: <strong style=\"color:var(--accent-success)\">${DOT_SUCCESS}</strong></div>"
    echo "                 <div>QNAME: <strong style=\"color:var(--accent-success)\">${QNAME_SUCCESS}</strong></div>"
    echo "                 <div>DoH: <strong style=\"color:var(--accent-success)\">${DOH_SUCCESS}</strong></div>"
    echo "            </div>"
    echo "        </div>"
    
    echo "    </div>"
}

generate_object_summary() {
    # Part 1: Charts Card (Only if ENABLE_CHARTS is true)
    if [[ "$ENABLE_CHARTS" == "true" ]]; then
        cat >> "$LOG_OUTPUT_DIR/temp_obj_summary_${SESSION_ID}.html" << EOF
                <div class="card" style="margin-bottom: 20px; --card-accent: #8b5cf6; cursor: pointer;" onclick="this.nextElementSibling.open = !this.nextElementSibling.open">
                     <h3 style="margin-top:0; font-size:1rem; margin-bottom:15px;">📊 Estatísticas de Serviços</h3>
                     <div style="position: relative; height: 300px; width: 100%;">
                        <canvas id="chartServices"></canvas>
                     </div>
                     <div class="summary-details">
                        <p style="margin:0; font-size:0.9rem; color:var(--text-secondary);">
                            Distribuição de respostas DNS (NOERROR, NXDOMAIN, etc.)
                        </p>
                     </div>
                </div>
EOF
    fi

    # Part 2: Table Header
    cat >> "$LOG_OUTPUT_DIR/temp_obj_summary_${SESSION_ID}.html" << EOF
        <details class="section-details" style="margin-bottom: 30px;">
            <summary>📋  Tabela Detalhada de Serviços</summary>
            <div style="padding: 15px;">
                <div class="table-responsive">
                    <table>
                        <thead>
                            <tr>
                                <th>Grupo</th>
                                <th>Alvo</th>
                                <th>Servidor</th>
                                <th>Funcionalidades (Badges)</th>
                            </tr>
                        </thead>
                        <tbody>
EOF

    # Part 3: Inject Rows (Bash Logic)
    if [[ -s "$LOG_OUTPUT_DIR/temp_svc_table_${SESSION_ID}.html" ]]; then
        cat "$LOG_OUTPUT_DIR/temp_svc_table_${SESSION_ID}.html" >> "$LOG_OUTPUT_DIR/temp_obj_summary_${SESSION_ID}.html"
    else
        echo "<tr><td colspan='4' style='text-align:center; color:#888;'>Nenhum dado de serviço coletado.</td></tr>" >> "$LOG_OUTPUT_DIR/temp_obj_summary_${SESSION_ID}.html"
    fi

    # Part 4: Table Footer
    cat >> "$LOG_OUTPUT_DIR/temp_obj_summary_${SESSION_ID}.html" << EOF
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
                        <tr><td>Valida Conectividade</td><td>${VALIDATE_CONNECTIVITY}</td><td>Testa porta 53 antes do envio da query.</td></tr>
                        <tr><td>Check BIND Version</td><td>${CHECK_BIND_VERSION}</td><td>Consulta caos class para versão do BIND.</td></tr>
                        <tr><td>Modern Features</td><td>E=${ENABLE_EDNS_CHECK} C=${ENABLE_COOKIE_CHECK} Q=${ENABLE_QNAME_CHECK}</td><td>EDNS0, Cookie e QNAME Minimization.</td></tr>
                        <tr><td>Encrypted DNS</td><td>TLS=${ENABLE_TLS_CHECK} DoT=${ENABLE_DOT_CHECK} DoH=${ENABLE_DOH_CHECK}</td><td>Suporte a transporte criptografado.</td></tr>
                        <tr><td>Ping Enabled</td><td>${ENABLE_PING}</td><td>Verificação de latência ICMP (Count: ${PING_COUNT}, Timeout: ${PING_TIMEOUT}s).</td></tr>
                        <tr><td>Traceroute</td><td>${ENABLE_TRACE}</td><td>Mapeamento de rota (Hops: ${TRACE_MAX_HOPS}).</td></tr>
                        <tr><td>TCP Check (+tcp)</td><td>${ENABLE_TCP_CHECK}</td><td>Obrigatoriedade de suporte a DNS via TCP.</td></tr>
                        <tr><td>DNSSEC Check (+dnssec)</td><td>${ENABLE_DNSSEC_CHECK}</td><td>Validação da cadeia de confiança DNSSEC.</td></tr>

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
    # Prepare Arrays from Memory
    local lat_js=""
    local count_lat=0
    # Create temp file for sorting latency
    local tmp_lat_sort="$LOG_OUTPUT_DIR/lat_sort.tmp"
    > "$tmp_lat_sort"
    
    for ip in "${!STATS_SERVER_PING_AVG[@]}"; do
        local val=${STATS_SERVER_PING_AVG[$ip]}
        # Handle decimal comma/dot
        val=$(echo "$val" | tr ',' '.')
        if [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
             echo "$ip $val" >> "$tmp_lat_sort"
        fi
    done
    
    # Sort by latency desc (Top 10)
    sort -k2 -nr "$tmp_lat_sort" | head -n 12 | while read -r srv lat; do
         lat_js+="latencyLabels.push('$srv'); latencyData.push($lat);"
    done
    rm -f "$tmp_lat_sort"

    # Prepare Traceroute Data
    local trace_js=""
    if [[ -f "$TEMP_TRACE" ]]; then
        while IFS=':' read -r ip hops; do
             trace_js+="traceLabels.push('$ip'); traceData.push($hops);"
        done < "$TEMP_TRACE"
    fi

    cat << EOF
    <script>
        // Chart Configuration
        Chart.defaults.color = '#94a3b8';
        Chart.defaults.borderColor = '#334155';
        Chart.defaults.font.family = "system-ui, -apple-system, sans-serif";

        const ctxOverview = document.getElementById('chartOverview');
        const ctxLatency = document.getElementById('chartLatency');

        // 1. OVERVIEW CHART (Global Counters)
        if (ctxOverview) {
            new Chart(ctxOverview, {
                type: 'doughnut',
                data: {
                    labels: ['Sucesso ($SUCCESS_TESTS)', 'Falhas ($FAILED_TESTS)', 'Divergências ($DIVERGENT_TESTS)'],
                    datasets: [{
                        data: [$SUCCESS_TESTS, $FAILED_TESTS, $DIVERGENT_TESTS],
                        backgroundColor: ['#10b981', '#ef4444', '#d946ef'],
                        borderWidth: 0,
                        hoverOffset: 4
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    cutout: '65%',
                    plugins: {
                        legend: { position: 'right', labels: { color: '#cbd5e1', font: { size: 12 } } },
                        title: { display: false }
                    }
                }
            });
        }

        // 2. LATENCY CHART (Top 10 Slowest or All)
        const latencyLabels = [];
        const latencyData = [];
        const traceLabels = [];
        const traceData = [];
        
        $lat_js
        $trace_js

        const colorPalette = ['#3b82f6', '#ef4444', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16'];

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
    local p_noerror=0; [[ $TOTAL_DNS_QUERY_COUNT -gt 0 ]] && p_noerror=$(( (CNT_NOERROR * 100) / TOTAL_DNS_QUERY_COUNT ))
    local p_noanswer=0; [[ $TOTAL_DNS_QUERY_COUNT -gt 0 ]] && p_noanswer=$(( (CNT_NOANSWER * 100) / TOTAL_DNS_QUERY_COUNT ))
    local p_nxdomain=0; [[ $TOTAL_DNS_QUERY_COUNT -gt 0 ]] && p_nxdomain=$(( (CNT_NXDOMAIN * 100) / TOTAL_DNS_QUERY_COUNT ))
    local p_servfail=0; [[ $TOTAL_DNS_QUERY_COUNT -gt 0 ]] && p_servfail=$(( (CNT_SERVFAIL * 100) / TOTAL_DNS_QUERY_COUNT ))
    local p_refused=0; [[ $TOTAL_DNS_QUERY_COUNT -gt 0 ]] && p_refused=$(( (CNT_REFUSED * 100) / TOTAL_DNS_QUERY_COUNT ))
    local p_timeout=0; [[ $TOTAL_DNS_QUERY_COUNT -gt 0 ]] && p_timeout=$(( (CNT_TIMEOUT * 100) / TOTAL_DNS_QUERY_COUNT ))
    local p_neterror=0; [[ $TOTAL_DNS_QUERY_COUNT -gt 0 ]] && p_neterror=$(( (CNT_NETWORK_ERROR * 100) / TOTAL_DNS_QUERY_COUNT ))
    local p_other=0; [[ $TOTAL_DNS_QUERY_COUNT -gt 0 ]] && p_other=$(( (CNT_OTHER_ERROR * 100) / TOTAL_DNS_QUERY_COUNT ))

    cat >> "$TEMP_STATS" << EOF
    <div style="margin-top: 30px; margin-bottom: 20px;">
        <h3 style="color:var(--text-primary); border-bottom: 2px solid var(--border-color); padding-bottom: 10px; font-size:1.1rem;">📊 Detalhamento de Respostas e Grupos</h3>
        
        <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap:15px; margin-top:15px;">
            <div class="card" style="--card-accent: #10b981; padding:15px; text-align:center; cursor:pointer;" onclick="showInfoModal('NOERROR', 'O servidor processou a consulta com sucesso e retornou uma resposta válida (com ou sem dados).<br><br><b>Significado:</b> Operação normal.<br>Se a contagem for alta, indica saúde do sistema.')">
                <div style="font-size:1.5rem; font-weight:bold;">${CNT_NOERROR}</div>
                <div style="font-size:0.8rem; color:var(--text-secondary);">NOERROR</div>
                <div style="font-size:0.7rem; color:#10b981;">${p_noerror}%</div>
            </div>
             <div class="card" style="--card-accent: #64748b; padding:15px; text-align:center; cursor:pointer;" onclick="showInfoModal('NOANSWER', 'O servidor respondeu com status NOERROR, mas não retornou a seção ANSWER.<br><br><b>Significado:</b> O nome existe, mas não há registro do tipo solicitado (ex: pediu AAAA mas só tem A).')">
                <div style="font-size:1.5rem; font-weight:bold;">${CNT_NOANSWER}</div>
                <div style="font-size:0.8rem; color:var(--text-secondary);">NOANSWER</div>
                <div style="font-size:0.7rem; color:var(--text-secondary);">${p_noanswer}%</div>
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
                <div style="font-size:0.7rem; color:var(--text-secondary);">${p_neterror}%</div>
            </div>
             <div class="card" style="--card-accent: #64748b; padding:15px; text-align:center; cursor:pointer;" onclick="showInfoModal('OTHER', 'Outros erros não classificados.<br><br><b>Significado:</b> Códigos de retorno raros ou erros de parsing.')">
                <div style="font-size:1.5rem; font-weight:bold;">${CNT_OTHER_ERROR}</div>
                <div style="font-size:0.8rem; color:var(--text-secondary);">OTHER</div>
                 <div style="font-size:0.7rem; color:var(--text-secondary);">${p_other}%</div>
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



generate_html_report_v2() {
    local target_file="$HTML_FILE"
    
    # --- PRE-CALCULATIONS & SUMMARY STATS ---
    local total_exec=$(( CNT_TESTS_SRV + CNT_TESTS_ZONE + CNT_TESTS_REC ))
    local fail_ratio=0
    [[ $total_exec -gt 0 ]] && fail_ratio=$(( (FAILED_TESTS * 100) / total_exec ))
    
    local grade="A"
    local grade_color="#10b981" # Green
    if [[ $fail_ratio -ge 10 ]]; then grade="C"; grade_color="#ef4444"; 
    elif [[ $fail_ratio -gt 0 || $((SEC_REVEALED+SEC_AXFR_RISK)) -gt 0 ]]; then grade="B"; grade_color="#f59e0b"; fi
    
    # Scope Calculations (Parity with Terminal)
    local srv_count=${#UNIQUE_SERVERS[@]}
    local zone_count=0
    local rec_count=0
    if [[ -f "$FILE_DOMAINS" ]]; then
        zone_count=$(grep -vE '^\s*#|^\s*$' "$FILE_DOMAINS" | wc -l)
        rec_count=$(awk -F';' '!/^#/ && !/^\s*$/ { 
            n_recs = split($4, a, ",");
            n_extras = 0;
            gsub(/[[:space:]]/, "", $5);
            if (length($5) > 0) n_extras = split($5, b, ",");
            count += n_recs * (1 + n_extras) 
        } END { print count }' "$FILE_DOMAINS")
    fi
     [[ -z "$rec_count" ]] && rec_count=0
    
    # Global Latency Calc
    local glob_lat_sum=0
    local glob_lat_cnt=0
    for ip in "${!STATS_SERVER_PING_AVG[@]}"; do
        local val=${STATS_SERVER_PING_AVG[$ip]}
        val=${val%%.*} # Integer part only for math
        if [[ "$val" =~ ^[0-9]+$ ]] && [[ "$val" -gt 0 ]]; then
            glob_lat_sum=$((glob_lat_sum + val))
            glob_lat_cnt=$((glob_lat_cnt + 1))
        fi
    done
    local glob_lat_avg=0
    [[ $glob_lat_cnt -gt 0 ]] && glob_lat_avg=$((glob_lat_sum / glob_lat_cnt))

    # Prepare JSON Strings for Charts
    local json_labels=""
    local json_data=""
    
    local tmp_sort="$LOG_OUTPUT_DIR/lat_sort.tmp"
    > "$tmp_sort"
    for ip in "${!STATS_SERVER_PING_AVG[@]}"; do
        local val=${STATS_SERVER_PING_AVG[$ip]}
        val=$(echo "$val" | tr ',' '.')
        if [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
             echo "$ip $val" >> "$tmp_sort"
        fi
    done
    sort -k2 -nr "$tmp_sort" | head -n 15 | while read -r srv lat; do
          json_labels+="\"$srv\","
          json_data+="$lat,"
    done
    rm -f "$tmp_sort"
    json_labels="[${json_labels%,}]"
    json_data="[${json_data%,}]"

    # --- BUILD SERVER ROWS ---
    local server_rows=""
    local sorted_groups=$(echo "${!DNS_GROUPS[@]}" | tr ' ' '\n' | sort)
    for grp in $sorted_groups; do
        # Filter Logic
        if [[ "$ONLY_TEST_ACTIVE_GROUPS" == "true" ]]; then
             # Sanitize key for lookup (remove potential hidden chars if any, though sorted_groups should be clean)
             local clean_key=$(echo "$grp" | tr -d '[:space:]\r\n\t')
             if [[ -z "${ACTIVE_GROUPS_CALC[$clean_key]}" ]]; then continue; fi
        fi
        
        local g_total=0; local g_avg_lat=0; local g_lat_sum=0
        for ip in ${DNS_GROUPS[$grp]}; do
             g_total=$((g_total+1))
             local lat=${STATS_SERVER_PING_AVG[$ip]%%.*} # Int
             [[ "$lat" =~ ^[0-9]+$ ]] && g_lat_sum=$((g_lat_sum + lat))
        done
        [[ $g_total -gt 0 ]] && g_avg_lat=$((g_lat_sum / g_total))
        
        server_rows+="<details style='margin-bottom:15px; border:1px solid #334155; border-radius:8px; overflow:hidden;'>
            <summary style='background:#1e293b; padding:12px 15px; cursor:pointer; font-weight:600; color:#fff; display:flex; justify-content:space-between;'>
                <span>📂 $grp <span style='font-size:0.8em; opacity:0.6; font-weight:400;'>($g_total servers)</span></span>
                <span style='font-size:0.8em; color:#94a3b8;'>Avg Lat: ${g_avg_lat}ms</span>
            </summary>
            <table style='width:100%; border-collapse:collapse;'>
            <thead style='background:#0f172a;'>
               <tr><th style='width:25%'>Servidor</th><th style='width:20%'>Latência</th><th>Config & Features</th><th style='width:15%; text-align:right'>Detalhamento</th></tr>
            </thead>
            <tbody>"
            
        for ip in ${DNS_GROUPS[$grp]}; do
            local lat="${STATS_SERVER_PING_AVG[$ip]:-0}"
            local loss="${STATS_SERVER_PING_LOSS[$ip]:-0}"
            local lat_class="bg-ok"
            if (( $(echo "$lat > 100" | bc -l 2>/dev/null) )); then lat_class="bg-warn"; fi
            if [[ "$loss" != "0%" && "$loss" != "0" ]]; then lat_class="bg-fail"; fi
            
            local caps=""
            [[ "${STATS_SERVER_DNSSEC[$ip]}" == "OK" ]] && caps+="<span class='badge ok-bg' style='color:#a855f7;'>DNSSEC</span>"
            [[ "${STATS_SERVER_DOH[$ip]}" == "OK" ]] && caps+="<span class='badge bg-ok'>DoH</span>"
            [[ "${STATS_SERVER_TLS[$ip]}" == "OK" ]] && caps+="<span class='badge bg-ok'>TLS</span>"
            [[ "${STATS_SERVER_COOKIE[$ip]}" == "OK" ]] && caps+="<span class='badge bg-ok'>COOKIE</span>"
            [[ "${STATS_SERVER_EDNS[$ip]}" == "OK" ]] && caps+="<span class='badge bg-ok'>EDNS</span>"
            
            local ver_st="${STATS_SERVER_VERSION[$ip]}"
            local rec_st="${STATS_SERVER_RECURSION[$ip]}"
            local ver_cls="bg-neutral"; [[ "$ver_st" == "HIDDEN" ]] && ver_cls="bg-ok" || ver_cls="bg-fail"
            local rec_cls="bg-neutral"; [[ "$rec_st" == "CLOSED" ]] && rec_cls="bg-ok" || rec_cls="bg-fail"

            local safe_ip=${ip//./_}
            server_rows+="<tr>
                <td><div style='font-weight:bold; color:#fff'>$ip</div></td>
                <td><span class='badge $lat_class'>${lat}ms</span> <div style='font-size:0.7em; color:#64748b'>Loss: $loss</div></td>
                <td><div style='margin-bottom:4px;'><span class='badge $ver_cls'>VER: $ver_st</span> <span class='badge $rec_cls'>REC: $rec_st</span></div><div style='display:flex; gap:5px; flex-wrap:wrap; opacity:0.8'>$caps</div></td>
                <td style='text-align:right'>
                    <button class='btn-tech' onclick=\"showModal('ver_${safe_ip}', 'BIND ($ip)')\">VER</button>
                    <button class='btn-tech' onclick=\"showModal('rec_${safe_ip}', 'REC ($ip)')\">REC</button>
                </td>
            </tr>"
        done
        server_rows+="</tbody></table></details>"
    done

    # --- BUILD ZONE ROWS ---
    local zone_rows=""
    if [[ -f "$FILE_DOMAINS" ]]; then
        while IFS=';' read -r domain groups _ _ _; do
             [[ "$domain" =~ ^# || -z "$domain" ]] && continue
             domain=$(echo "$domain" | xargs)
             
             # Consensus SOA Calc
             local -A soa_counts; local most_frequent_soa=""; local max_count=0
             IFS=',' read -ra grp_list <<< "$groups"
             for grp in "${grp_list[@]}"; do
                  for srv in ${DNS_GROUPS[$grp]}; do
                       local s="${STATS_ZONE_SOA[$domain|$grp|$srv]}"
                       [[ -n "$s" && "$s" != "N/A" ]] && soa_counts["$s"]=$((soa_counts["$s"]+1))
                  done
             done
             for s in "${!soa_counts[@]}"; do
                 if (( soa_counts["$s"] > max_count )); then max_count=${soa_counts["$s"]}; most_frequent_soa="$s"; fi
             done
             unset soa_counts
             
             zone_rows+="<details style='margin-bottom:15px; border:1px solid #334155; border-radius:8px; overflow:hidden;'>
                <summary style='background:#1e293b; padding:12px 15px; cursor:pointer; font-weight:600; color:#fff;'>🌍 $domain <span style='font-size:0.8em; color:#94a3b8; font-weight:400; margin-left:10px;'>Consensus SOA: $most_frequent_soa</span></summary>
                <table style='width:100%'>
                <thead style='background:#0f172a'><tr><th>Grupo</th><th>Servidor</th><th>SOA Serial</th><th>AXFR Policy</th><th>Logs</th></tr></thead>
                <tbody>"

             for grp in "${grp_list[@]}"; do
                  for srv in ${DNS_GROUPS[$grp]}; do
                       local soa="${STATS_ZONE_SOA[$domain|$grp|$srv]}"
                       local axfr="${STATS_ZONE_AXFR[$domain|$grp|$srv]}"
                       local soa_cls="bg-neutral"; [[ "$soa" == "$most_frequent_soa" ]] && soa_cls="bg-ok" || soa_cls="bg-fail"
                       [[ "$most_frequent_soa" == "" ]] && soa_cls="bg-warn" 
                       local axfr_cls="bg-ok"; [[ "$axfr" != "DENIED" && "$axfr" != "REFUSED" ]] && axfr_cls="bg-fail"
                       
                       local safe_dom=${domain//./_}; local safe_srv=${srv//./_}
                       zone_rows+="<tr>
                            <td>$grp</td><td>$srv</td>
                            <td style='font-family:monospace'><span class='badge $soa_cls'>$soa</span></td>
                            <td><span class='badge $axfr_cls'>$axfr</span></td>
                            <td><button class='btn-tech' onclick=\"showModal('soa_${safe_dom}_${safe_srv}','SOA $domain @ $srv')\">SOA</button> <button class='btn-tech' onclick=\"showModal('axfr_${safe_dom}_${safe_srv}','AXFR $domain @ $srv')\">AXFR</button></td>
                        </tr>"
                  done
             done
             zone_rows+="</tbody></table></details>"
        done < "$FILE_DOMAINS"
    fi

    # --- BUILD RECORD ROWS ---
    local record_rows=""
    local tmp_rec_keys="$LOG_OUTPUT_DIR/rec_keys.tmp"
    for key in "${!STATS_RECORD_RES[@]}"; do echo "$key" >> "$tmp_rec_keys"; done
    if [[ -s "$tmp_rec_keys" ]]; then
        sort "$tmp_rec_keys" > "$tmp_rec_keys.sorted"
        local cur_zone=""; local cur_type=""
        while read -r key; do
             IFS='|' read -r r_dom r_type r_grp r_srv <<< "$key"
             if [[ "$r_dom" != "$cur_zone" ]]; then
                 [[ -n "$cur_zone" ]] && record_rows+="</tbody></table></details></details>"
                 cur_zone="$r_dom"; cur_type=""; 
                 record_rows+="<details style='margin-bottom:10px; border:1px solid #334155; border-radius:8px;'><summary style='background:#1e293b; padding:10px 15px; cursor:pointer; font-weight:700; color:#fff;'>📝 $cur_zone</summary>"
             fi
             if [[ "$r_type" != "$cur_type" ]]; then
                 [[ -n "$cur_type" ]] && record_rows+="</tbody></table></details>"
                 cur_type="$r_type"
                 record_rows+="<div style='padding:5px 15px;'><details style='margin-bottom:5px; border:1px solid #475569; border-radius:6px;'><summary style='background:#334155; padding:5px 10px; cursor:pointer; font-size:0.9em;'>Tipo: <strong style='color:#facc15'>$cur_type</strong></summary><table style='width:100%; font-size:0.9em;'><thead><tr><th>Server</th><th>Status</th><th>Resposta</th><th>Latência</th><th>Log</th></tr></thead><tbody>"
             fi

             local r_status="${STATS_RECORD_RES[$key]}"; local r_ans="${STATS_RECORD_ANSWER[$key]}"; local r_lat="${STATS_RECORD_LATENCY[$key]}"
             local r_cons="${STATS_RECORD_CONSISTENCY[$r_dom|$r_type|$r_grp]}"; local st_cls="bg-neutral"
             [[ "$r_status" == "NOERROR" ]] && st_cls="bg-ok"; [[ "$r_status" == "NXDOMAIN" ]] && st_cls="bg-warn"; [[ "$r_status" != "NOERROR" && "$r_status" != "NXDOMAIN" ]] && st_cls="bg-fail"
             local cons_badge=""; [[ "$r_cons" == "DIVERGENT" ]] && cons_badge="<span class='badge bg-fail'>DIV</span>"
             local safe_dom=${r_dom//./_}; local safe_srv=${r_srv//./_}
             
             record_rows+="<tr><td>$r_srv <span style='font-size:0.8em;opacity:0.6'>($r_grp)</span> $cons_badge</td><td><span class='badge $st_cls'>$r_status</span></td><td><div style='max-height:40px; overflow-y:auto; font-family:monospace; font-size:0.8em; white-space:pre-wrap;'>$r_ans</div></td><td>${r_lat}ms</td><td><button class='btn-tech' onclick=\"showModal('rec_${safe_dom}_${r_type}_${safe_srv}','DIG $r_dom ($r_type)')\">LOG</button></td></tr>"
        done < "$tmp_rec_keys.sorted"
        [[ -n "$cur_type" ]] && record_rows+="</tbody></table></details></div>"
        [[ -n "$cur_zone" ]] && record_rows+="</details>"
        rm -f "$tmp_rec_keys" "$tmp_rec_keys.sorted"
    fi
    
    local help_content=$(grep -A 999 "show_help() {" "$0" | sed -n '/^show_help() {/,/^}/p' | sed '1d;$d' | sed 's/&/\\&amp;/g; s/</\\&lt;/g; s/>/\\&gt;/g')

    # --- HTML HEADER & CSS ---
    cat > "$target_file" << EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Relatório DNS v${SCRIPT_VERSION}</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root { --bg-body: #0f172a; --bg-card: #1e293b; --text-main: #f8fafc; --text-muted: #94a3b8; --border: #334155; --accent: #3b82f6; }
        * { box-sizing: border-box; margin: 0; padding: 0; outline: none; }
        body { font-family: 'Inter', system-ui, -apple-system, sans-serif; background: var(--bg-body); color: var(--text-main); font-size: 14px; line-height: 1.5; height: 100vh; display: flex; overflow: hidden; }
        aside { width: 260px; background: #020617; border-right: 1px solid var(--border); display: flex; flex-direction: column; padding: 20px; flex-shrink: 0; }
        .logo { font-size: 1.2rem; font-weight: 700; color: #fff; margin-bottom: 30px; display: flex; align-items: center; gap: 10px; }
        .nav-item { padding: 12px 15px; margin-bottom: 5px; color: var(--text-muted); cursor: pointer; border-radius: 8px; transition: all 0.2s; font-weight: 500; display: flex; align-items: center; gap: 10px; }
        .nav-item:hover { background: rgba(255,255,255,0.05); color: #fff; }
        .nav-item.active { background: var(--accent); color: #fff; }
        main { flex: 1; overflow-y: auto; padding: 30px; position: relative; }
        .page-header { display: flex; justify-content: space-between; align-items: end; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 1px solid var(--border); }
        h1 { font-size: 1.8rem; font-weight: 700; margin-bottom: 5px; }
        .subtitle { color: var(--text-muted); }
        .dashboard-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .card { background: var(--bg-card); border: 1px solid var(--border); border-radius: 12px; padding: 20px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); }
        .card-header { font-size: 0.9rem; font-weight: 700; color: #fff; text-transform: uppercase; border-bottom: 1px solid var(--border); padding-bottom: 10px; margin-bottom: 15px; }
        .stat-row { display: flex; justify-content: space-between; margin-bottom: 8px; font-size: 0.9rem; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 4px; }
        .stat-label { color: var(--text-muted); display:flex; gap:8px; align-items:center;}
        .stat-val { font-weight: 600; color: #fff; }
        .text-ok { color: #34d399; } .text-fail { color: #f87171; } .text-warn { color: #fbbf24; }
        
        table { width: 100%; border-collapse: collapse; }
        th { text-align: left; padding: 12px 15px; background: rgba(0,0,0,0.2); color: var(--text-muted); font-weight: 600; border-bottom: 1px solid var(--border); }
        td { padding: 12px 15px; border-bottom: 1px solid var(--border); color: var(--text-main); vertical-align: middle; }
        tr:hover td { background: rgba(255,255,255,0.02); }
        .badge { display: inline-flex; padding: 4px 10px; border-radius: 20px; font-size: 0.75rem; font-weight: 600; align-items: center; gap: 5px; line-height: 1; }
        .bg-ok { background: rgba(16, 185, 129, 0.15); color: #34d399; }
        .bg-fail { background: rgba(239, 68, 68, 0.15); color: #f87171; }
        .bg-warn { background: rgba(245, 158, 11, 0.15); color: #fbbf24; }
        .bg-neutral { background: rgba(148, 163, 184, 0.15); color: #cbd5e1; }
        .btn-tech { background: transparent; border: 1px solid var(--border); color: var(--accent); padding: 4px 8px; border-radius: 4px; cursor: pointer; font-size: 0.75rem; text-decoration: none; display: inline-block; }
        .btn-tech:hover { background: var(--accent); color: white; border-color: var(--accent); }
        .tab-content { display: none; } .tab-content.active { display: block; }
        .modal { display: none; position: fixed; z-index: 999; left: 0; top: 0; width: 100%; height: 100%; background-color: rgba(0,0,0,0.8); backdrop-filter: blur(4px); }
        .modal-content { background-color: #1e293b; margin: 5vh auto; width: 90%; max-width: 1000px; height: 90vh; border-radius: 12px; border: 1px solid var(--border); display: flex; flex-direction: column; overflow: hidden; }
        .modal-header { padding: 15px 20px; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; background: #0f172a; }
        .modal-body { flex: 1; padding: 0; overflow-y: auto; background: #0b1120; }
        .modal-body pre { color: #e2e8f0; font-family: monospace; font-size: 0.9rem; padding: 20px; white-space: pre-wrap; margin:0; }
        .summary-card { background: rgba(59, 130, 246, 0.1); border: 1px solid rgba(59, 130, 246, 0.2); border-radius: 8px; padding: 15px; margin-bottom: 20px; color:#fff; display: flex; gap: 20px; flex-wrap: wrap; }
    </style>
    <script>
        function openTab(id) {
            document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
            document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
            document.getElementById(id).classList.add('active');
            event.currentTarget.classList.add('active');
            if(id === 'tab-dashboard' && window.myChart) { window.myChart.resize(); }
        }
        function showModal(id, title) {
            const el = document.getElementById('log_' + id);
            if(!el) { alert('Log undefined: ' + id); return; }
            document.getElementById('mBody').innerHTML = '<pre>' + el.innerHTML + '</pre>';
            document.getElementById('mTitle').innerText = title;
            document.getElementById('logModal').style.display = 'block';
        }
        function closeModal() { document.getElementById('logModal').style.display = 'none'; }
        window.onclick = function(e) { if(e.target.className === 'modal') closeModal(); }
        document.addEventListener('keydown', (e) => { if(e.key === 'Escape') closeModal(); });
    </script>
</head>
<body>
    <aside>
        <div class="logo"><span style="color:var(--accent)">DNS</span>Diag <span style="font-size:0.5em; opacity:0.5; margin-left:5px">v${SCRIPT_VERSION}</span></div>
        <nav>
            <div class="nav-item active" onclick="openTab('tab-dashboard')">📊 Dashboard</div>
            <div class="nav-item" onclick="openTab('tab-servers')">🖥️ Servidores</div>
            <div class="nav-item" onclick="openTab('tab-zones')">🌍 Zonas</div>
            <div class="nav-item" onclick="openTab('tab-records')">📝 Registros</div>
            <div class="nav-item" onclick="openTab('tab-config')">⚙️ Bastidores</div>
            <div class="nav-item" onclick="openTab('tab-help')">❓ Ajuda</div>
            <div class="nav-item" onclick="openTab('tab-logs')">📜 Logs Verbos</div>
        </nav>
        <div style="margin-top:auto; padding-top:20px; border-top:1px solid var(--border); font-size:0.75rem; color:#64748b;">
            Executado por: <strong>$USER</strong><br>$TIMESTAMP
        </div>
    </aside>
    <main>
        <!-- DASHBOARD TAB -->
        <div id="tab-dashboard" class="tab-content active">
            <div class="page-header">
                <div><h1>Dashboard Executivo</h1><div class="subtitle">Visão unificada da execução (Paridade Terminal).</div></div>
                <div style="text-align:right"><div style="font-size:3rem; font-weight:800; color:${grade_color}; line-height:1;">${grade}</div><div style="font-size:0.8rem; letter-spacing:1px; color:${grade_color}; font-weight:600;">HEALTH SCORE</div></div>
            </div>

            <!-- TERMINAL PARITY GRID -->
            <div class="dashboard-grid">
                <!-- GERAL -->
                <div class="card" style="border-top: 3px solid #3b82f6;">
                    <div class="card-header">GERAL</div>
                    <div class="stat-row"><span class="stat-label">⏱️ Duração</span> <span class="stat-val">${TOTAL_DURATION}s</span></div>
                    <div class="stat-row"><span class="stat-label">🧪 Execuções</span> <span class="stat-val">${total_exec}</span></div>
                    <div class="stat-row" style="margin-left:10px; font-size:0.8em; color:#94a3b8"><span class="stat-label">Sry / Zone / Rec</span> <span>${CNT_TESTS_SRV} / ${CNT_TESTS_ZONE} / ${CNT_TESTS_REC}</span></div>
                    <div class="stat-row"><span class="stat-label">🔢 Escopo</span> <span class="stat-val">${srv_count} Srv | ${zone_count} Zones | ${rec_count} Rec</span></div>
                </div>

                <!-- SERVIDORES -->
                <div class="card" style="border-top: 3px solid #f59e0b;">
                    <div class="card-header">SERVIDORES</div>
                    <div class="stat-row"><span class="stat-label">📡 Conectividade</span> <span class="stat-val"><span class="text-ok">${CNT_PING_OK:-0} OK</span> / <span class="text-fail">${CNT_PING_FAIL:-0} Fail</span></span></div>
                    <div class="stat-row"><span class="stat-label">🌉 Portas (53/853)</span> <span class="stat-val">53[<span class="text-ok">${TCP_SUCCESS:-0}</span>/<span class="text-fail">${TCP_FAIL:-0}</span>] | 853[<span class="text-ok">${DOT_SUCCESS:-0}</span>/<span class="text-fail">${DOT_FAIL:-0}</span>]</span></div>
                    <div class="stat-row"><span class="stat-label">⚙️ Config (Ver/Rec)</span> <span class="stat-val">Ver[<span class="text-ok">${SEC_HIDDEN:-0}</span>/<span class="text-fail">${SEC_REVEALED:-0}</span>] | Rec[<span class="text-ok">${SEC_REC_OK:-0}</span>/<span class="text-fail">${SEC_REC_RISK:-0}</span>]</span></div>
                    <div class="stat-row"><span class="stat-label">🔧 Recursos</span> <span class="stat-val">EDNS[<span class="text-ok">${EDNS_SUCCESS:-0}</span>] | Cookie[<span class="text-ok">${COOKIE_SUCCESS:-0}</span>]</span></div>
                    <div class="stat-row"><span class="stat-label">🛡️ Segurança</span> <span class="stat-val">DNSSEC[<span class="text-ok">${DNSSEC_SUCCESS:-0}</span>/<span class="text-fail">${DNSSEC_FAIL:-0}</span>] TLS[<span class="text-ok">${TLS_SUCCESS:-0}</span>]</span></div>
                </div>

                <!-- ZONAS -->
                <div class="card" style="border-top: 3px solid #10b981;">
                     <div class="card-header">ZONAS</div>
                     <div class="stat-row"><span class="stat-label">🔄 SOA Sync</span> <span class="stat-val"><span class="text-ok">${CNT_ZONES_OK:-0} OK</span> / <span class="text-fail">${CNT_ZONES_DIV:-0} DIV</span></span></div>
                     <div class="stat-row"><span class="stat-label">🌍 AXFR</span> <span class="stat-val"><span class="text-ok">${SEC_AXFR_OK:-0} Block</span> / <span class="text-fail">${SEC_AXFR_RISK:-0} Open</span></span></div>
                     <div class="stat-row"><span class="stat-label">🔐 Assinaturas</span> <span class="stat-val"><span class="text-ok">${ZONE_SEC_SIGNED:-0} Signed</span> / <span class="text-fail">${ZONE_SEC_UNSIGNED:-0} Unsigned</span></span></div>
                </div>

                 <!-- REGISTROS -->
                <div class="card" style="border-top: 3px solid #a855f7;">
                     <div class="card-header">REGISTROS</div>
                     <div class="stat-row"><span class="stat-label">✅ Sucessos</span> <span class="stat-val"><span class="text-ok">${CNT_REC_FULL_OK:-0} OK</span> / <span class="text-warn">${CNT_REC_PARTIAL:-0} Partial</span></span></div>
                     <div class="stat-row"><span class="stat-label">🚫 Resultados</span> <span class="stat-val"><span class="text-fail">${CNT_REC_FAIL:-0} Fail</span> / <span class="text-warn">${CNT_REC_NXDOMAIN:-0} NX</span></span></div>
                     <div class="stat-row"><span class="stat-label">⚠️ Consistência</span> <span class="stat-val"><span class="text-ok">${CNT_REC_CONSISTENT:-0} Sync</span> / <span class="text-fail">${CNT_REC_DIVERGENT:-0} Div</span></span></div>
                </div>
            </div>

            <div style="display: grid; grid-template-columns: 2fr 1fr; gap: 20px; margin-bottom: 30px;">
                <div class="card"><div class="card-header" style="color:#aaa; border:none; margin:0; padding:0; padding-bottom:10px;">Top Latência</div><div style="height: 250px;"><canvas id="chartLat"></canvas></div></div>
                <div class="card"><div class="card-header" style="color:#aaa; border:none; margin:0; padding:0; padding-bottom:10px;">Status Global</div><div style="height: 250px;"><canvas id="chartStat"></canvas></div></div>
            </div>
             <script>
                const ctxLat = document.getElementById('chartLat');
                if(ctxLat) { new Chart(ctxLat, { type: 'bar', data: { labels: $json_labels, datasets: [{ label: 'Ping (ms)', data: $json_data, backgroundColor: '#3b82f6', borderRadius: 4 }] }, options: { responsive: true, maintainAspectRatio: false, scales: { y: { beginAtZero: true, grid: { color:'rgba(255,255,255,0.05)' } }, x: { grid: { display:false } } }, plugins: { legend: { display: false } } } }); }
                const ctxStat = document.getElementById('chartStat');
                if(ctxStat) { new Chart(ctxStat, { type: 'doughnut', data: { labels: ['Sucesso', 'Falha', 'Divergente'], datasets: [{ data: [$SUCCESS_TESTS, $FAILED_TESTS, $DIVERGENT_TESTS], backgroundColor: ['#10b981', '#ef4444', '#a855f7'], borderWidth: 0 }] }, options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'bottom', labels: { color:'#94a3b8' } } } } }); }
            </script>
        </div>

        <div id="tab-servers" class="tab-content"><div class="page-header"><h1>Servidores</h1><div class="subtitle">Inventário e Performance.</div></div>$server_rows</div>
        <div id="tab-zones" class="tab-content"><div class="page-header"><h1>Zonas</h1><div class="subtitle">Autoridade e SOA.</div></div>$zone_rows</div>
        <div id="tab-records" class="tab-content"><div class="page-header"><h1>Registros</h1><div class="subtitle">Resolução e Consistência.</div></div>$record_rows</div>
        
        <div id="tab-config" class="tab-content">
             <div class="page-header"><h1>Bastidores da Execução</h1></div>
             <div class="dashboard-grid">
                 <div class="card">
                    <div class="card-header">⏱️ Tempos e Performance</div>
                    <table>
                        <tr><td>Inicio</td><td>${START_TIME_HUMAN}</td></tr>
                        <tr><td>Fim</td><td>${END_TIME_HUMAN}</td></tr>
                        <tr><td>Duração</td><td>${TOTAL_DURATION}s</td></tr>
                        <tr><td>Sleep Overhead</td><td>${TOTAL_SLEEP_TIME}s</td></tr>
                    </table>
                 </div>
                 <div class="card">
                     <div class="card-header">📂 Arquivos e Caminhos</div>
                     <table>
                        <tr><td>Script Dir</td><td style="font-family:monospace; font-size:0.8em">${SCRIPT_DIR}</td></tr>
                        <tr><td>Domains File</td><td style="font-family:monospace; font-size:0.8em">${FILE_DOMAINS}</td></tr>
                        <tr><td>Groups File</td><td style="font-family:monospace; font-size:0.8em">${FILE_GROUPS}</td></tr>
                        <tr><td>Log Output</td><td style="font-family:monospace; font-size:0.8em">${LOG_OUTPUT_DIR}</td></tr>
                     </table>
                 </div>
                 <div class="card">
                     <div class="card-header">⚙️ Flags de Execução</div>
                     <table>
                        <tr><td>Ping Check</td><td>${ENABLE_PING}</td></tr>
                        <tr><td>IPv6</td><td>${ENABLE_IPV6}</td></tr>
                        <tr><td>Trace</td><td>${ENABLE_TRACE}</td></tr>
                        <tr><td>JSON Report</td><td>${ENABLE_JSON_REPORT}</td></tr>
                        <tr><td>Color Output</td><td>${COLOR_OUTPUT}</td></tr>
                     </table>
                 </div>
             </div>
             
             <div class="card">
                <div class="card-header">🔧 Tresholds e Limites</div>
                <div style="display:flex; gap:20px; flex-wrap:wrap;">
                    <span class="badge bg-neutral">Ping Count: ${PING_COUNT}</span>
                    <span class="badge bg-neutral">Ping Timeout: ${PING_TIMEOUT}s</span>
                    <span class="badge bg-neutral">Dig Retry: ${DIG_TRIES}</span>
                    <span class="badge bg-neutral">Dig Timeout: ${DIG_TIMEOUT}s</span>
                    <span class="badge bg-neutral">Packet Loss Limit: ${PING_PACKET_LOSS_LIMIT}%</span>
                    <span class="badge bg-neutral">Latency Slow: ${PING_LATENCY_SLOW}ms</span>
                </div>
             </div>
             
             <h3 style="margin-top:20px">Variáveis de Ambiente</h3>
             <pre style="background:#020617; padding:15px; border-radius:8px; overflow-x:auto; font-size:0.8em; color:#64748b;">
USER=$USER
HOSTNAME=$HOSTNAME
TERM=$TERM
SHELL=$SHELL
             </pre>
             
             <!-- INJECT DETAILED CONFIG TABLE -->
EOF
    if [[ -f "$TEMP_CONFIG" ]]; then cat "$TEMP_CONFIG" >> "$target_file"; fi
    cat >> "$target_file" << EOF
        </div>
        
        <div id="tab-help" class="tab-content">
             <div class="page-header"><h1>Ajuda & Sobre</h1></div>
             
             <div class="card" style="margin-bottom:20px; border-left:4px solid #3b82f6;">
                <h3>📌 Disclaimer</h3>
                <p style="color:#94a3b8; margin-top:10px;">
                    Este relatório foi gerado automaticamente pelo <strong>DNS Diagnostics Tool v${SCRIPT_VERSION}</strong>.
                    Todas as informações aqui apresentadas refletem o estado da infraestrutura no momento exato da execução.
                    Latências e conectividade podem variar. A flag <strong>VER: HIDDEN</strong> indica que o servidor oculta sua versão (boa prática).
                    <strong>AXFR: DENIED</strong> indica que a transferência de zona está bloqueada (seguro).
                </p>
             </div>
             
             <div class="dashboard-grid">
                 <div class="card">
                    <div class="card-header">Legenda de Ícones</div>
                    <table>
                        <tr><td>✅</td><td>Sucesso / OK / Consistente</td></tr>
                        <tr><td>🚫</td><td>Falha / NXDOMAIN / Erro Crítico</td></tr>
                        <tr><td>⚠️</td><td>Aviso / Divergência (Alerta)</td></tr>
                        <tr><td>🛡️</td><td>Seguro (Bloqueado/Protegido)</td></tr>
                        <tr><td>🔓</td><td>Inseguro (Aberto/Sem Assinatura)</td></tr>
                    </table>
                 </div>
                 <div class="card">
                    <div class="card-header">Glossário Técnico</div>
                    <ul style="list-style:none; padding:0; color:#94a3b8; font-size:0.9em;">
                        <li style="margin-bottom:8px"><strong style="color:#fff">SOA Serial:</strong> Número de série da zona (deve ser igual em todos os servidores).</li>
                        <li style="margin-bottom:8px"><strong style="color:#fff">AXFR:</strong> Transferência completa de zona (risco se aberto para todos).</li>
                        <li style="margin-bottom:8px"><strong style="color:#fff">Recursion:</strong> Se "Open", o servidor resolve nomes externos (risco de DDoS).</li>
                        <li style="margin-bottom:8px"><strong style="color:#fff">DNSSEC:</strong> Validação de segurança criptográfica para domínios.</li>
                    </ul>
                 </div>
             </div>

             <div class="card">
                <div class="card-header">Comandos e Uso (Help Text)</div>
                <pre style="color:#e2e8f0;">$help_content</pre>
             </div>
        </div>
                <div id="tab-logs" class="tab-content">
              <div class="page-header"><h1>Logs Verbos (Execução Terminal)</h1></div>
              <div style="background:#0b1120; color:#e2e8f0; font-family:monospace; padding:20px; border-radius:8px; height:70vh; overflow:auto; white-space:pre-wrap; font-size:0.85rem; border:1px solid #334155;">
EOF
    if [[ -f "$TEMP_FULL_LOG" ]]; then 
        # Sanitize HTML entities in log to prevent breaking the report
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$TEMP_FULL_LOG" >> "$target_file"
    else
        echo "Log indisponível." >> "$target_file"
    fi
    cat >> "$target_file" << EOF
              </div>
         </div>
        
        <div id="logModal" class="modal">
            <div class="modal-content">
                <div class="modal-header"><div id="mTitle">Log</div><span style="cursor:pointer;" onclick="closeModal()">×</span></div>
                <div id="mBody" class="modal-body"></div>
            </div>
        </div>
        
        <div style="display:none">
EOF
    if [[ -f "$TEMP_DETAILS" ]]; then cat "$TEMP_DETAILS" >> "$target_file"; fi
    cat >> "$target_file" << EOF
        </div>
    </main>
    <script>if(window.myChart){window.myChart.resize();}</script>
</body></html>
EOF
}
assemble_html() {
    :
}


generate_security_html() {
    # Generate HTML block if there is data
    if [[ -s "$TEMP_SEC_ROWS" ]]; then
        local sec_content
        sec_content=$(cat "$TEMP_SEC_ROWS")
        
        # Simple Mode
        if [[ "$ENABLE_SIMPLE_REPORT" == "true" ]]; then
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
        name=$(echo "$name" | tr -d '[:space:]\r\n\t' ); servers=$(echo "$servers" | tr -d '[:space:]\r')
        [[ -z "$timeout" ]] && timeout=$TIMEOUT
        IFS=',' read -ra srv_arr <<< "$servers"
        DNS_GROUPS["$name"]="${srv_arr[@]}"; DNS_GROUP_DESC["$name"]="$desc"; DNS_GROUP_TYPE["$name"]="$type"; DNS_GROUP_TIMEOUT["$name"]="$timeout"
    done < "$FILE_GROUPS"

    # Identify Unique Servers to Test (Global Discovery)
    declare -gA UNIQUE_SERVERS
    declare -gA SERVER_GROUPS_MAP
    
    # Identificar Grupos Ativos (Filtragem)
    # Limpar qualquer whitespace ou caractere invisivel nos nomes dos grupos
    declare -gA ACTIVE_GROUPS_CALC
    
    if [[ "$ONLY_TEST_ACTIVE_GROUPS" == "true" ]]; then
        echo -e "${GRAY}  Filtro Ativado: Carregando apenas grupos referenciados em $FILE_DOMAINS...${NC}"
        if [[ -f "$FILE_DOMAINS" ]]; then
            while IFS=';' read -r domain groups _ _ _; do
                 [[ "$domain" =~ ^# || -z "$domain" ]] && continue
                 
                 # Split groups by comma
                 IFS=',' read -ra grp_list <<< "$groups"
                 for raw_g in "${grp_list[@]}"; do
                     # Sanitize: Remove spaces, carriage returns, tabs
                     local clean_g=$(echo "$raw_g" | tr -d '[:space:]\r\n\t')
                     if [[ -n "$clean_g" ]]; then
                         ACTIVE_GROUPS_CALC["$clean_g"]=1
                         # Debug only if verbose > 1
                         [[ "$VERBOSE_LEVEL" -gt 1 ]] && echo "    -> Ativando Grupo: [$clean_g]"
                     fi
                 done
            done < "$FILE_DOMAINS"
        else
            echo -e "${YELLOW}  Aviso: $FILE_DOMAINS não encontrado. Ativando todos os grupos.${NC}"
            for g in "${!DNS_GROUPS[@]}"; do ACTIVE_GROUPS_CALC[$g]=1; done
        fi
    else
        # Se filtro desligado, ativa todos
        for g in "${!DNS_GROUPS[@]}"; do ACTIVE_GROUPS_CALC[$g]=1; done
    fi

    for grp in "${!DNS_GROUPS[@]}"; do
        # Sanitize loop key just in case
        local clean_key=$(echo "$grp" | tr -d '[:space:]\r\n\t')
        
        # Skip if not active
        if [[ -z "${ACTIVE_GROUPS_CALC[$clean_key]}" ]]; then 
             [[ "$VERBOSE_LEVEL" -gt 1 ]] && echo -e "    🚫 Ignorando Grupo Inativo: [$clean_key]"
             continue
        fi
        
        # Add to unique servers list
        for ip in ${DNS_GROUPS[$grp]}; do
            UNIQUE_SERVERS[$ip]=1
            # Append group to map
            if [[ -z "${SERVER_GROUPS_MAP[$ip]}" ]]; then SERVER_GROUPS_MAP[$ip]="$grp"; else SERVER_GROUPS_MAP[$ip]="${SERVER_GROUPS_MAP[$ip]},$grp"; fi
        done
    done
    
    local num_active=${#ACTIVE_GROUPS_CALC[@]}
    local num_srv=${#UNIQUE_SERVERS[@]}
    echo -e "  ✅ Escopo Definido: ${BOLD}${num_active}${NC} Grupos Ativos -> ${BOLD}${num_srv}${NC} Servidores Únicos."
}







log_tech_details() {
    local id=$1
    local title=$2
    local content=$3
    # Sanitize content for HTML
    local safe_out=$(echo "$content" | sed 's/&/\\&amp;/g; s/</\\&lt;/g; s/>/\\&gt;/g')
    echo "<div id=\"log_${id}\" style=\"display:none\">$safe_out</div>" >> "$TEMP_DETAILS"
}

check_tcp_dns() {
    local host=$1
    local port=$2
    local log_id=$3
    
    local out=""
    local ret=1
    
    # Try nc first (netcat)
    if command -v nc >/dev/null; then
        out=$(timeout "$TIMEOUT" nc -z -v -w "$TIMEOUT" "$host" "$port" 2>&1)
        ret=$?
    else
        # Fallback to bash /dev/tcp
        if timeout "$TIMEOUT" bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
            out="Connection to $host $port port [tcp/*] succeeded!"
            ret=0
        else
            out="Connection to $host $port port [tcp/*] failed: Connection refused or Timeout."
            ret=1
        fi
    fi
    
    local safe_out=$(echo "$out" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    echo "<div id=\"${log_id}_content\" style=\"display:none\"><pre>$safe_out</pre></div>" >> "$TEMP_DETAILS"
    echo "<div id=\"${log_id}_title\" style=\"display:none\">TCP Check | $host:$port</div>" >> "$TEMP_DETAILS"
    
    return $ret
}


assemble_json() {
    [[ "$ENABLE_JSON_REPORT" != "true" ]] && return
    
    JSON_FILE="${HTML_FILE%.html}.json"
    
    # --- BUILD SECTIONS ---

    # 1. SERVERS
    local json_servers=""
    if [[ "$ENABLE_PHASE_SERVER" == "true" ]]; then
       local first=true
       for ip in "${!UNIQUE_SERVERS[@]}"; do
           $first || json_servers+=","
           first=false
           
           # Metrics
           local grps="${SERVER_GROUPS_MAP[$ip]}"
           local lat="${STATS_SERVER_PING_AVG[$ip]:-0}"
           local jit="${STATS_SERVER_PING_JITTER[$ip]:-0}"
           local loss="${STATS_SERVER_PING_LOSS[$ip]:-0}"
           local status="${STATS_SERVER_PING_STATUS[$ip]:-UNK}"
           
           # Caps
           local p53="${STATS_SERVER_PORT_53[$ip]:-NA}"
           local rec="${STATS_SERVER_RECURSION[$ip]:-NA}"
           local dnss="${STATS_SERVER_DNSSEC[$ip]:-NA}"
           local doh="${STATS_SERVER_DOH[$ip]:-NA}"
           local tls="${STATS_SERVER_TLS[$ip]:-NA}"
           
           json_servers+="{
             \"ip\": \"$ip\",
             \"groups\": \"$grps\",
             \"ping\": { \"status\": \"$status\", \"latency\": $lat, \"jitter\": $jit, \"loss\": $loss },
             \"capabilities\": {
                 \"port53\": \"$p53\",
                 \"recursion\": \"$rec\",
                 \"dnssec\": \"$dnss\",
                 \"doh\": \"$doh\",
                 \"tls\": \"$tls\"
             }
           }"
       done
    fi
    
    # 2. ZONES
    local json_zones=""
    if [[ "$ENABLE_PHASE_ZONE" == "true" ]]; then
        local first_z=true
        while IFS=';' read -r domain groups _ _ _; do
             [[ "$domain" =~ ^# || -z "$domain" ]] && continue
             domain=$(echo "$domain" | xargs)
             
             $first_z || json_zones+=","
             first_z=false
             
             IFS=',' read -ra grp_list <<< "$groups"
             local zone_servers_json=""
             local first_s=true
             
             for grp in "${grp_list[@]}"; do
                  for srv in ${DNS_GROUPS[$grp]}; do
                       $first_s || zone_servers_json+=","
                       first_s=false
                       local soa="${STATS_ZONE_SOA[$domain|$grp|$srv]}"
                       local axfr="${STATS_ZONE_AXFR[$domain|$grp|$srv]}"
                       zone_servers_json+="{ \"server\": \"$srv\", \"group\": \"$grp\", \"soa\": \"$soa\", \"axfr\": \"$axfr\" }"
                  done
             done
             
             json_zones+="{
               \"domain\": \"$domain\",
               \"results\": [ $zone_servers_json ]
             }"
        done < "$FILE_DOMAINS"
    fi

    # 3. RECORDS
    local json_records=""
    if [[ "$ENABLE_PHASE_RECORD" == "true" ]]; then
         local first_r=true
         # We need to iterate stats keys or reconstruct from domains file. 
         # Reconstructing logic similar to report gen is safer for order.
          while IFS=';' read -r domain groups test_types record_types extra_hosts; do
             [[ "$domain" =~ ^# || -z "$domain" ]] && continue
             IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
             IFS=',' read -ra grp_list <<< "$groups"
             IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
             local targets=("$domain")
             for h in "${extra_list[@]}"; do [[ -n "$h" ]] && targets+=("$h.$domain"); done
             
             for target in "${targets[@]}"; do
                 for rec_type in "${rec_list[@]}"; do
                     rec_type=${rec_type^^}
                     
                     $first_r || json_records+=","
                     first_r=false
                     
                     local rec_results_json=""
                     local first_rr=true
                     local consistent="CONSISTENT"
                     
                     # Check Consistency first
                     # (Logic simplified: checking stored consistency flag)
                     # But consistency is stored per Group. We aggregate blindly here.
                     
                     for grp in "${grp_list[@]}"; do
                         for srv in ${DNS_GROUPS[$grp]}; do
                             $first_rr || rec_results_json+=","
                             first_rr=false
                             local st="${STATS_RECORD_RES[$target|$rec_type|$grp|$srv]}"
                             local ans="${STATS_RECORD_ANSWER[$target|$rec_type|$grp|$srv]}"
                             # Escape json
                             ans=$(echo "$ans" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
                             rec_results_json+="{ \"server\": \"$srv\", \"group\": \"$grp\", \"status\": \"$st\", \"answer\": \"$ans\" }"
                         done
                     done
                     
                     json_records+="{
                       \"target\": \"$target\",
                       \"type\": \"$rec_type\",
                       \"results\": [ $rec_results_json ]
                     }"
                 done
             done
          done < "$FILE_DOMAINS"
    fi

    # Build Final JSON
    cat > "$JSON_FILE" << EOF
{
  "meta": {
    "script_version": "$SCRIPT_VERSION",
    "timestamp_start": "$START_TIME_HUMAN",
    "duration_seconds": $TOTAL_DURATION,
    "user": "$USER",
    "hostname": "$HOSTNAME"
  },
  "config": {
    "phases": {
       "server": $ENABLE_PHASE_SERVER,
       "zone": $ENABLE_PHASE_ZONE,
       "record": $ENABLE_PHASE_RECORD
    }
  },
  "summary": {
    "executions": {
       "server_tests": $((CNT_TESTS_SRV + 0)),
       "zone_tests": $((CNT_TESTS_ZONE + 0)),
       "record_tests": $((CNT_TESTS_REC + 0))
    },
    "counters": {
       "success": $((SUCCESS_TESTS + 0)),
       "failure": $((FAILED_TESTS + 0)),
       "divergent": $((DIVERGENT_TESTS + 0))
    }
  },
  "data": {
     "servers": [ $json_servers ],
     "zones": [ $json_zones ],
     "records": [ $json_records ]
  }
}
EOF

}

# --- HIERARCHICAL REPORTING (v2 Refactored) ---
generate_hierarchical_stats() {
    echo -e "\n${BOLD}======================================================${NC}"
    echo -e "${BOLD}         RELATÓRIO DE ESTATÍSTICAS (DETALHADO)${NC}"
    echo -e "${BOLD}======================================================${NC}"

    # ==========================
    # 1. SERVER STATS AGGREGATION
    # ==========================
    if [[ "$ENABLE_PHASE_SERVER" == "true" ]]; then
        echo -e "\n${BLUE}${BOLD}1. TESTES DE SERVIDORES (Infraestrutura & Capabilities)${NC}"
        
        # Pre-Calculation for Aggregates (Ping/Jitter/Loss are numeric)
        local G_LAT_MIN=999999; local G_LAT_MAX=0; local G_LAT_SUM=0; local G_LAT_CNT=0
        local G_JIT_MIN=999999; local G_JIT_MAX=0; local G_JIT_SUM=0; local G_JIT_CNT=0
        local G_LOSS_SUM=0; local G_LOSS_CNT=0
        
        # Capability Counters (Global)
        local G_P53_OPEN=0; local G_P53_CLOSED=0; local G_P53_FILT=0
        local G_P853_OK=0;  local G_P853_FAIL=0
        local G_REC_OPEN=0; local G_REC_CLOSED=0
        local G_EDNS_OK=0;  local G_EDNS_FAIL=0
        local G_COOKIE_OK=0; local G_COOKIE_NO=0; local G_COOKIE_FAIL=0
        local G_VER_HIDDEN=0; local G_VER_REVEALED=0
        local G_DNSSEC_OK=0; local G_DNSSEC_FAIL=0
        local G_DOH_OK=0; local G_DOH_FAIL=0
        local G_TLS_OK=0; local G_TLS_FAIL=0

        # Group Stats Storage
        local -A GRP_LAT_MIN; local -A GRP_LAT_MAX; local -A GRP_LAT_SUM; local -A GRP_LAT_CNT
        local -A GRP_JIT_MIN; local -A GRP_JIT_MAX; local -A GRP_JIT_SUM; local -A GRP_JIT_CNT
        local -A GRP_LOSS_SUM; local -A GRP_LOSS_CNT
        
        local -A GRP_P53_OPEN; local -A GRP_P53_CLOSED; local -A GRP_P53_FILT
        local -A GRP_REC_OPEN; local -A GRP_REC_CLOSED
        local -A GRP_EDNS_OK;  local -A GRP_EDNS_FAIL
        local -A GRP_DNSSEC_OK; local -A GRP_DNSSEC_FAIL
        local -A GRP_DOH_OK; local -A GRP_DOH_FAIL
        local -A GRP_TLS_OK; local -A GRP_TLS_FAIL
        
        # Ping Counters
        local G_PING_OK=0; local G_PING_SLOW=0; local G_PING_FAIL=0; local G_PING_DOWN=0
        local -A GRP_PING_OK; local -A GRP_PING_SLOW
        local -A GRP_PING_FAIL; local -A GRP_PING_DOWN
        
        local -A GROUPS_SEEN

        # Iterate all servers to populate stats
        for ip in "${!UNIQUE_SERVERS[@]}"; do
            local grps="${SERVER_GROUPS_MAP[$ip]}"
            
            # Numeric Metrics
            local lat_min="${STATS_SERVER_PING_MIN[$ip]}"; [[ -z "$lat_min" ]] && lat_min=0
            local lat_avg="${STATS_SERVER_PING_AVG[$ip]}"; [[ -z "$lat_avg" ]] && lat_avg=0
            local lat_max="${STATS_SERVER_PING_MAX[$ip]}"; [[ -z "$lat_max" ]] && lat_max=0
            local jit="${STATS_SERVER_PING_JITTER[$ip]}";  [[ -z "$jit" || "$jit" == "-" ]] && jit=0
            local loss="${STATS_SERVER_PING_LOSS[$ip]}";   [[ -z "$loss" || "$loss" == "-" ]] && loss=0
            
            # Global Aggregates (Latency)
            if [[ "$lat_avg" != "0" ]]; then
                G_LAT_SUM=$(echo "$G_LAT_SUM + $lat_avg" | bc)
                G_LAT_CNT=$((G_LAT_CNT + 1))
                if (( $(echo "$lat_avg < $G_LAT_MIN" | bc -l) )); then G_LAT_MIN=$lat_avg; fi
                if (( $(echo "$lat_avg > $G_LAT_MAX" | bc -l) )); then G_LAT_MAX=$lat_avg; fi
            fi
            
            # Global Aggregates (Jitter)
            if [[ -n "${STATS_SERVER_PING_JITTER[$ip]}" && "${STATS_SERVER_PING_JITTER[$ip]}" != "-" ]]; then
                G_JIT_SUM=$(echo "$G_JIT_SUM + $jit" | bc)
                G_JIT_CNT=$((G_JIT_CNT + 1))
                if (( $(echo "$jit < $G_JIT_MIN" | bc -l) )); then G_JIT_MIN=$jit; fi
                if (( $(echo "$jit > $G_JIT_MAX" | bc -l) )); then G_JIT_MAX=$jit; fi
            fi

            # Global Aggregates (Loss)
            if [[ -n "${STATS_SERVER_PING_LOSS[$ip]}" && "${STATS_SERVER_PING_LOSS[$ip]}" != "-" ]]; then
                G_LOSS_SUM=$(echo "$G_LOSS_SUM + $loss" | bc)
                G_LOSS_CNT=$((G_LOSS_CNT + 1))
            fi
             
            # Ping Status Counters
            local p_stat="${STATS_SERVER_PING_STATUS[$ip]}"
            if [[ -z "$p_stat" || "$p_stat" == "-" ]]; then
                 if [[ "$loss" == "100" ]]; then p_stat="DOWN"
                 elif [[ "$loss" != "-" && $(echo "$loss > $PING_PACKET_LOSS_LIMIT" | bc -l 2>/dev/null) -eq 1 ]]; then p_stat="FAIL"
                 elif [[ "$loss" != "-" ]]; then p_stat="OK"; fi
            fi
            
            if [[ "$p_stat" == "OK" ]]; then G_PING_OK=$((G_PING_OK+1));
            elif [[ "$p_stat" == "SLOW" ]]; then G_PING_SLOW=$((G_PING_SLOW+1));
            elif [[ "$p_stat" == "FAIL" ]]; then G_PING_FAIL=$((G_PING_FAIL+1));
            elif [[ "$p_stat" == "DOWN" ]]; then G_PING_DOWN=$((G_PING_DOWN+1)); fi
            
            # Capability Metrics
            local p53="${STATS_SERVER_PORT_53[$ip]}"
            local p853="${STATS_SERVER_PORT_853[$ip]}"
            local rec="${STATS_SERVER_RECURSION[$ip]}"
            local edns="${STATS_SERVER_EDNS[$ip]}"
            local cookie="${STATS_SERVER_COOKIE[$ip]}"
            local ver="${STATS_SERVER_VERSION[$ip]}"
            local dnssec="${STATS_SERVER_DNSSEC[$ip]}"
            local doh="${STATS_SERVER_DOH[$ip]}"
            local tls="${STATS_SERVER_TLS[$ip]}"

            # Global Counts
            [[ "$p53" == "OPEN" ]] && G_P53_OPEN=$((G_P53_OPEN + 1))
            [[ "$p53" == "CLOSED" ]] && G_P53_CLOSED=$((G_P53_CLOSED + 1))
            [[ "$p53" == "FILTERED" ]] && G_P53_FILT=$((G_P53_FILT + 1))

            [[ "$p853" == "OK" ]] && G_P853_OK=$((G_P853_OK + 1))
            [[ "$p853" == "refused" || "$p853" == "timeout" ]] && G_P853_FAIL=$((G_P853_FAIL + 1))

            [[ "$rec" == "OPEN" ]] && G_REC_OPEN=$((G_REC_OPEN + 1))
            [[ "$rec" == "CLOSED" ]] && G_REC_CLOSED=$((G_REC_CLOSED + 1))

            [[ "$edns" == "OK" ]] && G_EDNS_OK=$((G_EDNS_OK + 1))
            [[ "$edns" == "FAIL" ]] && G_EDNS_FAIL=$((G_EDNS_FAIL + 1))

            [[ "$cookie" == "OK" ]] && G_COOKIE_OK=$((G_COOKIE_OK + 1))
            [[ "$cookie" == "NO" ]] && G_COOKIE_NO=$((G_COOKIE_NO + 1))
            [[ "$cookie" == "FAIL" ]] && G_COOKIE_FAIL=$((G_COOKIE_FAIL + 1))

            [[ "$ver" == "HIDDEN" ]] && G_VER_HIDDEN=$((G_VER_HIDDEN + 1))
            [[ "$ver" == "REVEALED" ]] && G_VER_REVEALED=$((G_VER_REVEALED + 1))
            
            [[ "$dnssec" == "OK" ]] && G_DNSSEC_OK=$((G_DNSSEC_OK + 1))
            [[ "$dnssec" == "FAIL" ]] && G_DNSSEC_FAIL=$((G_DNSSEC_FAIL + 1))
            
            [[ "$doh" == "OK" ]] && G_DOH_OK=$((G_DOH_OK + 1))
            [[ "$doh" != "OK" && "$doh" != "SKIP" ]] && G_DOH_FAIL=$((G_DOH_FAIL + 1))
            
            [[ "$tls" == "OK" ]] && G_TLS_OK=$((G_TLS_OK + 1))
            [[ "$tls" != "OK" && "$tls" != "SKIP" ]] && G_TLS_FAIL=$((G_TLS_FAIL + 1))

            # Group Iteration
            IFS=',' read -ra GRPS <<< "$grps"
            for g in "${GRPS[@]}"; do
                GROUPS_SEEN[$g]=1
                
                # Initialize numeric if empty
                [[ -z "${GRP_LAT_MIN[$g]}" ]] && GRP_LAT_MIN[$g]=999999
                [[ -z "${GRP_LAT_MAX[$g]}" ]] && GRP_LAT_MAX[$g]=0
                [[ -z "${GRP_JIT_MIN[$g]}" ]] && GRP_JIT_MIN[$g]=999999
                [[ -z "${GRP_JIT_MAX[$g]}" ]] && GRP_JIT_MAX[$g]=0

                if [[ -n "${STATS_SERVER_PING_LOSS[$ip]}" && "${STATS_SERVER_PING_LOSS[$ip]}" != "-" ]]; then
                    GRP_LOSS_SUM[$g]=$(awk -v s="${GRP_LOSS_SUM[$g]:-0}" -v v="$loss" 'BEGIN {print s+v}')
                    GRP_LOSS_CNT[$g]=$(( ${GRP_LOSS_CNT[$g]:-0} + 1 ))
                fi
                
                # Numeric
                if (( $(echo "$lat_avg > 0" | bc -l) )); then
                     if (( $(echo "$lat_min < ${GRP_LAT_MIN[$g]}" | bc -l) )); then GRP_LAT_MIN[$g]=$lat_min; fi
                     if (( $(echo "$lat_max > ${GRP_LAT_MAX[$g]}" | bc -l) )); then GRP_LAT_MAX[$g]=$lat_max; fi
                     GRP_LAT_SUM[$g]=$(awk -v s="${GRP_LAT_SUM[$g]:-0}" -v v="$lat_avg" 'BEGIN {print s+v}')
                     GRP_LAT_CNT[$g]=$(( ${GRP_LAT_CNT[$g]:-0} + 1 ))

                     if [[ -n "${STATS_SERVER_PING_JITTER[$ip]}" && "${STATS_SERVER_PING_JITTER[$ip]}" != "-" ]]; then
                         if (( $(echo "$jit < ${GRP_JIT_MIN[$g]}" | bc -l) )); then GRP_JIT_MIN[$g]=$jit; fi
                         if (( $(echo "$jit > ${GRP_JIT_MAX[$g]}" | bc -l) )); then GRP_JIT_MAX[$g]=$jit; fi
                         GRP_JIT_SUM[$g]=$(awk -v s="${GRP_JIT_SUM[$g]:-0}" -v v="$jit" 'BEGIN {print s+v}')
                         GRP_JIT_CNT[$g]=$(( ${GRP_JIT_CNT[$g]:-0} + 1 ))
                     fi
                fi
            
            # Capabilities Group
            if [[ "$p53" == "OPEN" ]]; then GRP_P53_OPEN[$g]=$(( ${GRP_P53_OPEN[$g]:-0} + 1 ));
            elif [[ "$p53" == "CLOSED" ]]; then GRP_P53_CLOSED[$g]=$(( ${GRP_P53_CLOSED[$g]:-0} + 1 ));
            else GRP_P53_FILT[$g]=$(( ${GRP_P53_FILT[$g]:-0} + 1 )); fi
            
            if [[ "$p853" == "OK" ]]; then GRP_P853_OK[$g]=$(( ${GRP_P853_OK[$g]:-0} + 1 ));
            else GRP_P853_FAIL[$g]=$(( ${GRP_P853_FAIL[$g]:-0} + 1 )); fi
            
            if [[ "$rec" == "OPEN" ]]; then GRP_REC_OPEN[$g]=$(( ${GRP_REC_OPEN[$g]:-0} + 1 ));
            else GRP_REC_CLOSED[$g]=$(( ${GRP_REC_CLOSED[$g]:-0} + 1 )); fi
            
            if [[ "$edns" == "OK" ]]; then GRP_EDNS_OK[$g]=$(( ${GRP_EDNS_OK[$g]:-0} + 1 ));
            else GRP_EDNS_FAIL[$g]=$(( ${GRP_EDNS_FAIL[$g]:-0} + 1 )); fi
            
            if [[ "$dnssec" == "OK" ]]; then GRP_DNSSEC_OK[$g]=$(( ${GRP_DNSSEC_OK[$g]:-0} + 1 ));
            elif [[ "$dnssec" == "FAIL" ]]; then GRP_DNSSEC_FAIL[$g]=$(( ${GRP_DNSSEC_FAIL[$g]:-0} + 1 )); fi
            
            if [[ "$doh" == "OK" ]]; then GRP_DOH_OK[$g]=$(( ${GRP_DOH_OK[$g]:-0} + 1 ));
            else GRP_DOH_FAIL[$g]=$(( ${GRP_DOH_FAIL[$g]:-0} + 1 )); fi
            
            if [[ "$tls" == "OK" ]]; then GRP_TLS_OK[$g]=$(( ${GRP_TLS_OK[$g]:-0} + 1 ));
            else GRP_TLS_FAIL[$g]=$(( ${GRP_TLS_FAIL[$g]:-0} + 1 )); fi
            
            # Group Ping Stats
            if [[ "$p_stat" == "OK" ]]; then GRP_PING_OK[$g]=$(( ${GRP_PING_OK[$g]:-0} + 1 ));
            elif [[ "$p_stat" == "SLOW" ]]; then GRP_PING_SLOW[$g]=$(( ${GRP_PING_SLOW[$g]:-0} + 1 ));
            elif [[ "$p_stat" == "FAIL" ]]; then GRP_PING_FAIL[$g]=$(( ${GRP_PING_FAIL[$g]:-0} + 1 ));
            elif [[ "$p_stat" == "DOWN" ]]; then GRP_PING_DOWN[$g]=$(( ${GRP_PING_DOWN[$g]:-0} + 1 )); fi
        done
    done
    
    # Display Global Stats
    if [[ $G_LAT_CNT -gt 0 ]]; then
        local g_lat_avg=$(awk -v s="$G_LAT_SUM" -v c="$G_LAT_CNT" 'BEGIN {printf "%.2f", s/c}')
        local g_jit_avg=$(awk -v s="$G_JIT_SUM" -v c="$G_JIT_CNT" 'BEGIN {if(c>0) printf "%.2f", s/c; else print "0.00"}')
        local g_loss_avg=$(awk -v s="$G_LOSS_SUM" -v c="$G_LOSS_CNT" 'BEGIN {if(c>0) printf "%.2f", s/c; else print "0.00"}')
        
        echo -e "${GRAY}---------------------------------------------------------------${NC}"
        echo -e "  🌍 ${BOLD}GLOBAL ALL SERVERS${NC}"
        echo -e "     Latência : Min ${G_LAT_MIN}ms / Avg ${g_lat_avg}ms / Max ${G_LAT_MAX}ms"
        echo -e "     Jitter   : Min ${G_JIT_MIN}ms / Avg ${g_jit_avg}ms / Max ${G_JIT_MAX}ms"
        echo -e "     Connectivity : OK:${GREEN}${G_PING_OK}${NC} | Slow:${YELLOW}${G_PING_SLOW}${NC} | Fail:${RED}${G_PING_FAIL}${NC} | Down:${RED}${G_PING_DOWN}${NC}"
        echo -e "     Avg Loss : ${g_loss_avg}%"
        echo -e "     Ports    : 53 [Open:${GREEN}${G_P53_OPEN}${NC}/${RED}${G_P53_CLOSED}${NC}/${YELLOW}${G_P53_FILT}${NC}] | 853 [OK:${GREEN}${G_P853_OK}${NC}/Fail:${RED}${G_P853_FAIL}${NC}]"
        echo -e "     Security : Rec Open:${RED}${G_REC_OPEN}${NC} | Ver Hidden:${GREEN}${G_VER_HIDDEN}${NC} | Cookie OK:${GREEN}${G_COOKIE_OK}${NC}"
        echo -e "     Modern   : EDNS OK:${GREEN}${G_EDNS_OK}${NC} | DNSSEC OK:${GREEN}${G_DNSSEC_OK}${NC} | DoH OK:${GREEN}${G_DOH_OK}${NC} | TLS OK:${GREEN}${G_TLS_OK}${NC}"
    fi
    
    # Display Group Stats
    for g in "${!GROUPS_SEEN[@]}"; do
        echo -e "${GRAY}---------------------------------------------------------------${NC}"
        echo -e "  🏢 ${BOLD}GRUPO: $g${NC}"
        
        # Calc Group Averages
        local gl_avg="N/A"; local gl_min="N/A"; local gl_max="N/A"
        local gj_avg="N/A"; local gj_min="N/A"; local gj_max="N/A"
        local gloss_avg="N/A"
        
        if [[ ${GRP_LAT_CNT[$g]} -gt 0 ]]; then
            gl_avg=$(awk -v s="${GRP_LAT_SUM[$g]}" -v c="${GRP_LAT_CNT[$g]}" 'BEGIN {printf "%.2f", s/c}')
            gl_min=${GRP_LAT_MIN[$g]}
            gl_max=${GRP_LAT_MAX[$g]}
            
            gj_avg=$(awk -v s="${GRP_JIT_SUM[$g]}" -v c="${GRP_JIT_CNT[$g]}" 'BEGIN {printf "%.2f", s/c}')
            gj_min=${GRP_JIT_MIN[$g]}
            gj_max=${GRP_JIT_MAX[$g]}
        fi
        if [[ ${GRP_LOSS_CNT[$g]} -gt 0 ]]; then
            gloss_avg=$(awk -v s="${GRP_LOSS_SUM[$g]}" -v c="${GRP_LOSS_CNT[$g]}" 'BEGIN {printf "%.2f", s/c}')
        fi
        
        # Calculate Group DoT
        local g_dot_ok=${GRP_TLS_OK[$g]:-0} # Using TLS OK count which corresponds to DoT/853 check in this context or create specific if needed
        # In run_server_tests: GRP_TLS stats are populated from DoT check? No, separate.
        # Let's check GRP_P53_* vs GRP_P853 needed?
        # Re-check accumulation loop: 
        # GRP counters for 853 were missing in accumulation!
        # Need to fix accumulation first? 
        # Wait, I see GRP_TLS_OK... In run_server_tests, STATS_SERVER_TLS is handshake. STATS_SERVER_PORT_853 is socket.
        # Let's check aggregation loop lines ~3270+
        
        echo -e "     📊 Performance: Lat [${gl_min}/${gl_avg}/${gl_max}] | Jit [${gj_min}/${gj_avg}/${gj_max}] | Loss [${gloss_avg}%]"
        echo -e "     📡 Conexão : OK:${GREEN}${GRP_PING_OK[$g]:-0}${NC} | Slow:${YELLOW}${GRP_PING_SLOW[$g]:-0}${NC} | Fail:${RED}${GRP_PING_FAIL[$g]:-0}${NC} | Down:${RED}${GRP_PING_DOWN[$g]:-0}${NC}"
        echo -e "     🛡️  Segurança: P53 Open:${GREEN}${GRP_P53_OPEN[$g]:-0}${NC} | P853 Open:${GREEN}${GRP_P853_OK[$g]:-0}${NC} | Rec Open:${RED}${GRP_REC_OPEN[$g]:-0}${NC} | EDNS OK:${GREEN}${GRP_EDNS_OK[$g]:-0}${NC}"
        echo -e "     ✨ Modern   : DNSSEC OK:${GREEN}${GRP_DNSSEC_OK[$g]:-0}${NC} | DoH OK:${GREEN}${GRP_DOH_OK[$g]:-0}${NC} | TLS OK:${GREEN}${GRP_TLS_OK[$g]:-0}${NC}"

        echo -e "     ${GRAY}Servers:${NC}"
        printf "       %-18s | %-6s | %-20s | %-6s | %-12s | %-6s | %-6s | %-6s | %-6s | %-6s | %-6s | %-6s\n" "IP" "Ping" "Lat/Jit/Loss" "TCP53" "DoT_TCP853" "VER" "REC" "EDNS" "COOKIE" "DNSSEC" "DOH" "TLS"
        
        # List Servers in this Group
        for ip in ${DNS_GROUPS[$g]}; do
             local s_lat_min="${STATS_SERVER_PING_MIN[$ip]}"; [[ -z "$s_lat_min" ]] && s_lat_min="-"
             local s_lat_avg="${STATS_SERVER_PING_AVG[$ip]}"; [[ -z "$s_lat_avg" ]] && s_lat_avg="-"
             local s_lat_max="${STATS_SERVER_PING_MAX[$ip]}"; [[ -z "$s_lat_max" ]] && s_lat_max="-"
             local s_jit="${STATS_SERVER_PING_JITTER[$ip]}";  [[ -z "$s_jit" ]] && s_jit="-"
             local s_loss="${STATS_SERVER_PING_LOSS[$ip]}";   [[ -z "$s_loss" ]] && s_loss="-"
             
             local p53="${STATS_SERVER_PORT_53[$ip]}"
             local p853="${STATS_SERVER_PORT_853[$ip]}"
             local ver="${STATS_SERVER_VERSION[$ip]}"
             local rec="${STATS_SERVER_RECURSION[$ip]}"
             local edns="${STATS_SERVER_EDNS[$ip]}"
             local dnssec="${STATS_SERVER_DNSSEC[$ip]}"
             local doh="${STATS_SERVER_DOH[$ip]}"
             local tls="${STATS_SERVER_TLS[$ip]}"
             
             local s_status="${STATS_SERVER_PING_STATUS[$ip]}"
             local s_status="${STATS_SERVER_PING_STATUS[$ip]}"
             if [[ -z "$s_status" || "$s_status" == "-" ]]; then
                  # Fallback calculation if status missing
                  if [[ "$s_loss" == "100" ]]; then s_status="DOWN"
                  elif [[ "$s_loss" != "-" && $(echo "$s_loss > $PING_PACKET_LOSS_LIMIT" | bc -l 2>/dev/null) -eq 1 ]]; then s_status="FAIL"
                  elif [[ "$s_loss" != "-" ]]; then s_status="OK"; fi
             fi
             [[ -z "$s_status" ]] && s_status="-"
             
             # Colorize Loss/Down/Slow
             local c_stat=$NC
             if [[ "$s_status" == "FAIL" || "$s_status" == "DOWN" ]]; then c_stat=$RED
             elif [[ "$s_status" == "SLOW" ]]; then c_stat=$YELLOW
             elif [[ "$s_status" == "OK" ]]; then c_stat=$GREEN
             fi
             
             # Shorten Columns
             local c_p53=$GREEN; [[ "$p53" != "OPEN" ]] && c_p53=$RED
             local c_dot=$GREEN; [[ "$p853" != "OK" ]] && c_dot=$RED
             local c_ver=$GREEN; [[ "$ver" == "REVEALED" ]] && c_ver=$YELLOW
             [[ "$ver" == "HIDDEN" ]] && c_ver=$GREEN
             
             local c_rec=$GREEN; [[ "$rec" == "OPEN" ]] && c_rec=$RED
             local c_edns=$GREEN; [[ "$edns" == "FAIL" ]] && c_edns=$RED
             local c_cookie=$GREEN; [[ "$cookie" != "OK" ]] && c_cookie=$YELLOW
             local c_dnssec=$GREEN; [[ "$dnssec" != "OK" ]] && c_dnssec=$RED
             local c_doh=$GREEN; [[ "$doh" != "OK" ]] && c_doh=$RED; [[ "$doh" == "SKIP" ]] && c_doh=$GRAY
             local c_tls=$GREEN; [[ "$tls" != "OK" ]] && c_tls=$RED; [[ "$tls" == "SKIP" ]] && c_tls=$GRAY
             
             local lat_str="${s_lat_avg}/${s_jit}/${s_loss}%"
             [[ "$s_loss" == "100" ]] && lat_str="DOWN"
             
             printf "       %-18s | ${c_stat}%-6s${NC} | ${c_stat}%-20s${NC} | ${c_p53}%-6s${NC} | ${c_dot}%-12s${NC} | ${c_ver}%-6s${NC} | ${c_rec}%-6s${NC} | ${c_edns}%-6s${NC} | ${c_cookie}%-6s${NC} | ${c_dnssec}%-6s${NC} | ${c_doh}%-6s${NC} | ${c_tls}%-6s${NC}\n" \
                 "$ip" "$s_status" "$lat_str" "${p53:0:4}" "${p853:0:6}" "${ver:0:4}" "${rec:0:4}" "${edns:0:3}" "${cookie:0:4}" "${dnssec:0:4}" "${doh:0:3}" "${tls:0:3}"
        done
    done
    
    elif [[ "$ENABLE_PHASE_SERVER" == "false" ]]; then
        echo -e "\n${GRAY}   [Fase 1 desabilitada: Estatísticas de servidor ignoradas]${NC}"
    fi
    
    # ==========================
    # 2. ZONE STATS AGGREGATION
    # ==========================
    if [[ "$ENABLE_PHASE_ZONE" == "true" ]]; then
        echo -e "\n${BLUE}${BOLD}2. TESTES DE ZONA (SOA & AXFR)${NC}"
        
        # Header (Widths adjusted to match colorized rows: 30 | 29 | 15 | 29 | 15 )
        printf "  %-30s | %-20s | %-16s | %-20s | %-15s\n" "ZONA" "SOA CONSENSUS" "SOA SERIAL" "AXFR SECURITY" "DNSSEC"
        echo -e "  ${GRAY}-----------------------------------------------------------------------------------------------------------------${NC}"

        # Global Summary Counters (Reset)
        declare -g CNT_ZONES_OK=0
        declare -g CNT_ZONES_DIV=0

        while IFS=';' read -r domain groups _ _ _; do
            [[ "$domain" =~ ^# || -z "$domain" ]] && continue
            domain=$(echo "$domain" | xargs)
            IFS=',' read -ra grp_list <<< "$groups"
            
            # 1. SOA Analysis
            local soa_serials=()
            local soa_consistent=true
            local first_soa=""
            
            # Collect all SOA serials for this domain
            for grp in "${grp_list[@]}"; do
                 for srv in ${DNS_GROUPS[$grp]}; do
                      local s_soa="${STATS_ZONE_SOA[$domain|$grp|$srv]}"
                      if [[ -z "$first_soa" ]]; then first_soa="$s_soa"; fi
                      if [[ "$s_soa" != "$first_soa" ]]; then soa_consistent=false; fi
                 done
            done
            
            local soa_display="${GREEN}✅ SYNC${NC}"
            local soa_val="${GREEN}${first_soa}${NC}"
            
            # Check for error values in consistent result
            if [[ "$first_soa" == "TIMEOUT" || "$first_soa" == "ERR" || "$first_soa" == "N/A" ]]; then
                 soa_val="${RED}${first_soa}${NC}"
            fi
            
            if [[ "$soa_consistent" == "false" ]]; then
                 soa_display="${RED}⚠️ DIVERGENT${NC}"
                 soa_val="${YELLOW}MIXED${NC}"
                 CNT_ZONES_DIV=$((CNT_ZONES_DIV+1))
            else
                 CNT_ZONES_OK=$((CNT_ZONES_OK+1))
            fi
            
            # 2. AXFR & DNSSEC Analysis
            local axfr_allowed_count=0
            local axfr_total_count=0
            
            local dnssec_signed_count=0
            local dnssec_total_count=0
            
            for grp in "${grp_list[@]}"; do
                 for srv in ${DNS_GROUPS[$grp]}; do
                      local status="${STATS_ZONE_AXFR[$domain|$grp|$srv]}"
                      axfr_total_count=$((axfr_total_count+1))
                      if [[ "$status" == "ALLOWED" ]]; then axfr_allowed_count=$((axfr_allowed_count+1)); fi
                  
                  local d_sig="${STATS_ZONE_DNSSEC[$domain|$grp|$srv]}"
                  dnssec_total_count=$((dnssec_total_count+1))
                  if [[ "$d_sig" == "SIGNED" ]]; then dnssec_signed_count=$((dnssec_signed_count+1)); fi
             done
        done
        
        local axfr_display="${GREEN}🛡️ DENIED${NC}"
        if [[ $axfr_allowed_count -gt 0 ]]; then
             axfr_display="${RED}❌ ALLOWED ($axfr_allowed_count/$axfr_total_count)${NC}"
        fi
        
        local dnssec_display="${RED}🔓 UNSIGNED${NC}"
        if [[ $dnssec_signed_count -eq $dnssec_total_count && $dnssec_total_count -gt 0 ]]; then
             dnssec_display="${GREEN}🔐 SIGNED${NC}"
        elif [[ $dnssec_signed_count -gt 0 ]]; then
             dnssec_display="${YELLOW}⚠️ PARTIAL${NC}"
        fi
        
        # Use wider columns in printf to accommodate potential color codes if we want perfect alignment 
        # or stick to standard visual width. The issue is likely that the header is NARROWER than the content definition.
        
        # Row: 
        # Zone: 30
        # SOA Cons: 20 visual -> 29 raw
        # Wait, \e[32m is 5 chars. \e[0m is 4 chars. Total 9 invis chars. 
        # Text "✅ SYNC". Length 7. 7+9 = 16.
        # printf %-29s pads it to 29. Visual length 29-9 = 20. Match Header 20. Correct.
        
        # SOA Val:
        # Text "1234567890". Color 9. 19 chars.
        # printf %-15s... If serialized is 10 chars + 9 color = 19. It will overflow 15.
        # Let's bump SOA SERIAL col to 25 in Row.
        
        # AXFR:
        # Text "🛡️ DENIED". Length 9? (Shield is 2 chars?). 9+9=18. 
        # printf %-29s. Visual 20. Correct.
        
        # DNSSEC:
        # Text "🔓 UNSIGNED". Length 11. 11+9=20.
        # printf %-15s. Overflow!
        
        # FIX: Align everything to:
        # Zone: 30
        # SOA Cons: 20 visual -> 29 raw
        # SOA Ser: 15 visual -> 24 raw (inc color)
        # AXFR: 20 visual -> 29 raw
        # DNSSEC: 15 visual -> 24 raw
        
        printf "  %-30s | %-29s | %-24s | %-29s | %-24s\n" "$domain" "$soa_display" "$soa_val" "$axfr_display" "$dnssec_display"
        
        # 3. Detail on Divergence (SOA)
        if [[ "$soa_consistent" == "false" ]]; then
             echo -e "  ${GRAY}   └── Breakdown:${NC}"
             for grp in "${grp_list[@]}"; do
                  local g_soa=""
                  for srv in ${DNS_GROUPS[$grp]}; do
                       local s_soa="${STATS_ZONE_SOA[$domain|$grp|$srv]}"
                       printf "       %-20s : %s\n" "• ${grp} ($srv)" "$s_soa" 
                  done
             done
             echo ""
        fi

        
    done < "$FILE_DOMAINS"
    
    # Close Phase 2 Block
    elif [[ "$ENABLE_PHASE_ZONE" == "false" ]]; then
        echo -e "\n${GRAY}   [Fase 2 desabilitada: Estatísticas de zona ignoradas]${NC}"
    fi

    # ==========================
    # 3. RECORD STATS AGGREGATION
    # ==========================
    if [[ "$ENABLE_PHASE_RECORD" == "true" ]]; then
        echo -e "\n${BLUE}${BOLD}3. TESTES DE REGISTROS (Resolução & Consistência)${NC}"
        
        # Header
        printf "  %-30s | %-6s | %-16s | %-24s | %-40s\n" "RECORD" "TYPE" "STATUS" "CONSISTENCY" "ANSWERS"
        echo -e "  ${GRAY}------------------------------------------------------------------------------------------------------------------------------------${NC}"

        # Global Summary Counters (Reset)
        declare -g CNT_REC_FULL_OK=0
        declare -g CNT_REC_PARTIAL=0
        declare -g CNT_REC_FAIL=0
        declare -g CNT_REC_NXDOMAIN=0
        declare -g CNT_REC_CONSISTENT=0
        declare -g CNT_REC_DIVERGENT=0

    while IFS=';' read -r domain groups test_types record_types extra_hosts; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        
        IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra grp_list <<< "$groups"
        IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
        
        local targets=("$domain")
        for h in "${extra_list[@]}"; do [[ -n "$h" ]] && targets+=("$h.$domain"); done
        
        for target in "${targets[@]}"; do
            for rec_type in "${rec_list[@]}"; do
                rec_type=${rec_type^^}
                
                # Aggregation Vars
                local total_servers=0
                local total_ok=0
                local first_answer=""
                local is_consistent=true
                local answers_summary=""
                
                # Collect Data
                for grp in "${grp_list[@]}"; do
                    for srv in ${DNS_GROUPS[$grp]}; do
                         total_servers=$((total_servers+1))
                         local st="${STATS_RECORD_RES[$target|$rec_type|$grp|$srv]}"
                         local ans="${STATS_RECORD_ANSWER[$target|$rec_type|$grp|$srv]}"
                         
                         if [[ "$st" == "NOERROR" ]]; then
                             total_ok=$((total_ok+1))
                             if [[ -z "$first_answer" ]]; then first_answer="$ans"; fi
                             # Strict comparison of answers
                             if [[ "$ans" != "$first_answer" ]]; then is_consistent=false; fi
                         fi
                    done
                done
                
                # Determine Status Display & Counters
                local status_fmt=""
                if [[ $total_ok -eq $total_servers ]]; then
                    status_fmt="${GREEN}✅ OK ($total_ok/$total_servers)${NC}"
                    CNT_REC_FULL_OK=$((CNT_REC_FULL_OK+1))
                elif [[ $total_ok -eq 0 ]]; then
                     # Check if it was NXDOMAIN
                     local sample_st="${STATS_RECORD_RES[$target|$rec_type|${grp_list[0]}|${DNS_GROUPS[${grp_list[0]}]%% *}]}" 
                     # (Approximation: check first server result)
                     if [[ "$sample_st" == "NXDOMAIN" ]]; then
                         status_fmt="${YELLOW}🚫 NXDOMAIN${NC}"
                         CNT_REC_NXDOMAIN=$((CNT_REC_NXDOMAIN+1))
                     else
                         status_fmt="${RED}❌ FAIL (0/$total_servers)${NC}"
                         CNT_REC_FAIL=$((CNT_REC_FAIL+1))
                     fi
                else
                    status_fmt="${YELLOW}⚠️ PARTIAL ($total_ok/$total_servers)${NC}"
                    CNT_REC_PARTIAL=$((CNT_REC_PARTIAL+1))
                fi
                
                # Determine Consistency Display
                local cons_fmt="${GRAY}--${NC}"
                if [[ $total_ok -gt 0 ]]; then
                     if [[ "$is_consistent" == "true" ]]; then
                          cons_fmt="${GREEN}✅ SYNC${NC}"
                          CNT_REC_CONSISTENT=$((CNT_REC_CONSISTENT+1))
                     else
                          cons_fmt="${RED}⚠️ DIVERGENT${NC}"
                          CNT_REC_DIVERGENT=$((CNT_REC_DIVERGENT+1))
                     fi
                fi
                
                # Determine Answer Display
                local ans_fmt=""
                if [[ $total_ok -gt 0 ]]; then
                     if [[ "$is_consistent" == "true" ]]; then
                          ans_fmt="${first_answer:0:50}"
                          if [[ ${#first_answer} -gt 50 ]]; then ans_fmt="${ans_fmt}..."; fi
                     else
                          ans_fmt="${YELLOW}Mixed (See Breakdown)${NC}"
                     fi
                else
                     ans_fmt="${GRAY}No Answer${NC}"
                fi
                
                printf "  %-30s | %-6s | %-25s | %-33s | %s\n" "$target" "$rec_type" "$status_fmt" "$cons_fmt" "$ans_fmt"
                
                # Expansion for inconsistencies
                if [[ $total_ok -gt 0 && "$is_consistent" == "false" ]]; then
                     echo -e "  ${GRAY}   └── Breakdown:${NC}"
                     for grp in "${grp_list[@]}"; do
                          for srv in ${DNS_GROUPS[$grp]}; do
                               local s_ans="${STATS_RECORD_ANSWER[$target|$rec_type|$grp|$srv]}"
                               local s_st="${STATS_RECORD_RES[$target|$rec_type|$grp|$srv]}"
                               if [[ "$s_st" == "NOERROR" ]]; then
                                    printf "       %-20s : %s\n" "• ${grp} ($srv)" "${s_ans:0:60}"
                               else
                                    printf "       %-20s : %s\n" "• ${grp} ($srv)" "${RED}$s_st${NC}"
                               fi
                          done
                     done
                     echo ""
                fi
            done
        done
    done <<< "$sorted_domains"
    echo ""

    elif [[ "$ENABLE_PHASE_RECORD" == "false" ]]; then
        echo -e "\n${GRAY}   [Fase 3 desabilitada: Estatísticas de registros ignoradas]${NC}"
    fi
}

print_final_terminal_summary() {
     # Calculate totals
     local total_tests=$((CNT_TESTS_SRV + CNT_TESTS_ZONE + CNT_TESTS_REC))
     local duration=$TOTAL_DURATION
     
     # Use our new function
     generate_hierarchical_stats
     
     echo -e "\n${BOLD}======================================================${NC}"
     echo -e "${BOLD}              RESUMO DA EXECUÇÃO${NC}"
     echo -e "${BOLD}======================================================${NC}"
     
     # Calculate totals for summary
     local srv_count=${#UNIQUE_SERVERS[@]}
     local zone_count=0
     local rec_count=0
     
     if [[ -f "$FILE_DOMAINS" ]]; then
        zone_count=$(grep -vE '^\s*#|^\s*$' "$FILE_DOMAINS" | wc -l)
        
        # Calculate expected unique records (same logic as run_record_tests)
        rec_count=$(awk -F';' '!/^#/ && !/^\s*$/ { 
            n_recs = split($4, a, ",");
            n_extras = 0;
            gsub(/[[:space:]]/, "", $5);
            if (length($5) > 0) n_extras = split($5, b, ",");
            count += n_recs * (1 + n_extras) 
        } END { print count }' "$FILE_DOMAINS")
     fi
     [[ -z "$rec_count" ]] && rec_count=0

     echo -e "${BLUE}${BOLD}GERAL:${NC}"
     echo -e "  ⏱️  Duração Total   : ${duration}s"
     echo -e "  🧪 Total Execuções  : ${total_tests} (${CNT_TESTS_SRV} Server Tests, ${CNT_TESTS_ZONE} Zone Tests, ${CNT_TESTS_REC} Record Tests)"
     echo -e "  🔢 Escopo Testado   : ${srv_count} Servidores | ${zone_count} Zonas | ${rec_count} Registros"
     
     echo -e "\n${BLUE}${BOLD}SERVIDORES:${NC}"
     echo -e "  📡 Conectividade   : ${GREEN}${CNT_PING_OK:-0} OK${NC} / ${RED}${CNT_PING_FAIL:-0} Falhas${NC}"
     echo -e "  🌉 Portas          : 53[${GREEN}${TCP_SUCCESS:-0}${NC}/${RED}${TCP_FAIL:-0}${NC}] | 853[${GREEN}${DOT_SUCCESS:-0}${NC}/${RED}${DOT_FAIL:-0}${NC}]"
     echo -e "  ⚙️  Configuração    : Ver[${GREEN}${SEC_HIDDEN:-0}${NC}/${RED}${SEC_REVEALED:-0}${NC}] | Rec[${GREEN}${SEC_REC_OK:-0}${NC}/${RED}${SEC_REC_RISK:-0}${NC}]"
     echo -e "  🔧 Recursos        : EDNS[${GREEN}${EDNS_SUCCESS:-0}${NC}] | Cookie[${GREEN}${COOKIE_SUCCESS:-0}${NC}]"
     echo -e "  🛡️  Segurança       : DNSSEC[${GREEN}${DNSSEC_SUCCESS:-0}${NC}/${RED}${DNSSEC_FAIL:-0}${NC}] | DoH[${GREEN}${DOH_SUCCESS:-0}${NC}/${RED}${DOH_FAIL:-0}${NC}] | TLS[${GREEN}${TLS_SUCCESS:-0}${NC}/${RED}${TLS_FAIL:-0}${NC}]"
     
     echo -e "\n${BLUE}${BOLD}ZONAS:${NC}"
     # Calcs for Zone Summary if not fully populated in previous steps (using available globals)
     # SEC_AXFR_RISK = Allowed, SEC_AXFR_OK = Denied
     echo -e "  🔄 SOA Sync        : ${GREEN}${CNT_ZONES_OK:-0} Consistentes${NC} / ${RED}${CNT_ZONES_DIV:-0} Divergentes${NC}"
     echo -e "  🌍 AXFR            : ${GREEN}${SEC_AXFR_OK:-0} Bloqueados${NC} / ${RED}${SEC_AXFR_RISK:-0} Expostos${NC}"
     echo -e "  🔐 Assinaturas     : ${GREEN}${ZONE_SEC_SIGNED:-0} Assinadas${NC} / ${RED}${ZONE_SEC_UNSIGNED:-0} Falhas (Missing)${NC}"
     
     echo -e "\n${BLUE}${BOLD}REGISTROS:${NC}"
     local rec_ok=$((CNT_NOERROR))
     echo -e "  ✅ Sucessos        : ${GREEN}${CNT_REC_FULL_OK:-0} OK${NC} / ${YELLOW}${CNT_REC_PARTIAL:-0} Parcial${NC}"
     echo -e "  🚫 Resultados      : ${RED}${CNT_REC_FAIL:-0} Falhas${NC} / ${YELLOW}${CNT_REC_NXDOMAIN:-0} NXDOMAIN${NC}"
     echo -e "  ⚠️  Consistência    : ${GREEN}${CNT_REC_CONSISTENT:-0} Sincronizados${NC} / ${RED}${CNT_REC_DIVERGENT:-0} Divergentes${NC}"
     
     # Log to text file
     if [[ "$ENABLE_LOG_TEXT" == "true" ]]; then
          echo "Writing text log..."
          # Redirect new stats to log
          generate_hierarchical_stats >> "$LOG_FILE_TEXT"
     fi
     
     # Always append stats to HTML Log Buffer
     generate_hierarchical_stats >> "$TEMP_FULL_LOG"

     echo -e "\n${BOLD}======================================================${NC}"
     echo -e "${CYAN}      📥 BAIXE E CONTRIBUA NO GITHUB${NC}"
     echo -e "${CYAN}      🔗 https://github.com/flashbsb/diagnostico_dns${NC}"
     echo -e "${BOLD}======================================================${NC}"
}

resolve_configuration() {
    # 1. Validation
    [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] && TIMEOUT=4
    [[ ! "$CONSISTENCY_CHECKS" =~ ^[0-9]+$ ]] && CONSISTENCY_CHECKS=3
}

validate_dig_capabilities() {
    # Check for DoT support (+tls)
    if [[ "$ENABLE_DOT_CHECK" == "true" ]]; then
        # Try a dummy local check. If +tls is invalid, dig returns 1 or prints "Invalid option"
        if ! dig +tls +noall . &>/dev/null; then
             echo -e "${YELLOW}⚠️  Aviso: O binário 'dig' local não suporta a opção '+tls'. O teste DoT será desativado.${NC}"
             ENABLE_DOT_CHECK="false"
        fi
    fi

    # Check for DoH support (+https)
    if [[ "$ENABLE_DOH_CHECK" == "true" ]]; then
        if ! dig +https +noall . &>/dev/null; then
             echo -e "${YELLOW}⚠️  Aviso: O binário 'dig' local não suporta a opção '+https'. O teste DoH será desativado.${NC}"
             ENABLE_DOH_CHECK="false"
        fi
    fi
 
    # Check for Cookie support (+cookie)
    if [[ "$ENABLE_COOKIE_CHECK" == "true" ]]; then
         if ! dig -h 2>&1 | grep -q "+\[no\]cookie"; then
             echo -e "${YELLOW}⚠️  Aviso: O binário 'dig' local não suporta a opção '+cookie'. O teste de Cookies será desativado.${NC}"
             ENABLE_COOKIE_CHECK="false"
         fi
    fi

    # Check for DNSSEC support (+dnssec)
    if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
        if ! dig +dnssec +noall . &>/dev/null; then
             echo -e "${YELLOW}⚠️  Aviso: O binário 'dig' local não suporta a opção '+dnssec'. A validação DNSSEC será desativada.${NC}"
             ENABLE_DNSSEC_CHECK="false"
        fi
    fi
}

# ==============================================
# NOVA ESTRUTURA MODULAR (Server -> Zone -> Records)
# ==============================================

# --- AUX: Get Probe Domain ---
get_probe_domain() {
    # Returns the first valid domain from the CSV to use as a target for server capability checks
    grep -vE '^\s*#|^\s*$' "$FILE_DOMAINS" | head -1 | awk -F';' '{print $1}'
}

# --- 1. SERVER TESTS ---
run_server_tests() {
    echo -e "\n${BLUE}=== FASE 1: TESTES DE SERVIDOR (Infraestrutura & Capabilities) ===${NC}"
    log_section "PHASE 1: SERVER TESTS"

    # Declare cache arrays globally
    declare -gA CACHE_TCP_STATUS
    declare -gA CACHE_TLS_STATUS
    declare -gA CACHE_EDNS_STATUS
    declare -gA CACHE_COOKIE_STATUS
    declare -gA CACHE_SEC_STATUS
    
    # New Statistical Arrays (Comprehensive)
    declare -gA STATS_SERVER_PING_MIN
    declare -gA STATS_SERVER_PING_AVG
    declare -gA STATS_SERVER_PING_MAX
    declare -gA STATS_SERVER_PING_LOSS
    declare -gA STATS_SERVER_PING_JITTER
    declare -gA STATS_SERVER_PING_STATUS
    
    declare -gA STATS_SERVER_PORT_53
    declare -gA STATS_SERVER_PORT_853
    declare -gA STATS_SERVER_VERSION
    declare -gA STATS_SERVER_RECURSION
    declare -gA STATS_SERVER_EDNS
    declare -gA STATS_SERVER_COOKIE
    declare -gA STATS_SERVER_DNSSEC
    declare -gA STATS_SERVER_DOH
    declare -gA STATS_SERVER_TLS
    declare -gA STATS_SERVER_HOPS


    
    # START SERVER HTML SECTION
    cat >> "$TEMP_SECTION_SERVER" << EOF
    <div style="margin-top: 50px;">
        <h2>🖥️ Saúde dos Servidores (Infraestrutura & Capabilities)</h2>
        <div class="table-responsive">
        <table>
            <thead>
                <tr>
                    <th>Servidor</th>
                    <th>Grupos</th>
                    <th>Ping (ICMP)</th>
                    <th>Latência (Avg/Jit/Loss)</th>
                    <th>Hops</th>
                    <th>Porta 53</th>
                    <th>Porta 853 (ABS)</th>
                    <th>Versão (Bind)</th>
                    <th>Recursão</th>
                    <th>EDNS</th>
                    <th>Cookie</th>
                    <th>DNSSEC (Val)</th>
                    <th>DoH (443)</th>
                    <th>TLS (Hshake)</th>
                </tr>
            </thead>
            <tbody>
EOF
    
    local probe_target=$(get_probe_domain)
    [[ -z "$probe_target" ]] && probe_target="."

    local HEADER_PRINTED="false"

    for ip in "${!UNIQUE_SERVERS[@]}"; do
        local grps="${SERVER_GROUPS_MAP[$ip]}"
        
        # Header/Legend for first run (or if verbose) - Simplified for clean output
        if [[ "$HEADER_PRINTED" == "false" ]]; then
             echo -e "${GRAY}  Legend: [Ping] [Port53] [DoT] [Ver] [Rec] [EDNS] [Cookie] [DNSSEC] [DoH] [TLS]${NC}"
             HEADER_PRINTED="true"
        fi
        
        echo -e "  🖥️  ${CYAN}Testing Server:${NC} $ip (Grupos: $grps)"
        
        # 1.1 Connectivity (Ping/Trace/Ports)
        local ping_res_html="<span class='badge neutral'>N/A</span>"
        local ping_res_term="${GRAY}N/A${NC}"
        local lat_stats="-"
        local tcp53_res_html="<span class='badge neutral'>N/A</span>"
        local tcp53_res_term="${GRAY}N/A${NC}"
        local tls853_res_html="<span class='badge neutral'>N/A</span>"
        local tls853_res_term="${GRAY}N/A${NC}"
        local ver_res_html="<span class='badge neutral'>N/A</span>"
        local ver_res_term="${GRAY}N/A${NC}"
        local rec_res_html="<span class='badge neutral'>N/A</span>"
        local rec_res_term="${GRAY}N/A${NC}"
        local edns_res_html="<span class='badge neutral'>N/A</span>"
        local edns_res_term="${GRAY}N/A${NC}"
        local cookie_res_html="<span class='badge neutral'>N/A</span>"
        local cookie_res_term="${GRAY}N/A${NC}"
        local dnssec_res_html="<span class='badge neutral'>N/A</span>"
        local doh_res_html="<span class='badge neutral'>N/A</span>"
        local tls_res_html="<span class='badge neutral'>N/A</span>"
        
        
        # Ping with Stats Extraction
        STATS_SERVER_PING_STATUS[$ip]="SKIP"
        if [[ "$ENABLE_PING" == "true" ]]; then
            local cmd_ping="ping -c $PING_COUNT -W $PING_TIMEOUT $ip"
            local out_ping=$($cmd_ping 2>&1)
            
            # Extract Packet Loss
            # Extract Packet Loss (Handle floats like 66.6667% -> 66)
            local loss_pct=$(echo "$out_ping" | grep -oP '\d+(\.\d+)?(?=% packet loss)' | awk -F. '{print $1}')
            [[ -z "$loss_pct" ]] && loss_pct=100
            STATS_SERVER_PING_LOSS[$ip]=$loss_pct
            
            # Extract Timing (rtt min/avg/max/mdev = 1.1/2.2/3.3/0.4 ms)
            local rtt_line=$(echo "$out_ping" | grep "rtt" | head -1)
            local p_min="0"; local p_avg="0"; local p_max="0"; local p_mdev="0"
            
            if [[ -n "$rtt_line" ]]; then
                 local vals=$(echo "$rtt_line" | awk -F'=' '{print $2}' | tr -d ' ms')
                 IFS='/' read -r p_min p_avg p_max p_mdev <<< "$vals"
            fi
            
            STATS_SERVER_PING_MIN[$ip]=$p_min
            STATS_SERVER_PING_AVG[$ip]=$p_avg
            STATS_SERVER_PING_MAX[$ip]=$p_max
            STATS_SERVER_PING_JITTER[$ip]=$p_mdev 
            
            # Prepare detailed stats string
            local ping_details="${GRAY}[${p_avg}ms|±${p_mdev}|${loss_pct}%]${NC}"
            
            if [[ "$loss_pct" -eq 100 ]]; then
                ping_res_html="<span class='badge status-fail'>100% LOSS</span>"
                ping_res_term="${RED}DOWN${NC}"
                CNT_PING_FAIL=$((CNT_PING_FAIL+1))
                STATS_SERVER_PING_STATUS[$ip]="DOWN"
            elif [[ "$loss_pct" -gt "$PING_PACKET_LOSS_LIMIT" ]]; then
                ping_res_html="<span class='badge status-warn'>${loss_pct}% LOSS</span>"
                ping_res_term="${YELLOW}FAIL ${ping_details}${NC}"
                CNT_PING_FAIL=$((CNT_PING_FAIL+1))
                lat_stats="${p_avg}ms / ±${p_mdev} / ${loss_pct}%"
                STATS_SERVER_PING_STATUS[$ip]="FAIL"
            else 
                # Packet Loss OK, Check Latency Threshold
                local lat_status="OK"
                # Use bc for float comparison if available, else integer
                local p_avg_int=${p_avg%.*}
                if [[ "$p_avg_int" -gt "$LATENCY_WARNING_THRESHOLD" ]]; then
                    ping_res_html="<span class='badge status-warn'>SLOW (${p_avg}ms)</span>"
                    ping_res_term="${YELLOW}SLOW ${ping_details}${NC}"
                    CNT_PING_OK=$((CNT_PING_OK+1)) # Still reachable
                    STATS_SERVER_PING_STATUS[$ip]="SLOW"
                else
                    ping_res_html="<span class='badge status-ok'>OK</span>"
                    ping_res_term="${GREEN}OK ${ping_details}${NC}"
                    CNT_PING_OK=$((CNT_PING_OK+1))
                    STATS_SERVER_PING_STATUS[$ip]="OK"
                fi
                
                lat_stats="${p_avg}ms / ±${p_mdev} / ${loss_pct}%"
            fi
        fi

        # --- TRACEROUTE CHECK ---
        local hops="N/A"
        local hops_html="<span class='badge neutral'>N/A</span>"
        
        if [[ "$ENABLE_TRACE" == "true" ]]; then
             echo -e "     🗺️  Tracing..."
             # Use -n to avoid DNS resolution delays, -w to limit wait
             local trace_out
             trace_out=$(traceroute -n -m "$TRACE_MAX_HOPS" -w 3 "$ip" 2>&1)
             
             # Logic to determine status
             local last_line=$(echo "$trace_out" | tail -n 1)
             local last_hop_num=$(echo "$last_line" | awk '{print $1}')
             local reached_target="false"
             
             # Check if target IP appears in the output (ignoring the command line itself)
             # Use grep to check for IP in the last few lines or strictly in the output lines
             if echo "$trace_out" | grep -q "$ip"; then
                 # Be careful, $ip is in the command line echoed by some shells or header of traceroute
                 # Check if it appears at the end of a line or as a hop address
                 if echo "$trace_out" | grep -v "traceroute to" | grep -Fq "$ip"; then
                     reached_target="true"
                 fi
             fi
             
             if [[ "$reached_target" == "true" && "$last_hop_num" =~ ^[0-9]+$ ]]; then
                 # Success
                 hops=$last_hop_num
                 hops_html="<span class='badge neutral'>${hops}</span>"
                 STATS_SERVER_HOPS[$ip]=$hops
                 echo "$ip:$hops" >> "$TEMP_TRACE"
                 echo -e "     🗺️  ${GRAY}Trace Hops  :${NC} ${hops}"
                 
             elif [[ "$last_hop_num" -ge "$TRACE_MAX_HOPS" ]]; then
                 # Reached Max Hops without confirmation -> BLOCKED/TIMEOUT
                 hops="MAX"
                 hops_html="<span class='badge status-warn' title='Trace completou $TRACE_MAX_HOPS saltos sem confirmar destino. Provável Bloqueio ICMP.'>BLOCKED</span>"
                 STATS_SERVER_HOPS[$ip]=$TRACE_MAX_HOPS
                 # We flag as MAX for chart or just don't add to chart? Let's add as Max to show distance/effort.
                 echo "$ip:$TRACE_MAX_HOPS" >> "$TEMP_TRACE"
                 echo -e "     🗺️  ${GRAY}Trace Hops  :${NC} ${YELLOW}BLOCKED ($TRACE_MAX_HOPS)${NC}"
                 
             else
                 # Partial or weird error
                 hops="ERR"
                 hops_html="<span class='badge status-fail'>ERR</span>"
                 echo -e "     🗺️  ${GRAY}Trace Hops  :${NC} ${RED}FAIL (N/A)${NC}"
             fi
             
             log_tech_details "trace_${ip}" "Traceroute: $ip" "$trace_out"
             hops_html="<button class='btn-tech' onclick=\"showLog('trace_${ip}')\">${hops_html/button/span}</button>"
        fi
        
        # Port 53
        if check_tcp_dns "$ip" 53 "port53_$ip"; then 
            tcp53_res_html="<span class='badge status-ok'>OPEN</span>"
            tcp53_res_term="${GREEN}OPEN${NC}"
            STATS_SERVER_PORT_53[$ip]="OPEN"
            TCP_SUCCESS=$((TCP_SUCCESS+1)); CACHE_TCP_STATUS[$ip]="OK"
        else 
            tcp53_res_html="<span class='badge status-fail'>CLOSED</span>"
            tcp53_res_term="${RED}CLOSED${NC}"
            STATS_SERVER_PORT_53[$ip]="CLOSED"
            TCP_FAIL=$((TCP_FAIL+1)); CACHE_TCP_STATUS[$ip]="FAIL"
        fi
        
        # Port 853
        if [[ "$ENABLE_DOT_CHECK" == "true" ]]; then
             if check_tcp_dns "$ip" 853 "port853_$ip"; then 
                 tls853_res_html="<span class='badge status-ok'>OPEN</span>"
                 tls853_res_term="${GREEN}OK${NC}"
                 STATS_SERVER_PORT_853[$ip]="OPEN"
                 CACHE_TLS_STATUS[$ip]="OK"
                 DOT_SUCCESS=$((DOT_SUCCESS+1))
             else 
                 tls853_res_html="<span class='badge status-fail'>CLOSED</span>"
                 tls853_res_term="${RED}FAIL${NC}"
                 STATS_SERVER_PORT_853[$ip]="CLOSED"
                 CACHE_TLS_STATUS[$ip]="FAIL"
                 DOT_FAIL=$((DOT_FAIL+1))
             fi
        else
             STATS_SERVER_PORT_853[$ip]="SKIPPED"
             tls853_res_term="${GRAY}SKIP${NC}"
        fi

        # 1.2 Attributes (Version, Recursion)
        if [[ "$CHECK_BIND_VERSION" == "true" ]]; then 
             local cmd_ver="dig @$ip version.bind chaos txt +time=$TIMEOUT"
             local out_ver_full=$($cmd_ver 2>&1)
             # Extract short version for logic
             local out_ver=$(echo "$out_ver_full" | grep "TXT" | grep "version.bind" | awk -F'"' '{print $2}')
             
             log_tech_details "ver_$ip" "Bind Version Check: $ip" "$out_ver_full"
             
             if [[ -z "$out_ver" || "$out_ver" == "" ]]; then 
                 ver_res_html="<span class='badge status-ok' style='cursor:pointer' onclick=\"showLog('ver_$ip')\">HIDDEN</span>"
                 ver_res_term="${GREEN}HIDDEN${NC}"
                 STATS_SERVER_VERSION[$ip]="HIDDEN"
                 SEC_HIDDEN=$((SEC_HIDDEN+1))
             else 
                 ver_res_html="<span class='badge status-fail' style='cursor:pointer' onclick=\"showLog('ver_$ip')\" title='$out_ver'>REVEA.</span>"
                 ver_res_term="${RED}REVEALED${NC}"
                 STATS_SERVER_VERSION[$ip]="REVEALED"
                 SEC_REVEALED=$((SEC_REVEALED+1))
             fi
        else
             STATS_SERVER_VERSION[$ip]="SKIPPED"
             ver_res_term="${GRAY}SKIP${NC}"
        fi
        
        if [[ "$ENABLE_RECURSION_CHECK" == "true" ]]; then
             local cmd_rec="dig @$ip google.com A +recurse +time=$TIMEOUT +tries=1"
             local out_rec=$($cmd_rec 2>&1)
             log_tech_details "rec_$ip" "Recursion Check: $ip" "$out_rec"

             if echo "$out_rec" | grep -q "status: REFUSED" || echo "$out_rec" | grep -q "recursion requested but not available"; then
                 rec_res_html="<span class='badge status-ok' style='cursor:pointer' onclick=\"showLog('rec_$ip')\">CLOSED</span>"
                 rec_res_term="${GREEN}CLOSED${NC}"
                 STATS_SERVER_RECURSION[$ip]="CLOSED"
                 SEC_REC_OK=$((SEC_REC_OK+1))
             elif echo "$out_rec" | grep -q "status: NOERROR"; then
                 rec_res_html="<span class='badge status-fail' style='cursor:pointer' onclick=\"showLog('rec_$ip')\">OPEN</span>"
                 rec_res_term="${RED}OPEN${NC}"
                 STATS_SERVER_RECURSION[$ip]="OPEN"
                 SEC_REC_RISK=$((SEC_REC_RISK+1))
             else
                 rec_res_html="<span class='badge status-warn' style='cursor:pointer' onclick=\"showLog('rec_$ip')\">UNK</span>"
                 rec_res_term="${YELLOW}UNK${NC}"
                 STATS_SERVER_RECURSION[$ip]="UNKNOWN"
             fi
        else
             STATS_SERVER_RECURSION[$ip]="SKIPPED"
             rec_res_term="${GRAY}SKIP${NC}"
        fi

        # 1.3 Capabilities (EDNS, Cookie)
        if [[ "$ENABLE_EDNS_CHECK" == "true" ]]; then
             if dig +edns=0 +noall +comments @$ip $probe_target +time=$TIMEOUT | grep -q "EDNS: version: 0"; then
                 edns_res_html="<span class='badge status-ok'>OK</span>"
                 edns_res_term="${GREEN}OK${NC}"
                 STATS_SERVER_EDNS[$ip]="OK"
                 EDNS_SUCCESS=$((EDNS_SUCCESS+1)); CACHE_EDNS_STATUS[$ip]="OK"
             else 
                 edns_res_html="<span class='badge status-fail'>FAIL</span>"
                 edns_res_term="${RED}FAIL${NC}"
                 STATS_SERVER_EDNS[$ip]="FAIL"
                 EDNS_FAIL=$((EDNS_FAIL+1)); CACHE_EDNS_STATUS[$ip]="FAIL"
             fi
        else
             STATS_SERVER_EDNS[$ip]="SKIPPED"
             edns_res_term="${GRAY}SKIP${NC}"
        fi
        
        if [[ "$ENABLE_COOKIE_CHECK" == "true" ]]; then
             if dig +cookie +noall +comments @$ip $probe_target +time=$TIMEOUT | grep -q "COOKIE:"; then
                 cookie_res_html="<span class='badge status-ok'>OK</span>"
                 cookie_res_term="${GREEN}OK${NC}"
                 STATS_SERVER_COOKIE[$ip]="OK"
                 COOKIE_SUCCESS=$((COOKIE_SUCCESS+1)); CACHE_COOKIE_STATUS[$ip]="OK"
             else 
                 cookie_res_html="<span class='badge status-neutral'>NO</span>"
                 cookie_res_term="${YELLOW}NO${NC}"
                 STATS_SERVER_COOKIE[$ip]="ABSENT"
                 COOKIE_FAIL=$((COOKIE_FAIL+1)); CACHE_COOKIE_STATUS[$ip]="ABSENT"
             fi
        fi
        
        # 1.4 Security & Modern (DNSSEC, DoH, TLS)
        if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
             # Only check validation if server is Recursive (OPEN) or UNKNOWN.
             # If CLOSED (Authoritative), it won't validate, so mark N/A.
             if [[ "${STATS_SERVER_RECURSION[$ip]}" == "CLOSED" ]]; then
                 STATS_SERVER_DNSSEC[$ip]="NA"
                 dnssec_res_html="<span class='badge neutral' title='Authoritative Only'>N/A (Auth)</span>"
             elif check_dnssec_validation "$ip"; then
                 STATS_SERVER_DNSSEC[$ip]="OK"
                 DNSSEC_SUCCESS=$((DNSSEC_SUCCESS+1))
                 dnssec_res_html="<span class='badge status-ok'>VALIDATING</span>"
             else
                 STATS_SERVER_DNSSEC[$ip]="FAIL" 
                 DNSSEC_FAIL=$((DNSSEC_FAIL+1))
                 dnssec_res_html="<span class='badge status-fail'>FAIL</span>"
             fi
        else STATS_SERVER_DNSSEC[$ip]="SKIP"; fi
        
        if [[ "$ENABLE_DOH_CHECK" == "true" ]]; then
             if check_doh_avail "$ip"; then
                 STATS_SERVER_DOH[$ip]="OK"
                 DOH_SUCCESS=$((DOH_SUCCESS+1))
                 doh_res_html="<span class='badge status-ok'>AVAILABLE</span>"
             else
                 STATS_SERVER_DOH[$ip]="FAIL"
                 DOH_FAIL=$((DOH_FAIL+1))
                 doh_res_html="<span class='badge status-fail'>FAIL</span>"
             fi
        else STATS_SERVER_DOH[$ip]="SKIP"; fi
        
        if [[ "$ENABLE_TLS_CHECK" == "true" ]]; then
             if check_tls_handshake "$ip"; then
                 STATS_SERVER_TLS[$ip]="OK"
                 TLS_SUCCESS=$((TLS_SUCCESS+1))
                 tls_res_html="<span class='badge status-ok'>OK</span>"
             else
                 STATS_SERVER_TLS[$ip]="FAIL"
                 TLS_FAIL=$((TLS_FAIL+1))
                 tls_res_html="<span class='badge status-fail'>FAIL</span>"
             fi
        else STATS_SERVER_TLS[$ip]="SKIP"; fi
        
        # Ping Count
        [[ "$ENABLE_PING" == "true" ]] && CNT_TESTS_SRV=$((CNT_TESTS_SRV+1))
        # Port 53
        CNT_TESTS_SRV=$((CNT_TESTS_SRV+1))
        # Port 853
        [[ "$ENABLE_DOT_CHECK" == "true" ]] && CNT_TESTS_SRV=$((CNT_TESTS_SRV+1))
        # Version
        [[ "$CHECK_BIND_VERSION" == "true" ]] && CNT_TESTS_SRV=$((CNT_TESTS_SRV+1))
        # Recursion
        [[ "$ENABLE_RECURSION_CHECK" == "true" ]] && CNT_TESTS_SRV=$((CNT_TESTS_SRV+1))
        # EDNS
        [[ "$ENABLE_EDNS_CHECK" == "true" ]] && CNT_TESTS_SRV=$((CNT_TESTS_SRV+1))
        # Cookie
        [[ "$ENABLE_COOKIE_CHECK" == "true" ]] && CNT_TESTS_SRV=$((CNT_TESTS_SRV+1))
        # DNSSEC
        [[ "$ENABLE_DNSSEC_CHECK" == "true" ]] && CNT_TESTS_SRV=$((CNT_TESTS_SRV+1))
        # DoH
        [[ "$ENABLE_DOH_CHECK" == "true" ]] && CNT_TESTS_SRV=$((CNT_TESTS_SRV+1))

        # ADD ROW
        echo "<tr><td>$ip</td><td>$grps</td><td>$ping_res_html</td><td>$hops_html</td><td>$lat_stats</td><td>$tcp53_res_html</td><td>$tls853_res_html</td><td>$ver_res_html</td><td>$rec_res_html</td><td>$edns_res_html</td><td>$cookie_res_html</td><td>$dnssec_res_html</td><td>$doh_res_html</td><td>$tls_res_html</td></tr>" >> "$TEMP_SECTION_SERVER"
        
        # CSV Export Server
        if [[ "$ENABLE_CSV_REPORT" == "true" ]]; then
            local csv_ts=$(date "+%Y-%m-%d %H:%M:%S")
            echo "$csv_ts;$ip;$grps;${STATS_SERVER_PING_STATUS[$ip]};${STATS_SERVER_PING_AVG[$ip]};${STATS_SERVER_PING_JITTER[$ip]};${STATS_SERVER_PING_LOSS[$ip]};${STATS_SERVER_PORT_53[$ip]};${STATS_SERVER_PORT_853[$ip]};${STATS_SERVER_VERSION[$ip]};${STATS_SERVER_RECURSION[$ip]};${STATS_SERVER_EDNS[$ip]};${STATS_SERVER_COOKIE[$ip]};${STATS_SERVER_DNSSEC[$ip]};${STATS_SERVER_DOH[$ip]};${STATS_SERVER_TLS[$ip]}" >> "$LOG_FILE_CSV_SRV"
        fi
        
        # Prepare Output Terms for new checks
        local dnssec_term="${GRAY}SKIP${NC}"
        if [[ "${STATS_SERVER_DNSSEC[$ip]}" == "OK" ]]; then dnssec_term="${GREEN}OK${NC}"; fi
        if [[ "${STATS_SERVER_DNSSEC[$ip]}" == "FAIL" ]]; then dnssec_term="${RED}FAIL${NC}"; fi
        if [[ "${STATS_SERVER_DNSSEC[$ip]}" == "NA" ]]; then dnssec_term="${YELLOW}N/A${NC}"; fi
        
        local doh_term="${GRAY}SKIP${NC}"; [[ "${STATS_SERVER_DOH[$ip]}" == "OK" ]] && doh_term="${GREEN}OK${NC}"
        [[ "${STATS_SERVER_DOH[$ip]}" == "FAIL" ]] && doh_term="${RED}FAIL${NC}"
        
        local tls_term="${GRAY}SKIP${NC}"; [[ "${STATS_SERVER_TLS[$ip]}" == "OK" ]] && tls_term="${GREEN}OK${NC}"
        [[ "${STATS_SERVER_TLS[$ip]}" == "FAIL" ]] && tls_term="${RED}FAIL${NC}"

        echo -e "     Ping:${ping_res_term} | TCP53:${tcp53_res_term} | DoT_TCP853:${tls853_res_term} | Ver:${ver_res_term} | Rec:${rec_res_term} | EDNS:${edns_res_term} | Cookie:${cookie_res_term} | DNSSEC:${dnssec_term} | DoH:${doh_term} | TLS:${tls_term}"

        # --- JSON Export (Ping) ---
        if [[ "$ENABLE_JSON_REPORT" == "true" ]]; then
             # Ping JSON
             echo "{ \"server\": \"$ip\", \"groups\": \"$grps\", \"min\": \"${STATS_SERVER_PING_MIN[$ip]}\", \"avg\": \"${STATS_SERVER_PING_AVG[$ip]}\", \"max\": \"${STATS_SERVER_PING_MAX[$ip]}\", \"loss\": \"${STATS_SERVER_PING_LOSS[$ip]}\" }," >> "$TEMP_JSON_Ping"
             
             # Security/Caps JSON
             # Clean HTML tags for JSON
             local j_ver=$(echo "${STATS_SERVER_VERSION[$ip]}")
             local j_rec=$(echo "${STATS_SERVER_RECURSION[$ip]}")
             local j_edns=$(echo "${STATS_SERVER_EDNS[$ip]}")
             local j_cook=$(echo "${STATS_SERVER_COOKIE[$ip]}")
             local j_p53=$(echo "${STATS_SERVER_PORT_53[$ip]}")
             local j_p853=$(echo "${STATS_SERVER_PORT_853[$ip]}")
             
             echo "{ \"server\": \"$ip\", \"groups\": \"$grps\", \"version\": \"$j_ver\", \"recursion\": \"$j_rec\", \"edns\": \"$j_edns\", \"cookie\": \"$j_cook\", \"port53\": \"$j_p53\", \"port853\": \"$j_p853\" }," >> "$TEMP_JSON_Sec"
        fi
    done
    
    echo "</tbody></table></div></div>" >> "$TEMP_SECTION_SERVER"
}

# --- 2. ZONE TESTS ---
run_zone_tests() {
    echo -e "\n${BLUE}=== FASE 2: TESTES DE ZONA (SOA, AXFR) ===${NC}"
    log_section "PHASE 2: ZONE TESTS"
    
    local zone_count=0
    [[ -f "$FILE_DOMAINS" ]] && zone_count=$(grep -vE '^\s*#|^\s*$' "$FILE_DOMAINS" | wc -l)
    echo "  Identificadas ${zone_count} zonas únicas para teste."
    echo "  Legend: [SOA] [AXFR] [DNSSEC]"
    
    # Global Stats Arrays
    declare -gA STATS_ZONE_AXFR
    declare -gA STATS_ZONE_SOA
    declare -gA STATS_ZONE_DNSSEC
    
    # START ZONE HTML SECTION
    cat >> "$TEMP_SECTION_ZONE" << EOF
    <div style="margin-top: 50px;">
        <h2>🌎 Saúde das Zonas (Consistência & Segurança)</h2>
        <div class="table-responsive">
        <table>
            <thead>
                <tr>
                    <th>Zona</th>
                    <th>Grupo</th>
                    <th>Servidor</th>
                    <th>SOA Serial</th>
                    <th>AXFR Status</th>
                    <th>DNSSEC Sig</th>
                </tr>
            </thead>
            <tbody>
EOF
    
    # Unique domains processing
    # Create temp file for unique sorting (preserving comments separate if needed, but for execution we just want unique targets)
    declare -g sorted_domains=$(grep -vE '^\s*#|^\s*$' "$FILE_DOMAINS" | sort -u)
    
    # Process line by line from variable
    while IFS=';' read -r domain groups _ _ _; do
        [[ -z "$domain" || "$domain" =~ ^# ]] && continue
        domain=$(echo "$domain" | xargs)
        IFS=',' read -ra grp_list <<< "$groups"
        
        echo -e "  🌎 ${CYAN}Zone:${NC} $domain"
        
        for grp in "${grp_list[@]}"; do
             # Get servers
             local srvs=${DNS_GROUPS[$grp]}
             [[ -z "$srvs" ]] && continue
             
             # Calculate SOA for Group (First pass)
             local first_serial=""
             local is_signed_zone="false"
             declare -A SERVER_SERIALS
             declare -A SERVER_AXFR
             declare -A SERVER_DNSSEC_SIG
             
             for srv in $srvs; do
                  # SOA
                  local serial="ERR"
                  if [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" ]]; then
                       # Capture stderr to null, take head -1, strictly numeric
                       serial=$(dig +short +time=$TIMEOUT @$srv $domain SOA 2>/dev/null | head -1 | awk '{print $3}')
                       
                       # Validate numeric
                       if [[ ! "$serial" =~ ^[0-9]+$ ]]; then
                           # If empty, likely timeout. If text, likely parsing error.
                           if [[ -z "$serial" ]]; then serial="TIMEOUT"; else serial="ERR"; fi
                       fi
                       
                       SERVER_SERIALS[$srv]="$serial"
                       STATS_ZONE_SOA["$domain|$grp|$srv"]="$serial"
                       if [[ -z "$first_serial" && "$serial" != "TIMEOUT" ]]; then first_serial="$serial"; fi
                  else
                       SERVER_SERIALS[$srv]="N/A"
                       STATS_ZONE_SOA["$domain|$grp|$srv"]="N/A"
                  fi
                  
                  # Log SOA
                  log_tech_details "soa_${domain}_${srv}" "SOA Check: $domain @ $srv" "$(dig +short @$srv $domain SOA 2>&1)"
                  
                  # AXFR
                  local axfr_stat="N/A"
                  local axfr_raw="SKIPPED"
                  if [[ "$ENABLE_AXFR_CHECK" == "true" ]]; then
                      local out_axfr=$(dig @$srv $domain AXFR +time=$TIMEOUT +tries=1)
                      if echo "$out_axfr" | grep -q "Refused" || echo "$out_axfr" | grep -q "Transfer failed"; then
                          axfr_stat="<span class='badge status-ok'>DENIED</span>"
                          axfr_raw="DENIED"
                          SEC_AXFR_OK=$((SEC_AXFR_OK+1))
                      elif echo "$out_axfr" | grep -q "SOA"; then
                          axfr_stat="<span class='badge status-fail'>ALLOWED</span>"
                          axfr_raw="ALLOWED"
                          SEC_AXFR_RISK=$((SEC_AXFR_RISK+1))
                      else
                          axfr_stat="<span class='badge status-warn'>TIMEOUT/ERR</span>"
                          axfr_raw="TIMEOUT"
                          SEC_AXFR_TIMEOUT=$((SEC_AXFR_TIMEOUT+1))
                      fi
                      CNT_TESTS_ZONE=$((CNT_TESTS_ZONE+1))
                      # Log AXFR
                      log_tech_details "axfr_${domain}_${srv}" "AXFR Check: $domain @ $srv" "$out_axfr"
                  fi
                  
                  # DNSSEC Signature Check (Smart Detection)
                  local sig_res="UNSIGNED"
                  if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
                       local out_sig=$(dig +dnssec +noall +answer @$srv $domain SOA +time=$TIMEOUT)
                       if echo "$out_sig" | grep -q "RRSIG"; then
                            sig_res="SIGNED"
                            is_signed_zone="true"
                       fi
                       CNT_TESTS_ZONE=$((CNT_TESTS_ZONE+1))
                  fi
                  SERVER_DNSSEC_SIG[$srv]="$sig_res"
                  
                  # SOA Count
                  [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" ]] && CNT_TESTS_ZONE=$((CNT_TESTS_ZONE+1))
                  SERVER_AXFR[$srv]="$axfr_stat"
                  STATS_ZONE_AXFR["$domain|$grp|$srv"]="$axfr_raw"
                  STATS_ZONE_DNSSEC["$domain|$grp|$srv"]="$sig_res"
             done

             # Add Rows
             for srv in $srvs; do
                 local serial=${SERVER_SERIALS[$srv]}
                 local ser_html="$serial"
                 if [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" ]]; then
                     if [[ "$serial" == "TIMEOUT" ]]; then
                         ser_html="<span class='badge neutral'>TIMEOUT</span>"
                     elif [[ "$serial" == "N/A" ]]; then
                         ser_html="<span class='badge neutral'>N/A</span>"
                     elif [[ "$serial" == "$first_serial" ]]; then
                         ser_html="<span class='badge status-ok' title='Synced'>$serial</span>"
                         SOA_SYNC_OK=$((SOA_SYNC_OK+1))
                     else
                         ser_html="<span class='badge status-fail' title='Divergent'>$serial</span>"
                         SOA_SYNC_FAIL=$((SOA_SYNC_FAIL+1))
                     fi
                 fi
                 
                 local sig_status=${SERVER_DNSSEC_SIG[$srv]}
                 local sig_html="<span class='badge neutral'>N/A</span>"
                 
                 if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
                      if [[ "$is_signed_zone" == "true" ]]; then
                          if [[ "$sig_status" == "SIGNED" ]]; then
                               sig_html="<span class='badge status-ok'>SIGNED</span>"
                               ZONE_SEC_SIGNED=$((ZONE_SEC_SIGNED+1))
                          else
                               sig_html="<span class='badge status-fail'>MISSING</span>"
                               ZONE_SEC_UNSIGNED=$((ZONE_SEC_UNSIGNED+1))
                          fi
                      else
                          sig_html="<span class='badge neutral'>UNSIGNED</span>"
                      fi
                 fi
                 
                 echo "<tr><td>$domain</td><td>$grp</td><td>$srv</td><td>$ser_html</td><td>${SERVER_AXFR[$srv]}</td><td>${sig_html}</td></tr>" >> "$TEMP_SECTION_ZONE"
                 
                 # CSV Export Zone
                 if [[ "$ENABLE_CSV_REPORT" == "true" ]]; then
                      local csv_ts=$(date "+%Y-%m-%d %H:%M:%S")
                      # Clean AXFR status (remove html tags)
                      local clean_axfr=$(echo "${SERVER_AXFR[$srv]}" | sed 's/<[^>]*>//g')
                      echo "$csv_ts;$domain;$srv;$grp;$serial;$clean_axfr;$sig_status" >> "$LOG_FILE_CSV_ZONE"
                 fi
                 
                 # Term Output
                 local term_soa="$serial"
                 [[ "$serial" == "$first_serial" ]] && term_soa="${GREEN}$serial${NC}" || term_soa="${RED}$serial${NC}"
                 [[ "$serial" == "TIMEOUT" ]] && term_soa="${YELLOW}TIMEOUT${NC}"
                 
                 local term_axfr="${SERVER_AXFR[$srv]}"
                 # Simple AXFR status for term
                 if [[ "$term_axfr" == *"DENIED"* ]]; then term_axfr="${GREEN}DENIED${NC}"
                 elif [[ "$term_axfr" == *"ALLOWED"* ]]; then term_axfr="${RED}ALLOWED${NC}"
                 else term_axfr="${YELLOW}TIMEOUT${NC}"; fi
                 
                 local term_sig=""
                 if [[ "$ENABLE_DNSSEC_CHECK" == "true" ]]; then
                      if [[ "$is_signed_zone" == "true" ]]; then
                           [[ "$sig_status" == "SIGNED" ]] && term_sig="${GREEN}[SIG:OK]${NC}" || term_sig="${RED}[SIG:FAIL]${NC}"
                      else
                           term_sig="${YELLOW}[UNSIGNED]${NC}"
                      fi
                 fi
                 
                 echo -e "     🏢 Grupo: $grp -> $srv : SOA[$term_soa] AXFR[$term_axfr] $term_sig"
             done
         done
    done < "$FILE_DOMAINS"
    
    echo "</tbody></table></div></div>" >> "$TEMP_SECTION_ZONE"
}

# --- 3. RECORD TESTS ---
run_record_tests() {
    echo -e "\n${BLUE}=== FASE 3: TESTES DE REGISTROS (Resolução e Consistência) ===${NC}"
    log_section "PHASE 3: RECORD TESTS"
    
    local rec_count=0
     if [[ -f "$FILE_DOMAINS" ]]; then
        rec_count=$(awk -F';' '!/^#/ && !/^\s*$/ { 
            n_recs = split($4, a, ",");
            n_extras = 0;
            # remove CR/LF/Spaces
            gsub(/[[:space:]]/, "", $5);
            if (length($5) > 0) n_extras = split($5, b, ",");
            count += n_recs * (1 + n_extras) 
        } END { print count }' "$FILE_DOMAINS")
     fi
    [[ -z "$rec_count" ]] && rec_count=0
    echo "  Identificados ${rec_count} registros únicos para teste."
    echo -e "  Legend: [Status] [Inconsistency=Differs from Group]"
    
    # Global Stats Arrays for Records
    declare -gA STATS_RECORD_RES      # Status code
    declare -gA STATS_RECORD_ANSWER   # Actual data for comparison
    declare -gA STATS_RECORD_LATENCY  
    declare -gA STATS_RECORD_CONSISTENCY # Per Record|Group -> CONSISTENT/DIVERGENT
    declare -gA STATS_RECORD_DIV_COUNT   # Per Record|Group -> Number of unique answers
    
    # START RECORD HTML SECTION
    cat >> "$TEMP_SECTION_RECORD" << EOF
    <div style="margin-top: 50px;">
        <h2>🔍 Validação de Registros (Records)</h2>
        <div class="table-responsive">
        <table>
            <thead>
                <tr>
                    <th>Zona</th>
                    <th>Tipo</th>
                    <th>Grupo</th>
EOF
    # We don't know number of servers per group easily for header, implies flexible columns or vertical list
    cat >> "$TEMP_SECTION_RECORD" << EOF
                    <th>Resultados (Por Servidor)</th>
                </tr>
            </thead>
            <tbody>
EOF

    while IFS=';' read -r domain groups test_types record_types extra_hosts; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra grp_list <<< "$groups"
        
        IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
        local targets=("$domain")
        for h in "${extra_list[@]}"; do
            [[ -n "$h" ]] && targets+=("$h.$domain")
        done
        
        for target in "${targets[@]}"; do
            # Use target for display and testing
            
            for rec_type in "${rec_list[@]}"; do
                rec_type=${rec_type^^} # Uppercase
                echo -e "  🔍 ${CYAN}$target${NC} IN ${PURPLE}$rec_type${NC}"
                
                for grp in "${grp_list[@]}"; do
                    local srv_list=${DNS_GROUPS[$grp]}
                    
                    # Consistency Tracking (List based - Robust)
                    local ANSWERS_LIST_RAW=""
                    
                    # Legend moved to start of phase
                    
                    # Build server results HTML
                    local results_html=""
                    # Buffer for terminal output
                    local term_output_buffer=()
                    
                    for srv in $srv_list; do
                         CNT_TESTS_REC=$((CNT_TESTS_REC + 1))
                         
                         # Uses full output to capture Status and Answer
                         local out_full
                         out_full=$(dig +tries=1 +time=$TIMEOUT @$srv $target $rec_type 2>&1)
                         local ret=$?
                         
                         # Log Raw Output
                         local safe_target=${target//./_}
                         local safe_srv=${srv//./_}
                         log_tech_details "rec_${safe_target}_${rec_type}_${safe_srv}" "DIG: $target ($rec_type) @ $srv" "$out_full"
                         
                         # Extract status
                         local status="UNKNOWN"
                         if [[ $ret -ne 0 ]]; then status="ERR:$ret"; CNT_NETWORK_ERROR=$((CNT_NETWORK_ERROR + 1));
                         elif echo "$out_full" | grep -q "status: NOERROR"; then status="NOERROR"; CNT_NOERROR=$((CNT_NOERROR + 1));
                         elif echo "$out_full" | grep -q "status: NXDOMAIN"; then status="NXDOMAIN"; CNT_NXDOMAIN=$((CNT_NXDOMAIN + 1));
                         elif echo "$out_full" | grep -q "status: SERVFAIL"; then status="SERVFAIL"; CNT_SERVFAIL=$((CNT_SERVFAIL + 1));
                         elif echo "$out_full" | grep -q "status: REFUSED"; then status="REFUSED"; CNT_REFUSED=$((CNT_REFUSED + 1));
                         elif echo "$out_full" | grep -q "connection timed out"; then status="TIMEOUT"; CNT_TIMEOUT=$((CNT_TIMEOUT + 1));
                         else status="OTHER"; CNT_OTHER_ERROR=$((CNT_OTHER_ERROR + 1)); fi
                         
                         # Extract Answer Data for comparison (Sort to handle RRset order)
                         local answer_data=""
                         if [[ "$status" == "NOERROR" ]]; then
                            answer_data=$(echo "$out_full" | grep -A 20 ";; ANSWER SECTION:" | grep -v ";; ANSWER SECTION:" | sed '/^$/d' | grep -v ";;" | sort | awk '{$1=$2=$3=$4=""; print $0}' | xargs)
                         else
                            answer_data="STATUS:$status"
                         fi
                         
                         local comparison_data="$answer_data"
                         if [[ "$rec_type" == "SOA" && "$status" == "NOERROR" ]]; then
                             # For SOA, extract strict Serial (usually 3rd field in parsed answer: MNAME RNAME SERIAL...)
                             # answer_data is typically: "ns1.host.com. dns.host.com. 2023122001 7200..."
                             comparison_data=$(echo "$answer_data" | awk '{print $3}')
                         fi
                         
                         # Store Result Globally (Using target instead of domain key)
                         STATS_RECORD_RES["$target|$rec_type|$grp|$srv"]="$status"
                         STATS_RECORD_ANSWER["$target|$rec_type|$grp|$srv"]="$answer_data"
                         
                         # Map answer to server for consistency check (Use Base64 key to avoid special char issues)
                         local ans_key=$(echo -n "$comparison_data" | base64 -w0)
                         ANSWERS_LIST_RAW+="$ans_key"$'\n'
    
                         # Extract Latency
                         local dur=$(echo "$out_full" | grep "Query time:" | awk '{print $4}')
                         [[ -z "$dur" ]] && dur=0
                         STATS_RECORD_LATENCY["$target|$rec_type|$grp|$srv"]="$dur"
                         
                         # Extract short answer for display (Badge Title & Terminal)
                         local badge_title="Status: $status"
                         local term_extra=""
                         if [[ -n "$answer_data" && "$status" == "NOERROR" ]]; then
                            badge_title="$answer_data"
                            term_extra=""
                         fi
                         
                         # Generate HTML & Counters
                         local term_line=""
                         if [[ "$status" == "NOERROR" ]]; then
                             results_html+="<span class='badge status-ok' title='$srv: $badge_title'>$srv: OK</span> "
                             term_line="     💻 $srv ($grp) : ${GREEN}OK${NC}$term_extra"
                             SUCCESS_TESTS=$((SUCCESS_TESTS + 1))
                         elif [[ "$status" == "NXDOMAIN" ]]; then
                             results_html+="<span class='badge status-warn' title='$srv: NXDOMAIN'>$srv: NX</span> "
                             term_line="     💻 $srv ($grp) : ${YELLOW}NXDOMAIN${NC}"
                             SUCCESS_TESTS=$((SUCCESS_TESTS + 1))
                         else
                             results_html+="<span class='badge status-fail' title='$srv: $status'>$srv: ERR</span> "
                             term_line="     💻 $srv ($grp) : ${RED}FAIL ($status)${NC}"
                             FAILED_TESTS=$((FAILED_TESTS + 1))
                         fi
                         term_output_buffer+=("$term_line")
                         
                         # --- CSV EXPORT (Restored) ---
                         if [[ "$ENABLE_CSV_REPORT" == "true" ]]; then
                             local csv_ts=$(date "+%Y-%m-%d %H:%M:%S")
                             local dur=$(echo "$out_full" | grep "Query time:" | awk '{print $4}')
                             [[ -z "$dur" ]] && dur=0
                             
                             # Clean answer snippet (remove newlines/special chars)
                             local clean_ans=$(echo "${answer_data}" | tr -d '\n\r;' | cut -c1-100)
                             
                             echo "$csv_ts;$target;$rec_type;$grp;$srv;$status;$dur;$clean_ans" >> "$LOG_FILE_CSV_REC"
                         fi
                         
                         # --- JSON EXPORT (Restored) ---
                         if [[ "$ENABLE_JSON_REPORT" == "true" ]]; then
                             local dur=$(echo "$out_full" | grep "Query time:" | awk '{print $4}')
                             [[ -z "$dur" ]] && dur=0
                             echo "{ \"domain\": \"$target\", \"group\": \"$grp\", \"server\": \"$srv\", \"record\": \"$rec_type\", \"status\": \"$status\", \"latency_ms\": $dur }," >> "$TEMP_JSON_DNS"
                         fi
    
                    done
                    # Consistency Analysis for Group
                    local unique_answers=$(echo -n "$ANSWERS_LIST_RAW" | sort -u | sed '/^$/d' | wc -l)
                    STATS_RECORD_DIV_COUNT["$target|$rec_type|$grp"]=$unique_answers
                    
                    if [[ $unique_answers -gt 1 ]]; then
                         STATS_RECORD_CONSISTENCY["$target|$rec_type|$grp"]="DIVERGENT"
                         DIVERGENT_TESTS=$((DIVERGENT_TESTS + 1))
                         results_html+="<span class='badge status-fail' style='margin-left:10px;'>DIVERGENT ($unique_answers)</span>"
                         
                         # Print buffered lines with [D] appended
                         for line in "${term_output_buffer[@]}"; do
                             echo -e "${line} ${RED}[Inconsistente]${NC}"
                         done
                    else
                         STATS_RECORD_CONSISTENCY["$target|$rec_type|$grp"]="CONSISTENT"
                         # Print buffered lines normally
                         for line in "${term_output_buffer[@]}"; do
                             echo -e "$line"
                         done
                    fi
                    
                    # Add row to HTML
                    echo "<tr><td>$target</td><td>$rec_type</td><td>$grp</td><td>$results_html</td></tr>" >> "$TEMP_SECTION_RECORD"
                done
            done
        done
    done < "$FILE_DOMAINS"
    echo ""
    
    echo "</tbody></table></div></div>" >> "$TEMP_SECTION_RECORD"
}

main() {
    START_TIME_EPOCH=$(date +%s); START_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S")

    # Define cleanup trap
    trap 'rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS" "$TEMP_PING" "$TEMP_TRACE" "$TEMP_CONFIG" "$TEMP_TIMING" "$TEMP_MODAL" "$TEMP_DISCLAIMER" "$TEMP_SERVICES" "$LOG_OUTPUT_DIR/temp_help_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_obj_summary_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_svc_table_${SESSION_ID}.html" "$TEMP_TRACE_SIMPLE" "$TEMP_PING_SIMPLE" "$TEMP_MATRIX_SIMPLE" "$TEMP_SERVICES_SIMPLE" "$LOG_OUTPUT_DIR/temp_domain_body_simple_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_group_body_simple_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_security_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_security_simple_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_sec_rows_${SESSION_ID}.html" "$TEMP_JSON_Ping" "$TEMP_JSON_DNS" "$TEMP_JSON_Sec" "$TEMP_JSON_Trace" "$TEMP_JSON_DOMAINS" "$LOG_OUTPUT_DIR/temp_chart_${SESSION_ID}.js" "$TEMP_HEALTH_MAP" "$TEMP_SECTION_SERVER" "$TEMP_SECTION_ZONE" "$TEMP_SECTION_RECORD" "$TEMP_FULL_LOG" 2>/dev/null' EXIT

    while getopts ":n:g:lhyjstdxrTVZMvq" opt; do case ${opt} in 
        n) FILE_DOMAINS=$OPTARG ;; 
        g) FILE_GROUPS=$OPTARG ;; 
        l) ENABLE_LOG_TEXT="true" ;; 
        y) INTERACTIVE_MODE="false" ;; 
        j) ENABLE_JSON_REPORT="true" ;;
        t) ENABLE_TCP_CHECK="true" ;;
        d) ENABLE_DNSSEC_CHECK="true" ;;
        x) ENABLE_AXFR_CHECK="true" ;;
        r) ENABLE_RECURSION_CHECK="true" ;;

        V) CHECK_BIND_VERSION="true" ;;
        Z) ENABLE_SOA_SERIAL_CHECK="true" ;;
        M) # Enable All Modern
           ENABLE_EDNS_CHECK="true"
           ENABLE_COOKIE_CHECK="true"
           ENABLE_QNAME_CHECK="true"
           ENABLE_TLS_CHECK="true"
           ENABLE_DOT_CHECK="true"
           ENABLE_DOH_CHECK="true"
           ;;
        v) VERBOSE_LEVEL=$((VERBOSE_LEVEL + 1)) ;; # Increment verbose
        q) VERBOSE_LEVEL=0 ;; # Quiet
        h) show_help; exit 0 ;; 
        *) echo "Opção inválida"; exit 1 ;; 
    esac; done

    if ! command -v dig &> /dev/null; then echo "Erro: 'dig' nao encontrado."; exit 1; fi
    if ! command -v timeout &> /dev/null; then echo "Erro: 'timeout' nao encontrado (necessario para checks)."; exit 1; fi
    if [[ "$ENABLE_PING" == "true" ]] && ! command -v ping &> /dev/null; then echo "Erro: 'ping' nao encontrado (necessario para -t/Ping)."; exit 1; fi

    
    init_log_file
    validate_csv_files
    
    interactive_configuration
    
    resolve_configuration
    
    # Init and Validation
    validate_dig_capabilities
    
    # Capture initial preference for charts logic
    INITIAL_ENABLE_CHARTS="$ENABLE_CHARTS"
    
    [[ "$INTERACTIVE_MODE" == "false" ]] && print_execution_summary
    
    # ==========================
    # NEW EXECUTION FLOW
    # ==========================
    init_html_parts
    write_html_header
    load_dns_groups
    
    # 1. SERVER Phase
    if [[ "$ENABLE_PHASE_SERVER" == "true" ]]; then
        run_server_tests
    fi
    
    # 2. ZONE Phase
    if [[ "$ENABLE_PHASE_ZONE" == "true" ]]; then
        run_zone_tests
    fi
    
    # 3. RECORD Phase
    if [[ "$ENABLE_PHASE_RECORD" == "true" ]]; then
        run_record_tests
    fi
    
    # LEGACY CALLS REMOVED 
    # process_tests; run_ping_diagnostics; run_trace_diagnostics; run_security_diagnostics

    END_TIME_EPOCH=$(date +%s); END_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S"); TOTAL_DURATION=$((END_TIME_EPOCH - START_TIME_EPOCH))
    
    if [[ -z "$TOTAL_SLEEP_TIME" ]]; then TOTAL_SLEEP_TIME=0; fi
    TOTAL_SLEEP_TIME=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", $TOTAL_SLEEP_TIME}")

    [[ "$ENABLE_LOG_TEXT" == "true" ]] && echo "Execution finished" >> "$LOG_FILE_TEXT"
    
    # Calculate stats first via terminal summary (which calls hierarchical_stats)
    print_final_terminal_summary
    
    # Generate Config HTML for insertion
    generate_config_html
    
    # Then generate HTML with populated stats
    generate_html_report_v2
    
    if [[ "$ENABLE_JSON_REPORT" == "true" ]]; then
        assemble_json
    fi
    
    echo -e "\n${GREEN}=== CONCLUÍDO ===${NC}"
    echo "  📄 Relatório HTML   : $HTML_FILE"
    [[ "$ENABLE_JSON_REPORT" == "true" ]] && echo "  📄 Relatório JSON   : $LOG_FILE_JSON"
    if [[ "$ENABLE_CSV_REPORT" == "true" ]]; then
        echo "  📄 Relatório CSV (Srv) : $LOG_FILE_CSV_SRV"
        echo "  📄 Relatório CSV (Zone): $LOG_FILE_CSV_ZONE"
        echo "  📄 Relatório CSV (Rec) : $LOG_FILE_CSV_REC"
    fi
    [[ "$ENABLE_LOG_TEXT" == "true" ]] && echo "  📝 Log Texto        : $LOG_FILE_TEXT"

}

main "$@"
