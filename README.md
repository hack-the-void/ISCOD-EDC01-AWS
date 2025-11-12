# ☁️ MediTrack – Étude de cas ISCOD

Projet réalisé dans le cadre de la formation **Administrateur Système DevOps (ISCOD)**.  
L’objectif : **automatiser le déploiement d’une infrastructure AWS complète et sécurisée** avec **Terraform** et **Ansible**.

---

## 🧩 Description

Le projet déploie une infrastructure cloud pour **MediTrack**, une PME fictive du secteur médical :  
- **VPC + Subnet public**  
- **Instance EC2** (Ubuntu)  
- **Bucket S3** pour héberger le site web statique  
- **Distribution CloudFront** pour la diffusion HTTPS  
- **Rôles IAM** dédiés, suivant le principe du moindre privilège

---

## ⚙️ Technologies

- **Terraform** – Infrastructure as Code  
- **Ansible** – Configuration automatisée  
- **AWS** – EC2, S3, CloudFront, IAM  
- **Linux / SSH** – Gestion des accès et clés  

---

## 🔐 Sécurité

Le déploiement est réalisé via un rôle **IAM**
assumé par un utilisateur dédié,
avec des permissions limitées à la région **eu-west-3** et aux ressources du projet.

---
