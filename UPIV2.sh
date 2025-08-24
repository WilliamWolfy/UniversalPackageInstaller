#!/usr/bin/env bash
# ==========================================================
# UniversalPackageInstaller (UPI) v1.0.0
# Alias : upi
#
# Script universel pour installer des logiciels
# sous Linux (apt/snap) et Windows (UnigetUI/winget).
#
# - Détection automatique de l'OS
# - Vérification de la connexion Internet
# - Vérification de mise à jour via GitHub
# - Bibliothèque de paquets unifiée
# - Profils prédéfinis (Gamer, Dev, Bureautique, etc.)
# - Tri alphabétique des paquets/profils
#
# ==========================================================
scriptNom="UniversalPackageInstaller"
scriptAlias="upi"
scriptCreateur="William Wolfy"
scriptVersion="1.0.0"           # ⚠️ Pense à aligner avec version.txt sur GitHub
url_version="https://raw.githubusercontent.com/WilliamWolfy/UniversalPackageInstaller/refs/heads/main/version.txt"
scriptRepertoire="$(pwd)"
OS="Inconnu"
debug=0

declare -A paquetsListe
declare -A paquetsDescriptif
declare -A paquetsCategorie
declare -A paquetsDepot
declare -A paquetsCommandeLinux
declare -A paquetsCommandeWindows
declare -A profilsPredefinis

###########################
# Utilitaires d'affichage #
###########################

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

function information { echoCouleur "bleu" "ℹ️  $*"; echo ""; }

################
# Détection OS #
################

function detecterOS {
  case "$(uname -s)" in
    Linux*)  OS="Linux" ;;
    CYGWIN*|MINGW*|MSYS*) OS="Windows" ;;
    *)       OS="Inconnu" ;;
  esac
  # winget sous Git Bash/MSYS peut s’appeler winget.exe
  if [[ "$OS" == "Windows" ]]; then
    if command -v winget.exe >/dev/null 2>&1; then
      WINGET_CMD="winget.exe"
    fi
  fi
  echo "🖥️  Système détecté : $OS"
}

################
# Infos script #
################

function scriptInformation {
  titre "Bienvenue dans $scriptNom ($scriptAlias)" "#" "vert"
  titre "Créé par $scriptCreateur" "/" "cyan"
  information "Version: $scriptVersion"
  echo ""
}

###############################
# Vérifier connexion internet #
###############################

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

# ######################
# Vérifier mise à jour #
# ######################

function checkUpdate {
    versionEnLigne="$(curl -s "$url_version")"
    if [[ -n "$versionEnLigne" && "$versionEnLigne" != "$scriptVersion" ]]; then
        echoCouleur "jaune" "⚠️ Nouvelle version : $versionEnLigne (actuelle : $scriptVersion)"
        echo "👉 Téléchargez la dernière version depuis GitHub"
    else
        echo "✅ UPI est à jour (v$scriptVersion)"
    fi
}

#######################
# Mise à jour système #
#######################

function majSysteme {

  titre "Mise à jour du système et des dépendances utile au fonctionnement du script" "=" "jaune"

  if [ "$OS" == "Linux" ]
  then sudo apt update && sudo apt upgrade -y
  fi

  if [ "$OS" == "Windows" ]
  then control update
    upgrade --uninstall-previous
    winget install --id MartiCliment.UniGetUI -e --accept-source-agreements --accept-package-agreements
  fi
}

#######################################
# Ajouter un paquet à la bibliothèque #
#######################################

function bibliothequePaquets {
    local nom="$1" categorie="$2" descriptif="$3" depot="$4" cmdLinux="$5" cmdWindows="$6"

    paquetsListe["$nom"]="$nom"
    paquetsCategorie["$nom"]="$categorie"
    paquetsDescriptif["$nom"]="$descriptif"
    paquetsDepot["$nom"]="$depot"
    paquetsCommandeLinux["$nom"]="$cmdLinux"
    paquetsCommandeWindows["$nom"]="$cmdWindows"
}

#########################
# Installation multi-OS #
#########################

function installation {
    local choix=("$@")
    local total=${#choix[@]}
    local compteur=0

    for paquet in "${choix[@]}"; do
        if [[ -n "${paquetsListe[$paquet]}" ]]; then
            titre "➡️ Installation de $paquet..." "+" "vert"
            if [[ "$OS" == "Linux" ]]; then
                [[ -n "${paquetsDepot[$paquet]}" ]] && sudo add-apt-repository -y "${paquetsDepot[$paquet]}"
                eval "${paquetsCommandeLinux[$paquet]}"
            elif [[ "$OS" == "Windows" ]]
            then eval "${paquetsCommandeWindows[$paquet]}"
            fi
            compteur=$((compteur+1))
            echoCouleur "vert" "✅ $paquet installé ($compteur/$total)"
        else
            echoCouleur "rouge" "❌ Paquet inconnu : $paquet"
        fi
    done
}
#########################
# Menu Linux (whiptail) #
# #######################

function menuLinux {
    while true; do
        choix=$(whiptail --title "UniversalPackageInstaller (UPI)" \
            --menu "Que voulez-vous faire ?" 20 78 10 \
            "1" "Installation personnalisée" \
            "2" "Installation par catégorie" \
            "3" "Configuration prédéfinie" \
            "4" "Tout installer" \
            "0" "Quitter" \
            3>&1 1>&2 2>&3)

        case $choix in
            1) menuPersonnalise ;;
            2) menuCategorie ;;
            3) menuConfig ;;
            4) installation $(printf "%s\n" "${!paquetsListe[@]}" | sort) ;;
            0) exit ;;
        esac
    done
}

function menuPersonnalise {
    local options=()
    for p in $(printf "%s\n" "${!paquetsListe[@]}" | sort); do
        options+=("$p" "${paquetsDescriptif[$p]}" "OFF")
    done
    selection=$(whiptail --title "Choix des paquets" \
        --checklist "Sélectionnez vos paquets :" 20 78 10 "${options[@]}" \
        3>&1 1>&2 2>&3)
    installation $(echo $selection | tr -d '"')
}

function menuCategorie {
    categories=($(printf "%s\n" "${paquetsCategorie[@]}" | sort -u))
    choixCategorie=$(whiptail --title "Choix catégorie" \
        --menu "Choisissez une catégorie :" 20 78 10 \
        $(for c in "${categories[@]}"; do echo "$c" "-"; done) \
        3>&1 1>&2 2>&3)

    selection=()
    for p in $(printf "%s\n" "${!paquetsListe[@]}" | sort); do
        [[ "${paquetsCategorie[$p]}" == "$choixCategorie" ]] && selection+=("$p")
    done
    installation "${selection[@]}"
}

function menuConfig {
    local options=()
    for profil in $(printf "%s\n" "${!profilsPredefinis[@]}" | sort); do
        options+=("$profil" "-")
    done
    choix=$(whiptail --title "Profils prédéfinis" \
        --menu "Choisissez un profil :" 20 78 10 "${options[@]}" \
        3>&1 1>&2 2>&3)
    [[ -n "$choix" ]] && installation ${profilsPredefinis[$choix]}
}

################################
# Menu Windows (console texte) #
################################
function menuWindows {
    while true; do
        echo ""
        titre "UniversalPackageInstaller (UPI) - Windows" "-" "jaune"
        echo "1) Installation personnalisée"
        echo "2) Installation par catégorie"
        echo "3) Configuration prédéfinie"
        echo "4) Tout installer"
        echo "0) Quitter"
        read -p "Votre choix : " choix
        case $choix in
            1) menuWindowsPersonnalise ;;
            2) menuWindowsCategorie ;;
            3) menuWindowsConfig ;;
            4) installation $(printf "%s\n" "${!paquetsListe[@]}" | sort) ;;
            0) exit ;;
        esac
    done
}

function menuWindowsPersonnalise {
    echo "Paquets disponibles (triés) :"
    for p in $(printf "%s\n" "${!paquetsListe[@]}" | sort); do
        echo " - $p : ${paquetsDescriptif[$p]}"
    done
    read -p "Indiquez les paquets à installer (séparés par des espaces) : " choix
    installation $choix
}

function menuWindowsConfig {
    echo "Profils disponibles (triés) :"
    for profil in $(printf "%s\n" "${!profilsPredefinis[@]}" | sort); do
        echo " - $profil"
    done
    read -p "Quel profil voulez-vous installer ? " choix
    installation ${profilsPredefinis[$choix]}
}

########
# Menu #
########
function menu {
  if [[ "$OS" == "Linux" ]]
  then menuLinux
  elif [[ "$OS" == "Windows" ]]
  then menuWindows
  else
    echo "❌ OS non reconnu"
    exit 1
  fi
}

#######################################################################################
# === DÉFINITION DES PAQUETS (Open Source) ===                                        #
# Chaque entrée : Nom / Catégorie / Descriptif / Dépôt(Linux) / CmdLinux / CmdWindows #
#######################################################################################

# Outils d’archives (bundle)
bibliothequePaquets "Zip" "Outils" \
  "Ensemble d’outils pour fichiers compressés (zip, 7z, rar, etc.)." \
  "" \
  "sudo apt install -y rar unrar zip unzip p7zip-full p7zip-rar sharutils arj cabextract file-roller" \
  "$WINGET_CMD install --id 7zip.7zip --silent --accept-package-agreements --accept-source-agreements"

# Curl / Htop / Neofetch (utilitaires)
bibliothequePaquets "Curl" "Outils" \
  "Client HTTP/FTP en ligne de commande, très utile pour scripts et diagnostics." \
  "" \
  "sudo apt install -y curl" \
  "$WINGET_CMD install --id cURL.cURL --silent --accept-package-agreements --accept-source-agreements"

bibliothequePaquets "Htop" "Outils" \
  "Moniteur de processus interactif en TUI (alternative améliorée à top)." \
  "" \
  "sudo apt install -y htop" \
  "$WINGET_CMD install --id htop.htop --silent --accept-package-agreements --accept-source-agreements"

bibliothequePaquets "Neofetch" "Outils" \
  "Affiche les infos système de manière esthétique dans le terminal." \
  "" \
  "sudo apt install -y neofetch || sudo apt install -y neofetch || true" \
  ""  # (optionnel sous Windows)

# Navigateurs
bibliothequePaquets "Brave" "Navigateur" \
  "Navigateur axé confidentialité, rapide, avec modes avancés." \
  "" \
  'sudo apt install -y curl && \
   if [[ ! -f /usr/share/keyrings/brave-browser-archive-keyring.gpg ]]; then \
     sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg; \
   fi && \
   if [[ ! -f /etc/apt/sources.list.d/brave-browser-release.sources ]]; then \
     sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources; \
   fi && \
   sudo apt update && sudo apt install -y brave-browser' \
  '$WINGET_CMD install --id Brave.Brave --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Firefox" "Navigateur" \
  "Navigateur libre de la fondation Mozilla." \
  "" \
  "sudo apt install -y firefox" \
  '$WINGET_CMD install --id Mozilla.Firefox --silent --accept-package-agreements --accept-source-agreements'

# Multimédia
bibliothequePaquets "VLC" "Multimedia" \
  "Lecteur multimédia libre supportant la quasi-totalité des formats." \
  "" \
  "sudo apt install -y vlc" \
  '$WINGET_CMD install --id VideoLAN.VLC --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Audacity" "Multimedia" \
  "Éditeur audio libre : enregistrement et traitement du son." \
  "" \
  "sudo apt install -y audacity" \
  '$WINGET_CMD install --id Audacity.Audacity --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "OBS" "Multimedia" \
  "OBS Studio : streaming et enregistrement vidéo open-source." \
  "" \
  "sudo apt install -y obs-studio" \
  '$WINGET_CMD install --id OBSProject.OBSStudio --silent --accept-package-agreements --accept-source-agreements'

# Graphisme / 3D
bibliothequePaquets "GIMP" "Graphisme" \
  "Retouche d’image avancée, alternative libre à Photoshop." \
  "" \
  "sudo apt install -y gimp" \
  '$WINGET_CMD install --id GIMP.GIMP --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Inkscape" "Graphisme" \
  "Éditeur vectoriel libre, alternative à Illustrator." \
  "" \
  "sudo apt install -y inkscape" \
  '$WINGET_CMD install --id Inkscape.Inkscape --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Blender" "3D" \
  "Suite libre de modélisation et animation 3D." \
  "" \
  "sudo apt install -y blender" \
  '$WINGET_CMD install --id BlenderFoundation.Blender --silent --accept-package-agreements --accept-source-agreements'

# Bureautique / Cloud / Communication
bibliothequePaquets "LibreOffice" "Bureautique" \
  "Suite bureautique libre (Writer, Calc, Impress…)." \
  "" \
  "sudo apt install -y libreoffice" \
  '$WINGET_CMD install --id TheDocumentFoundation.LibreOffice --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "OnlyOffice" "Bureautique" \
  "Suite bureautique collaborative compatible MS Office." \
  "" \
  "sudo snap install onlyoffice-desktopeditors" \
  '$WINGET_CMD install --id ONLYOFFICE.DesktopEditors --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Thunderbird" "Communication" \
  "Client e-mail open-source avec calendrier et extensions." \
  "" \
  "sudo apt install -y thunderbird" \
  '$WINGET_CMD install --id Mozilla.Thunderbird --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Signal" "Communication" \
  "Messagerie chiffrée de bout en bout (open-source)." \
  "" \
  "sudo snap install signal-desktop" \
  '$WINGET_CMD install --id OpenWhisperSystems.Signal --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Element" "Communication" \
  "Client Matrix open-source pour chat/chambres/communautés." \
  "" \
  "sudo snap install element-desktop" \
  '$WINGET_CMD install --id Element.Element --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Nextcloud" "Cloud" \
  "Synchronisation/partage de fichiers auto-hébergés (client desktop)." \
  "" \
  "sudo snap install nextcloud" \
  '$WINGET_CMD install --id Nextcloud.NextcloudDesktop --silent --accept-package-agreements --accept-source-agreements'

# Dev / Virtualisation
bibliothequePaquets "Git" "Développement" \
  "Système de gestion de versions distribué." \
  "" \
  "sudo apt install -y git" \
  '$WINGET_CMD install --id Git.Git --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "GitHub" "Développement" \
  "GitHub CLI : gérer GitHub depuis le terminal." \
  "" \
  "sudo apt install -y gh || { (type -p wget >/dev/null || (sudo apt update && sudo apt install -y wget)) && \
   sudo mkdir -p -m 755 /etc/apt/keyrings && out=$(mktemp) && \
   wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg && \
   cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null && \
   sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
   sudo mkdir -p -m 755 /etc/apt/sources.list.d && \
   echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | \
   sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null && sudo apt update && sudo apt install -y gh; }" \
  '$WINGET_CMD install --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "VSCode" "Développement" \
  "Éditeur de code populaire, extensible." \
  "" \
  "sudo snap install code --classic" \
  '$WINGET_CMD install --id Microsoft.VisualStudioCode --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "NodeJS" "Développement" \
  "Runtime JavaScript côté serveur." \
  "" \
  "sudo apt install -y nodejs npm" \
  '$WINGET_CMD install --id OpenJS.NodeJS --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Python" "Développement" \
  "Langage polyvalent pour scripts, data, web…" \
  "" \
  "sudo apt install -y python3 python3-pip" \
  '$WINGET_CMD install --id Python.Python.3 --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Docker" "Développement" \
  "Moteur de conteneurs (Linux : paquet communautaire docker.io)." \
  "" \
  "sudo apt install -y docker.io" \
  ""  # Docker Desktop Windows n’est pas OSS → pas installé ici

bibliothequePaquets "VirtualBox" "Virtualisation" \
  "Virtualisation d’OS (machines virtuelles)." \
  "" \
  "sudo apt install -y virtualbox" \
  '$WINGET_CMD install --id Oracle.VirtualBox --silent --accept-package-agreements --accept-source-agreements'

# Réseaux / DNS
bibliothequePaquets "Unbound" "DNS" \
  "Résolveur DNS récursif local (sécurité et confidentialité)." \
  "" \
  'sudo apt install -y unbound && \
   sudo tee /etc/unbound/unbound.conf >/dev/null <<EOF
server:
  verbosity: 1
  interface: 127.0.0.1
  access-control: 127.0.0.0/8 allow
  do-ip4: yes
  do-udp: yes
  hide-identity: yes
  hide-version: yes
forward-zone:
  name: "."
  forward-addr: 1.1.1.1
  forward-addr: 8.8.8.8
EOF
   sudo systemctl restart unbound' \
  ''  # (facultatif sous Windows)

# Outils spécifiques Ubuntu
bibliothequePaquets "Snapd" "Outils" \
  "Gestionnaire de paquets Snap pour installer des applications sandboxées." \
  "" \
  "sudo apt install -y snapd && sudo snap install snap-store" \
  ""  # non applicable Windows

bibliothequePaquets "Cubic" "Outils" \
  "Création d’images ISO Ubuntu personnalisées." \
  "ppa:cubic-wizard/release" \
  "sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 6494C6D6997C215E && sudo apt update && sudo apt install -y cubic" \
  ""  # non applicable Windows

bibliothequePaquets "RPI" "Outils" \
  "Écriture simple d’OS sur cartes SD pour Raspberry Pi." \
  "" \
  "sudo apt install -y rpi-imager" \
  '$WINGET_CMD install --id RaspberryPiFoundation.RaspberryPiImager --silent --accept-package-agreements --accept-source-agreements'

# Jeux
bibliothequePaquets "Steam" "Jeux" \
  "Plateforme de jeux avec compatibilité Proton sous Linux." \
  "" \
  "sudo apt install -y steam-installer || sudo apt install -y steam" \
  '$WINGET_CMD install --id Valve.Steam --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Lutris" "Jeux" \
  "Gestionnaire de jeux open-source (intègre Proton/Wine, GOG, etc.)." \
  "" \
  "sudo apt install -y lutris" \
  '$WINGET_CMD install --id Lutris.Lutris --silent --accept-package-agreements --accept-source-agreements'

# Associatif (⚠ LibreAssOS s’appuie sur ces paquets)
bibliothequePaquets "Dolibarr" "Associatif" \
  "ERP/CRM libre pour associations et PME." \
  "" \
  "sudo snap install dolibarr" \
  ""  # pas d’ID winget officiel standard

bibliothequePaquets "Jitsi" "Communication" \
  "Jitsi (attention : le paquet jitsi-meet est côté serveur). Pour client bureau, préférer 'Jitsi Meet Desktop' (snap) si besoin." \
  "" \
  "sudo apt install -y jitsi-meet || true" \
  ""  # (client desktop différent sur Windows)

######################
# Profils prédéfinis #
######################
profilsPredefinis["Minimal"]="VLC"
profilsPredefinis["Bureautique"]="LibreOffice GIMP"
profilsPredefinis["Gamer"]="Steam Lutris VLC"
profilsPredefinis["Developpeur"]="Git VSCode NodeJS Python"
profilsPredefinis["Créatif"]="GIMP Inkscape Blender Audacity"
profilsPredefinis["Complet"]="$(printf "%s\n" "${!paquetsListe[@]}" | sort)"
profilsPredefinis["LibreAssOS"]="... (inchangé)"

########
# Main #
#########
scriptInformation
detecterOS
checkInternet
checkUpdate
majSysteme
menu
