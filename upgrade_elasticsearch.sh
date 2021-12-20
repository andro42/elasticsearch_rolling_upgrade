#!/bin/bash

# Usage: 
#     bash upgrade_elasticsearch.sh "es_node01 es_node02 es_node3" "https://localhost:9200" "elastic" "securepassword" ["ignore_status"]'
# Include script_body.sh in the same folder
# Version: 0.4 (reboot)

# Params
NODES=$1            # Example: "es_node01 es_node02 es_node03"
ES_URL=$2           # Use localhost Example: "https://localhost:9200"
ES_USER=$3          # Example: elastic
ES_PASS=$4          # Example: securepass
OPTIONS=$5          # Possible values: 
                    #   status_ignore (do not wait for green status), 
                    #   status_yellow (continue script on green or yellow),
                    #   reboot

# ---- Help -------------------------------------------------------------------
echo; echo; echo -e $_{1..100}"\b=";
echo "                UPGRADE ES NODES script";echo
echo "This script updates ES on multiple ES nodes."
echo ""
echo "Usage:"
echo "    bash upgrade_elasticsearch.sh NODES ES_URL ES_USER ES_PASS [OPTIONS]"
echo "Example:"
echo '    bash upgrade_elasticsearch.sh "es_node01 es_node02 es_node3" "https://localhost:9200" "elastic" "securepassword" ["status_yellow,reboot"]'
echo ""
echo '   ES_URL: Use localhost address. Example: "https://localhost:9200"'
echo ""
echo "  [OPTIONS] possible values:"
echo "    status_ignore - Do not wait for green status of the cluster"
echo "    status_yellow - Wait for yellow or green status before continue"
echo "    reboot        - Reboot the server"
echo ""
echo "Prerequisites:"
echo "    - Debian or Redhat based Linux operating system"
echo "    - ssh client"
echo "    - script_body_1.sh: script that is sent to ssh session"
echo "    - script_body_2.sh: script that is sent to ssh session"
echo ""
echo "It uses ssh to connect to nodes. Use command 'ssh-keygen; ssh-copy-id userid@hostname' to avoid typing password for each node"
echo;echo "by Andrej Zevnik @2021"
echo "Version 0.4"
echo -e $_{1..100}"\b=";echo;echo
sleep 2

# ---- Global vars ------------------------------------------------------------
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

# ---- Check for arguments and script file ------------------------------------
if [[ ! -f script_body_1.sh ]]; then  echo -e "${RED}[ERROR]:${NC} File script_body_1.sh missing. Check usage."; echo; exit 1; fi;
if [[ ! -f script_body_2.sh ]]; then  echo -e "${RED}[ERROR]:${NC} File script_body_2.sh missing. Check usage."; echo; exit 1; fi;
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
        bash script_body_1.sh "$ES_URL" "local" "$ES_USER" "$ES_PASS" "$OPTIONS"
        echo "------------------------ Completed script on local node [$NODE] -----------------------------"
        sleep 2
    else
        # Remote node
        echo "------------------------ Connecting to node [$NODE] -----------------------------------------"
        sleep 2
        # Problems with interactive commands like read
        # ssh ${NODE} 'bash -s' < script_body.sh "$ES_URL" "$ES_USER" "$ES_PASS" "$OPTIONS"
        ssh ${NODE} -t bash -c "$(printf "%q" "$(< script_body_1.sh )")" -- "$ES_URL" "remote" "$ES_USER" "$ES_PASS" "$OPTIONS"
        # If [reboot] was set
        if [[ $OPTIONS =~ "reboot"  ]]; then
            echo "    [REBOOT]: Waiting for node: [${NODE}] to reboot..."
            sleep 5
            until (echo > "/dev/tcp/${NODE}/22") >/dev/null 2>&1; do
                sleep 3 
                echo "    [REBOOT]: Waiting for port 22 on node [${NODE}] to open..."
            done
            echo "    [REBOOT]: Port 22 on node [${NODE}] opened. Waiting 10s to connect..."
            sleep 10
            echo "    [REBOOT]: Reconnecting SSH and executing commands after reboot..."
            sleep 2
            ssh ${NODE} -t bash -c "$(printf "%q" "$(< script_body_2.sh )")" -- "$ES_URL" "$ES_USER" "$ES_PASS" "$OPTIONS"
        fi
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
