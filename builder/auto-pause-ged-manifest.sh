#!/bin/bash

# Check if the correct number of arguments were provided
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <Namespace> <Release Name> <PVC Size> <SeedDMS URL> <Admin Password> <API Token>"
    exit 1
fi

# Assign arguments to variables
namespace=$1
releaseName=$2
pvcSize=$3
seedDmsUrl=$4
adminPassword=$5
helpApiToken=$6

# Set replicas to 1
replicas=0

# Call the owncloud-template.sh script with the additional replicas parameter
./owncloud-template.sh "$namespace" "$releaseName" "$pvcSize" "$seedDmsUrl" "$adminPassword" "$helpApiToken" "$replicas"



