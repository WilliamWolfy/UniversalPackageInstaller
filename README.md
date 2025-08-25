# 🚀 Gestionnaire de Profils & Paquets

## 🌍 Qu’est-ce que c’est ?

Ce projet est un **outil multi-OS** (Linux 🐧, Windows 🪟, macOS 🍏) qui permet d’installer facilement des logiciels en fonction de **profils prédéfinis** ou de vos propres choix.

👉 L’idée : au lieu de chercher chaque logiciel un par un, vous choisissez un profil (*Bureautique, Développeur, Gamer, Graphiste…*) ou construisez un profil personnalisé, et tout s’installe automatiquement 🎉.

C’est un projet **en cours de développement**, qui s’enrichit régulièrement avec de nouveaux logiciels et fonctionnalités.

---

## ✨ Fonctionnalités principales

* 📦 **Installation automatisée** des logiciels via `apt`, `snap`, `winget` ou autres.
* 🖥️ **Multi-OS** : fonctionne sur Linux, Windows et macOS (si les commandes sont renseignées).
* 📑 **Profils prédéfinis** : Bureautique, Développeur, Gamer, Graphiste, etc.
* 🛠️ **Profil personnalisé** : choisissez vos logiciels dans une liste triée **par ordre alphabétique et numérotée**.
* 🔄 **Évolutif** : vous pouvez ajouter vos propres logiciels et créer vos profils facilement.

---

## 🏁 Comment l’utiliser ?

1. Clonez le projet :

   ```bash
   git clone https://github.com/ton-projet/gestion-profils.git
   cd gestion-profils
   ```

2. Lancez le script principal :

   ```bash
   ./install.sh
   ```

3. Choisissez :

   * Un **profil complet** (Bureautique, Développeur, etc.)
   * Ou un **profil personnalisé** (sélection par numéro ou nom de paquet)

---

## 📂 Organisation du projet

* **`UPI.sh`** → le script principal interactif
* **`packages.json`** → la liste complète des logiciels avec leurs commandes d’installation
* **`profiles.json`** → les profils regroupant plusieurs logiciels
* **`ReadMe.txt`** → ce fichier 🙂

---

## 🧩 Ajouter vos logiciels

Envie d’enrichir la liste ?
Il suffit d’éditer **`packages.json`** et d’ajouter :

```json
{
  "name": "NomDuLogiciel",
  "category": "Catégorie",
  "description": "Brève description",
  "linux": "commande d'installation Linux",
  "windows": "commande d'installation Windows",
  "macos": "commande d'installation MacOS"
}
```

Ensuite, ajoutez-le éventuellement dans un profil via **`profiles.json`**.

---

## 📌 Statut du projet

⚠️ **Projet en cours de développement**

* 🔹 Tous les paquets ne sont pas encore disponibles sur les 3 OS.
* 🔹 Les profils s’enrichissent petit à petit.
* 🔹 De nouvelles fonctionnalités arrivent (meilleure détection de l’OS, interface plus claire, etc.).

---

## 🤝 Contributions

Vous êtes les bienvenus pour :

* Ajouter des logiciels
* Créer de nouveaux profils
* Améliorer le script
