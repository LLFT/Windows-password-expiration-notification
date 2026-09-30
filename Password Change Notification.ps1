# Ce script exploite un fichier de configuration externe (Config.psd1, dans le même dossier
# par défaut) pour tous ses paramètres. Voir Config.psd1 pour la description de chaque clé.

param(
    # Envoie un exemple de mail utilisateur (gabarit UserMailSubject/UserMailBody de Config.psd1,
    # rempli avec des valeurs d'exemple) à l'adresse SupportMail, pour voir le rendu réel avant
    # déploiement - sans toucher à l'Active Directory, sans droits Administrateur requis, et sans
    # jamais rien envoyer à un vrai utilisateur.
    # Usage : .\Password_Change_Notification.ps1 -PreviewMail
    #     ou : .\Password_Change_Notification.ps1 -PreviewMail -PreviewUserName "Marie Curie" -PreviewDaysToExpire 3
    [switch]$PreviewMail,
    [string]$PreviewUserName = "Jean Dupont",
    [int]$PreviewDaysToExpire = 5
)

# Écrit une ligne horodatée dans un fichier de log et sur la console (couleur selon le niveau).
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "OK", "DRYRUN")]
        [string]$Level = "INFO",
        [Parameter(Mandatory)][string]$LogFile,
        [bool]$IsDryRun = $false
    )
    $ts     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = if ($IsDryRun) { "[DRYRUN]" } else { "" }
    $line   = "[$ts][$Level]$prefix $Message"

    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "OK"    { Write-Host $line -ForegroundColor Green }
        "INFO"  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }
}

# Remplace les jetons {NomDeChamp} d'un gabarit par les valeurs fournies. Utilisé pour le sujet
# et le corps du mail utilisateur, personnalisables depuis Config.psd1 (UserMailSubject /
# UserMailBody) sans toucher au script. Un jeton sans valeur correspondante reste tel quel
# dans le résultat (pas d'erreur), pour rester tolérant à une faute de frappe dans le psd1.
function Format-MailTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)][hashtable]$Values
    )
    $result = $Template
    foreach ($key in $Values.Keys) {
        $result = $result.Replace("{$key}", [string]$Values[$key])
    }
    return $result
}

# S'assurer que le module ActiveDirectory est chargé au début du script (inutile en mode
# -PreviewMail, qui ne touche jamais à l'AD).
# À ce stade, le fichier de log n'est pas encore déterminé : on ne peut donc pas encore
# utiliser Write-Log, d'où l'usage de Write-Error pour cette étape de bootstrap.
if (-not $PreviewMail) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    catch {
        Write-Error "Erreur lors du chargement du module ActiveDirectory. Assurez-vous qu'il est installé."
        exit 1
    }
}

# Charge le fichier de configuration psd1 et vérifie la présence des clés obligatoires.
# Alimente les variables de script utilisées par le reste du script.
# Même remarque que ci-dessus : le fichier de log n'est pas encore déterminé à ce stade.
function Import-ScriptConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Error "Fichier de configuration introuvable : '$ConfigPath'."
        exit 1
    }

    try {
        $config = Import-PowerShellDataFile -Path $ConfigPath -ErrorAction Stop
    }
    catch {
        Write-Error "Impossible de lire le fichier de configuration '$ConfigPath'. Erreur: $($_.Exception.Message)"
        exit 1
    }

    # Clés strictement obligatoires.
    $requiredKeys = @("SmtpServer", "ExpireInDays", "SupportMail", "SenderMail", "UserMailBody","UserMailSubject")
    $missingKeys = $requiredKeys | Where-Object { -not $config.ContainsKey($_) -or [string]::IsNullOrWhiteSpace(($config[$_] | Out-String)) }
    if ($missingKeys) {
        Write-Error "Le fichier de configuration '$ConfigPath' ne définit pas les clés obligatoires suivantes : $($missingKeys -join ', ')."
        exit 1
    }

    # TargetGroup et TargetOU : au moins un des deux doit être renseigné (chacun peut contenir
    # zéro, un ou plusieurs DN).
    $targetGroups = if ($config.ContainsKey("TargetGroup")) { @($config.TargetGroup) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } } else { @() }
    $targetOUs = if ($config.ContainsKey("TargetOU")) { @($config.TargetOU) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } } else { @() }

    if ($targetGroups.Count -eq 0 -and $targetOUs.Count -eq 0) {
        Write-Error "Configuration invalide : renseignez au moins TargetGroup ou TargetOU dans '$ConfigPath'."
        exit 1
    }

    # Sections du rapport support : valeurs autorisées, dans l'ordre où elles seront affichées.
    # Absent du psd1 => les quatre sections, dans cet ordre par défaut.
    $validReportSections = @("Notified", "NotNotified", "MailError", "NoEmail")
    $requestedSections = if ($config.ContainsKey("SupportReportSection")) {
        @($config.SupportReportSection) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    } else {
        $validReportSections
    }
    $unknownSections = $requestedSections | Where-Object { $validReportSections -notcontains $_ }
    if ($unknownSections) {
        Write-Warning "SupportReportSection contient des valeurs inconnues, ignorées : $($unknownSections -join ', '). Valeurs valides : $($validReportSections -join ', ')."
    }
    $script:SupportReportSection = $requestedSections | Where-Object { $validReportSections -contains $_ }
    if ($script:SupportReportSection.Count -eq 0) {
        Write-Warning "SupportReportSection ne contient aucune valeur valide : le rapport support sera vide de contenu détaillé."
    }

    $script:SmtpServer = $config.SmtpServer
    $script:ExpireInDays = $config.ExpireInDays
    $script:NotifUser = [bool]$config.NotifUser
    $script:SupportMail = @($config.SupportMail) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $script:SenderMail = $config.SenderMail
    $script:SupportDisplayName = if ($config.ContainsKey("SupportDisplayName") -and -not [string]::IsNullOrWhiteSpace($config.SupportDisplayName)) { $config.SupportDisplayName } else { "Support informatique" }
    $script:TargetGroup = $targetGroups
    $script:TargetOU = $targetOUs
    $script:ExclusionGroup = if ($config.ContainsKey("ExclusionGroup")) { @($config.ExclusionGroup) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } } else { @() }
    $script:UserMailSubjectTemplate = $config.UserMailSubject
    $script:UserMailBodyTemplate = $config.UserMailBody

    Write-Verbose "Configuration chargée depuis '$ConfigPath'."
}

# Mode -PreviewMail : construit un mail utilisateur avec des valeurs d'exemple (ou fournies en
# paramètre) et l'envoie à SupportMail, pour voir le rendu réel avant déploiement. Ne touche
# jamais à l'Active Directory ni à un vrai utilisateur ; pas de droits Administrateur requis ;
# pas d'écriture dans le fichier de log (sortie console uniquement, outil manuel de test).
function Send-UserMailPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][int]$DaysToExpire
    )

    $callerScriptPath = if ($MyInvocation.PSCommandPath) { Split-Path $MyInvocation.PSCommandPath -Parent } else { (Get-Location).Path }
    $ConfigPath = Join-Path $callerScriptPath "Config.psd1"

    Import-ScriptConfiguration -ConfigPath $ConfigPath

    $encodingMail = New-Object System.Text.UTF8Encoding

    $templateValues = @{
        UserName           = $UserName
        DaysToExpire       = $DaysToExpire
        SupportDisplayName = $script:SupportDisplayName
    }
    $subject = "[APERCU] " + (Format-MailTemplate -Template $script:UserMailSubjectTemplate -Values $templateValues)
    $body    = Format-MailTemplate -Template $script:UserMailBodyTemplate -Values $templateValues

    Write-Host "Envoi de l'aperçu à : $($script:SupportMail -join ', ')"
    try {
        Send-Mailmessage -SmtpServer $script:SmtpServer -From $script:SenderMail -To $script:SupportMail -Subject $subject -Body $body -BodyAsHTML -Priority High -Encoding $encodingMail -ErrorAction Stop
        Write-Host "Aperçu envoyé avec succès." -ForegroundColor Green
    }
    catch {
        Write-Error "Échec de l'envoi de l'aperçu : $($_.Exception.Message)"
        exit 1
    }
}

# Récupère, dédoublonne et filtre les utilisateurs cibles à partir des groupes listés dans
# TargetGroup et/ou des OU listées dans TargetOU, en excluant les membres des groupes d'exclusion.
function Get-TargetUsers {
    [CmdletBinding()]
    param(
        [string[]]$ExcludedDNs,
        [Parameter(Mandatory = $true)][string]$LogFile
    )

    # DistinguishedName -> objet utilisateur, pour dédoublonner les utilisateurs présents
    # à la fois dans le groupe et dans une OU (ou dans plusieurs OU).
    $userMap = @{}
    $adProperties = @("Name", "EmailAddress", "PasswordLastSet", "PasswordNeverExpires", "PasswordExpired", "Enabled", "LockedOut")

    foreach ($group in $script:TargetGroup) {
        try {
            Write-Log -Message "Récupération des membres du groupe cible : '$group'." -Level INFO -LogFile $LogFile
            $groupUsers = Get-ADGroupMember -Identity $group -Recursive -ErrorAction Stop |
                          Where-Object { $_.objectClass -eq "user" } |
                          Get-ADUser -Properties $adProperties
            foreach ($u in $groupUsers) {
                $userMap[$u.DistinguishedName] = $u
            }
            Write-Log -Message "$($groupUsers.Count) membres du groupe cible : '$group'." -Level INFO -LogFile $LogFile
        }
        catch {
            Write-Log -Message "Impossible de récupérer les membres du groupe cible '$group'. Erreur: $($_.Exception.Message)" -Level WARN -LogFile $LogFile
        }
    }

    foreach ($ou in $script:TargetOU) {
        try {
            Write-Log -Message "Récupération des utilisateurs de l'OU : '$ou'." -Level INFO -LogFile $LogFile
            $ouUsers = Get-ADUser -SearchBase $ou -SearchScope Subtree -Filter * -Properties $adProperties -ErrorAction Stop
            foreach ($u in $ouUsers) {
                $userMap[$u.DistinguishedName] = $u
            }
            Write-Log -Message "$($ouUsers.Count) utilisateurs récupérés dans l'OU : '$ou'." -Level INFO -LogFile $LogFile
        }
        catch {
            Write-Log -Message "Impossible de récupérer les utilisateurs de l'OU '$ou'. Vérifiez que le DN est correct. Erreur: $($_.Exception.Message)" -Level WARN -LogFile $LogFile
        }
    }

    $userMap.Values | Where-Object {
        $_.Enabled -eq $true -and
        $_.LockedOut -eq $false -and
        $_.PasswordNeverExpires -eq $false -and
        $_.PasswordExpired -eq $false -and
        -not ($ExcludedDNs -contains $_.DistinguishedName)
    }
}

#--------------------------------------------------------------------------------------------
# Rapport support : collecte dans des dictionnaires (objets structurés, pas de HTML), rendu
# HTML séparé et déclenché une seule fois à la fin. SupportReportSection (Config.psd1) choisit
# quelles sections apparaissent, et dans quel ordre.
#--------------------------------------------------------------------------------------------

# Métadonnées d'affichage par section (titre, couleur, colonnes). Modifier ici suffit à changer
# la présentation sans toucher à la logique de collecte.
$script:ReportSectionMeta = @{
    Notified    = @{ Title = "Utilisateurs notifiés";                                              Color = "#2e7d32"; Columns = @("Name", "DaysToExpire") }
    NotNotified = @{ Title = "Utilisateurs qui auraient été notifiés (simulation, NotifUser=false)"; Color = "#1565c0"; Columns = @("Name", "DaysToExpire") }
    MailError   = @{ Title = "Échecs d'envoi";                                                      Color = "#c62828"; Columns = @("Name", "DaysToExpire", "ErrorMessage") }
    NoEmail     = @{ Title = "Adresse e-mail manquante";                                             Color = "#ef6c00"; Columns = @("Name", "DaysToExpire") }
}
$script:ReportColumnLabels = @{
    Name         = "Utilisateur"
    DaysToExpire = "Jours restants"
    ErrorMessage = "Erreur"
}

# Génère le tableau HTML d'une seule section. Retourne une chaîne vide si la section n'a rien à afficher.
function Get-SupportReportSectionHtml {
    param(
        [Parameter(Mandatory = $true)][string]$SectionKey,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Items
    )

    if ($Items.Count -eq 0) { return "" }

    $meta = $script:ReportSectionMeta[$SectionKey]
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<h3 style='color:$($meta.Color);font-family:Segoe UI,Arial,sans-serif;margin-bottom:4px;'>$($meta.Title) ($($Items.Count))</h3>")
    [void]$sb.AppendLine("<table style='border-collapse:collapse;width:100%;font-family:Segoe UI,Arial,sans-serif;font-size:13px;margin-bottom:18px;'>")

    [void]$sb.Append("<tr style='background:#f5f5f5;'>")
    foreach ($col in $meta.Columns) {
        [void]$sb.Append("<th style='text-align:left;padding:4px 8px;border:1px solid #ddd;'>$($script:ReportColumnLabels[$col])</th>")
    }
    [void]$sb.AppendLine("</tr>")

    foreach ($item in $Items) {
        [void]$sb.Append("<tr>")
        foreach ($col in $meta.Columns) {
            [void]$sb.Append("<td style='padding:4px 8px;border:1px solid #ddd;'>$($item.$col)</td>")
        }
        [void]$sb.AppendLine("</tr>")
    }

    [void]$sb.AppendLine("</table>")
    return $sb.ToString()
}

# Assemble le mail complet à partir des dictionnaires collectés et de l'ordre choisi dans Config.psd1.
function Build-SupportReportBody {
    param(
        [Parameter(Mandatory = $true)][hashtable]$ReportItems,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Sections
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<html><body style='font-family:Segoe UI,Arial,sans-serif;'>")
    [void]$sb.AppendLine("<p>Rapport de notification d'expiration de mot de passe - $(Get-Date -Format 'dd/MM/yyyy HH:mm').</p>")

    foreach ($section in $Sections) {
        [void]$sb.Append((Get-SupportReportSectionHtml -SectionKey $section -Items $ReportItems[$section]))
    }

    [void]$sb.AppendLine("</body></html>")
    return $sb.ToString()
}

# Fonction principale pour la notification de changement de mot de passe
function Invoke-PasswordChangeNotification {
    [CmdletBinding(DefaultParameterSetName='Default')]
    param(
        [Parameter(Mandatory=$false)]
        [string]$LogFilePath = "$PSScriptRoot\Logs\PasswordChangeNotification.log"
    )
    $encodingMail = New-Object System.Text.UTF8Encoding

    Write-Log -Message "Préparation des listes d'exclusion de groupes..." -Level INFO -LogFile $LogFilePath
    $excludedUsersDNs = @()

    foreach ($groupName in $script:ExclusionGroup) {
        try {
            $members = Get-ADGroupMember -Identity $groupName -Recursive -ErrorAction Stop |
                       Where-Object {$_.objectClass -eq "user"} |
                       Select-Object -ExpandProperty DistinguishedName

            foreach ($dn in $members) {
                $excludedUsersDNs += $dn
            }
            Write-Log -Message "Ajouté $($members.Count) membres du groupe '$groupName' aux exclusions. Total exclusions: $($excludedUsersDNs.Count)." -Level INFO -LogFile $LogFilePath
        }
        catch {
            Write-Log -Message "Impossible de récupérer les membres du groupe d'exclusion '$groupName'. Le filtrage pourrait être incomplet. Erreur: $($_.Exception.Message)" -Level WARN -LogFile $LogFilePath
        }
    }

    Write-Log -Message "Début de la notification des mots de passe expirants." -Level INFO -LogFile $LogFilePath

    $users = Get-TargetUsers -ExcludedDNs $excludedUsersDNs -LogFile $LogFilePath

    # Collecte structurée : un objet par cas, classé dans la bonne catégorie. Le rendu HTML
    # est fait une seule fois à la fin par Build-SupportReportBody, pas au fil de la boucle.
    $reportItems = @{
        Notified    = [System.Collections.Generic.List[object]]::new()
        NotNotified = [System.Collections.Generic.List[object]]::new()
        MailError   = [System.Collections.Generic.List[object]]::new()
        NoEmail     = [System.Collections.Generic.List[object]]::new()
    }
    $hasReportableItems = $false

    foreach ($user in $users) {
        $userName = $user.Name
        $userEmail = $user.EmailAddress
        $passwordSetDate = $user.PasswordLastSet

        try {
            $passwordPolicy = Get-ADUserResultantPasswordPolicy -Identity $user
            if ($passwordPolicy) {
                $maxPasswordAge = $passwordPolicy.MaxPasswordAge
            } else {
                $maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
            }
        }
        catch {
            Write-Log -Message "Impossible de récupérer la politique de mot de passe pour l'utilisateur $($userName). Utilisation de la politique par défaut du domaine. Erreur: $($_.Exception.Message)" -Level WARN -LogFile $LogFilePath
            $maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
        }

        $expiresOn = $passwordSetDate + $maxPasswordAge
        $today = Get-Date
        $daysToExpire = (New-TimeSpan -Start $today -End $expiresOn).Days

        $templateValues = @{
            UserName           = $userName
            DaysToExpire       = $daysToExpire
            SupportDisplayName = $script:SupportDisplayName
        }
        $subject = Format-MailTemplate -Template $script:UserMailSubjectTemplate -Values $templateValues
        $body    = Format-MailTemplate -Template $script:UserMailBodyTemplate -Values $templateValues

        if ($daysToExpire -lt $script:ExpireInDays) {
            if ($userEmail) {
                try {
                    if ($script:NotifUser) {
                        # NotifUser = $true : seul cas où un mail est réellement envoyé à l'utilisateur.
                        Send-Mailmessage -SmtpServer $script:SmtpServer -From $script:SenderMail -To $userEmail -Subject $subject -Body $body -BodyAsHTML -Priority High -ErrorAction Stop -Encoding $encodingMail
                        Write-Log -Message "$userName expire dans $daysToExpire jour(s) (Notifié)" -Level OK -LogFile $LogFilePath
                        $reportItems.Notified.Add([PSCustomObject]@{ Name = $userName; DaysToExpire = $daysToExpire })
                    } else {
                        # NotifUser = $false : simulation, aucun mail envoyé, tracé explicitement en DRYRUN.
                        Write-Log -Message "$userName expire dans $daysToExpire jour(s) (aurait été notifié - NotifUser désactivé)" -Level DRYRUN -LogFile $LogFilePath -IsDryRun $true
                        $reportItems.NotNotified.Add([PSCustomObject]@{ Name = $userName; DaysToExpire = $daysToExpire })
                    }
                    $hasReportableItems = $true
                }
                catch {
                    Write-Log -Message "$userName expire dans $daysToExpire jour(s) - Erreur d'envoi mail: $($_.Exception.Message)" -Level ERROR -LogFile $LogFilePath
                    $reportItems.MailError.Add([PSCustomObject]@{ Name = $userName; DaysToExpire = $daysToExpire; ErrorMessage = $_.Exception.Message })
                    $hasReportableItems = $true
                }
            } else {
                Write-Log -Message "$userName expire dans $daysToExpire jour(s) - Adresse e-mail absente" -Level WARN -LogFile $LogFilePath
                $reportItems.NoEmail.Add([PSCustomObject]@{ Name = $userName; DaysToExpire = $daysToExpire })
                $hasReportableItems = $true
            }
        }
    }

    # Envoyer le rapport au support (à toutes les adresses listées dans SupportMail), avec
    # uniquement les sections choisies dans SupportReportSection (Config.psd1), dans cet ordre.
    if ($hasReportableItems) {
        $reportBody = Build-SupportReportBody -ReportItems $reportItems -Sections $script:SupportReportSection
        try {
            Send-Mailmessage -SmtpServer $script:SmtpServer -From $script:SenderMail -To $script:SupportMail -Subject "Rapport de notification d'expiration de mot de passe." -Body $reportBody -BodyAsHTML -Priority High -ErrorAction Stop -Encoding $encodingMail
            Write-Log -Message "Rapport de notification envoyé au support ($($script:SupportMail -join ', '))." -Level OK -LogFile $LogFilePath
        }
        catch {
            Write-Log -Message "Erreur lors de l'envoi du rapport au support: $($_.Exception.Message)" -Level ERROR -LogFile $LogFilePath
        }
    } else {
        Write-Log -Message "Aucun utilisateur à signaler. Pas de rapport envoyé au support." -Level INFO -LogFile $LogFilePath
    }
    Write-Log -Message "Fin de la notification des mots de passe expirants." -Level INFO -LogFile $LogFilePath
}

# Fonction principale pour l'orchestration du script
function Start-PasswordChangeNotificationScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ScriptPath = $(
            if ($MyInvocation.MyCommand.Path) {
                Split-Path $MyInvocation.MyCommand.Path -Parent
            } else {
                (Get-Location).Path
            }
        ),

        # Chemin du fichier de configuration psd1. Par défaut : Config.psd1 dans le dossier du script.
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath
    )

    Set-Location $ScriptPath

    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $ScriptPath "Config.psd1"
    }

    # Vérification des privilèges administrateur
    $myIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $wp = New-Object Security.Principal.WindowsPrincipal($myIdentity)

    if (-not $wp.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Error "Ce script nécessite des privilèges Administrateur. Relancez ce script avec les droits nécessaires."
        exit 1
    } else {
        Clear-Host
        Write-Host "Attention : Cette instance de PowerShell s'exécute en tant qu'administrateur."

        # Chargement de la configuration (doit se faire avant toute utilisation de $script:SupportMail, etc.)
        Import-ScriptConfiguration -ConfigPath $ConfigPath

        $OutPath = $PSScriptRoot
        $logDirectory = Join-Path -Path $OutPath -ChildPath "Logs"

        Write-Host "Chemin du dossier de logs calculé : '$logDirectory'"
        if (-not (Test-Path -Path $logDirectory)) {
            try {
                New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null
                Write-Host "Dossier de logs créé : '$logDirectory'"
            }
            catch {
                Write-Error "Impossible de créer le dossier de logs '$logDirectory'. Erreur: $($_.Exception.Message)"
                exit 1
            }
        } else {
            Write-Host "Le dossier de logs existe déjà : '$logDirectory'"
        }

        $currentLogFile = "$logDirectory\PasswordChangeNotification.log"
        if (Test-Path -Path $currentLogFile) {
            $archiveDateTime = Get-Date -Format "yyyyMMdd_HHmmss"
            $archiveLogFile = "$logDirectory\PasswordChangeNotification_$archiveDateTime.log"
            try {
                Move-Item -Path $currentLogFile -Destination $archiveLogFile -Force -ErrorAction Stop
            }
            catch {
                # Note : le fichier de log courant vient d'être (re)nommé/déplacé, donc Write-Log
                # (qui écrirait dans $currentLogFile) recréera simplement un fichier vide ici.
                Write-Warning "Impossible d'archiver le fichier de log '$currentLogFile'. Erreur: $($_.Exception.Message)"
            }
        }

        Invoke-PasswordChangeNotification -LogFilePath $currentLogFile
    }
}

# Point d'entrée du script
# -PreviewMail : envoie un exemple de mail utilisateur à SupportMail puis s'arrête (voir
# Send-UserMailPreview ci-dessus). Sans ce paramètre : exécution normale, qui utilise Config.psd1
# (même dossier que ce script) sauf si -ConfigPath est précisé explicitement.
if ($PreviewMail) {
    Send-UserMailPreview -UserName $PreviewUserName -DaysToExpire $PreviewDaysToExpire
} else {
    Start-PasswordChangeNotificationScript -Verbose
}
