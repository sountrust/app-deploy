# 🧩 Kube-Deploy – Application Auto-Deployment Manifests

This directory enables automated manifest generation and Git-based application lifecycle management for all managed applications in the VCloud Director.

---

## 📦 Structure

```
kube-deploy/
├── builder/                   # Shell scripts for generating manifests
│   ├── owncloud-template.sh
│   ├── auto-deploy-owncloud-manifest.sh
│   ├── auto-pause-backup-manifest.sh
│   ├── seeddms-template.sh
│   ├── auto-deploy-seeddms-manifest.sh
│   ├── auto-pause-ged-manifest.sh
│   ├── suitecrm-template.sh
│   ├── auto-deploy-suitecrm-manifest.sh
│   ├── auto-pause-suitecrm-manifest.sh
├── owncloud-manifests/
├── seeddms-manifests/
└── suitecrm-manifests/
```

---

## 🚀 Application Deployment – Overview

Each supported application (OwnCloud, SeedDMS, SuiteCRM) follows a similar lifecycle model:

1. **Deployment**: Using a `auto-deploy-<app>-manifest.sh` script, you create manifests by providing runtime arguments such as namespace, hostname, volume size, etc.
2. **Pause/Deactivate**: Set `replicas=0` using `auto-pause-<app>.sh` scripts to stop the application while keeping PVC and database intact.
3. **Data Persistence**: All apps use a specified storage class and generate PVCs automatically.
4. **GitOps Workflow**: Manifests are committed and pushed to the repo. Git is the source of truth for app state.

---

## 🛠️ OwnCloud Deployment Logic

Scripts:
- `auto-deploy-owncloud-manifest.sh`
- `auto-pause-backup-manifest.sh`
- `owncloud-template.sh`

Deployment behavior:
- Creates namespace, PVCs for app, db, redis
- Deploys MariaDB + OwnCloud + Redis
- Adds a TLS Certificate and Traefik Ingress
- Pushes manifests to Git repo under `owncloud-manifests/<namespace>/<release>`

Replicas can be scaled (0 or 1) based on user status (active/inactive).

---

## 🗂️ SeedDMS Deployment Logic

Scripts:
- `auto-deploy-seeddms-manifest.sh`
- `auto-pause-ged-manifest.sh`
- `seeddms-template.sh`

Behavior:
- Creates namespace, PVCs for data and DB
- Deploys MariaDB and SeedDMS containers
- Sets custom encryption key (`ENC_KEY`)
- Mounts `/var/data` and `/etc/nginx/ssl`
- Generates full TLS Ingress and Service YAMLs

Git commit/push finalizes deployment.

---

## 💼 SuiteCRM Deployment Logic

Scripts:
- `auto-deploy-suitecrm-manifest.sh`
- `auto-pause-suitecrm-manifest.sh`
- `suitecrm-template.sh`

Behavior:
- Uses Bitnami SuiteCRM + MariaDB containers
- Mounts `/bitnami/data` for CRM persistence
- Injects `API_TOKEN` for management API integration
- All Kubernetes resources generated and pushed under `suitecrm-manifests/<namespace>/<release>`

Replicas (0/1) reflect user access or plan lifecycle status.
