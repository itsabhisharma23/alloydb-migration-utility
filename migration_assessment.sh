#!/bin/bash

CONFIG_FILE="migration.config" 

GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
BOLD=$(tput bold)
NC=$(tput sgr0)

if [[ -f "$CONFIG_FILE" ]]; then
  echo "\nLoading your configuration from $CONFIG_FILE"
  source "$CONFIG_FILE"
else
  echo "\nWarning: Configuration file '$CONFIG_FILE' not found. "
fi

sudo apt-get update
sudo apt-get install -yq git python3 python3-pip python3-distutils
sudo pip install --upgrade pip virtualenv

virtualenv -p python3 env
source env/bin/activate
wget https://github.com/GoogleCloudPlatform/database-assessment/releases/download/v4.3.43/dma-4.3.43-py3-none-any.whl
pip install psycopg
pip install 'dma-4.3.43-py3-none-any.whl'

dma readiness-check --db-type postgres --hostname $SOURCE_HOST --no-prompt --port $SOURCE_PORT --database postgres --username postgres --password $DVT_SOURCE_PASSWORD