#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Função para log
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Verificar se está rodando como root para certbot
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script precisa ser executado como root para usar certbot"
        exit 1
    fi
}

# Verificar se certbot está instalado
check_certbot() {
    if ! command -v certbot &> /dev/null; then
        error "Certbot não está instalado. Instale com:"
        echo "  Ubuntu/Debian: apt update && apt install certbot"
        echo "  CentOS/RHEL: yum install certbot"
        exit 1
    fi
}

# Verificar se docker-compose está instalado
check_docker_compose() {
    if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
        error "Docker Compose não encontrado"
        exit 1
    fi
}

# Parar containers se estiverem rodando
stop_containers() {
    log "Parando containers se estiverem rodando..."
    docker-compose down 2>/dev/null || docker compose down 2>/dev/null || true
}

# Configurar certificado para UniFi
setup_unifi() {
    local domain=$1
    local email=$2
    
    log "Configurando certificado SSL para UniFi (domínio: $domain)"
    
    # Parar containers para liberar portas
    stop_containers
    
    # Gerar certificado
    log "Gerando certificado Let's Encrypt..."
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain" || {
        error "Falha ao gerar certificado para $domain"
        return 1
    }
    
    # Criar diretório SSL
    mkdir -p ssl/unifi
    
    # Copiar certificados
    log "Copiando certificados para UniFi..."
    cp "/etc/letsencrypt/live/$domain/fullchain.pem" ssl/unifi/
    cp "/etc/letsencrypt/live/$domain/privkey.pem" ssl/unifi/
    
    # Converter para formato PKCS12 (UniFi precisa)
    log "Convertendo certificado para formato PKCS12..."
    openssl pkcs12 -export \
        -in ssl/unifi/fullchain.pem \
        -inkey ssl/unifi/privkey.pem \
        -out ssl/unifi/keystore \
        -name unifi \
        -password pass:aircontrolenterprise
    
    # Ajustar permissões
    chown -R 1000:1000 ssl/unifi
    chmod 600 ssl/unifi/privkey.pem
    chmod 644 ssl/unifi/fullchain.pem
    
    log "Certificado UniFi configurado com sucesso!"
}

# Configurar certificado para Omada
setup_omada() {
    local domain=$1
    local email=$2
    
    log "Configurando certificado SSL para Omada (domínio: $domain)"
    
    # Parar containers para liberar portas
    stop_containers
    
    # Gerar certificado
    log "Gerando certificado Let's Encrypt..."
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain" || {
        error "Falha ao gerar certificado para $domain"
        return 1
    }
    
    # Criar diretório SSL
    mkdir -p ssl/omada
    
    # Copiar certificados (Omada usa nomes específicos)
    log "Copiando certificados para Omada..."
    cp "/etc/letsencrypt/live/$domain/fullchain.pem" ssl/omada/tls.crt
    cp "/etc/letsencrypt/live/$domain/privkey.pem" ssl/omada/tls.key
    
    # Ajustar permissões
    chown -R 1000:1000 ssl/omada
    chmod 600 ssl/omada/tls.key
    chmod 644 ssl/omada/tls.crt
    
    log "Certificado Omada configurado com sucesso!"
}

# Configurar renovação automática
setup_renewal() {
    log "Configurando renovação automática..."
    
    # Criar script de renovação
    cat > /usr/local/bin/renew-controllers-certs.sh << 'EOF'
#!/bin/bash
# Script de renovação automática dos certificados

COMPOSE_DIR="/opt/controllers"  # Ajuste o caminho conforme necessário

# Log da renovação
echo "[$(date)] Iniciando renovação de certificados..." >> /var/log/controllers-renewal.log

# Parar containers
cd "$COMPOSE_DIR"
docker-compose down >> /var/log/controllers-renewal.log 2>&1

# Renovar certificados
certbot renew --quiet >> /var/log/controllers-renewal.log 2>&1

# Reprocessar certificados se renovados
if [ $? -eq 0 ]; then
    # Reprocessar UniFi se existir
    if [ -d "ssl/unifi" ]; then
        for domain in $(certbot certificates | grep "Certificate Name" | awk '{print $3}'); do
            if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
                # Copiar novos certificados
                cp "/etc/letsencrypt/live/$domain/fullchain.pem" ssl/unifi/
                cp "/etc/letsencrypt/live/$domain/privkey.pem" ssl/unifi/
                
                # Recriar keystore
                openssl pkcs12 -export \
                    -in ssl/unifi/fullchain.pem \
                    -inkey ssl/unifi/privkey.pem \
                    -out ssl/unifi/keystore \
                    -name unifi \
                    -password pass:aircontrolenterprise
                
                chown -R 1000:1000 ssl/unifi
                break
            fi
        done
    fi
    
    # Reprocessar Omada se existir
    if [ -d "ssl/omada" ]; then
        for domain in $(certbot certificates | grep "Certificate Name" | awk '{print $3}'); do
            if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
                cp "/etc/letsencrypt/live/$domain/fullchain.pem" ssl/omada/tls.crt
                cp "/etc/letsencrypt/live/$domain/privkey.pem" ssl/omada/tls.key
                chown -R 1000:1000 ssl/omada
                break
            fi
        done
    fi
    
    # Reiniciar containers
    docker-compose up -d >> /var/log/controllers-renewal.log 2>&1
    echo "[$(date)] Renovação concluída com sucesso" >> /var/log/controllers-renewal.log
else
    # Reiniciar containers mesmo se não houve renovação
    docker-compose up -d >> /var/log/controllers-renewal.log 2>&1
    echo "[$(date)] Nenhum certificado precisou ser renovado" >> /var/log/controllers-renewal.log
fi
EOF

    # Tornar executável
    chmod +x /usr/local/bin/renew-controllers-certs.sh
    
    # Ajustar o caminho no script
    sed -i "s|/opt/controllers|$(pwd)|g" /usr/local/bin/renew-controllers-certs.sh
    
    # Adicionar ao crontab (executa todo dia 1 às 2h da manhã)
    (crontab -l 2>/dev/null | grep -v "renew-controllers-certs"; echo "0 2 1 * * /usr/local/bin/renew-controllers-certs.sh") | crontab -
    
    log "Renovação automática configurada! Logs em: /var/log/controllers-renewal.log"
}

# Criar estrutura de diretórios
create_directories() {
    log "Criando estrutura de diretórios..."
    mkdir -p {data/{unifi-db,unifi-config,omada-data,omada-logs,omada-backups},ssl/{unifi,omada}}
    chown -R 1000:1000 data/ ssl/
}

# Menu principal
main_menu() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      Setup SSL - Controllers        ║${NC}"
    echo -e "${BLUE}║   UniFi Network + Omada Controller   ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Opções disponíveis:${NC}"
    echo "1) Configurar SSL apenas para UniFi"
    echo "2) Configurar SSL apenas para Omada"
    echo "3) Configurar SSL para ambos (UniFi + Omada)"
    echo "4) Apenas configurar renovação automática"
    echo "5) Testar configuração atual"
    echo "6) Sair"
    echo
    read -rp "Escolha uma opção (1-6): " choice
    
    case $choice in
        1)
            read -rp "Domínio para UniFi: " unifi_domain
            read -rp "Email para Let's Encrypt: " email
            setup_unifi "$unifi_domain" "$email"
            setup_renewal
            ;;
        2)
            read -rp "Domínio para Omada: " omada_domain
            read -rp "Email para Let's Encrypt: " email
            setup_omada "$omada_domain" "$email"
            setup_renewal
            ;;
        3)
            read -rp "Domínio para UniFi: " unifi_domain
            read -rp "Domínio para Omada: " omada_domain
            read -rp "Email para Let's Encrypt: " email
            setup_unifi "$unifi_domain" "$email"
            setup_omada "$omada_domain" "$email"
            setup_renewal
            ;;
        4)
            setup_renewal
            ;;
        5)
            test_configuration
            ;;
        6)
            log "Saindo..."
            exit 0
            ;;
        *)
            error "Opção inválida!"
            sleep 2
            main_menu
            ;;
    esac
}

# Testar configuração
test_configuration() {
    log "Testando configuração atual..."
    
    # Verificar se os certificados existem
    if [ -d "ssl/unifi" ] && [ -f "ssl/unifi/keystore" ]; then
        log "✓ Certificados UniFi encontrados"
    else
        warn "✗ Certificados UniFi não encontrados"
    fi
    
    if [ -d "ssl/omada" ] && [ -f "ssl/omada/tls.crt" ]; then
        log "✓ Certificados Omada encontrados"
    else
        warn "✗ Certificados Omada não encontrados"
    fi
    
    # Verificar se os containers estão rodando
    if docker-compose ps | grep -q "Up"; then
        log "✓ Containers estão rodando"
    else
        warn "✗ Containers não estão rodando"
    fi
    
    echo
    read -rp "Pressione Enter para continuar..."
    main_menu
}

# Função principal
main() {
    # Verificações iniciais
    check_root
    check_certbot
    check_docker_compose
    
    # Criar estrutura de diretórios
    create_directories
    
    # Mostrar menu
    main_menu
    
    # Finalizar
    echo
    log "Configuração concluída!"
    log "Para iniciar os containers: docker-compose up -d"
    log "UniFi estará disponível em: https://seu-dominio:8443"
    log "Omada estará disponível em: https://seu-dominio:8043"
}

# Executar função principal
main "$@"