#!/bin/bash

if [[ "$FOUNDATION" != "" ]]; then
  echo "sourcing $PWD/$FOUNDATION-env...."
  source $PWD/$FOUNDATION-env
else
  echo "sourcing $PWD/env...."
  source $PWD/env
fi

export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=`$BOSH_CMD int ./$BOSH_ALIAS/creds.yml --path /admin_password`
$BOSH_CMD -e $BOSH_IP --ca-cert <($BOSH_CMD int ./$BOSH_ALIAS/creds.yml --path /director_ssl/ca) alias-env $BOSH_ALIAS

$BOSH_CMD delete-deployment -e $BOSH_ALIAS -d nexus -n

$BOSH_CMD delete-deployment -e $BOSH_ALIAS -d concourse -n

$BOSH_CMD delete-deployment -e $BOSH_ALIAS -d vault -n

$BOSH_CMD delete-env vsphere/bosh.yml \
    --state=$BOSH_ALIAS/state.json \
    --vars-store=$BOSH_ALIAS/creds.yml \
    -o vsphere/cpi.yml \
    -o vsphere/resource-pool.yml \
    -v director_name=bosh-concourse \
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
    -v stemcell_sha=$STEMCELL_SHA

rm -rf ./$BOSH_ALIAS
