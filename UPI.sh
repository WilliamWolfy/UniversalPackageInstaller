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
scriptVersion="25.08.25"           # ⚠️ Pense à aligner avec version.txt sur GitHub
url_version="https://raw.githubusercontent.com/WilliamWolfy/UniversalPackageInstaller/refs/heads/Prototype/version.txt"
url_script="https://raw.githubusercontent.com/WilliamWolfy/UniversalPackageInstaller/refs/heads/Prototype/UPI.sh"

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

function detecterOS {
    OS_FAMILY="Inconnu"
    OS_DISTRO="Inconnu"
    OS_VERSION="Inconnu"

    case "$(uname -s)" in
        Linux*)
            OS_FAMILY="Linux"
            if [[ -f /etc/os-release ]]; then
                # Lecture des infos depuis os-release
                . /etc/os-release
                OS_DISTRO="$ID"
                OS_VERSION="$VERSION_ID"
            fi
            ;;
        Darwin*)
            OS_FAMILY="macOS"
            OS_DISTRO=$(sw_vers -productName)
            OS_VERSION=$(sw_vers -productVersion)
            ;;
        MINGW*|CYGWIN*|MSYS*|Windows_NT)
            OS_FAMILY="Windows"
            # Utiliser PowerShell pour obtenir la version exacte
            OS_DISTRO=$(powershell -Command "(Get-ComputerInfo).WindowsProductName" 2>/dev/null | tr -d '\r')
            OS_VERSION=$(powershell -Command "(Get-ComputerInfo).WindowsVersion" 2>/dev/null | tr -d '\r')
            ;;
        *)
            OS_FAMILY="Inconnu"
            OS_DISTRO="Inconnu"
            OS_VERSION="Inconnu"
            ;;
    esac

    echo "🖥️ OS détecté : $OS_FAMILY / $OS_DISTRO / $OS_VERSION"
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

function arrayToJson() {
    local arr=("$@")
    printf '%s\n' "${arr[@]}" | jq -R . | jq -s .
}

function gererPaquet {
    local paquet="$1"
    local action=""

    if [[ -z "$paquet" ]]; then
        PS3="Choisir une action : "
        select action in "Ajouter" "Modifier" "Supprimer" "Annuler"; do
            case $REPLY in
                1) action="add"; break ;;
                2) action="edit"; break ;;
                3) action="delete"; break ;;
                4) return ;;
                *) echo "Choix invalide." ;;
            esac
        done
    else
        if jq -e --arg name "$paquet" '.packages[] | select(.name==$name)' "$PAQUETS_FILE" >/dev/null 2>&1; then
            action="edit"
        else
            action="add"
        fi
    fi

    # Si modification ou suppression, afficher une liste pour choisir le paquet
    if [[ "$action" == "edit" || "$action" == "delete" ]]; then
        mapfile -t package_list < <(jq -r '.packages[].name' "$PAQUETS_FILE")
        echo "📦 Liste des paquets disponibles :"
        select paquet in "${package_list[@]}" "Annuler"; do
            if [[ "$REPLY" -ge 1 && "$REPLY" -le "${#package_list[@]}" ]]; then
                break
            elif [[ "$REPLY" -eq $(( ${#package_list[@]} + 1 )) ]]; then
                return
            else
                echo "Choix invalide."
            fi
        done
    fi

    case $action in
        delete)
            jq --arg name "$paquet" 'del(.packages[] | select(.name==$name))' "$PAQUETS_FILE" > "$PAQUETS_FILE.tmp" && mv "$PAQUETS_FILE.tmp" "$PAQUETS_FILE"
            echo "🗑️ Paquet '$paquet' supprimé."
            ;;
        edit)
            echo "✏️ Modification du paquet '$paquet' :"
            read -p "Nouvelle description (laisser vide pour conserver) : " new_description
            read -p "Nouvelle catégorie (laisser vide pour conserver) : " new_category
            [[ -n "$new_description" ]] && jq --arg name "$paquet" --arg desc "$new_description" \
                '(.packages[] | select(.name==$name).description) |= $desc' "$PAQUETS_FILE" > "$PAQUETS_FILE.tmp" && mv "$PAQUETS_FILE.tmp" "$PAQUETS_FILE"
            [[ -n "$new_category" ]] && jq --arg name "$paquet" --arg cat "$new_category" \
                '(.packages[] | select(.name==$name).category) |= $cat' "$PAQUETS_FILE" > "$PAQUETS_FILE.tmp" && mv "$PAQUETS_FILE.tmp" "$PAQUETS_FILE"

            for os in linux windows macos; do
                echo "🖥️ Commandes existantes pour $os :"
                mapfile -t current_cmds < <(jq -r --arg name "$paquet" --arg os "$os" \
                    '.packages[] | select(.name==$name) | .[$os] // [] | if type=="array" then .[] else . end' "$PAQUETS_FILE")
                for c in "${current_cmds[@]}"; do echo " - $c"; done
                read -p "Ajouter une commande pour $os (laisser vide pour passer) : " cmd
                if [[ -n "$cmd" ]]; then
                    jq --arg name "$paquet" --arg os "$os" --arg cmd "$cmd" \
                        '(.packages[] | select(.name==$name) | .[$os]) += [$cmd]' "$PAQUETS_FILE" > "$PAQUETS_FILE.tmp" && mv "$PAQUETS_FILE.tmp" "$PAQUETS_FILE"
                fi
            done
            ;;
        add)
            echo "➕ Ajout d'un nouveau paquet :"
            read -p "Nom : " name
            paquet="$name"
            read -p "Description : " description
            read -p "Catégorie : " category

            declare -a linux_cmds=()
            declare -a windows_cmds=()
            declare -a macos_cmds=()

            read -p "Commandes pour Linux (séparées par ';', laisser vide si aucune) : " input
            [[ -n "$input" ]] && IFS=';' read -r -a linux_cmds <<< "$input"
            read -p "Commandes pour Windows (séparées par ';', laisser vide si aucune) : " input
            [[ -n "$input" ]] && IFS=';' read -r -a windows_cmds <<< "$input"
            read -p "Commandes pour macOS (séparées par ';', laisser vide si aucune) : " input
            [[ -n "$input" ]] && IFS=';' read -r -a macos_cmds <<< "$input"

            linux_json=$(arrayToJson "${linux_cmds[@]}")
            windows_json=$(arrayToJson "${windows_cmds[@]}")
            macos_json=$(arrayToJson "${macos_cmds[@]}")

            jq --arg name "$paquet" --arg desc "$description" --arg cat "$category" \
               --argjson linux "$linux_json" --argjson windows "$windows_json" --argjson macos "$macos_json" \
               '.packages += [{"name":$name,"category":$cat,"description":$desc,"linux":$linux,"windows":$windows,"macos":$macos}]' \
               "$PAQUETS_FILE" > "$PAQUETS_FILE.tmp" && mv "$PAQUETS_FILE.tmp" "$PAQUETS_FILE"

            echo "✅ Paquet '$paquet' ajouté."
            ;;
    esac
}

telecharger() {
    local url="$1"
    local sortie="$2"

    if [[ -z "$sortie" ]]; then
        # Mode lecture dans stdout
        if command -v curl >/dev/null 2>&1; then
            curl -sL "$url"
        else
            wget -qO- "$url"
        fi
    else
        # Mode écriture dans fichier
        if command -v curl >/dev/null 2>&1; then
            curl -sL -o "$sortie" "$url"
        else
            wget -qO "$sortie" "$url"
        fi
    fi
}

function installerDepuisLien {
    local url="$1"
    local nom="$(basename "$url")"
    local dossier_cache="$(dirname "$0")/packages/$OS_FAMILY"
    mkdir -p "$dossier_cache"
    local fichier="$dossier_cache/$nom"

    # Mode cache par défaut
    local CACHE_MODE="normal"
    for arg in "$@"; do
        case "$arg" in
            --force-download) CACHE_MODE="force" ;;
            --cache-only) CACHE_MODE="cache" ;;
        esac
    done

    # Vérification du fichier existant
    if [[ -f "$fichier" ]]; then
        case "$CACHE_MODE" in
            force)
                echo "🔄 Forçage du re-téléchargement de $url"
                telecharger "$url" "$fichier"
                ;;
            cache)
                echo "✅ Utilisation du cache (aucun téléchargement)"
                ;;
            *)
                echo "📦 Le paquet '$nom' est déjà présent."
                read -p "Voulez-vous le re-télécharger ? (o/n) " rep
                if [[ "$rep" =~ ^[Oo]$ ]]; then
                    telecharger "$url" "$fichier"
                else
                    echo "✅ Utilisation du fichier en cache"
                fi
                ;;
        esac
    else
        telecharger "$url" "$fichier"
    fi

    # Décompression automatique pour archives
    local unpack_dir="$dossier_cache/unpacked"
    mkdir -p "$unpack_dir"
    case "$fichier" in
        *.zip) unzip -o "$fichier" -d "$unpack_dir" ;;
        *.tar.gz|*.tgz) tar -xzf "$fichier" -C "$unpack_dir" ;;
        *.tar.xz) tar -xJf "$fichier" -C "$unpack_dir" ;;
    esac

    # Installation selon l'OS et type de fichier
    case "$OS_FAMILY" in
        Linux)
            if [[ "$fichier" =~ \.deb$ ]]; then
                echo "➡️ Installation .deb"
                sudo dpkg -i "$fichier" 2>/dev/null || sudo apt-get install -f -y
            elif [[ "$fichier" =~ \.rpm$ ]]; then
                echo "➡️ Installation .rpm"
                if command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y "$fichier" || sudo yum localinstall -y "$fichier"
                else
                    sudo yum localinstall -y "$fichier"
                fi
            elif [[ "$fichier" =~ \.AppImage$ ]]; then
                chmod +x "$fichier"
                sudo mv "$fichier" /usr/local/bin/
            elif [[ -x "$fichier" ]]; then
                bash "$fichier"
            fi
            ;;
        Windows)
            if [[ "$fichier" =~ \.exe$ ]]; then
                "$fichier" /quiet /norestart || "$fichier"
            elif [[ "$fichier" =~ \.msi$ ]]; then
                msiexec /i "$fichier" /quiet /norestart
            elif [[ "$fichier" =~ \.zip$ ]]; then
                unzip -o "$fichier" -d "$HOME/AppData/Local/"
            fi
            ;;
        MacOS)
            if [[ "$fichier" =~ \.dmg$ ]]; then
                mkdir -p "$dossier_cache/mnt"
                hdiutil attach "$fichier" -mountpoint "$dossier_cache/mnt"
                cp -r "$dossier_cache/mnt"/*.app /Applications/
                hdiutil detach "$dossier_cache/mnt"
            elif [[ "$fichier" =~ \.pkg$ ]]; then
                sudo installer -pkg "$fichier" -target /
            elif [[ "$fichier" =~ \.zip$ ]]; then
                unzip -o "$fichier" -d /Applications/
            fi
            ;;
    esac

    echo "✅ Installation terminée pour $nom"
}

# Installer un paquet
function installerPaquet {
    local paquet="$1"

    # Vérifie si le paquet est défini dans le fichier JSON
    local data
    data=$(jq -r --arg p "$paquet" '.packages[] | select(.name==$p)' "$PAQUETS_FILE")

    if [[ -z "$data" ]]; then
        echo "⚠️ Paquet '$paquet' non référencé dans $PAQUETS_FILE"
        echo "➡️ Tentative d'installation automatique selon l'OS..."

        case "$OS_FAMILY" in
            Linux)
                case "$OS_DISTRO" in
                    ubuntu|debian)
                        sudo apt update
                        sudo apt install -y "$paquet"
                        ;;
                    fedora|rhel|centos)
                        sudo dnf install -y "$paquet"
                        ;;
                    arch|manjaro)
                        sudo pacman -Sy --noconfirm "$paquet"
                        ;;
                    *)
                        echo "⚠️ Distribution Linux $OS_DISTRO non supportée"
                        return 1
                        ;;
                esac
                jq --arg name "$paquet" \
                   '.packages += [{"name":$name,"description":"Ajout automatique","linux":["installation via gestionnaire"]}]' \
                   "$PAQUETS_FILE" > "$PAQUETS_FILE.tmp" && mv "$PAQUETS_FILE.tmp" "$PAQUETS_FILE"
                ;;
            Windows)
                winget install -e --id "$paquet"
                jq --arg name "$paquet" \
                   '.packages += [{"name":$name,"description":"Ajout automatique","windows":["winget install -e --id " + $name]}]' \
                   "$PAQUETS_FILE" > "$PAQUETS_FILE.tmp" && mv "$PAQUETS_FILE.tmp" "$PAQUETS_FILE"
                ;;
            MacOS)
                brew install "$paquet"
                jq --arg name "$paquet" \
                   '.packages += [{"name":$name,"description":"Ajout automatique","macos":["brew install " + $name]}]' \
                   "$PAQUETS_FILE" > "$PAQUETS_FILE.tmp" && mv "$PAQUETS_FILE.tmp" "$PAQUETS_FILE"
                ;;
            *)
                echo "⚠️ OS non supporté"
                return 1
                ;;
        esac
        return 0
    fi

    titre "📦 Installation de $paquet..." "+" "jaune"

    # Récupère URL ou commandes spécifiques
    local url
    local cmds=()
    case "$OS_FAMILY" in
        Linux)
            url=$(jq -r --arg p "$paquet" '.packages[] | select(.name==$p) | .urls.linux // empty' "$PAQUETS_FILE")
            mapfile -t cmds < <(jq -r --arg p "$paquet" '.packages[] | select(.name==$p) | .linux | if type=="array" then .[] else . end' "$PAQUETS_FILE")
            ;;
        Windows)
            url=$(jq -r --arg p "$paquet" '.packages[] | select(.name==$p) | .urls.windows // empty' "$PAQUETS_FILE")
            mapfile -t cmds < <(jq -r --arg p "$paquet" '.packages[] | select(.name==$p) | .windows | if type=="array" then .[] else . end' "$PAQUETS_FILE")
            ;;
        MacOS)
            url=$(jq -r --arg p "$paquet" '.packages[] | select(.name==$p) | .urls.macos // empty' "$PAQUETS_FILE")
            mapfile -t cmds < <(jq -r --arg p "$paquet" '.packages[] | select(.name==$p) | .macos | if type=="array" then .[] else . end' "$PAQUETS_FILE")
            ;;
    esac

    # Téléchargement si URL
    if [[ -n "$url" && "$url" != "null" ]]; then
        echo "🌍 Téléchargement depuis $url"
        installerDepuisLien "$url"
    fi

    # Exécution des commandes spécifiques
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

    # --- Étape 1 : Choix des profils existants
    echo "📂 Profils disponibles :"
    jq -r '.profiles | keys[]' profiles.json | nl -w2 -s". "
    read -p "👉 Numéros des profils à utiliser comme base (séparés par des espaces, vide pour aucun) : " choixProfils

    paquetsFusion=()

    if [[ -n "$choixProfils" ]]; then
        for num in $choixProfils; do
            profil=$(jq -r ".profiles | keys[$((num-1))]" profiles.json)
            if [[ "$profil" != "null" ]]; then
                mapfile -t tmp < <(jq -r ".profiles.\"$profil\"[]" profiles.json)
                paquetsFusion+=("${tmp[@]}")
            fi
        done
    fi

    # --- Étape 2 : Ajouter des paquets supplémentaires
    echo
    echo "📦 Liste des paquets disponibles :"
    jq -r '.packages[].name' packages.json | nl -w2 -s". "
    read -p "👉 Numéros des paquets supplémentaires à ajouter (séparés par des espaces, vide pour aucun) : " choixPkgs

    if [[ -n "$choixPkgs" ]]; then
        for num in $choixPkgs; do
            paquet=$(jq -r ".packages[$((num-1))].name" packages.json)
            [[ "$paquet" != "null" ]] && paquetsFusion+=("$paquet")
        done
    fi

    # --- Nettoyage doublons + tri alphabétique
    paquetsFusion=($(printf "%s\n" "${paquetsFusion[@]}" | sort -u))

    echo "${paquetFusion[@]}"
    # --- Étape 3 : Nom du nouveau profil
    read -p "👉 Entrez le nom du nouveau profil : " nouveauProfil
    [[ -z "$nouveauProfil" ]] && nouveauProfil="exported_profile"

    fichierMinimal="$nouveauProfil.json"
    fichierComplet="$nouveauProfil-full.json"

    # --- JSON minimal (noms seulement)
    jq -n --arg profil "$nouveauProfil" \
        --argjson paquets "$(printf '%s\n' "${paquetsFusion[@]}" | jq -R . | jq -s .)" \
        '{($profil): $paquets}' > "$fichierMinimal"

    # --- JSON complet (objets complets)
    # Crée un tableau avec tous les objets correspondant aux noms des paquets fusionnés
    nomsJson=$(printf '%s\n' "${paquetsFusion[@]}" | jq -R . | jq -s .)

    jq -n --arg profil "$nouveauProfil" --argjson noms "$nomsJson" \
        --slurpfile allPackages packages.json \
        '{
            ($profil): $allPackages[0].packages | map(select(.name as $n | $n | IN($noms[])))
        }' > "$fichierComplet"

    echo "✅ Fichiers exportés :"
    echo "   - Minimal : $fichierMinimal"
    echo "   - Complet : $fichierComplet"

    # --- Étape 4 : Ajouter à profiles.json ?
    read -p "👉 Ajouter ce profil à profiles.json ? (o/n) " reponse
    if [[ "$reponse" =~ ^[oOyY]$ ]]; then
        jq --arg profil "$nouveauProfil" \
           --argjson paquets "$(printf '%s\n' "${paquetsFusion[@]}" | jq -R . | jq -s .)" \
           '.profiles + {($profil): $paquets} | {profiles: .}' profiles.json \
           > profiles.json.tmp && mv profiles.json.tmp profiles.json
        echo "✅ Profil ajouté à profiles.json"
    fi
}


function importerPaquets {
    local fichier="$1"

    # --- Choix du fichier si non fourni
    if [[ -z "$fichier" ]]; then
        echo "📂 Sélection du fichier à importer"
        local fichiers=($(ls "$(dirname "$0")"/*.json 2>/dev/null))
        
        if [[ ${#fichiers[@]} -eq 0 ]]; then
            read -rp "⚠️ Aucun fichier JSON trouvé. Entrez le chemin complet du fichier à importer : " fichier
        else
            echo "0) Entrer un chemin personnalisé"
            for i in "${!fichiers[@]}"; do
                echo "$((i+1))) ${fichiers[$i]}"
            done
            read -rp "👉 Choix : " choix
            if [[ "$choix" == "0" ]]; then
                read -rp "👉 Entrez le chemin complet : " fichier
            elif [[ "$choix" =~ ^[0-9]+$ ]] && (( choix > 0 && choix <= ${#fichiers[@]} )); then
                fichier="${fichiers[$((choix-1))]}"
            else
                echo "❌ Choix invalide"
                return 1
            fi
        fi
    fi

    # --- Vérification existence fichier
    if [[ ! -f "$fichier" ]]; then
        echo "❌ Fichier introuvable : $fichier"
        return 1
    fi

    # --- Détection type JSON
    local typeJSON="minimal"  # par défaut minimal
    local cleProfil
    cleProfil=$(jq -r 'keys[0]' "$fichier" 2>/dev/null)
    if jq -e ".\"$cleProfil\"[0] | type == \"object\"" "$fichier" >/dev/null 2>&1; then
        typeJSON="complet"
    fi

    echo "📂 Import du profil : $cleProfil ($typeJSON)"

    local paquets=()
    if [[ "$typeJSON" == "minimal" ]]; then
        paquets=($(jq -r ".\"$cleProfil\"[]" "$fichier"))
    else
        # JSON complet : on récupère les noms et ajoute les paquets inconnus dans packages.json
        mapfile -t paquets < <(jq -r ".\"$cleProfil\"[].name" "$fichier")
        for p in "${paquets[@]}"; do
            exists=$(jq -e --arg name "$p" '.packages[] | select(.name==$name)' packages.json >/dev/null 2>&1; echo $?)
            if [[ $exists -ne 0 ]]; then
                # Ajout automatique du paquet complet
                jq --argjson pkg "$(jq -r ".\"$cleProfil\"[] | select(.name==\"$p\")" "$fichier")" \
                   '.packages += [$pkg]' packages.json > packages.json.tmp && mv packages.json.tmp packages.json
                echo "➕ Paquet inconnu '$p' ajouté dans packages.json"
            fi
        done
    fi

    # --- Supprimer doublons
    paquets=($(printf "%s\n" "${paquets[@]}" | sort -u))

    # --- Mise à jour profiles.json
    jq --arg profil "$cleProfil" --argjson paquets "$(printf '%s\n' "${paquets[@]}" | jq -R . | jq -s .)" \
       '.profiles + {($profil): $paquets} | {profiles: .}' profiles.json > profiles.json.tmp && mv profiles.json.tmp profiles.json
    echo "✅ Profil '$cleProfil' ajouté ou mis à jour dans profiles.json"

    # --- Installation des paquets
    echo "📦 Installation des paquets du profil : ${paquets[*]}"
    for p in "${paquets[@]}"; do
        installerPaquet "$p"
    done
}

# ================================================================
# MISE A JOUR AUTO
# ================================================================

function checkUpdate {
    # Déduire les URLs des JSON depuis url_script
    url_base="${url_script%/*}/"          # base : https://raw.githubusercontent.com/.../Prototype/
    url_packages="${url_base}packages.json"
    url_profiles="${url_base}profiles.json"

    # Vérifier et télécharger packages.json si absent
    if [[ ! -f "$PAQUETS_FILE" ]]; then
        echo "⚠️ $PAQUETS_FILE introuvable, téléchargement..."
        if telecharger "$PAQUETS_FILE" "$url_packages"; then
            echo "✅ $PAQUETS_FILE téléchargé."
        else
            echo "❌ Échec du téléchargement de $PAQUETS_FILE"
        fi
    fi

    # Vérifier et télécharger profiles.json si absent
    if [[ ! -f "$PROFILS_FILE" ]]; then
        echo "⚠️ $PROFILS_FILE introuvable, téléchargement..."
        if telecharger "$url_packages" "$PROFILS_FILE"; then
            echo "✅ $PROFILS_FILE téléchargé."
        else
            echo "❌ Échec du téléchargement de $PROFILS_FILE"
        fi
    fi

    # Vérification de la version du script
    echo "🔎 Vérification des mises à jour..."
    versionEnLigne="$(telecharger "$url_version")"

    if [[ -z "$versionEnLigne" ]]; then
        echo "⚠️ Impossible de vérifier la dernière version."
        return
    fi

    if [[ "$versionEnLigne" != "$scriptVersion" ]]; then
        echoCouleur "jaune" "⚠️ Nouvelle version : $versionEnLigne (actuelle : $scriptVersion)"
        read -p "Voulez-vous mettre à jour maintenant ? (o/n) " rep
        if [[ "$rep" =~ ^[Oo]$ ]]; then
            echo "⬇️ Téléchargement de la nouvelle version..."
            telecharger "$url_script" "$0"
            chmod +x "$0"
            echo "✅ Mise à jour effectuée. Redémarrage..."
            exec "$0" "$@"   # Relance automatique du script
        fi
    else
        echo "✅ UPI est déjà à jour (version $scriptVersion)"
    fi
}

# ================================================================
# Mise à jour système
# ================================================================

function majSysteme {
    titre "Mise à jour et vérification des dépendances" "=" "jaune"

    if [[ "$OS_FAMILY" == "Linux" ]]; then
        echo "🔄 Mise à jour du système Linux ($OS_DISTRO $OS_VERSION)..."

        # Détecter le gestionnaire de paquets disponible
        if command -v apt >/dev/null 2>&1; then
            PKG_CMD="sudo apt"
            UPDATE_CMD="update && sudo apt upgrade -y"
            INSTALL_CMD="install -y"
        elif command -v dnf >/dev/null 2>&1; then
            PKG_CMD="sudo dnf"
            UPDATE_CMD="upgrade --refresh -y"
            INSTALL_CMD="install -y"
        elif command -v pacman >/dev/null 2>&1; then
            PKG_CMD="sudo pacman"
            UPDATE_CMD="-Syu --noconfirm"
            INSTALL_CMD="-S --noconfirm"
        elif command -v zypper >/dev/null 2>&1; then
            PKG_CMD="sudo zypper"
            UPDATE_CMD="refresh && sudo zypper update -y"
            INSTALL_CMD="install -y"
        elif command -v apk >/dev/null 2>&1; then
            PKG_CMD="sudo apk"
            UPDATE_CMD="update"
            INSTALL_CMD="add"
        else
            echo "⚠️ Aucun gestionnaire de paquets reconnu sur cette distribution."
        fi

        # Mise à jour du système si gestionnaire détecté
        if [[ -n "$PKG_CMD" ]]; then
            echo "🔄 Mise à jour via $PKG_CMD..."
            eval "$PKG_CMD $UPDATE_CMD"
            echo "🔧 Installation des dépendances..."
            eval "$PKG_CMD $INSTALL_CMD jq whiptail curl unzip wget dos2unix"
        fi

        # Détecter le mode GUI
        if command -v whiptail >/dev/null 2>&1; then
            GUI="menuWhiptail"
        else
            GUI="menu"
        fi

    elif [[ "$OS_FAMILY" == "macOS" ]]; then
        echo "🔄 Vérification du système macOS ($OS_VERSION)..."
        if ! command -v brew >/dev/null 2>&1; then
            echo "⚠️ Homebrew non trouvé, installation..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew update
        brew upgrade
        brew install jq wget curl
        GUI="menu"

    elif [[ "$OS_FAMILY" == "Windows" ]]; then
        echo "🔄 Mise à jour Windows ($OS_DISTRO $OS_VERSION)..."
        winget upgrade --all
        winget install --id MartiCliment.UniGetUI -e --accept-source-agreements --accept-package-agreements
        winget install --id jq -e --accept-source-agreements --accept-package-agreements
        GUI="menu"

    else
        echo "❌ OS non reconnu, impossible de mettre à jour et installer les dépendances."
        GUI="menu"
    fi

    echo "✅ Vérification système terminée. Mode GUI : $GUI"
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
            "5" "Gérer les paquets" \
            "0" "Quitter" 3>&1 1>&2 2>&3)

        case $choix in
            1) menuWhiptailPersonnalise ;;
            2) menuWhiptailProfil ;;
            3) importerPaquets ;;
            4) exporterPaquets ;;
            5) gererPaquet ;;
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
    echo "5) Gérer les paquetes"
    echo "0) Quitter"
    read -p "Votre choix : " choix
    case $choix in
        1) menuPersonnalise ;;
        2) menuProfil ;;
        3) importerPaquets ;;
        4) exporterPaquets ;;
        5) gererPaquet ;;
        0) exit ;;
    esac
}

function menuPersonnalise {
    # Récupère les paquets "nom|description", triés alphabétiquement
    mapfile -t paquets < <(jq -r '.packages[] | "\(.name)|\(.description)"' "$PAQUETS_FILE" | sort -t"|" -k1,1)

    echo "=== 📦 Paquets disponibles ==="
    i=1
    declare -A num2name
    for line in "${paquets[@]}"; do
        IFS="|" read -r name desc <<< "$line"
        printf "%2d) %-20s : %s\n" "$i" "$name" "$desc"
        num2name[$i]="$name"
        ((i++))
    done

    echo
    read -p "👉 Entrez les paquets à installer (noms ou numéros, séparés par espace) : " choix

    for p in $choix; do
        if [[ "$p" =~ ^[0-9]+$ ]]; then
            # Cas numéro
            if [[ -n "${num2name[$p]}" ]]; then
                paquet="${num2name[$p]}"
                installerPaquet "$paquet"
            else
                echo "⚠️  Numéro $p invalide (aucun paquet associé)"
            fi
        else
            # Cas nom → on laisse installerPaquet gérer
            installerPaquet "$p"
        fi
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
detecterOSV2
verifierInternet
checkUpdate
majSysteme
chargerPaquets
eval "$GUI"
