#!/bin/bash

# Nome da instância
INSTANCE_NAME="valheim-server"
# AMI Ubuntu 20.04 LTS
AMI_ID="ami-0a91cd140a1fc148a"
# Tipo de instância
INSTANCE_TYPE="t3.micro"
# Nome do par de chaves (não será mais necessário, mas deixado aqui caso deseje usá-lo posteriormente)
KEY_NAME="minha-chave-aws"
# Grupo de segurança, permitindo acesso apenas pelas portas do Valheim
SECURITY_GROUP_NAME="valheim-sg"
REGION="us-east-1"
ROLE_NAME="SSMRoleForEC2"

# Criar grupo de segurança para permitir tráfego nas portas do Valheim (2456-2458)
SG_ID=$(aws ec2 create-security-group --group-name $SECURITY_GROUP_NAME --description "SG for Valheim Server" --output text --query 'GroupId' --region $REGION)

# Configurar regras do grupo de segurança (não precisa abrir a porta 22 para SSH, já que usaremos SSM)
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol udp --port 2456-2458 --cidr 0.0.0.0/0 --region $REGION

# Criar a role IAM para permitir o uso de SSM
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://<(echo '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}')

# Associar políticas gerenciadas para o SSM à role criada
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Criar uma instância EC2 com Docker e SSM ativado
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type $INSTANCE_TYPE \
    --security-group-ids $SG_ID \
    --iam-instance-profile Name=$ROLE_NAME \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data '#!/bin/bash
                 sudo apt-get update -y
                 sudo apt-get install docker.io -y
                 sudo systemctl start docker
                 sudo systemctl enable docker
                 sudo docker run -d --name valheim-server \
                   -p 2456-2458:2456-2458/udp \
                   -e SERVER_NAME="MeuServerValheim" \
                   -e WORLD_NAME="meu_mundo" \
                   -e SERVER_PASS="minhasenha" \
                   lloesche/valheim-server
                 # Instalar o SSM agent
                 sudo snap install amazon-ssm-agent --classic
                 sudo systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent
                 sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent' \
    --output text --query 'Instances[0].InstanceId' --region $REGION)

# Exibir status da instância
echo "Instância EC2 criada com ID: $INSTANCE_ID"
echo "Esperando que a instância inicie..."

# Aguardar até que a instância esteja rodando
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

# Obter IP público da instância
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text --region $REGION)
echo "Instância iniciada com IP: $PUBLIC_IP"
