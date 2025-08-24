#!/bin/bash
################################################################################
# UniversalPackageInstaller (UPI) - Script Linux avec JSON
# Auteur : William Wolfy
# Version : 1.0.0
# Licence : MIT
################################################################################

scriptNom="UniversalPackageInstaller"
scriptAlias="upi"
scriptVersion="1.0.0"
scriptRepertoire="$(pwd)"

# Fichier JSON
json_url="https://raw.githubusercontent.com/WilliamWolfy/UniversalPackageInstaller/main/bibliotheque.json"
json_local="$HOME/upi_bibliotheque.json"

# OS détecté : "Linux", "Windows", "Inconnu"
systeme="Inconnu"

# Logs
listeDesPaquetsInstaller=()

# Bibliothèque
declare -A paquetsCategorie
declare -A paquetsDescriptif
declare -A paquetsDepot
declare -A paquetsCommande

declare -A profilsPredefinis
paquetsListe=()

#########################
# Fonctions d’affichage #
#########################

# Affichage couleur
function echoCouleur {
  local couleur="$1"; shift
  local texte="$*"
  local defaut="\033[0m"
  declare -A c=( ["noir"]="\033[30m" ["rouge"]="\033[31m" ["vert"]="\033[32m"
                 ["jaune"]="\033[33m" ["bleu"]="\033[34m" ["magenta"]="\033[35m"
                 ["cyan"]="\033[36m" ["blanc"]="\033[37m" ["defaut"]="\033[0m" )
  echo -e "${c[$couleur]}$texte$defaut"
}

# Titre encadré avec motif et couleur
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

function information { echoCouleur "bleu" "ℹ️  $*"; echo ""; }

#########################
# Vérifications système #
#########################

function detecterSysteme {
  case "$(uname -s)" in
    Linux*)  systeme="Linux" ;;
    CYGWIN*|MINGW*|MSYS*) systeme="Windows" ;;
    *)       systeme="Inconnu" ;;
  esac
  # winget sous Git Bash/MSYS peut s’appeler winget.exe
  if [[ "$systeme" == "Windows" ]]; then
    if command -v winget.exe >/dev/null 2>&1; then
      WINGET_CMD="winget.exe"
    fi
  fi
  echo "🖥️  Système détecté : $systeme"
}

# Connexion Internet
function checkInternet {
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

# Vérification mise à jour script
function check_update {
    url_version="https://google.com/version.txt"
    versionEnLigne=$(curl -s "$url_version")
    if [[ -n "$versionEnLigne" && "$versionEnLigne" != "$scriptVersion" ]]; then
        echoCouleur "jaune" "⚠️ Nouvelle version : $versionEnLigne (actuelle : $scriptVersion)"
        echo "👉 Téléchargez la dernière version depuis GitHub"
    else
        echo "✅ UPI est à jour (v$scriptVersion)"
    fi
}


#####################################
# Téléchargement et lecture du JSON #
#####################################

function charger_json {
    if [[ ! -f "$json_local" ]]; then
        echo "📥 Téléchargement de la bibliothèque depuis GitHub..."
        curl -s -o "$json_local" "$json_url" || { echoCouleur "rouge" "Erreur : impossible de récupérer la bibliothèque JSON."; exit 1; }
    fi

    # Lecture paquets
    paquetsListe=($(jq -r '.paquets[].nom' "$json_local" | sort))
    for row in $(jq -c '.paquets[]' "$json_local"); do
        nom=$(echo "$row" | jq -r '.nom')
        paquetsCategorie["$nom"]=$(echo "$row" | jq -r '.categorie')
        paquetsDescriptif["$nom"]=$(echo "$row" | jq -r '.descriptif')
        paquetsDepot["$nom"]=$(echo "$row" | jq -r '.depot')
        paquetsCommande["$nom"]=$(echo "$row" | jq -r '.commande')
    done

    # Lecture profils
    for profile in $(jq -r '.profils | keys[]' "$json_local"); do
        profilsPredefinis["$profile"]=$(jq -r ".profils[\"$profile\"] | join(\" \")" "$json_local")
    done
}

##########################
# Installation selective #
##########################

function installation {
    local choix=("$@")
    local total=${#choix[@]}
    local compteur=0

    for paquet in "${choix[@]}"; do
        titre "$paquet" "-" "jaune"
        information "${paquetsDescriptif[$paquet]}"

        [[ -n "${paquetsDepot[$paquet]}" ]] && sudo add-apt-repository -y "${paquetsDepot[$paquet]}"

        eval "${paquetsCommande[$paquet]}"
        listeDesPaquetsInstaller+=("$paquet")
        compteur=$((compteur+1))
        information "✅ Installé ($compteur/$total)"
    done
}

###################
# Menu interactif #
###################

function ui_menu {
    local title="$1"; shift
    local prompt="$1"; shift
    local items=("$@")
    echo "== $title =="
    echo "$prompt"
    local i=1
    for it in "${items[@]}"; do printf "%2d) %s\n" "$i" "$it"; i=$((i+1)); done
    read -rp "Votre choix (numéro) : " idx
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx>=1 && idx<=${#items[@]} )); then
        echo "${items[$((idx-1))]}"
    else
        echo ""
    fi
}

function menuPrincipal {
    while true; do
        local choix
        choix=$(ui_menu "$scriptNom - Mode d'installation" "Choisissez un mode :" \
            "Installation personnalisée" \
            "Installation complète" \
            "Installation par configuration prédéfinie" \
            "Quitter")

        case "$choix" in
            "Installation personnalisée") menuPersonnalise ;;
            "Installation complète") installation "${paquetsListe[@]}" ;;
            "Installation par configuration prédéfinie") menuConfig ;;
            "Quitter") exit 0 ;;
        esac
    done
}

function menuPersonnalise {
    echo "Paquets disponibles :"
    for p in "${paquetsListe[@]}"; do echo " - $p"; done
    read -rp "Entrez les paquets à installer (séparés par espaces) : " selection
    installation $selection
}

function menuConfig {
    echo "Profils disponibles :"
    for k in "${!profilsPredefinis[@]}"; do echo " - $k"; done
    read -rp "Choisissez un profil : " profil
    [[ -n "${profilsPredefinis[$profil]}" ]] && installation ${profilsPredefinis[$profil]}
}

########
# Main #
########

function main {
    titre "Bienvenue dans $scriptNom ($scriptAlias)" "#" "vert"
    detecterSysteme
    checkInternet
    check_update
    charger_json
    menuPrincipal
}

main
