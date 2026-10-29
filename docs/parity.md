# Différences voulues entre le site et l’app iOS

Le site sert de référence. Les écarts ci-dessous sont voulus : ils viennent de la plateforme, pas d’un oubli. Toute autre différence de texte ou d’élément est un défaut à corriger des deux côtés.

### Serveur du site
Le site passe par son propre serveur, l’app parle directement à Vélo’v. Ces messages n’existent donc que sur le site :
- Les erreurs des routes `/api` (requête invalide) : « Ce déverrouillage n’est pas valide. », « Cette réservation n’est pas valide. », « Cette note n’est pas valide. », « Ce reçu n’est pas valide. », « Ce réglage n’est pas valide. », « Ces coordonnées ne sont pas valides. », « Cet échange n’est pas valide. », « Cette période n’est pas valide. », « Choisissez une station valide. », « Numéro de vélo invalide. », « Numéro de station invalide. », « Ce vélo est introuvable. ».
- Les demandes de connexion venues de ces routes : « Connectez-vous pour réserver ou déverrouiller. », « Connectez-vous pour modifier votre compte. », « Connectez-vous pour retrouver vos statistiques. », etc.
- La protection du serveur : « Trop de tentatives de connexion. Réessayez dans une minute. », « Cette action n’est possible que depuis ce site. », « Le service est momentanément indisponible. Réessayez dans un instant. », « Le service ne répond pas. ».
- Les pannes entre le navigateur et le serveur : « Le serveur ne répond pas. Actualisez la page avant de réessayer. », « Le serveur ne répond pas. Réessayez dans un instant. », « Réponse inattendue. Actualisez la page avant de réessayer. », « Pas de réponse. Votre message a peut-être déjà été envoyé. », « Réponse inattendue. Votre message a peut-être déjà été envoyé. », « Réponse inattendue. Vos points ont peut-être été débités. », « Réponse inattendue. Les 15 minutes ont peut-être été ajoutées. », « Vélo’v ne répond pas. Actualisez la page pour voir si le réglage a changé. ».
- La déconnexion : le site prévient le serveur et peut échouer (« Déconnexion impossible. Réessayez. »). L’app se déconnecte sur place et n’a pas ce message. « Déconnexion effectuée. Vélo’v ne l’a pas encore confirmée. » existe des deux côtés.
- La connexion : le site laisse le serveur vérifier le formulaire (« Saisissez votre adresse e-mail et votre code secret à six chiffres. », « Vérifiez votre adresse e-mail et votre code secret. »). L’app grise « Se connecter » tant que l’adresse est vide ou que le code n’a pas 6 chiffres.

### Téléphone ou navigateur
Même phrase, seul l’objet change :
- Site « Ce navigateur ne peut pas suivre cette action. Rien n’a été envoyé. » / app « Ce téléphone ne peut pas suivre cette action. Rien n’a été envoyé. »
- Site « Ce navigateur ne peut pas garder le code. Copiez-le maintenant. » / app « Ce téléphone ne peut pas garder le code. Copiez-le maintenant. »
- Site « Ce navigateur ne peut pas enregistrer le code. Vos points n’ont pas été utilisés. » / app « Ce téléphone ne peut pas enregistrer le code. Vos points n’ont pas été utilisés. »
- Site « Impossible de lire les codes enregistrés sur ce navigateur. » / app « Impossible de lire les codes enregistrés sur ce téléphone. »
- Site « Enregistré sur ce navigateur. » / app « Enregistré sur ce téléphone. »
- Site « La page a été fermée avant la réponse. L’action a peut-être abouti. » / app « L’app a été fermée avant la réponse. L’action a peut-être abouti. »
- « Actualisez la page » sur le site devient « actualisez » dans l’app : site « Vélo’v ne répond pas. Le vélo est peut-être réservé : actualisez la page avant de réessayer. » / app « Vélo’v ne répond pas. Le vélo est peut-être réservé : actualisez avant de réessayer. ». De même pour « La modification a peut-être été prise en compte » et pour « L’offre a changé. Actualisez la page avant de confirmer. » / « L’offre a changé. Actualisez avant de confirmer. ».
- Seul le site a « Ce navigateur ne peut pas empêcher un double envoi depuis un autre onglet. Rien n’a été envoyé. » : l’app n’a pas d’onglets.

### Localisation
Les réglages à ouvrir ne sont pas les mêmes :
- Refus : site « Localisation refusée. Autorisez-la pour ce site dans votre navigateur, puis dans les réglages de localisation de votre appareil. » / app « Localisation refusée. Autorisez-la dans Réglages > Vélo’v+ > Position. »
- Service coupé : site « Votre appareil ne trouve pas votre position. Vérifiez que le service de localisation est activé pour ce navigateur. » / app « Le service de localisation est désactivé sur ce téléphone. »
- Seul le site a « Localisation indisponible sur cette page. Recherchez une station par son nom. » (page non sécurisée) et « Ce navigateur ne permet pas la localisation. Recherchez une station par son nom. ».
- La ligne technique change de forme : site « Code · message · navigateur/système · Permission … », app « CLError … · auth … · services on/off ».
- Les messages communs sont identiques : « La localisation a pris trop de temps. Réessayez. », « Impossible de vous localiser pour le moment. », « Aucune station ouverte ne correspond à ce filtre. ».

### Cartes
- Le site utilise Leaflet et les tuiles OpenStreetMap en couleur, l’app MapKit (Plans). Sur le site, la carte des Stations est dans une carte arrondie, avec ses boutons + et −. Dans l’app, elle occupe tout l’écran, sous une barre de recherche et un bouton de localisation flottants (Liquid Glass).
- Seul le site affiche « Ctrl + molette pour zoomer » ou « ⌘ + molette pour zoomer » : l’app zoome au pincement.
- « Itinéraire » ouvre Google Maps à pied sur le site, Plans à pied dans l’app.
- Sur ordinateur, la Vue d’ensemble du site présélectionne une station, avec sa carte (« Voir les vélos »), et les Stations ont un panneau latéral. Sur téléphone, le site et l’app ne présélectionnent rien et utilisent la même petite fiche (nom, étoile, X, compteurs, « Voir les vélos », « Itinéraire »).

### Navigation
- Les Statistiques sont un onglet sur le site (« Statistiques » sur ordinateur, « Stats » en bas sur téléphone). Dans l’app, c’est un bouton « Statistiques » en haut de Trajets, et la page s’ouvre avec une flèche « Retour aux trajets ». Le site a donc six onglets, l’app cinq.
- Seul le site a le lien clavier « Aller au contenu », la barre latérale sur ordinateur (icône du compte et bouton de déconnexion) et la réserve de place pour la barre de défilement.
- Seul le site masque le bouton « Se déconnecter » de la page Compte sur ordinateur : la barre latérale l’affiche déjà.

### Présentation des confirmations
- Dans la fiche d’un vélo, le site affiche « Réserver ce vélo ? » ou « Déverrouiller ce vélo ? » dans un encadré gris, dans la fiche elle-même. L’app ouvre une feuille par-dessus : « Vélo 20449 », puis la question en titre, puis la phrase et Annuler / Confirmer. Le texte, les boutons, l’avertissement à plus de 200 m et les états d’erreur sont les mêmes.
- Les fenêtres du site sont des boîtes de dialogue centrées sur ordinateur, ou des feuilles en bas de l’écran sur téléphone. L’app utilise les feuilles iOS : on peut les baisser d’un geste, sauf pendant un envoi.
- L’app ajoute des retours haptiques à la confirmation et au résultat.

### Reçus et presse-papiers
- Le site télécharge le PDF du reçu. L’app ouvre la feuille de partage iOS, et seul l’app peut dire « Le reçu n’a pas pu être enregistré sur ce téléphone. ».
- Seul le site peut échouer à copier : « Copie impossible. Sélectionnez le code pour le copier. ». Dans l’app, la copie ne peut pas échouer.

### Live Activities et widgets
Ces éléments n’existent que dans l’app :
- Réservation en cours sur l’écran verrouillé et dans la Dynamic Island : le pilule « Réservé », le compte à rebours, « Vélo 20449 · Borne 4 », « Borne 4 · Bellecour / Saint-Exupéry » et « Expirée ».
- Trajet en cours : « En trajet » puis « Terminé », le chronomètre et « Vélo 20449 ».
Le bandeau de réservation dans l’app et sur le site reste identique : l’horloge et le compte à rebours, puis « Déverrouiller ».

### Apparence propre à iOS
- La barre d’onglets du bas, les boutons Actualiser et Compte de l’en-tête et la barre de recherche des Stations utilisent le matériau Liquid Glass d’iOS. Le site utilise des surfaces blanches avec un filet.
- L’app utilise la police des chiffres « Velov Glyphic Timer » pour les comptes à rebours des Live Activities.

### Diagnostic
- La ligne technique d’une panne réseau garde le code exact et la durée. App : « Délai dépassé après 30 s · NSURLErrorTimedOut (-1001) », « Connexion perdue après 2 s · NSURLErrorNetworkConnectionLost (-1005) », « Pas de réseau après 0 s · NSURLErrorNotConnectedToInternet (-1009) ». Site : nom de l’erreur du navigateur (TypeError, AbortError) et durée, quand le navigateur les donne.
- Seule l’app a le Journal technique (page Compte) : les 50 dernières requêtes envoyées à Vélo’v (heure, méthode, chemin aux identifiants masqués sauf numéros de station et de vélo, statut HTTP ou code d’erreur, durée, action), sans jeton, en-tête, contenu, nom, e-mail ni téléphone, avec « Partager » et « Effacer ».
