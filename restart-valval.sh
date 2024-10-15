#!/bin/bash

# Define a região e ID da instância
REGION="us-east-1"
INSTANCE_ID="i-xxxxxxxxxxxxxx"  # Substitua pelo seu ID de instância

# Iniciar a instância EC2
aws ec2 start-instances --instance-ids $INSTANCE_ID --region $REGION
