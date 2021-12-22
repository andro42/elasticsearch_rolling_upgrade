#!/bin/bash

# Usage: 
#     bash upgrade_elasticsearch.sh "es_node01 es_node02 es_node3" "https://localhost:9200" "elastic" "securepassword" ["ignore_status"]'
# Include script_body.sh in the same folder
# Version: 0.5 (log to file)

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
echo; echo; 
echo "===================================================================================================="
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
echo "===================================================================================================="
echo;echo
sleep 2

# ---- Global vars ------------------------------------------------------------
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m"
LOGFILE="run.log"

# ---- Logging function -------------------------------------------------------
echolog () {
    local msg=$1
    local echo_opt=$2
    local init=$3

    if [ "$init" == "init" ]; then
        echo > $LOGFILE
    fi
    if [ "$echo_opt" == "-e" ]; then
        echo -e "${msg}" | tee -a $LOGFILE  #; echo | tee -a $LOGFILE
    else
        echo "${msg}" | tee -a $LOGFILE
    fi
    return 0
}

# ---- Check for arguments and script file ------------------------------------
echolog "====================================================================================================" "--" "init"
echolog "               Starting script [$(date)]"
echolog "===================================================================================================="
echolog ""
if [[ ! -f script_body_1.sh ]]; then  echolog "${RED}[ERROR]:${NC} File script_body_1.sh missing. Check usage." "-e"; exit 1; fi;
if [[ ! -f script_body_2.sh ]]; then  echolog "${RED}[ERROR]:${NC} File script_body_2.sh missing. Check usage." "-e"; exit 1; fi;
if [ -z "$NODES" ];   then echolog "${RED}[ERROR]:${NC} Argument NODES missing. Check usage." "-e"; exit 1; fi;
if [ -z "$ES_URL" ];  then echolog "${RED}[ERROR]:${NC} Argument ES_URL missing. Check usage." "-e"; exit 1; fi;
if [ -z "$ES_USER" ]; then echolog "[WARNING]: Optional Argument ES_USER missing."; echolog; fi;
if [ -z "$ES_PASS" ]; then echolog "[WARNING]: Optional Argument ES_PASS missing."; echolog; fi; 

# ---- Shell Options ----------------------------------------------------------
shopt -s nocasematch

# ---- Loop for each node and apply script_body.sh ----------------------------
for NODE in ${NODES} ; do
    if [[ $NODE == $(hostname) || $NODE == $(hostname -s) ]]; then 
        # Local node
        echolog "------------------------ Executing on local node [$NODE] ------------------------------------"
        sleep 2
        bash script_body_1.sh "$ES_URL" "local" "$ES_USER" "$ES_PASS" "$OPTIONS" | tee -a $LOGFILE
        echolog "------------------------ Completed script on local node [$NODE] -----------------------------"
        sleep 2
    else
        # Remote node
        echolog "------------------------ Connecting to node [$NODE] -----------------------------------------"
        sleep 2
        # Problems with interactive commands like read
        # ssh ${NODE} 'bash -s' < script_body.sh "$ES_URL" "$ES_USER" "$ES_PASS" "$OPTIONS"
        ssh ${NODE} -t bash -c "$(printf "%q" "$(< script_body_1.sh )")" -- "$ES_URL" "remote" "$ES_USER" "$ES_PASS" "$OPTIONS" | tee -a $LOGFILE
        # If [reboot] was set
        if [[ $OPTIONS =~ "reboot"  ]]; then
            echolog "    [REBOOT]: Waiting for node: [${NODE}] to reboot..."
            sleep 5
            until (echo > "/dev/tcp/${NODE}/22") >/dev/null 2>&1; do
                sleep 3 
                echolog "    [REBOOT]: Waiting for port 22 on node [${NODE}] to open..."
            done
            echolog "    [REBOOT]: Port 22 on node [${NODE}] ${GREEN}opened${NC}. Waiting 10s to connect..." "-e"
            sleep 10
            echolog "    [REBOOT]: Reconnecting SSH and executing commands after reboot..."
            sleep 2
            ssh ${NODE} -t bash -c "$(printf "%q" "$(< script_body_2.sh )")" -- "$ES_URL" "$ES_USER" "$ES_PASS" "$OPTIONS" | tee -a $LOGFILE
        fi
        echolog "------------------------ Disconnecting from node [$NODE] ------------------------------------"
        echolog ""
        sleep 2
    fi
done

# ---- Finaly -----------------------------------------------------------------
echolog; echolog
echolog "===================================================================================================="
echolog "                            Main script ${GREEN}COMPLETED${NC}. " "-e"
echolog "===================================================================================================="
echolog; echolog
# echo "Press [1] to view run.log. Press any other key to finish..."
read -s -n 1 -p "Press [1] to view run.log. Press any other key to finish..."  key
echo; echo
if [[ "$key" == "1" ]]; then
    echo "[1] was pressed. Starting less viewer. Press [q] to exit program..."
    sleep 3
    less -r $LOGFILE
fi

