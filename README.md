# Testes com o dig para DNS

Scripts para testes com o dig de forma iterativa e recusiva.

## 🚀 Instalação Rápida

```bash
# Instalar os pacotes
apt update
apt install bc wget curl -y

# Baixar o script e arquivos de configuração
wget -O diagnostico_dns.sh https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/diagnostico_dns.sh
wget -O dns_groups.csv https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/dns_groups.csv
wget -O domains_tests.csv https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/domains_tests.csv
wget -O script_config.cfg https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/script_config.cfg
ou
curl -L -o diagnostico_dns.sh https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/diagnostico_dns.sh
curl -L -o dns_groups.csv https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/dns_groups.csv
curl -L -o domains_tests.csv https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/domains_tests.csv
curl -L -o script_config.cfg https://raw.githubusercontent.com/flashbsb/diagnostico_dns/refs/heads/main/script_config.cfg

#alterar arquivos de configuração conforme necessidade

#alterar permissões e executar script
chmod +x diagnostico_dns.sh
./diagnostico_dns.sh
