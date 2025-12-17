# 🔍 Diagnóstico DNS Avançado

> "Porque a culpa é sempre do DNS, mas agora você tem provas coloridas em HTML para diagnosticar o problema."

Este é um script em **Bash** "levemente" ajeitadinho para realizar testes de resolução de nomes em massa contra múltiplos servidores DNS. Ele ignora a sanidade mental de quem tenta debugar DNS na mão (`dig` um por um? sério?) e automatiza consultas iterativas, recursivas, validação de portas e até latência.

Ideal para engenheiros de rede, sysadmins e pessoas que precisam provar tecnicamente que nem sempre o problema **não** é a aplicação, ou confirmar que **sim** :D.

## 🚀 Funcionalidades

* **Verificação de Consistência:** Por que testar uma vez se você pode testar 10? O script repete as queries para garantir que o resultado é estável (pega DNS fazendo Load Balance com dados desatualizados).
* **Critérios de Divergência (Strict Mode):** Você define o que é erro. Mudança de IP no Round-Robin deve alarmar? Ordem dos registros importa? TTL mudando é problema? Você decide.
* **HTML Dashboard:** Gera um relatório visual com matriz de falhas, tempos de resposta, **resumos de TCP/DNSSEC**, inventário de execução e o **manual de ajuda completo embutido**.
* **Security & Risk Scan:** Verifica vulnerabilidades comuns como **Transferência de Zona (AXFR)** permitida, **Recursão Aberta**, **Sincronismo SOA** (Serial) e vazamento de versão do BIND.
* **Testes de Serviço (Features):** Valida se o servidor suporta **TCP** (RFC 7766) e se responde com validação **DNSSEC** (RRSIG/AD), com contadores de sucesso/falha no terminal e HTML.
* **Validação de Conectividade:** Testa a porta 53 (TCP/UDP) antes de tentar o DNS. Se a porta estiver fechada, ele nem perde tempo tentando resolver (Smart Error Logging).
* **Latência (ICMP):** Roda testes de ping contra os servidores DNS para saber se o problema é resolução ou se o link caiu mesmo.
* **Modo Interativo:** Pergunta se você quer mudar os timeouts, número de tentativas de consistência e critérios rigorosos (Strict IP/TTL/Order).
* **Agnóstico:** Se não tiver `nc` (netcat), ele usa `/dev/tcp` do Bash. Se não tiver `dig`, bem... aí você não devia estar rodando um script de DNS.

## 📋 Pré-requisitos

Você precisa de um Linux e vontade de viver. Ah, e destes pacotes:

* `bash` (versão 4+ recomendada).
* `bind-utils` (ou `dnsutils` no Debian/Ubuntu) - precisamos do binário `dig`.
* `iputils-ping` - para os testes de ICMP.
* `nc` (netcat) - opcional (o script usa `/dev/tcp` automaticamente se ausente).

## 🛠️ Instalação

```bash
# 1. baixe o arquivo e dê permissão de execução (porque o Linux não confia em você)
chmod +x diagnostico_dns.sh

# 2. Crie os arquivos CSV (veja os exemplos abaixo) ou o script vai reclamar.
````

ou git (precisa instalar o git)
```bash
# 1. Clone este repositório (você já deve ter feito isso)
git clone https://github.com/flashbsb/diagnostico_dns.git
cd diagnostico_dns
````

## ▶️ Como Usar

### Modo Interativo (Recomendado para Debug)

Rode sem argumentos. O script vai te entrevistar sobre timeouts, retries, e ativar os modos rigorosos de verificação (Strict Mode). A detecção de IPv6 é automática.

```bash
./diagnostico_dns.sh
```

### Modo "Confio nos meus Defaults" (Automação)

Use a flag `-y` para pular as perguntas e aceitar os padrões definidos no cabeçalho do script.

```bash
./diagnostico_dns.sh -y
```

> **Nota:** No modo `-y`, o script usará as variáveis do arquivo `diagnostico.conf`. Certifique-se de configurar `ENABLE_TCP_CHECK` e `ENABLE_DNSSEC_CHECK` conforme necessário.

### Flags Disponíveis

  * `-n <arquivo>`: Caminho do CSV de domínios (Default: domains_tests.csv)
  * `-g <arquivo>`: Caminho do CSV de grupos DNS (Default: dns_groups.csv)
  * `-l`: Gerar LOG de texto (.log) estilo forense (Auditoria)
  * `-y`: Modo Silencioso (Não interativo / Aceita defaults do .conf)
  * `-s`: Modo Simplificado (Gera HTML sem logs técnicos para redução de tamanho)
  * `-j`: Gera saída em JSON estruturado (.json) para integrações.
  * `-t`: Habilita testes de conectividade TCP (Sobrescreve conf)
  * `-d`: Habilita validação DNSSEC (Sobrescreve conf)
  * `-x`: Habilita teste de transferência de zona (AXFR) (Sobrescreve conf)
  * `-r`: Habilita teste de recursão aberta (Sobrescreve conf)
  * `-T`: Habilita traceroute (Rota)
  * `-V`: Habilita verificação de versão BIND
  * `-Z`: Habilita verificação de sincronismo SOA
  * `-h`: Exibe este menu de ajuda

## 🕵️‍♂️ Critérios de Divergência (Strict Mode)

O script possui um sistema inteligente para detectar "flapping" ou inconsistências entre as múltiplas tentativas ${CYAN}CONSISTENCY_CHECKS${NC} (Padrão: 3)

* **Strict IP Check:** Se `true`, qualquer alteração no IP de resposta entre as tentativas é marcada como DIVERGÊNCIA. Se `false` (padrão), ele entende que Round-Robin é normal.
* **Strict Order Check:** Se `true`, a ordem dos registros na resposta deve ser idêntica. Se `false` (padrão), a ordem é ignorada (sort) antes de comparar.
* **Strict TTL Check:** Se `true`, o TTL deve ser idêntico em todas as respostas. Se `false` (padrão), diferenças de TTL (comuns em propagação/cache) são ignoradas.

> Esses critérios podem ser configurados no início do modo interativo.

## ⚙️ Configuração dos CSVs

O script depende de dois arquivos CSV no mesmo diretório. **Use ponto e vírgula (;)** como separador, senão o `awk` chora.

### 1\. `dns_groups.csv` (Seus Alvos)

Define **QUEM** responderá as perguntas.

Formato: `NOME_GRUPO;DESCRICAO;TIPO;TIMEOUT;SERVIDORES`

| Campo | Descrição |
|-------|-----------|
| **Nome** | ID do grupo (sem espaços, ex: `GOOGLE`). Usado para vincular no outro CSV. |
| **Descrição** | Texto livre para o relatório. |
| **Tipo** | `authoritative` (não recursivo), `recursive` (resolvers públicos) ou `mixed`. |
| **Timeout** | Timeout específico para este grupo em segundos (ex: `2`). |
| **Servidores** | IPs ou Hostnames separados por vírgula (ex: `8.8.8.8,8.8.4.4`). |

**Exemplo:**

```csv
CLOUDFLARE;Resolver Publico Rapido;recursive;2;1.1.1.1,1.0.0.1
AD_INTERNO;Active Directory Corp;mixed;1;192.168.10.5,192.168.10.6
```
### 2\. `diagnostico.conf` (Ajustes Finos)
 
 Arquivo opcional para definir defaults (se não quiser usar o menu interativo toda vez).
 
 ```bash
 ENABLE_TCP_CHECK="true"      # Testa suporte a TCP/53
 ENABLE_DNSSEC_CHECK="true"   # Testa validação DNSSEC
 ENABLE_AXFR_CHECK="true"     # Testa transferência de zona (RISCO)
 ENABLE_RECURSION_CHECK="true"# Testa recursão aberta (RISCO)
 ENABLE_SOA_SERIAL_CHECK="true" # Valida consistência de Serial SOA
 ENABLE_TRACE_CHECK="true"    # Executa traceroute (pode ser lento)
 
 # Relatórios
 ENABLE_FULL_REPORT="true"    # Gera relatório HTML Detalhado (Padrão: true)
 ENABLE_SIMPLE_REPORT="false" # Gera relatório HTML Simplificado (Padrão: false)
 GENERATE_JSON_REPORT="false" # Gera relatório JSON (Padrão: false)
 
 # Comportamento
 VALIDATE_CONNECTIVITY="true" # Testa porta 53 antes do dig
 ONLY_TEST_ACTIVE_GROUPS="true" # Otimização: Testar apenas IPs usados
 VERBOSE="false"              # Logs detalhados no terminal
 GENERATE_LOG_TEXT="false"    # Gera log .log além do HTML
 TIMEOUT=4                    # Timeout global
 LOG_PREFIX="dnsdiag"         # Prefixo dos arquivos de log
 PING_PACKET_LOSS_LIMIT=5     # % - Tolerância de perda de pacotes
 
 # Ajustes do DIG
 DEFAULT_DIG_OPTIONS="...flags..."
 RECURSIVE_DIG_OPTIONS="...flags..."
 ```
 
 ### 3\. `domains_tests.csv` (Suas Perguntas)

Define **O QUE** você vai perguntar e para quem.

Formato: `DOMINIO;GRUPOS;TESTE;TIPOS_REGISTRO;HOSTS_EXTRA`

| Campo | Descrição |
|-------|-----------|
| **Domínio** | O domínio raiz (ex: `google.com`). |
| **Grupos** | IDs definidos no `dns_groups.csv` (ex: `CLOUDFLARE`). Pode ter múltiplos separados por vírgula. |
| **Teste** | `iterative` (padrão), `recursive` (pede a resposta completa) ou `both`. |
| **Registros** | Tipos de record separados por vírgula (ex: `a,aaaa,mx,txt,soa`). |
| **Hosts Extra** | Subdomínios (apenas o prefixo) para testar junto (ex: `www,mail`). |

**Exemplo:**

```csv
google.com;CLOUDFLARE;recursive;a,aaaa;www,drive
meu-ad.local;AD_INTERNO;iterative;a,soa,srv;ldap
```

## 🐛 Troubleshooting

  * **O relatório HTML está em branco:** Verifique se você tem permissão de escrita na pasta `logs/`.
  * **"Connection Refused" na matriz:** O servidor existe, mas a porta 53 está fechada. Verifique firewall.
  * **"Timeout" na matriz:** O pacote saiu e nunca voltou (ou foi dropado). Rota ou Firewall.
  * **Script trava no ping:** Se você colocou 500 IPs, vai demorar. Ajuste o `PING_COUNT` no início da execução interativa.

-----

*Mantido por quem cansou de usar `nslookup` no Windows.*

#### Arquivo: `dns_groups_public.csv`
Contém os principais resolvers públicos e alguns autoritativos "raiz" para teste de estresse.

```csv
# NOME;DESCRICAO;TIPO;TIMEOUT;SERVIDORES
GOOGLE;Google Public DNS;recursive;2;8.8.8.8,8.8.4.4
CLOUDFLARE;Cloudflare DNS;recursive;2;1.1.1.1,1.0.0.1
QUAD9;Quad9 Security DNS;recursive;3;9.9.9.9,149.112.112.112
OPENDNS;Cisco OpenDNS;recursive;3;208.67.222.222,208.67.220.220
ROOT_SERVERS;Root Servers (Letra A e J);authoritative;5;198.41.0.4,192.58.128.30
````

#### Arquivo: `domains_tests_public.csv`

Testa domínios grandes, registros TXT (SPF), MX e conectividade básica.

```csv
# DOMINIO;GRUPOS;TESTE;TIPOS_REGISTRO;HOSTS_EXTRA
google.com;GOOGLE,CLOUDFLARE;recursive;a,aaaa,txt;www,mail
wikipedia.org;QUAD9,OPENDNS;recursive;a,soa;pt,en
cisco.com;OPENDNS;recursive;mx,txt;
ietf.org;ROOT_SERVERS;iterative;ns;
example.com;GOOGLE,CLOUDFLARE,QUAD9;recursive;a;
fail-test.local;GOOGLE;recursive;a; # Este deve gerar NXDOMAIN para testar o alerta amarelo
```

### Como rodar com esses arquivos novos:

```bash
./diagnostico_dns.sh -g dns_groups_public.csv -n domains_tests_public.csv
