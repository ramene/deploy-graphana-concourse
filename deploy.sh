#!/bin/bash -ex

if [[ "$FOUNDATION" != "" ]]; then
  echo "sourcing $PWD/$FOUNDATION-env...."
  source $PWD/$FOUNDATION-env
else
  echo "sourcing $PWD/env...."
  source $PWD/env
fi

mkdir -p $BOSH_ALIAS

$BOSH_CMD create-env vsphere/bosh.yml \
  --state=$BOSH_ALIAS/state.json \
  --vars-store=$BOSH_ALIAS/creds.yml \
  -o vsphere/cpi.yml \
  -o vsphere/resource-pool.yml \
  -o vsphere/jumpbox-user.yml \
  -v director_name=$BOSH_ALIAS \
  -v internal_cidr=$NETWORK_CIDR \
  -v internal_gw=$NETWORK_GATEWAY \
  -v internal_ip=$BOSH_IP \
  -v dns_servers=$DNS_SERVERS \
  -v network_name="$VCENTER_NETWORK_NAME" \
  -v vcenter_dc=$VSPHERE_DATACENTER \
  -v vcenter_ds=$VCENTER_STORAGE_NAME \
  -v vcenter_ip=$VCENTER_IP \
  -v vcenter_user=$VCENTER_USERNAME \
  -v vcenter_password=$VCENTER_PASSWORD \
  -v vcenter_templates=$VCENTER_VM_TEMPLATES_FOLDER_NAME \
  -v vcenter_vms=$VCENTER_VMS_FOLDER_NAME \
  -v vcenter_disks=$VCENTER_DISK_FOLDER_NAME \
  -v vcenter_cluster=$VCENTER_CLUSTER_NAME \
  -v vcenter_rp=$VCENTER_RESOURCE_POOL \
  -v bosh_release_url=$BOSH_RELEASE_URL \
  -v bosh_release_sha=$BOSH_RELEASE_SHA \
  -v vsphere_cpi_url=$VSPHERE_CPI_URL \
  -v vsphere_cpi_sha=$VSPHERE_CPI_SHA \
  -v stemcell_url=$STEMCELL_URL \
  -v stemcell_sha=$STEMCELL_SHA \
  -v os_conf_release_url=$OS_CONF_RELEASE_URL \
  -v os_conf_release_sha=$OS_CONF_RELEASE_SHA

export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=`$BOSH_CMD int ./$BOSH_ALIAS/creds.yml --path /admin_password`

$BOSH_CMD -e $BOSH_IP --ca-cert <($BOSH_CMD int ./$BOSH_ALIAS/creds.yml --path /director_ssl/ca) alias-env $BOSH_ALIAS

$BOSH_CMD -e $BOSH_ALIAS -n update-cloud-config vsphere/cloud-config.yml \
  -v concourse_az_name=$CONCOURSE_AZ_NAME \
  -v concourse_nw_name=$CONCOURSE_NW_NAME \
  -v vcenter_cluster=$VCENTER_CLUSTER_NAME \
  -v network_cidr=$NETWORK_CIDR \
  -v network_name=$VCENTER_NETWORK_NAME \
  -v network_gateway=$NETWORK_GATEWAY \
  -v dns_servers=$DNS_SERVERS \
  -v reserved_ips=$RESERVED_IPS \
  -v static_ips=$CLOUD_CONFIG_STATIC_IPS \
  -v vcenter_rp=$VCENTER_RESOURCE_POOL

if [[ "$BOSH_INTERNET_CONNECTIVITY" == "false" ]]; then
  if [ ! -f concourse.tgz ]; then
    wget -O concourse.tgz https://bosh.io/d/github.com/concourse/concourse
  fi
  $BOSH_CMD -e $BOSH_ALIAS -n upload-release concourse.tgz

  if [ ! -f garden-runc-release.tgz ]; then
    wget -O garden-runc-release.tgz https://bosh.io/d/github.com/cloudfoundry/garden-runc-release
  fi
  $BOSH_CMD -e $BOSH_ALIAS -n upload-release garden-runc-release.tgz

  if [ ! -f consul-boshrelease.tgz ]; then
    wget -O consul-boshrelease.tgz https://bosh.io/d/github.com/cloudfoundry-community/consul-boshrelease
  fi
  $BOSH_CMD -e $BOSH_ALIAS -n upload-release consul-boshrelease.tgz

  if [ ! -f vault-boshrelease.tgz ]; then
    wget -O vault-boshrelease.tgz https://bosh.io/d/github.com/cloudfoundry-community/vault-boshrelease
  fi
  $BOSH_CMD -e $BOSH_ALIAS -n upload-release vault-boshrelease.tgz
else
  $BOSH_CMD -e $BOSH_ALIAS -n upload-release https://bosh.io/d/github.com/concourse/concourse
  $BOSH_CMD -e $BOSH_ALIAS -n upload-release https://bosh.io/d/github.com/cloudfoundry/garden-runc-release
  $BOSH_CMD -e $BOSH_ALIAS -n upload-release https://bosh.io/d/github.com/cloudfoundry-community/consul-boshrelease
  $BOSH_CMD -e $BOSH_ALIAS -n upload-release https://bosh.io/d/github.com/cloudfoundry-community/vault-boshrelease
fi

if [[ ! -f "bosh-stemcell-$SC_VERSION-vsphere-esxi-ubuntu-trusty-go_agent.tgz" ]]; then
  wget https://s3.amazonaws.com/bosh-core-stemcells/vsphere/bosh-stemcell-$SC_VERSION-vsphere-esxi-ubuntu-trusty-go_agent.tgz
fi

$BOSH_CMD -e $BOSH_ALIAS -n upload-stemcell bosh-stemcell-$SC_VERSION-vsphere-esxi-ubuntu-trusty-go_agent.tgz

##### VAULT DEPLOYMENT START #####
VAULT_TLS_FLAGS="--vars-store vault-tls.yml"
if [[ ! -z $VAULT_SERVER_CERT_FILENAME ]]; then
  VAULT_TLS_FLAGS="--var-file vault-tls.certificate=$VAULT_SERVER_CERT_FILENAME --var-file vault-tls.private_key=$VAULT_PRIVATE_KEY_FILENAME"
  echo "Using provided Vault cert"
else
  echo "Generating cert for Vault"
fi

$BOSH_CMD -e $BOSH_ALIAS -n -d $VAULT_CMD deploy vault.yml \
  -v VAULT_AZ_NAME=$VAULT_AZ_NAME \
  -v VAULT_NW_NAME=$VAULT_NW_NAME \
  -v STATIC_IPS=$VAULT_STATIC_IPS \
  -v VAULT_INSTANCES=$VAULT_INSTANCES \
  -v VAULT_VM_TYPE=$VAULT_VM_TYPE \
  -v VAULT_DISK_TYPE=$VAULT_DISK_TYPE \
  -v LOAD_BALANCER_URL=$VAULT_LOAD_BALANCER_URL \
  -v VAULT_TCP_PORT=$VAULT_TCP_PORT \
  $VAULT_TLS_FLAGS
##### VAULT DEPLOYMENT END #####

##### VAULT CONFIGURATION START #####
# Initialize vault

set +e
IS_VAULT_INTIALIZED=$(curl -m 10 -s -o /dev/null -w "%{http_code}" $VAULT_ADDR/v1/sys/health)
set -e

if [ $IS_VAULT_INTIALIZED -eq 501 ]; then
  echo "Initalizing Vault"
  VAULT_INIT_RESPONSE=$($VAULT_CMD init)

  rm -rf ./$BOSH_ALIAS/vault.log

  echo "$VAULT_INIT_RESPONSE" >> ./$BOSH_ALIAS/vault.log

  # Unseal the vault
  set +x
  export VAULT_TOKEN=$(cat ./$BOSH_ALIAS/vault.log | grep 'Initial Root Token' | awk '{print $4}')

  $VAULT_CMD unseal $(cat ./$BOSH_ALIAS/vault.log | grep 'Unseal Key 1' | awk '{print $4}')
  $VAULT_CMD unseal $(cat ./$BOSH_ALIAS/vault.log | grep 'Unseal Key 2' | awk '{print $4}')
  $VAULT_CMD unseal $(cat ./$BOSH_ALIAS/vault.log | grep 'Unseal Key 3' | awk '{print $4}')
  set -x
elif [ $IS_VAULT_INTIALIZED -eq 503 ]; then
  # Unseal the vault
  echo "Unsealing vault"
  set +x
  export VAULT_TOKEN=$(cat ./$BOSH_ALIAS/vault.log | grep 'Initial Root Token' | awk '{print $4}')

  $VAULT_CMD unseal $(cat ./$BOSH_ALIAS/vault.log | grep 'Unseal Key 1' | awk '{print $4}')
  $VAULT_CMD unseal $(cat ./$BOSH_ALIAS/vault.log | grep 'Unseal Key 2' | awk '{print $4}')
  $VAULT_CMD unseal $(cat ./$BOSH_ALIAS/vault.log | grep 'Unseal Key 3' | awk '{print $4}')
  set -x
elif [ $IS_VAULT_INTIALIZED -eq 500 ]; then
  echo "Vault is hosed.. troubleshoot it using bosh commands"
  exit 1
elif [ $IS_VAULT_INTIALIZED -eq 000 ]; then
  echo "Unable to connect to $VAULT_ADDR.. Could be DNS, or certificates error"
  exit 1
else
  echo "Vault already initialized and hence skipping this step"
fi

### Token based authentication ###
# Create a token with the specified policy

## Approle based authentication ###
# $VAULT_CMD auth-enable approle
# $VAULT_CMD write auth/approle/role/$ROLE_NAME policies=$VAULT_POLICY_NAME -period="87600h"
# export ROLE_ID=$($VAULT_CMD read -format=json auth/approle/role/$ROLE_NAME/role-id | $JQ_CMD .data.role_id | tr -d '"')
# export SECRET_ID=$($VAULT_CMD write -format=json -f auth/approle/role/$ROLE_NAME/secret-id | $JQ_CMD .data.secret_id | tr -d '"')
# export CLIENT_TOKEN=$($VAULT_CMD write -format=json auth/approle/login role_id=$ROLE_ID secret_id=$SECRET_ID | $JQ_CMD .auth.client_token | tr -d '"')

#### VAULT CONFIGURATION END #####

if [[ ! -e ./$BOSH_ALIAS/create_token_response.json ]]; then
  # Create a mount for concourse
  $VAULT_CMD mount -path=$CONCOURSE_VAULT_MOUNT -description="Secrets for use by concourse pipelines" generic

  # Create application policy
  $VAULT_CMD policy-write $VAULT_POLICY_NAME vault-policy.hcl
  CREATE_TOKEN_RESPONSE=$($VAULT_CMD token-create --policy=$VAULT_POLICY_NAME -period="87600h" -format=json)
  rm -rf ./$BOSH_ALIAS/create_token_response.json
  echo $CREATE_TOKEN_RESPONSE > ./$BOSH_ALIAS/create_token_response.json
fi

CLIENT_TOKEN=$(cat ./$BOSH_ALIAS/create_token_response.json | $JQ_CMD .auth.client_token | tr -d '"')

#### CONCOURSE DEPLOYMENT START #####
$BOSH_CMD -e $BOSH_ALIAS -n -d concourse deploy concourse.yml \
  -v CONCOURSE_AZ_NAME=$CONCOURSE_AZ_NAME \
  -v CONCOURSE_NW_NAME=$CONCOURSE_NW_NAME \
  -v ATC_STATIC_IPS=$CONCOURSE_WEB_STATIC_IPS \
  -v DB_STATIC_IPS=$CONCOURSE_DB_STATIC_IPS \
  -v WORKER_STATIC_IPS=$CONCOURSE_WORKER_STATIC_IPS \
  -v CONCOURSE_EXTERNAL_URL=$CONCOURSE_EXTERNAL_URL \
  -v VAULT_ADDR=$VAULT_ADDR \
  -v CLIENT_TOKEN=$CLIENT_TOKEN \
  -v CONCOURSE_VAULT_MOUNT=$CONCOURSE_VAULT_MOUNT \
  -v CONCOURSE_ADMIN_USERNAME=$CONCOURSE_ADMIN_USERNAME \
  -v CONCOURSE_ADMIN_PASSWORD=$CONCOURSE_ADMIN_PASSWORD \
  -v ATC_WEB_INSTANCES=$ATC_WEB_INSTANCES \
  -v ATC_WEB_VM_TYPE=$ATC_WEB_VM_TYPE \
  -v CONCOURSE_DB_INSTANCES=$CONCOURSE_DB_INSTANCES \
  -v CONCOURSE_DB_VM_TYPE=$CONCOURSE_DB_VM_TYPE \
  -v CONCOURSE_DB_PERSISTENT_DISK_TYPE=$CONCOURSE_DB_PERSISTENT_DISK_TYPE \
  -v CONCOURSE_WORKER_INSTANCES=$CONCOURSE_WORKER_INSTANCES \
  -v CONCOURSE_WORKER_VM_TYPE=$CONCOURSE_WORKER_VM_TYPE
  # -v BACKEND_ROLE=$BACKEND_ROLE \
  # -v ROLE_ID=$ROLE_ID \
  # -v SECRET_ID=$SECRET_ID
##### CONCOURSE DEPLOYMENT END #####

$BOSH_CMD -e $BOSH_ALIAS -n -d nexus deploy nexus.yml \
  -v NEXUS_AZ_NAME=$NEXUS_AZ_NAME \
  -v NEXUS_NW_NAME=$NEXUS_NW_NAME \
  -v NEXUS_INSTANCES=$NEXUS_INSTANCES \
  -v NEXUS_VM_TYPE=$NEXUS_VM_TYPE \
  -v STATIC_IPS=$NEXUS_STATIC_IPS

$BOSH_CMD -e $BOSH_ALIAS clean-up --all -n
