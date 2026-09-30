@{
    #==============================================================
    # Configuration - Password Change Notification
    # Toutes les valeurs entre [ ] sont à adapter à votre environnement.
    #==============================================================

    # Serveur SMTP utilisé pour l'envoi des mails.
    # Assurez-vous que ce serveur autorise le relais anonyme depuis cette machine.
    SmtpServer = "[messagerie.domain.tld]"

    # Nombre de jours avant expiration à partir duquel la notification est envoyée.
    ExpireInDays = 15

    #--------------------------------------------------------------
    # Adresses de messagerie
    #--------------------------------------------------------------
    # Adresse d'expédition unique (From) des mails, aussi bien vers les utilisateurs que vers le support.
    SenderMail = "[expediteur@domain.tld]"

    # Nom affiché utilisé uniquement dans la signature du mail envoyé aux utilisateurs
    # ("Merci, <SupportDisplayName>"). Absent => "Support informatique" par défaut.
    SupportDisplayName = "[Expire-Account]"

    # Liste d'une ou plusieurs adresses e-mail du support. Toutes reçoivent le rapport de synthèse.
    SupportMail = @(
        "[responsable-it@domain.tld]"
        # "astreinte@NOMDEDOMAINE"
    )

    # Sections à inclure dans le rapport envoyé au support, dans l'ordre d'affichage voulu.
    # Valeurs possibles : "Notified" (notifiés réellement), "NotNotified" (l'auraient été,
    # NotifUser=$false), "MailError" (échecs d'envoi), "NoEmail" (adresse manquante).    
    SupportReportSection = @(
        "Notified",
        "NotNotified",
        "MailError",
        "NoEmail"
    )

    #--------------------------------------------------------------
    # Périmètre des utilisateurs surveillés
    #--------------------------------------------------------------
    # Liste de groupes Active Directory (DN) contenant les utilisateurs à surveiller, en
    # complément (ou à la place) des OU listées dans TargetOU ci-dessous.
    # Laissez un tableau vide @() si vous ne souhaitez cibler que des OU.
    TargetGroup = @(
        #"CN=[GROUPENAME],OU=[OUNAME],OU=[OUNAME],DC=[DCNAME],DC=[DCNAME],DC=[DCNAME]"
    )

    # Liste d'unités d'organisation (DN) dont les utilisateurs doivent être surveillés,
    # en complément (ou à la place) du groupe ci-dessus. Recherche récursive (sous-OU incluses).
    # Laissez un tableau vide @() si vous ne souhaitez cibler que TargetGroup.
    TargetOU = @(
        #"OU=[OUNAME],OU=[OUNAME],DC=[DCNAME],DC=[DCNAME],DC=[DCNAME]"
        # "OU=[AUTREOUNAME],DC=[DCNAME],DC=[DCNAME],DC=[DCNAME]"
    )

    # Liste de groupes Active Directory (DN) contenant les utilisateurs à exclure de la surveillance.
    ExclusionGroup = @(
        #"CN=[GROUPENAME],OU=[OUNAME],OU=[OUNAME],DC=[DCNAME],DC=[DCNAME],DC=[DCNAME]"
        #"CN=[GROUPENAME],OU=[OUNAME],OU=[OUNAME],DC=[DCNAME],DC=[DCNAME],DC=[DCNAME]"
    )

    # $true  : envoi réel des mails aux utilisateurs.
    # $false : simulation (dry-run) - rien n'est envoyé aux utilisateurs, mais chaque cas est
    #          tracé dans le log avec le niveau DRYRUN. Le rapport de synthèse, lui, part
    #          toujours vers SupportMail, que NotifUser soit $true ou $false.
    NotifUser = $false

    #--------------------------------------------------------------
    # Contenu du mail envoyé aux utilisateurs
    #--------------------------------------------------------------
    # Personnalisez le sujet et le corps ici, sans toucher au script.
    #
    # Emplacements disponibles (remplacés automatiquement) : {UserName}, {DaysToExpire},
    # {SupportDisplayName}. Un emplacement mal orthographié reste affiché tel quel, sans erreur.
    #
    # IMPORTANT : ce fichier n'exécute pas de code PowerShell (texte littéral uniquement) - donc
    # jamais de $variable, $(...), etc. ici, uniquement les emplacements {NomDeChamp} ci-dessus.
    # Gardez les apostrophes SIMPLES : ' comme ci-dessous (jamais les doubles ") pour que le
    # texte reste toujours littéral. S'il faut une apostrophe dans le texte, doublez-la : ''.
    UserMailSubject = 'Important - Votre Mot de Passe expire dans {DaysToExpire} jours - Service Informatique'

    UserMailBody = @'
{UserName},
<p>Votre Mot de Passe expire dans {DaysToExpire} jours.<br>
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
<p>Merci,<br>{SupportDisplayName}</p>
'@
}
