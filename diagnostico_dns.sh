#!/bin/bash

# ==============================================
# SCRIPT DIAGNÓSTICO DNS - RANGE EDITION
# Versão: 7.2
# "Agora informa os IDs dos testes no cabeçalho."
# ==============================================

# --- CONFIGURAÇÕES PADRÃO ---
DEFAULT_DIG_OPTIONS="+norecurse +time=1 +tries=1 +nocookie +cd +bufsize=512"
RECURSIVE_DIG_OPTIONS="+time=1 +tries=1 +nocookie +cd +bufsize=512"
LOG_PREFIX="dnsdiag"
TIMEOUT=5
VALIDATE_CONNECTIVITY=true
GENERATE_HTML=true
SLEEP=1.50
VERBOSE=true
IP_VERSION="ipv4"
MAX_RETRIES=1
CHECK_BIND_VERSION=false

# Arquivos Padrão
FILE_DOMAINS="domains_tests.csv"
FILE_GROUPS="dns_groups.csv"

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
declare -i TOTAL_TESTS=0
declare -i SUCCESS_TESTS=0
declare -i FAILED_TESTS=0
declare -i WARNING_TESTS=0

# Carregar config externa
[[ -f "script_config.cfg" ]] && source script_config.cfg

# Setup Arquivos
mkdir -p logs
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HTML_FILE="logs/${LOG_PREFIX}_${TIMESTAMP}.html"
TEMP_HEADER="logs/temp_header_${TIMESTAMP}.html"
TEMP_STATS="logs/temp_stats_${TIMESTAMP}.html"
TEMP_MATRIX="logs/temp_matrix_${TIMESTAMP}.html"
TEMP_DETAILS="logs/temp_details_${TIMESTAMP}.html"

# ==============================================
# HELP & BANNER
# ==============================================

show_help() {
    echo -e "${BLUE}Diagnóstico DNS Avançado - v7.2${NC}"
    echo -e "Uso: $0 [opções]"
    echo -e "Opções:"
    echo -e "  ${GREEN}-n <arquivo>${NC}   Arquivo de domínios (Default: domains_tests.csv)"
    echo -e "  ${GREEN}-g <arquivo>${NC}   Arquivo de grupos (Default: dns_groups.csv)"
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
    echo ""
    echo -e "${PURPLE}[DEBUG & CONTROLE]${NC}"
    echo -e "  📢 Verbose Mode  : ${CYAN}${VERBOSE}${NC}"
    echo -e "  🛠️  Dig Options   : ${GRAY}${DEFAULT_DIG_OPTIONS:0:40}...${NC}"
    echo ""
    echo -e "${PURPLE}[SAÍDA]${NC}"
    echo -e "  📄 Relatório HTML: ${GREEN}$HTML_FILE${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo ""
}

# ==============================================
# INFRA & DEBUG PRINT
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

print_verbose_debug() {
    local type="$1"
    local msg="$2"
    local srv="$3"
    local target="$4"
    local raw_output="$5"
    local dur="$6"

    local color=$NC
    local label=""
    case "$type" in
        "FAIL") color=$RED; label="FALHA CRÍTICA" ;;
        "WARN") color=$YELLOW; label="ALERTA/ATENÇÃO" ;;
        *) color=$CYAN; label="INFO" ;;
    esac

    echo -e "\n${color}    ┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${color}    │ [DEBUG] $label: $msg ${NC}"
    echo -e "${color}    ├─────────────────────────────────────────────────────────────┤${NC}"
    echo -e "    │ 🎯 Alvo    : $target"
    echo -e "    │ 🖥️  Server  : $srv"
    echo -e "    │ ⏱️  Tempo   : ${dur}ms"
    
    if [[ -n "$raw_output" ]]; then
        echo -e "${color}    ├───────────────────── DADOS DO PROTOCOLO ────────────────────┤${NC}"
        local headers=$(echo "$raw_output" | grep -E ";; ->>HEADER<<-" | head -1 | sed 's/;; //')
        local flags=$(echo "$raw_output" | grep -E ";; flags:" | head -1 | sed 's/;; //')
        local msg_size=$(echo "$raw_output" | grep -E ";; MSG SIZE" | head -1 | sed 's/;; //')
        local error_line=$(echo "$raw_output" | grep -iE "connection timed out|network is unreachable|communications error|end of file" | head -1)

        [[ -n "$headers" ]] && echo -e "    │ 🏷️  Header  : $headers"
        [[ -n "$flags" ]]   && echo -e "    │ 🏳️  Flags   : $flags"
        [[ -n "$msg_size" ]] && echo -e "    │ 📦 Size    : $msg_size"
        [[ -n "$error_line" ]] && echo -e "    │ ⚠️  SysMsg  : $error_line"
    fi
    echo -e "${color}    └─────────────────────────────────────────────────────────────┘${NC}"
}

# ==============================================
# GERAÇÃO HTML
# ==============================================

init_html_parts() { > "$TEMP_HEADER"; > "$TEMP_STATS"; > "$TEMP_MATRIX"; > "$TEMP_DETAILS"; }

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
        .dashboard { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 30px; }
        .card { background: #252526; padding: 15px; border-radius: 6px; text-align: center; border-bottom: 3px solid #444; }
        .card-num { font-size: 2em; font-weight: bold; display: block; }
        .card-label { font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; color: #888; }
        .st-total { border-color: #007acc; } .st-total .card-num { color: #007acc; }
        .st-ok { border-color: #4ec9b0; } .st-ok .card-num { color: #4ec9b0; }
        .st-warn { border-color: #ffcc02; } .st-warn .card-num { color: #ffcc02; }
        .st-fail { border-color: #f44747; } .st-fail .card-num { color: #f44747; }
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
        .tech-section { margin-top: 50px; border-top: 3px dashed #3e3e42; padding-top: 20px; }
        .tech-controls { margin-bottom: 15px; }
        .btn-ctrl { background: #3e3e42; color: white; border: none; padding: 5px 10px; border-radius: 3px; cursor: pointer; margin-right: 10px; font-size: 0.9em; }
        .btn-ctrl:hover { background: #007acc; }
        details { background: #1e1e1e; margin-bottom: 10px; border: 1px solid #333; border-radius: 4px; }
        summary { cursor: pointer; padding: 10px; background: #252526; list-style: none; font-family: monospace; }
        summary:hover { background: #2a2d2e; }
        summary::-webkit-details-marker { display: none; }
        .log-header { display: flex; align-items: center; gap: 10px; }
        .log-id { background: #007acc; color: white; padding: 2px 6px; border-radius: 3px; font-size: 0.8em; }
        pre { background: #000; color: #ccc; padding: 15px; margin: 0; overflow-x: auto; border-top: 1px solid #333; font-family: 'Consolas', monospace; font-size: 0.85em; }
        .badge { padding: 2px 5px; border-radius: 3px; font-size: 0.8em; border: 1px solid #444; }
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

assemble_html() {
    generate_stats_block
    cat "$TEMP_HEADER" >> "$HTML_FILE"
    cat "$TEMP_STATS" >> "$HTML_FILE"
    cat "$TEMP_MATRIX" >> "$HTML_FILE"
    cat >> "$HTML_FILE" << EOF
        <div class="tech-section">
            <div style="display:flex; justify-content:space-between; align-items:center;">
                <h2>🛠️ Logs Técnicos Detalhados</h2>
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
    rm -f "$TEMP_HEADER" "$TEMP_STATS" "$TEMP_MATRIX" "$TEMP_DETAILS"
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

process_tests() {
    [[ ! -f "$FILE_DOMAINS" ]] && { echo -e "${RED}ERRO: $FILE_DOMAINS não encontrado!${NC}"; exit 1; }

    echo -e "LEGENDA DE EXECUÇÃO:"
    echo -e "  ${GREEN}.${NC} = Sucesso (NOERROR)"
    echo -e "  ${YELLOW}!${NC} = Alerta (NXDOMAIN / SERVFAIL)"
    echo -e "  ${RED}x${NC} = Falha Crítica (TIMEOUT / REFUSED)"
    echo ""
    
    local test_id=0
    
    while IFS=';' read -r domain groups test_types record_types extra_hosts || [ -n "$domain" ]; do
        [[ "$domain" =~ ^# || -z "$domain" ]] && continue
        
        domain=$(echo "$domain" | xargs)
        groups=$(echo "$groups" | tr -d '[:space:]')
        IFS=',' read -ra group_list <<< "$groups"
        IFS=',' read -ra rec_list <<< "$(echo "$record_types" | tr -d '[:space:]')"
        IFS=',' read -ra extra_list <<< "$(echo "$extra_hosts" | tr -d '[:space:]')"
        
        echo -e "${CYAN}>> Domínio: ${WHITE}${domain} ${PURPLE}[${record_types}]${NC}"

        # ----------------------------------------------------
        # PRÉ-CÁLCULO DE TESTES PARA O HTML
        # ----------------------------------------------------
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
                 [[ "${DNS_GROUP_TYPE[$grp]}" == "authoritative" && "$mode" == "recursive" ]] && continue
                 [[ "${DNS_GROUP_TYPE[$grp]}" == "recursive" && "$mode" == "iterative" ]] && continue
                 for t in "${calc_targets[@]}"; do
                     for r in "${rec_list[@]}"; do
                         calc_count=$((calc_count + num_srv))
                     done
                 done
            done
        done
        
        local start_id=$((test_id + 1))
        local end_id=$((test_id + calc_count))
        local range_txt="(Tests #$start_id - #$end_id)"
        [[ $calc_count -eq 0 ]] && range_txt=""
        # ----------------------------------------------------
        
        # Header com o range incluído
        echo "<div class=\"domain-block\"><div class=\"domain-header\"><span>🌐 $domain <span style=\"font-size:0.8em; color:#bbb; font-weight:normal; margin-left:10px;\">$range_txt</span></span><span class=\"badge\">$test_types</span></div>" >> "$TEMP_MATRIX"
        
        local modes=("${calc_modes[@]}") # Reutiliza array calculado
        
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
                [[ "${DNS_GROUP_TYPE[$grp]}" == "authoritative" && "$mode" == "recursive" ]] && continue
                [[ "${DNS_GROUP_TYPE[$grp]}" == "recursive" && "$mode" == "iterative" ]] && continue
                
                for target in "${targets[@]}"; do
                    for rec in "${rec_list[@]}"; do
                        echo "<tr><td><span class=\"badge\">$mode</span> <strong>$target</strong> <span style=\"color:#666\">($rec)</span></td>" >> "$TEMP_MATRIX"
                        
                        for srv in "${srv_list[@]}"; do
                            test_id=$((test_id + 1))
                            TOTAL_TESTS+=1
                            local unique_id="test_${test_id}"
                            
                            # === VALIDAÇÃO CONEXÃO ===
                            if [[ "$VALIDATE_CONNECTIVITY" == "true" ]]; then
                                if ! validate_connectivity "$srv" "${DNS_GROUP_TIMEOUT[$grp]}"; then
                                    FAILED_TESTS+=1
                                    # HTML
                                    echo "<td><a href=\"#$unique_id\" class=\"cell-link status-fail\">❌ DOWN</a></td>" >> "$TEMP_MATRIX"
                                    echo "<details id=\"$unique_id\"><summary class=\"log-header\"><span class=\"log-id\">#$test_id</span> <span style=\"color:#f44747\">FALHA CONEXÃO</span> $srv</summary><pre>Porta 53 inacessível (TCP/UDP).</pre></details>" >> "$TEMP_DETAILS"
                                    
                                    # CONSOLE
                                    echo -ne "${RED}x${NC}"
                                    if [[ "$VERBOSE" == "true" ]]; then
                                        print_verbose_debug "FAIL" "Servidor não responde na porta 53" "$srv" "$target ($rec)" "" "N/A"
                                    fi
                                    continue
                                fi
                            fi
                            
                            # === EXECUÇÃO DIG ===
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
                            
                            local status_txt="OK"
                            local css_class="status-ok"
                            local icon="✅"
                            
                            # === ANÁLISE DE RESULTADOS ===
                            if [[ $ret -ne 0 ]]; then
                                status_txt="ERR:$ret"; css_class="status-fail"; icon="❌"; FAILED_TESTS+=1
                                echo -ne "${RED}x${NC}"
                                [[ "$VERBOSE" == "true" ]] && print_verbose_debug "FAIL" "Erro de Execução DIG (Code $ret)" "$srv" "$target ($rec)" "$output" "$dur"

                            elif echo "$output" | grep -q "status: SERVFAIL"; then
                                status_txt="SERVFAIL"; css_class="status-warning"; icon="⚠️"; WARNING_TESTS+=1
                                echo -ne "${YELLOW}!${NC}"
                                [[ "$VERBOSE" == "true" ]] && print_verbose_debug "WARN" "SERVFAIL (Falha no servidor)" "$srv" "$target ($rec)" "$output" "$dur"

                            elif echo "$output" | grep -q "status: NXDOMAIN"; then
                                status_txt="NXDOMAIN"; css_class="status-warning"; icon="🔸"; WARNING_TESTS+=1
                                echo -ne "${YELLOW}!${NC}"
                                # NXDOMAIN não gera debug verbose pois pode ser comportamento esperado

                            elif echo "$output" | grep -q "status: REFUSED"; then
                                status_txt="REFUSED"; css_class="status-fail"; icon="⛔"; FAILED_TESTS+=1
                                echo -ne "${RED}x${NC}"
                                [[ "$VERBOSE" == "true" ]] && print_verbose_debug "FAIL" "REFUSED (Acesso negado/ACL)" "$srv" "$target ($rec)" "$output" "$dur"

                            elif echo "$output" | grep -q "connection timed out"; then
                                status_txt="TIMEOUT"; css_class="status-fail"; icon="⏳"; FAILED_TESTS+=1
                                echo -ne "${RED}x${NC}"
                                [[ "$VERBOSE" == "true" ]] && print_verbose_debug "FAIL" "TIMEOUT (Sem resposta)" "$srv" "$target ($rec)" "$output" "$dur"

                            else
                                SUCCESS_TESTS+=1
                                echo -ne "${GREEN}.${NC}"
                            fi
                            
                            # Escrita HTML
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
    while getopts ":n:g:h" opt; do
        case ${opt} in
            n) FILE_DOMAINS=$OPTARG ;;
            g) FILE_GROUPS=$OPTARG ;;
            h) show_help; exit 0 ;;
            \?) echo -e "${RED}Opção inválida: -$OPTARG${NC}" >&2; show_help; exit 1 ;;
        esac
    done

    if ! command -v dig &> /dev/null; then echo "Erro: 'dig' nao encontrado."; exit 1; fi
    print_execution_summary
    init_html_parts
    write_html_header
    load_dns_groups
    process_tests
    assemble_html
    
    echo -e "\n${GREEN}=== DIAGNÓSTICO CONCLUÍDO ===${NC}"
    echo "Total: $TOTAL_TESTS | Sucesso: $SUCCESS_TESTS | Alertas: $WARNING_TESTS | Falhas: $FAILED_TESTS"
    echo -e "Relatório Gerado: ${CYAN}$HTML_FILE${NC}"
}

main "$@"
