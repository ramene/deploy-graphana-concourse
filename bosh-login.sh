#!/bin/bash

source ./env

export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=`$BOSH_CMD int ./$BOSH_ALIAS/creds.yml --path /admin_password`
