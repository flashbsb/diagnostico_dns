#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
DIAGNÓSTICO DNS - PY EDITION (Versão Definitiva)
Versão: 10.1 (Stable - Bugfixes Applied)

Requisitos:
1. Python 3.6+
2. 'dig' instalado e no PATH do sistema (bind-utils no Linux / BIND Tools no Windows)
3. (Opcional) 'pip install colorama' para cores nativas no Windows
"""

import sys
import os
import time
import csv
import socket
import argparse
import platform
import subprocess
import threading
import datetime
import re  # Necessário para extrair contagem de respostas
from concurrent.futures import ThreadPoolExecutor, as_completed

# ==============================================
# TRATAMENTO DE CORES (Cross-Platform)
# ==============================================
try:
    from colorama import init, Fore, Style
    init()
    HAS_COLORAMA = True
except ImportError:
    HAS_COLORAMA = False
    # Definições manuais completas de ANSI
    class Fore:
        BLACK = '\033[30m'
        RED = '\033[91m'
        GREEN = '\033[92m'
        YELLOW = '\033[93m'
        BLUE = '\033[94m'
        CYAN = '\033[96m'
        MAGENTA = '\033[95m'
        WHITE = '\033[97m'
        RESET = '\033[0m'
    class Style:
        BRIGHT = '\033[1m'
        RESET_ALL = '\033[0m'

# ==============================================
# CONFIGURAÇÕES GLOBAIS
# ==============================================
CONFIG = {
    "TIMEOUT": 5.0,
    "SLEEP": 0.05,
    "VALIDATE_CONNECTIVITY": True,
    "GENERATE_HTML": True,
    "GENERATE_LOG_TEXT": False,
    "VERBOSE": False,
    "IP_VERSION": "ipv4",
    "CHECK_BIND": False,
    "ENABLE_PING": True,
    "PING_COUNT": 4,
    "PING_TIMEOUT": 2,
    "THREADS": 10,
    "FILES": {
        "DOMAINS": "domains_tests.csv",
        "GROUPS": "dns_groups.csv"
    }
}

# Constantes de Dig
DEFAULT_DIG_OPTS = ["+norecurse", "+time=1", "+tries=1", "+nocookie", "+cd", "+bufsize=512"]
RECURSIVE_DIG_OPTS = ["+time=1", "+tries=1", "+nocookie", "+cd", "+bufsize=512"]

# Controle de Estado e Locks
STATS = {
    "TOTAL": 0,
    "SUCCESS": 0,
    "FAILED": 0,
    "WARNING": 0
}
LOCK = threading.Lock()
HTML_CONN_ERR_LOGGED = set()
CONNECTIVITY_CACHE = {}

# Buffers para escrita
HTML_MATRIX_BUFFER = []
HTML_DETAILS_BUFFER = []
PING_RESULTS_BUFFER = []

# ==============================================
# UTILITÁRIOS
# ==============================================

def log_print(msg, color=Fore.CYAN, level="INFO"):
    """Printa bonito no terminal."""
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    with LOCK:
        # Usamos RESET aqui para garantir visibilidade do timestamp
        print(f"{Style.BRIGHT}[{ts}]{Style.RESET_ALL} {color}{msg}{Style.RESET_ALL}")

def file_log(msg):
    """Escreve no log de texto estilo forense."""
    if not CONFIG["GENERATE_LOG_TEXT"]: return
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with LOCK:
        with open(LOG_FILE_TEXT, "a", encoding="utf-8") as f:
            f.write(f"[{ts}] {msg}\n")

def check_dependencies():
    """Verifica se o usuário tem o dig instalado."""
    try:
        subprocess.run(["dig", "-v"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        print(f"{Fore.RED}ERRO CRÍTICO: O comando 'dig' não foi encontrado.{Fore.RESET}")
        print("Instale o BIND Tools. No Windows, coloque o dig.exe no PATH.")
        sys.exit(1)

# ==============================================
# NETWORK CORE
# ==============================================

def check_port(server, port=53, timeout=2.0):
    """Verifica conectividade TCP nativa do Python."""
    if server in CONNECTIVITY_CACHE:
        return CONNECTIVITY_CACHE[server]
    
    try:
        with socket.create_connection((server, port), timeout=timeout):
            res = True
    except (socket.timeout, ConnectionRefusedError, OSError):
        res = False
    
    with LOCK:
        CONNECTIVITY_CACHE[server] = res
    return res

def run_ping(ip):
    """Ping cross-platform."""
    sys_os = platform.system().lower()
    cmd = ["ping"]
    
    if "windows" in sys_os:
        cmd.extend(["-n", str(CONFIG["PING_COUNT"]), "-w", str(CONFIG["PING_TIMEOUT"] * 1000), ip])
    else: # Linux / Mac
        cmd.extend(["-c", str(CONFIG["PING_COUNT"]), "-W", str(CONFIG["PING_TIMEOUT"]), ip])
        
    start = time.time()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, errors='replace')
        duration = int((time.time() - start) * 1000)
        return proc.returncode, proc.stdout, duration
    except Exception as e:
        return 1, str(e), 0

def run_dig(server, target, record, mode="iterative"):
    """Roda o DIG e retorna output bruto."""
    cmd = ["dig"]
    if mode == "iterative":
        cmd.extend(DEFAULT_DIG_OPTS)
    else:
        cmd.extend(RECURSIVE_DIG_OPTS)
    
    if CONFIG["IP_VERSION"] == "ipv4":
        cmd.append("-4")
    elif CONFIG["IP_VERSION"] == "ipv6":
        cmd.append("-6")
        
    cmd.extend([f"@{server}", target, record])
    
    start = time.time()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, errors='replace')
        duration = int((time.time() - start) * 1000)
        return proc.returncode, proc.stdout, duration, " ".join(cmd)
    except Exception as e:
        return 999, str(e), 0, " ".join(cmd)

# ==============================================
# WORKER (Lógica Principal de Análise)
# ==============================================

def process_dns_task(task_data):
    """Thread Worker - Executa e analisa o teste DNS."""
    domain, group_name, srv, target, rec_type, mode, test_id = task_data
    
    # 1. Validação de Conectividade (TCP Check)
    if CONFIG["VALIDATE_CONNECTIVITY"]:
        if not check_port(srv, 53, CONFIG["TIMEOUT"]):
            with LOCK:
                STATS["FAILED"] += 1
                STATS["TOTAL"] += 1
                
                conn_id = f"conn_err_{srv.replace('.', '_')}"
                html_cell = f'<td><a href="#" onclick="showLog(\'{conn_id}\'); return false;" class="cell-link status-fail">❌ DOWN</a></td>'
                
                if srv not in HTML_CONN_ERR_LOGGED:
                    HTML_CONN_ERR_LOGGED.add(srv)
                    html_log = f'<details id="{conn_id}" class="conn-error-block"><summary class="log-header" style="color:#f44747"><span class="log-id">GLOBAL</span> <strong>FALHA CONEXÃO</strong> - {srv}</summary><pre style="border-top:1px solid #f44747; color:#f44747">Servidor {srv} inalcançável na porta 53 TCP.\nTestes abortados.</pre></details>'
                    HTML_DETAILS_BUFFER.append(html_log)
                    
                file_log(f"CRITICAL: Falha de Conectividade -> {srv}:53")
                print(f"{Fore.RED}x{Style.RESET_ALL}", end="", flush=True)
                return (group_name, target, rec_type, mode, html_cell)

    # 2. Execução do Dig
    ret_code, output, duration, full_cmd = run_dig(srv, target, rec_type, mode)
    
    # 3. Análise do Resultado
    status_txt = "OK"
    css_class = "status-ok"
    icon = "✅"
    log_color = ""
    
    # Extrai contador de respostas (Regex)
    answer_match = re.search(r"ANSWER:\s+(\d+)", output)
    answer_count = int(answer_match.group(1)) if answer_match else 0

    if ret_code != 0:
        status_txt = f"ERR:{ret_code}"
        css_class = "status-fail"
        icon = "❌"
        with LOCK: STATS["FAILED"] += 1
        print(f"{Fore.RED}x{Style.RESET_ALL}", end="", flush=True)

    elif "status: SERVFAIL" in output:
        status_txt = "SERVFAIL"
        css_class = "status-warning"
        icon = "⚠️"
        with LOCK: STATS["WARNING"] += 1
        print(f"{Fore.YELLOW}!{Style.RESET_ALL}", end="", flush=True)

    elif "status: NXDOMAIN" in output:
        status_txt = "NXDOMAIN"
        css_class = "status-warning"
        icon = "🔸"
        with LOCK: STATS["WARNING"] += 1
        print(f"{Fore.YELLOW}!{Style.RESET_ALL}", end="", flush=True)

    elif "status: REFUSED" in output:
        status_txt = "REFUSED"
        css_class = "status-fail"
        icon = "⛔"
        with LOCK: STATS["FAILED"] += 1
        print(f"{Fore.RED}x{Style.RESET_ALL}", end="", flush=True)

    elif "connection timed out" in output:
        status_txt = "TIMEOUT"
        css_class = "status-fail"
        icon = "⏳"
        with LOCK: STATS["FAILED"] += 1
        print(f"{Fore.RED}x{Style.RESET_ALL}", end="", flush=True)

    elif "status: NOERROR" in output:
        # Lógica de NOANSWER (Corrigido)
        if answer_count == 0:
            status_txt = "NOANSWER"
            css_class = "status-warning"
            icon = "⚠️"
            with LOCK: STATS["WARNING"] += 1
            print(f"{Fore.YELLOW}!{Style.RESET_ALL}", end="", flush=True)
        else:
            status_txt = "OK"
            css_class = "status-ok"
            icon = "✅"
            with LOCK: STATS["SUCCESS"] += 1
            print(f"{Fore.GREEN}.{Style.RESET_ALL}", end="", flush=True)
    else:
        # Caso genérico
        status_txt = "UNKNOWN"
        css_class = "status-warning"
        icon = "❓"
        with LOCK: STATS["WARNING"] += 1
        print(f"{Fore.YELLOW}?{Style.RESET_ALL}", end="", flush=True)
        
    with LOCK: STATS["TOTAL"] += 1

    # 4. Montagem do HTML Fragmentado
    unique_id = f"test_{test_id}"
    html_cell = f'<td><a href="#" onclick="showLog(\'{unique_id}\'); return false;" class="cell-link {css_class}">{icon} {status_txt} <span class="time-badge">{duration}ms</span></a></td>'
    
    safe_output = output.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    
    if css_class == "status-fail": log_color = "color:#f44747"
    elif css_class == "status-warning": log_color = "color:#ffcc02"
    
    html_log = f'<details id="{unique_id}"><summary class="log-header"><span class="log-id">#{test_id}</span> <span style="{log_color}">{status_txt}</span> <strong>{srv}</strong> &rarr; {target} ({rec_type}) <span class="badge">{duration}ms</span></summary><pre>{full_cmd}\n\n{safe_output}</pre></details>'
    
    with LOCK:
        HTML_DETAILS_BUFFER.append(html_log)
        file_log(f"TEST #{test_id} | {mode} | {srv} | {target} | {status_txt} | {duration}ms")

    return (group_name, target, rec_type, mode, html_cell)

# ==============================================
# CARREGAMENTO E EXECUÇÃO
# ==============================================

def load_csvs():
    """Lê os CSVs e retorna estruturas de dados."""
    dns_groups = {}
    domains_tests = []
    
    if not os.path.exists(CONFIG["FILES"]["GROUPS"]):
        print(f"{Fore.RED}ERRO: Arquivo {CONFIG['FILES']['GROUPS']} não encontrado.{Fore.RESET}")
        sys.exit(1)
        
    # Load Groups
    with open(CONFIG["FILES"]["GROUPS"], 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter=';')
        for row in reader:
            if not row or row[0].startswith('#'): continue
            if len(row) < 5: 
                print(f"{Fore.YELLOW}Aviso: Linha inválida em grupos: {row}{Fore.RESET}")
                continue
            name, desc, type_, timeout, servers = row
            dns_groups[name] = {
                "desc": desc, "type": type_, "timeout": timeout, "servers": servers.split(',')
            }
            
    # Load Domains
    if not os.path.exists(CONFIG["FILES"]["DOMAINS"]):
        print(f"{Fore.RED}ERRO: Arquivo {CONFIG['FILES']['DOMAINS']} não encontrado.{Fore.RESET}")
        sys.exit(1)
        
    with open(CONFIG["FILES"]["DOMAINS"], 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter=';')
        for row in reader:
            if not row or row[0].startswith('#'): continue
            if len(row) < 5: continue
            dom, grps, tests, recs, extras = row
            domains_tests.append({
                "domain": dom,
                "groups": grps.split(','),
                "test_types": tests,
                "records": recs.split(','),
                "extras": extras.split(',') if extras else []
            })
            
    return dns_groups, domains_tests

def interactive_mode():
    """Menu interativo."""
    print(f"{Fore.BLUE}=== MODO INTERATIVO (Pressione ENTER para default) ==={Fore.RESET}")
    
    def ask(prompt, key, cast=str):
        val = input(f"  🔹 {prompt} [{CONFIG[key]}]: ")
        if val:
            CONFIG[key] = cast(val)
            print(f"     {Fore.YELLOW}>> Definido: {CONFIG[key]}{Fore.RESET}")

    ask("Timeout Global (s)", "TIMEOUT", float)
    ask("Threads Simultâneas", "THREADS", int)
    ask("Versão IP (ipv4/ipv6)", "IP_VERSION", str)
    ask("Validar Conexão Porta 53? (True/False)", "VALIDATE_CONNECTIVITY", bool)
    ask("Ativar Ping? (True/False)", "ENABLE_PING", bool)
    
    if CONFIG["ENABLE_PING"]:
        ask("Ping Count", "PING_COUNT", int)
        ask("Ping Timeout (s)", "PING_TIMEOUT", float)
    print("\n")

def generate_html_report(start_time, end_time, total_duration, groups_data):
    """Gera o arquivo HTML final."""
    
    html_content = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>DNS Report - Python Ed.</title>
    <style>
        body {{ font-family: 'Segoe UI', sans-serif; background: #1e1e1e; color: #d4d4d4; margin: 0; padding: 20px; }}
        .container {{ max-width: 1400px; margin: 0 auto; }}
        h1 {{ color: #ce9178; text-align: center; margin-bottom: 20px; }}
        .modal {{ display: none; position: fixed; z-index: 999; left: 0; top: 0; width: 100%; height: 100%; overflow: auto; background-color: rgba(0,0,0,0.8); backdrop-filter: blur(2px); }}
        .modal-content {{ background-color: #252526; margin: 5% auto; padding: 0; border: 1px solid #444; width: 80%; max-width: 1000px; border-radius: 8px; box-shadow: 0 0 30px rgba(0,0,0,0.7); }}
        .modal-header {{ padding: 15px 20px; background: #333; border-bottom: 1px solid #444; display: flex; justify-content: space-between; align-items: center; }}
        .modal-body {{ padding: 20px; max-height: 70vh; overflow-y: auto; }}
        .close-btn {{ color: #aaa; font-size: 28px; font-weight: bold; cursor: pointer; }}
        .close-btn:hover {{ color: #f44747; }}
        #modalTitle {{ font-weight: bold; font-family: monospace; color: #9cdcfe; font-size: 1.1em; }}
        #modalText {{ font-family: 'Consolas', monospace; white-space: pre-wrap; color: #d4d4d4; background: #1e1e1e; padding: 15px; border: 1px solid #333; }}
        .dashboard {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 10px; }}
        .card {{ background: #252526; padding: 15px; border-radius: 6px; text-align: center; border-bottom: 3px solid #444; }}
        .card-num {{ font-size: 2em; font-weight: bold; display: block; }}
        .st-total {{ border-color: #007acc; }} .st-total .card-num {{ color: #007acc; }}
        .st-ok {{ border-color: #4ec9b0; }} .st-ok .card-num {{ color: #4ec9b0; }}
        .st-warn {{ border-color: #ffcc02; }} .st-warn .card-num {{ color: #ffcc02; }}
        .st-fail {{ border-color: #f44747; }} .st-fail .card-num {{ color: #f44747; }}
        .timing-strip {{ background: #252526; padding: 10px; margin-bottom: 30px; display: flex; justify-content: space-around; font-family: monospace; border-left: 5px solid #666; }}
        .domain-block {{ background: #252526; margin-bottom: 20px; border-radius: 6px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.2); }}
        .domain-header {{ background: #333; padding: 10px 15px; font-weight: bold; border-left: 5px solid #007acc; display: flex; justify-content: space-between; }}
        table {{ width: 100%; border-collapse: collapse; }}
        th, td {{ padding: 8px 12px; text-align: left; border-bottom: 1px solid #3e3e42; font-size: 0.9em; }}
        th {{ background: #2d2d30; color: #dcdcaa; }}
        .cell-link {{ text-decoration: none; display: block; width: 100%; height: 100%; cursor: pointer; }}
        .cell-link:hover {{ background: rgba(255,255,255,0.05); }}
        .status-ok {{ color: #4ec9b0; }}
        .status-warning {{ color: #ffcc02; }}
        .status-fail {{ color: #f44747; font-weight: bold; background: rgba(244, 71, 71, 0.1); }}
        .time-badge {{ font-size: 0.75em; color: #808080; margin-left: 5px; }}
        details {{ background: #1e1e1e; margin-bottom: 10px; border: 1px solid #333; }}
        summary {{ cursor: pointer; padding: 10px; background: #252526; font-family: monospace; }}
        pre {{ background: #000; color: #ccc; padding: 15px; margin: 0; overflow-x: auto; border-top: 1px solid #333; }}
        .badge {{ padding: 2px 5px; border-radius: 3px; font-size: 0.8em; border: 1px solid #444; }}
        .footer {{ margin-top: 40px; padding: 20px; border-top: 1px solid #333; text-align: center; color: #666; font-size: 0.9em; }}
    </style>
    <script>
        function showLog(id) {{
            var el = document.getElementById(id);
            if(!el) return;
            var text = el.querySelector('pre').innerHTML;
            var title = el.querySelector('summary').innerText;
            document.getElementById('modalTitle').innerText = title;
            document.getElementById('modalText').innerHTML = text;
            document.getElementById('logModal').style.display = "block";
        }}
        function closeModal() {{ document.getElementById('logModal').style.display = "none"; }}
        window.onclick = function(e) {{ if(e.target == document.getElementById('logModal')) closeModal(); }}
        document.addEventListener('keydown', function(e){{ if(e.key === "Escape") closeModal(); }});
    </script>
</head>
<body>
    <div id="logModal" class="modal">
        <div class="modal-content">
            <div class="modal-header"><div id="modalTitle">Log</div><span class="close-btn" onclick="closeModal()">&times;</span></div>
            <div class="modal-body"><pre id="modalText"></pre></div>
        </div>
    </div>
    <div class="container">
        <h1>📊 Relatório DNS - Python Power Edition</h1>
        <div class="dashboard">
            <div class="card st-total"><span class="card-num">{STATS['TOTAL']}</span><span class="card-label">Testes</span></div>
            <div class="card st-ok"><span class="card-num">{STATS['SUCCESS']}</span><span class="card-label">Sucesso</span></div>
            <div class="card st-warn"><span class="card-num">{STATS['WARNING']}</span><span class="card-label">Alertas</span></div>
            <div class="card st-fail"><span class="card-num">{STATS['FAILED']}</span><span class="card-label">Falhas</span></div>
        </div>
        <div class="timing-strip">
            <div>Início: {start_time}</div>
            <div>Fim: {end_time}</div>
            <div>Duração: {total_duration:.2f}s</div>
            <div>Threads: {CONFIG['THREADS']}</div>
        </div>
        {"".join(HTML_MATRIX_BUFFER)}
        <div class="ping-section">
            <h2>📡 Latência (ICMP)</h2>
            <table><thead><tr><th>Servidor</th><th>Status</th><th>Latência</th><th>Raw Output</th></tr></thead>
            <tbody>{"".join(PING_RESULTS_BUFFER)}</tbody></table>
        </div>
        <div class="tech-section">
            <h2>🛠️ Logs Técnicos</h2>
            {"".join(HTML_DETAILS_BUFFER)}
        </div>
        <div class="footer">Gerado por <strong>DNS Diagnostic Python Tool</strong></div>
    </div>
</body>
</html>
"""
    filename = f"logs/dnsdiag_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
    with open(filename, "w", encoding="utf-8") as f:
        f.write(html_content)
    return filename

# ==============================================
# MAIN
# ==============================================

if __name__ == "__main__":
    check_dependencies()
    
    parser = argparse.ArgumentParser(description="DNS Diagnostic Tool - Python Edition")
    parser.add_argument("-n", "--domains", help="Arquivo de Domínios")
    parser.add_argument("-g", "--groups", help="Arquivo de Grupos")
    parser.add_argument("-y", "--yes", action="store_true", help="Modo não interativo")
    parser.add_argument("-t", "--threads", type=int, help="Número de threads")
    args = parser.parse_args()

    if args.domains: CONFIG["FILES"]["DOMAINS"] = args.domains
    if args.groups: CONFIG["FILES"]["GROUPS"] = args.groups
    if args.threads: CONFIG["THREADS"] = args.threads
    
    os.makedirs("logs", exist_ok=True)
    LOG_FILE_TEXT = f"logs/dnsdiag_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

    print(f"{Fore.BLUE}=============================================={Fore.RESET}")
    print(f"{Fore.BLUE}    DNS DIAGNOSTIC TOOL v10.1 (Python)    {Fore.RESET}")
    print(f"{Fore.BLUE}=============================================={Fore.RESET}")
    
    if not args.yes:
        interactive_mode()
        
    dns_groups, domains_tests = load_csvs()
    
    # Geração de Tarefas
    tasks = []
    test_counter = 0
    
    log_print(f"Gerando lista de tarefas para {len(domains_tests)} domínios...", Fore.MAGENTA)
    
    for dt in domains_tests:
        dom = dt['domain']
        targets = [dom] + [f"{sub}.{dom}" for sub in dt['extras'] if sub]
        modes = ["iterative", "recursive"] if "both" in dt['test_types'] else [dt['test_types']]
        # Ajuste para caso esteja setado apenas como recursive ou iterative no CSV sem ser 'both'
        if "both" in dt['test_types']: modes = ["iterative", "recursive"]
        elif "recursive" in dt['test_types']: modes = ["recursive"]
        else: modes = ["iterative"]

        for grp_name in dt['groups']:
            if grp_name not in dns_groups: continue
            grp_servers = dns_groups[grp_name]['servers']
            
            for srv in grp_servers:
                for mode in modes:
                    for target in targets:
                        for rec in dt['records']:
                            test_counter += 1
                            tasks.append((dom, grp_name, srv, target, rec, mode, test_counter))

    log_print(f"Total de testes a realizar: {len(tasks)}", Fore.CYAN)
    log_print(f"Iniciando ThreadPool com {CONFIG['THREADS']} workers.", Fore.CYAN)
    
    start_time = datetime.datetime.now()
    t_start = time.time()
    results_map = {}
    
    # Executor DNS
    with ThreadPoolExecutor(max_workers=CONFIG["THREADS"]) as executor:
        future_to_task = {executor.submit(process_dns_task, task): task for task in tasks}
        
        for future in as_completed(future_to_task):
            task = future_to_task[future]
            try:
                dom, grp, srv, target, rec, mode, _ = task
                res = future.result()
                key = (dom, grp, target, rec, mode)
                if key not in results_map: results_map[key] = {}
                results_map[key][srv] = res[4] # html_cell
            except Exception as exc:
                print(f"Task generated an exception: {exc}")

    # Executor PING
    if CONFIG["ENABLE_PING"]:
        log_print("\nIniciando Ping Tests...", Fore.MAGENTA)
        unique_ips = set()
        for g in dns_groups.values():
            for s in g['servers']: unique_ips.add(s)
            
        with ThreadPoolExecutor(max_workers=CONFIG["THREADS"]) as executor:
            future_ping = {executor.submit(run_ping, ip): ip for ip in unique_ips}
            for future in as_completed(future_ping):
                ip = future_ping[future]
                ret, out, dur = future.result()
                status = "✅ UP" if ret == 0 else "❌ DOWN"
                cls = "status-ok" if ret == 0 else "status-fail"
                PING_RESULTS_BUFFER.append(f"<tr><td><strong>{ip}</strong></td><td class='{cls}'>{status}</td><td>{dur}ms</td><td><details><summary>Output</summary><pre>{out}</pre></details></td></tr>")
                print(f"   Ping {ip}: {status}")

    # Montagem do Relatório Ordenado
    log_print("\nMontando relatório HTML...", Fore.CYAN)
    for dt in domains_tests:
        dom = dt['domain']
        targets = [dom] + [f"{sub}.{dom}" for sub in dt['extras'] if sub]
        modes = ["iterative", "recursive"] if "both" in dt['test_types'] else ([dt['test_types']] if dt['test_types'] in ["recursive", "iterative"] else ["iterative"]) # Fallback seguro
        if "both" in dt['test_types']: modes = ["iterative", "recursive"]
        elif "recursive" in dt['test_types']: modes = ["recursive"]
        else: modes = ["iterative"]

        HTML_MATRIX_BUFFER.append(f'<div class="domain-block"><div class="domain-header"><span>🌐 {dom}</span><span class="badge">{dt["test_types"]}</span></div>')
        
        for grp_name in dt['groups']:
            if grp_name not in dns_groups: continue
            srvs = dns_groups[grp_name]['servers']
            
            HTML_MATRIX_BUFFER.append(f'<div style="padding:10px; background:#2d2d30; color:#9cdcfe;">Grupo: {grp_name}</div>')
            HTML_MATRIX_BUFFER.append('<table><thead><tr><th style="width:30%">Target (Record)</th>')
            for s in srvs: HTML_MATRIX_BUFFER.append(f'<th>{s}</th>')
            HTML_MATRIX_BUFFER.append('</tr></thead><tbody>')
            
            for mode in modes:
                for target in targets:
                    for rec in dt['records']:
                        key = (dom, grp_name, target, rec, mode)
                        HTML_MATRIX_BUFFER.append(f'<tr><td><span class="badge">{mode}</span> <strong>{target}</strong> <span style="color:#666">({rec})</span></td>')
                        
                        row_results = results_map.get(key, {})
                        for srv in srvs:
                            cell = row_results.get(srv, "<td>N/A</td>")
                            HTML_MATRIX_BUFFER.append(cell)
                        HTML_MATRIX_BUFFER.append('</tr>')
            HTML_MATRIX_BUFFER.append('</tbody></table>')
        HTML_MATRIX_BUFFER.append('</div>')

    t_end = time.time()
    final_file = generate_html_report(start_time.strftime("%d/%m/%Y %H:%M:%S"), datetime.datetime.now().strftime("%d/%m/%Y %H:%M:%S"), t_end - t_start, dns_groups)
    
    print(f"\n{Fore.GREEN}=== CONCLUSÃO ==={Fore.RESET}")
    print(f"Relatório gerado em: {Fore.CYAN}{final_file}{Fore.RESET}")
    print(f"Total Testes: {STATS['TOTAL']} | Sucessos: {STATS['SUCCESS']} | Alertas: {STATS['WARNING']} | Falhas: {STATS['FAILED']}")
