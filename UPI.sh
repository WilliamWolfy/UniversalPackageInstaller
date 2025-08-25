#!/usr/bin/env bash
# ================================================================
# UniversalPackageInstaller (UPI)
# Auteur : WilliamWolfy
# Description : Gestion universelle des paquets (Linux & Windows)
# - Tous les paquets et profils sont externalisés dans des fichiers JSON
# - Fonctionne sous Linux (apt/snap) et Windows (winget/UnigetUI)
# - Support export/import JSON et CSV
# ================================================================

# ================================================================
# CONFIGURATION
# ================================================================
scriptNom="UniversalPackageInstaller"
scriptAlias="UPI"
scriptCreateur="William Wolfy"
scriptVersion="1.0.0"           # ⚠️ Pense à aligner avec version.txt sur GitHub
url_version="https://raw.githubusercontent.com/WilliamWolfy/UniversalPackageInstaller/refs/heads/main/version.txt"
url_script="https://raw.githubusercontent.com/WilliamWolfy/UniversalPackageInstaller/main/UPI.sh"

scriptRepertoire="$(pwd)"

PAQUETS_FILE="packages.json"
PROFILS_FILE="profiles.json"


OS="Inconnu"
GUI="menu"

# ================================================================
# Utilitaires d'affichage
# ================================================================

function echoCouleur {
  local couleur="$1"; shift
  local texte="$*"
  local defaut="\033[0m"
  declare -A c=(
    ["noir"]="\033[30m" ["rouge"]="\033[31m" ["vert"]="\033[32m"
    ["jaune"]="\033[33m" ["bleu"]="\033[34m" ["magenta"]="\033[35m"
    ["cyan"]="\033[36m" ["blanc"]="\033[37m" ["defaut"]="\033[0m"
  )
  if [[ -n "${c[$couleur]}" ]]; then
    echo -e "${c[$couleur]}$texte$defaut"
  else
    echo -e "$texte"
  fi
}

function titre {
  local texte="$1"
  local symbole="${2:--}"
  local couleur="${3:-defaut}"
  local long=$((${#texte} + 4))
  local separateur
  separateur="$(printf "%${long}s" | tr ' ' "$symbole")"
  echoCouleur "$couleur" "$separateur"
  echoCouleur "$couleur" "$symbole $texte $symbole"
  echoCouleur "$couleur" "$separateur"
  echo ""
}

function information { echoCouleur "jaune" "ℹ️  $*"; echo ""; }

# ================================================================
# Infos script
# ================================================================

function scriptInformation {
  titre "Bienvenue dans $scriptNom ($scriptAlias)" "#" "bleu"
  titre "Créé par $scriptCreateur" "/" "blanc"
  echoCouleur "rouge" "Version: $scriptVersion"
  echo ""
}


# ================================================================
# FONCTIONS UTILITAIRES
# ================================================================

# Détection système
function detecterOS {
    case "$(uname -s)" in
        Linux*)  OS="Linux" ;;
        MINGW*|CYGWIN*|MSYS*|Windows_NT) OS="Windows" ;;
        *) OS="Inconnu" ;;
    esac
}

# Vérifier connexion internet
function verifierInternet {
  echo "🔎 Vérification de la connexion Internet..."
  if command -v curl >/dev/null 2>&1; then
    if curl -I -m 5 -s https://github.com >/dev/null; then
      echo "✅ Connexion Internet OK"
      return 0
    fi
  fi
  # fallback ping (Linux: -c ; Windows: -n)
  if ping -c 1 github.com >/dev/null 2>&1 || ping -n 1 github.com >/dev/null 2>&1; then
    echo "✅ Connexion Internet OK"
    return 0
  fi
  echo "❌ Aucune connexion Internet détectée. Veuillez vérifier votre réseau."
  exit 1
}

# Charger les paquets disponibles depuis JSON
function chargerPaquets {
    if [[ ! -f "$PAQUETS_FILE" ]]; then
        echo "❌ Fichier $PAQUETS_FILE introuvable"
        exit 1
    fi
    mapfile -t listePaquets < <(jq -r '.packages[].name' "$PAQUETS_FILE" | sort)
}

# Charger un profil prédéfini depuis JSON
function chargerProfil {
    local profil="$1"
    if [[ ! -f "$PROFILS_FILE" ]]; then
        echo "❌ Fichier $PROFILS_FILE introuvable"
        return 1
    fi
    jq -r --arg p "$profil" '.profiles[$p][]?' "$PROFILS_FILE"
}

function installerDepuisLien {
    local url="$1"
    local nom="$(basename "$url")"
    local tmpdir="$(mktemp -d)"
    local fichier="$tmpdir/$nom"

    echo "⬇️ Téléchargement de $url"
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$fichier" "$url"
    else
        wget -O "$fichier" "$url"
    fi

    # Décompression si archive
    case "$fichier" in
        *.zip) unzip -o "$fichier" -d "$tmpdir" ;;
        *.tar.gz|*.tgz) tar -xzf "$fichier" -C "$tmpdir" ;;
        *.tar.xz) tar -xJf "$fichier" -C "$tmpdir" ;;
    esac

    if [[ "$OS" == "Linux" ]]; then
        if [[ "$fichier" =~ \.deb$ ]]; then
            sudo dpkg -i "$fichier" || sudo apt-get install -f -y
        elif [[ "$fichier" =~ \.AppImage$ ]]; then
            chmod +x "$fichier" && sudo mv "$fichier" /usr/local/bin/
        fi
    elif [[ "$OS" == "Windows" ]]; then
        if [[ "$fichier" =~ \.exe$ ]]; then
            "$fichier" /quiet /norestart
        elif [[ "$fichier" =~ \.msi$ ]]; then
            msiexec /i "$fichier" /quiet /norestart
        fi
    fi

    echo "✅ Installation depuis lien terminée"
}

# Installer un paquet
function installerPaquet {
    local paquet="$1"

    # Vérifie si le paquet est défini dans le fichier JSON
    local data
    data=$(jq -r --arg p "$paquet" '.packages[] | select(.name==$p)' "$PAQUETS_FILE")

    if [[ -z "$data" ]]; then
        echo "⚠️ Paquet '$paquet' non référencé dans $PAQUETS_FILE"

        # Tentative d'installation automatique selon l'OS
        if [[ "$OS" == "Linux" ]]; then
            echo "➡️ Tentative d'installation via apt..."
            if sudo apt install -y "$paquet"; then
                echo "✅ Paquet $paquet installé avec apt"
                # Ajout automatique au JSON
                jq --arg name "$paquet" \
                   '.packages += [{"name":$name,"description":"Ajout automatique depuis apt","linux":["sudo apt install -y " + $name]}]' \
                   "$PAQUETS_FILE" > "$PAQUETS_FILE.tmp" && mv "$PAQUETS_FILE.tmp" "$PAQUETS_FILE"
            else
                echo "❌ Échec d'installation de $paquet via apt"
                return 1
            fi

        elif [[ "$OS" == "Windows" ]]; then
            echo "➡️ Tentative d'installation via winget..."
            if winget install -e --id "$paquet"; then
                echo "✅ Paquet $paquet installé avec winget"
                # Ajout automatique au JSON
                jq --arg name "$paquet" \
                   '.packages += [{"name":$name,"description":"Ajout automatique depuis winget","windows":["winget install -e --id " + $name]}]' \
                   "$PAQUETS_FILE" > "$PAQUETS_FILE.tmp" && mv "$PAQUETS_FILE.tmp" "$PAQUETS_FILE"
            else
                echo "❌ Échec d'installation de $paquet via winget"
                return 1
            fi
        fi

        return 0
    fi

    titre "📦 Installation de $paquet..." "+" "jaune"

    # Récupère l’URL spécifique à l’OS (si définie)
    local url
    if [[ "$OS" == "Linux" ]]; then
        url=$(jq -r --arg p "$paquet" '.packages[] | select(.name==$p) | .urls.linux // empty' "$PAQUETS_FILE")
        mapfile -t cmds < <(jq -r --arg p "$paquet" '.packages[] | select(.name==$p) | .linux | if type=="array" then .[] else . end' "$PAQUETS_FILE")
    elif [[ "$OS" == "Windows" ]]; then
        url=$(jq -r --arg p "$paquet" '.packages[] | select(.name==$p) | .urls.windows // empty' "$PAQUETS_FILE")
        mapfile -t cmds < <(jq -r --arg p "$paquet" '.packages[] | select(.name==$p) | .windows | if type=="array" then .[] else . end' "$PAQUETS_FILE")
    fi

    # 1. Téléchargement si URL définie
    if [[ -n "$url" && "$url" != "null" ]]; then
        echo "🌍 Téléchargement depuis $url"
        installerDepuisLien "$url"
    fi

    # 2. Exécution des commandes spécifiques
    if ((${#cmds[@]} > 0)); then
        echo "⚙️ Exécution des commandes pour $paquet..."
        for cmd in "${cmds[@]}"; do
            echo "➡️ $cmd"
            eval "$cmd"
        done
    fi

    echo "✅ $paquet installé avec succès"
}

# ================================================================
# IMPORT / EXPORT
# ================================================================

function exporterPaquets {
    titre "*" "Créer et exporter un nouveau profil" "cyan"

    # --- Étape 1 : Choix des profils (optionnel)
    echo "📂 Profils disponibles :"
    jq -r '.profiles | keys[]' profiles.json | nl -w2 -s". "
    echo
    read -p "👉 Entrez les numéros des profils à utiliser comme base (séparés par des espaces, vide pour aucun) : " choixProfils

    paquetsFusion=()

    if [[ -n "$choixProfils" ]]; then
        selectionProfils=()
        for num in $choixProfils; do
            profil=$(jq -r ".profiles | keys[$((num-1))]" profiles.json)
            if [[ "$profil" != "null" ]]; then
                selectionProfils+=("$profil")
            fi
        done

        for profil in "${selectionProfils[@]}"; do
            paquets=$(jq -r ".profiles.\"$profil\"[]" profiles.json)
            for p in $paquets; do
                paquetsFusion+=("$p")
            done
        done
    fi

# --- Étape 2 : Ajouter des paquets supplémentaires
    echo
    echo "📦 Liste des paquets disponibles :"

    jq -r '.packages[].name' packages.json | nl -w2 -s". "

    echo
    read -p "👉 Entrez les numéros des paquets supplémentaires à ajouter (séparés par des espaces, vide pour aucun) : " choixPkgs

    if [[ -n "$choixPkgs" ]]; then
        for num in $choixPkgs; do
            paquet=$(jq -r ".packages[$((num-1))].name" packages.json)

            if [[ "$paquet" != "null" ]]; then
                paquetsFusion+=("$paquet")
            fi
        done
    fi

    # Nettoyage doublons + tri alphabétique
    paquetsFusion=($(printf "%s\n" "${paquetsFusion[@]}" | sort -u))

    # --- Étape 3 : Nom du nouveau profil et fichier export
    echo
    read -p "👉 Entrez le nom du nouveau profil à créer : " nouveauProfil
    if [[ -z "$nouveauProfil" ]]; then
        echo "❌ Nom de profil invalide."
        return 1
    fi

    read -p "👉 Entrez le nom du fichier JSON à créer (par défaut: export.json) : " nomFichier
    [[ -z "$nomFichier" ]] && nomFichier="export.json"

    # Création du fichier export
    jq -n --arg profil "$nouveauProfil" --argjson paquets "$(printf '%s\n' "${paquetsFusion[@]}" | jq -R . | jq -s .)" \
        '{($profil): $paquets}' > "$nomFichier"

    if jq empty "$nomFichier" >/dev/null 2>&1; then
        echo "✅ Profil exporté dans $nomFichier (JSON valide)"
    else
        echo "❌ Erreur : fichier $nomFichier invalide"
        return 1
    fi

    # --- Étape 4 : Ajouter à profiles.json ?
    read -p "👉 Voulez-vous ajouter ce profil à profiles.json ? (o/n) " reponse
    if [[ "$reponse" =~ ^[oOyY]$ ]]; then
        tmp=$(mktemp)
        jq --arg profil "$nouveauProfil" --argjson paquets "$(printf '%s\n' "${paquetsFusion[@]}" | jq -R . | jq -s .)" \
            '.profiles + {($profil): $paquets} | {profiles: .}' profiles.json > "$tmp"

        if jq empty "$tmp" >/dev/null 2>&1; then
            mv "$tmp" profiles.json
            echo "✅ Profil ajouté à profiles.json (JSON valide)"
        else
            echo "❌ Erreur : tentative d’ajout invalide, profiles.json n’a pas été modifié"
            rm "$tmp"
        fi
    fi
}

function importerPaquets {
    local fichier="$1"
    if [[ ! -f "$fichier" ]]; then
        echo "❌ Fichier introuvable : $fichier"
        return 1
    fi

    local liste=()
    case "$fichier" in
        *.json)
            if command -v jq >/dev/null 2>&1; then
                liste=($(jq -r '.packages[]' "$fichier"))
            else
                echo "⚠️ jq requis pour importer du JSON"
                return 1
            fi
            ;;
        *.csv)
            liste=($(cat "$fichier"))
            ;;
        *)
            echo "❌ Format non reconnu (attendu .json ou .csv)"
            return 1
            ;;
    esac

    echo "📦 Installation de : ${liste[*]}"
    for p in "${liste[@]}"; do
        installerPaquet "$p"
    done
}

# ================================================================
# MISE A JOUR AUTO
# ================================================================

function checkUpdate {
    echo "🔎 Vérification des mises à jour..."
    versionEnLigne="$(curl -s "$url_version")"

    if [[ -z "$versionEnLigne" ]]; then
        echo "⚠️ Impossible de vérifier la dernière version."
        return
    fi

    if [[ -n "$versionEnLigne" && "$versionEnLigne" != "$scriptVersion" ]]; then
        echoCouleur "jaune" "⚠️ Nouvelle version : $versionEnLigne (actuelle : $scriptVersion)"
        read -p "Voulez-vous mettre à jour maintenant ? (o/n) " rep
        if [[ "$rep" =~ ^[Oo]$ ]]; then
            echo "⬇️ Téléchargement de la nouvelle version..."
            curl -s -L -o "$0" "$url_script"
            chmod +x "$0"
            echo "✅ Mise à jour effectuée. Redémarrage..."
            exec "$0" "$@"   # 🔥 Relance automatique du script
        fi
    else
        echo "✅ UPI est déjà à jour (version $scriptVersion)"
    fi
}

# ================================================================
# Mise à jour système
# ================================================================

function majSysteme {

  titre "Mise à jour du système et des dépendances utile au fonctionnement du script" "=" "jaune"

  if [ "$OS" == "Linux" ]
  then sudo apt update && sudo apt upgrade -y
    sudo apt install whiptail
    sudo apt install dos2unix

    local ui="$(whiptail -v)"
    local ui="${ui:0:8}"
    if [ "$ui" == "whiptail" ]
    then GUI="menuWhiptail"
    else GUI="menu"
  fi

  if [ "$OS" == "Windows" ]
  then control update
    winget upgrade --all
    winget install --id MartiCliment.UniGetUI -e --accept-source-agreements --accept-package-agreements
    winget install jq # utilitaire de gestion des fichiers format JSON
    GUI="menu"
  fi

fi
}

# ================================================================
# MENUS
# ================================================================

# menu avec GUI Whiptail
function menuWhiptail {
    while true; do
        choix=$(whiptail --title "UniversalPackageInstaller" --menu "Choisissez :" 20 78 10 \
            "1" "Installation personnalisée" \
            "2" "Installation par profil" \
            "3" "Importer une liste" \
            "4" "Exporter les paquets" \
            "0" "Quitter" 3>&1 1>&2 2>&3)

        case $choix in
            1) menuWhiptailPersonnalise ;;
            2) menuWhiptailProfil ;;
            3) read -p "Chemin du fichier à importer : " f; importerPaquets "$f" ;;
            4) exporterPaquets ;;
            0) exit ;;
        esac
    done
}

function menuWhiptailPersonnalise {
    local options=()
    mapfile -t paquets < <(jq -r '.packages[] | "\(.name)|\(.description)"' "$PAQUETS_FILE")

    for line in "${paquets[@]}"; do
        IFS="|" read -r name desc <<< "$line"
        options+=("$name" "$desc" OFF)
    done

    choix=$(whiptail --title "Choix des paquets" \
                     --checklist "Sélectionnez :" 20 78 10 \
                     "${options[@]}" 3>&1 1>&2 2>&3)

    for p in $choix; do
        installerPaquet "$(echo "$p" | tr -d '"')"
    done
}

function menuWhiptailProfil {
    if [[ ! -f "$PROFILS_FILE" ]]; then
        echo "❌ Fichier $PROFILS_FILE introuvable"
        return 1
    fi

    # Construit des paires [profil] [description] triées par nom
    local options=()
    while IFS='|' read -r key count; do
        options+=("$key" "$count paquet(s)")
    done < <(jq -r '.profiles | to_entries[] | "\(.key)|\(.value|length)"' "$PROFILS_FILE" | sort -t'|' -k1,1)

    if ((${#options[@]} == 0)); then
        echo "❌ Aucun profil trouvé dans $PROFILS_FILE"
        return 1
    fi

    # Affiche le menu avec paires tag/description
    local choix
    choix=$(whiptail --title "Choix du profil" \
                     --menu "Sélectionnez :" 20 78 10 \
                     "${options[@]}" 3>&1 1>&2 2>&3)

    # Annulation (ESC) ou vide → on sort proprement
    [[ -z "$choix" ]] && return 0

    # Récupère les paquets du profil choisi et lance l'installation
    mapfile -t paquets < <(chargerProfil "$choix")
    if ((${#paquets[@]} == 0)); then
        echo "⚠️ Aucun paquet dans le profil « $choix »"
        return 0
    fi

    for p in "${paquets[@]}"; do
        installerPaquet "$p"
    done
}

function menuWhiptailProfil {
    if [[ ! -f "$PROFILS_FILE" ]]; then
        echo "❌ Fichier $PROFILS_FILE introuvable"
        return 1
    fi

    # Construit des paires [profil] [description] triées par nom
    local options=()
    while IFS='|' read -r key count; do
        options+=("$key" "$count paquet(s)")
    done < <(jq -r '.profiles | to_entries[] | "\(.key)|\(.value|length)"' "$PROFILS_FILE" | sort -t'|' -k1,1)

    if ((${#options[@]} == 0)); then
        echo "❌ Aucun profil trouvé dans $PROFILS_FILE"
        return 1
    fi

    # Affiche le menu avec paires tag/description
    local choix
    choix=$(whiptail --title "Choix du profil" \
                     --menu "Sélectionnez :" 20 78 10 \
                     "${options[@]}" 3>&1 1>&2 2>&3)

    # Annulation (ESC) ou vide → on sort proprement
    [[ -z "$choix" ]] && return 0

    # Récupère les paquets du profil choisi et lance l'installation
    mapfile -t paquets < <(chargerProfil "$choix")
    if ((${#paquets[@]} == 0)); then
        echo "⚠️ Aucun paquet dans le profil « $choix »"
        return 0
    fi

    for p in "${paquets[@]}"; do
        installerPaquet "$p"
    done
}

#menus texte simples
function menu {
    titre "UniversalPackageInstaller" "W" "jaune"
    echo "1) Personnalisée"
    echo "2) Par profil"
    echo "3) Importer une liste"
    echo "4) Exporter les paquets"
    echo "0) Quitter"
    read -p "Votre choix : " choix
    case $choix in
        1) menuPersonnalise ;;
        2) menuProfil ;;
        3) read -p "Chemin du fichier à importer : " f; importerPaquets "$f" ;;
        4) exporterPaquets ;;
        0) exit ;;
    esac
}

function menuPersonnalise {
    mapfile -t paquets < <(jq -r '.packages[] | "\(.name)|\(.description)"' "$PAQUETS_FILE")

    echo "=== Paquets disponibles ==="
    for line in "${paquets[@]}"; do
        IFS="|" read -r name desc <<< "$line"
        printf " - %s : %s\n" "$name" "$desc"
    done

    read -p "Entrez les paquets à installer (séparés par espace) : " choix
    for p in $choix; do
        installerPaquet "$p"
    done
}

function menuProfil {
    if [[ ! -f "$PROFILS_FILE" ]]; then
        echo "❌ Fichier $PROFILS_FILE introuvable"
        return 1
    fi

    # Liste triée des profils avec le nombre de paquets
    mapfile -t profils < <(jq -r '.profiles | to_entries[] | "\(.key)|\(.value|length)"' "$PROFILS_FILE" | sort -t'|' -k1,1)

    echo "=== Profils disponibles ==="
    for line in "${profils[@]}"; do
        IFS='|' read -r key count <<< "$line"
        printf " - %s (%s paquet(s))\n" "$key" "$count"
    done

    read -p "Quel profil installer ? " choix
    [[ -z "$choix" ]] && return 0

    mapfile -t paquets < <(chargerProfil "$choix")
    if ((${#paquets[@]} == 0)); then
        echo "⚠️ Aucun paquet dans le profil « $choix »"
        return 0
    fi

    for p in "${paquets[@]}"; do
        installerPaquet "$p"
    done
}

# ================================================================
# MAIN
# ================================================================

scriptInformation
detecterOS
verifierInternet
checkUpdate
majSysteme
chargerPaquets
eval "$GUI"