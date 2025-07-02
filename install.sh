#!/bin/bash

# Controllers Manager - UniFi & Omada - v6.0 Finalíssima
PROJECT_NAME="controllers"
WORK_DIR="/opt/controllers"
LOG_FILE="/var/log/controllers-install.log"

# Colors
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; C='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log() { echo -e "${G}[$(date '+%H:%M:%S')] $1${NC}"; echo "[$(date)] $1" >> "$LOG_FILE"; }
warn() { echo -e "${Y}[WARN] $1${NC}"; echo "[WARN] $1" >> "$LOG_FILE"; }
error() { echo -e "${R}[ERROR] $1${NC}"; echo "[ERROR] $1" >> "$LOG_FILE"; }
success() { echo -e "${G}[OK] $1${NC}"; echo "[OK] $1" >> "$LOG_FILE"; }


# ===================================================================================
# FUNÇÃO DE SELEÇÃO DE VERSÃO (CORRIGIDA COM REDIRECIONAMENTO DE SAÍDA)
# Todos os 'echos' de menu são enviados para stderr (>&2) para não contaminar a variável.
# ===================================================================================
select_version() {
    local service=$1
    local repo=""
    local choice
    local selected_version=""
    local tmp_file="/tmp/controllers_versions.txt"

    log "Buscando versões online para $service..." >&2

    case $service in
        unifi|UniFi) repo="linuxserver/docker-unifi-network-application" ;;
        omada|Omada) repo="mbentley/docker-omada-controller" ;;
        *) echo "latest"; return ;;
    esac

    set -o pipefail
    curl -s --connect-timeout 10 "https://api.github.com/repos/$repo/tags" | jq -r '.[].name' | grep -v -i -E 'beta|rc|test' | sed 's/^v//' | sort -V -r | head -15 > "$tmp_file"
    local exit_code=$?
    set +o pipefail
    
    local online_versions=()
    if [ $exit_code -eq 0 ] && [ -s "$tmp_file" ]; then
        mapfile -t online_versions < "$tmp_file"
    else
        warn "Falha ao buscar versões online. O menu mostrará apenas 'latest'." >&2
    fi
    rm -f "$tmp_file"

    local final_versions=("latest" "${online_versions[@]}")

    # Menu interativo (saída redirecionada para >&2)
    echo -e "${C}╔══════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${C}║${BOLD}         SELECIONAR VERSÃO - ${service^^}                 ${NC}${C}║${NC}" >&2
    echo -e "${C}╚══════════════════════════════════════════════════════════╝${NC}" >&2
    echo >&2

    local i=1
    for version in "${final_versions[@]}"; do
        echo "$i) $version" >&2
        ((i++))
    done
    echo >&2

    while true; do
        # O prompt do read já vai para stderr por padrão
        read -p "Selecione a versão (1-${#final_versions[@]}): " choice
        if [[ -z "$choice" ]]; then
            selected_version="latest"; break;
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#final_versions[@]} ]; then
            selected_version="${final_versions[$((choice-1))]}"; break;
        else
            error "Opção inválida!" >&2
        fi
    done

    success "Versão escolhida: $selected_version" >&2
    # A ÚNICA SAÍDA DE DADOS PARA STDOUT (o que a variável vai capturar)
    echo "$selected_version"
}

update_docker_compose_versions() {
    local unifi_version=$1
    local omada_version=$2
    
    log "Atualizando docker-compose.yml com versões selecionadas..."
    [ -f "docker-compose.yml" ] && cp docker-compose.yml docker-compose.yml.backup
    
    if [ -n "$unifi_version" ]; then
        log "Definindo UniFi para versão: $unifi_version"
        sed -i "s|image: lscr.io/linuxserver/unifi-network-application:.*|image: lscr.io/linuxserver/unifi-network-application:$unifi_version|g" docker-compose.yml
    fi
    
    if [ -n "$omada_version" ]; then
        log "Definindo Omada para versão: $omada_version"
        sed -i "s|image: mbentley/omada-controller:.*|image: mbentley/omada-controller:$omada_version|g" docker-compose.yml
    fi
    
    success "Docker-compose.yml atualizado com as versões selecionadas"
}

version_selection_menu() {
    local service=$1
    local auto_latest=${2:-false}

    if [ "$auto_latest" = "true" ]; then
        echo "latest"; return 0;
    fi

    # Menu de pergunta (saída redirecionada para >&2)
    echo -e "\n${Y}Deseja selecionar uma versão específica para $service?${NC}" >&2
    echo "1) Sim - Escolher versão" >&2
    echo "2) Não - Usar 'latest'" >&2
    echo >&2

    read -p "Escolha (1-2): " version_choice

    case $version_choice in
        1) select_version "$service" ;;
        *) log "Usando versão 'latest' para $service"; echo "latest" ;;
    esac
}

check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        warn "Executando como root - tome cuidado!"
        if ! groups "$USER" 2>/dev/null | grep -q '\bdocker\b'; then
            log "Adicionando usuário $USER ao grupo docker..."
            usermod -aG docker "$USER" 2>/dev/null || true
        fi
    else
        groups "$USER" | grep -q '\bdocker\b' || { error "Usuário não está no grupo docker"; exit 1; }
    fi
}

install_dependencies() {
    log "Verificando dependências..."
    if [ -f /etc/os-release ]; then . /etc/os-release; OS=$ID; else error "Não foi possível detectar a distribuição"; return 1; fi
    
    local deps_to_install=()
    ! command -v curl &> /dev/null && deps_to_install+=("curl")
    ! command -v jq &> /dev/null && deps_to_install+=("jq")

    if [ ${#deps_to_install[@]} -gt 0 ]; then
        log "Instalando dependências básicas: ${deps_to_install[*]}"
        case $OS in
            ubuntu|debian) sudo apt-get update -qq && sudo apt-get install -y "${deps_to_install[@]}" >/dev/null 2>&1 ;;
            centos|rhel|fedora) sudo yum update -y -q && sudo yum install -y "${deps_to_install[@]}" >/dev/null 2>&1 ;;
        esac
    fi
    
    if ! command -v docker &>/dev/null; then
        log "Instalando Docker..."; curl -fsSL https://get.docker.com | sudo sh >/dev/null 2>&1
        sudo usermod -aG docker "$USER"; warn "Faça logout/login ou execute: newgrp docker"
    fi
    if ! docker compose version &>/dev/null; then
        log "Instalando Docker Compose..."; case $OS in
            ubuntu|debian) sudo apt-get install -y docker-compose-plugin >/dev/null 2>&1 ;;
            centos|rhel|fedora) sudo yum install -y docker-compose-plugin >/dev/null 2>&1 ;;
        esac
    fi
    success "Dependências OK"
}

create_directories() {
    log "Criando estrutura de diretórios...";
    mkdir -p {data/{unifi-db,unifi-config,omada-data,omada-logs,omada-backups},ssl/{unifi,omada},backups}
    sudo chown -R 1000:1000 data/ ssl/ backups/ 2>/dev/null || true
}

#
# ---- DAQUI PARA BAIXO, O RESTO DO SEU SCRIPT PERMANECE IGUAL ----
# Todas as suas funções de menu, backup, logs, etc., foram preservadas.
#

show_menu() {
    clear
    echo -e "${C}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${BOLD}          GERENCIADOR UniFi & Omada Controllers             ${NC}${C}║${NC}"
    echo -e "${C}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${C}║${NC}  1) 🚀 Instalar UniFi Controller                          ${C}║${NC}"
    echo -e "${C}║${NC}  2) 🚀 Instalar Omada Controller                          ${C}║${NC}"
    echo -e "${C}║${NC}  3) 🚀 Instalar Ambos os Controllers                      ${C}║${NC}"
    echo -e "${C}║${NC}  4) 🔒 Configurar SSL                                     ${C}║${NC}"
    echo -e "${C}║${NC}  5) 📊 Status dos Containers                              ${C}║${NC}"
    echo -e "${C}║${NC}  6) 📋 Ver Logs                                           ${C}║${NC}"
    echo -e "${C}║${NC}  7) 🔄 Atualizar                                          ${C}║${NC}"
    echo -e "${C}║${NC}  8) 📦 Gerenciar Versões                                  ${C}║${NC}"
    echo -e "${C}║${NC}  9) 💾 Backup                                             ${C}║${NC}"
    echo -e "${C}║${NC} 10) 🗑️ Remover                                            ${C}║${NC}"
    echo -e "${C}║${NC} 11) 🚪 Sair                                               ${C}║${NC}"
    echo -e "${C}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    if [ -f "docker-compose.yml" ]; then
        local running
        running=$(docker compose ps -q 2>/dev/null | wc -l)
        echo -e "${B}📍 Containers rodando: ${running}${NC}"
        
        local unifi_ver
        unifi_ver=$(grep "unifi-network-application:" docker-compose.yml | cut -d':' -f3 | tr -d ' ')
        local omada_ver
        omada_ver=$(grep "omada-controller:" docker-compose.yml | cut -d':' -f3 | tr -d ' ')
        [ -n "$unifi_ver" ] && echo -e "${B}📦 UniFi: ${unifi_ver}${NC}"
        [ -n "$omada_ver" ] && echo -e "${B}📦 Omada: ${omada_ver}${NC}"
        echo
    fi
}

manage_versions() {
    clear
    echo -e "${C}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${BOLD}                  GERENCIAR VERSÕES                      ${NC}${C}║${NC}"
    echo -e "${C}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "1) Ver versões atuais"
    echo "2) Alterar versão do UniFi"
    echo "3) Alterar versão do Omada"
    echo "4) Voltar ao menu principal"
    echo
    
    read -p "Escolha: " opt
    
    case $opt in
        1)
            echo -e "${Y}=== Versões Atuais ===${NC}"
            if [ -f "docker-compose.yml" ]; then
                local unifi_ver
                unifi_ver=$(grep "unifi-network-application:" docker-compose.yml | cut -d':' -f3 | tr -d ' ')
                local omada_ver
                omada_ver=$(grep "omada-controller:" docker-compose.yml | cut -d':' -f3 | tr -d ' ')
                echo "UniFi: ${unifi_ver:-'não encontrado'}"
                echo "Omada: ${omada_ver:-'não encontrado'}"
            else
                error "docker-compose.yml não encontrado"
            fi
            ;;
        2)
            local new_version
            new_version=$(select_version "UniFi")
            read -p "Confirmar alteração para $new_version? [y/N] " confirm
            [[ "$confirm" =~ [yY] ]] && {
                update_docker_compose_versions "$new_version" ""
                success "Versão do UniFi alterada para: $new_version"
                warn "Execute a opção de 'Instalar' ou 'Atualizar' para aplicar a mudança."
            }
            ;;
        3)
            local new_version
            new_version=$(select_version "Omada")
            read -p "Confirmar alteração para $new_version? [y/N] " confirm
            [[ "$confirm" =~ [yY] ]] && {
                update_docker_compose_versions "" "$new_version"
                success "Versão do Omada alterada para: $new_version"
                warn "Execute a opção de 'Instalar' ou 'Atualizar' para aplicar a mudança."
            }
            ;;
        4) return 0 ;;
        *) error "Opção inválida!" ;;
    esac
    
    [ "$opt" != "4" ] && read -p "Pressione Enter..."
}

install_controllers() {
    local service=$1
    local unifi_version=""
    local omada_version=""
    
    log "Preparando instalação de $service..."
    
    [ ! -f "docker-compose.yml" ] && { error "docker-compose.yml não encontrado!"; return 1; }
    
    case $service in
        "unifi")
            unifi_version=$(version_selection_menu "UniFi")
            ;;
        "omada")
            omada_version=$(version_selection_menu "Omada")
            ;;
        "both")
            echo -e "${C}╔══════════════════════════════════════════════════════════╗${NC}"
            echo -e "${C}║${BOLD}           SELEÇÃO DE VERSÕES - AMBOS CONTROLADORES       ${NC}${C}║${NC}"
            echo -e "${C}╚══════════════════════════════════════════════════════════╝${NC}"
            echo
            echo -e "${Y}=== UniFi Controller ===${NC}"
            unifi_version=$(version_selection_menu "UniFi")
            echo
            echo -e "${Y}=== Omada Controller ===${NC}"
            omada_version=$(version_selection_menu "Omada")
            ;;
    esac
    
    update_docker_compose_versions "$unifi_version" "$omada_version"
    
    install_dependencies || { error "Falha nas dependências"; return 1; }
    create_directories "$service"
    
    log "Parando containers antigos..."
    docker compose down --remove-orphans 2>/dev/null || true
    
    log "Baixando imagens com versões selecionadas..."
    local services_to_action
    case $service in
        "unifi") 
            log "Baixando UniFi versão: $unifi_version"
            services_to_action="unifi-db unifi-network-application"
            ;;
        "omada") 
            log "Baixando Omada versão: $omada_version"
            services_to_action="omada-controller"
            ;;
        "both") 
            log "Baixando UniFi versão: $unifi_version e Omada versão: $omada_version"
            services_to_action=""
            ;;
    esac
    docker compose pull $services_to_action
    
    log "Iniciando containers..."
    case $service in
        "unifi") services_to_action="unifi-db unifi-network-application" ;;
        "omada") services_to_action="omada-controller" ;;
        "both") services_to_action="" ;;
    esac
    docker compose up -d $services_to_action
    
    sleep 15
    
    local failed=()
    case $service in
        "unifi")
            ! docker compose ps unifi-db | grep -q "Up" && failed+=("unifi-db")
            ! docker compose ps unifi-network-application | grep -q "Up" && failed+=("unifi-network-application")
            ;;
        "omada")
            ! docker compose ps omada-controller | grep -q "Up" && failed+=("omada-controller")
            ;;
        "both")
            ! docker compose ps unifi-db | grep -q "Up" && failed+=("unifi-db")
            ! docker compose ps unifi-network-application | grep -q "Up" && failed+=("unifi-network-application")
            ! docker compose ps omada-controller | grep -q "Up" && failed+=("omada-controller")
            ;;
    esac
    
    if [ ${#failed[@]} -gt 0 ]; then
        error "Containers falharam: ${failed[*]}"
        return 1
    fi
    
    success "Instalação de $service concluída!"
    
    echo
    echo -e "${C}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${BOLD}                   VERSÕES INSTALADAS                    ${NC}${C}║${NC}"
    echo -e "${C}╠══════════════════════════════════════════════════════════╣${NC}"
    [ -n "$unifi_version" ] && printf "${C}║${NC} ${G}UniFi:${NC} %-48s ${C}║${NC}\n" "$unifi_version"
    [ -n "$omada_version" ] && printf "${C}║${NC} ${G}Omada:${NC} %-48s ${C}║${NC}\n" "$omada_version"
    echo -e "${C}╚══════════════════════════════════════════════════════════╝${NC}"
    
    show_access_info "$service"
}

show_access_info() {
    local service=$1
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    
    echo
    echo -e "${C}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${BOLD}                 INFORMAÇÕES DE ACESSO                   ${NC}${C}║${NC}"
    echo -e "${C}╠══════════════════════════════════════════════════════════╣${NC}"
    
    case $service in
        "unifi"|"both")
            printf "${C}║${NC} ${G}UniFi:${NC} https://%-37s ${C}║${NC}\n" "${server_ip}:8443"
            ;;
    esac
    
    case $service in
        "omada"|"both")
            printf "${C}║${NC} ${G}Omada:${NC} https://%-37s ${C}║${NC}\n" "${server_ip}:8043"
            ;;
    esac
    
    echo -e "${C}║${NC} Configure no primeiro acesso                             ${C}║${NC}"
    echo -e "${C}╚══════════════════════════════════════════════════════════╝${NC}"
}

check_status() {
    clear
    echo -e "${C}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${BOLD}                   STATUS DOS CONTAINERS                 ${NC}${C}║${NC}"
    echo -e "${C}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    
    if ! docker compose ps &>/dev/null; then
        error "Nenhum container encontrado"
        read -p "Pressione Enter..."
        return 1
    fi
    
    echo -e "${Y}=== Containers ===${NC}"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    echo -e "${Y}=== Recursos ===${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker compose ps -q) 2>/dev/null || echo "Nenhum container rodando"
    
    echo
    echo -e "${Y}=== Espaço em Disco ===${NC}"
    df -h . | tail -1
    du -sh data/* 2>/dev/null || echo "Sem dados"
    
    read -p "Pressione Enter..."
}

show_logs() {
    clear
    echo -e "${C}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${BOLD}                      LOGS DISPONÍVEIS                   ${NC}${C}║${NC}"
    echo -e "${C}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "1) UniFi Application"
    echo "2) UniFi Database"
    echo "3) Omada Controller"
    echo "4) Todos os containers"
    echo "5) Logs em tempo real"
    echo "6) Voltar"
    echo
    
    read -p "Escolha: " opt
    
    case $opt in
        1) docker compose logs --tail=50 unifi-network-application 2>/dev/null || warn "Container não encontrado" ;;
        2) docker compose logs --tail=50 unifi-db 2>/dev/null || warn "Container não encontrado" ;;
        3) docker compose logs --tail=50 omada-controller 2>/dev/null || warn "Container não encontrado" ;;
        4) docker compose logs --tail=30 ;;
        5) echo -e "${Y}Logs em tempo real (Ctrl+C para sair)${NC}"; docker compose logs -f ;;
        6) return 0 ;;
        *) error "Opção inválida!" ;;
    esac
    
    [ "$opt" != "6" ] && read -p "Pressione Enter..."
}

update_menu() {
    clear
    echo -e "${C}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${BOLD}                 ATUALIZAR CONTROLADORAS                 ${NC}${C}║${NC}"
    echo -e "${C}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "1) Atualizar UniFi"
    echo "2) Atualizar Omada"
    echo "3) Atualizar tudo"
    echo "4) Voltar"
    echo
    
    read -p "Escolha: " opt
    
    if [ ! -f "update-containers.sh" ]; then
        error "update-containers.sh não encontrado!"
        read -p "Pressione Enter..."
        return 1
    fi
    
    case $opt in
        1) ./update-containers.sh unifi ;;
        2) ./update-containers.sh omada ;;
        3) ./update-containers.sh all ;;
        4) return 0 ;;
        *) error "Opção inválida!" ;;
    esac
    
    [ "$opt" != "4" ] && read -p "Pressione Enter..."
}

create_backup() {
    local backup_name="controllers-backup-$(date +%Y%m%d_%H%M%S)"
    local backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    
    log "Criando backup..."
    mkdir -p "$backup_dir"
    
    [ -d "data" ] && { tar -czf "$backup_dir/data-backup.tar.gz" -C . data/; success "Backup dos dados criado"; }
    [ -d "ssl" ] && { tar -czf "$backup_dir/ssl-backup.tar.gz" -C . ssl/; success "Backup SSL criado"; }
    
    cp docker-compose.yml "$backup_dir/" 2>/dev/null || true
    cp setup-ssl.sh "$backup_dir/" 2>/dev/null || true
    cp update-containers.sh "$backup_dir/" 2>/dev/null || true
    
    cat > "$backup_dir/backup-info.txt" << EOF
Backup: $(date)
Sistema: $(uname -a)
Usuário: $(whoami)
Containers: $(docker compose ps --format "{{.Name}}" | tr '\n' ' ')
EOF
    
    tar -czf "${backup_name}.tar.gz" -C backups "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    success "Backup: ${backup_name}.tar.gz"
    read -p "Pressione Enter..."
}

remove_menu() {
    clear
    echo -e "${R}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${R}║${BOLD}                     REMOVER CONTAINERS                  ${NC}${R}║${NC}"
    echo -e "${R}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "1) Parar containers"
    echo "2) Remover UniFi"
    echo "3) Remover Omada"
    echo "4) Remover tudo (containers + dados)"
    echo "5) Limpeza do sistema"
    echo "6) Voltar"
    echo
    
    read -p "Escolha: " opt
    
    case $opt in
        1)
            warn "Parando todos os containers..."
            docker compose down
            success "Containers parados"
            ;;
        2)
            warn "Removendo UniFi..."
            read -p "Confirma? (y/N): " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] && {
                docker compose stop unifi-db unifi-network-application
                docker compose rm -f unifi-db unifi-network-application
                success "UniFi removido"
            }
            ;;
        3)
            warn "Removendo Omada..."
            read -p "Confirma? (y/N): " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] && {
                docker compose stop omada-controller
                docker compose rm -f omada-controller
                success "Omada removido"
            }
            ;;
        4)
            error "ATENÇÃO: Isso remove TUDO!"
            read -p "Digite 'DELETE' para confirmar: " confirm
            [ "$confirm" = "DELETE" ] && {
                docker compose down -v --remove-orphans
                docker system prune -af --volumes
                rm -rf data/ ssl/ backups/
                success "Tudo removido"
            }
            ;;
        5)
            log "Limpando sistema..."
            docker system prune -f
            docker image prune -af
            success "Limpeza concluída"
            ;;
        6) return 0 ;;
        *) error "Opção inválida!" ;;
    esac
    
    [ "$opt" != "6" ] && read -p "Pressione Enter..."
}

configure_ssl() {
    log "Configurando SSL..."
    
    if [ ! -f "setup-ssl.sh" ]; then
        error "setup-ssl.sh não encontrado!"
        read -p "Pressione Enter..."
        return 1
    fi
    
    chmod +x setup-ssl.sh
    sudo ./setup-ssl.sh
    read -p "Pressione Enter..."
}

main() {
    # Garante que o script rode a partir do seu próprio diretório
    cd "$(dirname "$0")" || { error "Não foi possível entrar no diretório do script: $(dirname "$0")"; exit 1; }
    
    # Define o WORK_DIR para o diretório atual onde o script está
    WORK_DIR=$(pwd)
    
    check_privileges
    
    while true; do
        show_menu
        read -p "Escolha uma opção: " choice
        
        case $choice in
            1) install_controllers "unifi"; read -p "Pressione Enter..." ;;
            2) install_controllers "omada"; read -p "Pressione Enter..." ;;
            3) install_controllers "both"; read -p "Pressione Enter..." ;;
            4) configure_ssl ;;
            5) check_status ;;
            6) show_logs ;;
            7) update_menu ;;
            8) manage_versions ;;
            9) create_backup ;;
            10) remove_menu ;;
            11) log "Saindo..."; exit 0 ;;
            *) error "Opção inválida!"; sleep 1 ;;
        esac
    done
}

main "$@"
