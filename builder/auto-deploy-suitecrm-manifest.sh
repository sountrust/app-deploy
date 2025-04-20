#!/bin/bash

# Check if the correct number of arguments were provided
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <Namespace> <Release Name> <Persistance Volume Size ex: 8Gi> <suitecrm Host> <suitecrm Password> <API Token>"
    exit 1
fi

# Assign arguments to variables
namespace=$1
releaseName=$2
pvcSize=$3
suitecrmUrl=$4
adminPassword=$5
helpApiToken=$6

# Set replicas to 1
replicas=1

# Call the owncloud-template.sh script with the additional replicas parameter
./suitecrm-template.sh "$namespace" "$releaseName" "$pvcSize" "$suitecrmUrl" "$adminPassword" "$helpApiToken" "$replicas"


