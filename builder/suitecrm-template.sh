#!/bin/bash

# Check if the correct number of arguments were provided
if [ "$#" -ne 7 ]; then
    echo "Usage: $0 <Namespace> <Release Name> <Persistence Volume Size ex: 8Gi> <SuiteCRM URL> <SuiteCRM Password> <API Token> <Replicas>"
    exit 1
fi

# Assign arguments to variables
namespace=$1
releaseName=$2
pvcSize=$3
suitecrmUrl=$4
adminPassword=$5
apiToken=$6
replicas=$7

# Define other fixed variables
mariadbImage="docker.io/bitnami/mariadb:11.2"
suitecrmImage="your-repo/suitecrm:latest"
storageClass="your-storage-class"
adminEmail="admin@example.com"

# Create directory structure
mkdir -p ../suitecrm-manifests/$namespace/$releaseName
cd ../suitecrm-manifests/$namespace/$releaseName

# Create Namespace file (if not existing)
if [ ! -f ../namespace.yaml ]; then
    cat <<EOF > ../namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace
EOF
fi

# Create PVC files for "data" and "db"
# Create PVC files for data required volume
cat <<EOF > ${releaseName}-suitecrm-data.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${releaseName}-suitecrm-data
  namespace: $namespace
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: $storageClass
  resources:
    requests:
      storage: $pvcSize
EOF

# Create PVC files for db required volume
cat <<EOF > ${releaseName}-suitecrm-db.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${releaseName}-suitecrm-db
  namespace: $namespace
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $storageClass
  resources:
    requests:
      storage: 256Mi
EOF

# Create Mariadb Deployment file
cat <<EOF > ${releaseName}-mariadb-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${releaseName}-mariadb
  namespace: $namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${releaseName}-mariadb
  template:
    metadata:
      labels:
        app: ${releaseName}-mariadb
    spec:
      containers:
      - name: mariadb
        image: $mariadbImage
        ports:
        - containerPort: 3306
        env:
        - name: ALLOW_EMPTY_PASSWORD
          value: "yes"
        - name: MARIADB_USER
          value: cloud_suitecrm
        - name: MARIADB_DATABASE
          value: cloud_suitecrm
        - name: MARIADB_PASSWORD
          value: cloud123
        volumeMounts:
        - name: ${releaseName}-mariadb-db
          mountPath: /bitnami/mariadb
      volumes:
      - name: ${releaseName}-mariadb-db
        persistentVolumeClaim:
          claimName: ${releaseName}-suitecrm-db
EOF

# Create Mariadb Service file
cat <<EOF > ${releaseName}-mariadb-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ${releaseName}-mariadb
  namespace: $namespace
spec:
  ports:
  - port: 3306
    targetPort: 3306
    protocol: TCP
    name: mariadb
  selector:
    app: ${releaseName}-mariadb
EOF

# Create SuiteCRM Deployment file
cat <<EOF > ${releaseName}-suitecrm-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $releaseName
  namespace: $namespace
spec:
  replicas: $replicas
  selector:
    matchLabels:
      app: $releaseName
  template:
    metadata:
      labels:
        app: $releaseName
    spec:
      containers:
      - name: suitecrm
        image: $suitecrmImage
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        - containerPort: 8443
        env:
        - name: SUITECRM_DATABASE_HOST
          value: ${releaseName}-mariadb.${namespace}.svc.cluster.local
        - name: SUITECRM_DATABASE_NAME
          value: "cloud_suitecrm"
        - name: SUITECRM_DATABASE_USER
          value: "cloud_suitecrm"
        - name: SUITECRM_DATABASE_PASSWORD
          value: "cloud123"
        - name: ALLOW_EMPTY_PASSWORD
          value: "no"
        - name: SUITECRM_DATABASE_PORT_NUMBER
          value: "3306"
        - name: SUITECRM_USERNAME
          value: "$adminEmail"
        - name: SUITECRM_PASSWORD
          value: "$adminPassword"
        - name: API_TOKEN
          value: "$apiToken"
        volumeMounts:
        - name: ${releaseName}-app-data
          mountPath: /bitnami/data
      volumes:
      - name: ${releaseName}-app-data
        persistentVolumeClaim:
          claimName: ${releaseName}-suitecrm-data
EOF

# Create Service file for SuiteCRM
cat <<EOF > ${releaseName}-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: $releaseName
  namespace: $namespace
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: $releaseName
EOF

# Create Certificate for TLS
cat <<EOF > ${releaseName}-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${releaseName}-tls
  namespace: $namespace
spec:
  secretName: ${releaseName}-tls
  issuerRef:
    name: acme-issuer
    kind: ClusterIssuer
  dnsNames:
    - "$suitecrmUrl"
EOF

# Create Ingress file
cat <<EOF > ${releaseName}-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $releaseName
  namespace: $namespace
  annotations:
    kubernetes.io/ingress.class: "traefik"
spec:
  rules:
  - host: $suitecrmUrl
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $releaseName
            port:
              number: 80
  tls:
  - hosts:
    - "$suitecrmUrl"
    secretName: ${releaseName}-tls
EOF

cd ../
# Add changes to git, assuming '../suitecrm-manifests' is at the root of your Git repository
git add .
git commit -m "Updated SuiteCRM deployment $releaseName in $namespace namespace"
git push

echo "SuiteCRM manifests for $releaseName have been updated in ../suitecrm-manifests/$namespace/$releaseName and pushed to the Git repository"
