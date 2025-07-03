#!/bin/bash

# setup-ssl.sh - v2.0 Inteligente e Automatizado
# Gerencia certificados SSL para UniFi e Omada, lidando com serviços conflitantes.

# --- Cores e Funções de Log ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; C='\033[0;36m'; NC='\033[0m'
log() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }

# --- Variável Global ---
SERVICE_ON_PORT_80=""

# --- Funções de Verificação ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script precisa ser executado como root (sudo)."
        exit 1
    fi
}

check_dependencies() {
    log "Verificando dependências..."
    local missing_deps=()
    ! command -v certbot &>/dev/null && missing_deps+=("certbot")
    ! command -v docker &>/dev/null && missing_deps+=("docker")
    ! docker compose version &>/dev/null && missing_deps+=("docker-compose-plugin")
    ! command -v keytool &>/dev/null && missing_deps+=("default-jre")

    if [ ${#missing_deps[@]} -gt 0 ]; then
        warn "Dependências faltando: ${missing_deps[*]}. Tentando instalar..."
        sudo apt-get update -qq && sudo apt-get install -y "${missing_deps[@]}"
    fi
    success "Dependências OK."
}

# --- Funções de Gerenciamento de Serviço (A Inteligência) ---
stop_service_on_port_80() {
    log "Verificando se a porta 80 está em uso por outro serviço..."
    local process_name
    process_name=$(sudo lsof -t -i:80 | xargs -r ps -o comm= -p | head -n 1)

    if [ -n "$process_name" ]; then
        if [[ "$process_name" =~ (apache2|nginx|httpd) ]]; then
            SERVICE_ON_PORT_80=$process_name
            warn "Porta 80 em uso por '$SERVICE_ON_PORT_80'. Parando o serviço temporariamente..."
            sudo systemctl stop "$SERVICE_ON_PORT_80"
            sleep 3 # Aguarda a porta ser liberada
        elif [[ "$process_name" == "docker-proxy" ]]; then
            warn "Porta 80 em uso por um contêiner Docker. Parando os contêineres do projeto..."
            SERVICE_ON_PORT_80="docker"
            docker compose down 2>/dev/null || true
            sleep 3
        else
            error "Processo desconhecido '$process_name' usando a porta 80. Abortando."
            exit 1
        fi
    else
        log "Porta 80 está livre. Parando contêineres do projeto por precaução..."
        docker compose down 2>/dev/null || true
    fi
}

start_service_on_port_80() {
    if [ -n "$SERVICE_ON_PORT_80" ]; then
        log "Reiniciando o serviço '$SERVICE_ON_PORT_80' que estava na porta 80..."
        if [ "$SERVICE_ON_PORT_80" == "docker" ]; then
            docker compose up -d
        else
            sudo systemctl start "$SERVICE_ON_PORT_80"
        fi
    else
        log "Iniciando contêineres do projeto..."
        docker compose up -d
    fi
}

# --- Funções de Certificado ---
run_certbot_for_domain() {
    local domain=$1
    local email=$2
    log "Gerando certificado Let's Encrypt para '$domain'..."
    sudo certbot certonly --standalone --non-interactive --agree-tos --email "$email" -d "$domain"
    if [ $? -ne 0 ]; then
        error "Falha ao gerar certificado para $domain."
        return 1
    fi
    success "Certificado para '$domain' gerado com sucesso!"
    return 0
}

import_certificate_into_unifi() {
    local domain=$1
    log "Iniciando importação forçada de SSL para o UniFi..."
    
    local KEYSTORE_PATH
    KEYSTORE_PATH=$(find ./data/unifi-config -name keystore -type f | head -n 1)

    if [ -z "$KEYSTORE_PATH" ]; then
        error "NÃO FOI POSSÍVEL ENCONTRAR o arquivo 'keystore' dentro de ./data/unifi-config/"
        return 1
    fi
    log "Keystore do UniFi encontrado em: $KEYSTORE_PATH"

    local LE_LIVE_PATH="/etc/letsencrypt/live/$domain"

    log "Fazendo backup do keystore atual..."
    cp "$KEYSTORE_PATH" "${KEYSTORE_PATH}.bak_$(date +%F_%H-%M-%S)"

    log "Convertendo certificados para o formato PKCS12..."
    sudo openssl pkcs12 -export -inkey "$LE_LIVE_PATH/privkey.pem" -in "$LE_LIVE_PATH/fullchain.pem" \
        -out "/tmp/unifi_cert.p12" -name unifi -password pass:aircontrolenterprise || { error "Falha ao criar .p12"; return 1; }

    log "Deletando certificado antigo do keystore..."
    sudo keytool -delete -alias unifi -keystore "$KEYSTORE_PATH" -deststorepass aircontrolenterprise

    log "Importando novo certificado para o keystore..."
    sudo keytool -importkeystore -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise \
        -destkeystore "$KEYSTORE_PATH" -srckeystore "/tmp/unifi_cert.p12" -srcstoretype PKCS12 \
        -srcstorepass aircontrolenterprise -alias unifi -noprompt || { error "Falha ao importar para o keystore"; return 1; }
    
    sudo chown 1000:1000 "$KEYSTORE_PATH"
    rm "/tmp/unifi_cert.p12"
    success "Certificado importado no UniFi com sucesso!"
}

# --- Lógica Principal do Script ---
main() {
    # Garante que, ao sair do script (normalmente ou por erro), os serviços voltem ao normal
    trap start_service_on_port_80 EXIT
    
    check_root
    check_dependencies
    
    clear
    echo -e "${C}╔══════════════════════════════════════╗${NC}"
    echo -e "${C}║      Setup SSL - Controllers        ║${NC}"
    echo -e "${C}╚══════════════════════════════════════╝${NC}"
    echo
    echo "1) Configurar SSL para UniFi"
    echo "2) Configurar SSL para Omada"
    echo "3) Configurar para Ambos"
    echo "4) Sair"
    echo
    read -p "Escolha uma opção: " choice

    local unifi_domain=""
    local omada_domain=""
    local email=""

    case $choice in
        1)
            read -p "Digite o domínio para o UniFi (ex: unifi.meusite.com): " unifi_domain
            read -p "Digite seu email para o Let's Encrypt: " email
            ;;
        2)
            read -p "Digite o domínio para o Omada (ex: omada.meusite.com): " omada_domain
            read -p "Digite seu email para o Let's Encrypt: " email
            ;;
        3)
            read -p "Digite o domínio para o UniFi: " unifi_domain
            read -p "Digite o domínio para o Omada: " omada_domain
            read -p "Digite seu email para o Let's Encrypt: " email
            ;;
        4) exit 0 ;;
        *) error "Opção inválida!"; exit 1 ;;
    esac

    # Para os serviços para liberar a porta 80
    stop_service_on_port_80

    # Processa UniFi se o domínio foi fornecido
    if [ -n "$unifi_domain" ]; then
        if run_certbot_for_domain "$unifi_domain" "$email"; then
            import_certificate_into_unifi "$unifi_domain"
        else
            error "Não foi possível continuar com a importação no UniFi devido a falha na geração do certificado."
        fi
    fi

    # Processa Omada se o domínio foi fornecido
    if [ -n "$omada_domain" ]; then
        if run_certbot_for_domain "$omada_domain" "$email"; then
            warn "Para o Omada, a importação do certificado é MANUAL."
            echo -e "${YELLOW}------------------------------------------------------------------${NC}"
            echo -e "${YELLOW}Acesse a interface web do Omada em https://IP_DO_SERVIDOR:8043${NC}"
            echo -e "${YELLOW}Vá para 'Settings > Controller > HTTPS Certificate' e faça o upload dos seguintes arquivos:${NC}"
            echo -e "  - ${GREEN}Arquivo do Certificado:${NC} /etc/letsencrypt/live/${omada_domain}/fullchain.pem"
            echo -e "  - ${GREEN}Arquivo da Chave:${NC} /etc/letsencrypt/live/${omada_domain}/privkey.pem"
            echo -e "${YELLOW}------------------------------------------------------------------${NC}"
        fi
    fi

    log "Processo de configuração de SSL concluído."
    log "O trap de saída irá reiniciar os serviços agora..."
    # A função 'start_service_on_port_80' será chamada automaticamente na saída do script.
}

main "$@"
