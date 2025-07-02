#!/bin/bash

# Script para atualizar containers UniFi e Omada
# Uso: ./update-containers.sh [unifi|omada|all]

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Função para fazer backup antes da atualização
backup_data() {
    local service=$1
    local backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    
    log "Criando backup de $service..."
    mkdir -p "$backup_dir"
    
    case $service in
        "unifi")
            if [ -d "data/unifi-config" ]; then
                tar -czf "$backup_dir/unifi-config-backup.tar.gz" -C data unifi-config
                log "Backup UniFi criado: $backup_dir/unifi-config-backup.tar.gz"
            fi
            ;;
        "omada")
            if [ -d "data/omada-data" ]; then
                tar -czf "$backup_dir/omada-data-backup.tar.gz" -C data omada-data
                log "Backup Omada criado: $backup_dir/omada-data-backup.tar.gz"
            fi
            ;;
    esac
}

check_current_version() {
    local service=$1
    case $service in
        "unifi-network-application")
            grep "unifi-network-application:" docker-compose.yml | cut -d':' -f3
            ;;
        "omada-controller")
            grep "omada-controller:" docker-compose.yml | cut -d':' -f3
            ;;
    esac
}

# Função para atualizar um serviço específico
update_service() {
    local service=$1
    local current_version=$(check_current_version "$service")
    
    info "Atualizando $service (versão atual: ${current_version:-'latest'})..."
    
    # Fazer backup
    backup_data "$service"
    
    # Parar o serviço
    log "Parando $service..."
    docker compose stop "$service"
    
    # Remover container antigo
    log "Removendo container antigo..."
    docker compose rm -f "$service"
    
    # Baixar nova imagem
    log "Baixando nova imagem..."
    docker compose pull "$service"
    
    # Iniciar com nova imagem
    log "Iniciando $service com nova imagem..."
    docker compose up -d "$service"
    
    # Aguardar inicialização
    log "Aguardando inicialização..."
    sleep 30
    
    # Verificar se está rodando
    if docker compose ps "$service" | grep -q "Up"; then
        log "✓ $service atualizado e rodando com sucesso!"
    else
        error "✗ Falha ao inicializar $service após atualização"
        return 1
    fi
}

# Função para verificar updates disponíveis
check_updates() {
    log "Verificando atualizações disponíveis..."
    
    # Puxar informações das imagens
    docker compose pull --dry-run 2>/dev/null || {
        log "Verificando manualmente..."
        docker compose config --services | while read service; do
            image=$(docker compose config | grep -A 5 "$service:" | grep "image:" | awk '{print $2}')
            if [ -n "$image" ]; then
                info "Verificando $service ($image)..."
                docker pull "$image" > /dev/null 2>&1
            fi
        done
    }
    
    log "Verificação concluída. Execute com parâmetro para atualizar."
}

# Função para limpeza de imagens antigas
cleanup_images() {
    log "Limpando imagens antigas..."
    docker image prune -f
    docker system prune -f --volumes=false
    log "Limpeza concluída!"
}

# Função para mostrar status dos containers
show_status() {
    info "Status atual dos containers:"
    echo
    docker compose ps
    echo
    
    info "Uso de recursos:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
}

# Função principal
main() {
    local action=${1:-"help"}
    
    case $action in
        "unifi")
            update_service "unifi-network-application"
            ;;
        "omada")
            update_service "omada-controller"
            ;;
        "all")
            info "Atualizando todos os containers..."
            update_service "unifi-db"
            update_service "unifi-network-application"
            update_service "omada-controller"
            cleanup_images
            ;;
        "check")
            check_updates
            ;;
        "status")
            show_status
            ;;
        "backup")
            backup_data "unifi"
            backup_data "omada"
            ;;
        "cleanup")
            cleanup_images
            ;;
        "help"|*)
            echo -e "${BLUE}Script de Atualização - Controllers${NC}"
            echo
            echo "Uso: $0 [opção]"
            echo
            echo "Opções:"
            echo "  unifi     - Atualiza apenas o UniFi Network Application"
            echo "  omada     - Atualiza apenas o Omada Controller"
            echo "  all       - Atualiza todos os containers"
            echo "  check     - Verifica atualizações disponíveis"
            echo "  status    - Mostra status atual dos containers"
            echo "  backup    - Faz backup dos dados"
            echo "  cleanup   - Remove imagens antigas não utilizadas"
            echo "  help      - Mostra esta ajuda"
            echo
            echo "Exemplos:"
            echo "  $0 check          # Verificar updates"
            echo "  $0 unifi          # Atualizar só UniFi"
            echo "  $0 all            # Atualizar tudo"
            ;;
    esac
}

# Verificar se docker-compose existe
if ! command -v docker compose &> /dev/null && ! command -v docker &> /dev/null; then
    error "Docker Compose não encontrado!"
    exit 1
fi

# Verificar se está no diretório correto
if [ ! -f "docker-compose.yml" ]; then
    error "docker-compose.yml não encontrado no diretório atual!"
    exit 1
fi

# Executar função principal
main "$@"