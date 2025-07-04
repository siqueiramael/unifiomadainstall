# 🚀 Gerenciador de Controladoras UniFi & Omada

Este projeto fornece um conjunto de scripts para instalar, gerenciar e manter as controladoras **UniFi Network** e **Omada TP-Link** de forma automatizada e lado a lado em um único servidor usando Docker.

A solução foi criada para ser simples e robusta, ideal para técnicos, administradores de redes e entusiastas que precisam de uma forma rápida e confiável de gerenciar ambas as plataformas.


---

## ✨ Funcionalidades Principais

* **🚀 Instalação Automatizada:** Instale as controladoras UniFi, Omada ou ambas com um único comando.
* **🔧 Seleção de Versão Interativa:** Escolha versões específicas das controladoras para garantir compatibilidade com backups antigos.
* **🔒 Configuração de SSL Inteligente:** Um script dedicado que gera e instala certificados SSL gratuitos da Let's Encrypt, parando e reiniciando automaticamente serviços conflitantes como Apache ou Nginx.
* **🤖 Automação de SSL para UniFi:** O certificado SSL é instalado e importado no UniFi de forma 100% automática.
* **🚪 Acesso Limpo (Proxy Reverso):** Instruções detalhadas para configurar o Apache como proxy reverso, permitindo o acesso via `https://unifi.seusite.com` e `https://omada.seusite.com`, sem a necessidade de portas.
* **💾 Sistema de Backup Local:** Ferramentas para criar, restaurar e agendar backups locais com política de retenção automática (diária, semanal e mensal).
* **🐳 Baseado em Docker:** Toda a solução é containerizada, garantindo isolamento, portabilidade e um ambiente limpo.

---

## 📋 Índice

* [Pré-requisitos](#-pré-requisitos)
* [Estrutura dos Arquivos](#-estrutura-dos-arquivos)
* [Instalação Rápida](#-instalação-rápida)
* [Como Usar o Gerenciador](#-como-usar-o-gerenciador-installsh)
* [Configurando o SSL com Domínio (HTTPS)](#-configurando-o-ssl-com-domínio-https)
* [Opcional: Acesso Sem Portas (Proxy Reverso com Apache)](#-opcional-acesso-sem-portas-proxy-reverso-com-apache)
* [Backup e Restauração](#-backup-e-restauração)
* [Outras Ferramentas](#-outras-ferramentas)
* [Solução de Problemas (FAQ)](#-solução-de-problemas-faq)

---

## ⚠️ Pré-requisitos

1.  **Servidor ou VPS:** Com **Ubuntu 20.04 / 22.04** ou **Debian 11 / 12**.
2.  **Acesso Root ou Sudo:** Para instalar dependências e gerenciar serviços.
3.  **Domínios Apontados:** Para usar SSL e o Proxy Reverso, você precisará de domínios com registros DNS do tipo `A` apontando para o IP do seu servidor.

---

## 🗂️ Estrutura dos Arquivos

O projeto é composto por 5 arquivos principais:

* `install.sh`: O script principal, seu painel de controle para todas as operações.
* `docker-compose.yml`: A "receita" do Docker para criar as controladoras.
* `update-containers.sh`: Script auxiliar para atualizar as imagens dos contêineres.
* `setup-ssl.sh`: Script inteligente para configurar os certificados de segurança (HTTPS).
* `backup.sh`: O novo gerenciador de backups e restaurações locais.

---

## 🚀 Instalação Rápida

1.  **Clone o Repositório:**
    ```bash
    sudo apt update && sudo apt install -y git
    cd /opt
    sudo git clone [https://github.com/siqueiramael/unifiomadainstall.git](https://github.com/siqueiramael/unifiomadainstall.git) controllers
    cd controllers
    ```
2.  **Dê Permissão de Execução:**
    ```bash
    chmod +x *.sh
    ```
3.  **Execute o Gerenciador Principal:**
    ```bash
    sudo ./install.sh
    ```
    Siga as opções do menu para instalar as controladoras desejadas.

---

## 🛠️ Como Usar o Gerenciador (`install.sh`)

O menu principal centraliza todas as ações importantes.

| Opção | Descrição |
| :--- | :--- |
| **1-3) Instalar Controller(s)** | Instala UniFi, Omada ou ambos, com seleção de versão. |
| **4) Configurar SSL** | Executa o `setup-ssl.sh` para gerar e instalar certificados HTTPS. |
| **5) Status dos Containers** | Mostra o status e uso de recursos dos contêineres. |
| **6) Ver Logs** | Permite visualizar os logs dos contêineres. |
| **7) Atualizar** | Executa `update-containers.sh` para atualizar as imagens. |
| **8) Gerenciar Versões**| Permite alterar a versão de uma controladora antes de uma instalação/atualização. |
| **9) Backup** | **NOVO:** Abre o menu do `backup.sh` para criar, restaurar ou agendar backups. |
| **10) Remover** | Oferece opções para parar ou remover completamente a instalação. |
| **11) Sair** | Encerra o script. |

---

## 🔒 Configurando o SSL com Domínio (HTTPS)

O script `setup-ssl.sh` automatiza a maior parte do processo.
1.  Execute `sudo ./install.sh` e escolha a opção **4) Configurar SSL**.
2.  O script irá detectar e parar/reiniciar serviços conflitantes (Apache/Nginx) automaticamente.
3.  **Para o UniFi:** A importação do certificado é **100% automática**.
4.  **Para o Omada:** A importação é **manual**. O script exibirá os caminhos dos arquivos (`fullchain.pem` e `privkey.pem`) para você fazer o upload na interface web do Omada.

---

## 🚪 Opcional: Acesso Sem Portas (Proxy Reverso com Apache)

Para acessar suas controladoras usando apenas o domínio (ex: `https://unifi.seusite.com`), sem digitar a porta, você pode configurar o Apache como um Proxy Reverso.

**Este guia assume que você já tem o Apache instalado** (`sudo apt install apache2`).

#### Passo 1: Ativar os Módulos do Apache
```bash
sudo a2enmod proxy proxy_http proxy_wstunnel ssl rewrite
```

#### Passo 2: Criar os Arquivos de Configuração
Crie os arquivos de configuração do Apache em `/etc/apache2/sites-available/` para cada domínio, substituindo `seu-dominio.com` pelo seu domínio real.

* **Arquivo `unifi.conf`:**
    ```apache
    <VirtualHost *:80>
        ServerName unifi.seu-dominio.com
        Redirect permanent / [https://unifi.seu-dominio.com/](https://unifi.seu-dominio.com/)
    </VirtualHost>
    <IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName unifi.seu-dominio.com
        SSLEngine on
        SSLCertificateFile /etc/letsencrypt/live/[unifi.seu-dominio.com/fullchain.pem](https://unifi.seu-dominio.com/fullchain.pem)
        SSLCertificateKeyFile /etc/letsencrypt/live/[unifi.seu-dominio.com/privkey.pem](https://unifi.seu-dominio.com/privkey.pem)
        SSLProxyEngine On
        SSLProxyVerify none
        SSLProxyCheckPeerCN off
        ProxyPreserveHost On
        ProxyRequests Off
        RewriteEngine On
        RewriteCond %{HTTP:Upgrade} =websocket [NC]
        RewriteRule /(.*) wss://127.0.0.1:8443/$1 [P,L]
        ProxyPass / [https://127.0.0.1:8443/](https://127.0.0.1:8443/)
        ProxyPassReverse / [https://127.0.0.1:8443/](https://127.0.0.1:8443/)
    </VirtualHost>
    </IfModule>
    ```

* **Arquivo `omada.conf`:**
    ```apache
    <VirtualHost *:80>
        ServerName omada.seu-dominio.com
        Redirect permanent / [https://omada.seu-dominio.com/](https://omada.seu-dominio.com/)
    </VirtualHost>
    <IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName omada.seu-dominio.com
        SSLEngine on
        SSLCertificateFile /etc/letsencrypt/live/[omada.seu-dominio.com/fullchain.pem](https://omada.seu-dominio.com/fullchain.pem)
        SSLCertificateKeyFile /etc/letsencrypt/live/[omada.seu-dominio.com/privkey.pem](https://omada.seu-dominio.com/privkey.pem)
        SSLProxyEngine On
        SSLProxyVerify none
        SSLProxyCheckPeerCN off
        ProxyPreserveHost On
        ProxyRequests Off
        ProxyPass / [https://127.0.0.1:8043/](https://127.0.0.1:8043/)
        ProxyPassReverse / [https://127.0.0.1:8043/](https://127.0.0.1:8043/)
    </VirtualHost>
    </IfModule>
    ```

#### Passo 3: Ativar as Configurações
```bash
sudo a2ensite unifi.conf omada.conf
sudo apache2ctl configtest
sudo systemctl restart apache2
```

---

## 💾 Backup e Restauração

Use a **Opção 9** do menu principal para acessar o novo gerenciador de backups (`backup.sh`).

* **Fazer Backup Agora:** Cria um backup instantâneo (completo, do UniFi ou do Omada) na pasta `./backups`. O nome do arquivo segue o padrão `backup-serviço-dd-mm-aaaa_HH-MM-SS.tar.gz`.
* **Restaurar um Backup:** Lista os backups disponíveis e restaura o selecionado. **Atenção:** este processo apaga os dados atuais da controladora correspondente antes de restaurar.
* **Configurar Backups Agendados:** Cria uma tarefa agendada (`cron job`) que roda um script diariamente às 3h da manhã para:
    1.  Criar um backup completo de todos os dados.
    2.  Fazer a rotação dos backups antigos, mantendo os últimos 7 diários, o último de cada semana (dos últimos 35 dias) e o primeiro de cada mês (do último ano). Isso economiza espaço de forma inteligente.

---

## 🔧 Outras Ferramentas

### ⚫ Atualizando as Controladoras
A opção **7) Atualizar** do menu principal utiliza o script `update-containers.sh` para baixar as versões mais recentes das imagens Docker com a tag que estiver configurada no seu `docker-compose.yml`. Para fazer um upgrade/downgrade controlado para uma versão específica, utilize a **Opção 8) Gerenciar Versões** antes.

---

## 🤔 Solução de Problemas (FAQ)

**1. Meu servidor está com 100% de CPU após instalar o Omada!**
* **Calma, isso é normal!** Na primeira vez que o Omada inicia, ele gera chaves de segurança. Este processo é intensivo e pode demorar de 15 a 30 minutos. A carga da CPU irá se estabilizar sozinha.

**2. Instalei uma controladora e a outra parou de funcionar.**
* Isso acontece porque a instalação foca em um serviço. A solução é simples:
    1.  Pare tudo: `docker compose down`
    2.  Inicie tudo junto: `docker compose up -d`

**3. O menu de seleção de versão não aparece.**
* Isso indica que o script não conseguiu se conectar à API do GitHub. Verifique a conexão de internet da sua VPS. O script continuará de forma segura usando a versão `latest`.
```
