#!/usr/bin/env bash
################################################################################
# UniversalPackageInstaller (UPI)
# Alias   : upi
# Auteur  : William Wolfy
# Version : 1.0.0
# Licence : MIT
#
# Description :
#   Script d’installation universel (Linux/Windows) basé sur une bibliothèque
#   centralisée de paquets. Permet :
#     - Installation personnalisée (checklist), complète, par catégorie, ou profil
#     - Export / import de profils
#     - Détection OS (Linux/Windows) et commandes adaptées
#     - Vérification connexion Internet
#     - Vérification de mise à jour (GitHub - URL factice à remplacer)
#
# Remarques :
#   - Sous Linux : APT/SNAP (Ubuntu/Debian).
#   - Sous Windows : installation via winget ; UnigetUI est installé au démarrage
#     si absent (interface graphique pratique, sans CLI officielle → winget reste
#     le moteur d’install en script).
################################################################################

##############################################
# Variables globales
##############################################
scriptNom="UniversalPackageInstaller"
scriptAlias="upi"
scriptCreateur="William Wolfy"
scriptVersion="1.0.0"           # ⚠️ Pense à aligner avec version.txt sur GitHub
scriptRepertoire="$(pwd)"
debug=0

# OS détecté : "Linux", "Windows", "Inconnu"
systeme="Inconnu"
WINGET_CMD="winget"             # sera ajusté à winget.exe si nécessaire

# Logs
listeDesRepositoryInstaller=()
listeDesPaquetsInstaller=()

# Bibliothèque
declare -A paquetsListe           # clé=Nom → Nom
declare -A paquetsCategorie       # clé=Nom → Catégorie
declare -A paquetsDescriptif      # clé=Nom → Descriptif
declare -A paquetsDepot           # clé=Nom → Dépôt (Linux)
declare -A paquetsCommandeLinux   # clé=Nom → Commande Linux
declare -A paquetsCommandeWindows # clé=Nom → Commande Windows (winget)

# Profils prédéfinis (⚠ LibreAssOS intact)
declare -A profilsPredefinis
# Les valeurs sont des listes de clés (noms de paquets) séparées par des espaces.
# "Complet" sera calculé dynamiquement (toute la bibliothèque).
profilsPredefinis["Minimal"]="VLC Zip Curl"
profilsPredefinis["Gamer"]="Steam Lutris OBS VLC"
profilsPredefinis["Bureautique"]="LibreOffice OnlyOffice Thunderbird Signal GIMP Inkscape VLC"
profilsPredefinis["Developpeur"]="Git GitHub VSCode NodeJS Python Docker VirtualBox Brave Neofetch Htop"
profilsPredefinis["Creatif"]="GIMP Inkscape Blender Audacity OBS VLC"
# 🔒 NE PAS MODIFIER
profilsPredefinis["LibreAssOS"]="LibreOffice OnlyOffice Dolibarr Nextcloud Thunderbird Signal Jitsi GIMP Inkscape VLC Brave OBS"

##############################################
# Utilitaires d'affichage
##############################################
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

##############################################
# Vérifications système
##############################################
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

function checkUpdate {
  echo "🔎 Vérification des mises à jour..."
  # ⚠️ URL factice à remplacer par ton dépôt
  local url_version="https://raw.githubusercontent.com/WilliamWolfy/UniversalPackageInstaller/main/version.txt"
  local versionEnLigne
  versionEnLigne="$(curl -m 5 -s "$url_version" || true)"
  if [[ -n "$versionEnLigne" && "$versionEnLigne" != "$scriptVersion" ]]; then
    echo "⚠️  Nouvelle version disponible : $versionEnLigne (actuelle : $scriptVersion)"
    echo "👉 Mets à jour depuis ton dépôt GitHub."
  else
    echo "✅ UPI est à jour (v$scriptVersion)."
  fi
}

# Windows : garantir UnigetUI (installé via winget)
function ensureUnigetUI {
  [[ "$systeme" != "Windows" ]] && return 0
  if ! command -v "$WINGET_CMD" >/dev/null 2>&1; then
    echo "❌ winget n’est pas disponible. Mettez Windows à jour (App Installer requis)."
    return 1
  fi
  # Vérifie si UnigetUI est présent
  if "$WINGET_CMD" show --id "marticliment.UnigetUI" >/dev/null 2>&1; then
    echo "✅ UnigetUI détecté."
    return 0
  fi
  echo "📦 Installation d’UnigetUI (Windows)..."
  "$WINGET_CMD" install --id "marticliment.UnigetUI" --silent --accept-package-agreements --accept-source-agreements
}

##############################################
# Logs
##############################################
function logRepository {
  listeDesRepositoryInstaller+=("$1")
  echo "$1" >> ListeDesRepositoryInstaller.txt
}
function logPaquets {
  listeDesPaquetsInstaller+=("$1")
  echo "$1" >> ListeDesPaquetsInstaller.txt
}

##############################################
# Système (Linux)
##############################################
function majSysteme {
  [[ "$systeme" != "Linux" ]] && return 0
  sudo apt update && sudo apt upgrade -y
}

##############################################
# Bibliothèque : ajout d’un paquet
##############################################
# Usage:
# bibliothequePaquets "Ajouter" "Nom" "Catégorie" "Descriptif" "DepotLinux|vide" "CommandeLinux" "CommandeWindows"
function bibliothequePaquets {
  local action="$1" nom="$2" categorie="$3" descriptif="$4" depot="$5" cmdLinux="$6" cmdWindows="$7"
  if [[ "$action" == "Ajouter" ]]; then
    paquetsListe["$nom"]="$nom"
    paquetsCategorie["$nom"]="$categorie"
    paquetsDescriptif["$nom"]="$descriptif"
    paquetsDepot["$nom"]="$depot"
    paquetsCommandeLinux["$nom"]="$cmdLinux"
    paquetsCommandeWindows["$nom"]="$cmdWindows"
  fi
}

##############################################
# Installation
##############################################
function installation {
  local choix=("$@")
  local total=${#choix[@]}
  local compteur=0

  for paquet in "${choix[@]}"; do
    if [[ -n "${paquetsListe[$paquet]}" ]]; then
      titre "$paquet" "-" "jaune"
      information "${paquetsDescriptif[$paquet]}"

      if [[ "$systeme" == "Linux" && -n "${paquetsDepot[$paquet]}" ]]; then
        # Ajout du dépôt si fourni
        sudo add-apt-repository -y "${paquetsDepot[$paquet]}"
        logRepository "${paquetsDepot[$paquet]}"
      fi

      # Exécution commande adaptée
      if [[ "$systeme" == "Linux" ]]; then
        eval "${paquetsCommandeLinux[$paquet]}"
      elif [[ "$systeme" == "Windows" ]]; then
        # UnigetUI obligatoire (installation si manquant)
        ensureUnigetUI
        if [[ -n "${paquetsCommandeWindows[$paquet]}" ]]; then
          eval "${paquetsCommandeWindows[$paquet]}"
        else
          echoCouleur "rouge" "⚠️ $paquet : non défini pour Windows (ignoré)."
        fi
      else
        echoCouleur "rouge" "⚠️ OS non supporté pour $paquet."
        continue
      fi

      logPaquets "$paquet"
      compteur=$((compteur+1))
      information "✅ Installé ($compteur/$total)"
    else
      echoCouleur "rouge" "⚠️ Paquet inconnu: $paquet"
    fi
  done
}

##############################################
# Export / Import de profils
##############################################
function exportPaquets {
  local profile
  profile="$(ui_input "Nom du profil à exporter (ex: gamer, dev, bureautique)" "monprofil")" || return 1
  [[ -z "$profile" ]] && { echoCouleur "rouge" "⚠️ Aucun nom saisi, export annulé."; return 1; }
  local filename="export_${profile}.txt"
  printf "%s\n" "${listeDesPaquetsInstaller[@]}" > "$filename"
  information "✅ Profil exporté dans $filename"
}

function exportProfilPredefini {
  local nom="$1"
  local liste="${profilsPredefinis[$nom]}"
  local filename="export_${nom,,}.txt"
  echo $liste | tr ' ' '\n' > "$filename"
  information "✅ Profil prédéfini \"$nom\" exporté dans $filename"
}

function importPaquets {
  local files=(export_*.txt)
  if [[ ! -e "${files[0]}" ]]; then
    echoCouleur "rouge" "⚠️ Aucun fichier d’export trouvé."
    return
  fi
  local choix
  choix="$(ui_menu "Importer un profil" "Choisissez un fichier d’export :" "${files[@]}")" || return 1
  [[ -z "$choix" ]] && { echoCouleur "rouge" "⚠️ Aucun fichier sélectionné."; return 1; }

  mapfile -t paquetsToInstall < "$choix"
  information "Import de ${#paquetsToInstall[@]} paquets depuis $choix..."
  installation "${paquetsToInstall[@]}"
}

##############################################
# Wrappers UI : whiptail si dispo, sinon fallback texte
##############################################
have_whiptail=0
if command -v whiptail >/dev/null 2>&1; then have_whiptail=1; fi

# ui_menu "Titre" "Message" item1 item2 item3 ...
function ui_menu {
  local title="$1"; shift
  local prompt="$1"; shift
  local items=("$@")

  if [[ $have_whiptail -eq 1 ]]; then
    # Construire paires "item" "desc" (desc vide)
    local opts=()
    for it in "${items[@]}"; do opts+=("$it" ""); done
    whiptail --title "$title" --menu "$prompt" 20 78 10 "${opts[@]}" 3>&1 1>&2 2>&3
    return $?
  else
    echo "== $title =="
    echo "$prompt"
    local i=1
    for it in "${items[@]}"; do printf "%2d) %s\n" "$i" "$it"; i=$((i+1)); done
    read -rp "Votre choix (numéro) : " idx
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx>=1 && idx<=${#items[@]} )); then
      echo "${items[$((idx-1))]}"
      return 0
    else
      return 1
    fi
  fi
}

# ui_checklist "Titre" "Message" items...
# Retourne liste (séparée par espaces) sur stdout
function ui_checklist {
  local title="$1"; shift
  local prompt="$1"; shift
  local items=("$@")
  if [[ $have_whiptail -eq 1 ]]; then
    local opts=()
    for it in "${items[@]}"; do
      opts+=("$it" "" "OFF")
    done
    whiptail --title "$title" --checklist "$prompt" 20 78 12 "${opts[@]}" 3>&1 1>&2 2>&3
    return $?
  else
    echo "== $title =="
    echo "$prompt"
    printf "%s\n" "${items[@]}"
    read -rp "Saisissez les éléments souhaités (séparés par des espaces) : " line
    echo "$line"
    return 0
  fi
}

# ui_input "Message" "defaut"
function ui_input {
  local prompt="$1"; local def="${2:-}"
  if [[ $have_whiptail -eq 1 ]]; then
    whiptail --inputbox "$prompt" 10 70 "$def" 3>&1 1>&2 2>&3
    return $?
  else
    read -rp "$prompt [$def]: " ans
    echo "${ans:-$def}"
    return 0
  fi
}

##############################################
# Menus interactifs
##############################################
function menuPrincipal {
  while true; do
    local choix
    choix="$(ui_menu "$scriptNom - Mode d'installation" "Choisissez un mode :" \
      "Installation personnalisée" \
      "Installation complète" \
      "Installation par catégorie" \
      "Installation par configuration prédéfinie" \
      "Exporter la liste installée (profil)" \
      "Importer et installer depuis un profil exporté" \
      "Quitter")" || exit 0

    case "$choix" in
      "Installation personnalisée") menuPersonnalise ;;
      "Installation complète") installation "${!paquetsListe[@]}" ;;
      "Installation par catégorie") menuCategorie ;;
      "Installation par configuration prédéfinie") menuConfig ;;
      "Exporter la liste installée (profil)") exportPaquets ;;
      "Importer et installer depuis un profil exporté") importPaquets ;;
      "Quitter") exit 0 ;;
    esac
  done
}

function menuPersonnalise {
  local options=()
  # Montrer les noms (les descriptifs restent consultables lors de l'install)
  for p in "${!paquetsListe[@]}"; do options+=("$p"); done
  local selection
  selection="$(ui_checklist "Installation personnalisée" "Sélectionnez vos paquets :" "${options[@]}")" || return 1
  [[ -z "$selection" ]] && { echoCouleur "rouge" "⚠️ Aucun paquet sélectionné."; return 1; }
  # Nettoyage guillemets si whiptail
  selection="$(echo "$selection" | tr -d '"')"
  # Conversion en tableau robuste
  # shellcheck disable=SC2206
  local paquetsChoisis=( $selection )
  installation "${paquetsChoisis[@]}"
}

function menuCategorie {
  # Liste unique des catégories
  mapfile -t categories < <(printf "%s\n" "${paquetsCategorie[@]}" | sort -u)
  local choixCategorie
  choixCategorie="$(ui_menu "Installation par catégorie" "Choisissez une catégorie :" "${categories[@]}")" || return 1

  local selection=()
  for p in "${!paquetsListe[@]}"; do
    [[ "${paquetsCategorie[$p]}" == "$choixCategorie" ]] && selection+=("$p")
  done
  installation "${selection[@]}"
}

function menuConfig {
  local nomsProfils=()
  for k in "${!profilsPredefinis[@]}"; do nomsProfils+=("$k"); endone=false; done
  local choix
  choix="$(ui_menu "Configurations prédéfinies" "Choisissez une configuration :" "${nomsProfils[@]}")" || return 1

  if [[ -n "$choix" ]]; then
    local paquets
    if [[ "$choix" == "Complet" ]]; then
      # Tous les paquets connus au moment du clic
      paquets="${!paquetsListe[@]}"
    else
      paquets="${profilsPredefinis[$choix]}"
    fi
    information "Installation du profil $choix..."
    exportProfilPredefini "$choix"
    # shellcheck disable=SC2086
    installation $paquets
  fi
}

##############################################
# Infos script
##############################################
function scriptInformation {
  titre "Bienvenue dans $scriptNom ($scriptAlias)" "#" "vert"
  titre "Créé par $scriptCreateur" "/" "cyan"
  information "Version: $scriptVersion"
  echo "OS cible : $systeme"
  echo ""
}

##############################################
# === DÉFINITION DES PAQUETS (Open Source) ===
# Chaque entrée : Nom / Catégorie / Descriptif / Dépôt(Linux) / CmdLinux / CmdWindows
##############################################

# Outils d’archives (bundle)
bibliothequePaquets "Ajouter" \
  "Zip" "Outils" \
  "Ensemble d’outils pour fichiers compressés (zip, 7z, rar, etc.)." \
  "" \
  "sudo apt install -y rar unrar zip unzip p7zip-full p7zip-rar sharutils arj cabextract file-roller" \
  "$WINGET_CMD install --id 7zip.7zip --silent --accept-package-agreements --accept-source-agreements"

# Curl / Htop / Neofetch (utilitaires)
bibliothequePaquets "Ajouter" \
  "Curl" "Outils" \
  "Client HTTP/FTP en ligne de commande, très utile pour scripts et diagnostics." \
  "" \
  "sudo apt install -y curl" \
  "$WINGET_CMD install --id cURL.cURL --silent --accept-package-agreements --accept-source-agreements"

bibliothequePaquets "Ajouter" \
  "Htop" "Outils" \
  "Moniteur de processus interactif en TUI (alternative améliorée à top)." \
  "" \
  "sudo apt install -y htop" \
  "$WINGET_CMD install --id htop.htop --silent --accept-package-agreements --accept-source-agreements"

bibliothequePaquets "Ajouter" \
  "Neofetch" "Outils" \
  "Affiche les infos système de manière esthétique dans le terminal." \
  "" \
  "sudo apt install -y neofetch || sudo apt install -y neofetch || true" \
  ""  # (optionnel sous Windows)

# Navigateurs
bibliothequePaquets "Ajouter" \
  "Brave" "Navigateur" \
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

bibliothequePaquets "Ajouter" \
  "Firefox" "Navigateur" \
  "Navigateur libre de la fondation Mozilla." \
  "" \
  "sudo apt install -y firefox" \
  '$WINGET_CMD install --id Mozilla.Firefox --silent --accept-package-agreements --accept-source-agreements'

# Multimédia
bibliothequePaquets "Ajouter" \
  "VLC" "Multimedia" \
  "Lecteur multimédia libre supportant la quasi-totalité des formats." \
  "" \
  "sudo apt install -y vlc" \
  '$WINGET_CMD install --id VideoLAN.VLC --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "Audacity" "Multimedia" \
  "Éditeur audio libre : enregistrement et traitement du son." \
  "" \
  "sudo apt install -y audacity" \
  '$WINGET_CMD install --id Audacity.Audacity --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "OBS" "Multimedia" \
  "OBS Studio : streaming et enregistrement vidéo open-source." \
  "" \
  "sudo apt install -y obs-studio" \
  '$WINGET_CMD install --id OBSProject.OBSStudio --silent --accept-package-agreements --accept-source-agreements'

# Graphisme / 3D
bibliothequePaquets "Ajouter" \
  "GIMP" "Graphisme" \
  "Retouche d’image avancée, alternative libre à Photoshop." \
  "" \
  "sudo apt install -y gimp" \
  '$WINGET_CMD install --id GIMP.GIMP --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "Inkscape" "Graphisme" \
  "Éditeur vectoriel libre, alternative à Illustrator." \
  "" \
  "sudo apt install -y inkscape" \
  '$WINGET_CMD install --id Inkscape.Inkscape --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "Blender" "3D" \
  "Suite libre de modélisation et animation 3D." \
  "" \
  "sudo apt install -y blender" \
  '$WINGET_CMD install --id BlenderFoundation.Blender --silent --accept-package-agreements --accept-source-agreements'

# Bureautique / Cloud / Communication
bibliothequePaquets "Ajouter" \
  "LibreOffice" "Bureautique" \
  "Suite bureautique libre (Writer, Calc, Impress…)." \
  "" \
  "sudo apt install -y libreoffice" \
  '$WINGET_CMD install --id TheDocumentFoundation.LibreOffice --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "OnlyOffice" "Bureautique" \
  "Suite bureautique collaborative compatible MS Office." \
  "" \
  "sudo snap install onlyoffice-desktopeditors" \
  '$WINGET_CMD install --id ONLYOFFICE.DesktopEditors --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "Thunderbird" "Communication" \
  "Client e-mail open-source avec calendrier et extensions." \
  "" \
  "sudo apt install -y thunderbird" \
  '$WINGET_CMD install --id Mozilla.Thunderbird --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "Signal" "Communication" \
  "Messagerie chiffrée de bout en bout (open-source)." \
  "" \
  "sudo snap install signal-desktop" \
  '$WINGET_CMD install --id OpenWhisperSystems.Signal --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "Element" "Communication" \
  "Client Matrix open-source pour chat/chambres/communautés." \
  "" \
  "sudo snap install element-desktop" \
  '$WINGET_CMD install --id Element.Element --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "Nextcloud" "Cloud" \
  "Synchronisation/partage de fichiers auto-hébergés (client desktop)." \
  "" \
  "sudo snap install nextcloud" \
  '$WINGET_CMD install --id Nextcloud.NextcloudDesktop --silent --accept-package-agreements --accept-source-agreements'

# Dev / Virtualisation
bibliothequePaquets "Ajouter" \
  "Git" "Développement" \
  "Système de gestion de versions distribué." \
  "" \
  "sudo apt install -y git" \
  '$WINGET_CMD install --id Git.Git --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "GitHub" "Développement" \
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

bibliothequePaquets "Ajouter" \
  "VSCode" "Développement" \
  "Éditeur de code populaire, extensible." \
  "" \
  "sudo snap install code --classic" \
  '$WINGET_CMD install --id Microsoft.VisualStudioCode --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "NodeJS" "Développement" \
  "Runtime JavaScript côté serveur." \
  "" \
  "sudo apt install -y nodejs npm" \
  '$WINGET_CMD install --id OpenJS.NodeJS --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "Python" "Développement" \
  "Langage polyvalent pour scripts, data, web…" \
  "" \
  "sudo apt install -y python3 python3-pip" \
  '$WINGET_CMD install --id Python.Python.3 --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "Docker" "Développement" \
  "Moteur de conteneurs (Linux : paquet communautaire docker.io)." \
  "" \
  "sudo apt install -y docker.io" \
  ""  # Docker Desktop Windows n’est pas OSS → pas installé ici

bibliothequePaquets "Ajouter" \
  "VirtualBox" "Virtualisation" \
  "Virtualisation d’OS (machines virtuelles)." \
  "" \
  "sudo apt install -y virtualbox" \
  '$WINGET_CMD install --id Oracle.VirtualBox --silent --accept-package-agreements --accept-source-agreements'

# Réseaux / DNS
bibliothequePaquets "Ajouter" \
  "Unbound" "DNS" \
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
bibliothequePaquets "Ajouter" \
  "Snapd" "Outils" \
  "Gestionnaire de paquets Snap pour installer des applications sandboxées." \
  "" \
  "sudo apt install -y snapd && sudo snap install snap-store" \
  ""  # non applicable Windows

bibliothequePaquets "Ajouter" \
  "Cubic" "Outils" \
  "Création d’images ISO Ubuntu personnalisées." \
  "ppa:cubic-wizard/release" \
  "sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 6494C6D6997C215E && sudo apt update && sudo apt install -y cubic" \
  ""  # non applicable Windows

bibliothequePaquets "Ajouter" \
  "Raspberry Pi Imager" "Outils" \
  "Écriture simple d’OS sur cartes SD pour Raspberry Pi." \
  "" \
  "sudo apt install -y rpi-imager" \
  '$WINGET_CMD install --id RaspberryPiFoundation.RaspberryPiImager --silent --accept-package-agreements --accept-source-agreements'

# Jeux
bibliothequePaquets "Ajouter" \
  "Steam" "Jeux" \
  "Plateforme de jeux avec compatibilité Proton sous Linux." \
  "" \
  "sudo apt install -y steam-installer || sudo apt install -y steam" \
  '$WINGET_CMD install --id Valve.Steam --silent --accept-package-agreements --accept-source-agreements'

bibliothequePaquets "Ajouter" \
  "Lutris" "Jeux" \
  "Gestionnaire de jeux open-source (intègre Proton/Wine, GOG, etc.)." \
  "" \
  "sudo apt install -y lutris" \
  '$WINGET_CMD install --id Lutris.Lutris --silent --accept-package-agreements --accept-source-agreements'

# Associatif (⚠ LibreAssOS s’appuie sur ces paquets)
bibliothequePaquets "Ajouter" \
  "Dolibarr" "Associatif" \
  "ERP/CRM libre pour associations et PME." \
  "" \
  "sudo snap install dolibarr" \
  ""  # pas d’ID winget officiel standard

bibliothequePaquets "Ajouter" \
  "Jitsi" "Communication" \
  "Jitsi (attention : le paquet jitsi-meet est côté serveur). Pour client bureau, préférer 'Jitsi Meet Desktop' (snap) si besoin." \
  "" \
  "sudo apt install -y jitsi-meet || true" \
  ""  # (client desktop différent sur Windows)

##############################################
# Main
##############################################
function main {
  clear
  detecterSysteme
  scriptInformation
  checkInternet
  checkUpdate
  [[ "$systeme" == "Linux" ]] && majSysteme
  menuPrincipal
}

main
