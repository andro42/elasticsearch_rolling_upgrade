#!/bin/bash

# Params ##################################
URL=$1
ES_USER=$2
ES_PASS=$3
OPTIONS=$4
###########################################

# Body ####################################
NODE_NAME=$(hostname)
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

# ---- Check for arguments ----------------------------------------------------
if [ -z "$URL" ]; then echo -e "${RED}[ERROR]:${NC} Argument ES_URL missing. Check usage."; echo; exit 1; fi;
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
    # After reboot wait max 5 min for ES service to start
    echo "    Waiting max 5 min for Elasticsearch service to start..."
    res=400
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
        sleep 1
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
echo;echo;echo -e $_{1..100}"\b="; echo "====== Checking for ES and related services on node [$NODE_NAME]"; echo -e $_{1..100}"\b=";
if [ -f "/etc/init.d/elasticsearch" ]; then
    echo -n "    Checking elasticsearch service.........."
    sudo systemctl is-active --quiet elasticsearch.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
    sleep 5 # Wait for elasticserach
fi
if [ -f "/etc/init.d/filebeat" ]; then       
    echo -n "    Checking filebeat service..............."
    sudo systemctl is-active --quiet filebeat.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/metricbeat" ]; then     
    echo -n "    Checking metricbeat service............."
    sudo systemctl is-active --quiet metricbeat.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/auditbeat" ]; then      
    echo -n "     Checking auditbeat service............."
    sudo systemctl is-active --quiet auditbeat.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/logstash" ]; then
    echo -n "    Checking logstash service..............."
    sudo systemctl is-active --quiet logstash.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/kibana" ]; then
    echo -n "    Checking kibana service................."
    sudo systemctl is-active --quiet kibana.service \
        && echo -e "${GREEN} [OK]. ${NC}" \
        || echo -e "${RED} [ERROR]. ${NC}"
fi
if [ -f "/etc/init.d/nginx" ]; then
    echo -n "    Checking nginx service.................."
    sudo systemctl is-active --quiet nginx \
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