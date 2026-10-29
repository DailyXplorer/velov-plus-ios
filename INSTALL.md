# Installer Vélo’v+ sur l’iPhone

L’app est signée avec un compte Apple gratuit (équipe personnelle). Une app installée de cette façon cesse de s’ouvrir au bout de 7 jours : il suffit alors de la réinstaller. Vos données restent sur l’iPhone d’une installation à l’autre (session, codes d’invitation).

## Une seule fois, sur l’iPhone

1. Branchez l’iPhone au Mac avec un câble, déverrouillez-le et touchez **Se fier** si l’iPhone le demande.
2. Activez le **Mode développeur** : Réglages > Confidentialité et sécurité > Mode développeur. Activez-le, laissez l’iPhone redémarrer, puis touchez **Activer** au réveil et saisissez votre code.
   Si l’option n’apparaît pas, faites d’abord une première installation (étape suivante, côté Mac) : elle apparaît ensuite.
3. Après la première installation, faites confiance au certificat : Réglages > Général > VPN et gestion de l’appareil, touchez le profil « Apple Development » de votre compte, puis **Faire confiance**.
4. Ouvrez Vélo’v+ et connectez-vous avec votre email et votre code secret Vélo’v.
5. Pour voir la réservation sur l’écran verrouillé et dans la Dynamic Island : Réglages > Vélo’v+ > **Activités en direct** doit être activé (il l’est par défaut).

## Une seule fois, sur le Mac

Le Mac doit connaître le compte Apple gratuit : Xcode > Réglages > Comptes doit lister l’équipe personnelle. Ces étapes se font dans la session graphique du Mac (pas à distance), car la signature a besoin du trousseau déverrouillé.

## Tous les 7 jours

Le responsable réinstalle l’app depuis la session graphique du Mac, iPhone branché et déverrouillé :

- double-clic sur `scripts/install.command` dans le Finder ;
- ou, dans le Terminal, depuis le dossier du projet : `make build && make install`.

Le script écrit tout dans `~/.velov-ios-install.log` et termine par la ligne `DONE`. La ligne `exit status 0` juste avant indique que l’installation a réussi.

## En cas de problème

- « Untrusted Developer » ou l’app ne s’ouvre pas : refaites l’étape 3.
- « No Accounts » ou « No profiles » pendant `make build` : ouvrez `VelovCompagnon.xcodeproj` dans Xcode, choisissez l’équipe personnelle dans Signing & Capabilities pour les cibles VelovCompagnon et VelovWidgets, puis relancez le script.
- L’app a expiré (elle se ferme à l’ouverture) : réinstallez-la, rien d’autre à faire.
