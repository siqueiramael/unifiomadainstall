#!/bin/bash

# backup.sh - Gerenciador de Backup e Restauração para as Controladoras
# v2.0 - Adicionado Agendamento e Retenção de Backups

# --- Cores e Funções de Log ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; C='\033[0;36m'; NC='\033[0m'
log() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
success() { echo -e "${GREEN}[OK] $1${NC}"; }

BACKUP_DIR="./backups"
[ ! -d "$BACKUP_DIR" ] && mkdir -p "$BACKUP_DIR"

# --- Funções do Script ---

do_backup() {
    clear
    echo "Qual controladora você deseja fazer backup?"
    echo "1) UniFi"
    echo "2) Omada"
    echo "3) Ambas (Completo)"
    echo "4) Voltar"
    read -p "Escolha: " choice

    local service_name=""
    local folders_to_backup=""

    case $choice in
        1) service_name="unifi"; folders_to_backup="./data/unifi-db ./data/unifi-config";;
        2) service_name="omada"; folders_to_backup="./data/omada-data ./data/omada-logs";;
        3) service_name="completo"; folders_to_backup="./data";;
        4) return;;
        *) error "Opção inválida!"; return;;
    esac

    local backup_filename="${BACKUP_DIR}/backup-${service_name}-$(date +%F_%H-%M-%S).tar.gz"
    
    log "Iniciando backup de '$service_name' para o arquivo '$backup_filename'..."
    tar -czf "$backup_filename" $folders_to_backup
    
    if [ $? -eq 0 ]; then
        success "Backup criado com sucesso!"
        ls -lh "$backup_filename"
    else
        error "Falha ao criar o backup."
    fi
}

do_restore() {
    clear
    log "Listando backups disponíveis em '$BACKUP_DIR':"
    
    local backups=("$BACKUP_DIR"/*.tar.gz)
    
    if [ ! -f "${backups[0]}" ]; then
        error "Nenhum arquivo de backup (.tar.gz) encontrado em '$BACKUP_DIR'."
        return
    fi
    
    local i=1
    for backup_file in "${backups[@]}"; do
        echo "$i) $(basename "$backup_file")"
        ((i++))
    done
    echo "$i) Cancelar"
    
    read -p "Escolha o número do backup que deseja restaurar: " choice

    if [[ "$choice" -eq $i ]]; then
        warn "Restauração cancelada."; return
    fi

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
        error "Seleção inválida."; return
    fi
    
    local backup_to_restore="${backups[$((choice-1))]}"
    
    echo
    error "ATENÇÃO! ESTA AÇÃO É DESTRUTIVA!"
    warn "Todos os dados atuais das controladoras serão APAGADOS e substituídos pelo conteúdo do backup:"
    warn "$(basename "$backup_to_restore")"
    echo
    read -p "Digite 'RESTAURAR' em maiúsculas para confirmar: " confirm

    if [ "$confirm" != "RESTAURAR" ]; then
        error "Confirmação incorreta. Restauração cancelada."; return
    fi

    log "Iniciando processo de restauração..."

    log "1. Parando todos os contêineres..."
    docker compose down || { error "Falha ao parar os contêineres."; return 1; }
    
    log "2. Removendo dados atuais..."
    if [[ "$backup_to_restore" == *"unifi"* ]]; then rm -rf ./data/unifi-db ./data/unifi-config; fi
    if [[ "$backup_to_restore" == *"omada"* ]]; then rm -rf ./data/omada-data ./data/omada-logs; fi
    if [[ "$backup_to_restore" == *"completo"* ]]; then rm -rf ./data; fi
    success "Dados antigos removidos."

    log "3. Extraindo o backup..."
    tar -xzf "$backup_to_restore" -C . || { error "Falha ao extrair o backup."; return 1; }
    success "Backup extraído."

    log "4. Ajustando permissões dos dados restaurados..."
    sudo chown -R 1000:1000 ./data

    log "5. Iniciando os contêineres com os dados restaurados..."
    docker compose up -d || { error "Falha ao iniciar os contêineres."; return 1; }

    sleep 15
    docker compose ps
    success "Restauração concluída! Verifique se suas controladoras estão funcionando como esperado."
}

# --- NOVA FUNÇÃO DE AGENDAMENTO ---
setup_schedule() {
    clear
    log "Configurando o agendamento de backups automáticos..."
    
    local SCRIPT_PATH="/usr/local/bin/run_controllers_backup.sh"
    local CRON_FILE="/etc/cron.d/controllers_backup"
    local CONTROLLERS_DIR=$(pwd) # Pega o diretório atual, ex: /opt/controllers

    # Cria o script que será executado pelo cron
    log "Criando script de backup diário em '$SCRIPT_PATH'..."
    
    sudo tee "$SCRIPT_PATH" > /dev/null << EOF
#!/bin/bash
# Script para execução diária de backup e rotação (GFS)

BACKUP_DIR="$CONTROLLERS_DIR/backups"
LOG_FILE="$CONTROLLERS_DIR/backups/rotation.log"
DATE_FORMAT=\$(date +%F)
DAY_OF_WEEK=\$(date +%u) # 1=Segunda, 7=Domingo
DAY_OF_MONTH=\$(date +%d)
DAY_OF_YEAR=\$(date +%j) # Dia do ano (1-366)

echo "---[\$(date)]--- Iniciando ciclo de backup e rotação ---" >> \$LOG_FILE

# 1. Cria o backup completo do dia
echo "Criando backup diário..." >> \$LOG_FILE
tar -czf "\$BACKUP_DIR/backup-completo-\$DATE_FORMAT.tar.gz" -C "$CONTROLLERS_DIR" data >> \$LOG_FILE 2>&1

# 2. Lógica de Rotação e Limpeza
echo "Iniciando limpeza de backups antigos..." >> \$LOG_FILE
find "\$BACKUP_DIR" -type f -name 'backup-completo-*.tar.gz' -mtime +7 | while read daily_backup; do
    backup_date=\$(echo "\$daily_backup" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
    
    # Verifica se é o backup de domingo (semanal) ou do dia 1º (mensal)
    day_of_week_of_file=\$(date -d "\$backup_date" +%u)
    day_of_month_of_file=\$(date -d "\$backup_date" +%d)

    # Se NÃO for domingo E NÃO for dia 1º, pode apagar.
    if [[ "\$day_of_week_of_file" -ne 7 && "\$day_of_month_of_file" -ne 1 ]]; then
        echo "Apagando backup diário antigo: \$(basename "\$daily_backup")" >> \$LOG_FILE
        rm "\$daily_backup"
    fi
done

# Apaga backups semanais com mais de 1 mês (mantém os 4 últimos domingos)
find "\$BACKUP_DIR" -type f -name 'backup-completo-*.tar.gz' -mtime +35 | while read weekly_backup; do
    backup_date=\$(echo "\$weekly_backup" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
    day_of_month_of_file=\$(date -d "\$backup_date" +%d)
    
    # Se for um backup semanal (domingo) mas NÃO for do dia 1º, apaga.
    if [[ "\$(date -d "\$backup_date" +%u)" -eq 7 && "\$day_of_month_of_file" -ne 1 ]]; then
        echo "Apagando backup semanal antigo (>35 dias): \$(basename "\$weekly_backup")" >> \$LOG_FILE
        rm "\$weekly_backup"
    fi
done

# Apaga backups mensais com mais de 1 ano
find "\$BACKUP_DIR" -type f -name 'backup-completo-*.tar.gz' -mtime +366 | while read monthly_backup; do
    echo "Apagando backup mensal antigo (>1 ano): \$(basename "\$monthly_backup")" >> \$LOG_FILE
    rm "\$monthly_backup"
done

echo "---[\$(date)]--- Ciclo de rotação finalizado ---" >> \$LOG_FILE
EOF

    sudo chmod +x "$SCRIPT_PATH"
    
    # Cria o arquivo de cron para rodar o script todo dia às 3 da manhã
    log "Criando tarefa agendada em '$CRON_FILE'..."
    sudo tee "$CRON_FILE" > /dev/null << EOF
# Tarefa agendada para backup diário das controladoras UniFi e Omada
# Executa todos os dias às 03:00 da manhã
0 3 * * * root $SCRIPT_PATH
EOF

    success "Agendamento de backup configurado com sucesso!"
    warn "O primeiro backup automático será executado às 3h da manhã."
    warn "Você pode testar o script de rotação rodando: sudo $SCRIPT_PATH"
}


# --- Menu Principal do Script de Backup ---
main_menu() {
    clear
    echo -e "${C}╔════════════════════════════════════════════╗${NC}"
    echo -e "${C}║        GERENCIADOR DE BACKUP E RESTORE     ║${NC}"
    echo -e "${C}╚════════════════════════════════════════════╝${NC}"
    echo
    echo "1) Fazer Backup Agora"
    echo "2) Restaurar um Backup"
    echo "3) Configurar Backups Agendados"
    echo "4) Voltar para o menu principal"
    echo
    read -p "Escolha uma opção: " choice

    case $choice in
        1) do_backup;;
        2) do_restore;;
        3) setup_schedule;;
        4) exit 0;;
        *) error "Opção inválida!";;
    esac
}

# --- Execução ---
# Garante que o script rode como root, pois vai mexer no crontab
if [[ $EUID -ne 0 ]]; then
   error "Este script precisa ser executado com 'sudo' para configurar o agendamento."
   exit 1
fi

while true; do
    main_menu
    read -p "Pressione Enter para continuar..."
done
