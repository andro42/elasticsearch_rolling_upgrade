#!/bin/bash

# Usage: 
#     bash upgrade_elasticsearch.sh "es_node01 es_node02 es_node3" "https://localhost:9200" "elastic" "securepassword"'
# Include script_body.sh in the same folder
# Version: 0.2

# Params
NODES=$1 # Example: "es_node01 es_node02 es_node03"
ES_URL=$2
ES_USER=$3
ES_PASS=$4

# ---- Help -------------------------------------------------------------------
echo; echo; echo -e $_{1..100}"\b=";
echo "                UPGRADE ES NODES script";echo
echo "This script updates ES on multiple ES nodes."
echo ""
echo "Usage:"
echo "    bash upgrade_elasticsearch.sh NODES ES_URL ES_USER ES_PASS"
echo "Example:"
echo '    bash upgrade_elasticsearch.sh "es_node01 es_node02 es_node3" "https://localhost:9200" "elastic" "securepassword" '
echo ""
echo "Prerequisites:"
echo "    - Debian or Redhat based Linux operating system"
echo "    - ssh client"
echo "    - script_body.sh: script that is sent to ssh session"
echo ""
echo "It uses ssh to connect to nodes. Use command 'ssh-keygen; ssh-copy-id userid@hostname' to avoid typing password for each node"
echo;echo "by Andrej Zevnik @2021"
echo -e $_{1..100}"\b=";echo;echo
sleep 2

# ---- Global vars ------------------------------------------------------------
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

# ---- Check for arguments and script file ------------------------------------
if [[ ! -f script_body.sh ]]; then  echo -e "${RED}[ERROR]:${NC} File script_body.sh missing. Check usage."; echo; exit 1; fi;
if [ -z "$NODES" ];   then echo -e "${RED}[ERROR]:${NC} Argument NODES missing. Check usage."; echo; exit 1; fi;
if [ -z "$ES_URL" ];  then echo -e "${RED}[ERROR]:${NC} Argument ES_URL missing. Check usage."; echo; exit 1; fi;
if [ -z "$ES_USER" ]; then echo "[WARNING]: Optional Argument ES_USER missing."; echo; fi;
if [ -z "$ES_PASS" ]; then echo "[WARNING]: Optional Argument ES_PASS missing."; echo; fi; 

# ---- Shell Options ----------------------------------------------------------
shopt -s nocasematch

# ---- Loop for each node and apply script_body.sh ----------------------------
for NODE in ${NODES} ; do
    if [[ $NODE == $(hostname) || $NODE == $(hostname -s) ]]; then 
        # Local node
        echo "------------------------ Executing on local node [$NODE] ------------------------------------"
        sleep 2
        bash script_body.sh "$ES_URL" "$ES_USER" "$ES_PASS" 
        echo "------------------------ Completed script on local node [$NODE] -----------------------------"
        sleep 2
    else
        # Remote node
        echo "------------------------ Connecting to node [$NODE] -----------------------------------------"
        sleep 2
        ssh ${NODE} 'bash -s' < script_body.sh "$ES_URL" "$ES_USER" "$ES_PASS"
        echo "------------------------ Disconnecting from node [$NODE] ------------------------------------"
        sleep 2
    fi
done

# ---- Finaly -----------------------------------------------------------------
echo; echo
echo -e $_{1..100}"\b="
echo "                            Main script COMPLETED. "
echo -e $_{1..100}"\b="
echo; echo
