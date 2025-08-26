#!/usr/bin/env bash
# ================================================================
# UniversalPackageInstaller (UPI)
# Auteur : WilliamWolfy
# Description : Gestion universelle des packages (Linux & Windows)
# - Tous les packages et profils sont externalisés dans des fichiers JSON
# - Fonctionne sous Linux (apt/snap) et Windows (winget/UnigetUI)
# - Support export/import JSON et CSV
# ================================================================

# ================================================================
# CONFIGURATION
# ================================================================
scriptName="Universal Package Installer"
scriptAlias="UPI"
scriptCreator="William Wolfy"
scriptVersion="26.08.25"           # ⚠️ Pense à aligner avec version.txt sur GitHub
url_version="https://raw.githubusercontent.com/WilliamWolfy/UniversalPackageInstaller/refs/heads/Prototype-multi-langue/version.txt"
url_script="https://raw.githubusercontent.com/WilliamWolfy/UniversalPackageInstaller/refs/heads/Prototype-multi-langue/UPI.sh"

scriptRepertory="$(pwd)"

LANG_FILE="lang.json"
DEFAULT_LANG="fr"
PACKAGES_FILE="packages.json"
PROFILES_FILE="profiles.json"

GUI="menu"

# ================================================================
# Utilitaires d'affichage
# ================================================================

function load_language {
    local file="$LANG_FILE"
    local lang="$DEFAULT_LANG"

    if [[ ! -f "$file" ]]; then
        echo "❌ Missing language file: $file"
        return 1
    fi

    # Detect format (old: top-level "en"/"fr", new: top-level Lang_*)
    if jq -e 'has("en") and has("fr")' "$file" >/dev/null 2>&1; then
        echo "ℹ️ Detected old lang.json format, converting..."

        cp "$file" "$file.bak"
        tmp=$(mktemp)

        jq '
          to_entries
          | map(.key as $lang
            | .value
            | to_entries[]
            | {key: (if (.key|startswith("Lang_")) then .key else "Lang_" + .key end),
               lang: $lang,
               value: .value})
          | group_by(.key)
          | map({ (.[0].key): (reduce .[] as $item ({}; .[$item.lang] = $item.value)) })
          | add
        ' "$file" > "$tmp"

        if jq empty "$tmp" >/dev/null 2>&1; then
            mv "$tmp" "$file"
            echo "✅ Conversion successful (backup in $file.bak)"
            jq -r 'keys[]' "$file"
        else
            echo "❌ Conversion failed, keeping original file."
            rm -f "$tmp"
            return 1
        fi
    fi

    # Load only selected language
    while IFS="=" read -r key val; do
        export "$key=$val"
    done < <(jq -r --arg l "$lang" '
        to_entries[]
        | select(.value[$l] != null)
        | "\(.key)=\(.value[$l])"
    ' "$file")
}

function echoColor {
  local color="$1"; shift
  local texte="$*"
  local defaut="\033[0m"
  declare -A c=(
    ["noir"]="\033[30m" ["rouge"]="\033[31m" ["vert"]="\033[32m"
    ["jaune"]="\033[33m" ["bleu"]="\033[34m" ["magenta"]="\033[35m"
    ["cyan"]="\033[36m" ["blanc"]="\033[37m" ["defaut"]="\033[0m"
  )
  if [[ -n "${c[$color]}" ]]; then
    echo -e "${c[$color]}$texte$defaut"
  else
    echo -e "$texte"
  fi
}

function title {
  local texte="$1"
  local symbole="${2:--}"
  local color="${3:-defaut}"
  local long=$((${#texte} + 4))
  local separateur
  separateur="$(printf "%${long}s" | tr ' ' "$symbole")"
  echoColor "$color" "$separateur"
  echoColor "$color" "$symbole $texte $symbole"
  echoColor "$color" "$separateur"
  echo ""
}

function echoInformation { echo ""; echoColor "jaune" "ℹ️  $*"; echo ""; }
function echoCheck { echo ""; echoColor "vert" "✅ $*"; echo ""; }
function echoError { echo ""; echoColor "rouge" "❌ $*"; echo ""; }
function echoWarning { echo ""; echoColor "jaune" "⚠️ $*"; echo ""; }

# ================================================================
# Function: askQuestion
# Handles different question types: Open (QO), Yes/No (QF), Multiple Choice (QCM), Number (QN)
# Returns answer in variable: $response
# ================================================================

function askQuestion() {
    local prompt="$1"
    local qtype="${2:-QO}"
    shift 2
    local options=("$@")
    response=""

    case "$qtype" in
        QO) 
            read -rp "$prompt: " response
            ;;

        QF) 
            local yes_list=("Y" "Yes" "O" "Oui" "1")
            local no_list=("N" "No" "Non" "2")
            local answer=""
            while true; do
                echo -e "$prompt\n1) Yes\n2) No"
                read -rp "Choice: " answer
                answer="${answer^}"  # Capitalize first letter
                if [[ " ${yes_list[*]} " == *" $answer "* ]]; then
                    response="Yes"
                    break
                elif [[ " ${no_list[*]} " == *" $answer "* ]]; then
                    response="No"
                    break
                else
                    echo "Invalid choice, try again."
                fi
            done
            ;;

        QCM)
            local min=0 max=0
            local mod=""
            # Check if first argument is limit
            if [[ "$1" =~ ^([+-]?[0-9]+)$ ]]; then
                mod="$1"
                shift
                options=("$@")
            fi
            local n_options=${#options[@]}
            local selected=()
            while true; do
                echo "$prompt"
                for i in "${!options[@]}"; do
                    printf "%d) %s\n" $((i+1)) "${options[$i]}"
                done
                read -rp "Enter numbers separated by spaces (0 to cancel): " input
                [[ "$input" == "0" ]] && response="CANCEL" && return

                selected=()
                valid=true
                for num in $input; do
                    if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > n_options )); then
                        valid=false
                        break
                    fi
                    selected+=("${options[$((num-1))]}")
                done
                if ! $valid; then
                    echo "Invalid selection, try again."
                    continue
                fi

                # Apply limits if mod is set
                if [[ -n "$mod" ]]; then
                    if [[ "$mod" =~ ^\+([0-9]+)$ ]]; then
                        (( ${#selected[@]} < ${BASH_REMATCH[1]} )) && { echo "Select at least ${BASH_REMATCH[1]} items."; continue; }
                    elif [[ "$mod" =~ ^-([0-9]+)$ ]]; then
                        (( ${#selected[@]} > ${BASH_REMATCH[1]} )) && { echo "Select at most ${BASH_REMATCH[1]} items."; continue; }
                    else
                        (( ${#selected[@]} != mod )) && { echo "Select exactly $mod items."; continue; }
                    fi
                fi
                break
            done
            response="${selected[*]}"
            ;;

        QN)
            local min=${1:-}
            local max=${2:-}
            local number=""
            while true; do
                local prompt_text="$prompt"
                [[ -n "$min" && -n "$max" ]] && prompt_text+=" ($min-$max)"
                [[ -n "$min" && -z "$max" ]] && prompt_text+=" (>= $min)"
                [[ -z "$min" && -n "$max" ]] && prompt_text+=" (<= $max)"
                read -rp "$prompt_text: " number
                if ! [[ "$number" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                    echo "Please enter a valid number."
                    continue
                fi
                [[ -n "$min" && "$number" -lt "$min" ]] && { echo "Number too small."; continue; }
                [[ -n "$max" && "$number" -gt "$max" ]] && { echo "Number too large."; continue; }
                response="$number"
                break
            done
            ;;

        *)
            echo "Unknown question type: $qtype"
            ;;
    esac
}


# ================================================================
# Infos script
# ================================================================

function scriptInformation {
    clear
    title "$Lang_welcome $scriptName ($scriptAlias)" "#" "bleu"
    title "by $scriptCreator" "/" "blanc"
    echoColor "rouge" "Version: $scriptVersion"
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

    echoInformation "🖥️ OS : $OS_FAMILY / $OS_DISTRO / $OS_VERSION"
}

# Vérifier connexion internet
function checkInternet {
  echo "🔎 ${Lang_check_internet}..."
  if command -v curl >/dev/null 2>&1; then
    if curl -I -m 5 -s https://github.com >/dev/null; then
      echoCheck "${Lang_internet_ok}."
      return 0
    fi
  fi
  # fallback ping (Linux: -c ; Windows: -n)
  if ping -c 1 github.com >/dev/null 2>&1 || ping -n 1 github.com >/dev/null 2>&1; then
    echoCheck "${Lang_internet_ok}."
    return 0
  fi
  echoError "${Lang_internet_fail}."
  exit 1
}

# Charger les packages disponibles depuis JSON
function chargerpackages {
    if [[ ! -f "$PACKAGES_FILE" ]]; then
        echoError "$Lang_file_not_found : $PACKAGES_FILE"
        exit 1
    fi
    mapfile -t listepackages < <(jq -r '.packages[].name' "$PACKAGES_FILE" | sort)
}

# Charger un profil prédéfini depuis JSON
function loadProfile {
    local profil="$1"
    if [[ ! -f "$PROFILES_FILE" ]]; then
        echoError "${Lang_file_not_found} : $PROFILES_FILE"
        return 1
    fi
    jq -r --arg p "$profil" '.profiles[$p][]?' "$PROFILES_FILE"
}

function arrayToJson() {
    local arr=("$@")
    printf '%s\n' "${arr[@]}" | jq -R . | jq -s .
}

function managePackages {
    local package="$1"
    local action=""

    if [[ -z "$package" ]]; then
        PS3="$Lang_select_action : "
        select action in "$Lang_add" "$Lang_edit" "$Lang_delete" "$Lang_cancel"; do
            case $REPLY in
                1) action="add"; break ;;
                2) action="edit"; break ;;
                3) action="delete"; break ;;
                4) return ;;
                *) echo "$Lang_invalid_choice." ;;
            esac
        done
    else
        if jq -e --arg name "$package" '.packages[] | select(.name==$name)' "$PACKAGES_FILE" >/dev/null 2>&1; then
            action="edit"
        else
            action="add"
        fi
    fi

    # Si modification ou suppression, afficher une liste pour choisir le package
    if [[ "$action" == "edit" || "$action" == "delete" ]]; then
        mapfile -t package_list < <(jq -r '.packages[].name' "$PACKAGES_FILE")
        echo "📦 $available_packages :"
        select package in "${package_list[@]}" "Annuler"; do
            if [[ "$REPLY" -ge 1 && "$REPLY" -le "${#package_list[@]}" ]]; then
                break
            elif [[ "$REPLY" -eq $(( ${#package_list[@]} + 1 )) ]]; then
                return
            else
                echo "$invalid_choice."
            fi
        done
    fi

    case $action in
        delete)
            jq --arg name "$package" 'del(.packages[] | select(.name==$name))' "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"
            echo "🗑️ $Lang_package_deleted '$package'."
            ;;
        edit)
            echo "✏️ $Lang_package_modified '$package' :"
            read -p "Nouvelle description (laisser vide pour conserver) : " new_description
            read -p "Nouvelle catégorie (laisser vide pour conserver) : " new_category
            [[ -n "$new_description" ]] && jq --arg name "$package" --arg desc "$new_description" \
                '(.packages[] | select(.name==$name).description) |= $desc' "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"
            [[ -n "$new_category" ]] && jq --arg name "$package" --arg cat "$new_category" \
                '(.packages[] | select(.name==$name).category) |= $cat' "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"

            for os in linux windows macos; do
                echo "🖥️ Commandes existantes pour $os :"
                mapfile -t current_cmds < <(jq -r --arg name "$package" --arg os "$os" \
                    '.packages[] | select(.name==$name) | .[$os] // [] | if type=="array" then .[] else . end' "$PACKAGES_FILE")
                for c in "${current_cmds[@]}"; do echo " - $c"; done
                read -p "Ajouter une commande pour $os (laisser vide pour passer) : " cmd
                if [[ -n "$cmd" ]]; then
                    jq --arg name "$package" --arg os "$os" --arg cmd "$cmd" \
                        '(.packages[] | select(.name==$name) | .[$os]) += [$cmd]' "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"
                fi
            done
            ;;
        add)
            echo "➕ Ajout d'un nouveau package :"
            read -p "$Lang_name : " name
            package="$name"
            read -p "$Lang_description : " description
            read -p "$Lang_category : " category

            declare -a linux_cmds=()
            declare -a windows_cmds=()
            declare -a macos_cmds=()

            read -p "$Lang_command_line Linux (séparées par ';', laisser vide si aucune) : " input
            [[ -n "$input" ]] && IFS=';' read -r -a linux_cmds <<< "$input"
            read -p "$Lang_command_line Windows (séparées par ';', laisser vide si aucune) : " input
            [[ -n "$input" ]] && IFS=';' read -r -a windows_cmds <<< "$input"
            read -p "$Lang_command_line macOS (séparées par ';', laisser vide si aucune) : " input
            [[ -n "$input" ]] && IFS=';' read -r -a macos_cmds <<< "$input"

            linux_json=$(arrayToJson "${linux_cmds[@]}")
            windows_json=$(arrayToJson "${windows_cmds[@]}")
            macos_json=$(arrayToJson "${macos_cmds[@]}")

            jq --arg name "$package" --arg desc "$description" --arg cat "$category" \
               --argjson linux "$linux_json" --argjson windows "$windows_json" --argjson macos "$macos_json" \
               '.packages += [{"name":$name,"category":$cat,"description":$desc,"linux":$linux,"windows":$windows,"macos":$macos}]' \
               "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"

            echoCheck "$Lang_package_added : '$package'."
            ;;
    esac
}

download() {
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
                echo "🔄 $Lang_downloading $url"
                download "$url" "$fichier"
                ;;
            cache)
                echoCheck "$Lang_using_cache"
                ;;
            *)
                echo "📦 Le package '$nom' est déjà présent."
                read -p "Voulez-vous le re-télécharger ? (o/n) " rep
                if [[ "$rep" =~ ^[Oo]$ ]]; then
                    download "$url" "$fichier"
                else
                    echo "✅ Utilisation du fichier en cache"
                fi
                ;;
        esac
    else
        download "$url" "$fichier"
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

    echoCheck "$Lang_install_success : $nom"
}

# Installer un package
function installPackage {
    local package="$1"

    # Vérifie si le package est défini dans le fichier JSON
    local data
    data=$(jq -r --arg p "$package" '.packages[] | select(.name==$p)' "$PACKAGES_FILE")

    if [[ -z "$data" ]]; then
        echo "⚠️ package '$package' non référencé dans $PACKAGES_FILE"
        echo "➡️ Tentative d'installation automatique selon l'OS..."

        case "$OS_FAMILY" in
            Linux)
                case "$OS_DISTRO" in
                    ubuntu|debian)
                        sudo apt update
                        sudo apt install -y "$package"
                        ;;
                    fedora|rhel|centos)
                        sudo dnf install -y "$package"
                        ;;
                    arch|manjaro)
                        sudo pacman -Sy --noconfirm "$package"
                        ;;
                    *)
                        echo "⚠️ Distribution Linux $OS_DISTRO non supportée"
                        return 1
                        ;;
                esac
                jq --arg name "$package" \
                   '.packages += [{"name":$name,"description":"Ajout automatique","linux":["installation via gestionnaire"]}]' \
                   "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"
                ;;
            Windows)
                winget install -e --id "$package"
                jq --arg name "$package" \
                   '.packages += [{"name":$name,"description":"Ajout automatique","windows":["winget install -e --id " + $name]}]' \
                   "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"
                ;;
            MacOS)
                brew install "$package"
                jq --arg name "$package" \
                   '.packages += [{"name":$name,"description":"Ajout automatique","macos":["brew install " + $name]}]' \
                   "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"
                ;;
            *)
                echo "⚠️ OS non supporté"
                return 1
                ;;
        esac
        return 0
    fi

    title "📦 $Lang_installation : $package..." "+" "jaune"

    # Récupère URL ou commandes spécifiques
    local url
    local cmds=()
    case "$OS_FAMILY" in
        Linux)
            url=$(jq -r --arg p "$package" '.packages[] | select(.name==$p) | .urls.linux // empty' "$PACKAGES_FILE")
            mapfile -t cmds < <(jq -r --arg p "$package" '.packages[] | select(.name==$p) | .linux | if type=="array" then .[] else . end' "$PACKAGES_FILE")
            ;;
        Windows)
            url=$(jq -r --arg p "$package" '.packages[] | select(.name==$p) | .urls.windows // empty' "$PACKAGES_FILE")
            mapfile -t cmds < <(jq -r --arg p "$package" '.packages[] | select(.name==$p) | .windows | if type=="array" then .[] else . end' "$PACKAGES_FILE")
            ;;
        MacOS)
            url=$(jq -r --arg p "$package" '.packages[] | select(.name==$p) | .urls.macos // empty' "$PACKAGES_FILE")
            mapfile -t cmds < <(jq -r --arg p "$package" '.packages[] | select(.name==$p) | .macos | if type=="array" then .[] else . end' "$PACKAGES_FILE")
            ;;
    esac

    # Téléchargement si URL
    if [[ -n "$url" && "$url" != "null" ]]; then
        echo "🌍 $Lang_downloading : $url"
        installerDepuisLien "$url"
    fi

    # Exécution des commandes spécifiques
    if ((${#cmds[@]} > 0)); then
        echo "⚙️ $Lang_command_line_running : $package..."
        for cmd in "${cmds[@]}"; do
            echo "➡️ $cmd"
            eval "$cmd"
        done
    fi

    echoCheck "$Lang_install_success : $package"
}

# ================================================================
# IMPORT / EXPORT
# ================================================================

function exportPackages {
    title "$Lang_export_profile" "*" "cyan"

    # --- Étape 1 : Choix des profils existants
    echo "📂 $Lang_list_profile :"
    jq -r '.profiles | keys[]' profiles.json | nl -w2 -s". "
    read -p "👉 $Lang_select_number : " choixProfils

    packagesFusion=()

    if [[ -n "$choixProfils" ]]; then
        for num in $choixProfils; do
            profil=$(jq -r ".profiles | keys[$((num-1))]" profiles.json)
            if [[ "$profil" != "null" ]]; then
                mapfile -t tmp < <(jq -r ".profiles.\"$profil\"[]" profiles.json)
                packagesFusion+=("${tmp[@]}")
            fi
        done
    fi

    # --- Étape 2 : Ajouter des packages supplémentaires
    echo
    echo "📦 ${Lang_available_packages} : "
    jq -r '.packages[].name' packages.json | nl -w2 -s". "
    read -p "👉 $Lang_select_number : " choixPkgs

    if [[ -n "$choixPkgs" ]]; then
        for num in $choixPkgs; do
            package=$(jq -r ".packages[$((num-1))].name" packages.json)
            [[ "$package" != "null" ]] && packagesFusion+=("$package")
        done
    fi

    # --- Nettoyage doublons + tri alphabétique
    packagesFusion=($(printf "%s\n" "${packagesFusion[@]}" | sort -u))

    echo "${packageFusion[@]}"
    # --- Étape 3 : Nom du nouveau profil
    read -p "👉 Entrez le nom du nouveau profil : " newProfile
    [[ -z "$newProfile" ]] && newProfile="exported_profile"

    fichierMinimal="$newProfile.json"
    fichierComplet="$newProfile-full.json"

    # --- JSON minimal (noms seulement)
    jq -n --arg profil "$newProfile" \
        --argjson packages "$(printf '%s\n' "${packagesFusion[@]}" | jq -R . | jq -s .)" \
        '{($profil): $packages}' > "$fichierMinimal"

    # --- JSON complet (objets complets)
    # Crée un tableau avec tous les objets correspondant aux noms des packages fusionnés
    nomsJson=$(printf '%s\n' "${packagesFusion[@]}" | jq -R . | jq -s .)

    jq -n --arg profil "$newProfile" --argjson noms "$nomsJson" \
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
        jq --arg profil "$newProfile" \
           --argjson packages "$(printf '%s\n' "${packagesFusion[@]}" | jq -R . | jq -s .)" \
           '.profiles + {($profil): $packages} | {profiles: .}' profiles.json \
           > profiles.json.tmp && mv profiles.json.tmp profiles.json
        echo "✅ Profil ajouté à profiles.json"
    fi
}


function importPackages {
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

    local packages=()
    if [[ "$typeJSON" == "minimal" ]]; then
        packages=($(jq -r ".\"$cleProfil\"[]" "$fichier"))
    else
        # JSON complet : on récupère les noms et ajoute les packages inconnus dans packages.json
        mapfile -t packages < <(jq -r ".\"$cleProfil\"[].name" "$fichier")
        for p in "${packages[@]}"; do
            exists=$(jq -e --arg name "$p" '.packages[] | select(.name==$name)' packages.json >/dev/null 2>&1; echo $?)
            if [[ $exists -ne 0 ]]; then
                # Ajout automatique du package complet
                jq --argjson pkg "$(jq -r ".\"$cleProfil\"[] | select(.name==\"$p\")" "$fichier")" \
                   '.packages += [$pkg]' packages.json > packages.json.tmp && mv packages.json.tmp packages.json
                echo "➕ package inconnu '$p' ajouté dans packages.json"
            fi
        done
    fi

    # --- Supprimer doublons
    packages=($(printf "%s\n" "${packages[@]}" | sort -u))

    # --- Mise à jour profiles.json
    jq --arg profil "$cleProfil" --argjson packages "$(printf '%s\n' "${packages[@]}" | jq -R . | jq -s .)" \
       '.profiles + {($profil): $packages} | {profiles: .}' profiles.json > profiles.json.tmp && mv profiles.json.tmp profiles.json
    echo "✅ Profil '$cleProfil' ajouté ou mis à jour dans profiles.json"

    # --- Installation des packages
    echo "📦 Installation des packages du profil : ${packages[*]}"
    for p in "${packages[@]}"; do
        installPackage "$p"
    done
}

# ================================================================
# MISE A JOUR AUTO
# ================================================================

function checkUpdate {
    # Déduire les URLs des JSON depuis url_script
    url_base="${url_script%/*}/"          # base : https://raw.githubusercontent.com/.../Prototype/
    url_lang="${url_base}lang.json"
    url_packages="${url_base}packages.json"
    url_profiles="${url_base}profiles.json"

    checkInternet

    # Vérifier et télécharger lang.json si absent
    if [[ ! -f "$LANG_FILE" ]]; then
        echoWarning "${Lang_file_not_found:-File not found :} $LANG_FILE, ${Lang_downloading:-Downloading}..."
        if download "$url_packages" "$LANG_FILE"; then
            echoCheck "${Lang_download_ok:-Downloaded}$LANG_FILE."
        else
            echoError "${Lang_download_failed:-Download failed} $LANG_FILE"
        fi
    fi

    # Vérifier et télécharger packages.json si absent
    if [[ ! -f "$PACKAGES_FILE" ]]; then
        echoWarning "${Lang_file_not_found:-File not found :} $PACKAGES_FILE, ${Lang_downloading:-Downloading}..."
        if download "$url_packages" "$PACKAGES_FILE"; then
            echoCheck "${Lang_download_ok:-Downloaded}$PACKAGES_FILE."
        else
            echoError "${Lang_download_failed:-Download failed} $PACKAGES_FILE"
        fi
    fi

    # Vérifier et télécharger profiles.json si absent
    if [[ ! -f "$PROFILES_FILE" ]]; then
        echoWarning "${Lang_file_not_found:-File not found :} $PROFILES_FILE ${Lang_downloading:-Downloading}..."
        if download "$url_packages" "$PROFILES_FILE"; then
            echoCheck "${Lang_download_ok:-Downloaded} $PROFILES_FILE"
        else
            echoError "${Lang_download_failed:-Download failed} $PROFILES_FILE"
        fi
    fi

    # Vérification de la version du script
    echo "🔎 ${Lang_update_check:-Cheking for update}"
    versionEnLigne="$(download "$url_version")"

    if [[ -z "$versionEnLigne" ]]; then
        echoWarning "${Lang_unable_check_version:-Unable to check latest version}"
        return
    fi

    if [[ "$versionEnLigne" != "$scriptVersion" ]]; then
        echoWarning "${Lang_update_available:-New version available} $versionEnLigne (actuelle : $scriptVersion)"
        read -p "${Lang_update_prompt:-Update now ?} (o/n) " rep
        if [[ "$rep" =~ ^[Oo]$ ]]; then
            echo "⬇️ ${Lang_downloading_new_version:-Downloading the new version}..."
            download "$url_script" "$0"
            chmod +x "$0"
            echoCheck "${Lang_update_done:-Updated. Restarting...}"
            exec "$0" "$@"   # Relance automatique du script
        fi
    else
        echoCheck "${Lang_update_none:- UPI is up to date (version %s)}"
    fi
}

# ================================================================
# Mise à jour système
# ================================================================

function majSysteme {
    title "Mise à jour et vérification des dépendances" "=" "jaune"

    checkInternet

    if [[ "$OS_FAMILY" == "Linux" ]]; then
        echo "🔄 Mise à jour du système Linux ($OS_DISTRO $OS_VERSION)..."

        # Détecter le gestionnaire de packages disponible
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
            echo "⚠️ Aucun gestionnaire de packages reconnu sur cette distribution."
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
            "4" "Exporter les packages" \
            "5" "Gérer les packages" \
            "0" "Quitter" 3>&1 1>&2 2>&3)

        case $choix in
            1) menuWhiptailPersonnalise ;;
            2) menuWhiptailProfil ;;
            3) importPackages ;;
            4) exportPackages ;;
            5) managePackages ;;
            0) exit ;;
        esac
    done
}

function menuWhiptailPersonnalise {
    local options=()
    mapfile -t packages < <(jq -r '.packages[] | "\(.name)|\(.description)"' "$PACKAGES_FILE")

    for line in "${packages[@]}"; do
        IFS="|" read -r name desc <<< "$line"
        options+=("$name" "$desc" OFF)
    done

    choix=$(whiptail --title "Choix des packages" \
                     --checklist "Sélectionnez :" 20 78 10 \
                     "${options[@]}" 3>&1 1>&2 2>&3)

    for p in $choix; do
        installPackage "$(echo "$p" | tr -d '"')"
    done
}

function menuWhiptailProfil {
    if [[ ! -f "$PROFILES_FILE" ]]; then
        echo "❌ Fichier $PROFILES_FILE introuvable"
        return 1
    fi

    # Construit des paires [profil] [description] triées par nom
    local options=()
    while IFS='|' read -r key count; do
        options+=("$key" "$count package(s)")
    done < <(jq -r '.profiles | to_entries[] | "\(.key)|\(.value|length)"' "$PROFILES_FILE" | sort -t'|' -k1,1)

    if ((${#options[@]} == 0)); then
        echo "❌ Aucun profil trouvé dans $PROFILES_FILE"
        return 1
    fi

    # Affiche le menu avec paires tag/description
    local choix
    choix=$(whiptail --title "Choix du profil" \
                     --menu "Sélectionnez :" 20 78 10 \
                     "${options[@]}" 3>&1 1>&2 2>&3)

    # Annulation (ESC) ou vide → on sort proprement
    [[ -z "$choix" ]] && return 0

    # Récupère les packages du profil choisi et lance l'installation
    mapfile -t packages < <(loadProfile "$choix")
    if ((${#packages[@]} == 0)); then
        echo "⚠️ Aucun package dans le profil « $choix »"
        return 0
    fi

    for p in "${packages[@]}"; do
        installPackage "$p"
    done
}

function menuWhiptailProfil {
    if [[ ! -f "$PROFILES_FILE" ]]; then
        echo "❌ Fichier $PROFILES_FILE introuvable"
        return 1
    fi

    # Construit des paires [profil] [description] triées par nom
    local options=()
    while IFS='|' read -r key count; do
        options+=("$key" "$count package(s)")
    done < <(jq -r '.profiles | to_entries[] | "\(.key)|\(.value|length)"' "$PROFILES_FILE" | sort -t'|' -k1,1)

    if ((${#options[@]} == 0)); then
        echo "❌ Aucun profil trouvé dans $PROFILES_FILE"
        return 1
    fi

    # Affiche le menu avec paires tag/description
    local choix
    choix=$(whiptail --title "Choix du profil" \
                     --menu "Sélectionnez :" 20 78 10 \
                     "${options[@]}" 3>&1 1>&2 2>&3)

    # Annulation (ESC) ou vide → on sort proprement
    [[ -z "$choix" ]] && return 0

    # Récupère les packages du profil choisi et lance l'installation
    mapfile -t packages < <(loadProfile "$choix")
    if ((${#packages[@]} == 0)); then
        echo "⚠️ Aucun package dans le profil « $choix »"
        return 0
    fi

    for p in "${packages[@]}"; do
        installPackage "$p"
    done
}

function menu {
    while true; do
        title "$scriptName" "W" "jaune"
        echo "1) ${Lang_personalized:-Personalized}"
        echo "2) ${Lang_by_profile:-By profile}"
        echo "3) ${Lang_import_list:-Import list}"
        echo "4) ${Lang_export_packages:-Export packages}"
        echo "5) ${Lang_manage_packages:-Manage packages}"
        echo "0) ${Lang_exit:-Exit}"
        echo ""
        read -p "${Lang_your_choice:-Your choice}" choice
        case "$choice" in
            1) menuPersonnalise ;;
            2) menuProfile ;;
            3) importPackages ;;
            4) exportPackages ;;
            5) managePackages ;;
            0) exit ;;
            *) echoError "${Lang_invalid_choice:-Invalid choice}" ;;
        esac
    done
}

function menuPersonnalise {
    if [[ ! -f "$PACKAGES_FILE" ]]; then
        echoError "${Lang_file_not_found:-File not found}: $PACKAGES_FILE"
        return 1
    fi

    # Charger et trier les paquets
    mapfile -t packagesList < <(jq -r '.packages[] | "\(.name)|\(.description)"' "$PACKAGES_FILE" | sort -t'|' -k1,1)
    (( ${#packagesList[@]} == 0 )) && { echoError "${Lang_no_packages:-No packages available}"; return 1; }

    while true; do
        echo ""
        title "${Lang_available_packages:-Available packages}" "-" "cyan"
        for i in "${!packagesList[@]}"; do
            IFS="|" read -r pkgName pkgDesc <<< "${packagesList[$i]}"
            printf "%2d) %s : %s\n" $((i+1)) "$pkgName" "$pkgDesc"
        done
        echo " 0) ${Lang_back:-Back to menu}"
        echo ""

        read -p "${Lang_choose_packages:-Enter package numbers or names (0 to go back): } " userChoice
        [[ -z "$userChoice" ]] && continue
        [[ "$userChoice" == "0" ]] && return 0

        for choice in $userChoice; do
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >=1 && choice <= ${#packagesList[@]} )); then
                idx=$((choice-1))
                IFS="|" read -r pkgName _ <<< "${packagesList[$idx]}"
                installPackage "$pkgName"
            else
                # Considérer que l’utilisateur a entré un nom directement
                installPackage "$choice"
            fi
        done
    done
}

function menuProfile {
    if [[ ! -f "$PROFILES_FILE" ]]; then
        echoError "${Lang_profile_not_found:-File not found}: $PROFILES_FILE"
        return 1
    fi

    mapfile -t profiles < <(jq -r '.profiles | to_entries[] | "\(.key)|\(.value|length)"' "$PROFILES_FILE" | sort -t'|' -k1,1)
    (( ${#profiles[@]} == 0 )) && { echoError "${Lang_no_profiles:-No profiles available}"; return 1; }

    while true; do
        echo ""
        title "${Lang_available_profiles:-Available profiles}" "-" "cyan"
        for i in "${!profiles[@]}"; do
            IFS='|' read -r name count <<< "${profiles[$i]}"
            printf "%2d) %s (%s)\n" $((i+1)) "$name" "$(printf "${Lang_packages_count:-%s package(s)}" "$count")"
        done
        echo " 0) ${Lang_back:-Back to menu}"
        echo ""

        read -p "${Lang_choose_number:-Choose number (0 to go back): }" choice
        [[ "$choice" == "0" ]] && return 0

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >=1 && choice <= ${#profiles[@]} )); then
            idx=$((choice - 1))
            IFS='|' read -r selected _ <<< "${profiles[$idx]}"
            mapfile -t packages < <(jq -r --arg p "$selected" '.profiles[$p][]?' "$PROFILES_FILE")
            if ((${#packages[@]} == 0)); then
                echoError "${Lang_no_package_found:-No packages found} « $selected »"
                continue
            fi
            for pkg in "${packages[@]}"; do
                installPackage "$pkg"
            done
            return 0
        else
            echoError "${Lang_invalid_number:-Invalid number, try again}"
        fi
    done
}

# ================================================================
# MAIN
# ================================================================

load_language "fr"
scriptInformation
detecterOS
checkUpdate
majSysteme
chargerpackages
eval "$GUI"
