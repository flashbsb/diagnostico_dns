#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS - EXECUTIVE EDITION
# Versão: 11.5.13
# "SOA Serial Strict Consistency"
# ==============================================

# --- CONFIGURAÇÕES GERAIS ---
SCRIPT_VERSION="11.5.13"

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
LOG_FILE_CSV="$LOG_OUTPUT_DIR/${LOG_PREFIX}_v${SCRIPT_VERSION}_${TIMESTAMP}.csv"

# Default Configuration
VERBOSE_LEVEL=1  # 0=Quiet, 1=Summary, 2=Verbose (Cmds), 3=Debug (Outs)
ENABLE_JSON_LOG="false"

# Extra Features Defaults
ENABLE_EDNS_CHECK="true"
ENABLE_COOKIE_CHECK="true"
ENABLE_QNAME_CHECK="true"
ENABLE_TLS_CHECK="true"
ENABLE_DOT_CHECK="true"
ENABLE_DOH_CHECK="true"

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
    
    # Init CSV
    if [[ "$ENABLE_CSV_REPORT" == "true" ]]; then
        echo "Timestamp;Grupo;Servidor;Dominio;Record;Status;Latencia_ms;Detalhes;TCP;DNSSEC;EDNS0;Cookie;TLS;DoT;DoH;QNAME" > "$LOG_FILE_CSV"
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

    echo -e "  🛡️ Version Check : ${CYAN}${CHECK_BIND_VERSION}${NC}"
    echo -e "  🛡️ AXFR Check    : ${CYAN}${ENABLE_AXFR_CHECK}${NC}"
    echo -e "  🛡️ Recurse Check : ${CYAN}${ENABLE_RECURSION_CHECK}${NC}"
    echo -e "  🛡️ SOA Sync Check: ${CYAN}${ENABLE_SOA_SERIAL_CHECK}${NC}"
    echo -e "  🛡️ Active Groups : ${CYAN}${ONLY_TEST_ACTIVE_GROUPS}${NC}"
    echo ""
    echo -e "${PURPLE}[MODERN & SECURITY]${NC}"
    echo -e "  🛡️ EDNS0 Check   : ${CYAN}${ENABLE_EDNS_CHECK}${NC}"
    echo -e "  🍪 Cookie Check  : ${CYAN}${ENABLE_COOKIE_CHECK}${NC}"
    echo -e "  📉 QNAME Min     : ${CYAN}${ENABLE_QNAME_CHECK}${NC}"
    echo -e "  🔐 TLS Connect   : ${CYAN}${ENABLE_TLS_CHECK}${NC}"
    echo -e "  🔒 DoT (Tls)     : ${CYAN}${ENABLE_DOT_CHECK}${NC}"
    echo -e "  🌐 DoH (Https)   : ${CYAN}${ENABLE_DOH_CHECK}${NC}"
    echo ""
    echo -e "${PURPLE}[CRITÉRIOS DE DIVERGÊNCIA]${NC}"
    echo -e "  🔢 Strict IP     : ${CYAN}${STRICT_IP_CHECK}${NC} (True = IP diferente diverge)"
    echo -e "  🔃 Strict Order  : ${CYAN}${STRICT_ORDER_CHECK}${NC} (True = Ordem diferente diverge)"
    echo -e "  ⏱️ Strict TTL    : ${CYAN}${STRICT_TTL_CHECK}${NC} (True = TTL diferente diverge)"
    echo ""
    echo -e "${PURPLE}[DEBUG & CONTROLE]${NC}"
    echo -e "  📢 Verbose Mode  : ${CYAN}${VERBOSE}${NC}"
    echo -e "  📝 Gerar Log TXT : ${CYAN}${ENABLE_LOG_TEXT}${NC}"
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
    echo -e "  📄 Relatório Detalhado: ${GREEN}$HTML_FILE${NC}"
    [[ "$ENABLE_JSON_REPORT" == "true" ]] && echo -e "  📄 Relatório JSON    : ${GREEN}${HTML_FILE%.html}.json${NC}"
    [[ "$ENABLE_CSV_REPORT" == "true" ]] && echo -e "  📄 Relatório CSV     : ${GREEN}$LOG_FILE_CSV${NC}"
    [[ "$ENABLE_LOG_TEXT" == "true" ]] && echo -e "  📄 Log Texto     : ${GREEN}$LOG_FILE_TEXT${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo ""
}

# ==============================================
# LOGGING (TEXTO)
# ==============================================

log_entry() {
    [[ "$ENABLE_LOG_TEXT" != "true" ]] && return
    local msg="$1"
    local ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[$ts] $msg" >> "$LOG_FILE_TEXT"
}

log_section() {
    [[ "$ENABLE_LOG_TEXT" != "true" ]] && return
    local title="$1"
    {
        echo ""
        echo "================================================================================"
        echo ">>> $title"
        echo "================================================================================"
    } >> "$LOG_FILE_TEXT"
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
        echo -e "\n${BLUE}--- CRITÉRIOS DE DIVERGÊNCIA (TOLERÂNCIA) ---${NC}"
        echo -e "${GRAY}(Se 'true', qualquer variação é marcada como divergente)${NC}"
        ask_boolean "Considerar mudança de IP como divergência?" "STRICT_IP_CHECK"
        ask_boolean "Considerar mudança de Ordem como divergência?" "STRICT_ORDER_CHECK"
        ask_boolean "Considerar mudança de TTL como divergência?" "STRICT_TTL_CHECK"
        
        echo -e "\n${BLUE}--- GERAL ---${NC}"
        ask_variable "Arquivo de Domínios (CSV)" "FILE_DOMAINS"
        ask_variable "Arquivo de Grupos (CSV)" "FILE_GROUPS"
        ask_variable "Diretório de Logs" "LOG_DIR"
        ask_variable "Prefixo arquivos Log" "LOG_PREFIX"
        ask_variable "Tentativas por Teste (Consistência)" "CONSISTENCY_CHECKS"
        ask_variable "Timeout Global (segundos)" "TIMEOUT"
        ask_variable "Sleep entre queries (segundos)" "SLEEP"
        ask_boolean "Validar conectividade porta 53?" "VALIDATE_CONNECTIVITY"
        ask_boolean "Verbose Debug?" "VERBOSE"
        ask_boolean "Gerar log texto?" "ENABLE_LOG_TEXT"
        ask_boolean "Habilitar Gráficos no HTML?" "ENABLE_CHARTS"
        ask_boolean "Gerar relatório JSON?" "ENABLE_JSON_REPORT"
        ask_boolean "Gerar relatório CSV (Plano)?" "ENABLE_CSV_REPORT"
        
        echo -e "\n${BLUE}--- TESTES ATIVOS ---${NC}"
        ask_boolean "Ativar Ping ICMP?" "ENABLE_PING"
        if [[ "$ENABLE_PING" == "true" ]]; then
             ask_variable "   ↳ Ping Count" "PING_COUNT"
             ask_variable "   ↳ Ping Timeout (s)" "PING_TIMEOUT"
        fi
        ask_boolean "Ativar Teste TCP (+tcp)?" "ENABLE_TCP_CHECK"
        ask_boolean "Ativar Teste DNSSEC (+dnssec)?" "ENABLE_DNSSEC_CHECK"

        ask_boolean "Testar SOMENTE grupos usados?" "ONLY_TEST_ACTIVE_GROUPS"
        
        echo -e "\n${BLUE}--- SECURITY SCAN ---${NC}"
        ask_boolean "Verificar Versão (BIND Privacy)?" "CHECK_BIND_VERSION"
        ask_boolean "Verificar Zone Transfer (AXFR)?" "ENABLE_AXFR_CHECK"
        ask_boolean "Verificar Recursão Aberta?" "ENABLE_RECURSION_CHECK"
        ask_boolean "Verificar Sincronismo SOA?" "ENABLE_SOA_SERIAL_CHECK"

        echo -e "\n${BLUE}--- MODERN STANDARDS ---${NC}"
        ask_boolean "Verificar EDNS0?" "ENABLE_EDNS_CHECK"
        ask_boolean "Verificar DNS Cookies?" "ENABLE_COOKIE_CHECK"
        ask_boolean "Verificar QNAME Minimization?" "ENABLE_QNAME_CHECK"
        ask_boolean "Verificar TLS Connection?" "ENABLE_TLS_CHECK"
        ask_boolean "Verificar DoT (DNS over TLS)?" "ENABLE_DOT_CHECK"
        ask_boolean "Verificar DoH (DNS over HTTPS)?" "ENABLE_DOH_CHECK"
        
        echo -e "\n${BLUE}--- OPÇÕES AVANÇADAS (DIG) ---${NC}"
        ask_variable "Dig Options (Padrão/Iterativo)" "DEFAULT_DIG_OPTIONS"
        ask_variable "Dig Options (Recursivo)" "RECURSIVE_DIG_OPTIONS"
        
        echo -e "\n${BLUE}--- ANÁLISE & VISUALIZAÇÃO ---${NC}"
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
    update_conf_key "VERBOSE" "$VERBOSE"
    update_conf_key "ENABLE_LOG_TEXT" "$ENABLE_LOG_TEXT"
    
    # Report Flags
    update_conf_key "ENABLE_CHARTS" "$ENABLE_CHARTS"
    update_conf_key "ENABLE_JSON_REPORT" "$ENABLE_JSON_REPORT"
    update_conf_key "ENABLE_CSV_REPORT" "$ENABLE_CSV_REPORT"
    
    # Tests
    sed -i "s|^ENABLE_PING=.*|ENABLE_PING=$ENABLE_PING|" "$CONFIG_FILE"
    if [[ "$ENABLE_PING" == "true" ]]; then
        sed -i "s|^PING_COUNT=.*|PING_COUNT=$PING_COUNT|" "$CONFIG_FILE"
        sed -i "s|^PING_TIMEOUT=.*|PING_TIMEOUT=$PING_TIMEOUT|" "$CONFIG_FILE"
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

generate_executive_summary() {
    # Calculate Risk Score
    local sec_risk_count=$((SEC_REVEALED + SEC_AXFR_RISK + SEC_REC_RISK + DNSSEC_FAIL))
    
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
        <h2>📊 Resumo Executivo</h2>
        <!-- General Inventory Row -->
        <div class="dashboard" style="grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));">
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
            <div class="card" style="--card-accent: #64748b; cursor:pointer;" onclick="showInfoModal('LATÊNCIA MÉDIA', 'Média de tempo de resposta (RTT) de todos os servidores.<br><br><b>Cálculo:</b> Soma de todos os RTTs / Total de respostas / Total de servidores.<br>Valores altos podem indicar congestionamento de rede ou servidores distantes.')">
                <span class="card-num">${avg_lat}${avg_lat_suffix}</span>
                <span class="card-label">Latência Média</span>
            </div>
            
            <!-- Risk Card -->
            <div class="card" style="--card-accent: var(--accent-danger); cursor:pointer;" onclick="showInfoModal('RISCO DE SEGURANÇA', 'Contagem acumulada de falhas de segurança detectadas.<br><br><b>Inclui:</b><br>- Versão Revelada<br>- AXFR Permitido<br>- Recursão Aberta<br>- DNSSEC Falho<br><br>Meta: <b>0</b>')">
                <span class="card-num" style="color: ${sec_risk_count:+"var(--accent-danger)"};">${sec_risk_count}</span>
                <span class="card-label">Risco de Segurança</span>
            </div>
            
            <!-- Divergence Card -->
            <div class="card" style="--card-accent: var(--accent-divergent); cursor:pointer;" onclick="showInfoModal('SERVIDORES INCONSISTENTES', 'Número de testes onde houve divergência de resposta (IP, Ordem ou TTL) entre tentativas consecutivas no mesmo servidor.<br><br>Indica instabilidade ou má configuração de balanceamento.')">
                <span class="card-num" style="color: ${DIVERGENT_TESTS:+"var(--accent-divergent)"};">${DIVERGENT_TESTS}</span>
                <span class="card-label">Inconsistências</span>
            </div>
        </div>
EOF
    
    if [[ "$ENABLE_CHARTS" == "true" ]]; then
         cat >> "$TEMP_STATS" << EOF
        <div style="display: flex; gap: 20px; align-items: flex-start; margin-bottom: 30px;">
             <!-- Overview Chart Container -->
             <div class="card" style="flex: 1; min-height: 350px; --card-accent: var(--accent-primary); align-items: center; justify-content: center;">
                 <h3 style="margin-top:0; color:var(--text-secondary); font-size:1rem; margin-bottom:10px;">Visão Geral de Execução</h3>
                 <div style="position: relative; height: 300px; width: 100%;">
                    <canvas id="chartOverview"></canvas>
                 </div>
             </div>
             <!-- Latency Chart Container -->
             <div class="card" style="flex: 1; min-height: 350px; --card-accent: var(--accent-warning); align-items: center; justify-content: center;">
                 <h3 style="margin-top:0; color:var(--text-secondary); font-size:1rem; margin-bottom:10px;">Top Latência (Médias)</h3>
                 <div style="position: relative; height: 300px; width: 100%;">
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
    local target_file="$HTML_FILE"
    
    # Initialize Target File
    > "$target_file"
     
    prepare_chart_resources
    
    # Offline Warning
    if [[ "$ENABLE_CHARTS" != "true" ]]; then
       cat >> "$target_file" << EOF
       <div style="background:rgba(255,255,0,0.1); border:1px solid #f59e0b; color:#f59e0b; padding:15px; margin:20px; border-radius:8px; text-align:center;">
           ⚠️ <strong>Aviso:</strong> Gráficos desabilitados (Biblioteca Chart.js não disponível offline ou falha no download).
       </div>
EOF
    fi
    
    generate_executive_summary
    generate_health_map
    generate_group_stats_html 
    generate_object_summary
    generate_timing_html
    generate_disclaimer_html 
    generate_config_html
    generate_modal_html
    generate_help_html

    # --- FINAL ASSEMBLY ---
    > "$TEMP_HEADER"
    write_html_header "$mode"

    cat "$TEMP_HEADER" >> "$target_file"
    cat "$TEMP_MODAL" >> "$target_file"
    
    generate_executive_summary
    cat "$TEMP_STATS" >> "$target_file"
    
    # 1. SERVER HEALTH SECTION
    cat "$TEMP_SECTION_SERVER" >> "$target_file"
    
    # 2. ZONE HEALTH SECTION
    cat "$TEMP_SECTION_ZONE" >> "$target_file"
    
    # 3. RECORD VALIDITY SECTION
    cat "$TEMP_SECTION_RECORD" >> "$target_file"

    # Append any legacy details if needed (mostly replaced by above)
    generate_disclaimer_html
    cat "$TEMP_DISCLAIMER" >> "$target_file"
    cat "$TEMP_CONFIG" >> "$target_file" 
    
    generate_help_html
    cat "$LOG_OUTPUT_DIR/temp_help_${SESSION_ID}.html" >> "$target_file"

    cat >> "$target_file" << EOF
</body>
</html>
EOF
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
        name=$(echo "$name" | xargs); servers=$(echo "$servers" | tr -d '[:space:]\r')
        [[ -z "$timeout" ]] && timeout=$TIMEOUT
        IFS=',' read -ra srv_arr <<< "$servers"
        DNS_GROUPS["$name"]="${srv_arr[@]}"; DNS_GROUP_DESC["$name"]="$desc"; DNS_GROUP_TYPE["$name"]="$type"; DNS_GROUP_TIMEOUT["$name"]="$timeout"
    done < "$FILE_GROUPS"
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
    
    # Helper to clean trailing comma from file content for valid JSON array
    # Check if files are non-empty before sed to avoid errors or malformed output
    local dns_data=""; [[ -s "$TEMP_JSON_DNS" ]] && dns_data=$(sed '$ s/,$//' "$TEMP_JSON_DNS")
    local domain_data=""; [[ -s "$TEMP_JSON_DOMAINS" ]] && domain_data=$(sed '$ s/,$//' "$TEMP_JSON_DOMAINS")
    local ping_data=""; [[ -s "$TEMP_JSON_Ping" ]] && ping_data=$(sed '$ s/,$//' "$TEMP_JSON_Ping")
    local sec_data=""; [[ -s "$TEMP_JSON_Sec" ]] && sec_data=$(sed '$ s/,$//' "$TEMP_JSON_Sec")
    local trace_data=""; [[ -s "$TEMP_JSON_Trace" ]] && trace_data=$(sed '$ s/,$//' "$TEMP_JSON_Trace")
    
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
  "statistics": {
    "general": {
    "domains": $domain_count,
    "groups": $group_count,
    "unique_servers": $server_count,
    "total_queries": $TOTAL_DNS_QUERY_COUNT,
    "total_tests": $TOTAL_TESTS,
    "success_rate": $p_succ,
    "latency_avg_ms": "$avg_lat",
    "success": $SUCCESS_TESTS,
    "warnings": $WARNING_TESTS,
    "failures": $FAILED_TESTS,
    "divergences": $DIVERGENT_TESTS,
    "tcp_checks": { "ok": $TCP_SUCCESS, "fail": $TCP_FAIL },
    "dnssec_checks": { "ok": $DNSSEC_SUCCESS, "absent": $DNSSEC_ABSENT, "fail": $DNSSEC_FAIL },
    "total_sleep_seconds": $TOTAL_SLEEP_TIME,
    "total_pings_sent": $TOTAL_PING_SENT,
    "soa_sync": { "ok": $SOA_SYNC_OK, "fail": $SOA_SYNC_FAIL },
    "counters": {
      "noerror": $CNT_NOERROR,
      "nxdomain": $CNT_NXDOMAIN,
      "servfail": $CNT_SERVFAIL,
      "refused": $CNT_REFUSED,
      "timeout": $CNT_TIMEOUT,
      "noanswer": $CNT_NOANSWER,
      "noanswer": $CNT_NOANSWER,
      "network_error": $CNT_NETWORK_ERROR
    },
    "modern_features": {
       "edns": {"ok": $EDNS_SUCCESS, "fail": $EDNS_FAIL},
       "cookie": {"ok": $COOKIE_SUCCESS, "fail": $COOKIE_FAIL},
       "qname": {"ok": $QNAME_SUCCESS, "fail": $QNAME_FAIL, "skip": $QNAME_SKIP},
       "tls": {"ok": $TLS_SUCCESS, "fail": $TLS_FAIL},
       "dot": {"ok": $DOT_SUCCESS, "fail": $DOT_FAIL},
       "doh": {"ok": $DOH_SUCCESS, "fail": $DOH_FAIL}
    }
    },
    "per_record_type": { $json_rec_stats },
    "per_group": { $json_grp_stats }
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

# --- HIERARCHICAL REPORTING ---
generate_hierarchical_stats() {
    echo -e "\n${BOLD}======================================================${NC}"
    echo -e "${BOLD}       RELATÓRIO HIERÁRQUICO DE ESTATÍSTICAS${NC}"
    echo -e "${BOLD}======================================================${NC}"

    # 1. SERVER STATS
    echo -e "\n${BLUE}${BOLD}1. ESTATÍSTICAS DE SERVIDORES (Global -> Grupo -> Servidor)${NC}"
    printf "%-18s | %-15s | %-20s | %-8s | %-8s | %-8s\n" "Servidor" "Grupo" "Latency (Avg/Loss)" "Port 53" "Recursion" "EDNS"
    echo "-------------------------------------------------------------------------------------------"
    
    local total_lat_sum=0
    local total_lat_cnt=0
    
    for ip in "${!UNIQUE_SERVERS[@]}"; do
        local grps="${SERVER_GROUPS_MAP[$ip]}"
        local ping_avg="${STATS_SERVER_PING_AVG[$ip]}"
        local ping_loss="${STATS_SERVER_PING_LOSS[$ip]}"
        local p53="${STATS_SERVER_PORT_53[$ip]}" 
        local rec="${STATS_SERVER_RECURSION[$ip]}"
        local edns="${STATS_SERVER_EDNS[$ip]}"
        
        # Format Ping
        local ping_str="N/A"
        if [[ -n "$ping_avg" && "$ping_avg" != "0" ]]; then
             ping_str="${ping_avg}ms (${ping_loss}%)"
             # Approximate global avg calc - Handled in valid numeric block below

        elif [[ "$ping_loss" == "100" ]]; then
             ping_str="DOWN"
        fi
        
        # Colorize
        local c_p53=$GREEN; [[ "$p53" != "OPEN" ]] && c_p53=$RED
        local c_rec=$RED; [[ "$rec" == "CLOSED" ]] && c_rec=$GREEN
        local c_edns=$GREEN; [[ "$edns" == "FAIL" ]] && c_edns=$RED
        
        # Colorize Latency
        local c_lat=$GREEN
        if [[ "$ping_str" == "DOWN" ]]; then
             c_lat=$RED
        elif [[ -n "$ping_avg" && "$ping_avg" != "0" ]]; then
             # Compare float
             if (( $(echo "$ping_avg > $LATENCY_WARNING_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
                  c_lat=$YELLOW
             fi
        fi

        # Safe AWK calculation to avoid overflow issues
        if [[ -n "$ping_avg" && "$ping_avg" != "0" ]]; then
             if [[ "$ping_avg" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                 total_lat_sum=$(awk -v s="$total_lat_sum" -v v="$ping_avg" 'BEGIN { printf "%.5f", s + v }')
                 total_lat_cnt=$((total_lat_cnt + 1))
             fi
        fi
        
        printf "%-18s | %-15s | ${c_lat}%-20s${NC} | ${c_p53}%-8s${NC} | ${c_rec}%-8s${NC} | ${c_edns}%-8s${NC}\n" \
            "$ip" "$grps" "$ping_str" "$p53" "$rec" "$edns"
    done
    
    # 2. ZONE STATS
    echo -e "\n${BLUE}${BOLD}2. SAÚDE DAS ZONAS (SOA & AXFR)${NC}"
    printf "%-25s | %-15s | %-20s | %-10s\n" "Zona" "Grupo" "SOA Serial (Mode)" "AXFR (Allow/Deny)"
    echo "-----------------------------------------------------------------------------"
    
    while IFS=';' read -r domain groups _ _ _; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs)
        IFS=',' read -ra grp_list <<< "$groups"
        
        for grp in "${grp_list[@]}"; do
             local srvs=${DNS_GROUPS[$grp]}
             local axfr_allow_cnt=0
             local axfr_deny_cnt=0
             local soa_list=""
             
             for srv in $srvs; do
                  local ax_stat="${STATS_ZONE_AXFR[$domain|$grp|$srv]}"
                  if [[ "$ax_stat" == "ALLOWED" ]]; then axfr_allow_cnt=$((axfr_allow_cnt+1)); 
                  elif [[ "$ax_stat" == "DENIED" ]]; then axfr_deny_cnt=$((axfr_deny_cnt+1)); fi
                  
                  local s_soa="${STATS_ZONE_SOA[$domain|$grp|$srv]}"
                  [[ -n "$s_soa" ]] && soa_list+="$s_soa"$'\n'
             done
             
             # SOA Consistency Check
             local unique_soas=$(echo -n "$soa_list" | sed '/^$/d' | sort -u)
             local unique_count=0
             if [[ -n "$unique_soas" ]]; then
                 unique_count=$(echo "$unique_soas" | wc -l)
             fi

             local soa_display="N/A"
             local c_soa=$RED
             
             if [[ $unique_count -gt 1 ]]; then
                 soa_display="DIVERGENT"
             elif [[ $unique_count -eq 1 ]]; then
                 soa_display=$(echo -n "$unique_soas" | tr -d '\n')
                 [[ "$soa_display" =~ ^[0-9]+$ ]] && c_soa=$GREEN
             fi
             
             local axfr_txt="${axfr_deny_cnt} DENIED"
             local c_axfr=$GREEN
             if [[ $axfr_allow_cnt -gt 0 ]]; then
                 axfr_txt="${axfr_allow_cnt} ALLOWED"
                 c_axfr=$RED
             fi
             
             printf "%-25s | %-15s | ${c_soa}%-20s${NC} | ${c_axfr}%-20s${NC}\n" \
                 "$domain" "$grp" "$soa_display" "$axfr_txt"
        done
    done < "$FILE_DOMAINS"
    
    # 3. RECORD STATS
    echo -e "\n${BLUE}${BOLD}3. CONSISTÊNCIA DE REGISTROS${NC}"
    printf "%-25s | %-6s | %-10s | %-15s | %-10s\n" "Zona" "Tipo" "Grupo" "Consistência" "Divergências"
    echo "-----------------------------------------------------------------------------"
    
    while IFS=';' read -r domain groups _ record_types _; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra grp_list <<< "$groups"
        
        for rec_type in "${rec_list[@]}"; do
            rec_type=${rec_type^^}
            for grp in "${grp_list[@]}"; do
                 local cons="${STATS_RECORD_CONSISTENCY[$domain|$rec_type|$grp]}"
                 local div_cnt="${STATS_RECORD_DIV_COUNT[$domain|$rec_type|$grp]}"
                 
                 local c_cons=$GREEN
                 [[ "$cons" == "DIVERGENT" ]] && c_cons=$RED
                 
                 # Only print if relevant (skip fully consistent to reduce noise? User asked for all stats)
                 [[ "$cons" == "CONSISTENT" ]] && cons="OK"
                 [[ -z "$cons" ]] && cons="N/A"
                 
                 local c_div=$GREEN
                 [[ $div_cnt -gt 0 || "$cons" == "DIVERGENT" ]] && c_div=$RED
                 
                 printf "%-25s | %-6s | %-10s | ${c_cons}%-15s${NC} | ${c_div}%-10s${NC}\n" \
                     "$domain" "$rec_type" "$grp" "$cons" "$div_cnt"
            done
        done
    done < "$FILE_DOMAINS"
    echo "======================================================"
}

print_final_terminal_summary() {
     # Calculate totals
     local total_tests=$TOTAL_TESTS
     local duration=$TOTAL_DURATION
     
     # Use our new function
     generate_hierarchical_stats
     
     echo -e "\n${BOLD}RESUMO DA EXECUÇÃO${NC}"
     echo "  Duração Total   : ${duration}s"
     echo "  Total de Testes : ${total_tests}"
     echo -e "  Sucesso         : ${GREEN}${SUCCESS_TESTS:-0}${NC}"
     echo -e "  Falhas          : ${RED}${FAILED_TESTS:-0}${NC}"
     echo -e "  Divergências    : ${YELLOW}${DIVERGENT_TESTS:-0}${NC}"
     
     # Log to text file
     if [[ "$ENABLE_LOG_TEXT" == "true" ]]; then
          echo "Writing text log..."
          # Redirect new stats to log
          generate_hierarchical_stats >> "$LOG_FILE_TEXT"
     fi

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
         if ! dig +cookie +noall . &>/dev/null; then
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
    
    declare -gA STATS_SERVER_PORT_53
    declare -gA STATS_SERVER_PORT_853
    declare -gA STATS_SERVER_VERSION
    declare -gA STATS_SERVER_RECURSION
    declare -gA STATS_SERVER_EDNS
    declare -gA STATS_SERVER_COOKIE

    # Identify Unique Servers to Test
    declare -gA UNIQUE_SERVERS
    declare -gA SERVER_GROUPS_MAP
    
    # Pre-calculate active groups based on domains_tests.csv if filter is on
    declare -gA ACTIVE_GROUPS_CALC
    if [[ "$ONLY_TEST_ACTIVE_GROUPS" == "true" ]]; then
        while IFS=';' read -r domain groups _ _ _; do
             [[ "$domain" =~ ^# || -z "$domain" ]] && continue
             IFS=',' read -ra grp_list <<< "$groups"
             for g in "${grp_list[@]}"; do ACTIVE_GROUPS_CALC[$(echo "$g" | tr -d '[:space:]')]=1; done
        done < "$FILE_DOMAINS"
    else
        for g in "${!DNS_GROUPS[@]}"; do ACTIVE_GROUPS_CALC[$g]=1; done
    fi

    for grp in "${!DNS_GROUPS[@]}"; do
        [[ -z "${ACTIVE_GROUPS_CALC[$grp]}" ]] && continue
        
        for ip in ${DNS_GROUPS[$grp]}; do
            UNIQUE_SERVERS[$ip]=1
            # Append group to map
            if [[ -z "${SERVER_GROUPS_MAP[$ip]}" ]]; then SERVER_GROUPS_MAP[$ip]="$grp"; else SERVER_GROUPS_MAP[$ip]="${SERVER_GROUPS_MAP[$ip]},$grp"; fi
        done
    done
    
    echo -e "  Identificados ${#UNIQUE_SERVERS[@]} servidores únicos para teste."
    
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
                    <th>Latência (Min/Avg/Max)</th>
                    <th>Porta 53</th>
                    <th>Porta 853 (ABS)</th>
                    <th>Versão (Bind)</th>
                    <th>Recursão</th>
                    <th>EDNS</th>
                    <th>Cookie</th>
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
             echo -e "${GRAY}  Legend: [Ping] [Port53] [DoT] [Ver] [Rec] [EDNS] [Cookie]${NC}"
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
        
        # Ping with Stats Extraction
        if [[ "$ENABLE_PING" == "true" ]]; then
            local cmd_ping="ping -c $PING_COUNT -W $PING_TIMEOUT $ip"
            local out_ping=$($cmd_ping 2>&1)
            
            # Extract Packet Loss
            local loss_pct=$(echo "$out_ping" | grep -oP '\d+(?=% packet loss)')
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
            
            if [[ "$loss_pct" -eq 100 ]]; then
                ping_res_html="<span class='badge status-fail'>100% LOSS</span>"
                ping_res_term="${RED}DOWN${NC}"
                CNT_PING_FAIL=$((CNT_PING_FAIL+1))
            elif [[ "$loss_pct" -gt 0 ]]; then
                ping_res_html="<span class='badge status-warn'>${loss_pct}% LOSS</span>"
                ping_res_term="${YELLOW}${loss_pct}% LOSS${NC}"
                CNT_PING_FAIL=$((CNT_PING_FAIL+1))
                lat_stats="${p_min}/${p_avg}/${p_max} ms"
            else 
                ping_res_html="<span class='badge status-ok'>OK</span>"
                ping_res_term="${GREEN}OK${NC}"
                CNT_PING_OK=$((CNT_PING_OK+1))
                lat_stats="${p_min}/${p_avg}/${p_max} ms"
            fi
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
             else 
                 tls853_res_html="<span class='badge status-fail'>CLOSED</span>"
                 tls853_res_term="${RED}FAIL${NC}"
                 STATS_SERVER_PORT_853[$ip]="CLOSED"
                 CACHE_TLS_STATUS[$ip]="FAIL"
             fi
        else
             STATS_SERVER_PORT_853[$ip]="SKIPPED"
             tls853_res_term="${GRAY}SKIP${NC}"
        fi

        # 1.2 Attributes (Version, Recursion)
        if [[ "$CHECK_BIND_VERSION" == "true" ]]; then 
             local out_ver=$(dig +short @$ip version.bind chaos txt +time=$TIMEOUT)
             if [[ -z "$out_ver" || "$out_ver" == "" ]]; then 
                 ver_res_html="<span class='badge status-ok'>HIDDEN</span>"
                 ver_res_term="${GREEN}HIDDEN${NC}"
                 STATS_SERVER_VERSION[$ip]="HIDDEN"
             else 
                 ver_res_html="<span class='badge status-fail' title='$out_ver'>REVEA.</span>"
                 ver_res_term="${RED}REVEALED${NC}"
                 STATS_SERVER_VERSION[$ip]="REVEALED"
             fi
        else
             STATS_SERVER_VERSION[$ip]="SKIPPED"
             ver_res_term="${GRAY}SKIP${NC}"
        fi
        
        if [[ "$ENABLE_RECURSION_CHECK" == "true" ]]; then
             local out_rec=$(dig @$ip google.com A +recurse +time=$TIMEOUT +tries=1)
             if echo "$out_rec" | grep -q "status: REFUSED" || echo "$out_rec" | grep -q "recursion requested but not available"; then
                 rec_res_html="<span class='badge status-ok'>CLOSED</span>"
                 rec_res_term="${GREEN}CLOSED${NC}"
                 STATS_SERVER_RECURSION[$ip]="CLOSED"
             elif echo "$out_rec" | grep -q "status: NOERROR"; then
                 rec_res_html="<span class='badge status-fail'>OPEN</span>"
                 rec_res_term="${RED}OPEN${NC}"
                 STATS_SERVER_RECURSION[$ip]="OPEN"
             else
                 rec_res_html="<span class='badge status-warn'>UNK</span>"
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
        else
             STATS_SERVER_COOKIE[$ip]="SKIPPED"
             cookie_res_term="${GRAY}SKIP${NC}"
        fi

        # ADD ROW
        echo "<tr><td>$ip</td><td>$grps</td><td>$ping_res_html</td><td>$lat_stats</td><td>$tcp53_res_html</td><td>$tls853_res_html</td><td>$ver_res_html</td><td>$rec_res_html</td><td>$edns_res_html</td><td>$cookie_res_html</td></tr>" >> "$TEMP_SECTION_SERVER"
        
        echo -e "     Ping:${ping_res_term} | 53:${tcp53_res_term} | 853:${tls853_res_term} | Ver:${ver_res_term} | Rec:${rec_res_term} | EDNS:${edns_res_term} | Cookie:${cookie_res_term}"

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
    echo "  Legend: [SOA] [AXFR]"
    
    # Global Stats Arrays
    declare -gA STATS_ZONE_AXFR
    declare -gA STATS_ZONE_SOA
    
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
                </tr>
            </thead>
            <tbody>
EOF
    
    while IFS=';' read -r domain groups _ _ _; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs)
        IFS=',' read -ra grp_list <<< "$groups"
        
        echo -e "  🌎 ${CYAN}Zone:${NC} $domain"
        
        for grp in "${grp_list[@]}"; do
             # Get servers
             local srvs=${DNS_GROUPS[$grp]}
             [[ -z "$srvs" ]] && continue
             
             # Calculate SOA for Group (First pass)
             local first_serial=""
             declare -A SERVER_SERIALS
             declare -A SERVER_AXFR
             
             for srv in $srvs; do
                  # SOA
                  local serial="ERR"
                  if [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" ]]; then
                       serial=$(dig +short +time=$TIMEOUT @$srv $domain SOA | awk '{print $3}')
                       [[ -z "$serial" ]] && serial="TIMEOUT"
                       SERVER_SERIALS[$srv]="$serial"
                       STATS_ZONE_SOA["$domain|$grp|$srv"]="$serial"
                       if [[ -z "$first_serial" && "$serial" != "TIMEOUT" ]]; then first_serial="$serial"; fi
                  else
                       SERVER_SERIALS[$srv]="N/A"
                       STATS_ZONE_SOA["$domain|$grp|$srv"]="N/A"
                  fi
                  
                  # AXFR
                  local axfr_stat="N/A"
                  local axfr_raw="SKIPPED"
                  if [[ "$ENABLE_AXFR_CHECK" == "true" ]]; then
                      local out_axfr=$(dig @$srv $domain AXFR +time=$TIMEOUT +tries=1)
                      if echo "$out_axfr" | grep -q "Refused" || echo "$out_axfr" | grep -q "Transfer failed"; then
                          axfr_stat="<span class='badge status-ok'>DENIED</span>"
                          axfr_raw="DENIED"
                      elif echo "$out_axfr" | grep -q "SOA"; then
                          axfr_stat="<span class='badge status-fail'>ALLOWED</span>"
                          axfr_raw="ALLOWED"
                      else
                          axfr_stat="<span class='badge status-warn'>TIMEOUT/ERR</span>"
                          axfr_raw="TIMEOUT"
                      fi
                  fi
                  SERVER_AXFR[$srv]="$axfr_stat"
                  STATS_ZONE_AXFR["$domain|$grp|$srv"]="$axfr_raw"
             done

             # Add Rows
             for srv in $srvs; do
                 local serial=${SERVER_SERIALS[$srv]}
                 local ser_html="$serial"
                 if [[ "$ENABLE_SOA_SERIAL_CHECK" == "true" ]]; then
                     if [[ "$serial" == "TIMEOUT" ]]; then
                         ser_html="<span class='badge status-neutral'>TIMEOUT</span>"
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
                 
                 echo "<tr><td>$domain</td><td>$grp</td><td>$srv</td><td>$ser_html</td><td>${SERVER_AXFR[$srv]}</td></tr>" >> "$TEMP_SECTION_ZONE"
                 
                 # Term Output
                 local term_soa="$serial"
                 [[ "$serial" == "$first_serial" ]] && term_soa="${GREEN}$serial${NC}" || term_soa="${RED}$serial${NC}"
                 [[ "$serial" == "TIMEOUT" ]] && term_soa="${YELLOW}TIMEOUT${NC}"
                 
                 local term_axfr="${SERVER_AXFR[$srv]}"
                 # Simple AXFR status for term
                 if [[ "$term_axfr" == *"DENIED"* ]]; then term_axfr="${GREEN}DENIED${NC}"
                 elif [[ "$term_axfr" == *"ALLOWED"* ]]; then term_axfr="${RED}ALLOWED${NC}"
                 else term_axfr="${YELLOW}unk${NC}"; fi
                 
                 echo -e "     💻 $srv ($grp) | SOA:$term_soa | AXFR:$term_axfr"
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
    echo -e "  Legend: [Server] (Group) : [Status] (Answer/Error) [${RED}⚠️${NC}=Inconsistências]"
    
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
                         TOTAL_TESTS=$((TOTAL_TESTS + 1))
                         
                         # Uses full output to capture Status and Answer
                         local out_full
                         out_full=$(dig +tries=1 +time=$TIMEOUT @$srv $target $rec_type 2>&1)
                         local ret=$?
                         
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
                            term_extra=" (${answer_data:0:50}...)" # Truncate for term
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
                             # Timestamp;Grupo;Servidor;Dominio;Record;Status;Latencia_ms;Detail;TCP;SEC;EDNS;COOKIE;TLS;DOT;DOH;QNAME
                             echo "$csv_ts;$grp;$srv;$target;$rec_type;$status;$dur;Phase3-Record;${CACHE_TCP_STATUS[$srv]};${CACHE_SEC_STATUS[$srv]};${CACHE_EDNS_STATUS[$srv]};${CACHE_COOKIE_STATUS[$srv]};${CACHE_TLS_STATUS[$srv]};;;;" >> "$LOG_FILE_CSV"
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
                             echo -e "${line} ${RED}[⚠️ ]${NC}"
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
    trap 'rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS" "$TEMP_PING" "$TEMP_TRACE" "$TEMP_CONFIG" "$TEMP_TIMING" "$TEMP_MODAL" "$TEMP_DISCLAIMER" "$TEMP_SERVICES" "$LOG_OUTPUT_DIR/temp_help_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_obj_summary_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_svc_table_${SESSION_ID}.html" "$TEMP_TRACE_SIMPLE" "$TEMP_PING_SIMPLE" "$TEMP_MATRIX_SIMPLE" "$TEMP_SERVICES_SIMPLE" "$LOG_OUTPUT_DIR/temp_domain_body_simple_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_group_body_simple_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_security_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_security_simple_${SESSION_ID}.html" "$LOG_OUTPUT_DIR/temp_sec_rows_${SESSION_ID}.html" "$TEMP_JSON_Ping" "$TEMP_JSON_DNS" "$TEMP_JSON_Sec" "$TEMP_JSON_Trace" "$TEMP_JSON_DOMAINS" "$LOG_OUTPUT_DIR/temp_chart_${SESSION_ID}.js" "$TEMP_HEALTH_MAP" "$TEMP_SECTION_SERVER" "$TEMP_SECTION_ZONE" "$TEMP_SECTION_RECORD" 2>/dev/null' EXIT

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
    run_server_tests
    
    # 2. ZONE Phase
    run_zone_tests
    
    # 3. RECORD Phase
    run_record_tests
    
    # LEGACY CALLS REMOVED 
    # process_tests; run_ping_diagnostics; run_trace_diagnostics; run_security_diagnostics

    END_TIME_EPOCH=$(date +%s); END_TIME_HUMAN=$(date +"%d/%m/%Y %H:%M:%S"); TOTAL_DURATION=$((END_TIME_EPOCH - START_TIME_EPOCH))
    
    if [[ -z "$TOTAL_SLEEP_TIME" ]]; then TOTAL_SLEEP_TIME=0; fi
    TOTAL_SLEEP_TIME=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", $TOTAL_SLEEP_TIME}")

    # Always generate standard HTML report
    assemble_html
    
    if [[ "$ENABLE_JSON_REPORT" == "true" ]]; then
        assemble_json
    fi

    [[ "$ENABLE_LOG_TEXT" == "true" ]] && echo "Execution finished" >> "$LOG_FILE_TEXT"
    print_final_terminal_summary
    echo -e "\n${GREEN}=== CONCLUÍDO ===${NC}"
    echo "Relatório HTML: $HTML_FILE"
    [[ "$ENABLE_JSON_REPORT" == "true" ]] && echo "Relatório JSON: $LOG_FILE_JSON"
    [[ "$ENABLE_CSV_REPORT" == "true" ]] && echo "Relatório CSV : $LOG_FILE_CSV"
    [[ "$ENABLE_LOG_TEXT" == "true" ]] && echo "Log Texto     : $LOG_FILE_TEXT"
    [[ "$ENABLE_JSON_LOG" == "true" ]] && echo "Log JSON      : $LOG_FILE_JSON"
}

main "$@"
