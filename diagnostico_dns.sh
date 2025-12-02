#!/bin/bash

# Configurações padrão
DEFAULT_DIG_OPTIONS="+norecurse +time=1 +tries=1 +nocookie +cd +bufsize=512"
RECURSIVE_DIG_OPTIONS="+time=1 +tries=1 +nocookie +cd +bufsize=512"
LOG_PREFIX="dnsdiag"
TIMEOUT=5
VALIDATE_CONNECTIVITY=true
GENERATE_HTML=true
SLEEP=0.5  # Intervalo em segundos entre os comandos (0 = sem intervalo)

# Cores para output no terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Carregar configurações externas se existirem
if [[ -f "script_config.cfg" ]]; then
    source script_config.cfg
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_PREFIX}_${TIMESTAMP}.txt"
HTML_FILE="${LOG_PREFIX}_${TIMESTAMP}.html"

# Variável global para contador de testes
TEST_COUNTER=0

# Função para aguardar intervalo entre comandos
wait_interval() {
    if [[ $(echo "$SLEEP > 0" | bc -l) -eq 1 ]]; then
        echo -e "${YELLOW}[INTERVALO] Aguardando ${SLEEP}s antes do próximo comando...${NC}"
        sleep $SLEEP
    fi
}

# Funções para gerar HTML
init_html_report() {
    if [[ "$GENERATE_HTML" == "true" ]]; then
        cat > "$HTML_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Relatório DNS - $TIMESTAMP</title>
    <style>
        body { 
            font-family: 'Courier New', Consolas, Monaco, monospace; 
            background: #1e1e1e; 
            color: #d4d4d4; 
            margin: 20px;
            line-height: 1.4;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .success { color: #4ec9b0; }
        .error { color: #f44747; }
        .warning { color: #ffcc02; }
        .info { color: #9cdcfe; }
        .section { 
            color: #ce9178; 
            font-weight: bold; 
            border-bottom: 2px solid #ce9178;
            padding: 10px 0;
            margin: 20px 0;
        }
        .query { color: #d4d4d4; }
        .answer { color: #4ec9b0; }
        .authority { color: #ffcc02; }
        .additional { color: #c586c0; }
        .timestamp { color: #6a9955; font-size: 0.9em; }
        .server { color: #9cdcfe; }
        .domain { color: #ffffff; }
        .record-type { color: #ff8800; }
        .test-header { 
            background: #2d2d30; 
            padding: 12px; 
            margin: 15px 0; 
            border-left: 4px solid #007acc;
            border-radius: 4px;
        }
        .dig-output { 
            background: #252526; 
            padding: 15px; 
            margin: 10px 0; 
            border: 1px solid #3e3e42;
            border-radius: 4px;
            white-space: pre-wrap;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
        }
        .summary { 
            background: #2d2d30; 
            padding: 15px; 
            margin: 15px 0;
            border-radius: 4px;
        }
        h1 { color: #ce9178; text-align: center; }
        h2 { color: #9cdcfe; border-bottom: 1px solid #3e3e42; padding-bottom: 5px; }
        .status-success { color: #4ec9b0; font-weight: bold; }
        .status-error { color: #f44747; font-weight: bold; }
        .group-info { color: #c586c0; }
        .test-counter { 
            background: #007acc; 
            color: white; 
            padding: 2px 6px; 
            border-radius: 3px; 
            font-weight: bold;
        }
        .interval { 
            color: #6a9955; 
            font-style: italic; 
            text-align: center;
            margin: 10px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Relatório de Diagnóstico DNS</h1>
        <div class="summary">
            <p><strong>Timestamp de início:</strong> <span class="timestamp">$TIMESTAMP</span></p>
            <p><strong>Arquivo de log:</strong> $LOG_FILE</p>
            <p><strong>Relatório HTML:</strong> $HTML_FILE</p>
            <p><strong>Intervalo entre comandos:</strong> ${SLEEP}s</p>
        </div>
        <hr>
EOF
    fi
}

html_log() {
    local message="$1"
    local class="$2"
    if [[ "$GENERATE_HTML" == "true" ]]; then
        echo "<div class=\"$class\">$message</div>" >> "$HTML_FILE"
    fi
}

html_log_section() {
    local message="$1"
    if [[ "$GENERATE_HTML" == "true" ]]; then
        echo "<div class=\"section\">$message</div>" >> "$HTML_FILE"
    fi
}

html_log_test() {
    local test_number="$1"
    local message="$2"
    if [[ "$GENERATE_HTML" == "true" ]]; then
        echo "<div class=\"test-header\">" >> "$HTML_FILE"
        echo "<span class=\"test-counter\">TESTE $test_number</span> - $message" >> "$HTML_FILE"
        echo "</div>" >> "$HTML_FILE"
    fi
}

html_log_interval() {
    if [[ "$GENERATE_HTML" == "true" ]] && [[ $(echo "$SLEEP > 0" | bc -l) -eq 1 ]]; then
        echo "<div class=\"interval\">⏱️ Intervalo de ${SLEEP}s</div>" >> "$HTML_FILE"
    fi
}

finalize_html_report() {
    if [[ "$GENERATE_HTML" == "true" ]]; then
        cat >> "$HTML_FILE" << EOF
        <div class="section">DIAGNÓSTICO CONCLUÍDO</div>
        <div class="summary">
            <p><strong>Total de testes executados:</strong> <span class="test-counter">$(printf "%02d" $TEST_COUNTER)</span></p>
            <p><strong>Timestamp de término:</strong> <span class="timestamp">$(date '+%Y-%m-%d %H:%M:%S')</span></p>
            <p><strong>Intervalo utilizado:</strong> ${SLEEP}s</p>
        </div>
    </div>
</body>
</html>
EOF
    fi
}

# Funções auxiliares
log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$message" | tee -a "$LOG_FILE"
    html_log "$message" "info"
}

log_color() {
    local color=$1
    local message=$2
    local class=$3
    echo -e "${color}$(date '+%Y-%m-%d %H:%M:%S') - ${message}${NC}" | tee -a "$LOG_FILE"
    html_log "$(date '+%Y-%m-%d %H:%M:%S') - $message" "${class:-info}"
}

log_test() {
    TEST_COUNTER=$((TEST_COUNTER + 1))
    local test_number=$(printf "%02d" $TEST_COUNTER)
    echo -e "${BLUE}$(date '+%Y-%m-%d %H:%M:%S') - $test_number - $1${NC}" | tee -a "$LOG_FILE"
    html_log_test "$test_number" "$1"
}

log_section() {
    echo -e "${YELLOW}================================================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}================================================================${NC}" | tee -a "$LOG_FILE"
    html_log_section "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_test_header() {
    local test_number=$(printf "%02d" $TEST_COUNTER)
    echo "------------------------------------------------" >> "$LOG_FILE"
    echo "TESTE $test_number: $1" >> "$LOG_FILE"
    echo "------------------------------------------------" >> "$LOG_FILE"
}

# Função para analisar e colorir a saída do dig
colorize_dig_output() {
    local output="$1"
    local server="$2"
    local domain="$3"
    local record_type="$4"
    
    # Colorir cabeçalho da consulta
    output=$(echo "$output" | sed "s/;; QUESTION SECTION:/${CYAN};; QUESTION SECTION:${NC}/")
    output=$(echo "$output" | sed "s/;; ANSWER SECTION:/${GREEN};; ANSWER SECTION:${NC}/")
    output=$(echo "$output" | sed "s/;; AUTHORITY SECTION:/${YELLOW};; AUTHORITY SECTION:${NC}/")
    output=$(echo "$output" | sed "s/;; ADDITIONAL SECTION:/${PURPLE};; ADDITIONAL SECTION:${NC}/")
    
    # Colorir flags importantes
    output=$(echo "$output" | sed "s/ flags: / flags: ${BLUE}/")
    output=$(echo "$output" | sed "s/; QUERY:/${NC}; QUERY:/")
    
    # Colorir respostas específicas
    output=$(echo "$output" | sed "s/^${domain}/\\${GREEN}${domain}${NC}/")
    output=$(echo "$output" | sed "s/ IN ${record_type} / IN ${BLUE}${record_type}${NC} /")
    
    # Colorir status de erro
    if echo "$output" | grep -q "status:"; then
        if echo "$output" | grep -q "status: NOERROR"; then
            output=$(echo "$output" | sed "s/status: NOERROR/${GREEN}status: NOERROR${NC}/")
        elif echo "$output" | grep -q "status: NXDOMAIN"; then
            output=$(echo "$output" | sed "s/status: NXDOMAIN/${RED}status: NXDOMAIN${NC}/")
        elif echo "$output" | grep -q "status: SERVFAIL"; then
            output=$(echo "$output" | sed "s/status: SERVFAIL/${RED}status: SERVFAIL${NC}/")
        elif echo "$output" | grep -q "status: REFUSED"; then
            output=$(echo "$output" | sed "s/status: REFUSED/${RED}status: REFUSED${NC}/")
        else
            output=$(echo "$output" | sed "s/status: /${YELLOW}status: ${NC}/")
        fi
    fi
    
    # Colorir tempos
    output=$(echo "$output" | sed "s/Query time:/${CYAN}Query time:${NC}/")
    output=$(echo "$output" | sed "s/SERVER:/${PURPLE}SERVER:${NC}/")
    output=$(echo "$output" | sed "s/${server}#53/${GREEN}${server}#53${NC}/")
    
    # Colorir quando não há resposta
    if echo "$output" | grep -q "connection timed out"; then
        output=$(echo "$output" | sed "s/connection timed out/${RED}connection timed out${NC}/")
    fi
    
    if echo "$output" | grep -q "no servers could be reached"; then
        output=$(echo "$output" | sed "s/no servers could be reached/${RED}no servers could be reached${NC}/")
    fi
    
    echo -e "$output"
}

load_dns_groups() {
    declare -gA DNS_GROUPS
    declare -gA DNS_GROUP_DESC
    declare -gA DNS_GROUP_TYPE
    
    while IFS=';' read -r name description type servers; do
        # Pular comentários e linhas vazias
        [[ "$name" =~ ^# ]] && continue
        [[ -z "$name" ]] && continue
        
        # Remover espaços em branco
        name=$(echo "$name" | tr -d '[:space:]')
        description=$(echo "$description" | tr -d '[:space:]')
        type=$(echo "$type" | tr -d '[:space:]')
        servers=$(echo "$servers" | tr -d '[:space:]')
        
        # Converter servidores em array
        IFS=',' read -ra servers_array <<< "$servers"
        DNS_GROUPS["$name"]="${servers_array[@]}"
        DNS_GROUP_DESC["$name"]="$description"
        DNS_GROUP_TYPE["$name"]="$type"
        
        log_color "$GREEN" "Grupo carregado: $name - ${#servers_array[@]} servidores - $description" "success"
    done < dns_groups.csv
}

validate_connectivity() {
    local server="$1"
    local timeout="$2"
    
    if nc -z -w "$timeout" "$server" 53 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

run_dig_test() {
    local server="$1"
    local domain="$2"
    local record_type="$3"
    local test_type="$4"
    local group="$5"
    local test_number=$(printf "%02d" $TEST_COUNTER)
    
    local options
    if [[ "$test_type" == "iterative" ]]; then
        options="$DEFAULT_DIG_OPTIONS"
    else
        options="$RECURSIVE_DIG_OPTIONS"
    fi
    
    log_test_header "Grupo: $group | Tipo: $test_type | Servidor: $server | Domínio: $domain | Registro: $record_type"
    
    echo "COMANDO EXECUTADO: dig $options @$server $domain $record_type" >> "$LOG_FILE"
    echo "SAÍDA:" >> "$LOG_FILE"
    
    local start_time
    local end_time
    local dig_output
    
    start_time=$(date +%s)
    dig_output=$(dig $options @"$server" "$domain" "$record_type" 2>&1)
    local exit_code=$?
    end_time=$(date +%s)
    
    local duration=$((end_time - start_time))
    
    # Escrever saída crua no arquivo de log
    echo "$dig_output" >> "$LOG_FILE"
    echo "TEMPO DE EXECUÇÃO: ${duration}s | CÓDIGO DE SAÍDA: $exit_code" >> "$LOG_FILE"
    echo >> "$LOG_FILE"
    
    # Adicionar ao HTML
    if [[ "$GENERATE_HTML" == "true" ]]; then
        echo "<div class=\"test-header\">" >> "$HTML_FILE"
        echo "<strong>Detalhes do Teste</strong><br>" >> "$HTML_FILE"
        echo "Servidor: <span class=\"server\">$server</span> | " >> "$HTML_FILE"
        echo "Domínio: <span class=\"domain\">$domain</span> | " >> "$HTML_FILE"
        echo "Tipo: <span class=\"record-type\">$record_type</span> | " >> "$HTML_FILE"
        echo "Modo: <span class=\"info\">$test_type</span> | " >> "$HTML_FILE"
        echo "Grupo: <span class=\"group-info\">$group</span>" >> "$HTML_FILE"
        echo "</div>" >> "$HTML_FILE"
        
        echo "<div class=\"dig-output\">" >> "$HTML_FILE"
        echo "<strong>Comando executado:</strong> dig $options @$server $domain $record_type" >> "$HTML_FILE"
        echo "<br><br>" >> "$HTML_FILE"
        echo "<strong>Saída:</strong><br>" >> "$HTML_FILE"
        echo "<pre>" >> "$HTML_FILE"
        echo "$dig_output" >> "$HTML_FILE"
        echo "</pre>" >> "$HTML_FILE"
        echo "</div>" >> "$HTML_FILE"
        
        if [ $exit_code -eq 0 ]; then
            echo "<p class=\"status-success\">✅ COMANDO EXECUTADO COM SUCESSO (${duration}s)</p>" >> "$HTML_FILE"
        else
            echo "<p class=\"status-error\">❌ FALHA NA EXECUÇÃO DO COMANDO (código: $exit_code, tempo: ${duration}s)</p>" >> "$HTML_FILE"
        fi
        
        # Registrar intervalo no HTML se aplicável
        html_log_interval
        
        echo "<hr>" >> "$HTML_FILE"
    fi
    
    # Mostrar saída colorida no terminal
    echo -e "${CYAN}=== RESULTADO DO TESTE ${test_number} ===${NC}"
    echo -e "${WHITE}Servidor: ${GREEN}$server${NC}"
    echo -e "${WHITE}Domínio: ${GREEN}$domain${NC}"
    echo -e "${WHITE}Tipo: ${BLUE}$record_type${NC}"
    echo -e "${WHITE}Modo: ${YELLOW}$test_type${NC}"
    echo -e "${WHITE}Grupo: ${PURPLE}$group${NC}"
    echo -e "${WHITE}Tempo: ${CYAN}${duration}s${NC}"
    
    # Analisar e colorir a saída do dig
    colorize_dig_output "$dig_output" "$server" "$domain" "$record_type"
    
    # Status final colorido baseado no código de saída
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ COMANDO EXECUTADO COM SUCESSO${NC}"
    else
        echo -e "${RED}✗ FALHA NA EXECUÇÃO DO COMANDO (código: $exit_code)${NC}"
    fi
    
    echo -e "${CYAN}================================${NC}"
    echo
    
    # Aguardar intervalo entre comandos
    wait_interval
    
    return $exit_code
}

process_domain_tests() {
    local domain_count=0
    local test_count=0
    
    while IFS=';' read -r domain groups test_types record_types extra_hosts; do
        # Pular comentários e linhas vazias
        [[ "$domain" =~ ^# ]] && continue
        [[ -z "$domain" ]] && continue
        
        # Remover espaços em branco
        domain=$(echo "$domain" | tr -d '[:space:]')
        groups=$(echo "$groups" | tr -d '[:space:]')
        test_types=$(echo "$test_types" | tr -d '[:space:]')
        record_types=$(echo "$record_types" | tr -d '[:space:]')
        extra_hosts=$(echo "$extra_hosts" | tr -d '[:space:]')
        
        ((domain_count++))
        log_section "PROCESSANDO DOMÍNIO: $domain"
        echo -e "${WHITE}Grupos: ${CYAN}$groups${NC}" | tee -a "$LOG_FILE"
        echo -e "${WHITE}Tipos de teste: ${YELLOW}$test_types${NC}" | tee -a "$LOG_FILE"
        echo -e "${WHITE}Tipos de registro: ${BLUE}$record_types${NC}" | tee -a "$LOG_FILE"
        
        # Converter strings em arrays
        IFS=',' read -ra groups_array <<< "$groups"
        IFS=',' read -ra record_types_array <<< "$record_types"
        
        # Processar hosts extras - CORREÇÃO AQUI
        local extra_hosts_array=()
        if [[ -n "$extra_hosts" ]]; then
            echo -e "${WHITE}Hosts extras: ${PURPLE}$extra_hosts${NC}" | tee -a "$LOG_FILE"
            IFS=',' read -ra extra_hosts_array <<< "$extra_hosts"
        else
            echo -e "${WHITE}Hosts extras: ${YELLOW}Nenhum${NC}" | tee -a "$LOG_FILE"
        fi
        
        echo | tee -a "$LOG_FILE"
        
        # Determinar tipos de teste
        local test_modes=()
        case "$test_types" in
            "both") test_modes=("iterative" "recursive") ;;
            "iterative") test_modes=("iterative") ;;
            "recursive") test_modes=("recursive") ;;
            *) log_color "$RED" "AVISO: Tipo de teste desconhecido: $test_types para $domain" "error"; continue ;;
        esac
        
        # Executar testes para cada grupo
        for group in "${groups_array[@]}"; do
            if [[ -z "${DNS_GROUPS[$group]}" ]]; then
                log_color "$RED" "ERRO: Grupo $group não encontrado para domínio $domain" "error"
                continue
            fi
            
            # Obter servidores do grupo
            local servers=(${DNS_GROUPS[$group]})
            local group_type="${DNS_GROUP_TYPE[$group]}"
            local group_desc="${DNS_GROUP_DESC[$group]}"
            
            log_color "$GREEN" "Testando grupo: $group ($group_type - $group_desc)" "success"
            
            for test_mode in "${test_modes[@]}"; do
                # Validar combinação teste/grupo
                if [[ "$group_type" == "authoritative" && "$test_mode" == "recursive" ]]; then
                    log_color "$YELLOW" "AVISO: Teste recursivo ignorado para grupo autoritativo: $group" "warning"
                    continue
                fi
                
                if [[ "$group_type" == "recursive" && "$test_mode" == "iterative" ]]; then
                    log_color "$YELLOW" "AVISO: Teste iterativo ignorado para grupo recursivo: $group" "warning"
                    continue
                fi
                
                for record_type in "${record_types_array[@]}"; do
                    for server in "${servers[@]}"; do
                        # Validar conectividade se configurado
                        if [[ "$VALIDATE_CONNECTIVITY" == "true" ]]; then
                            if ! validate_connectivity "$server" "$TIMEOUT"; then
                                log_color "$RED" "ERRO: Servidor $server não responde na porta 53" "error"
                                continue
                            fi
                        fi
                        
                        ((test_count++))
                        log_test "Testando: Grupo $group | $test_mode | $domain | $record_type | Servidor: $server"
                        run_dig_test "$server" "$domain" "$record_type" "$test_mode" "$group"
                        
                        # CORREÇÃO: Testar hosts extras para QUALQUER tipo de registro, não apenas A
                        if [[ ${#extra_hosts_array[@]} -gt 0 ]]; then
                            for host in "${extra_hosts_array[@]}"; do
                                local full_domain="${host}.${domain}"
                                ((test_count++))
                                log_test "Testando host extra: Grupo $group | $test_mode | $full_domain | $record_type | Servidor: $server"
                                run_dig_test "$server" "$full_domain" "$record_type" "$test_mode" "$group"
                            done
                        fi
                    done
                done
            done
        done
        echo | tee -a "$LOG_FILE"
        
    done < domains_tests.csv
    
    log_color "$GREEN" "RESUMO: Processados $domain_count domínios, executados $test_count testes" "success"
}

generate_summary() {
    log_section "RELATÓRIO DE EXECUÇÃO"
    echo -e "${WHITE}Arquivo de log: ${CYAN}$LOG_FILE${NC}" | tee -a "$LOG_FILE"
    echo -e "${WHITE}Relatório HTML: ${CYAN}$HTML_FILE${NC}" | tee -a "$LOG_FILE"
    echo -e "${WHITE}Timestamp de início: ${CYAN}$TIMESTAMP${NC}" | tee -a "$LOG_FILE"
    echo -e "${WHITE}Configurações carregadas:${NC}" | tee -a "$LOG_FILE"
    echo -e "  ${WHITE}- DEFAULT_DIG_OPTIONS: ${CYAN}$DEFAULT_DIG_OPTIONS${NC}" | tee -a "$LOG_FILE"
    echo -e "  ${WHITE}- RECURSIVE_DIG_OPTIONS: ${CYAN}$RECURSIVE_DIG_OPTIONS${NC}" | tee -a "$LOG_FILE"
    echo -e "  ${WHITE}- VALIDATE_CONNECTIVITY: ${CYAN}$VALIDATE_CONNECTIVITY${NC}" | tee -a "$LOG_FILE"
    echo -e "  ${WHITE}- TIMEOUT: ${CYAN}$TIMEOUT${NC}" | tee -a "$LOG_FILE"
    echo -e "  ${WHITE}- GENERATE_HTML: ${CYAN}$GENERATE_HTML${NC}" | tee -a "$LOG_FILE"
    echo -e "  ${WHITE}- SLEEP: ${CYAN}${SLEEP}s${NC}" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo -e "${WHITE}Grupos DNS carregados:${NC}" | tee -a "$LOG_FILE"
    for group in "${!DNS_GROUPS[@]}"; do
        echo -e "  ${WHITE}- $group: ${YELLOW}${DNS_GROUP_TYPE[$group]}${WHITE} (${GREEN}${DNS_GROUPS[$group]// /, }${WHITE})${NC}" | tee -a "$LOG_FILE"
    done
    echo | tee -a "$LOG_FILE"
}

main() {
    # Inicializar relatório HTML
    if [[ "$GENERATE_HTML" == "true" ]]; then
        init_html_report
    fi
    
    log_section "INICIANDO DIAGNÓSTICO DNS"
    
    # Verificar se bc está instalado (necessário para comparações decimais)
    if ! command -v bc &> /dev/null && [[ $(echo "$SLEEP > 0" | bc -l &>/dev/null; echo $?) -ne 0 ]]; then
        log_color "$YELLOW" "AVISO: comando 'bc' não encontrado. Intervalos decimais podem não funcionar corretamente." "warning"
    fi
    
    # Verificar arquivos necessários
    if [[ ! -f "dns_groups.csv" ]]; then
        log_color "$RED" "ERRO: dns_groups.csv não encontrado" "error"
        exit 1
    fi
    
    if [[ ! -f "domains_tests.csv" ]]; then
        log_color "$RED" "ERRO: domains_tests.csv não encontrado" "error"
        exit 1
    fi
    
    # Verificar dependências
    if ! command -v dig &> /dev/null; then
        log_color "$RED" "ERRO: comando 'dig' não encontrado. Instale o pacote dnsutils." "error"
        exit 1
    fi
    
    if ! command -v nc &> /dev/null && [[ "$VALIDATE_CONNECTIVITY" == "true" ]]; then
        log_color "$YELLOW" "AVISO: comando 'nc' não encontrado. Validação de conectividade desativada." "warning"
        VALIDATE_CONNECTIVITY="false"
    fi
    
    # Reiniciar contador de testes
    TEST_COUNTER=0
    
    load_dns_groups
    generate_summary
    process_domain_tests
    
    # Finalizar relatório HTML
    if [[ "$GENERATE_HTML" == "true" ]]; then
        finalize_html_report
    fi
    
    log_section "DIAGNÓSTICO CONCLUÍDO"
    log_color "$GREEN" "Relatório completo disponível em: $LOG_FILE" "success"
    if [[ "$GENERATE_HTML" == "true" ]]; then
        log_color "$GREEN" "Relatório HTML disponível em: $HTML_FILE" "success"
    fi
    log_color "$GREEN" "Total de testes executados: $(printf "%02d" $TEST_COUNTER)" "success"
    log_color "$GREEN" "Intervalo utilizado entre comandos: ${SLEEP}s" "success"
    log_color "$GREEN" "https://github.com/flashbsb/diagnostico_dns"
}

main "$@"
