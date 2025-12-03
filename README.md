````markdown
# 🔍 Diagnóstico DNS Avançado (Bash Edition)

> "Porque a culpa é sempre do DNS, mas agora você tem provas coloridas em HTML."

Este é um script em **Bash** "levemente" ajeitadinho para realizar testes de resolução de nomes em massa contra múltiplos servidores DNS. Ele ignora a sanidade mental de quem tenta debugar DNS na mão e automatiza consultas iterativas, recursivas e validação de portas.

Ideal para engenheiros de rede, sysadmins e pessoas que precisam provar para o chefe que o firewall está bloqueando a porta 53.

## 🚀 Funcionalidades

* **Multithread? Não.** Mas é rápido o suficiente.
* **Agnóstico de `netcat`:** Usa `/dev/tcp` nativo do Bash se você não tiver o `nc` instalado (hackerman mode).
* **Relatórios Bonitos:** Gera um HTML com CSS embutido (modo noturno, claro) para você enviar pro gerente.
* **Dados Estruturados:** Gera um JSON (artesanal) para integrações.
* **Logs Detalhados:** Tudo que acontece vai para `.txt` também.
* **Flexível:** Configuração via arquivos CSV (porque YAML é modinha).

## 📋 Pré-requisitos

Você precisa de um Linux e vontade de viver. Ah, e destes pacotes:

* `bash` (versão 4+ recomendada)
* `bind-utils` (ou `dnsutils` no Debian/Ubuntu) - precisamos do comando `dig`.
* `coreutils` (padrão em qualquer distro).

## 🛠️ Instalação

```bash
# 1. Clone este repositório (você já deve ter feito isso)
git clone [https://github.com/flashbsb/diagnostico_dns.git](https://github.com/flashbsb/diagnostico_dns.git)
cd diagnostico_dns

# 2. Dê permissão de execução (porque o Linux não confia em você)
chmod +x diagnostico_dns.sh
````

## ⚙️ Configuração

O script usa três arquivos na raiz. Se você errar o formato, o script vai te julgar (e falhar).

### 1\. `script_config.cfg`

Configurações globais. Edite para mudar timeouts ou opções do `dig`.

```ini
LOG_PREFIX="dnsdiag"
TIMEOUT="2"
IP_VERSION="ipv4" # ipv4, ipv6 ou both
GENERATE_HTML="true"
```

### 2\. `dns_groups.csv` (Seus Alvos)

Define **QUEM** você vai testar.

  * **Delimitador:** Ponto e vírgula (`;`)
  * **Formato:** `NOME_GRUPO;DESCRICAO;TIPO;TIMEOUT;SERVIDORES`

| Campo | Descrição | Exemplo |
|-------|-----------|---------|
| Nome | ID do grupo (sem espaços) | `GOOGLE` |
| Descrição | Texto livre | `DNS Publico` |
| Tipo | `authoritative`, `recursive` ou `mixed` | `recursive` |
| Timeout | Em segundos | `2` |
| Servidores | IPs ou Hostnames separados por vírgula | `8.8.8.8,8.8.4.4` |

**Exemplo:**

```csv
TLB1;DNS Primario;mixed;2;177.15.130.101,177.15.130.102
GOOGLE;Public DNS;recursive;1;8.8.8.8
```

### 3\. `domains_tests.csv` (Suas Perguntas)

Define **O QUE** você vai perguntar.

  * **Delimitador:** Ponto e vírgula (`;`)
  * **Formato:** `DOMINIO;GRUPOS;TESTE;TIPOS_REGISTRO;HOSTS_EXTRA`

| Campo | Descrição | Exemplo |
|-------|-----------|---------|
| Domínio | O domínio raiz | `google.com` |
| Grupos | IDs definidos no `dns_groups.csv` | `GOOGLE,TLB1` |
| Teste | `iterative`, `recursive` ou `both` | `recursive` |
| Registros | Tipos de record separados por vírgula | `a,ns,txt` |
| Hosts Extra | Subdomínios (apenas o prefixo) | `www,mail` |

**Exemplo:**

```csv
telebras.com.br;TLB1;iterative;ns,soa;
google.com;GOOGLE;recursive;a;www,mail,drive
```

## ▶️ Como Usar

Apenas rode. Sem argumentos, sem frescura.

```bash
./diagnostico_dns.sh
```

O script criará uma pasta `logs/` (se não existir) e cuspirá os resultados lá:

  * `logs/dnsdiag_YYYYMMDD_HHMMSS.html` (O bonitão)
  * `logs/dnsdiag_YYYYMMDD_HHMMSS.json` (O estruturado)
  * `logs/dnsdiag_YYYYMMDD_HHMMSS.txt` (O detalhado)

## 🐛 Troubleshooting

  * **"command not found: dig":** Instale o `bind-utils`. Não tem mágica.
  * **"AVISO: arquivo tem menos colunas":** Você provavelmente editou o CSV no Excel e ele comeu os ponto-e-vírgulas. Use um editor de texto de verdade (vim, nano, vscode).
  * **O script trava:** Verifique se os IPs nos grupos são alcançáveis. O timeout do `dig` às vezes é teimoso.

## 📜 Licença

Faça o que quiser. Se quebrar sua produção, eu nunca estive aqui.
Mas se ajudar, pague um café. ☕

*Mantido por [flashbsb](https://www.google.com/search?q=https://github.com/flashbsb)*

```
```
