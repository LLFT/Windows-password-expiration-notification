# Password Change Notification

Script PowerShell de notification d'expiration de mot de passe Active Directory. Surveille des
groupes et/ou unités d'organisation, envoie un mail aux utilisateurs dont le mot de passe expire
bientôt, et un rapport de synthèse au support.

## Prérequis

- PowerShell avec le module **ActiveDirectory** installé (RSAT).
- Exécution avec des **droits Administrateur** (le script le vérifie et s'arrête sinon).
- Un serveur SMTP autorisant le relais anonyme depuis la machine qui exécute le script.
- Politique d'exécution **AllSigned** : ce fichier doit être signé numériquement
  (`Set-AuthenticodeSignature`) après toute modification, sinon il sera refusé.

## Fichiers du projet

| Fichier | Rôle |
|---|---|
| `Password_Change_Notification.ps1` | Le script. Toute la logique ; aucun paramètre à modifier dedans. |
| `Config.psd1` | Tous les réglages (voir ci-dessous). Doit se trouver **dans le même dossier** que le script. |
| `Logs\` | Créé automatiquement à côté du script. Un fichier de log par exécution, l'ancien étant archivé avec un horodatage avant d'être remplacé. |

## Utilisation

### Exécution normale (production)

```powershell
.\Password_Change_Notification.ps1
```

Recherche les utilisateurs cibles (`TargetGroup` / `TargetOU`), exclut ceux de `ExclusionGroup`,
notifie ceux dont le mot de passe expire dans moins de `ExpireInDays` jours, puis envoie un
rapport de synthèse à `SupportMail`.

### Aperçu d'un mail (sans toucher à l'AD, sans droits Administrateur)

```powershell
.\Password_Change_Notification.ps1 -PreviewMail
.\Password_Change_Notification.ps1 -PreviewMail -PreviewUserName "Marie Curie" -PreviewDaysToExpire 3
```

Construit un mail avec le gabarit réel (`UserMailSubject` / `UserMailBody`) et l'envoie à
`SupportMail`, sujet préfixé `[APERCU]`. Utile pour valider la mise en forme avant tout envoi réel.
N'écrit rien dans les logs (sortie console uniquement) et ne modifie aucune donnée AD.

## Configuration (`Config.psd1`)

`Config.psd1` est un fichier de **données PowerShell** (`Import-PowerShellDataFile`), pas un
script : il n'exécute aucun code. Conséquences importantes à respecter en le modifiant :

- Jamais de `$variable`, `$(...)`, appel de fonction ou logique conditionnelle dedans — seulement
  des valeurs littérales (texte, nombre, `$true`/`$false`, tableaux `@()`, here-strings simple-quote).
- Une clé ne peut jamais être laissée sans valeur, même « juste pour la commenter » (par exemple
  `TargetGroup = #"..."` casse le fichier) : utilisez toujours une valeur littérale explicite,
  y compris vide (`""` ou `@()`).

### Clés obligatoires

| Clé | Type | Description |
|---|---|---|
| `SmtpServer` | texte | Serveur SMTP relais. |
| `ExpireInDays` | nombre | Seuil (en jours) déclenchant la notification. |
| `SenderMail` | texte | Adresse d'expédition (`From`) de tous les mails. |
| `SupportMail` | liste | Adresse(s) recevant le rapport de synthèse. |
| `UserMailSubject` | texte | Sujet du mail utilisateur (voir jetons ci-dessous). |
| `UserMailBody` | texte (here-string) | Corps HTML du mail utilisateur (voir jetons ci-dessous). |

Au moins une des deux clés `TargetGroup` / `TargetOU` doit contenir au moins une entrée.

### Clés optionnelles

| Clé | Type | Défaut si absente | Description |
|---|---|---|---|
| `SupportDisplayName` | texte | `"Support informatique"` | Nom affiché en signature du mail utilisateur (`{SupportDisplayName}`). |
| `SupportReportSection` | liste ordonnée | les 4 sections, dans l'ordre listé plus bas | Sections affichées dans le rapport support, et leur ordre. |
| `TargetGroup` | liste | `@()` | Groupes AD (DN) dont les membres sont surveillés. |
| `TargetOU` | liste | `@()` | OU (DN) dont les utilisateurs sont surveillés (recherche récursive). |
| `ExclusionGroup` | liste | `@()` | Groupes AD (DN) dont les membres sont exclus, quelle que soit leur origine (groupe ou OU). |
| `NotifUser` | `$true`/`$false` | `$false` | `$true` : envoi réel aux utilisateurs. `$false` : simulation, tracée en log (`DRYRUN`), rapport support toujours envoyé. |

`SupportReportSection` accepte : `"Notified"` (réellement notifiés), `"NotNotified"` (l'auraient
été si `NotifUser` avait été `$true`), `"MailError"` (échec d'envoi), `"NoEmail"` (utilisateur sans
adresse mail). Une valeur inconnue est ignorée avec un avertissement, elle ne bloque pas l'exécution.

### Gabarits de mail (`UserMailSubject` / `UserMailBody`)

Jetons remplacés automatiquement dans les deux champs :

- `{UserName}`
- `{DaysToExpire}`
- `{SupportDisplayName}`

Un jeton mal orthographié reste affiché tel quel (pas d'erreur). Écrivez ces deux valeurs entre
guillemets **simples** (`'...'` ou here-string `@'...'@`), jamais doubles, pour qu'elles restent
toujours du texte littéral quoi qu'elles contiennent (y compris des `$`). S'il faut une apostrophe
littérale dans le texte, doublez-la (`''`).

## Journalisation

Chaque exécution écrit dans `Logs\PasswordChangeNotification.log` (l'ancien fichier est archivé
avec un horodatage avant d'être remplacé). Niveaux utilisés : `INFO`, `OK`, `WARN`, `ERROR`,
`DRYRUN`. Le mode `-PreviewMail` n'écrit pas dans ce fichier (sortie console uniquement).

Il n'y a pas de journal d'événements Windows séparé : `Logs\*.log` est l'unique source de vérité
sur ce qui s'est passé lors d'une exécution.

## Checklist avant mise en production

1. `.\Password_Change_Notification.ps1 -PreviewMail` — valide le chargement de `Config.psd1` et le
   rendu du mail, sans toucher à l'AD.
2. Une exécution complète avec `NotifUser = $false` — valide le ciblage réel (`TargetGroup` /
   `TargetOU` / `ExclusionGroup`) et le rapport support, sans risque d'envoi aux utilisateurs.
3. `NotifUser = $true` seulement après validation des deux points précédents.
4. Re-signer le script (`Set-AuthenticodeSignature`) avant déploiement.

## Limites connues

- `Send-Mailmessage` est une cmdlet dépréciée par Microsoft ; elle reste fonctionnelle mais pourrait
  disparaître d'une future version de PowerShell.
- Le rendu HTML des mails (styles inline) n'a été vérifié dans aucun client mail réel au moment de
  la rédaction de ce script — à valider via `-PreviewMail` sur votre messagerie cible.
