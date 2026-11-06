# AWS Lab: Gerenciamento Seguro de Servidores com AWS Systems Manager (SSM)

[![AWS](https://img.shields.io/badge/AWS-Cloud-orange?logo=amazon-aws)](https://aws.amazon.com/)
[![Service](https://img.shields.io/badge/Service-Systems%20Manager%20%7C%20Session%20Manager%20%7C%20EC2-232F3E?logo=amazon-aws)](https://aws.amazon.com/systems-manager/)
[![Security](https://img.shields.io/badge/Security-Zero%20Inbound%20Ports%20%7C%20No%20SSH-green)](https://aws.amazon.com/compliance/zero-trust/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Guia prático e implementação de segurança para administração e gerenciamento de frotas de instâncias Amazon EC2 **sem abrir a porta 22 (SSH) na internet**, eliminando a necessidade de Bastion Hosts dedicados e chaves criptográficas `.pem` estáticas. Utiliza **AWS Systems Manager (SSM) Session Manager**, **Run Command**, políticas IAM de menor privilégio e auditoria centralizada via **AWS CloudTrail** e **Amazon CloudWatch Logs**.

---

## 🏛️ Diagrama de Arquitetura

```mermaid
flowchart TD
    subgraph Admins["👤 Administradores & Engenheiros DevOps"]
        UserCLI["AWS CLI + Session Manager Plugin"]
        UserBrowser["AWS Management Console (Navegador)"]
    end

    subgraph AWS_Cloud["☁️ AWS Cloud (Região us-east-1)"]
        subgraph IAM_Control["🔐 Camada de Identidade & Acesso (IAM)"]
            IAM_Auth["IAM Authentication & Authorization<br/>(MFA, STS, Role-Based Access)"]
        end

        subgraph SSM_Service["⚙️ AWS Systems Manager Control Plane"]
            SessionMgr["Session Manager Engine<br/>(TLS 1.2+ / Criptografia KMS)"]
            RunCmd["Run Command Engine<br/>(Orquestração em Lote)"]
        end

        subgraph VPC["VPC Segura"]
            subgraph Security_Perimeter["🛡️ Security Group: sg-ssm-zero-ports"]
                direction TB
                SG_Rules["Inbound Rules: ❌ NENHUMA (Portas 0-65535 fechadas)<br/>Outbound Rules: HTTPS :443 (Internet ou VPC Endpoints)"]
            end

            subgraph Instance_Tier["Instâncias Gerenciadas"]
                EC2["EC2 Instance (Amazon Linux 2023)<br/>Subnet Privada / Pública<br/>SSM Agent (Ativo por padrão)"]
                IAM_Profile["Instance Profile:<br/>AmazonSSMManagedInstanceCore"]
            end
        end

        subgraph Audit_Tier["📜 Governança, Compliance & Auditoria"]
            CloudTrail["AWS CloudTrail<br/>Log de eventos da API (StartSession)"]
            CW_Logs["Amazon CloudWatch Logs<br/>Gravação de output de sessões"]
            S3_Bucket["Amazon S3 Bucket<br/>Armazenamento imutável de logs"]
        end
    end

    UserCLI -->|1. Autenticação IAM| IAM_Auth
    UserBrowser -->|1. Autenticação IAM| IAM_Auth
    IAM_Auth -->|2. Autoriza sessão| SessionMgr & RunCmd
    
    SessionMgr <==|3. Conexão WebSocket Segura (Canal de Controle)|== EC2
    RunCmd -->|3. Despacha comandos de automação| EC2
    
    EC2 -. Protegida por .- SG_Rules
    EC2 --- IAM_Profile
    
    SessionMgr -->|Gera registro de auditoria| CloudTrail
    SessionMgr -->|Grava histórico de comandos| CW_Logs
    SessionMgr -->|Arquiva sessões completas| S3_Bucket
```

---

## 📁 Estrutura do Repositório

```text
aws-lab-ssm-session-manager/
├── .gitignore                          # Ignora chaves, logs e arquivos temporários
├── README.md                           # Documentação arquitetural e guia prático
├── iam/
│   ├── ssm-instance-role.json          # Trust Policy (AssumeRole) para instâncias EC2
│   └── ssm-session-logging-policy.json # Permissões de gravação de logs em CloudWatch e S3
└── scripts/
    ├── bastion_connect.sh              # Conexão interativa via terminal CLI usando Session Manager
    ├── run_command_example.sh          # Execução remota de scripts em lote sem SSH
    └── port_forwarding_tunnel.sh       # Túnel de portas seguro para serviços internos (Web/DB)
```

---

## ⚙️ Decisões Técnicas de Arquitetura

1. **Eliminação Completa de Portas de Entrada (Zero Inbound Ports):**
   - O Security Group da instância não possui regras de entrada (`0 inbound rules`). Toda comunicação com o SSM é iniciada pelo **SSM Agent** de dentro da instância para o control plane da AWS via HTTPS (porta de saída 443).
2. **Eliminação de Chaves Privadas SSH (`.pem` / `.pub`):**
   - Não há compartilhamento, expiração ou vazamento de pares de chaves SSH. O acesso é governado unicamente por credenciais IAM temporárias e políticas de menor privilégio.
3. **Auditoria Integral e Inviolável:**
   - Cada sessão interativa gera um evento `StartSession` no **AWS CloudTrail**, registrando quem acessou, quando e de qual IP de origem. Além disso, a saída de comandos pode ser gravada diretamente no **CloudWatch Logs** e **S3**.
4. **Port Forwarding Sem Bastion Host:**
   - Permite que desenvolvedores façam túnel para portas de serviços internos (ex: MySQL 3306, Redis 6379, HTTP 80) diretamente pela linha de comando local, mantendo o banco isolado em subnet privada sem IP público.

---

## 🚀 Guia Passo a Passo de Implantação

### Pré-requisitos
- Conta AWS com permissões para IAM, EC2, Systems Manager e CloudTrail.
- AWS CLI instalado e configurado (`aws configure`).
- Plugin do Session Manager instalado no ambiente local ([Guia Oficial](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)).

---

### Passo 1: Criar a Role IAM e o Instance Profile para a EC2

O SSM Agent requer permissões para se comunicar com os endpoints do Systems Manager:

```bash
# 1. Criar a Role IAM com a Trust Policy para EC2
aws iam create-role \
  --role-name "EC2-SSM-Instance-Role" \
  --assume-role-policy-document file://iam/ssm-instance-role.json

# 2. Anexar a política gerenciada padrão da AWS
aws iam attach-role-policy \
  --role-name "EC2-SSM-Instance-Role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

# 3. Criar o Instance Profile e associar à Role
aws iam create-instance-profile \
  --instance-profile-name "EC2-SSM-Instance-Profile"

aws iam add-role-to-instance-profile \
  --instance-profile-name "EC2-SSM-Instance-Profile" \
  --role-name "EC2-SSM-Instance-Role"
```

---

### Passo 2: Criar Security Group Sem Regras de Entrada (Zero Inbound)

```bash
# Obter VPC Padrão
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)

# Criar Security Group
SG_ID=$(aws ec2 create-security-group \
  --group-name "sg-ssm-zero-inbound" \
  --description "Security Group com zero portas abertas para a internet" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" --output text)

# IMPORTANTE: Nenhuma regra de Inbound é adicionada!
# O Security Group possui apenas a saída padrão (Outbound: 0.0.0.0/0 na porta 443).
```

---

### Passo 3: Provisionar a Instância EC2 Gerenciada

O **Amazon Linux 2023** já vem com o SSM Agent pré-instalado e configurado para iniciar automaticamente:

```bash
# Obter ID da AMI mais recente do Amazon Linux 2023
AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

# Iniciar instância associando o Instance Profile
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --iam-instance-profile Name="EC2-SSM-Instance-Profile" \
  --security-group-ids "$SG_ID" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EC2-Managed-SSM},{Key=Environment,Value=Lab}]' \
  --query "Instances[0].InstanceId" --output text)

echo "Instância criada: $INSTANCE_ID"
echo "Aguardando inicialização e registro no Systems Manager..."
sleep 40
```

---

### Passo 4: Verificar Registro no Systems Manager Fleet Manager

Valide se a instância reportou status online para o Systems Manager:

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query "InstanceInformationList[*].[InstanceId,PingStatus,PlatformName,AgentVersion]" \
  --output table
```

*Saída esperada:* `PingStatus: Online`

---

## 💻 Operação e Execução Prática

### 1. Iniciar Sessão Interativa no Terminal (Substituindo o SSH)
Execute o script fornecido para abrir uma sessão interativa instantânea:

```bash
chmod +x scripts/bastion_connect.sh
./scripts/bastion_connect.sh "$INSTANCE_ID"
```

Ou execute diretamente via AWS CLI:
```bash
aws ssm start-session --target "$INSTANCE_ID"
```

Você estará em um shell `sh-5.2$` como usuário `ssm-user`, com privilégios `sudo`, **sem ter aberto a porta 22**.

---

### 2. Automação em Lote com AWS Run Command
Execute comandos administrativos sem precisar abrir sessão interativa em cada máquina:

```bash
chmod +x scripts/run_command_example.sh
./scripts/run_command_example.sh "$INSTANCE_ID"
```

O script despacha o documento `AWS-RunShellScript`, monitora a execução e imprime a saída no terminal.

---

### 3. Criar Túnel Seguro de Port Forwarding
Se a instância roda um servidor web interno na porta 80 que não possui IP público liberado:

```bash
chmod +x scripts/port_forwarding_tunnel.sh
./scripts/port_forwarding_tunnel.sh "$INSTANCE_ID" 80 8080
```

Abra seu navegador local em `http://localhost:8080` e acesse a aplicação web da instância de forma criptografada.

---

## 🔍 Auditoria, Conformidade e Governança

### Histórico de Sessões no CloudTrail
Toda conexão gera registros detalhados no AWS CloudTrail:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StartSession \
  --max-results 5 \
  --query "Events[*].[EventTime,Username,Resources[0].ResourceName]" \
  --output table
```

### Gravação de Keystrokes no CloudWatch Logs
No console da AWS em **Systems Manager** > **Session Manager** > **Preferences**, você pode configurar:
1. **CloudWatch logging:** Encaminha todos os comandos digitados pelo usuário em tempo real para um grupo de logs `/aws/ssm/session-logs`.
2. **S3 logging:** Salva o arquivo de log completo da sessão compactado e assinado em bucket S3.
3. **KMS encryption:** Criptografa o tráfego da sessão com uma chave KMS gerenciada pelo cliente.

---

## 💰 Estimativa de Custos

| Recurso AWS | Configuração | Custo Estimado (us-east-1) |
| :--- | :--- | :--- |
| **AWS Systems Manager (Core)** | Session Manager e Run Command para EC2 | **Gratuito** |
| **EC2 Instância (1x)** | `t3.micro` | Coberto pelo **AWS Free Tier** (750h/mês) |
| **AWS IAM** | Roles, Policies e Instance Profiles | **Gratuito** |
| **Amazon CloudWatch Logs** | Primeiros 5 GB/mês de ingestão | **Gratuito** |
| **AWS CloudTrail** | Trilha padrão de eventos de gerenciamento | **Gratuito** |

> 💡 **Economia:** Elimina os custos de manter uma instância EC2 dedicada como Bastion Host 24/7 (economia média de **US$ 15 a US$ 30/mês por ambiente**).

---

## 🧹 Teardown / Limpeza de Recursos

Para remover todos os recursos criados durante este laboratório:

```bash
# 1. Terminar a Instância EC2
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
echo "Aguardando encerramento da instância..."
aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"

# 2. Deletar Security Group
aws ec2 delete-security-group --group-id "$SG_ID"

# 3. Remover Instance Profile da Role e deletar
aws iam remove-role-from-instance-profile \
  --instance-profile-name "EC2-SSM-Instance-Profile" \
  --role-name "EC2-SSM-Instance-Role"

aws iam delete-instance-profile \
  --instance-profile-name "EC2-SSM-Instance-Profile"

# 4. Desanexar política e deletar a Role IAM
aws iam detach-role-policy \
  --role-name "EC2-SSM-Instance-Role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

aws iam delete-role --role-name "EC2-SSM-Instance-Role"

echo "[✓] Limpeza concluída com sucesso. Nenhum recurso ativo na conta."
```
