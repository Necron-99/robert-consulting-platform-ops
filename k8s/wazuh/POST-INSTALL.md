# Wazuh Post-Install Steps

These steps must be run after every fresh install or indexer restart.

## 1. Patch wazuh-register-key ConfigMap (agent registration password)
```bash
kubectl patch configmap wazuh-register-key -n wazuh \
  --type merge \
  -p "{\"data\":{\"authd.pass\":\"$(aws ssm get-parameter \
    --name /robert-consulting/wazuh/agent-registration \
    --with-decryption --query Parameter.Value --output text)\"}}"

kubectl rollout restart statefulset/wazuh-manager-master -n wazuh
kubectl rollout status statefulset/wazuh-manager-master -n wazuh
```

## 2. Apply security config to indexer
```bash
kubectl exec -n wazuh wazuh-indexer-0 -- \
  bash -c "JAVA_HOME=/usr/share/wazuh-indexer/jdk \
  bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
  -cd /usr/share/wazuh-indexer/opensearch-security/ \
  -icl -p 9200 \
  -cacert /usr/share/wazuh-indexer/config/certs/root-ca.pem \
  -cert /usr/share/wazuh-indexer/config/certs/admin.pem \
  -key /usr/share/wazuh-indexer/config/certs/admin-key.pem \
  -nhnv"
```

## 3. Recreate rcadmin if lost
```bash
INDEXER_PASS=$(aws ssm get-parameter \
  --name /robert-consulting/wazuh/indexer-password \
  --with-decryption --query Parameter.Value --output text)

kubectl exec -n wazuh wazuh-indexer-0 -- \
  bash -c "curl -s -k -X PUT \
  'https://localhost:9200/_plugins/_security/api/internalusers/rcadmin' \
  -H 'Content-Type: application/json' \
  -u 'admin:admin' \
  -d '{\"password\": \"$INDEXER_PASS\", \"backend_roles\": [\"admin\"]}'"
```

## 4. Agent installation (Ubuntu)
```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | \
  sudo gpg --no-default-keyring \
  --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg \
  --import && sudo chmod 644 /usr/share/keyrings/wazuh.gpg

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
  https://packages.wazuh.com/4.x/apt/ stable main" | \
  sudo tee /etc/apt/sources.list.d/wazuh.list

sudo apt-get update
sudo WAZUH_MANAGER="116.203.8.108" \
  WAZUH_MANAGER_PORT="32583" \
  WAZUH_REGISTRATION_PASSWORD="<from SSM>" \
  WAZUH_AGENT_GROUP="default" \
  WAZUH_AGENT_NAME="<hostname>" \
  apt-get install -y wazuh-agent

# Fix agent config
sudo sed -i 's|<port>30759</port>|<port>32583</port>|' \
  /var/ossec/etc/ossec.conf

sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

## Credentials (all in SSM /robert-consulting/wazuh/)
- indexer-password: rcadmin dashboard login
- agent-registration: agent enrollment password
- Dashboard URL: https://wazuh.robertconsulting.net
- Login: rcadmin / <indexer-password from SSM>

## NodePorts
- 30759: agent registration (authd)
- 32583: agent events (remoted)
