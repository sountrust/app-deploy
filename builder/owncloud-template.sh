#!/bin/bash

# Check if the correct number of arguments were provided
if [ "$#" -ne 7 ]; then
    echo "Usage: $0 <Namespace> <Release Name> <Persistence Volume Size ex: 2Gi> <OwnCloud Host> <OwnCloud Password> <API Token> <Replicas>"
    exit 1
fi

# Assign arguments to variables
namespace=$1
releaseName=$2
pvcSize=$3
owncloudUrl=$4
adminPassword=$5
apiToken=$6
replicas=$7

# Define other fixed variables
mariadbImage="docker.io/bitnami/mariadb:11.2"
owncloudImage="your-repo/owncloud:latest"
storageClass="your-storage-class"
adminEmail="admin@example.com"

# Create directory structure
mkdir -p ../owncloud-manifests/$namespace/$releaseName
cd ../owncloud-manifests/$namespace/$releaseName

# Create Namespace file (if not existing)
if [ ! -f ../namespace.yaml ]; then
    cat <<EOF > ../namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace
EOF
fi

# PVC for "data" with adjustable size
cat <<EOF > ${releaseName}-owncloud-data.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${releaseName}-owncloud-data
  namespace: $namespace
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: $storageClass
  resources:
    requests:
      storage: $pvcSize
EOF

# Create PVC files for "data" and "db"
declare -a suffixes=("db" "redis")
declare -A accessModes=( ["redis"]="ReadWriteMany" ["db"]="ReadWriteOnce" )

# Create PVC files for each required volume
for suffix in "${suffixes[@]}"; do
    cat <<EOF > ${releaseName}-owncloud-${suffix}.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${releaseName}-owncloud-${suffix}
  namespace: $namespace
spec:
  accessModes:
    - ${accessModes[$suffix]}
  storageClassName: $storageClass
  resources:
    requests:
      storage: 256Mi
EOF
done

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
          value: cloud_owncloud
        - name: MARIADB_DATABASE
          value: cloud_owncloud
        - name: MARIADB_PASSWORD
          value: cloud123
        volumeMounts:
        - name: ${releaseName}-mariadb-db
          mountPath: /bitnami/mariadb
      volumes:
      - name: ${releaseName}-mariadb-db
        persistentVolumeClaim:
          claimName: ${releaseName}-owncloud-db
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

# Create owncloud Deployment file
cat <<EOF > ${releaseName}-owncloud-deployment.yaml
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
      - name: owncloud
        image: $owncloudImage
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        - containerPort: 443
        env:
        - name: OWNCLOUD_DOMAIN
          value: "$owncloudUrl"
        - name: OWNCLOUD_DB_TYPE
          value: "mysql"
        - name: OWNCLOUD_TRUSTED_DOMAINS
          value: $owncloudUrl
        - name: OWNCLOUD_DB_HOST
          value: ${releaseName}-mariadb.${namespace}.svc.cluster.local
        - name: OWNCLOUD_DB_NAME
          value: "cloud_owncloud"
        - name: OWNCLOUD_DB_USERNAME
          value: "cloud_owncloud"
        - name: OWNCLOUD_DB_PASSWORD
          value: "cloud123"
        - name: OWNCLOUD_ADMIN_USERNAME
          value: "$adminEmail"
        - name: OWNCLOUD_MYSQL_UTF8MB4
          value: "true"
        - name: OWNCLOUD_ADMIN_PASSWORD
          value: "$adminPassword"
        - name: OWNCLOUD_REDIS_ENABLED
          value: "true"
        - name: OWNCLOUD_REDIS_HOST
          value: ${releaseName}-redis.${namespace}.svc.cluster.local
        - name: API_TOKEN
          value: "$apiToken"
        volumeMounts:
        - name: ${releaseName}-app-data
          mountPath: /mnt/data
      volumes:
      - name: ${releaseName}-app-data
        persistentVolumeClaim:
          claimName: ${releaseName}-owncloud-data
EOF

# Create Service file for owncloud
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

# Create redis deployment
cat <<EOF > ${releaseName}-redis-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $releaseName-redis
  labels:
    app: $releaseName-redis
  namespace: $namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $releaseName-redis
  template:
    metadata:
      labels:
        app: $releaseName-redis
    spec:
      containers:
      - name: redis
        image: redis:6
        securityContext:
          runAsUser: 0
        args: ["--databases", "1"]
        ports:
        - containerPort: 6379
        readinessProbe:
          exec:
            command: ["redis-cli", "ping"]
          initialDelaySeconds: 15
          timeoutSeconds: 5
        livenessProbe:
          exec:
            command: ["redis-cli", "ping"]
          initialDelaySeconds: 20
          timeoutSeconds: 5
        volumeMounts:
        - name: ${releaseName}-redis-data
          mountPath: /data
      volumes:
      - name: ${releaseName}-redis-data
        persistentVolumeClaim:
          claimName: ${releaseName}-owncloud-redis
EOF

# Create redis service
cat <<EOF > ${releaseName}-redis-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ${releaseName}-redis
  namespace: $namespace
spec:
  ports:
  - port: 6379
    targetPort: 6379
    protocol: TCP
  selector:
    app: $releaseName-redis
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
    - "$owncloudUrl"
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
  - host: $owncloudUrl
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
    - "$owncloudUrl"
    secretName: ${releaseName}-tls
EOF

cd ../
# Add changes to git, assuming '../owncloud-manifests' is at the root of your Git repository
git add .
git commit -m "Updated owncloud deployment $releaseName in $namespace namespace"
git push

echo "owncloud manifests for $releaseName have been updated in ../owncloud-manifests/$namespace/$releaseName and pushed to the Git repository"
