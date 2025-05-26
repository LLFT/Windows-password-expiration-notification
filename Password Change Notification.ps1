# Configuration des variables globales
# Ces variables sont à configurer en fonction de votre environnement.
# Assurez-vous que le serveur SMTP autorise cette machine à envoyer des e-mails sans authentification.
$global:SmtpServer = "SERVEURSMTP"
$global:ExpireInDays = 15
$global:SupportMail = "Hotline <hotline@NOMDEDOMAINE>"
# Groupe Active Directory contenant les utilisateurs dont le mot de passe doit être surveillé.
$global:TargetGroup = "GR-MDP_POLICES_STANDARD"
# Chemin du dossier de logs. Assurez-vous que le compte exécutant le script a les droits d'écriture.
$global:ScriptLogPath = 'C:\Scripts\PasswordChangeNotification'

# S'assurer que le module ActiveDirectory est chargé au début du script.
# Il est préférable de le charger une seule fois et explicitement.
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "Erreur lors du chargement du module ActiveDirectory. Assurez-vous qu'il est installé."
    exit 1
}

# Configuration et vérification du journal d'événements personnalisé
function Test-EventLogConfiguration {
    $logName = "ScriptsNotifPWD"
    $sourceName = "PasswordChangeNotification"

    try {
        if (-not (Get-EventLog -List | Where-Object {$_.LogDisplayName -eq $logName})) {
            Write-Verbose "Création du journal d'événements '$logName'."
            New-EventLog -LogName $logName -Source $sourceName -ErrorAction Stop
        } else {
            # Vérifier si la source existe déjà. Si non, l'ajouter.
            # Get-EventLog ne permet pas de lister les sources pour un LogName sans avoir d'entrées.
            # Une approche plus robuste serait de tenter d'écrire et de gérer l'erreur si la source n'existe pas.
            # Pour l'instant, on suppose que New-EventLog crée la source si elle n'existe pas avec le LogName.
            Write-Verbose "Le journal d'événements '$logName' existe déjà."
        }
    }
    catch {
        Write-Error "Impossible de configurer le journal d'événements '$logName'. Erreur: $($_.Exception.Message)"
        exit 1
    }
}

# Fonction principale pour la notification de changement de mot de passe
function Invoke-PasswordChangeNotification {
    [CmdletBinding(DefaultParameterSetName='Default')]
    param(
        [Parameter(Mandatory=$false)]
        [string]$LogFilePath = "$global:ScriptLogPath\logs\PasswordChangeNotification.log"
    )

    Write-Verbose "Début de la notification des mots de passe expirants."

    # Récupérer les utilisateurs dont les mots de passe sont potentiellement expirants
    # Utilisation de Select-Object pour ne récupérer que les propriétés nécessaires.
    # Filtrage initial plus strict pour réduire le nombre d'objets traités.
    $users = Get-ADGroupMember $global:TargetGroup -Recursive |
             Where-Object {$_.objectClass -eq "user"} |
             Get-ADUser -Properties Name, EmailAddress, PasswordLastSet, PasswordNeverExpires, PasswordExpired, Enabled, LockedOut |
             Where-Object {
                 $_.Enabled -eq $true -and
                 $_.LockedOut -eq $false -and
                 $_.PasswordNeverExpires -eq $false -and
                 $_.PasswordExpired -eq $false
             }

    $notificationSummary = [System.Collections.Generic.List[string]]::new()
    $adminNotificationHtmlList = New-Object System.Text.StringBuilder
    [void]$adminNotificationHtmlList.AppendLine("<p>Liste des personnes inform&eacute;es de l'expiration de leur mot de passe :</p><ul>")
    $adminMailSent = $false

    foreach ($user in $users) {
        # Utilisez des variables descriptives pour la clarté.
        $userName = $user.Name
        $userEmail = $user.EmailAddress
        $passwordSetDate = $user.PasswordLastSet

        # Récupérer la politique de mot de passe spécifique à l'utilisateur ou par défaut du domaine.
        try {
            $passwordPolicy = Get-ADUserResultantPasswordPolicy -Identity $user
            if ($passwordPolicy) {
                $maxPasswordAge = $passwordPolicy.MaxPasswordAge
            } else {
                $maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
            }
        }
        catch {
            Write-Warning "Impossible de récupérer la politique de mot de passe pour l'utilisateur $($userName). Utilisation de la politique par défaut du domaine. Erreur: $($_.Exception.Message)"
            $maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
        }

        # Calculer la date d'expiration et les jours restants.
        $expiresOn = $passwordSetDate + $maxPasswordAge
        $today = Get-Date
        $daysToExpire = (New-TimeSpan -Start $today -End $expiresOn).Days

        $subject = "Important - Votre Mot de Passe expire dans $daysToExpire jours - Service Informatique"
        $body = @"
        $userName,
        <p>Votre Mot de Passe expire dans $daysToExpire jours.<br>
        Pour changer le mot de passe depuis un PC, pressez <b>CTRL + ALT + Suppr</b> puis <b>Modifier un mot de passe</b>.<br>
        Pour changer le mot de passe depuis un client léger, pressez <b>CTRL + ALT + Fin</b> puis <b>Modifier un mot de passe</b>.</p>

        <p>Pour rappel, les mots de passe doivent respecter les exigences minimales suivantes :</p>
        <ul>
            <li>Ne pas contenir le nom de compte de l&rsquo;utilisateur ou des parties du nom complet de l&rsquo;utilisateur comptant plus de deux caract&egrave;res successifs.</li>
            <li>Ne pas avoir de correspondance avec vos trois derniers mots de passe (exemple : Janvier*2018, Janvier*2019).</li>
            <li>Comporter au moins <b>10</b> caract&egrave;res.</li>
            <li>Contenir des caract&egrave;res provenant des quatre cat&eacute;gories suivantes :
                <ul>
                    <li>Au moins un caract&egrave;re majuscule (A &agrave; Z)</li>
                    <li>Caract&egrave;res minuscules (a &agrave; z)</li>
                    <li>Au moins un chiffre (0 &agrave; 9)</li>
                    <li>Caract&egrave;res non alphab&eacute;tiques (par exemple, !, $, #, %, *)</li>
                </ul>
            </li>
        </ul>
        <p>En cas de difficult&eacute;s, la Hotline reste &agrave; votre disposition.</p>
        <p>Merci,<br>$($global:SupportMail.Split('<')[0].Trim())</p>
"@

        if ($daysToExpire -lt $global:ExpireInDays) {
            if ($userEmail) {
                try {
                    Send-Mailmessage -SmtpServer $global:SmtpServer -From $global:SupportMail -To $userEmail -Subject $subject -Body $body -BodyAsHTML -Priority High -ErrorAction Stop
                    $adminMailSent = $true
                    $notificationSummary.Add("$userName expire dans $daysToExpire jour(s) (Notifié)")
                    [void]$adminNotificationHtmlList.AppendLine("<li>$userName ($daysToExpire jour(s))</li>")
                    Write-EventLog -LogName "ScriptsNotifPWD" -Source "PasswordChangeNotification" -EntryType Information -EventID 20191 -Message "$userName expire dans $daysToExpire jour(s) (Notifié)"
                    Write-Verbose "$userName notifié : $daysToExpire jour(s) restants."
                }
                catch {
                    $notificationSummary.Add("$userName expire dans $daysToExpire jour(s) - Erreur d'envoi mail: $($_.Exception.Message)")
                    [void]$adminNotificationHtmlList.AppendLine("<li>$userName ($daysToExpire jour(s)) - Erreur d'envoi mail : $($_.Exception.Message)</li>")
                    Write-EventLog -LogName "ScriptsNotifPWD" -Source "PasswordChangeNotification" -EntryType Error -EventID 20192 -Message "Erreur d'envoi mail pour $userName. Erreur: $($_.Exception.Message)"
                    Write-Error "Erreur d'envoi mail pour $userName: $($_.Exception.Message)"
                }
            } else {
                $notificationSummary.Add("$userName expire dans $daysToExpire jour(s) - Adresse e-mail absente")
                [void]$adminNotificationHtmlList.AppendLine("<li>$userName ($daysToExpire jour(s)) - Probl&egrave;me sur l'adresse de messagerie</li>")
                Write-EventLog -LogName "ScriptsNotifPWD" -Source "PasswordChangeNotification" -EntryType Warning -EventID 20193 -Message "$userName expire dans $daysToExpire jour(s). Adresse e-mail absente."
                Write-Warning "Adresse e-mail absente pour $userName."
            }
        } else {
            $notificationSummary.Add("$userName expire dans $daysToExpire jour(s) (Non Notifié)")
            Write-Verbose "$userName n'a pas été notifié : $daysToExpire jour(s) restants."
        }
    }

    [void]$adminNotificationHtmlList.AppendLine("</ul>")

    # Écrire toutes les entrées de log dans un fichier à la fin de la boucle.
    # Ceci évite d'ouvrir/fermer le fichier à chaque itération.
    try {
        $notificationSummary | Out-File $LogFilePath -Encoding utf8 -Append -ErrorAction Stop
    }
    catch {
        Write-Error "Impossible d'écrire dans le fichier de log '$LogFilePath'. Erreur: $($_.Exception.Message)"
    }


    # Envoyer le rapport au support
    if ($adminMailSent) {
        try {
            Send-Mailmessage -SmtpServer $global:SmtpServer -From $global:SupportMail -To $global:SupportMail -Subject "Rapport de notification d'expiration de mot de passe" -Body $adminNotificationHtmlList.ToString() -BodyAsHTML -Priority High -ErrorAction Stop
            Write-EventLog -LogName "ScriptsNotifPWD" -Source "PasswordChangeNotification" -EntryType Information -EventID 20194 -Message "Rapport de notification envoyé au support."
            Write-Verbose "Rapport de notification envoyé au support."
        }
        catch {
            Write-EventLog -LogName "ScriptsNotifPWD" -Source "PasswordChangeNotification" -EntryType Error -EventID 20195 -Message "Erreur lors de l'envoi du rapport au support. Erreur: $($_.Exception.Message)"
            Write-Error "Erreur lors de l'envoi du rapport au support: $($_.Exception.Message)"
        }
    } else {
        Write-Host "Aucun utilisateur notifié. Pas de rapport envoyé au support."
        Write-EventLog -LogName "ScriptsNotifPWD" -Source "PasswordChangeNotification" -EntryType Information -EventID 20196 -Message "Aucun utilisateur notifié. Pas de rapport envoyé au support."
    }
    Write-Verbose "Fin de la notification des mots de passe expirants."
}

# Fonction principale pour l'orchestration du script
function Start-PasswordChangeNotificationScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ScriptPath = (Split-Path $MyInvocation.MyCommand.Path -Parent)
    )

    $defaultForeground = (Get-Host).UI.RawUI.ForegroundColor
    $defaultBackground = (Get-Host).UI.RawUI.BackgroundColor

    # Changer le répertoire de travail si le script est appelé depuis un autre emplacement
    Set-Location $ScriptPath

    # Vérification des privilèges administrateur
    $myIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $wp = New-Object Security.Principal.WindowsPrincipal($myIdentity)

    if (-not $wp.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        (Get-Host).UI.RawUI.ForegroundColor = "Red"
        Write-Error "Ce script nécessite des privilèges Administrateur. Relancez ce script avec les droits nécessaires."
        (Get-Host).UI.RawUI.ForegroundColor = $defaultForeground
        exit 1
    } else {
        # Configuration de l'affichage de la console
        (Get-Host).UI.RawUI.BackgroundColor = "DarkRed"
        Clear-Host
        Write-Host "Attention : Cette instance de PowerShell s'exécute en tant qu'administrateur."

        # Préparation du dossier de logs
        $logDirectory = "$global:ScriptLogPath\logs"
        if (-not (Test-Path -Path $logDirectory)) {
            Write-Verbose "Création du dossier de logs : $logDirectory"
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }

        # Archivage du log précédent
        $currentLogFile = "$logDirectory\PasswordChangeNotification.log"
        if (Test-Path -Path $currentLogFile) {
            $archiveDateTime = Get-Date -Format "yyyyMMdd_HHmmss"
            $archiveLogFile = "$logDirectory\PasswordChangeNotification_$archiveDateTime.log"
            try {
                Move-Item -Path $currentLogFile -Destination $archiveLogFile -Force -ErrorAction Stop
                Write-Verbose "Ancien fichier de log archivé : $archiveLogFile"
            }
            catch {
                Write-Warning "Impossible d'archiver le fichier de log '$currentLogFile'. Erreur: $($_.Exception.Message)"
            }
        }

        # Appeler la fonction de configuration du journal d'événements
        Test-EventLogConfiguration

        # Lancer la fonction principale de notification
        Invoke-PasswordChangeNotification -LogFilePath $currentLogFile

        # Restaurer l'aspect de la console
        (Get-Host).UI.RawUI.BackgroundColor = $defaultBackground
    }
}

# Point d'entrée du script
Start-PasswordChangeNotificationScript -Verbose
