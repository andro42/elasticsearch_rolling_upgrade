#!/bin/bash

# Usage: 
#     bash upgrade_elasticsearch.sh "es_node01 es_node02 es_node3" "https://localhost:9200" "elastic" "securepassword" ["ignore_status"]'
# Include script_body.sh in the same folder
# Version: 0.7 (less -i on the end; metricbeat restart)

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
echo ""
echo "It uses ssh to connect to nodes. Use command 'ssh-keygen; ssh-copy-id userid@hostname' to avoid typing password for each node"
echo;echo "by Andrej Zevnik @2022"
echo "Version 0.7"
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
if [ -z "$NODES" ];   then echolog "${RED}[ERROR]:${NC} Argument NODES missing. Check usage." "-e"; exit 1; fi;
if [ -z "$ES_URL" ];  then echolog "${RED}[ERROR]:${NC} Argument ES_URL missing. Check usage." "-e"; exit 1; fi;
if [ -z "$ES_USER" ]; then echolog "[WARNING]: Optional Argument ES_USER missing."; echolog; fi;
if [ -z "$ES_PASS" ]; then echolog "[WARNING]: Optional Argument ES_PASS missing."; echolog; fi; 

# ---- Shell Options ----------------------------------------------------------
shopt -s nocasematch

#########################################################
# ---- Function ssh_commands_before_reboot ----------------------------------------------------------
ssh_commands_before_reboot () {

    # Params ##################################
    local URL=$1
    local REMOTE=$2
    local ES_USER=$3
    local ES_PASS=$4
    local OPTIONS=$5
    ###########################################

    # Body ####################################
    local NODE_NAME=$(hostname)
    local GREEN="\033[0;32m"
    local RED="\033[0;31m"
    local YELLOW="\033[0;33m"
    local NC="\033[0m"

    # ---- Check for arguments ----------------------------------------------------
    if [ -z "$URL" ]; then echo -e "${RED}[ERROR]:${NC} Argument ES_URL missing. Check usage."; echo; exit 1; fi;
    if [ -z "$REMOTE" ]; then echo -e "${RED}[ERROR]:${NC} Argument REMOTE missing."; echo; exit 1; fi;
    if [ -z "$ES_USER" ]; then echo "[WARNING]: Optional Argument ES_USER missing."; fi;
    if [ -z "$ES_PASS" ]; then echo "[WARNING]: Optional Argument ES_PASS missing."; fi; 
    if [ -z "$OPTIONS" ]; then OPTIONS="null"; fi; 

    # ---- Check for elasticsearch service ----------------------------------------
    echo ""
    echo "===================================================================================================="
    echo "====== Testing ES connection on node [$NODE_NAME]"
    echo "===================================================================================================="
    if systemctl status "elasticsearch.service" 2> /dev/null | grep -Fq "Active:"; then 
        es_bool=1 
    else 
        es_bool=0 
    fi
    if [ $es_bool == 1 ]; then 
        res=$(curl -s -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" -o /dev/null -w "%{http_code}" "$URL")
        if [ $res -eq 200 ]; then 
            echo -e "    Successfuly connected to $URL..... ${GREEN}[OK].${NC}"
        else
            echo -e "    ${RED}ERROR:${NC} Could not connect to $URL."; echo
            echo "    Response code: ${res}!"
            echo "    Response from server:"
            curl -s -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" "$URL"
            echo;echo;echo -e "    ${RED}TERMINATING${NC} bash script on node [$NODE_NAME]...."; echo
            read -n 1 -s -r -p "Press any key to exit...."
            exit 1
        fi
    else 
        echo "    Elasticsearch not installed. Skipping."
    fi
    sleep 1

    # ---- Wait for ES status green  ----------------------------------------------
    if [ $es_bool == 1 ]; then 
        echo;echo
        echo "===================================================================================================="
        echo "====== Checking for ES Cluster Status on node [$NODE_NAME]"
        echo "===================================================================================================="
        key=""
        # Wait for 10 min checkin for green status
        for i in {0..600}; do
            ES_STATUS=$(curl -s -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" "$URL/_cluster/health?pretty" \
                | grep status | awk '{ print $3 }' | tr -d '"' | tr -d ',')
            if [[ $ES_STATUS == "green" ]]; then  # 503 - master_not_discovered
                echo -e "    Elasticsearch cluster status: $ES_STATUS................. ${GREEN}[OK].${NC}"
                break
            elif [[ $OPTIONS =~ "status_ignore" ]]; then
                echo "    [WARNING]: Elasticsearch cluster status: $ES_STATUS. [ingore_status] was set so we continue regardless..."
                sleep 3
                break
            elif [ $ES_STATUS == "503" ]; then
                echo "    [WARNING]: Elasticsearch cluster status: $ES_STATUS - master_not_discovered."
                read -n 1 -s -r -p "    Press any key to continue executing script...."
                sleep 3
                break
            else 
                # Write warning only every 10s 
                if (( $i % 10 == 0 )); then
                    if [[ $OPTIONS =~ "status_yellow" && $ES_STATUS == "yellow" ]]; then
                        echo "    [WARNING]: Elasticsearch cluster status: $ES_STATUS. [status_yellow] was set so we continue regardless..."
                        sleep 3
                        break
                    else
                        echo "    [WARNING]: Elasticsearch cluster status: $ES_STATUS. Waiting for green status. Press [c] to override and continue."
                    fi
                fi
            fi
            #sleep 1
            # Check for key press to continue script
            read -s -n 1 -t 1  key
            if [[ $key == "c" || $key == "C" ]]; then
                echo "    [c] was pressed. Continue script execution in 5 seconds..."
                sleep 5
                break
            fi
        done
        sleep 1
    fi

    # ---- Check for update and check OS  -----------------------------------------
    echo;echo;
    echo "===================================================================================================="
    echo "====== Checking for updates on node [$NODE_NAME]"
    echo "===================================================================================================="
    # Check which OS
    if [[ -f /etc/debian_version ]]; then 
        sudo apt update
    elif [[ -f /etc/centos-release ]] | [[ -f /etc/redhat-release ]]; then 
        sudo yum check-update
    else
        echo -e "    ${RED}ERROR:${NC} Unkown Operating System."; echo
        exit 1
    fi
    sleep 2

    # ---- Elastic: Disable Replica Alocation and Flush ---------------------------
    if [ $es_bool == 1 ]; then 
        echo;echo;
        echo "===================================================================================================="
        echo "====== Elastic: Disable Replica Alocation and Flush on node [$NODE_NAME]"
        echo "===================================================================================================="
        # Disable Replica Alocation
        echo -n "    Starting Disable Replica Alocation......"
        res=$(curl -s -X PUT -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" -o /dev/null -w "%{http_code}" "$URL/_cluster/settings?pretty" -d'{"persistent": {"cluster.routing.allocation.enable": "primaries"}}' )
        if [ $res -eq 200 ]; then 
            echo -e "${GREEN} [OK]. ${NC}"
        else
            echo -e "    ${RED}ERROR:${NC} Could not Disable Replica Alocation"
            echo "    Response code: ${res}!"
        fi
        # Flush Synced
        echo -n "    Starting Flush all Indices.............."
        sleep 3
        res=$(curl -s -X POST -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" -o /dev/null -w "%{http_code}" "$URL/_flush")
        if [ $res -eq 200 ]; then 
            echo -e "${GREEN} [OK]. ${NC}"
        else
            echo -e "    Could not Flush All. This is usualy not a problem."
            echo "    Response code: ${res}!"
        fi
        sleep 2
    fi

    # ---- Stopping ES and related services ---------------------------------------
    echo;echo;
    echo "===================================================================================================="
    echo "====== Stopping ES and related services on node [$NODE_NAME]"
    echo "===================================================================================================="
    if systemctl status "filebeat.service" 2> /dev/null | grep -Fq "Active:"; then
        echo -n "    Stopping filebeat service..............."
        sudo systemctl stop filebeat.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "metricbeat.service" 2> /dev/null | grep -Fq "Active:"; then
        echo -n "    Stopping metricbeat service............."
        sudo systemctl stop metricbeat.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "auditbeat.service" 2> /dev/null | grep -Fq "Active:"; then
        echo -n "    Stopping auditbeat service.............."
        sudo systemctl stop auditbeat.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "logstash.service" 2> /dev/null | grep -Fq "Active:"; then
        echo -n "    Stopping logstash service..............."
        sudo systemctl stop logstash.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "kibana.service" 2> /dev/null | grep -Fq "Active:"; then
        echo -n "    Stopping kibana service................."
        sudo systemctl stop kibana.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "nginx.service" 2> /dev/null | grep -Fq "Active:"; then
        echo -n "    Stopping nginx service.................."
        sudo systemctl stop nginx \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "elasticsearch.service" 2> /dev/null | grep -Fq "Active:"; then 
        echo -n "    Stopping elasticsearch service.........."
        sudo systemctl stop elasticsearch.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    sleep 1

    # ---- System update ----------------------------------------------------------
    echo;echo;
    echo "===================================================================================================="
    echo "====== System update on node [$NODE_NAME]"
    echo "===================================================================================================="
    # Check which OS
    if [[ -f /etc/debian_version ]]; then 
        #sudo apt upgrade -y
        sudo apt-get -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" upgrade
    elif [[ -f /etc/centos-release ]] | [[ -f /etc/redhat-release ]]; then 
        sudo yum update -y
    else
        echo -e "    ${RED}ERROR:${NC} Unkown Operating System. Continuoing to start ES services..."; echo
    fi
    sudo systemctl daemon-reload
    sleep 1

    # ---- System Reboot if set in Options ---------------------------------
    if [[ $OPTIONS =~ "reboot"  ]]; then
        echo;echo;
        echo "===================================================================================================="
        echo "====== Rebooting the system on node [$NODE_NAME]"
        echo "===================================================================================================="
        # Reboot only remote servers.
        if [ $REMOTE == "remote" ]; then 
            echo -e "    [REBOOT]: System will ${YELLOW}reboot${NC} in 10 seconds. Press CTRL+C to cancel."
            sleep 10
            sudo reboot
        else
            echo -e "    ${YELLOW}[WARNING]${NC}: Option [reboot] was set, but this is local server. You need to reboot manualy after script completion."
            echo
            FINAL_WARN="    ${YELLOW}[WARNING]${NC}: Option [reboot] was set, but ${NODE_NAME} is local server. Manualy reboot this server."
            sleep 2
        fi
    fi

    # ---- Starting ES and related services ---------------------------------------
    echo;echo;
    echo "===================================================================================================="
    echo "====== Starting ES and related services on node [$NODE_NAME]"
    echo "===================================================================================================="
    if systemctl status "elasticsearch.service" 2> /dev/null | grep -Fq "Active:"; then 
        echo -n "    Starting elasticsearch service.........."
        sudo systemctl start elasticsearch.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
        sleep 5 # Wait for elasticserach
    fi
    if systemctl status "filebeat.service" 2> /dev/null | grep -Fq "Active:"; then      
        echo -n "    Starting filebeat service..............."
        sudo systemctl start filebeat.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "metricbeat.service" 2> /dev/null | grep -Fq "Active:"; then    
        echo -n "    Starting metricbeat service............."
        sudo systemctl start metricbeat.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "auditbeat.service" 2> /dev/null | grep -Fq "Active:"; then  
        echo -n "     Starting auditbeat service............."
        sudo systemctl start auditbeat.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "logstash.service" 2> /dev/null | grep -Fq "Active:"; then 
        echo -n "    Starting logstash service..............."
        sudo systemctl start logstash.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "kibana.service" 2> /dev/null | grep -Fq "Active:"; then 
        echo -n "    Starting kibana service................."
        sudo systemctl start kibana.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "nginx.service" 2> /dev/null | grep -Fq "Active:"; then 
        echo -n "    Starting nginx service.................."
        sudo systemctl start nginx \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    sleep 1

    # ---- Elastic: Enable back Replica Alocation ---------------------------------
    if [ $es_bool == 1 ]; then 
        echo;echo;
        echo "===================================================================================================="
        echo "====== Elastic: Enable back Replica Alocation on node [$NODE_NAME]"
        echo "===================================================================================================="
        curl -s -X PUT -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" "$URL/_cluster/settings?pretty" -d'{"persistent": {"cluster.routing.allocation.enable": null}}'
        echo "===================================================================================================="
        sleep 1
    fi

    # ---- Nginx: Safety restart --------------------------------------------------
    if systemctl status "nginx.service" 2> /dev/null | grep -Fq "Active:"; then 
        echo;echo;
        echo "===================================================================================================="
        echo "====== Nginx: Safety restart on node [$NODE_NAME]"
        echo "===================================================================================================="
        echo -n "    Restarting nginx service................"
        sudo systemctl restart nginx  \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
        echo "===================================================================================================="
        sleep 1
    fi

    # ---- Get ES Health ----------------------------------------------------------
    if [ $es_bool == 1 ]; then 
        echo;echo;
        echo "===================================================================================================="
        echo "====== Get ES Health on node [$NODE_NAME]"
        echo "===================================================================================================="
        curl -s -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" "$URL/_cluster/health?pretty" 
        sleep 1
    fi

    # ---- Finish -----------------------------------------------------------------
    echo "===================================================================================================="
    echo; echo; 
    echo "===================================================================================================="
    echo -e "    ${GREEN}Upgrade complete${NC} on node [$NODE_NAME]. Check above for status of upgrade.";
    echo "===================================================================================================="
    echo; echo; echo "------------------ Waiting 10s to disconnect from node [$NODE_NAME].... "
    sleep 10
    # End Function ssh_commands_before_reboot  ############################
}
#########################################################

#########################################################
# ---- Function ssh_commands_after_reboot ----------------------------------------------------------
ssh_commands_after_reboot () {
    # Params ##################################
    local URL=$1
    local ES_USER=$2
    local ES_PASS=$3
    local OPTIONS=$4
    ###########################################

    # Body ####################################
    local NODE_NAME=$(hostname)
    local GREEN="\033[0;32m"
    local RED="\033[0;31m"
    local YELLOW="\033[0;33m"
    local NC="\033[0m"

    # ---- Check for arguments ----------------------------------------------------
    if [ -z "$URL" ]; then echo -e "${RED}[ERROR]:${NC} Argument ES_URL missing. Check usage."; echo; exit 1; fi;
    if [ -z "$ES_USER" ]; then echo "[WARNING]: Optional Argument ES_USER missing."; fi;
    if [ -z "$ES_PASS" ]; then echo "[WARNING]: Optional Argument ES_PASS missing."; fi; 
    if [ -z "$OPTIONS" ]; then OPTIONS="null"; fi; 

    # ---- Check for elasticsearch service ----------------------------------------
    echo ""
    echo "===================================================================================================="
    echo "====== Testing ES connection on node [$NODE_NAME]"
    echo "===================================================================================================="
     if systemctl status "elasticsearch.service" 2> /dev/null | grep -Fq "Active:"; then 
        es_bool=1 
    else 
        es_bool=0 
    fi
    if [ $es_bool == 1 ]; then 
        # After reboot wait max 5 min for ES service to start
        echo "    Waiting max 5 min for Elasticsearch service to start..."
        echo "    (Press [c] to override and continue)"
        res=400
        key=""
        for i in {0..300}; do
            res=$(curl -s -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" -o /dev/null -w "%{http_code}" "$URL")
            if [ $res -eq 200 ]; then 
                echo -e "    Successfuly connected to $URL..... ${GREEN}[OK].${NC}"
                break
            else
                # Write warning only every 10s 
                if (( $i % 10 == 0 )); then
                    echo "    [WARNING]: Elasticsearch response code: ${res}. Waiting for 200..."
                fi
            fi
            #sleep 1
            # Check for key press to continue script
            read -s -n 1 -t 1  key
            if [[ $key == "c" || $key == "C" ]]; then
                echo "    [c] was pressed. Continue script execution in 5 seconds..."
                sleep 5
                res=200
                break
            fi
        done
        if [ $res -ne 200 ]; then
            echo -e "    ${RED}ERROR:${NC} Could not connect to $URL."; echo
            echo "    Response code: ${res}!"
            echo "    Response from server:"
            curl -s -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" "$URL"
            echo;echo;echo -e "    ${RED}TERMINATING${NC} bash script on node [$NODE_NAME]...."; echo
            read -n 1 -s -r -p "Press any key to exit...."
            exit 1
        fi
    else 
        echo "    Elasticsearch not installed. Skipping."
    fi
    sleep 1

    # ---- Checking status of ES and related services ---------------------------------------
    echo;echo;
    echo "===================================================================================================="
    echo "====== Checking for ES and related services on node [$NODE_NAME]"
    echo "===================================================================================================="
    if systemctl status "elasticsearch.service" 2> /dev/null | grep -Fq "Active:"; then 
        echo -n "    Checking elasticsearch service.........."
        sudo systemctl is-active --quiet elasticsearch.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
        sleep 5 # Wait for elasticserach
    fi
    if systemctl status "filebeat.service" 2> /dev/null | grep -Fq "Active:"; then      
        echo -n "    Checking filebeat service..............."
        sudo systemctl is-active --quiet filebeat.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "metricbeat.service" 2> /dev/null | grep -Fq "Active:"; then    
        echo -n "    Checking metricbeat service............."
        sudo systemctl is-active --quiet metricbeat.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "auditbeat.service" 2> /dev/null | grep -Fq "Active:"; then    
        echo -n "     Checking auditbeat service............."
        sudo systemctl is-active --quiet auditbeat.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "logstash.service" 2> /dev/null | grep -Fq "Active:"; then 
        echo -n "    Checking logstash service..............."
        sudo systemctl is-active --quiet logstash.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "kibana.service" 2> /dev/null | grep -Fq "Active:"; then 
        echo -n "    Checking kibana service................."
        sudo systemctl is-active --quiet kibana.service \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    if systemctl status "nginx.service" 2> /dev/null | grep -Fq "Active:"; then 
        echo -n "    Checking nginx service.................."
        sudo systemctl is-active --quiet nginx \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
    fi
    sleep 1

    # ---- Elastic: Enable back Replica Alocation ---------------------------------
    if [ $es_bool == 1 ]; then 
        echo;echo;
        echo "===================================================================================================="
        echo "====== Elastic: Enable back Replica Alocation on node [$NODE_NAME]"
        echo "===================================================================================================="
        curl -s -X PUT -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" "$URL/_cluster/settings?pretty" -d'{"persistent": {"cluster.routing.allocation.enable": null}}'
        echo "===================================================================================================="
        sleep 1
    fi

    # ---- Nginx: Safety restart --------------------------------------------------
	if systemctl status "nginx.service" 2> /dev/null | grep -Fq "Active:"; then     
        echo;echo;
        echo "===================================================================================================="
        echo "====== Nginx: Safety restart on node [$NODE_NAME]"
        echo "===================================================================================================="
        echo -n "    Restarting nginx service................"
        sudo systemctl restart nginx  \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
        echo "===================================================================================================="
        sleep 1
    fi

    # ---- Metricbeat: Safety restart --------------------------------------------------
	if systemctl status "metricbeat.service" 2> /dev/null | grep -Fq "Active:"; then     
        echo;echo;
        echo "===================================================================================================="
        echo "====== Metricbeat: Safety restart on node [$NODE_NAME]"
        echo "===================================================================================================="
        echo -n "    Restarting Metricbeat Service................"
        sudo systemctl restart metricbeat.service  \
            && echo -e "${GREEN} [OK]. ${NC}" \
            || echo -e "${RED} [ERROR]. ${NC}"
        echo "===================================================================================================="
        sleep 1
    fi

    # ---- Get ES Health ----------------------------------------------------------
    if [ $es_bool == 1 ]; then 
        echo;echo;
        echo "===================================================================================================="
        echo "====== Get ES Health on node [$NODE_NAME]"
        echo "===================================================================================================="
        curl -s -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" "$URL/_cluster/health?pretty" 
        sleep 1
    fi

    # ---- Finish -----------------------------------------------------------------
    echo "===================================================================================================="
    echo; echo; 
    echo "===================================================================================================="
    echo -e "    ${GREEN}Upgrade complete${NC} on node [$NODE_NAME]. Check above for status of upgrade."
    echo "===================================================================================================="
    echo; echo; echo "------------------ Waiting 10s to disconnect from node [$NODE_NAME].... "
    sleep 10
    # End Function ssh_commands_after_reboot ############################
}
#########################################################

# ---- Loop for each node and apply script_body.sh ----------------------------
for NODE in ${NODES} ; do
    if [[ $NODE == $(hostname) || $NODE == $(hostname -s) ]]; then 
        # Local node
        echolog "------------------------ Executing on local node [$NODE] ------------------------------------"
        sleep 2
        #bash script_body_1.sh "$ES_URL" "local" "$ES_USER" "$ES_PASS" "$OPTIONS" | tee -a $LOGFILE
        ssh_commands_before_reboot "$ES_URL" "local" "$ES_USER" "$ES_PASS" "$OPTIONS" | tee -a $LOGFILE
        echolog "------------------------ Completed script on local node [$NODE] -----------------------------"
        sleep 2
    else
        # Remote node
        echolog "------------------------ Connecting to node [$NODE] -----------------------------------------"
        sleep 2
        #ssh ${NODE} -t bash -c "$(printf "%q" "$(< script_body_1.sh )")" -- "$ES_URL" "remote" "$ES_USER" "$ES_PASS" "$OPTIONS" | tee -a $LOGFILE
        ssh -t ${NODE} "$(declare -f ssh_commands_before_reboot); ssh_commands_before_reboot '${ES_URL}' 'remote' '${ES_USER}' '${ES_PASS}' '${OPTIONS}'" | tee -a $LOGFILE
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
            #ssh ${NODE} -t bash -c "$(printf "%q" "$(< script_body_2.sh )")" -- "$ES_URL" "$ES_USER" "$ES_PASS" "$OPTIONS" | tee -a $LOGFILE
            ssh -t ${NODE} "$(declare -f ssh_commands_after_reboot); ssh_commands_after_reboot '${ES_URL}' '${ES_USER}' '${ES_PASS}' '${OPTIONS}'" | tee -a $LOGFILE
        fi
        echolog "------------------------ Disconnecting from node [$NODE] ------------------------------------"
        echolog ""
        sleep 2
    fi
done

# ---- Finaly -----------------------------------------------------------------
echolog; echolog
# Print final warn, err if exists
echolog "--- CHECKING FOR FINAL WARN"
echolog "${FINAL_WARN}"
if [ -n "${FINAL_WARN}" ]; then
    echolog "Final warn: ${FINAL_WARN}" "-e"
    echolog
fi
echolog "===================================================================================================="
echolog "                            Main script ${GREEN}COMPLETED${NC}. " "-e"
echolog "===================================================================================================="
echolog; echolog
# echo "Press [1] to view run.log. Press any other key to finish..."
read -s -n 1 -p "Press [1] to view run.log. Press any other key to finish..."  key
echo; echo
if [[ "$key" == "1" ]]; then
    echo "[1] was pressed. Starting less viewer. Press [q] to exit less..."
    sleep 1
    less -ir $LOGFILE
fi
