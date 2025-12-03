#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS AVANÇADO (Matrix Edition)
# Versão: 3.0
# "Agora com tabelas que o gerente consegue ler."
# ==============================================

# Configurações padrão
DEFAULT_DIG_OPTIONS="+norecurse +time=1 +tries=1 +nocookie +cd +bufsize=512"
RECURSIVE_DIG_OPTIONS="+time=1 +tries=1 +nocookie +cd +bufsize=512"
LOG_PREFIX="dnsdiag"
TIMEOUT=5
VALIDATE_CONNECTIVITY=true
GENERATE_HTML=true
GENERATE_JSON=false
SLEEP=0.1
VERBOSE=true
QUIET=false
IP_VERSION="ipv4"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Cache e Stats
declare -A CONNECTIVITY_CACHE
declare -i TOTAL_TESTS=0
declare -i SUCCESS_TESTS=0
declare -i FAILED_TESTS=0
declare -i TIMEOUT_TESTS=0

# Carregar config
[[ -f "script_config.cfg" ]] && source script_config.cfg

# Setup Logs
mkdir -p logs
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="logs/${LOG_PREFIX}_${TIMESTAMP}.txt"
HTML_FILE="logs/${LOG_PREFIX}_${TIMESTAMP}.html"
JSON_FILE="logs/${LOG_PREFIX}_${TIMESTAMP}.json"

# ==============================================
# FUNÇÕES DE INFRAESTRUTURA
# ==============================================

check_port_bash() {
    timeout "$3" bash -c "cat < /dev/tcp/$1/$2" &>/dev/null
    return $?
}

validate_connectivity() {
    local server="$1"
    local timeout="${2:-$TIMEOUT}"
    
    [[ -n "${CONNECTIVITY_CACHE[$server]}" ]] && return ${CONNECTIVITY_CACHE[$server]}
    
    local status=1
    if command -v nc &> /dev/null; then
        nc -z -w "$timeout" "$server" 53 2>/dev/null
        status=$?
    else
        check_port_bash "$server" 53 "$timeout"
        status=$?
    fi

    CONNECTIVITY_CACHE[$server]=$status
    return $status
}

validate_csv_file() {
    [[ ! -s "$1" ]] && { echo "Erro: $1 vazio."; return 1; }
    return 0
}

json_escape() { echo "$1" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g'; }

# ==============================================
# REPORTING HTML (O Pulo do Gato 😺)
# ==============================================

init_html_report() {
    [[ "$GENERATE_HTML" != "true" ]] && return
    cat > "$HTML_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>DNS Matrix - $TIMESTAMP</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #1e1e1e; color: #d4d4d4; margin: 20px; }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { color: #ce9178; text-align: center; }
        
        /* Domain Block */
        .domain-block { background: #252526; margin-bottom: 30px; border-radius: 8px; border-left: 5px solid #007acc; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
        .domain-header { background: #2d2d30; padding: 15px; font-size: 1.2em; font-weight: bold; color: #fff; border-bottom: 1px solid #3e3e42; display: flex; justify-content: space-between; }
        
        /* Tables */
        .group-table { width: 100%; border-collapse: collapse; margin: 0; }
        .group-table th, .group-table td { padding: 10px; text-align: left; border-bottom: 1px solid #3e3e42; border-right: 1px solid #3e3e42; }
        .group-table th { background: #333333; color: #9cdcfe; font-weight: 600; }
        .group-table tr:hover { background: #2a2d2e; }
        
        /* Status Cells */
        .status-ok { color: #4ec9b0; font-weight: bold; }
        .status-fail { color: #f44747; font-weight: bold; background: rgba(244, 71, 71, 0.1); }
        .status-timeout { color: #ffcc02; font-weight: bold; }
        .meta-info { font-size: 0.8em; color: #808080; }
        
        /* Dig Output Modal/Tooltip (Simplificado como texto oculto) */
        .dig-output { display: none; }
        
        .badge { padding: 2px 6px; border-radius: 4px; font-size: 0.8em; background: #3e3e42; margin-right: 5px; }
        .badge-iterative { color: #569cd6; border: 1px solid #569cd6; }
        .badge-recursive { color: #c586c0; border: 1px solid #c586c0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Diagnóstico DNS - Visão Matricial</h1>
EOF
}

# Funções auxiliares de HTML para criar estrutura
html_start_domain() {
    [[ "$GENERATE_HTML" == "true" ]] && echo "<div class=\"domain-block\"><div class=\"domain-header\"><span>🌐 $1</span><span style=\"font-size:0.8em; opacity:0.7\">$2</span></div>" >> "$HTML_FILE"
}

html_end_domain() {
    [[ "$GENERATE_HTML" == "true" ]] && echo "</div>" >> "$HTML_FILE"
}

html_start_group_table() {
    local group_name=$1
    local servers_arr=("${@:2}")
    
    if [[ "$GENERATE_HTML" == "true" ]]; then
        echo "<div style=\"padding: 10px; background: #1e1e1e; border-bottom: 1px solid #333;\"><strong style=\"color: #dcdcaa\">GRUPO: $group_name</strong></div>" >> "$HTML_FILE"
        echo "<table class=\"group-table\"><thead><tr><th style=\"width: 30%\">Target / Record</th>" >> "$HTML_FILE"
        for srv in "${servers_arr[@]}"; do
            echo "<th>$srv</th>" >> "$HTML_FILE"
        done
        echo "</tr></thead><tbody>" >> "$HTML_FILE"
    fi
}

html_end_group_table() {
    [[ "$GENERATE_HTML" == "true" ]] && echo "</tbody></table>" >> "$HTML_FILE"
}

finalize_html_report() {
    [[ "$GENERATE_HTML" == "true" ]] && echo "</div></body></html>" >> "$HTML_FILE"
}

# ==============================================
# LOGGING
# ==============================================
log_msg() {
    local msg="$(date '+%H:%M:%S') - $1"
    [[ "$QUIET" == "false" ]] && echo -e "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# ==============================================
# CORE
# ==============================================

load_dns_groups() {
    declare -gA DNS_GROUPS
    declare -gA DNS_GROUP_DESC
    declare -gA DNS_GROUP_TYPE
    declare -gA DNS_GROUP_TIMEOUT
    
    while IFS=';' read -r name desc type timeout servers || [ -n "$name" ]; do
        [[ "$name" =~ ^# || -z "$name" ]] && continue
        name=$(echo "$name" | xargs); servers=$(echo "$servers" | tr -d '[:space:]')
        [[ -z "$timeout" ]] && timeout=$TIMEOUT
        IFS=',' read -ra srv_arr <<< "$servers"
        DNS_GROUPS["$name"]="${srv_arr[@]}"
        DNS_GROUP_DESC["$name"]="$desc"
        DNS_GROUP_TYPE["$name"]="$type"
        DNS_GROUP_TIMEOUT["$name"]="$timeout"
    done < dns_groups.csv
}

# Executa o dig e retorna o status code E o output (via variavel global temporaria ou echo)
run_dig_capture() {
    local srv=$1; local dom=$2; local type=$3; local mode=$4
    local opts
    [[ "$mode" == "iterative" ]] && opts="$DEFAULT_DIG_OPTIONS" || opts="$RECURSIVE_DIG_OPTIONS"
    [[ "$IP_VERSION" == "ipv4" ]] && opts="$opts -4"
    
    local start_ts=$(date +%s%N)
    local output=$(dig $opts @$srv $dom $type 2>&1)
    local ret=$?
    local end_ts=$(date +%s%N)
    local duration_ms=$(( (end_ts - start_ts) / 1000000 ))
    
    # Salva no log cru
    echo "[$srv -> $dom ($type)] Ret: $ret Time: ${duration_ms}ms" >> "$LOG_FILE"
    
    # Retorna string formatada para o HTML: "RET_CODE|DURATION|OUTPUT_SHORT"
    # Pegando só o status do output para economizar bytes na string de retorno
    local status_txt="UNKNOWN"
    if echo "$output" | grep -q "NOERROR"; then status_txt="NOERROR"
    elif echo "$output" | grep -q "NXDOMAIN"; then status_txt="NXDOMAIN"
    elif echo "$output" | grep -q "SERVFAIL"; then status_txt="SERVFAIL"
    elif echo "$output" | grep -q "REFUSED"; then status_txt="REFUSED"
    elif echo "$output" | grep -q "timed out"; then status_txt="TIMEOUT"
    fi
    
    echo "$ret|$duration_ms|$status_txt"
}

process_tests() {
    log_msg "${BLUE}Iniciando processamento matricial...${NC}"
    
    while IFS=';' read -r domain groups test_types record_types extra_hosts || [ -n "$domain" ]; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        
        # Limpeza
        domain=$(echo "$domain" | xargs)
        groups=$(echo "$groups" | tr -d '[:space:]')
        IFS=',' read -ra group_list <<< "$groups"
        IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
        
        log_msg "${CYAN}>> Processando Domínio: $domain${NC}"
        html_start_domain "$domain" "Grupos: $groups | Testes: $test_types"
        
        # Determina modos
        local modes=()
        if [[ "$test_types" == *"both"* ]]; then modes=("iterative" "recursive")
        elif [[ "$test_types" == *"recursive"* ]]; then modes=("recursive")
        else modes=("iterative"); fi
        
        # --- LOOP DE GRUPOS ---
        for grp in "${group_list[@]}"; do
            [[ -z "${DNS_GROUPS[$grp]}" ]] && continue
            
            local srv_list=(${DNS_GROUPS[$grp]})
            html_start_group_table "$grp" "${srv_list[@]}"
            
            # Prepara lista de alvos (Dominio principal + Extras)
            local targets=("$domain")
            for ex in "${extra_list[@]}"; do targets+=("$ex.$domain"); done
            
            # --- LOOP DE LINHAS DA TABELA (Targets * Records * Modes) ---
            for mode in "${modes[@]}"; do
                # Validação de tipo de grupo
                [[ "${DNS_GROUP_TYPE[$grp]}" == "authoritative" && "$mode" == "recursive" ]] && continue
                [[ "${DNS_GROUP_TYPE[$grp]}" == "recursive" && "$mode" == "iterative" ]] && continue
                
                for target in "${targets[@]}"; do
                    for rec in "${rec_list[@]}"; do
                        
                        # Inicia Linha HTML
                        [[ "$GENERATE_HTML" == "true" ]] && echo "<tr><td><span class=\"badge badge-$mode\">$mode</span> <strong>$target</strong> <span class=\"meta-info\">($rec)</span></td>" >> "$HTML_FILE"
                        
                        # --- LOOP DE COLUNAS (Servidores) ---
                        for srv in "${srv_list[@]}"; do
                            
                            # Valida Conectividade
                            if [[ "$VALIDATE_CONNECTIVITY" == "true" ]]; then
                                if ! validate_connectivity "$srv" "${DNS_GROUP_TIMEOUT[$grp]}"; then
                                    [[ "$GENERATE_HTML" == "true" ]] && echo "<td><span class=\"status-fail\">DOWN</span></td>" >> "$HTML_FILE"
                                    log_msg "${RED}Falha conexao: $srv${NC}"
                                    continue
                                fi
                            fi
                            
                            # RODA O DIG
                            local result_str=$(run_dig_capture "$srv" "$target" "$rec" "$mode")
                            IFS='|' read -r ret_code duration status_txt <<< "$result_str"
                            
                            # HTML Cell Logic
                            local cell_class="status-ok"
                            local icon="✅"
                            
                            if [[ "$ret_code" -ne 0 ]] || [[ "$status_txt" == "TIMEOUT" ]]; then
                                cell_class="status-fail"
                                icon="❌"
                                FAILED_TESTS+=1
                            else
                                SUCCESS_TESTS+=1
                            fi
                            
                            if [[ "$GENERATE_HTML" == "true" ]]; then
                                echo "<td class=\"$cell_class\">$icon $status_txt <div class=\"meta-info\">${duration}ms</div></td>" >> "$HTML_FILE"
                            fi
                            
                            # Console feedback minimalista (ponto progressivo)
                            if [[ "$ret_code" -eq 0 ]]; then echo -n "."; else echo -n "x"; fi
                            
                            TOTAL_TESTS+=1
                            [[ "$SLEEP" != "0" ]] && sleep "$SLEEP"
                        done
                        
                        # Fecha Linha HTML
                        [[ "$GENERATE_HTML" == "true" ]] && echo "</tr>" >> "$HTML_FILE"
                    done
                done
            done
            html_end_group_table
        done
        
        echo "" # Quebra de linha no console após o domínio
        html_end_domain
        
    done < domains_tests.csv
}

# ==============================================
# MAIN
# ==============================================

main() {
    if ! command -v dig &> /dev/null; then echo "Instale o dig (bind-utils)"; exit 1; fi
    
    init_html_report
    load_dns_groups
    process_tests
    finalize_html_report
    
    echo -e "\n${GREEN}=== DIAGNÓSTICO CONCLUÍDO ===${NC}"
    echo "Total: $TOTAL_TESTS | Sucesso: $SUCCESS_TESTS | Falha: $FAILED_TESTS"
    echo "Relatório: $HTML_FILE"
}

main "$@"
