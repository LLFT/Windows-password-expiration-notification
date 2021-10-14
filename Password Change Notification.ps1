##################################################################################################################
# Configurer les Variables Suivantes 
# Autoriser depuis votre serveur SMTP à ce que cette machine puisse l'exploiter sans authentification
$smtpServer="SERVEURSMTP"
$expireindays = 15
$suportMail = "Hotline <hotline@NOMDEDOMAINE>"
$grpCible = "GR-MDP_POLICES_STANDARD" # Groupe des personnes étant sujet à l'authentification forte
###################################################################################################################

$logFileExists = Get-EventLog -list | Where-Object {$_.logdisplayname -eq "ScriptsNotifPWD"}
if (! $logFileExists) {
    New-EventLog -LogName "ScriptsNotifPWD" -Source "PasswordChangeNotification"
}


function PCN {

	#Récupère sur l'AD la liste des utilisateurs actifs dont le mot de passe est en droit d'expirer et qui n'est pas déjà expiré 
	Import-Module ActiveDirectory
	Import-Module ActiveDirectory

	$users = Get-ADGroupMember $grpCible -Recursive | Where { $_.objectClass -eq "user" } `
		| Get-ADUser -properties * | where {$_.enabled -eq $true} `
		| where {$_.lockedout -eq $false}   `
		| where { $_.PasswordNeverExpires -eq $false }  `
		| where { $_.passwordexpired -eq $false }
		
	$boolSendAdminMail=$FALSE
	$listUsers="
	<p> Liste des personnes inform&eacute;es de l'expiration de leur mot de passe.</p>
	<ul>

	";

	foreach ($user in $users)
	{
	  #Récupère les informations de l'utilisateur.
	  $Name = (Get-ADUser $user | foreach { $_.Name})
	  $emailaddress = $user.EmailAddress
	  $passwordSetDate = (get-aduser $user -properties * | foreach { $_.PasswordLastSet })
	  #Récupère la politique de mot de passe active pour l'utilisateur.
	  $PasswordPol = (Get-AduserResultantPasswordPolicy $user)
	  
	  #s'il est bien sujet à une politique on récupère le MaxPasswordAge de cette politique sinon on prends celle appliquée à l'ensemble du domaine.
	  if (($PasswordPol) -ne $null)
	  {
		$maxPasswordAge = ($PasswordPol).MaxPasswordAge
	  }	  
	  else
	  {
		$maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
	  }
	  
	  #On ajoute la date de son dernier changement de MdP à la valeur du MaxPasswordAge
	  $expireson = $passwordsetdate + $maxPasswordAge
	  $today = (get-date)
	  #On calcul le temps restant
	  $daystoexpire = (New-TimeSpan -Start $today -End $Expireson).Days
	  $subject="Important - Votre Mot de Passe expire dans $daystoExpire jours - Service Informatique"
	  $body ="
	  $name,
	  <p> Votre Mot de Passe expire dans $daystoExpire jours.<br>
	  Pour changer le mot de passe depuis un PC pressez <b>CTRL ALT Delete</b> et <b>Modifier un mot de passe <br>
	  Pour changer le mot de passe depuis un client léger pressez <b>CTRL ALT Fin</b> et <b>Modifier un mot de passe </b> <br>
	  
	  Pour rappel, les mots de passe doivent respecter les exigences minimales suivantes :

	  <ul>
		<li>Ne pas contenir le nom de compte de l&rsquo;utilisateur ou des parties du nom complet de l&rsquo;utilisateur comptant plus de deux caract&egrave;res successifs</li>
		<li>Ne pas avoir de correspondance avec vos trois derniers mots de passe (exemple : Janvier*2018, Janvier*2019)</li>
		<li>Comporter au moins <b>10</b> caract&egrave;res</li>
		<li>Contenir des caract&egrave;res provenant des quatre cat&eacute;gories suivantes :</li>
		<ul>
			<li>Au moins un caract&egrave;res majuscules (A &agrave; Z)</li>
			<li>Caract&egrave;res minuscules (a &agrave; z)</li>
			<li>Au moins un chiffres (0 &agrave; 9)</li>
			<li>Caract&egrave;res non alphab&eacute;tiques (par exemple, !, $, #, %, *)</li><br>
		
		<br>	
		
		
	<p>En cas de difficult&eacute;s la Hotline reste &agrave; votre disposition.</p> 
		</ul>
	  </ul>
	  <p>Merci, <br> 
	  </P>"

	  #On compare le temps restant au délais fixé en début de script
	  if ($daystoexpire -lt $expireindays){
	   #Si l'utilisateur à bien un mail on le notifie et l'on ajoute son nom dans la liste des notification destiné au support. Sinon si pas de mail sur l'utilsateur on notifie le support que l'information est absente.
		if ($emailaddress -ne $null){
			Send-Mailmessage -smtpServer $smtpServer -from $suportMail -to $emailaddress -subject $subject -body $body -bodyasHTML -priority High
			Send-Mailmessage -smtpServer $smtpServer -from $suportMail -to $emailaddress -subject $subject -body $body -bodyasHTML -priority High
			$boolSendAdminMail=$TRUE
			$listUsers += "<li>$name ($daystoExpire jour(s))</li>"
		}else{
			$listUsers += "<li>$name ($daystoExpire jour(s)) - Probl&egrave;me sur l'adresse de messagerie</li>"
		}
		write-eventlog -LogName "ScriptsNotifPWD" -Source "PasswordChangeNotification" -entrytype Information -eventID 20190 -message "$name expire dans $daystoExpire jour(s)(Notifié) "
		"$name expire dans $daystoExpire jour(s)(Notifié)"| Out-File "$varCheminDuScript\logs\Log.log" -encoding utf8 -Append
	  }else{
		"$name expire dans $daystoExpire jour(s)(Non Notifié)"| Out-File "$varCheminDuScript\logs\Log.log" -encoding utf8 -Append
	  }   
	}
	$listUsers += "</ul>"
																																							
	# On envoie au support la liste des comptes ayant été notifié par Mail et ceux dont l'adresse est absente de leur informations de compte.
	if ($boolSendAdminMail){
		Send-Mailmessage -smtpServer $smtpServer -from $suportMail -to $suportMail -subject "Notification Password" -body $listUsers -bodyasHTML -priority High 
		Send-Mailmessage -smtpServer $smtpServer -from $suportMail -to $suportMail -subject "Notification Password" -body $listUsers -bodyasHTML -priority High 
	}else{
		write-host "Liste Vide"
		write-eventlog -LogName "ScriptsNotifPWD" -Source "PasswordChangeNotification" -entrytype Information -eventID 20190 -message "Aucune Notification "
	}

}

function Main{
	$varCheminDuScript = 'c:\Scripts\'
	$DefaultForeground = (Get-Host).UI.RawUI.ForegroundColor
	$DefaultBackground = (Get-Host).UI.RawUI.BackgroundColor
	$myIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent() #On récupère l'identité du profil exécutant l'action.
	$wp = New-Object Security.Principal.WindowsPrincipal($myIdentity) #On transforme l'identité en objet.
	
	$resultLog = Test-Path -Path "$varCheminDuScript\logs"
	if ($resultLog -ne $true){		
		New-Item -ItemType directory -Name "logs" -Path "$varCheminDuScript" #Création du dossier de logs si absent.
	}
	
	$dt = get-date -format dd.MM.yyyy-HH.mm ((Get-Date).addDays(-7)) #recupération de la date d'hier pour créer un fichier horodaté
	if (Test-Path -Path "$varCheminDuScript\logs\Log.log"){
		Move-Item "$varCheminDuScript\logs\Log.log" -Destination "$varCheminDuScript\logs\Log_$dt.log" # Archivage du précédent LOG
	}
	
	if (-not $wp.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) { #On vérifie que le compte soit bien administrateur
		(get-host).UI.RawUI.ForegroundColor="red"
		"Ce script nécessite des privilèges Administrateur. Relancer ce script avec les droits nécessaires."
		(get-host).UI.RawUI.ForegroundColor=$DefaultForeground
	} else {		
		(get-host).UI.RawUI.Backgroundcolor="DarkRed" #on change l'aspect de la console
		clear-host #On vide l'écran
		write-host "Attention : Cette instance de PowerShell s'éxécute en tant qu'administrateur." 		
		PCN # On lance la fonction 
		(get-host).UI.RawUI.Backgroundcolor=$DefaultBackground #on change l'aspect de la console à sa valeur originale
	}
}

Main
