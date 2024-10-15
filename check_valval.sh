#!/bin/bash

# Definir a região da AWS (substitua conforme necessário)
REGION="us-east-1"

# Pegar o ID da instância EC2 atual
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Verificar se o servidor Docker está rodando
DOCKER_STATUS=$(sudo docker inspect -f '{{.State.Running}}' valheim-server 2>/dev/null)

if [ "$DOCKER_STATUS" != "true" ]; then
    echo "O container do servidor Valheim não está em execução. Saindo do script."
    exit 1
fi

# Verificar nos logs se há jogadores conectados
PLAYERS_CONNECTED=$(sudo docker logs valheim-server 2>&1 | grep -i "Got handshake from client" | wc -l)

# Se não houver jogadores conectados
if [ "$PLAYERS_CONNECTED" -eq 0 ]; then
    echo "Nenhum jogador ativo detectado. Aguardando 1 hora para nova verificação..."

    # Aguardar 1 hora (3600 segundos)
    sleep 3600

    # Verificar novamente após 1 hora
    PLAYERS_CONNECTED=$(sudo docker logs valheim-server 2>&1 | grep -i "Got handshake from client" | wc -l)

    # Se ainda não houver jogadores conectados, desligar a instância
    if [ "$PLAYERS_CONNECTED" -eq 0 ]; then
        echo "Sem jogadores ativos por mais de 1 hora. Desligando a instância..."

        # Verificar o estado da instância EC2
        INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].State.Name" --output text --region "$REGION")

        if [ "$INSTANCE_STATE" == "running" ]; then
            # Desligar a instância EC2
            aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
            echo "A instância EC2 foi desligada com sucesso."
        else
            echo "A instância EC2 já está parada."
        fi
    else
        echo "Jogadores conectados detectados. O servidor permanecerá ligado."
    fi
else
    echo "Jogadores conectados detectados. O servidor permanecerá ligado."
fi
