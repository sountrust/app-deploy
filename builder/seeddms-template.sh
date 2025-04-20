#!/bin/bash

# Check if the correct number of arguments were provided
if [ "$#" -ne 7 ]; then
    echo "Usage: $0 <Namespace> <Release Name> <PVC Size> <SeedDMS URL> <Admin Password> <API Token> <Replicas>"
    exit 1
fi

# Assign arguments to variables
namespace=$1
releaseName=$2
pvcSize=$3
seedDmsUrl=$4
adminPassword=$5
apiToken=$6
replicas=$7

# Define other fixed variables
mariadbImage="docker.io/bitnami/mariadb:11.2"
seedDmsImage="your-repo/seeddms:latest"
storageClass="your-storage-class"
encKey="your-encryption-key"
adminEmail="admin@example.com"

# Create directory structure
mkdir -p ../seeddms-manifests/$namespace/$releaseName
cd ../seeddms-manifests/$namespace/$releaseName

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
cat <<EOF > ${releaseName}-seeddms-data.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${releaseName}-seeddms-data
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
cat <<EOF > ${releaseName}-seeddms-db.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${releaseName}-seeddms-db
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
          value: cloud_seeddms
        - name: MARIADB_DATABASE
          value: cloud_seeddms
        - name: MARIADB_PASSWORD
          value: cloud123
        volumeMounts:
        - name: ${releaseName}-mariadb-db
          mountPath: /bitnami/mariadb
      volumes:
      - name: ${releaseName}-mariadb-db
        persistentVolumeClaim:
          claimName: ${releaseName}-seeddms-db
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

# Create SeedDMS Deployment file
cat <<EOF > ${releaseName}-seeddms-deployment.yaml
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
      securityContext:
        fsGroup: 65534  # GID for 'nobody' in Alpine
      initContainers:
      - name: init-seeddms
        image: alpine
        command:
        - sh
        - -c
        - |
          mkdir -p /mnt/data/1048576 /mnt/data/backup /mnt/data/cache /mnt/data/log /mnt/data/lucene /mnt/data/staging
          chown -R 65534:65534 /mnt/data/1048576 /mnt/data/backup /mnt/data/cache /mnt/data/log /mnt/data/lucene /mnt/data/staging
        volumeMounts:
        - name: ${releaseName}-app-data
          mountPath: /mnt/data
      containers:
      - name: seeddms
        image: $seedDmsImage
        imagePullPolicy: Always
        ports:
        - containerPort: 80
        - containerPort: 443
        env:
        - name: ENC_KEY
          value: $encKey
        - name: DB_DRIVER
          value: mysql
        - name: DB_HOSTNAME
          value: ${releaseName}-mariadb.${namespace}.svc.cluster.local
        - name: DB_DATABASE
          value: cloud_seeddms
        - name: DB_USER
          value: cloud_seeddms
        - name: DB_PASS
          value: cloud123
        - name: ADMIN_EMAIL
          value: "$adminEmail"
        - name: ADMIN_PASSWORD
          value: "$adminPassword"
        - name: API_TOKEN
          value: "$apiToken"
        volumeMounts:
        - name: ${releaseName}-app-data
          mountPath: /var/data
        - name: ${releaseName}-app-ssl
          mountPath: /etc/nginx/ssl
          readOnly: true
      volumes:
      - name: ${releaseName}-app-data
        persistentVolumeClaim:
          claimName: ${releaseName}-seeddms-data
      - name: ${releaseName}-app-ssl
        secret:
          secretName: ${releaseName}-tls
EOF

# Create Service file for SeedDMS
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
    targetPort: 80
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
    - "$seedDmsUrl"
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
  - host: $seedDmsUrl
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
    - "$seedDmsUrl"
    secretName: ${releaseName}-tls
EOF

cd ../
# Add changes to git, assuming '../seeddms-manifests' is at the root of your Git repository
git add .
git commit -m "Updated SeedDMS deployment $releaseName in $namespace namespace"
git push

echo "SeedDMS manifests for $releaseName have been updated in ../seeddms-manifests/$namespace/$releaseName and pushed to the Git repository"
