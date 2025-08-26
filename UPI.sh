#!/usr/bin/env bash
# ================================================================
# UniversalPackageInstaller (UPI)
# Auteur : WilliamWolfy
# Description : Gestion universelle des packages (Linux & Windows)
# - Tous les packages et profils sont externalisés dans des files JSON
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

GUI="menuMain"

# ================================================================
# Utilitaires d'affichage
# ================================================================

# ================================================================
# load_language
# EN: Load i18n strings from lang.json into environment variables.
#     - Accepts two formats:
#       A) “new” format (recommended): top-level keys are Lang_* and
#          each key maps to an object of languages: { "Lang_foo": { "en": "...", "fr": "..." } }
#       B) “old” format: top-level languages then keys:
#          { "en": { "Lang_foo": "..." }, "fr": { "Lang_foo": "..." } }
#     - Auto-converts (B) -> (A) if needed.
#     - Ensures ALL keys are prefixed with "Lang_" (auto-rewrite file if not).
#     - Loads ONLY the selected language, with fallback to "en" then "fr".
#
# FR : Charge les chaînes i18n depuis lang.json dans des variables.
#      - Accepte deux formats (nouveau et ancien), convertit si nécessaire.
#      - Garantit le préfixe "Lang_" pour toutes les clés.
#      - Ne charge que la langue choisie, avec retombée sur "en" puis "fr".
# ================================================================
# Function to load and normalize language file
function load_language {
    local lang_file="lang.json"
    local temp_file="lang.tmp.json"
    local backup_file="lang.json.bak"

    [[ ! -f "$lang_file" ]] && { echo "❌ $lang_file missing"; return 1; }

    # Backup before modification
    cp "$lang_file" "$backup_file"

    # Step 1: normalize keys (ensure Lang_ prefix)
    jq 'to_entries
        | map(
            { 
              key: (if (.key | startswith("Lang_")) then .key else "Lang_" + .key end), 
              value: .value 
            }
          )
        | from_entries' "$lang_file" > "$temp_file"

    mv "$temp_file" "$lang_file"

    # Step 2: detect duplicates and merge preferring richest entry
    jq 'to_entries
        | group_by(.key)
        | map(
            if length == 1 then .[0]
            else
                # Choose the entry with the most languages
                (.[]
                 | {key: .key, value: .value}
                ) as $all
                | reduce $all as $item (
                    {key: .[0].key, value: {}};
                    if ($item.value | length) > (.value | length)
                    then .value = $item.value
                    else .
                    end
                )
            end
        )
        | from_entries' "$lang_file" > "$temp_file"

    mv "$temp_file" "$lang_file"

    echo "✅ $lang_file normalized and cleaned (backup in $backup_file)"

    # Step 3: load variables into bash
    local lang="${LANGUAGE:-fr}"
    while IFS="=" read -r key val; do
        # Remove quotes
        val="${val%\"}"
        val="${val#\"}"
        export "$key"="$val"
    done < <(jq -r --arg l "$lang" 'to_entries | map("\(.key)=\(.value[$l] // .value["en"])") | .[]' "$lang_file")
}

function echoColor {
  local color="$1"; shift
  local text="$*"
  local default="\033[0m"
  declare -A c=(
    ["black"]="\033[30m" ["red"]="\033[31m" ["green"]="\033[32m"
    ["yellow"]="\033[33m" ["blue"]="\033[34m" ["magenta"]="\033[35m"
    ["cyan"]="\033[36m" ["white"]="\033[37m" ["default"]="\033[0m"
  )
  if [[ -n "${c[$color]}" ]]; then
    echo -e "${c[$color]}$text$default"
  else
    echo -e "$text"
  fi
}

function title {
  local text="$1"
  local symbole="${2:--}"
  local color="${3:-default}"
  local long=$((${#text} + 4))
  local separator
  separator="$(printf "%${long}s" | tr ' ' "$symbole")"
  echoColor "$color" "$separator"
  echoColor "$color" "$symbole $text $symbole"
  echoColor "$color" "$separator"
  echo ""
}

function echoInformation { echo ""; echoColor "yellow" "ℹ️  $*"; echo ""; }
function echoCheck { echo ""; echoColor "green" "✅ $*"; echo ""; }
function echoError { echo ""; echoColor "red" "❌ $*"; echo ""; }
function echoWarning { echo ""; echoColor "yellow" "⚠️ $*"; echo ""; }

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
    title "$Lang_welcome $scriptName ($scriptAlias)" "#" "blue"
    title "by $scriptCreator" "/" "white"
    echoColor "red" "Version: $scriptVersion"
    echo ""
}

# ================================================================
# FONCTIONS UTILITAIRES
# ================================================================

function detectOS {
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
function loadPackages {
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

    title "Manage Packages"

    if [[ -z "$package" ]]; then
        PS3="${Lang_select_action:-Select action :}"
        select action in "${Lang_add:-Add}" "${Lang_edit:-Edit}" "${Lang_delete:-Delete}" "${Lang_cancel:-Cancel}"; do
            case $REPLY in
                1) action="add"; break ;;
                2) action="edit"; break ;;
                3) action="delete"; break ;;
                4) return ;;
                *) echoError "${Lang_invalid_choice:-Invalid choice}" ;;
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
                echoError "${Lang_invalid_choice:-Invalid choice}"
            fi
        done
    fi

    case $action in
        delete)
            jq --arg name "$package" 'del(.packages[] | select(.name==$name))' "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"
            echo "🗑️ ${Lang_package_deleted:-Package deleted} '$package'."
            ;;
        edit)
            echo "✏️ ${Lang_package_modified:-Package modified} '$package' :"
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
            echo "➕ ${Lang_prompt_new_package:-Added a new package} :"
            read -p "${Lang_name:-Name} : " name
            package="$name"
            read -p "${Lang_description:-Description} : " description
            read -p "${Lang_category:-Category} : " category

            declare -a linux_cmds=()
            declare -a windows_cmds=()
            declare -a macos_cmds=()

            read -p "${Lang_command_line:-Command line} Linux (séparées par ';', laisser vide si aucune) : " input
            [[ -n "$input" ]] && IFS=';' read -r -a linux_cmds <<< "$input"
            read -p "${Lang_command_line:-Command line} Windows (séparées par ';', laisser vide si aucune) : " input
            [[ -n "$input" ]] && IFS=';' read -r -a windows_cmds <<< "$input"
            read -p "${Lang_command_line:-Command line} macOS (séparées par ';', laisser vide si aucune) : " input
            [[ -n "$input" ]] && IFS=';' read -r -a macos_cmds <<< "$input"

            linux_json=$(arrayToJson "${linux_cmds[@]}")
            windows_json=$(arrayToJson "${windows_cmds[@]}")
            macos_json=$(arrayToJson "${macos_cmds[@]}")

            jq --arg name "$package" --arg desc "$description" --arg cat "$category" \
               --argjson linux "$linux_json" --argjson windows "$windows_json" --argjson macos "$macos_json" \
               '.packages += [{"name":$name,"category":$cat,"description":$desc,"linux":$linux,"windows":$windows,"macos":$macos}]' \
               "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"

            echoCheck "${Lang_package_added:-Package added} : '$package'."
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
        # Mode écriture dans file
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
    local file="$dossier_cache/$nom"

    # Mode cache par défaut
    local CACHE_MODE="normal"
    for arg in "$@"; do
        case "$arg" in
            --force-download) CACHE_MODE="force" ;;
            --cache-only) CACHE_MODE="cache" ;;
        esac
    done

    # Vérification du file existant
    if [[ -f "$file" ]]; then
        case "$CACHE_MODE" in
            force)
                echo "🔄 $Lang_downloading $url"
                download "$url" "$file"
                ;;
            cache)
                echoCheck "$Lang_using_cache"
                ;;
            *)
                echo "📦 Le package '$nom' est déjà présent."
                read -p "Voulez-vous le re-télécharger ? (o/n) " rep
                if [[ "$rep" =~ ^[Oo]$ ]]; then
                    download "$url" "$file"
                else
                    echo "✅ Utilisation du file en cache"
                fi
                ;;
        esac
    else
        download "$url" "$file"
    fi

    # Décompression automatique pour archives
    local unpack_dir="$dossier_cache/unpacked"
    mkdir -p "$unpack_dir"
    case "$file" in
        *.zip) unzip -o "$file" -d "$unpack_dir" ;;
        *.tar.gz|*.tgz) tar -xzf "$file" -C "$unpack_dir" ;;
        *.tar.xz) tar -xJf "$file" -C "$unpack_dir" ;;
    esac

    # Installation selon l'OS et type de file
    case "$OS_FAMILY" in
        Linux)
            if [[ "$file" =~ \.deb$ ]]; then
                echo "➡️ Installation .deb"
                sudo dpkg -i "$file" 2>/dev/null || sudo apt-get install -f -y
            elif [[ "$file" =~ \.rpm$ ]]; then
                echo "➡️ Installation .rpm"
                if command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y "$file" || sudo yum localinstall -y "$file"
                else
                    sudo yum localinstall -y "$file"
                fi
            elif [[ "$file" =~ \.AppImage$ ]]; then
                chmod +x "$file"
                sudo mv "$file" /usr/local/bin/
            elif [[ -x "$file" ]]; then
                bash "$file"
            fi
            ;;
        Windows)
            if [[ "$file" =~ \.exe$ ]]; then
                "$file" /quiet /norestart || "$file"
            elif [[ "$file" =~ \.msi$ ]]; then
                msiexec /i "$file" /quiet /norestart
            elif [[ "$file" =~ \.zip$ ]]; then
                unzip -o "$file" -d "$HOME/AppData/Local/"
            fi
            ;;
        MacOS)
            if [[ "$file" =~ \.dmg$ ]]; then
                mkdir -p "$dossier_cache/mnt"
                hdiutil attach "$file" -mountpoint "$dossier_cache/mnt"
                cp -r "$dossier_cache/mnt"/*.app /Applications/
                hdiutil detach "$dossier_cache/mnt"
            elif [[ "$file" =~ \.pkg$ ]]; then
                sudo installer -pkg "$file" -target /
            elif [[ "$file" =~ \.zip$ ]]; then
                unzip -o "$file" -d /Applications/
            fi
            ;;
    esac

    echoCheck "$Lang_install_success : $nom"
}

# Installer un package
function installPackage {
    local package="$1"

    # Vérifie si le package est défini dans le file JSON
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

    title "📦 $Lang_installation : $package..." "+" "yellow"

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
    title "${Lang_export_profile:-Export profile}" "*" "cyan"

    # --- Étape 1 : Choix des profils existants
    echo "📂 ${Lang_list_profiles:-List of profiles}"
    jq -r '.profiles | keys[]' profiles.json | nl -w2 -s". "
    read -p "👉 ${Lang_select_profile_prompt:-Enter profile number(s) (space separated, 0 to cancel): }" choixProfils

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
    echo "📦 ${Lang_available_packages:-Available packages} : "
    jq -r '.packages[].name' packages.json | nl -w2 -s". "
    read -p "👉 ${Lang_choose_packages:-Enter package numbers or names (space separated, 0 to go back):}" choixPkgs

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
    read -p "👉 ${Lang_prompt_profile_name:-Enter export filename (default: %s): } " newProfile
    [[ -z "$newProfile" ]] && newProfile="exported_profile"

    fileMinimal="$newProfile.json"
    fileComplet="$newProfile-full.json"

    # --- JSON minimal (noms seulement)
    jq -n --arg profil "$newProfile" \
        --argjson packages "$(printf '%s\n' "${packagesFusion[@]}" | jq -R . | jq -s .)" \
        '{($profil): $packages}' > "$fileMinimal"

    # --- JSON complet (objets complets)
    # Crée un tableau avec tous les objets correspondant aux noms des packages fusionnés
    nomsJson=$(printf '%s\n' "${packagesFusion[@]}" | jq -R . | jq -s .)

    jq -n --arg profil "$newProfile" --argjson noms "$nomsJson" \
        --slurpfile allPackages packages.json \
        '{
            ($profil): $allPackages[0].packages | map(select(.name as $n | $n | IN($noms[])))
        }' > "$fileComplet"

    echoCheck "${Lang_file_exported:-File exported}"
    echo "   - Minimal : $fileMinimal"
    echo "   - Complet : $fileComplet"

    # --- Étape 4 : Ajouter à profiles.json ?
    read -p "👉 ${Lang_promt_profile_add:-Add this profile to profiles.json? (y/n)}" reponse
    if [[ "$reponse" =~ ^[oOyY]$ ]]; then
        jq --arg profil "$newProfile" \
           --argjson packages "$(printf '%s\n' "${packagesFusion[@]}" | jq -R . | jq -s .)" \
           '.profiles + {($profil): $packages} | {profiles: .}' profiles.json \
           > profiles.json.tmp && mv profiles.json.tmp profiles.json
        echoCheck "${Lang_profile_added:-Profile added to profiles.json}"
    fi
}

# ============================================================
# importPackages
# ------------------------------------------------------------
# FR : Importer un profil de paquets depuis un fichier JSON.
# EN : Import a package profile from a JSON file.
# ============================================================
function importPackages {
    local file="$1"

    # --- Ask for file if not provided
    if [[ -z "$file" ]]; then
        title "${Lang_select_file_import:-Select file to import}" "-" "cyan"
        local files=($(ls "$(dirname "$0")"/*.json 2>/dev/null))
        
        if [[ ${#files[@]} -eq 0 ]]; then
            read -rp "${Lang_no_json_found:-No JSON file found. Enter full path: }" file
        else
            echo " 0) ${Lang_custom_path:-Enter a custom path}"
            for i in "${!files[@]}"; do
                echo " $((i+1))) ${files[$i]}"
            done
            read -rp "${Lang_choose_file:-Choose: }" choix
            if [[ "$choix" == "0" ]]; then
                read -rp "${Lang_enter_full_path:-Enter full path: }" file
            elif [[ "$choix" =~ ^[0-9]+$ ]] && (( choix > 0 && choix <= ${#files[@]} )); then
                file="${files[$((choix-1))]}"
            else
                echoError "${Lang_invalid_choice:-Invalid choice}"
                return 1
            fi
        fi
    fi

    # --- Check file existence
    if [[ ! -f "$file" ]]; then
        echoError "${Lang_file_not_found:-File not found}: $file"
        return 1
    fi

    # --- Detect JSON type
    local typeJSON="minimal"
    local profileKey
    profileKey=$(jq -r 'keys[0]' "$file" 2>/dev/null)
    if jq -e ".\"$profileKey\"[0] | type == \"object\"" "$file" >/dev/null 2>&1; then
        typeJSON="complete"
    fi

    echoInformation "📂 $(printf "${Lang_import_profile:-Importing profile: %s (%s)}" "$profileKey" "$typeJSON")"

    local packages=()
    if [[ "$typeJSON" == "minimal" ]]; then
        packages=($(jq -r ".\"$profileKey\"[]" "$file"))
    else
        # JSON complete: fetch package names and add unknown ones to packages.json
        mapfile -t packages < <(jq -r ".\"$profileKey\"[].name" "$file")
        for p in "${packages[@]}"; do
            if ! jq -e --arg name "$p" '.packages[] | select(.name==$name)' packages.json >/dev/null 2>&1; then
                jq --argjson pkg "$(jq ".\"$profileKey\"[] | select(.name==\"$p\")" "$file")" \
                   '.packages += [$pkg]' packages.json > packages.json.tmp && mv packages.json.tmp packages.json
                echoCheck "➕ $(printf "${Lang_added_unknown_package:-Unknown package '%s' added to packages.json}" "$p")"
            fi
        done
    fi

    # --- Remove duplicates
    packages=($(printf "%s\n" "${packages[@]}" | sort -u))

    # --- Update profiles.json
    jq --arg profile "$profileKey" --argjson packages "$(printf '%s\n' "${packages[@]}" | jq -R . | jq -s .)" \
       '.profiles + {($profile): $packages} | {profiles: .}' profiles.json > profiles.json.tmp && mv profiles.json.tmp profiles.json
    echoCheck "✅ $(printf "${Lang_profile_added:-Profile '%s' added or updated in profiles.json}" "$profileKey")"

    # --- Install packages
    echoInformation "📦 $(printf "${Lang_installing_packages:-Installing packages from profile: %s}" "${packages[*]}")"
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
    title "Mise à jour et vérification des dépendances" "=" "yellow"

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
            GUI="menuMain"
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
        GUI="menuMain"

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
        echo "❌ file $PROFILES_FILE introuvable"
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
        echo "❌ file $PROFILES_FILE introuvable"
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

# ================================================================
# menuMain
# EN: Text menu using i18n strings and display helpers.
# FR : Menu texte utilisant les chaînes i18n et les helpers d’affichage.
# ================================================================
function menuMain() {
  while true; do
    title "$scriptName" "W" "yellow"
    echo "1) ${Lang_personalized:-Personalized}"
    echo "2) ${Lang_by_profile:-By profile}"
    echo "3) ${Lang_import_list:-Import list}"
    echo "4) ${Lang_export_packages:-Export packages}"
    echo "5) ${Lang_manage_packages:-Manage packages}"
    echo "0) ${Lang_exit:-Exit}"
    echo ""

    read -rp "${Lang_your_choice:-Your choice: }" _sel
    case "$_sel" in
      1) menuCustom ;;      # (ou menuPersonnalise si tu n’as pas encore renommé)
      2) menuProfile ;;
      3) importPackages ;;
      4) exportPackages ;;
      5) managePackages ;;
      0) return 0 ;;
      *) echoError "${Lang_invalid_choice:-Invalid choice}" ;;
    esac
  done
}

function menuCustom {
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

# ================================================================
# menuProfile
# EN: Show available profiles (numbered), let user choose by number.
#     - 0 returns to previous menu
#     - loops on invalid input
# FR : Affiche les profils (numérotés), choix par numéro.
#      - 0 pour revenir en arrière
#      - boucle si saisie invalide
# ================================================================
function menuProfile() {
  if [[ ! -f "$PROFILES_FILE" ]]; then
    echoError "${Lang_profile_not_found:-Profile file not found}: $PROFILES_FILE"
    return 1
  fi

  # Build "name|count" list, sorted by name
  mapfile -t _profiles < <(jq -r '.profiles | to_entries[] | "\(.key)|\(.value|length)"' "$PROFILES_FILE" | sort -t'|' -k1,1)
  (( ${#_profiles[@]} == 0 )) && { echoError "${Lang_no_profiles:-No profiles available}"; return 1; }

  while true; do
    echo ""
    title "${Lang_available_profiles:-Available profiles}" "-" "cyan"

    for i in "${!_profiles[@]}"; do
      IFS='|' read -r _name _count <<< "${_profiles[$i]}"
      # "Lang_packages_count" expected to be a printf-style pattern like "%s package(s)"
      printf "%2d) %s (%s)\n" $((i+1)) "$_name" "$(printf "${Lang_packages_count:-%s package(s)}" "$_count")"
    done
    echo " 0) ${Lang_back:-Back}"
    echo ""

    read -rp "${Lang_choose_number:-Choose a number (0 to go back): }" _choice
    # Go back
    [[ "$_choice" == "0" ]] && return 0
    # Only numeric, in range
    if [[ "$_choice" =~ ^[0-9]+$ ]] && (( _choice >= 1 && _choice <= ${#_profiles[@]} )); then
      local _idx=$((_choice - 1))
      IFS='|' read -r _selected _ <<< "${_profiles[$_idx]}"

      # Load packages of the chosen profile
      mapfile -t _pkgs < <(jq -r --arg p "$_selected" '.profiles[$p][]?' "$PROFILES_FILE")
      if ((${#_pkgs[@]} == 0)); then
        echoWarning "${Lang_no_package_found:-No packages found} « $_selected »"
        continue
      fi

      echoInformation "$(printf "${Lang_installing_profile:-Installing profile: %s}" "$_selected")"
      for _p in "${_pkgs[@]}"; do
        installPackage "$_p"
      done

      echoCheck "${Lang_profile_done:-Profile installation finished}."
      return 0
    else
      echoError "${Lang_invalid_number:-Invalid number, try again.}"
    fi
  done
}

# ================================================================
# MAIN
# ================================================================

load_language "fr"
scriptInformation
detectOS
checkUpdate
majSystem
loadPackages
eval "$GUI"
