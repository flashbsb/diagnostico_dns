#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
DIAGNÓSTICO DNS - PY EDITION (Versão 11.0 - Bash Replica)
Esta versão replica exatamente a lógica de decisão do script Bash original,
corrige o problema de Deadlock com logs e implementa timeouts forçados.

Correções Críticas:
1. Deadlock Fix: Uso de RLock para permitir log concomitante.
2. Lógica DNS: Paridade total com o script Bash (NOANSWER, NXDOMAIN, etc).
3. Anti-Freeze: O Python mata subprocessos (dig/ping) que excedem o tempo limite.
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
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

# ==============================================
# CORES & AMBIENTE
# ==============================================
try:
    from colorama import init, Fore, Style
    init()
    HAS_COLORAMA = True
except ImportError:
    HAS_COLORAMA = False
    # Fallback manual para garantir que funcione em Linux puro sem libs extras
    class Fore:
        BLACK = '\033[30m'; RED = '\033[91m'; GREEN = '\033[92m'; YELLOW = '\033[93m'
        BLUE = '\033[94m'; CYAN = '\033[96m'; MAGENTA = '\033[95m'; WHITE = '\033[97m'; RESET = '\033[0m'
    class Style:
        BRIGHT = '\033[1m'; RESET_ALL = '\033[0m'

# ==============================================
# CONFIGURAÇÕES (Idênticas ao Bash)
# ==============================================
CONFIG = {
    "TIMEOUT": 5.0,               # Timeout global
    "SLEEP": 0.05,                # Intervalo visual
    "VALIDATE_CONNECTIVITY": True,# Checa porta 53 antes
    "GENERATE_HTML": True,
    "GENERATE_LOG_TEXT": False,   # Ativado via -l
    "VERBOSE": False,             # Ativado via -v
    "IP_VERSION": "ipv4",
    "CHECK_BIND": False,          # Tenta descobrir versão do BIND
    "ENABLE_PING": True,
    "PING_COUNT": 4,              # Padrão Bash era 10, reduzido para agilidade (ajustável)
    "PING_TIMEOUT": 2,
    "THREADS": 10,
    "FILES": {"DOMAINS": "domains_tests.csv", "GROUPS": "dns_groups.csv"}
}

# Opções exatas do DIG usadas no Bash
DEFAULT_DIG_OPTS = ["+norecurse", "+time=1", "+tries=1", "+nocookie", "+cd", "+bufsize=512"]
RECURSIVE_DIG_OPTS = ["+time=1", "+tries=1", "+nocookie", "+cd", "+bufsize=512"]

STATS = {"TOTAL": 0, "SUCCESS": 0, "FAILED": 0, "WARNING": 0}

# [CORREÇÃO CRÍTICA]: RLock (Re-entrant Lock) impede o travamento quando
# a thread tenta escrever no log enquanto já segura o bloqueio de estatísticas.
LOCK = threading.RLock() 

HTML_CONN_ERR_LOGGED = set()
CONNECTIVITY_CACHE = {}
HTML_MATRIX_BUFFER = [] # Armazena fragmentos temporários
HTML_DETAILS_BUFFER = []
PING_RESULTS_BUFFER = []

# ==============================================
# UTILITÁRIOS
# ==============================================

def log_print(msg, color=Fore.CYAN):
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    with LOCK:
        print(f"{Style.BRIGHT}[{ts}]{Style.RESET_ALL} {color}{msg}{Style.RESET_ALL}")

def file_log(msg):
    """Escreve no log de texto se a flag -l estiver ativa."""
    if not CONFIG["GENERATE_LOG_TEXT"]: return
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with LOCK: # Seguro agora com RLock
            with open(LOG_FILE_TEXT, "a", encoding="utf-8") as f:
                f.write(f"[{ts}] {msg}\n")
    except Exception as e:
        print(f"Erro IO Log: {e}")

def check_dependencies():
    try:
        subprocess.run(["dig", "-v"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        print(f"{Fore.RED}ERRO CRÍTICO: 'dig' não encontrado.{Fore.RESET}")
        print("Instale 'bind-utils' (Linux) ou BIND Tools (Windows).")
        sys.exit(1)

# ==============================================
# CORE DE REDE (COM PROTEÇÃO ANTI-FREEZE)
# ==============================================

def check_port(server, port=53, timeout=2.0):
    """Valida conectividade TCP (substituto do netcat/bash tcp)."""
    if server in CONNECTIVITY_CACHE: return CONNECTIVITY_CACHE[server]
    try:
        with socket.create_connection((server, port), timeout=timeout): res = True
    except: res = False
    with LOCK: CONNECTIVITY_CACHE[server] = res
    return res

def get_bind_version(server):
    """Tenta extrair versão do BIND (chaos txt)."""
    cmd = ["dig", "+short", "+time=1", "+tries=1", f"@{server}", "chaos", "txt", "version.bind"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, errors='replace', timeout=3)
        ver = proc.stdout.strip().replace('"', '')
        return f" (Ver: {ver})" if ver else ""
    except: return ""

def run_ping(ip):
    """Ping cross-platform."""
    sys_os = platform.system().lower()
    cmd = ["ping"]
    if "windows" in sys_os:
        cmd.extend(["-n", str(CONFIG["PING_COUNT"]), "-w", str(CONFIG["PING_TIMEOUT"] * 1000), ip])
    else:
        cmd.extend(["-c", str(CONFIG["PING_COUNT"]), "-W", str(CONFIG["PING_TIMEOUT"]), ip])
    
    start = time.time()
    try:
        # Timeout de segurança = (Timeout * Count) + 2 segundos de margem
        safe_timeout = (CONFIG["PING_TIMEOUT"] * CONFIG["PING_COUNT"]) + 2
        proc = subprocess.run(cmd, capture_output=True, text=True, errors='replace', timeout=safe_timeout)
        return proc.returncode, proc.stdout, int((time.time() - start) * 1000)
    except subprocess.TimeoutExpired:
        return 1, "Ping Timeout (Python Kill)", 0
    except Exception as e:
        return 1, str(e), 0

def run_dig(server, target, record, mode="iterative"):
    """Executa o DIG com timeout forçado pelo Python."""
    cmd = ["dig"]
    cmd.extend(DEFAULT_DIG_OPTS if mode == "iterative" else RECURSIVE_DIG_OPTS)
    cmd.append("-4" if CONFIG["IP_VERSION"] == "ipv4" else "-6")
    cmd.extend([f"@{server}", target, record])
    
    start = time.time()
    try:
        # Timeout forçado: Configuração + 2s de margem. Se o dig travar, o Python mata.
        proc = subprocess.run(cmd, capture_output=True, text=True, errors='replace', timeout=CONFIG["TIMEOUT"] + 2)
        return proc.returncode, proc.stdout, int((time.time() - start) * 1000), " ".join(cmd)
    except subprocess.TimeoutExpired:
        # Simula um output de timeout para a lógica de análise processar
        return 999, ";; connection timed out (PYTHON WATCHDOG KILL)", int((time.time() - start) * 1000), " ".join(cmd)
    except Exception as e:
        return 999, str(e), 0, " ".join(cmd)

# ==============================================
# WORKER: ANÁLISE DE RESULTADOS
# ==============================================

def process_dns_task(task_data):
    """
    Processa um único teste DNS.
    Replica a lógica do Bash:
    Sucesso = NOERROR com ANSWER > 0
    Alerta  = NOERROR com ANSWER == 0 (NOANSWER), NXDOMAIN, SERVFAIL
    Falha   = TIMEOUT, REFUSED, Erro de Código
    """
    domain, group_name, srv, target, rec_type, mode, test_id = task_data
    
    # 1. Validação Conectividade (Se ativado)
    if CONFIG["VALIDATE_CONNECTIVITY"]:
        if not check_port(srv, 53, CONFIG["TIMEOUT"]):
            with LOCK:
                STATS["FAILED"] += 1; STATS["TOTAL"] += 1
                conn_id = f"conn_err_{srv.replace('.', '_')}"
                if srv not in HTML_CONN_ERR_LOGGED:
                    HTML_CONN_ERR_LOGGED.add(srv)
                    # Adiciona log de erro de conexão apenas uma vez
                    HTML_DETAILS_BUFFER.append(f'<details id="{conn_id}" class="conn-error-block"><summary class="log-header" style="color:#f44747"><strong>FALHA CONEXÃO</strong> - {srv}</summary><pre>O servidor {srv} não respondeu na porta 53 (TCP).\nTeste abortado.</pre></details>')
                print(f"{Fore.RED}x{Style.RESET_ALL}", end="", flush=True)
                file_log(f"CONN FAIL: {srv} unreachable on port 53")
                # Retorna célula de erro
                return (group_name, target, rec_type, mode, f'<td><a href="#" onclick="showLog(\'{conn_id}\'); return false;" class="cell-link status-fail">❌ DOWN</a></td>')

    # 2. Execução do Comando
    ret_code, output, duration, full_cmd = run_dig(srv, target, rec_type, mode)
    bind_ver = get_bind_version(srv) if CONFIG["CHECK_BIND"] else ""

    # 3. Análise Lógica (Idêntica ao Bash)
    # Regex para pegar número de answers: equivale ao grep -oE ", ANSWER: [0-9]+"
    answer_match = re.search(r"ANSWER:\s+(\d+)", output)
    answer_count = int(answer_match.group(1)) if answer_match else 0
    
    status_txt = "OK"; css="status-ok"; icon="✅"; log_col=""
    
    # Ordem de verificação replicada do Bash
    if ret_code != 0:
        status_txt = f"ERR:{ret_code}"; css="status-fail"; icon="❌"
        with LOCK: STATS["FAILED"] += 1; print(f"{Fore.RED}x{Style.RESET_ALL}", end="", flush=True)
    
    elif "status: SERVFAIL" in output:
        status_txt = "SERVFAIL"; css="status-warning"; icon="⚠️"
        with LOCK: STATS["WARNING"] += 1; print(f"{Fore.YELLOW}!{Style.RESET_ALL}", end="", flush=True)
    
    elif "status: NXDOMAIN" in output:
        status_txt = "NXDOMAIN"; css="status-warning"; icon="🔸"
        with LOCK: STATS["WARNING"] += 1; print(f"{Fore.YELLOW}!{Style.RESET_ALL}", end="", flush=True)
    
    elif "status: REFUSED" in output:
        status_txt = "REFUSED"; css="status-fail"; icon="⛔"
        with LOCK: STATS["FAILED"] += 1; print(f"{Fore.RED}x{Style.RESET_ALL}", end="", flush=True)
    
    elif "connection timed out" in output:
        status_txt = "TIMEOUT"; css="status-fail"; icon="⏳"
        with LOCK: STATS["FAILED"] += 1; print(f"{Fore.RED}x{Style.RESET_ALL}", end="", flush=True)
    
    elif "status: NOERROR" in output:
        # AQUI É O PULO DO GATO: NOERROR sem resposta é WARNING (NOANSWER)
        if answer_count == 0:
            status_txt = "NOANSWER"; css="status-warning"; icon="⚠️"
            with LOCK: STATS["WARNING"] += 1; print(f"{Fore.YELLOW}!{Style.RESET_ALL}", end="", flush=True)
        else:
            # NOERROR com resposta é SUCESSO
            with LOCK: STATS["SUCCESS"] += 1; print(f"{Fore.GREEN}.{Style.RESET_ALL}", end="", flush=True)
    
    else:
        # Fallback
        status_txt = "UNKNOWN"; css="status-warning"; icon="❓"
        with LOCK: STATS["WARNING"] += 1; print(f"{Fore.YELLOW}?{Style.RESET_ALL}", end="", flush=True)

    with LOCK: 
        STATS["TOTAL"] += 1
        
        # Prepara logging HTML
        if css == "status-fail": log_col = "color:#f44747"
        elif css == "status-warning": log_col = "color:#ffcc02"
        
        uid = f"test_{test_id}"
        # Célula da tabela
        html_cell = f'<td><a href="#" onclick="showLog(\'{uid}\'); return false;" class="cell-link {css}">{icon} {status_txt} <span class="time-badge">{duration}ms</span></a></td>'
        
        # Log detalhado (HTML)
        safe_output = output.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
        html_log = f'<details id="{uid}"><summary class="log-header"><span class="log-id">#{test_id}</span> <span style="{log_col}">{status_txt}</span> <strong>{srv}</strong> &rarr; {target} ({rec_type}) <span class="badge">{duration}ms</span>{bind_ver}</summary><pre>{full_cmd}\n\n{safe_output}</pre></details>'
        HTML_DETAILS_BUFFER.append(html_log)
        
        # Log texto (se ativado -l)
        file_log(f"TEST {test_id} | {srv} | {target} | {rec_type} | {status_txt} | {duration}ms")

    return (group_name, target, rec_type, mode, html_cell)

# ==============================================
# CARREGAMENTO E EXECUÇÃO
# ==============================================

def load_csvs():
    dg = {}; dt = []
    # Valida arquivos
    if not os.path.exists(CONFIG["FILES"]["GROUPS"]): sys.exit(f"{Fore.RED}ERRO: Arquivo {CONFIG['FILES']['GROUPS']} não encontrado.{Fore.RESET}")
    with open(CONFIG["FILES"]["GROUPS"], 'r', encoding='utf-8') as f:
        for r in csv.reader(f, delimiter=';'):
            if r and not r[0].startswith('#') and len(r)>=5:
                dg[r[0]] = {"desc": r[1], "type": r[2], "timeout": r[3], "servers": r[4].split(',')}
    
    if not os.path.exists(CONFIG["FILES"]["DOMAINS"]): sys.exit(f"{Fore.RED}ERRO: Arquivo {CONFIG['FILES']['DOMAINS']} não encontrado.{Fore.RESET}")
    with open(CONFIG["FILES"]["DOMAINS"], 'r', encoding='utf-8') as f:
        for r in csv.reader(f, delimiter=';'):
            if r and not r[0].startswith('#') and len(r)>=5:
                dt.append({"domain": r[0], "groups": r[1].split(','), "test_types": r[2], "records": r[3].split(','), "extras": r[4].split(',') if r[4] else []})
    return dg, dt

def interactive_mode():
    print(f"{Fore.BLUE}=== CONFIGURAÇÃO INTERATIVA ==={Fore.RESET}")
    def ask(msg, key, cast=str):
        v = input(f"  🔹 {msg} [{CONFIG[key]}]: ")
        if v: CONFIG[key] = cast(v); print(f"     >> {v}")
    
    ask("Gerar Log TXT (-l)? (True/False)", "GENERATE_LOG_TEXT", bool)
    ask("Check BIND Version? (True/False)", "CHECK_BIND", bool)
    ask("Threads", "THREADS", int)
    print("")

def generate_html(st, et, dur, grps):
    """Gera o HTML final, idêntico ao dashboard original."""
    css = """body{font-family:'Segoe UI',sans-serif;background:#1e1e1e;color:#d4d4d4;padding:20px} .container{max-width:1400px;margin:0 auto} 
    .card{background:#252526;padding:15px;border-radius:6px;text-align:center;border-bottom:3px solid #444} 
    .card-num{font-size:2em;font-weight:bold;display:block} .dashboard{display:grid;grid-template-columns:repeat(4,1fr);gap:15px}
    .st-ok .card-num{color:#4ec9b0} .st-fail .card-num{color:#f44747} .st-warn .card-num{color:#ffcc02}
    table{width:100%;border-collapse:collapse} th,td{padding:8px;border-bottom:1px solid #3e3e42} th{background:#2d2d30}
    .status-ok{color:#4ec9b0} .status-fail{color:#f44747;background:rgba(244,71,71,0.1);font-weight:bold} .status-warning{color:#ffcc02}
    .modal{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.8);backdrop-filter:blur(2px)} 
    .modal-content{background:#252526;margin:5% auto;width:80%;max-width:1000px;border:1px solid #444;padding:0;box-shadow:0 0 30px rgba(0,0,0,0.7)}
    .modal-header{padding:15px;background:#333;display:flex;justify-content:space-between} .close-btn{cursor:pointer;font-size:24px}
    .modal-body{padding:20px;max-height:70vh;overflow-y:auto}
    pre{background:#000;color:#ccc;padding:15px;overflow-x:auto} details{background:#1e1e1e;border:1px solid #333;margin-bottom:5px} summary{padding:10px;cursor:pointer;background:#252526}
    .log-header{display:flex;align-items:center;gap:10px} .badge{border:1px solid #444;padding:2px 5px;font-size:0.8em;border-radius:3px}"""
    
    js = """function showLog(id){document.getElementById('modalText').innerHTML=document.getElementById(id).querySelector('pre').innerHTML;document.getElementById('logModal').style.display='block'}
    function closeModal(){document.getElementById('logModal').style.display='none'}
    window.onclick=function(e){if(e.target==document.getElementById('logModal'))closeModal()}
    document.addEventListener('keydown',function(e){if(e.key==='Escape')closeModal()})"""
    
    html = f"""<!DOCTYPE html><html><head><meta charset='UTF-8'><title>DNS Report</title><style>{css}</style><script>{js}</script></head>
    <body><div id="logModal" class="modal"><div class="modal-content"><div class="modal-header"><strong>Log Detail</strong><span class="close-btn" onclick="closeModal()">&times;</span></div><div class="modal-body"><pre id="modalText"></pre></div></div>
    <div class="container"><h1>📊 Relatório Diagnóstico DNS</h1>
    <div class="dashboard">
        <div class="card st-total"><span class="card-num">{STATS['TOTAL']}</span>Total</div>
        <div class="card st-ok"><span class="card-num">{STATS['SUCCESS']}</span>Sucesso</div>
        <div class="card st-warn"><span class="card-num">{STATS['WARNING']}</span>Alertas</div>
        <div class="card st-fail"><span class="card-num">{STATS['FAILED']}</span>Falhas</div>
    </div>
    <div style="background:#252526;padding:10px;margin:20px 0;border-left:4px solid #666;font-family:monospace">
        Início: {st} &nbsp;|&nbsp; Fim: {et} &nbsp;|&nbsp; Duração: {dur:.2f}s &nbsp;|&nbsp; Threads: {CONFIG['THREADS']}
    </div>
    {"".join(HTML_MATRIX_BUFFER)}
    <h2 style="margin-top:40px">📡 Latência e Disponibilidade (Ping)</h2>
    <table><thead><tr><th>Host</th><th>Status</th><th>Latência</th></tr></thead><tbody>{"".join(PING_RESULTS_BUFFER)}</tbody></table>
    <h2 style="margin-top:40px">🛠️ Logs Técnicos</h2>{"".join(HTML_DETAILS_BUFFER)}
    <div style="text-align:center;margin-top:50px;color:#666;border-top:1px solid #333;padding:20px">Gerado por DNS Diagnostic Tool (Python Edition)</div>
    </div></body></html>"""
    
    fname = f"logs/dnsdiag_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
    with open(fname, "w", encoding="utf-8") as f: f.write(html)
    return fname

if __name__ == "__main__":
    check_dependencies()
    parser = argparse.ArgumentParser()
    parser.add_argument("-n", "--domains", help="Arquivo Domínios")
    parser.add_argument("-g", "--groups", help="Arquivo Grupos")
    parser.add_argument("-y", "--yes", action="store_true", help="Não Interativo")
    parser.add_argument("-t", "--threads", type=int, help="Threads")
    parser.add_argument("-l", "--log", action="store_true", help="Gerar log .txt")
    parser.add_argument("-v", "--verbose", action="store_true", help="Debug na tela")
    args = parser.parse_args()

    if args.domains: CONFIG["FILES"]["DOMAINS"] = args.domains
    if args.groups: CONFIG["FILES"]["GROUPS"] = args.groups
    if args.threads: CONFIG["THREADS"] = args.threads
    if args.log: CONFIG["GENERATE_LOG_TEXT"] = True
    if args.verbose: CONFIG["VERBOSE"] = True

    os.makedirs("logs", exist_ok=True)
    LOG_FILE_TEXT = f"logs/dnsdiag_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

    print(f"{Fore.BLUE}=============================================={Fore.RESET}")
    print(f"{Fore.BLUE}   DNS DIAGNOSTIC TOOL v11.0 (Bash Replica)   {Fore.RESET}")
    print(f"{Fore.BLUE}=============================================={Fore.RESET}")
    
    if not args.yes: interactive_mode()
    
    groups, tests = load_csvs()
    tasks = []
    tid = 0
    
    log_print(f"Carregando tarefas...", Fore.MAGENTA)
    for dt in tests:
        # Define modos: Both, Recursive ou Iterative
        modes = ["iterative", "recursive"] if "both" in dt['test_types'] else [dt['test_types']]
        targets = [dt['domain']] + [f"{x}.{dt['domain']}" for x in dt['extras']]
        
        for g in dt['groups']:
            if g in groups:
                for s in groups[g]['servers']:
                    for m in modes:
                        for t in targets:
                            for r in dt['records']:
                                tid+=1
                                tasks.append((dt['domain'], g, s, t, r, m, tid))

    log_print(f"Iniciando {len(tasks)} testes DNS com {CONFIG['THREADS']} threads...", Fore.CYAN)
    
    st_time = datetime.datetime.now(); t0 = time.time()
    
    # Dicionário para reordenar resultados (necessário pois threads terminam aleatoriamente)
    res_map = {} 
    
    # === EXECUÇÃO DNS MULTITHREAD ===
    with ThreadPoolExecutor(max_workers=CONFIG["THREADS"]) as exc:
        fut = {exc.submit(process_dns_task, t): t for t in tasks}
        try:
            for f in as_completed(fut):
                try:
                    d, g, s, t, r, m, _ = fut[f]
                    val = f.result()
                    # Chave única para recuperar o resultado na ordem correta depois
                    k = (d, g, t, r, m)
                    if k not in res_map: res_map[k] = {}
                    res_map[k][s] = val[4] # Guarda a célula HTML
                except Exception as e:
                    print(f"\n{Fore.RED}Erro Thread: {e}{Fore.RESET}")
        except KeyboardInterrupt:
            print(f"\n{Fore.RED}Cancelado pelo usuário!{Fore.RESET}")
            sys.exit(0)

    # === EXECUÇÃO PING ===
    if CONFIG["ENABLE_PING"]:
        log_print("\nIniciando Ping Tests...", Fore.MAGENTA)
        ips = set([s for g in groups.values() for s in g['servers']])
        with ThreadPoolExecutor(max_workers=CONFIG["THREADS"]) as exc:
            for f in as_completed({exc.submit(run_ping, i): i for i in ips}):
                rc, out, ms = f.result()
                st = "✅ UP" if rc==0 else "❌ DOWN"
                cls = "status-ok" if rc==0 else "status-fail"
                print(f"  Ping {out.split()[1] if len(out.split())>1 else 'IP'}: {st}")
                PING_RESULTS_BUFFER.append(f"<tr><td>{out.split()[1] if len(out.split())>1 else 'Target'}</td><td class='{cls}'>{st}</td><td>{ms}ms</td></tr>")

    # === MONTAGEM DO RELATÓRIO (REORDENAÇÃO) ===
    log_print("\nGerando Relatório HTML...", Fore.CYAN)
    
    for dt in tests:
        modes = ["iterative", "recursive"] if "both" in dt['test_types'] else [dt['test_types']]
        targets = [dt['domain']] + [f"{x}.{dt['domain']}" for x in dt['extras']]
        
        # Cabeçalho do Domínio
        HTML_MATRIX_BUFFER.append(f'<div class="domain-block"><div class="domain-header">🌐 {dt["domain"]} <span class="badge">{dt["test_types"]}</span></div>')
        
        for g in dt['groups']:
            if g in groups:
                srvs = groups[g]['servers']
                HTML_MATRIX_BUFFER.append(f'<div style="background:#2d2d30;color:#9cdcfe;padding:8px;border-bottom:1px solid #444;font-weight:bold">Grupo: {g}</div>')
                HTML_MATRIX_BUFFER.append('<table><thead><tr><th style="width:30%">Target (Record)</th>')
                for s in srvs: HTML_MATRIX_BUFFER.append(f'<th>{s}</th>')
                HTML_MATRIX_BUFFER.append('</tr></thead><tbody>')
                
                for m in modes:
                    for t in targets:
                        for r in dt['records']:
                            HTML_MATRIX_BUFFER.append(f'<tr><td><span class="badge">{m}</span> <strong>{t}</strong> <span style="color:#888">({r})</span></td>')
                            for s in srvs:
                                # Busca o resultado no mapa. Se não existir (erro grave ou conectividade), põe traço
                                cell = res_map.get((dt['domain'], g, t, r, m), {}).get(s, '<td style="color:#666">-</td>')
                                HTML_MATRIX_BUFFER.append(cell)
                            HTML_MATRIX_BUFFER.append('</tr>')
                HTML_MATRIX_BUFFER.append('</tbody></table>')
        HTML_MATRIX_BUFFER.append('</div>')

    final_file = generate_html(st_time.strftime("%d/%m %H:%M:%S"), datetime.datetime.now().strftime("%d/%m %H:%M:%S"), time.time()-t0, groups)
    
    print(f"\n{Fore.GREEN}=== SUCESSO ==={Fore.RESET}")
    print(f"Relatório HTML: {Fore.CYAN}{final_file}{Fore.RESET}")
    if CONFIG["GENERATE_LOG_TEXT"]:
        print(f"Relatório TXT : {Fore.CYAN}{LOG_FILE_TEXT}{Fore.RESET}")
    print(f"Stats: Total {STATS['TOTAL']} | OK {STATS['SUCCESS']} | Alertas {STATS['WARNING']} | Falhas {STATS['FAILED']}")
