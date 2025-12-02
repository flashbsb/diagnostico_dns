# Testes com o dig para DNS

Scripts para testes com o dig de forma iterativa e recusiva.

## 🚀 Instalação Rápida

```bash
# Instalar os pacotes
apt update && apt install bc

# Baixar o script e arquivos de configuração
wget -O diagnostico_dns.sh https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/diagnostico_dns.sh
wget -O diagnostico_dns.sh https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/dns_groups.csv
wget -O diagnostico_dns.sh https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/domains_tests.csv
wget -O diagnostico_dns.sh https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/script_config.cfg
ou
curl -L -o diagnostico_dns.sh https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/diagnostico_dns.sh
curl -L -o diagnostico_dns.sh https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/dns_groups.csv
curl -L -o diagnostico_dns.sh https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/domains_tests.csv
curl -L -o diagnostico_dns.sh https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/script_config.cfg

#alterar arquivos de configuração conforme necessidade

#alterar permissões e executar script
chmod +x diagnostico_dns.sh
./install_epe.sh
