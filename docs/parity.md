# Différences voulues entre le site et l’app iOS

Le site sert de référence. Les écarts ci-dessous sont voulus : ils viennent de la plateforme, pas d’un oubli. Toute autre différence de texte ou d’élément est un défaut à corriger des deux côtés.

Chaque report vers l’app est un audit complet, écran par écran, pas seulement une lecture du diff : lister chaque écran et composant du site avec son équivalent dans l’app, et comparer les textes (mot pour mot, typographie française), la mise en page, les polices et la casse, les couleurs (rouge et gris brume, ni noir, ni rose, ni ombre), les confirmations (une seule, pas d’écran de succès), les états de chargement et les règles de sécurité des actions. L’audit rend la liste des différences corrigées. Après un gros lot, comparer aussi, chaîne par chaîne, tous les textes visibles du site et de l’app : chaque différence est corrigée ou ajoutée à ce fichier.

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
- « Actualisez la page » sur le site devient « actualisez » dans l’app : site « L’offre a changé. Actualisez la page avant de confirmer. » / app « L’offre a changé. Actualisez avant de confirmer. ». Les messages d’un résultat incertain ne donnent que la cause et sont identiques des deux côtés (« Vélo’v ne répond pas. Le vélo est peut-être réservé. ») : la consigne n’apparaît qu’une fois, dans « Le résultat est incertain : vérifiez avant de réessayer. ».
- Seul le site a « Ce navigateur ne peut pas empêcher un double envoi depuis un autre onglet. Rien n’a été envoyé. » : l’app n’a pas d’onglets.

### Localisation
Les réglages à ouvrir ne sont pas les mêmes :
- Refus : site « Autorisez la localisation dans votre navigateur pour trouver les stations autour de vous. » / app « Autorisez la localisation dans Réglages pour trouver les stations autour de vous. », avec un lien « Ouvrir Réglages » dans le bandeau (aussi quand le service de localisation est coupé)
- Seule l’app sait que le service de localisation est coupé : « Le service de localisation est désactivé sur ce téléphone. »
- Seul le site a « Localisation indisponible sur cette page. Recherchez une station par son nom. » (page non sécurisée) et « Ce navigateur ne permet pas la localisation. Recherchez une station par son nom. ».
- Les messages communs sont identiques : « La localisation a pris trop de temps. Réessayez. », « Position introuvable pour le moment. », « Aucune station ouverte ne correspond à ce filtre. ».
- Ces messages s’affichent dans le bandeau d’erreur : en haut à droite sur ordinateur, en haut au centre sur téléphone et dans l’app.

### Cartes
- Le site utilise Leaflet et les tuiles OpenStreetMap en couleur, l’app MapKit (Plans). Sur le site, la carte des Stations est dans une carte arrondie, avec ses boutons + et −. Dans l’app, elle occupe tout l’écran, sous une barre de recherche et un bouton de localisation flottants (Liquid Glass).
- Seul le site affiche « Ctrl + molette pour zoomer » ou « ⌘ + molette pour zoomer » : l’app zoome au pincement.
- « Itinéraire » ouvre Google Maps à pied sur le site, Plans à pied dans l’app.
- Sur ordinateur, la Vue d’ensemble du site présélectionne une station, avec sa carte (« Voir les vélos »), et les Stations ont un panneau latéral. Sur téléphone, le site et l’app ne présélectionnent rien et utilisent la même petite fiche (nom, étoile, X, compteurs, « Voir les vélos », « Itinéraire »).

### Navigation
- Les Statistiques sont un onglet sur le site (« Statistiques » sur ordinateur, « Stats » en bas sur téléphone). Dans l’app, c’est un bouton « Statistiques » en haut de Trajets, et la page s’ouvre par-dessus Trajets avec le bouton retour d’iOS. Le site a donc six onglets, l’app cinq.
- Le détail d’un trajet et la fiche d’un vélo sont des fenêtres sur le site. Dans l’app, ce sont des pages qui s’ouvrent dans l’onglet, avec le bouton retour d’iOS et le glissement depuis le bord gauche. Depuis la carte d’une station, la liste des vélos reste un panneau plein écran, et la fiche d’un vélo s’y ouvre comme une page. Les deux gardent la même barre iOS en haut (Actualiser et X sur la liste, retour et X sur la fiche), avec le nom de la station ou le numéro du vélo en grand dessous.
- Sur le site, « Modifier mes coordonnées » et « Écrire au service client » ouvrent leur formulaire dans la carte, et le Journal technique n’existe pas. Dans l’app, ces trois éléments ouvrent leur propre page. Quitter un formulaire modifié demande « Ignorer les modifications ? », que l’on touche le bouton retour d’iOS, Annuler, l’onglet Compte ou un autre onglet, ou que l’on glisse depuis le bord gauche. La question s’affiche en alerte iOS centrée, avec « Ignorer » et « Continuer la saisie ».
- Pendant un envoi, l’app bloque aussi le bouton retour, le glissement retour et le geste qui baisse une feuille.
- Toucher l’onglet déjà ouvert revient à la racine de l’onglet puis remonte en haut de la page.
- Les Statistiques et la liste des vélos d’une station s’actualisent en tirant la page vers le bas.
- Seul le site a le lien clavier « Aller au contenu », la barre latérale sur ordinateur (icône du compte et bouton de déconnexion) et la réserve de place pour la barre de défilement.
- Seul le site masque le bouton « Se déconnecter » de la page Compte sur ordinateur : la barre latérale l’affiche déjà.

### Sans compte
- Le site garde le choix « Continuer sans compte » dans le cookie `vv_guest` et les favoris sans compte dans le stockage du navigateur. L’app garde les deux sur le téléphone (`UserDefaults`), sans identifiant ni jeton.
- Sur téléphone, le site sans compte n’a pas de barre d’onglets. L’app non plus : elle n’affiche que la page Stations, sans barre d’onglets, et la carte d’une station flotte à la place de la barre, à 24 pt des bords.
- « Se connecter » est un bouton gris brume sur le site, une capsule Liquid Glass avec l’icône de connexion à côté d’« Actualiser » dans l’app. Quand la capsule ne laisse pas le titre de la page en entier, l’app affiche à la place un bouton rond avec la seule icône, de la taille du bouton Compte.

### Présentation des confirmations
- Dans la fiche d’un vélo, le site affiche « Réserver ce vélo ? » ou « Déverrouiller ce vélo ? » dans un encadré gris, dans la fiche elle-même. L’app ouvre une feuille par-dessus, dont le titre est la question avec le vélo (« Réserver le vélo 20449 ? », « Déverrouiller le vélo 20449 ? »), puis la phrase et Annuler / Confirmer. Le texte, les boutons, l’avertissement à plus de 200 m et les états d’erreur sont les mêmes.
- Le site écrit « Réserver » et « Déverrouiller » en minuscules, côte à côte. L’app les écrit en capitales, qui ne tiennent pas côte à côte avec leurs icônes sur un iPhone : les deux boutons sont toujours empilés sur toute la largeur, à la même taille, plutôt que de réduire « DÉVERROUILLER ».
- Les réglages à confirmer (utilisation automatique des points, renouvellement automatique) utilisent l’interrupteur natif d’iOS, en rouge. Le toucher ouvre seulement la confirmation, comme sur le site.
- « Effacer » le Journal technique demande d’abord « Effacer le journal ? » (Effacer / Annuler), dans le menu natif d’iOS.
- Les fenêtres du site sont des boîtes de dialogue centrées sur ordinateur, ou des feuilles en bas de l’écran sur téléphone. L’app utilise les feuilles iOS : on peut les baisser d’un geste, sauf pendant un envoi.
- L’app ajoute des retours haptiques : un léger à chaque choix (onglet, menu, étoile, station, barre de graphique), un plus marqué à la confirmation d’un envoi, puis succès, refus ou avertissement quand le résultat est incertain.
- Sur un trajet litigieux, « Écrire au service client » ouvre l’onglet Compte sur la page du formulaire, avec ce trajet déjà choisi. Le site ouvre le même formulaire dans sa carte.

### Reçus et presse-papiers
- Le site télécharge le PDF du reçu. Dans l’app, « Reçu » télécharge le PDF, puis le bouton devient « Partager » et ouvre la feuille de partage iOS. Seul l’app peut dire « Le reçu n’a pas pu être enregistré sur ce téléphone. ».
- Seul le site peut échouer à copier : « Copie impossible. Sélectionnez le code pour le copier. ». Dans l’app, la copie ne peut pas échouer.

### Live Activities et widgets
Ces éléments n’existent que dans l’app :
- Réservation en cours sur l’écran verrouillé et dans la Dynamic Island : le pilule « Réservé », le compte à rebours, « Vélo 20449 », puis « Borne 4 · Bellecour / Saint-Exupéry » dessous, et « Expirée ».
- Trajet en cours : « En trajet » puis « Terminé », le chronomètre et « Vélo 20449 ».
Le bandeau de réservation dans l’app et sur le site reste identique : l’horloge et le compte à rebours, puis « Déverrouiller ».
Avec VoiceOver, la Live Activity se lit en une phrase : « Vélo 20449 réservé, 12 min restantes » ou « Vélo 20449, en trajet depuis 23 min ».
Dans l’app, le bandeau du trajet en cours reprend le bandeau rouge de la réservation : le vélo dans un cercle blanc, le temps écoulé, puis « 15 minutes de plus ».

### Apparence propre à iOS
- La barre d’onglets du bas, les boutons Actualiser et Compte de l’en-tête et la barre de recherche des Stations utilisent le matériau Liquid Glass d’iOS. Le site utilise des surfaces blanches avec un filet. Les pages qui défilent disparaissent sous une bande blanche en haut (barre d’état et barre de navigation) et en bas (barre d’onglets), pour que le verre ne laisse pas transparaître une traînée rose sous un bouton ou une carte rouge.
- Les filtres (Stations, type de vélo des Trajets, période des Statistiques) ouvrent le menu natif d’iOS en Liquid Glass (`Menu` avec un `Picker` intégré), où iOS coche le choix actuel. Les champs de formulaire (Pays, Objet, Trajet, Station pleine) ouvrent une feuille opaque en détente `.large` avec la liste des choix ; le choix actuel y est en texte rouge, sans coche, comme sur le site (`App/Design/SelectField.swift`). Le site garde sa liste blanche maison.
- La règle du propriétaire est : pas de coche dans un menu ouvert, le choix actuel est simplement en rouge. La feuille de choix la suit. Le menu natif des filtres ne la suit pas encore, car iOS y dessine sa coche ; c’est un écart à corriger, pas une différence voulue.
- L’app utilise la police des chiffres « Velov Glyphic Timer » pour les comptes à rebours des Live Activities.

### Diagnostic
- Ni le site ni l’app n’affichent de ligne technique sous une erreur.
- Le bandeau d’erreur de l’app est dessiné dans sa propre fenêtre, au-dessus des feuilles : une erreur passagère reste visible quand une feuille est ouverte. L’en-tête de la page est masqué tant que le bandeau est affiché, pour qu’aucun morceau ne dépasse autour.
- Seule l’app a le Journal technique (page Compte) : les 50 dernières lectures, plus les 100 dernières écritures et lectures faites pour une action, gardées 14 jours, envoyées à Vélo’v (heure, méthode, chemin aux identifiants masqués sauf numéros de station et de vélo, statut HTTP ou code d’erreur, durée, action, protocole, connexion neuve ou réutilisée, octets envoyés), sans jeton, en-tête, contenu, nom, e-mail ni téléphone, avec « Partager » et « Effacer ».
- Après un déverrouillage incertain, l’app relit seule les trajets en cours pendant environ 70 secondes, puis vérifie de nouveau 2 minutes après l’envoi. Le site rend la main tout de suite.
