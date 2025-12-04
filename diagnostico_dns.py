#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
DIAGNÓSTICO DNS - PY EDITION (Versão Definitiva & Corrigida)
Versão: 10.2 (Full Bash Parity)

Requisitos:
1. Python 3.6+
2. 'dig' instalado e no PATH (bind-utils / dnsutils)
3. (Opcional) 'pip install colorama'
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
# CORES (Cross-Platform)
# ==============================================
try:
    from colorama import init, Fore, Style
    init()
    HAS_COLORAMA = True
except ImportError:
    HAS_COLORAMA = False
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
    "GENERATE_LOG_TEXT": False, # Controlado pelo flag -l
    "VERBOSE": False,           # Controlado pelo flag -v
    "IP_VERSION": "ipv4",
    "CHECK_BIND": False,        # Restaurado do Bash
    "ENABLE_PING": True,
    "PING_COUNT": 4,
    "PING_TIMEOUT": 2,
    "THREADS": 10,
    "FILES": {
        "DOMAINS": "domains_tests.csv",
        "GROUPS": "dns_groups.csv"
    }
}

DEFAULT_DIG_OPTS = ["+norecurse", "+time=1", "+tries=1", "+nocookie", "+cd", "+bufsize=512"]
RECURSIVE_DIG_OPTS = ["+time=1", "+tries=1", "+nocookie", "+cd", "+bufsize=512"]

STATS = {"TOTAL": 0, "SUCCESS": 0, "FAILED": 0, "WARNING": 0}
LOCK = threading.Lock()
HTML_CONN_ERR_LOGGED = set()
CONNECTIVITY_CACHE = {}

# Buffers
HTML_MATRIX_BUFFER = []
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
    if not CONFIG["GENERATE_LOG_TEXT"]: return
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with LOCK:
        with open(LOG_FILE_TEXT, "a", encoding="utf-8") as f:
            f.write(f"[{ts}] {msg}\n")

def check_dependencies():
    try:
        subprocess.run(["dig", "-v"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        print(f"{Fore.RED}ERRO: 'dig' não encontrado. Instale o BIND Tools.{Fore.RESET}")
        sys.exit(1)

# ==============================================
# NETWORK CORE
# ==============================================

def check_port(server, port=53, timeout=2.0):
    if server in CONNECTIVITY_CACHE: return CONNECTIVITY_CACHE[server]
    try:
        with socket.create_connection((server, port), timeout=timeout): res = True
    except: res = False
    with LOCK: CONNECTIVITY_CACHE[server] = res
    return res

def get_bind_version(server):
    """Tenta descobrir a versão do BIND (Restaurado do Bash)"""
    cmd = ["dig", "+short", "+time=1", "+tries=1", f"@{server}", "chaos", "txt", "version.bind"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, errors='replace')
        ver = proc.stdout.strip().replace('"', '')
        return f" (Ver: {ver})" if ver else ""
    except:
        return ""

def run_ping(ip):
    sys_os = platform.system().lower()
    cmd = ["ping"]
    if "windows" in sys_os:
        cmd.extend(["-n", str(CONFIG["PING_COUNT"]), "-w", str(CONFIG["PING_TIMEOUT"] * 1000), ip])
    else:
        cmd.extend(["-c", str(CONFIG["PING_COUNT"]), "-W", str(CONFIG["PING_TIMEOUT"]), ip])
    start = time.time()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, errors='replace')
        return proc.returncode, proc.stdout, int((time.time() - start) * 1000)
    except Exception as e:
        return 1, str(e), 0

def run_dig(server, target, record, mode="iterative"):
    cmd = ["dig"]
    cmd.extend(DEFAULT_DIG_OPTS if mode == "iterative" else RECURSIVE_DIG_OPTS)
    cmd.append("-4" if CONFIG["IP_VERSION"] == "ipv4" else "-6")
    cmd.extend([f"@{server}", target, record])
    
    start = time.time()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, errors='replace')
        return proc.returncode, proc.stdout, int((time.time() - start) * 1000), " ".join(cmd)
    except Exception as e:
        return 999, str(e), 0, " ".join(cmd)

# ==============================================
# WORKER
# ==============================================

def process_dns_task(task_data):
    domain, group_name, srv, target, rec_type, mode, test_id = task_data
    
    # 1. Validação Conectividade
    if CONFIG["VALIDATE_CONNECTIVITY"]:
        if not check_port(srv, 53, CONFIG["TIMEOUT"]):
            with LOCK:
                STATS["FAILED"] += 1
                STATS["TOTAL"] += 1
                conn_id = f"conn_err_{srv.replace('.', '_')}"
                if srv not in HTML_CONN_ERR_LOGGED:
                    HTML_CONN_ERR_LOGGED.add(srv)
                    HTML_DETAILS_BUFFER.append(f'<details id="{conn_id}" class="conn-error-block"><summary class="log-header" style="color:#f44747"><strong>FALHA CONEXÃO</strong> - {srv}</summary><pre>Porta 53 inalcançável via TCP.</pre></details>')
                print(f"{Fore.RED}x{Style.RESET_ALL}", end="", flush=True)
                file_log(f"CONN FAIL: {srv}")
                return (group_name, target, rec_type, mode, f'<td><a href="#" onclick="showLog(\'{conn_id}\'); return false;" class="cell-link status-fail">❌ DOWN</a></td>')

    # 2. Execução
    ret_code, output, duration, full_cmd = run_dig(srv, target, rec_type, mode)
    
    # 3. Check Bind Version (Opcional)
    bind_ver = ""
    if CONFIG["CHECK_BIND"]:
        bind_ver = get_bind_version(srv)

    # 4. Análise
    answer_match = re.search(r"ANSWER:\s+(\d+)", output)
    answer_count = int(answer_match.group(1)) if answer_match else 0
    
    status_txt = "OK"; css="status-ok"; icon="✅"; log_col=""
    
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
        if answer_count == 0:
            status_txt = "NOANSWER"; css="status-warning"; icon="⚠️"
            with LOCK: STATS["WARNING"] += 1; print(f"{Fore.YELLOW}!{Style.RESET_ALL}", end="", flush=True)
        else:
            with LOCK: STATS["SUCCESS"] += 1; print(f"{Fore.GREEN}.{Style.RESET_ALL}", end="", flush=True)
    else:
        status_txt = "UNKNOWN"; css="status-warning"; icon="❓"
        with LOCK: STATS["WARNING"] += 1; print(f"{Fore.YELLOW}?{Style.RESET_ALL}", end="", flush=True)

    with LOCK: STATS["TOTAL"] += 1
    
    if CONFIG["VERBOSE"]:
        log_print(f"DEBUG: {srv} -> {target} ({rec_type}) = {status_txt}", Fore.MAGENTA)

    # 5. HTML
    if css == "status-fail": log_col = "color:#f44747"
    elif css == "status-warning": log_col = "color:#ffcc02"
    
    uid = f"test_{test_id}"
    html_cell = f'<td><a href="#" onclick="showLog(\'{uid}\'); return false;" class="cell-link {css}">{icon} {status_txt} <span class="time-badge">{duration}ms</span></a></td>'
    html_log = f'<details id="{uid}"><summary class="log-header"><span class="log-id">#{test_id}</span> <span style="{log_col}">{status_txt}</span> <strong>{srv}</strong> &rarr; {target} ({rec_type}) <span class="badge">{duration}ms</span>{bind_ver}</summary><pre>{full_cmd}\n\n{output.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")}</pre></details>'
    
    with LOCK: HTML_DETAILS_BUFFER.append(html_log); file_log(f"TEST {test_id} | {srv} | {target} | {status_txt}")
    return (group_name, target, rec_type, mode, html_cell)

# ==============================================
# MAIN
# ==============================================

def load_csvs():
    # Mesma lógica anterior, omitida para brevidade (não foi alterada)
    dg = {}; dt = []
    if not os.path.exists(CONFIG["FILES"]["GROUPS"]): sys.exit(f"{Fore.RED}Falta arquivo: {CONFIG['FILES']['GROUPS']}{Fore.RESET}")
    with open(CONFIG["FILES"]["GROUPS"], 'r', encoding='utf-8') as f:
        for r in csv.reader(f, delimiter=';'):
            if r and not r[0].startswith('#') and len(r)>=5: dg[r[0]] = {"desc": r[1], "type": r[2], "timeout": r[3], "servers": r[4].split(',')}
    if not os.path.exists(CONFIG["FILES"]["DOMAINS"]): sys.exit(f"{Fore.RED}Falta arquivo: {CONFIG['FILES']['DOMAINS']}{Fore.RESET}")
    with open(CONFIG["FILES"]["DOMAINS"], 'r', encoding='utf-8') as f:
        for r in csv.reader(f, delimiter=';'):
            if r and not r[0].startswith('#') and len(r)>=5: dt.append({"domain": r[0], "groups": r[1].split(','), "test_types": r[2], "records": r[3].split(','), "extras": r[4].split(',') if r[4] else []})
    return dg, dt

def interactive_mode():
    print(f"{Fore.BLUE}=== CONFIGURAÇÃO INTERATIVA ==={Fore.RESET}")
    def ask(msg, key, cast=str):
        v = input(f"  🔹 {msg} [{CONFIG[key]}]: ")
        if v: CONFIG[key] = cast(v); print(f"     >> {v}")
    
    ask("Log TXT (-l)? (True/False)", "GENERATE_LOG_TEXT", bool)
    ask("Check BIND Version? (True/False)", "CHECK_BIND", bool)
    ask("Verbose? (True/False)", "VERBOSE", bool)
    ask("Threads", "THREADS", int)
    print("")

def generate_html(st, et, dur, grps):
    # Template HTML (Resumido para caber, mas funcional)
    css = """body{font-family:'Segoe UI',sans-serif;background:#1e1e1e;color:#d4d4d4;padding:20px} .container{max-width:1400px;margin:0 auto} 
    .card{background:#252526;padding:15px;border-radius:6px;text-align:center;border-bottom:3px solid #444} 
    .card-num{font-size:2em;font-weight:bold;display:block} .dashboard{display:grid;grid-template-columns:repeat(4,1fr);gap:15px}
    .st-ok .card-num{color:#4ec9b0} .st-fail .card-num{color:#f44747} .st-warn .card-num{color:#ffcc02}
    table{width:100%;border-collapse:collapse} th,td{padding:8px;border-bottom:1px solid #3e3e42} th{background:#2d2d30}
    .status-ok{color:#4ec9b0} .status-fail{color:#f44747;background:rgba(244,71,71,0.1)} .status-warning{color:#ffcc02}
    .modal{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.8)} 
    .modal-content{background:#252526;margin:5% auto;width:80%;border:1px solid #444;padding:20px}
    pre{background:#000;padding:10px;overflow-x:auto} details{background:#1e1e1e;border:1px solid #333;margin-bottom:5px} summary{padding:10px;cursor:pointer;background:#252526}"""
    
    js = """function showLog(id){document.getElementById('modalText').innerHTML=document.getElementById(id).querySelector('pre').innerHTML;document.getElementById('logModal').style.display='block'}
    function closeModal(){document.getElementById('logModal').style.display='none'}"""
    
    html = f"""<!DOCTYPE html><html><head><meta charset='UTF-8'><title>DNS Report</title><style>{css}</style><script>{js}</script></head>
    <body><div id="logModal" class="modal" onclick="if(event.target==this)closeModal()"><div class="modal-content"><span onclick="closeModal()" style="float:right;cursor:pointer;font-size:20px">&times;</span><pre id="modalText"></pre></div></div>
    <div class="container"><h1>📊 DNS Report</h1>
    <div class="dashboard">
        <div class="card st-total"><span class="card-num">{STATS['TOTAL']}</span>Total</div>
        <div class="card st-ok"><span class="card-num">{STATS['SUCCESS']}</span>Sucesso</div>
        <div class="card st-warn"><span class="card-num">{STATS['WARNING']}</span>Alertas</div>
        <div class="card st-fail"><span class="card-num">{STATS['FAILED']}</span>Falhas</div>
    </div>
    <div style="background:#252526;padding:10px;margin:20px 0;border-left:4px solid #666">Início: {st} | Fim: {et} | Duração: {dur:.2f}s</div>
    {"".join(HTML_MATRIX_BUFFER)}
    <h2>📡 Ping (ICMP)</h2><table><tbody>{"".join(PING_RESULTS_BUFFER)}</tbody></table>
    <h2>🛠️ Logs</h2>{"".join(HTML_DETAILS_BUFFER)}
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
    # --- RESTAURADO ---
    parser.add_argument("-l", "--log", action="store_true", help="Gerar log .txt")
    parser.add_argument("-v", "--verbose", action="store_true", help="Debug na tela")
    args = parser.parse_args()

    if args.domains: CONFIG["FILES"]["DOMAINS"] = args.domains
    if args.groups: CONFIG["FILES"]["GROUPS"] = args.groups
    if args.threads: CONFIG["THREADS"] = args.threads
    if args.log: CONFIG["GENERATE_LOG_TEXT"] = True     # Correção aplicada
    if args.verbose: CONFIG["VERBOSE"] = True           # Correção aplicada

    os.makedirs("logs", exist_ok=True)
    LOG_FILE_TEXT = f"logs/dnsdiag_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

    print(f"{Fore.BLUE}=== DNS DIAGNOSTIC TOOL v10.2 (PY) ==={Fore.RESET}")
    if not args.yes: interactive_mode()
    
    groups, tests = load_csvs()
    tasks = []
    tid = 0
    
    log_print(f"Carregando tarefas...", Fore.MAGENTA)
    for dt in tests:
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

    log_print(f"Iniciando {len(tasks)} testes com {CONFIG['THREADS']} threads...", Fore.CYAN)
    
    st_time = datetime.datetime.now(); t0 = time.time()
    res_map = {}
    
    with ThreadPoolExecutor(max_workers=CONFIG["THREADS"]) as exc:
        fut = {exc.submit(process_dns_task, t): t for t in tasks}
        for f in as_completed(fut):
            try:
                d, g, s, t, r, m, _ = fut[f]
                val = f.result()
                k = (d, g, t, r, m)
                if k not in res_map: res_map[k] = {}
                res_map[k][s] = val[4]
            except Exception as e: print(e)

    if CONFIG["ENABLE_PING"]:
        log_print("Executando Ping...", Fore.MAGENTA)
        ips = set([s for g in groups.values() for s in g['servers']])
        with ThreadPoolExecutor(max_workers=CONFIG["THREADS"]) as exc:
            for f in as_completed({exc.submit(run_ping, i): i for i in ips}):
                rc, out, ms = f.result()
                st = "✅ UP" if rc==0 else "❌ DOWN"
                PING_RESULTS_BUFFER.append(f"<tr><td>{out.split()[1] if len(out.split())>1 else 'IP'}</td><td class='{'status-ok' if rc==0 else 'status-fail'}'>{st}</td><td>{ms}ms</td></tr>")

    # Reconstrói HTML ordenado
    for dt in tests:
        modes = ["iterative", "recursive"] if "both" in dt['test_types'] else [dt['test_types']]
        targets = [dt['domain']] + [f"{x}.{dt['domain']}" for x in dt['extras']]
        HTML_MATRIX_BUFFER.append(f'<div class="domain-block"><div class="domain-header">🌐 {dt["domain"]}</div>')
        for g in dt['groups']:
            if g in groups:
                HTML_MATRIX_BUFFER.append(f'<div style="background:#333;color:#fff;padding:5px">Grupo: {g}</div><table><tr><th>Target</th>')
                srvs = groups[g]['servers']
                for s in srvs: HTML_MATRIX_BUFFER.append(f'<th>{s}</th>')
                HTML_MATRIX_BUFFER.append('</tr>')
                for m in modes:
                    for t in targets:
                        for r in dt['records']:
                            HTML_MATRIX_BUFFER.append(f'<tr><td>{t} ({r})</td>')
                            for s in srvs: HTML_MATRIX_BUFFER.append(res_map.get((dt['domain'], g, t, r, m), {}).get(s, "<td>-</td>"))
                            HTML_MATRIX_BUFFER.append('</tr>')
                HTML_MATRIX_BUFFER.append('</table>')
        HTML_MATRIX_BUFFER.append('</div>')

    final = generate_html(st_time.strftime("%d/%m %H:%M"), datetime.datetime.now().strftime("%d/%m %H:%M"), time.time()-t0, groups)
    print(f"\n{Fore.GREEN}Concluído! Relatório: {final}{Fore.RESET}")
