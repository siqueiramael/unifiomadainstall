# 🚀 Gerenciador de Controladoras UniFi & Omada

Este projeto fornece um conjunto de scripts para instalar, gerenciar e manter as controladoras **UniFi Network** e **Omada TP-Link** de forma automatizada e lado a lado em um único servidor usando Docker.

A solução foi criada para ser simples e robusta, ideal para técnicos, administradores de redes e entusiastas que precisam de uma forma rápida e confiável de gerenciar ambas as plataformas sem conflitos de porta ou dependências.

![Exemplo do Menu Principal](https://i.imgur.com/G5g2mJc.png)

---

## ✨ Funcionalidades Principais

* **🚀 Instalação Automatizada:** Instale as controladoras UniFi, Omada ou ambas com um único comando.
* **🔧 Seleção de Versão Interativa:** Escolha versões específicas das controladoras para garantir compatibilidade com backups antigos ou para evitar atualizações indesejadas.
* **🔒 Configuração de SSL Simplificada:** Um script dedicado para gerar e instalar certificados SSL gratuitos da Let's Encrypt para seus domínios.
* **🔄 Renovação Automática de SSL:** Configura automaticamente um `cron job` para renovar seus certificados, garantindo que seus painéis estejam sempre seguros.
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
    * [Configurando o SSL com Domínio](#-configurando-o-ssl-com-domínio-setup-sslsh)
* [Solução de Problemas (FAQ)](#-solução-de-problemas-faq)

---

## ⚠️ Pré-requisitos

Antes de começar, garanta que você tenha:

1.  **Um Servidor ou VPS:** Com sistema operacional **Ubuntu 20.04 / 22.04** ou **Debian 11 / 12**.
2.  **Acesso Root ou Sudo:** Para instalar dependências como Docker e Certbot.
3.  **(Opcional, para SSL) Domínios:** Um ou dois nomes de domínio/subdomínio apontando (com registros DNS do tipo `A`) para o endereço IP do seu servidor. Ex: `unifi.meudominio.com` e `omada.meudominio.com`.

---

## 🗂️ Estrutura dos Arquivos

O projeto é composto por 4 arquivos principais:

* `install.sh`: O script principal, seu painel de controle para todas as operações.
* `docker-compose.yml`: O arquivo "receita" que diz ao Docker como criar e configurar os contêineres das controladoras.
* `update-containers.sh`: Um script auxiliar para fazer o backup e a atualização das imagens dos contêineres.
* `setup-ssl.sh`: O script auxiliar para configurar os certificados de segurança (HTTPS).

---

## 🚀 Instalação Rápida

Siga estes passos para colocar tudo no ar.

**1. Clone o Repositório**

Primeiro, acesse seu servidor via SSH e clone este repositório para um diretório de sua preferência (recomendado: `/opt/controllers`).

```bash
sudo apt update && sudo apt install -y git # Garante que o git está instalado
cd /opt
sudo git clone <URL_DO_SEU_REPOSITORIO_GIT> controllers
cd controllers
```

**2. Dê Permissão de Execução aos Scripts**

Torne os scripts executáveis com o seguinte comando:

```bash
chmod +x *.sh
```

**3. Execute o Gerenciador Principal**

Agora, basta iniciar o gerenciador. Ele irá guiar você por todo o processo.

```bash
sudo ./install.sh
```

Na primeira execução, o script irá verificar e instalar automaticamente as dependências necessárias, como Docker, Docker Compose e JQ. Depois, você verá o menu principal.

---

## 🛠️ Como Usar o Gerenciador (`install.sh`)

O menu principal é o seu ponto de partida para todas as ações.

| Opção | Descrição |
| :--- | :--- |
| **1) Instalar UniFi Controller** | Inicia a instalação apenas do UniFi. Você poderá escolher uma versão específica ou usar a mais recente (`latest`). |
| **2) Instalar Omada Controller** | Inicia a instalação apenas do Omada. Você também poderá escolher a versão. |
| **3) Instalar Ambos** | Instala as duas controladoras de uma vez, permitindo escolher a versão para cada uma. |
| **4) Configurar SSL** | Executa o script `setup-ssl.sh` para gerar certificados HTTPS para seus domínios. |
| **5) Status dos Containers** | Mostra quais contêineres estão rodando e o uso de recursos (CPU/Memória). |
| **6) Ver Logs** | Permite visualizar os logs em tempo real ou os logs recentes de cada contêiner para diagnosticar problemas. |
| **7) Atualizar** | Executa o script `update-containers.sh` para atualizar as imagens dos contêineres para as versões mais recentes (da tag configurada). |
| **8) Gerenciar Versões** | Permite alterar a versão de uma controladora no arquivo `docker-compose.yml` sem precisar reinstalar. Útil para preparar uma atualização ou downgrade. |
| **9) Backup** | Cria um arquivo `.tar.gz` de backup contendo todos os dados e configurações das controladoras. |
| **10) Remover** | Oferece opções para parar os contêineres ou remover completamente a instalação (incluindo os dados, se desejado). |
| **11) Sair** | Encerra o script. |

---

## 🔧 Outras Ferramentas

### ⚫ Atualizando as Controladoras

A atualização pode ser feita de duas maneiras, dependendo do seu objetivo.

#### Cenário 1: Atualizar para a Versão Mais Recente (se você usa a tag `latest`)

Se você instalou as controladoras usando a opção padrão `latest`, basta usar o menu de atualização para buscar a imagem mais recente disponível para essa tag.

1.  No menu principal, escolha a opção **7) Atualizar**.
2.  Selecione a controladora que deseja atualizar (ou todas).
3.  O script fará um backup, baixará a nova imagem `latest` e recriará o contêiner.

#### Cenário 2: Instalar uma Versão Específica (Upgrade ou Downgrade Controlado)

Este método é ideal quando você precisa instalar uma versão exata, como para restaurar um backup de uma versão anterior.

**Passo 1: Definir a Versão Desejada**
1.  No menu principal, escolha a opção **8) Gerenciar Versões**.
2.  Selecione a controladora (UniFi ou Omada).
3.  O script buscará as versões online e mostrará uma lista. Escolha na lista a versão exata que você deseja instalar.
4.  Confirme a alteração. O script irá modificar o arquivo `docker-compose.yml` com a nova versão, mas ainda **não irá aplicá-la**.

**Passo 2: Aplicar a Nova Versão**
1.  Com a versão já definida, volte ao menu principal.
2.  Escolha a opção de **Instalar** correspondente (ex: **1) Instalar UniFi Controller**).
3.  O script irá pular a seleção de versão (pois você já definiu) e irá baixar e recriar o contêiner usando a versão específica que você escolheu no Passo 1.

### 🔒 Configurando o SSL com Domínio (`setup-ssl.sh`)

Para acessar suas controladoras de forma segura com um cadeado verde (HTTPS), use este script.

**Importante:** Antes de executar, certifique-se de que o DNS do seu domínio (ex: `unifi.meudominio.com`) já está apontando para o IP do seu servidor.

1.  Execute o script principal: `sudo ./install.sh`
2.  Escolha a opção **4) Configurar SSL**.
3.  Siga as instruções, informando o domínio para cada controladora e um e-mail para o registro do Let's Encrypt.

O script cuidará de tudo, incluindo a configuração da renovação automática.

---

## 🤔 Solução de Problemas (FAQ)

**1. Meu servidor está com 100% de CPU após instalar o Omada! O que fazer?**

* **Calma, isso é normal!** Na primeira vez que o contêiner do Omada inicia, ele precisa gerar chaves de segurança interna. Em algumas VPS, esse processo pode ser muito intensivo e demorar de **15 a 30 minutos**. A carga da CPU irá se estabilizar e voltar ao normal sozinha. Apenas aguarde.

**2. Instalei uma controladora e a outra que já estava funcionando parou. E agora?**

* Isso pode acontecer porque o processo de instalação foca em subir apenas o serviço selecionado. A solução é simples:
    1.  Pare todos os contêineres com o comando: `docker compose down`
    2.  Inicie todos eles juntos novamente com: `docker compose up -d`
    * Pronto! Ambas as controladoras estarão online.

**3. O menu de seleção de versão não aparece, só um prompt `(1-1)` ou similar.**

* Isso indica que o script não conseguiu se conectar à API do GitHub para buscar as versões. Verifique a conexão de internet da sua VPS ou se há algum firewall bloqueando o acesso a `api.github.com`. Se o problema persistir, o script seguirá de forma segura usando a versão `latest`.

---
