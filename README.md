# elasticsearch_rolling_upgrade
## Rolling Upgrade of Elasticsearch Cluster

Bash script that performs a rolling upgrade of an Elasticsearch cluster. It's great for keeping your cluster automatically patched without downtime.

Script uses ssh to connect to other nodes.

It's tested with Elasticsearch version 7.15 on premise. Using this article as a guideline: https://www.elastic.co/guide/en/elasticsearch/reference/current/rolling-upgrades.html 

### Usage:
```bash
bash upgrade_elasticsearch.sh NODES ES_URL ES_USER ES_PASS
```
Example:
```bash
bash upgrade_elasticsearch.sh "es_node01 es_node02 es_node3" "https://localhost:9200" "user" "securepassword"
```

### Prerequisites:
- Centos or debian based linux operating system
- ssh
- Elasticsearch cluster or stand-alone

### Not yet supported features:
- Connecting without user and pass
- Upgrade only system packages
- OS reboot
