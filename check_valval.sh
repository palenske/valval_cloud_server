#!/bin/bash

# Define a região (substitua com a região correta)
REGION="us-east-1"

# Pega o ID da instância atual
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Verifica os logs do servidor para ver se há jogadores conectados
PLAYERS_CONNECTED=$(sudo docker logs valheim-server 2>&1 | grep -i "Got handshake from client" | wc -l)

# Se não houver jogadores conectados, espera 1 hora para verificar novamente
if [ "$PLAYERS_CONNECTED" -eq 0 ]; then
    echo "Nenhum jogador ativo no momento. Aguardando 1 hora para nova verificação..."

    # Esperar 1 hora (3600 segundos)
    sleep 3600

    # Verifica novamente após 1 hora
    PLAYERS_CONNECTED=$(sudo docker logs valheim-server 2>&1 | grep -i "Got handshake from client" | wc -l)

    # Se ainda não houver jogadores, desliga a instância
    if [ "$PLAYERS_CONNECTED" -eq 0 ]; then
        echo "Sem jogadores ativos por mais de 1 hora. Desligando a instância..."

        # Verificar se a instância já está parada
        INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].State.Name" --output text --region $REGION)

        if [ "$INSTANCE_STATE" == "running" ]; then
            aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION
            echo "Instância desligada com sucesso."
        else
            echo "A instância já está parada."
        fi
    else
        echo "Jogadores conectados detectados. O servidor permanecerá ligado."
    fi
else
    echo "Jogadores conectados detectados. O servidor permanecerá ligado."
fi


# Abra o crontab para edição
# crontab -e

# Adicione a linha abaixo para executar o script a cada 15 minutos
# */15 * * * * /path/to/check_valheim_inactivity.sh >> /var/log/valheim_check.log 2>&1
