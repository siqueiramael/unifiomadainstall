# 🚀 Gerenciador de Controladoras UniFi & Omada

Este projeto fornece um conjunto de scripts para instalar, gerenciar e manter as controladoras **UniFi Network** e **Omada TP-Link** de forma automatizada e lado a lado em um único servidor usando Docker.

A solução foi criada para ser simples e robusta, ideal para técnicos, administradores de redes e entusiastas que precisam de uma forma rápida e confiável de gerenciar ambas as plataformas sem conflitos de porta ou dependências.

![Exemplo do Menu Principal](https://i.imgur.com/G5g2mJc.png)

---

## ✨ Funcionalidades Principais

* **🚀 Instalação Automatizada:** Instale as controladoras UniFi, Omada ou ambas com um único comando.
* **🔧 Seleção de Versão Interativa:** Escolha versões específicas das controladoras para garantir compatibilidade com backups antigos ou para evitar atualizações indesejadas.
* **🔒 Configuração de SSL Inteligente:** Um script dedicado que gera e instala certificados SSL gratuitos da Let's Encrypt, parando e reiniciando automaticamente serviços conflitantes como Apache ou Nginx.
* **🤖 Automação Completa para UniFi:** O certificado SSL é instalado e importado no UniFi de forma 100% automática.
* **💾 Backup e Gerenciamento:** Ferramentas integradas para fazer backup dos dados, verificar status, ver logs e remover os serviços de forma controlada.
* **🐳 Baseado em Docker:** Toda a solução é containerizada, garantindo isolamento, portabilidade e um ambiente limpo no seu servidor.

---

## 📋 Índice

* [Pré-requisitos](#-pré-requisitos)
* [Estrutura dos Arquivos](#-estrutura-dos-arquivos)
* [Instalação Rápida](#-instalação-rápida)
* [Como Usar o Gerenciador](#-como-usar-o-gerenciador-installsh)
* [Outras Ferramentas](#-outras-ferramentas)
    * [Atualizando as Controladoras](#-atualizando-as-controladoras)
    * [Configurando o SSL com Domínio (HTTPS)](#-configurando-o-ssl-com-domínio-https)
* [Solução de Problemas (FAQ)](#-solução-de-problemas-faq)

---

## ⚠️ Pré-requisitos

Antes de começar, garanta que você tenha:

1.  **Um Servidor ou VPS:** Com sistema operacional **Ubuntu 20.04 / 22.04** ou **Debian 11 / 12**.
2.  **Acesso Root ou Sudo:** Para instalar dependências como Docker e Certbot.
3.  **Domínios Apontados:** Um ou dois nomes de domínio/subdomínio apontando (com registros DNS do tipo `A`) para o endereço IP do seu servidor. Ex: `unifi.meudominio.com` e `omada.meudominio.com`.

---

## 🗂️ Estrutura dos Arquivos

O projeto é composto por 4 arquivos principais:

* `install.sh`: O script principal, seu painel de controle para todas as operações.
* `docker-compose.yml`: O arquivo "receita" que diz ao Docker como criar e configurar os contêineres das controladoras.
* `update-containers.sh`: Um script auxiliar para fazer o backup e a atualização das imagens dos contêineres.
* `setup-ssl.sh`: O script auxiliar **inteligente** para configurar os certificados de segurança (HTTPS).

---

## 🚀 Instalação Rápida

Siga estes passos para colocar tudo no ar a partir de um servidor limpo.

**1. Clone o Repositório**

Acesse seu servidor via SSH e clone este repositório para o diretório `/opt/controllers`.

```bash
sudo apt update && sudo apt install -y git # Garante que o git está instalado
cd /opt
sudo git clone https://github.com/siqueiramael/unifiomadainstall.git controllers
cd controllers
```

**2. Dê Permissão de Execução aos Scripts**

```bash
chmod +x *.sh
```

**3. Execute o Gerenciador Principal**

Inicie o gerenciador. Ele guiará você por todo o processo.

```bash
sudo ./install.sh
```

Na primeira execução, o script irá instalar dependências necessárias. Depois, basta escolher a opção de instalação desejada no menu.

---

## 🛠️ Como Usar o Gerenciador (`install.sh`)

O menu principal é o seu ponto de partida para todas as ações.

| Opção | Descrição |
| :--- | :--- |
| **1-3) Instalar Controller(s)** | Inicia a instalação do UniFi, Omada ou ambos. Permite escolher uma versão específica ou usar a mais recente (`latest`). |
| **4) Configurar SSL** | Executa o script `setup-ssl.sh` para gerar e instalar certificados HTTPS para seus domínios. |
| **5) Status dos Containers** | Mostra quais contêineres estão rodando e o uso de recursos (CPU/Memória). |
| **6) Ver Logs** | Permite visualizar os logs em tempo real ou recentes de cada contêiner. |
| **7) Atualizar** | Executa o script `update-containers.sh` para atualizar as imagens dos contêineres. |
| **8) Gerenciar Versões**| Permite alterar a versão de uma controladora no `docker-compose.yml` sem reinstalar. |
| **9) Backup** | Cria um arquivo de backup `.tar.gz` contendo todos os dados e configurações. |
| **10) Remover** | Oferece opções para parar ou remover completamente a instalação (incluindo dados). |
| **11) Sair** | Encerra o script. |

---

## 🔧 Outras Ferramentas

### ⚫ Atualizando as Controladoras

A atualização pode ser feita de duas maneiras, dependendo do seu objetivo.

#### Cenário 1: Atualizar para a Versão Mais Recente (`latest`)

Se você instalou usando a tag `latest`, basta usar esta opção para buscar a imagem mais recente disponível.
1.  No menu principal, escolha a opção **7) Atualizar**.
2.  Selecione a controladora que deseja atualizar.

#### Cenário 2: Instalar uma Versão Específica (Upgrade/Downgrade)

Este método é ideal quando você precisa instalar uma versão exata (ex: para restaurar um backup).
1.  **Passo 1: Definir a Versão:** No menu, escolha a opção **8) Gerenciar Versões**. Escolha a controladora e a versão desejada na lista online.
2.  **Passo 2: Aplicar a Versão:** Volte ao menu e escolha a opção de **Instalar** correspondente (ex: **1) Instalar UniFi Controller**). O script irá baixar e recriar o contêiner com a versão que você acabou de definir.

### 🔒 Configurando o SSL com Domínio (HTTPS)

O script `setup-ssl.sh` automatiza a maior parte do processo.

**Como funciona:**
1.  Execute `sudo ./install.sh` e escolha a opção **4) Configurar SSL**.
2.  O script irá verificar se a porta 80 está em uso por serviços como Apache ou Nginx. Se estiver, ele irá pará-los temporariamente.
3.  Ele irá gerar os certificados usando o Let's Encrypt.
4.  **Para o UniFi:** A importação do certificado é **100% automática**.
5.  **Para o Omada:** A importação é **manual**. Ao final, o script exibirá uma mensagem com os caminhos dos arquivos que você precisa usar na interface web do Omada (`Configurações > Controladora > Certificado HTTPS`).
6.  Ao final, o script reinicia automaticamente os serviços que ele parou.

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
