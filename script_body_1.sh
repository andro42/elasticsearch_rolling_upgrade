#!/bin/bash

# Params ##################################
URL=$1
REMOTE=$2
ES_USER=$3
ES_PASS=$4
OPTIONS=$5
###########################################

# Body ####################################
NODE_NAME=$(hostname)
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

# ---- Check for arguments ----------------------------------------------------
if [ -z "$URL" ]; then echo -e "${RED}[ERROR]:${NC} Argument ES_URL missing. Check usage."; echo; exit 1; fi;
if [ -z "$REMOTE" ]; then echo -e "${RED}[ERROR]:${NC} Argument REMOTE missing."; echo; exit 1; fi;
if [ -z "$ES_USER" ]; then echo "[WARNING]: Optional Argument ES_USER missing."; fi;
if [ -z "$ES_PASS" ]; then echo "[WARNING]: Optional Argument ES_PASS missing."; fi; 
if [ -z "$OPTIONS" ]; then OPTIONS="null"; fi; 

# ---- Check for elasticsearch service ----------------------------------------
echo;echo;echo -e $_{1..100}"\b="; echo "====== Testing ES connection on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
if [ -f "/etc/init.d/elasticsearch" ]; then 
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
    echo;echo;echo -e $_{1..100}"\b="; echo "====== Checking for ES Cluster Status on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
    # Wait for 10 min checkin for green status
    for i in {0..600}; do
        ES_STATUS=$(curl -s -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" "$URL/_cluster/health?pretty" \
            | grep status | awk '{ print $3 }' | tr -d '"' | tr -d ',')
        if [[ $ES_STATUS == "green" || $ES_STATUS == "503" ]]; then  # 503 - master_not_discovered
            echo -e "    Elasticsearch cluster status: $ES_STATUS................. ${GREEN}[OK].${NC}"
            break
        elif [[ $OPTIONS =~ "status_ignore" ]]; then
            echo "    [WARNING]: Elasticsearch cluster status: $ES_STATUS. [ingore_status] was set so we continue regardless..."
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
                    echo "    [WARNING]: Elasticsearch cluster status: $ES_STATUS. Waiting for green status..."
                fi
            fi
        fi
        sleep 1
    done
    sleep 1
fi

# ---- Check for update and check OS  -----------------------------------------
echo;echo;echo -e $_{1..100}"\b="; echo "====== Checking for updates on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
# Check which OS
if [[ -f /etc/debian_version ]]; then 
    sudo apt update
elif [[ -f /etc/centos-release ]]; then 
    sudo yum check-update
else
    echo -e "    ${RED}ERROR:${NC} Unkown Operating System."; echo
    exit 1
fi
sleep 2

# ---- Elastic: Disable Replica Alocation and Flush ---------------------------
if [ $es_bool == 1 ]; then 
    echo;echo;echo -e $_{1..100}"\b="; echo "====== Elastic: Disable Replica Alocation and Flush on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
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
echo;echo;echo -e $_{1..100}"\b="; echo "====== Stopping ES and related services on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
if [ -f "/etc/init.d/filebeat" ]; then
    echo -n "    Stopping filebeat service..............."
    sudo systemctl stop filebeat.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/metricbeat" ]; then
    echo -n "    Stopping metricbeat service............."
    sudo systemctl stop metricbeat.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/auditbeat" ]; then
    echo -n "    Stopping auditbeat service.............."
    sudo systemctl stop auditbeat.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/logstash" ]; then
    echo -n "    Stopping logstash service..............."
    sudo systemctl stop logstash.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/kibana" ]; then
    echo -n "    Stopping kibana service................."
    sudo systemctl stop kibana.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/nginx" ]; then
    echo -n "    Stopping nginx service.................."
    sudo systemctl stop nginx \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/elasticsearch" ]; then  
    echo -n "    Stopping elasticsearch service.........."
    sudo systemctl stop elasticsearch.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
sleep 1

# ---- System update ----------------------------------------------------------
echo;echo;echo -e $_{1..100}"\b="; echo "====== System update on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
# Check which OS
if [[ -f /etc/debian_version ]]; then 
    #sudo apt upgrade -y
    sudo apt-get -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" upgrade
elif [[ -f /etc/centos-release ]]; then 
    sudo yum update -y
else
    echo -e "    ${RED}ERROR:${NC} Unkown Operating System. Continuoing to start ES services..."; echo
fi
sudo systemctl daemon-reload
sleep 1

# ---- System Reboot if set in Options ---------------------------------
if [[ $OPTIONS =~ "reboot"  ]]; then
    echo;echo;echo -e $_{1..100}"\b="; echo "====== Rebooting the system on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
    # Reboot only remote servers.
    if [ $REMOTE == "remote" ]; then 
        echo -e "    [REBOOT]: System will ${RED}reboot${NC} in 10 seconds. Press CTRL+C to cancel."
        sleep 10
        sudo reboot
    else
        echo "    [WARNING]: Option [reboot] was set, but this is local server. You need to reboot manualy after script completion."
        sleep 2
    fi
fi

# ---- Starting ES and related services ---------------------------------------
echo;echo;echo -e $_{1..100}"\b="; echo "====== Starting ES and related services on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
if [ -f "/etc/init.d/elasticsearch" ]; then
    echo -n "    Starting elasticsearch service.........."
    sudo systemctl start elasticsearch.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
    sleep 5 # Wait for elasticserach
fi
if [ -f "/etc/init.d/filebeat" ]; then       
    echo -n "    Starting filebeat service..............."
    sudo systemctl start filebeat.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/metricbeat" ]; then     
    echo -n "    Starting metricbeat service............."
    sudo systemctl start metricbeat.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/auditbeat" ]; then      
    echo -n "     Starting auditbeat service............."
    sudo systemctl start auditbeat.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/logstash" ]; then
    echo -n "    Starting logstash service..............."
    sudo systemctl start logstash.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/kibana" ]; then
    echo -n "    Starting kibana service................."
    sudo systemctl start kibana.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/nginx" ]; then
    echo -n "    Starting nginx service.................."
    sudo systemctl start nginx \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
sleep 1

# ---- Elastic: Enable back Replica Alocation ---------------------------------
if [ $es_bool == 1 ]; then 
    echo;echo;echo -e $_{1..100}"\b="; echo "====== Elastic: Enable back Replica Alocation on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
    curl -s -X PUT -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" "$URL/_cluster/settings?pretty" -d'{"persistent": {"cluster.routing.allocation.enable": null}}'
    echo -e $_{1..100}"\b="; 
    sleep 1
fi

# ---- Nginx: Safety restart --------------------------------------------------
if [ -f "/etc/init.d/nginx" ]; then
    echo;echo;echo -e $_{1..100}"\b="; echo "====== Nginx: Safety restart on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
    echo -n "    Restarting nginx service................"
    sudo systemctl restart nginx  \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
    echo -e $_{1..100}"\b="; 
    sleep 1
fi

# ---- Get ES Health ----------------------------------------------------------
if [ $es_bool == 1 ]; then 
    echo;echo;echo -e $_{1..100}"\b="; echo "====== Get ES Health on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
    curl -s -k -u "$ES_USER:$ES_PASS" -H "Content-Type: application/json" "$URL/_cluster/health?pretty" 
    sleep 1
fi

# ---- Finish -----------------------------------------------------------------
echo -e $_{1..100}"\b="; 
echo; echo; echo -e $_{1..100}"\b="; echo -e "    ${GREEN}Upgrade complete${NC} on node [$NODE_NAME]. Check above for status of upgrade.";
echo -e $_{1..100}"\b="; 
echo; echo; echo "------------------ Waiting 20s to disconnect from node [$NODE_NAME]. You can CTRL-c to speed-up.... "
sleep 20
# Body End ############################