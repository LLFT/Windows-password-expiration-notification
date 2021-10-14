# Windows-password-expiration-notification
Notify users by email of the impending expiration of their passwords and inform support of those who have been notified.
The script is designed to be executed by a scheduled task or by hand.
It has been tested on Windows server 2008 R2, 2012 R2, and 2016 environments.
For some reason, when running as a scheduled task, the "Send-Mailmessage" commands are not executed if they are not duplicated.
It is for this reason that if you launch it by hand you will receive two notification emails.
Small security flaw: As I have not developed the SMTP authentication part, you will need to authorize the machine hosting the script to send emails without being authenticated from your SMTP server.

=======================

Notifier les utilisateurs par email de l'expiration prochaine de leurs mots de passe et informer le support des personnes qui ont été prévenues.
Le script est conçu pour être exécuté par une tache planifiée ou à la main. 
Il a été testé sur des environnements Windows server 2008 R2, 2012 R2, et 2016.
Pour une raison obscure lors de l'exécution en tâche planifié les commandes "Send-Mailmessage" ne s'exécutent pas si elles ne sont pas doublées. 
C'est pour cette raison que si vous le lancé à la main vous recevrez deux mails de notification.
Petite faille de sécurité : Comme je n'ai pas développé la partie authentification SMTP, il vous faudra autoriser la machine hébergeant le script à émettre des mails sans être authentifié depuis votre serveur de SMTP. 
