#!/bin/bash

# Nome da instância
INSTANCE_NAME="valheim-server"
# AMI Ubuntu 20.04 LTS
AMI_ID="ami-04b107e90218672e5"
# Tipo de instância
INSTANCE_TYPE="t3.micro"
# Nome do grupo de segurança
SECURITY_GROUP_NAME="valheim-sg"
# Região AWS
REGION="us-east-1"
# Nome da role IAM para SSM
ROLE_NAME="SSMRoleForEC2"
# Nome do perfil de instância
INSTANCE_PROFILE_NAME="ValheimSSMInstanceProfile"

# Config servidor
SERVER_NAME="MeuServerValheim"
WORLD_NAME="meu_mundo"
SERVER_PASS="minhasenha"

# Verificar se a role IAM já existe
if aws iam get-role --role-name "$ROLE_NAME" --region "$REGION" &> /dev/null; then
    echo "A role IAM '$ROLE_NAME' já existe."
else
    aws iam create-role --role-name "$ROLE_NAME" \
        --assume-role-policy-document file://data/ec2-role-policy.json \
        --region "$REGION"
    
    aws iam attach-role-policy --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
        --region "$REGION"
    echo "Role IAM '$ROLE_NAME' criada e política AmazonSSMManagedInstanceCore anexada."
fi

# Verificar se o perfil de instância já existe
if aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --region "$REGION" &> /dev/null; then
    echo "O perfil de instância '$INSTANCE_PROFILE_NAME' já existe."
else
    aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --region "$REGION"
    aws iam add-role-to-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --role-name "$ROLE_NAME" --region "$REGION"
    echo "Perfil de instância '$INSTANCE_PROFILE_NAME' criado e role '$ROLE_NAME' adicionada."
fi

# Verificar se o grupo de segurança já existe e obter seu ID
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SECURITY_GROUP_NAME" --query 'SecurityGroups[0].GroupId' --output text --region "$REGION")

if [ "$SG_ID" == "None" ]; then
    SG_ID=$(aws ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" --description "SG para Valheim Server" --output text --query 'GroupId' --region "$REGION")
    echo "Grupo de segurança '$SECURITY_GROUP_NAME' criado com ID: $SG_ID."

    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol udp --port 2456-2458 --cidr 0.0.0.0/0 --region "$REGION"
    echo "Regras de segurança configuradas para o grupo '$SECURITY_GROUP_NAME'."
else
    echo "O grupo de segurança '$SECURITY_GROUP_NAME' já existe. Usando ID: $SG_ID"
fi

# Criar uma instância EC2 com Docker e SSM ativado
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type "$INSTANCE_TYPE" \
    --security-group-ids "$SG_ID" \
    --iam-instance-profile Name="$INSTANCE_PROFILE_NAME" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data "#!/bin/bash
                 SERVER_NAME='$SERVER_NAME'
                 WORLD_NAME='$WORLD_NAME'
                 SERVER_PASS='$SERVER_PASS'
                 
                 sudo apt-get update -y
                 sudo apt-get install docker.io -y
                 sudo systemctl start docker
                 sudo systemctl enable docker
                 sudo docker run -d --name valheim-server \
                   -p 2456-2458:2456-2458/udp \
                   -e SERVER_NAME=\$SERVER_NAME \
                   -e WORLD_NAME=\$WORLD_NAME \
                   -e SERVER_PASS=\$SERVER_PASS \
                   lloesche/valheim-server" \
    --output text --query 'Instances[0].InstanceId' --region "$REGION")

# Verificar se a instância foi criada com sucesso
if [ -z "$INSTANCE_ID" ]; then
    echo "Erro ao criar a instância EC2. Verifique os logs."
    exit 1
else
    echo "Instância EC2 criada com ID: $INSTANCE_ID."
    echo "Esperando que a instância inicie..."
fi

# Aguardar até que a instância esteja em estado 'running'
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

# Obter IP público da instância
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text --region "$REGION")

if [ "$PUBLIC_IP" == "None" ]; then
    echo "Falha ao obter o IP público da instância. Verifique o estado da instância."
    exit 1
else
    echo "Instância iniciada com sucesso! IP público: $PUBLIC_IP"
    echo "O servidor Valheim está em execução. Conecte-se usando o IP: $PUBLIC_IP"
fi
