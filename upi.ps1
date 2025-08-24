# ==========================================
# Universal Package Installer - PowerShell
# ==========================================
$ScriptVersion = "1.0.0"
$JsonUrl = "https://raw.githubusercontent.com/WilliamWolfy/UniversalPackageInstaller/main/bibliotheque.json"
$InstalledPackages = @()

function Titre($texte, $motif="-", $couleur="defaut") {
    $long = $texte.Length + 4
    $sep = $motif * $long
    switch ($couleur) {
        "rouge" { $color = "Red" }
        "vert" { $color = "Green" }
        "jaune" { $color = "Yellow" }
        "bleu" { $color = "Blue" }
        "cyan" { $color = "Cyan" }
        default { $color = "White" }
    }
    Write-Host $sep -ForegroundColor $color
    Write-Host "$motif $texte $motif" -ForegroundColor $color
    Write-Host $sep -ForegroundColor $color
    Write-Host ""
}

function Check-Internet {
    try { Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -TimeoutSec 10; Write-Host "✅ Internet OK" }
    catch { Write-Host "❌ Pas de connexion Internet"; exit 1 }
}

function Check-Version {
    $remoteVersion = (Invoke-WebRequest $JsonUrl.Replace("bibliotheque.json","version.txt") -UseBasicParsing).Content.Trim()
    if ($remoteVersion -ne $ScriptVersion) { Write-Host "⚠️ Nouvelle version : $remoteVersion" }
    else { Write-Host "✅ Version à jour" }
}

function Ensure-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "⚠️ Git absent, installation via Winget..."
        try { winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements; Write-Host "✅ Git installé" }
        catch { Write-Host "❌ Impossible d'installer Git"; exit 1 }
    } else { Write-Host "✅ Git détecté" }
}

function Load-Json {
    $tmpJson = "$env:TEMP\upi.json"
    Invoke-WebRequest -Uri $JsonUrl -OutFile $tmpJson
    $Global:JsonData = Get-Content $tmpJson | ConvertFrom-Json
}

function Install-Package($pkg) {
    $item = $Global:JsonData.logiciels | Where-Object {$_.nom -eq $pkg}
    $cmd = $item.cmdWindows
    Titre "Installation : $pkg" "-" "jaune"
    Write-Host $item.descriptif
    if ($cmd) { Invoke-Expression $cmd }
}

function Install-Profile($prof) {
    $packages = $Global:JsonData.profils.$prof | Sort-Object
    foreach ($p in $packages) { Install-Package $p }
}

function Menu {
    while ($true) {
        Write-Host "Options : 1) Installer logiciel 2) Installer profil 3) Quitter"
        $choice = Read-Host "Sélectionnez une option"
        switch ($choice) {
            "1" { $Global:JsonData.logiciels | Sort-Object nom | ForEach-Object {Write-Host $_.nom}; $pkg=Read-Host "Nom du logiciel"; Install-Package $pkg }
            "2" { $Global:JsonData.profils.PSObject.Properties.Name | Sort-Object | ForEach-Object {Write-Host $_}; $prof=Read-Host "Nom du profil"; Install-Profile $prof }
            "3" { Write-Host "Au revoir !"; exit 0 }
            default { Write-Host "Option invalide" }
        }
    }
}

# ==========================================
# Exécution
# ==========================================
Titre "Universal Package Installer" "=" "cyan"
Check-Internet
Check-Version
Ensure-Git
Load-Json
Menu
