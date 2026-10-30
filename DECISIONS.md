# Choix de conception

Ce document rassemble les règles que le code respecte et les raisons de quelques choix moins évidents. L’app suit la [version web](https://github.com/DailyXplorer/velov-plus) : mêmes textes, mêmes règles, mêmes hypothèses sur l’API.

## Écritures

Toute requête qui modifie le compte part exactement une fois par confirmation de l’utilisateur. Elle ne passe jamais par le client de lecture, qui sait réessayer, et n’est jamais renvoyée, quelle que soit la réponse. Pour un déverrouillage, la borne a pu s’ouvrir sans que la réponse arrive ; pour une réservation, des points ont pu être débités.

Chaque écriture part sur une connexion neuve : l’app crée une session `URLSession` pour cette seule requête, puis la ferme (`FreshConnectionTransport`, `Packages/VelovCore/Sources/VelovCore/HTTP.swift`). Le jeton de l’application, la connexion et l’actualisation de la session, qui sont aussi des POST, passent par le même chemin. Une connexion restée ouverte entre deux lectures peut mourir sans que le téléphone le sache. URLSession relance alors seul une lecture, mais jamais un POST : le déverrouillage échouait ainsi en « Connexion perdue après 0 s » (-1005) alors que toutes les lectures passaient. Les lectures gardent la session partagée. Même sur une connexion neuve, une connexion perdue ou un délai dépassé reste incertain.

Un échec est classé comme refus certain ou comme résultat incertain, à la manière de `isUncertain` côté web. Sont des refus certains les erreurs détectées sur le téléphone avant tout envoi (codes `local.`), les erreurs 4xx accompagnées d’un code et les états d’échec explicites du déverrouillage. Une erreur avant l’envoi est toujours un refus certain, même quand c’est une lecture préalable ou l’actualisation de la session qui ne répond pas (« Vélo’v ne répond pas. Rien n’a été envoyé. », `beforeSending`) : seule la requête d’écriture elle-même peut laisser un résultat incertain. Tout le reste est incertain : absence de réponse, délai dépassé, erreur 5xx ou page de passerelle, réponse 2xx illisible, erreur 4xx sans code, redirection, et l’état `TIME_OUT` d’un déverrouillage. Un 401 nu à une écriture partie est donc incertain, pour toutes les écritures : la passerelle a pu le renvoyer après l’exécution. L’app met fin à la session, et l’écriture garde son « Vérifier » pour la reconnexion. Une écriture ne suit jamais de redirection. Une réservation n’est réussie que si la réponse décrit la réservation demandée, même station et même vélo ; un 2xx vide, étranger ou sans vélo reste incertain. Après un résultat incertain, la feuille ne propose plus que « Fermer » ou « Vérifier ». Son message ne donne que la cause (« Vélo’v ne répond pas. Le vélo est peut-être déverrouillé. ») et la consigne n’apparaît qu’une fois, dans « Le résultat est incertain : vérifiez avant de réessayer. » ; « n’a pas abouti » est réservé aux refus certains. Le succès d’une écriture se lit dans `transactionState`, jamais dans le seul statut HTTP.

Un résultat incertain n’expire jamais avec le temps : il garde sa cible et la valeur voulue jusqu’à une vérification ciblée. Le déverrouillage est confirmé par un trajet du même vélo, et infirmé seulement sans trajet passé 2 minutes ; la réservation par la liste des réservations ; la note, le profil, les favoris, l’utilisation automatique et le renouvellement par une relecture comparée à la valeur voulue au moment de l’envoi. Un état inchangé ne vaut refus qu’après 2 minutes, le temps que Vélo’v l’affiche. Après un déverrouillage incertain, la feuille vérifie seule, sans attendre « Vérifier » : elle relit les trajets en cours pendant environ 70 secondes, le temps de retirer le vélo, puis vérifie de nouveau 2 minutes après l’envoi, tant qu’elle reste ouverte. Ce ne sont que des lectures : la requête n’est jamais renvoyée, et « Fermer » reste possible pendant ce temps. Une écriture encore « en cours » quand l’app a été fermée est incertaine dès le lancement suivant (« L’app a été fermée avant la réponse. L’action a peut-être abouti. ») : elle ne bloque aucune autre action et sa vérification démarre aussitôt.

Une réponse arrivée après une déconnexion ou un changement de compte est ignorée, et un jeton actualisé à ce moment n’est jamais enregistré.

La notation d’un vélo envoie une note par appui sur « Envoyer » : les étoiles sont le choix et le bouton vaut confirmation. Le téléchargement d’un justificatif est un POST qui ne fait que lire ; il part donc sans confirmation, une requête par appui.

Avant une réservation, l’app relit les identifiants de la station et du vélo, que le corps de la requête exige. Avant « 15 minutes de plus », elle revérifie que la station choisie est pleine et retrouve l’abonnement qui loue réellement le vélo. Avant un changement du renouvellement automatique, elle vérifie que Vélo’v l’autorise, puis relit l’état réel ; si cette relecture échoue, l’écriture n’est pas répétée et l’état reste inconnu. Un corps invalide ne quitte jamais le téléphone.

## Codes d’invitation

Le code obtenu contre des points est la seule preuve du débit. L’app vérifie donc que le stockage local est lisible et inscriptible avant le débit, puis écrit le code sur le téléphone avant toute autre chose. Un stockage illisible n’est jamais écrasé, car un ancien code peut encore s’y trouver. Les codes sont rangés dans Application Support sous une clé qui ne contient pas l’adresse du compte. Un débit qui a pu avoir lieu n’est jamais reproposé depuis la même feuille. Un solde, même inchangé ou plus élevé, ne prouve pas l’absence de débit : seul l’historique des points lu jusqu’à sa dernière page, sans débit du montant depuis l’envoi et au moins 2 minutes après, permet « Je n’ai pas été débité, réessayer ». Sinon la feuille propose « Fermer » et le service client.

## Lectures

Les lectures sont réessayées seulement sur les erreurs 502, 503 et 504, au plus trois fois et 8 secondes chacune, jamais après un délai dépassé : la passerelle de Cyclocity renvoie un 502 nu à environ une requête sur cinq. Une seule lecture tourne à la fois pour une même clé, et un échec n’est jamais mis en cache. La liste des stations sert la dernière version connue en cas de panne. Les vélos d’une station sont gardés 15 secondes pour la liste, mais une réservation les relit toujours. L’historique complet, utilisé par les statistiques, est lu page par page et gardé 10 minutes, 1 minute s’il est partiel ; l’écran suit la même durée et oublie ses statistiques à la fin d’un trajet, à un changement de compte et après une écriture qui touche aux trajets ou aux points. Seule une page vide prouve qu’un historique est complet, et un solde n’est jamais calculé sur un historique de points partiel. Les réservations sont relues une seule fois à la fois, au plus toutes les 5 secondes hors écriture. Le compte est relu une seule fois à la fois, et la dernière demande l’emporte : une demande ou un changement fait sur le téléphone pendant une lecture écarte la réponse de cette lecture et en relance une seule (`LatestLoad`).

Les réponses sont lues champ par champ : un champ obligatoire mal formé fait échouer la lecture, un champ facultatif mal formé devient simplement absent, et un vélo mal formé est ignoré sans perdre la station.

## Connexion et session

La connexion est une seule tentative ; un refus est affiché avec le message de Vélo’v et n’est jamais réessayé. Rien ne permet d’affirmer que Vélo’v limite un compte à un seul appareil : l’app n’en fait pas l’hypothèse et ne déconnecte jamais les autres sessions.

Le site, l’app et tout nouveau portage se connectent avec le client Keycloak `vls-web-lyon` (`Cyclocity.clientId`, `Packages/VelovCore/Sources/VelovCore/HTTP.swift`). Le client de l’app officielle, `vls-ios-lyon`, impose un seul appareil par compte : l’étape du formulaire d’appareil répond 4xx « Ce compte est déjà en cours d’utilisation sur un autre appareil », alors qu’un code erroné renvoie le formulaire de connexion avec un 200. `vls-web-lyon` laisse le site et l’app connectés ensemble (observé, non confirmé par l’opérateur). Quand un nouveau client reçoit ce refus, vérifier d’abord son identifiant de client avant de demander de se déconnecter ailleurs. Les pages de refus sont longues : l’app en extrait la phrase qui contient « autre appareil » ou « another device » (`HTMLForm.serverRefusal`) au lieu d’afficher un « refusé » générique. Elle n’affiche par ailleurs que le message d’erreur de Keycloak (`kc-feedback-text`, `alert-error`, `input-error`) ; tout autre corps, même court (« HTTP Status 403 - Forbidden »), donne « Vélo’v a refusé la connexion. ».

L’identifiant d’appareil est créé une fois, gardé dans le trousseau et conservé après une déconnexion, car un nouvel identifiant ressemblerait à un autre téléphone. Les jetons sont dans le trousseau, lisibles après le premier déverrouillage, jamais synchronisés. Une seule actualisation de session tourne à la fois, puisqu’un jeton d’actualisation ne sert qu’une fois, et seul un refus de ce jeton met fin à la session enregistrée. Au lancement et juste après la connexion, l’app lit l’adresse du compte dans le jeton enregistré, sans requête, pour suivre les écritures avant même que le compte soit chargé. Les identifiants ne sont envoyés qu’aux pages du domaine d’authentification de Vélo’v, et le jeton d’identité est vérifié (signature RS256, émetteur, audience, nonce, expiration).

Sans compte, l’app ne lit que les stations (flux GBFS publics) et les vélos d’une station (jeton de l’application, sans en-tête `Identity`). Elle ne charge ni compte ni réservations, et ne lance ni surveillance de fin de trajet, ni Activité en direct, ni fiche « Trajet terminé » : tout cela ne démarre qu’après la lecture du compte, et la coque sans compte (`GuestShell`) ne présente aucune des feuilles du compte. « Continuer sans compte » oublie la session enregistrée sur le téléphone, sans déconnexion auprès de Vélo’v : une session enregistrée, qui l’emporte sur un choix « sans compte » resté sur le téléphone, est donc toujours une session que l’utilisateur n’a pas quittée. Une session expirée (lecture du compte, des réservations ou des trajets en cours, ou écriture refusée en 401) fait le même ménage qu’une déconnexion (`AppModel.expire`) : les réponses encore attendues sont ignorées, la surveillance de fin de trajet s’arrête, les réservations, les feuilles, la fiche « Trajet terminé » en attente et les pages ouvertes sont effacées et les Activités en direct se terminent. Une écriture restée incertaine est gardée pour ce compte et se vérifie après la reconnexion. Toute écriture passe par `AppModel.runOnce`, qui fait ce lien. Dans les données d’exemple, une requête du compte depuis un écran sans compte arrête l’app (`SampleService.account()`), ce que les captures et `NavigationUITests` feraient voir.

## Fin de trajet

Pendant un trajet, l’app interroge les trajets en cours toutes les 20 secondes, seulement au premier plan, une requête à la fois et pendant 3 heures au plus. Elle vérifie aussitôt en revenant au premier plan. Il n’y a ni tâche de fond ni notification, car iOS ne maintiendrait pas une interrogation aussi fréquente en arrière-plan. Une notification « trajet terminé, notez le vélo » app fermée demanderait des notifications push, donc un compte développeur payant ; `BGAppRefresh` est gratuit mais iOS le lance quand il veut, de quelques minutes à quelques heures plus tard, et le propriétaire l’a refusé. Ne reproposer ni l’un ni l’autre sans compte payant. Après un déverrouillage, l’app attend jusqu’à 2 minutes que le trajet apparaisse.

Quand le vélo est raccroché, l’app relit le compte pour le prix et les réservations, ce qui termine toute Activité en direct restante. « Plus tard », comme toute autre façon de fermer la fiche « Trajet terminé », est mémorisé par trajet ; au lancement, l’app propose une seule fois le dernier trajet encore notable. La notation reste ouverte 3 heures après la fin du trajet.

## Activité en direct

L’Activité en direct de la réservation est démarrée et arrêtée par l’app seule : aucun jeton push n’est demandé et il n’y a pas d’App Group. Si iOS la refuse, rien d’autre n’en dépend et le bandeau de l’app reste affiché. Le widget utilise les mêmes icônes et les deux mêmes polices que l’app. Les captures de l’écran verrouillé et de la Dynamic Island dessinent les vues du widget sur une maquette, car un script ne peut pas verrouiller le simulateur.

L’Activité « trajet en cours » démarre après un déverrouillage réussi, ou quand l’app ouverte voit un trajet en cours sans activité affichée, et remplace alors celle de la réservation. Le temps écoulé avance seul grâce à Text(timerInterval:), sans mise à jour quand l’app est fermée. Elle se termine quand l’app voit le trajet fini et garde la durée finale 5 minutes, et une réponse plus ancienne qui liste encore ce trajet ne la relance pas ; une réponse vide dans les 2 minutes qui suivent le déverrouillage ne la termine pas. Elle devient périmée 4 heures après le départ et est retirée au lancement suivant. Elle affiche la station de départ et le numéro du vélo, sans son type : comme pour la réservation, le type n’y sert à rien. Les minutes gratuites de l’abonnement ne sont affichées nulle part : aucun champ chiffré lu par l’app ne les donne.

iOS force les chiffres tabulaires dans tout minuteur système (`Text(timerInterval:)`, styles `.timer`), quels que soient `.monospacedDigit()` ou les réglages de la police, ce qui laisse un blanc après chaque « 1 » (« 1 2:27 »). Les minuteurs utilisent donc une copie de la police sans la fonction `tnum`, `VelovGlyphicTimer-Regular.ttf`, produite par `scripts/make-number-font.py` (la licence OFL le permet sous un autre nom), dans un cadre de largeur fixe.

## Hypothèses sur l’API

Certaines écritures reposent sur des formats que la documentation publique laisse ouverts. Ils sont regroupés dans `Guesses.swift`, identique à `lib/guesses.ts` côté web. Ce sont des constantes à corriger après vérification, jamais des variantes essayées l’une après l’autre.

| Écriture | Hypothèse | Confiance | Source |
| --- | --- | --- | --- |
| Renouvellement automatique (`PATCH …/subscriptions/{id}`) | Corps `isAutoRenewal` | Moyenne | VLSKit, `Models/Subscription.swift` |
| « 15 minutes de plus » (`POST …/subscriptions/{id}/via`) | Type de média et champ `stationId` | Élevée | community-README §5.5, VLSKit `SubscriptionService.swift` |
| « 15 minutes de plus » | La station est désignée par son numéro, pas son UUID | Moyenne | VLSKit `Models/Subscription.swift` |
| Service client (`POST …/mail`, multipart) | Noms des champs | Élevée | community-README §10 |
| Service client | Catégories de réclamation | Moyenne | VLSKit `EmailService.swift` |
| Code d’invitation (`POST …/rewards/consume/promocode`) | Requête sans corps, réponse avec le code | Élevée | community-README §5.8, VLSKit `RewardService.swift` |

Le message au service client n’envoie pas d’identifiant de trajet, dont le format attendu est incertain : le code du trajet choisi est ajouté au texte. Aucune étape de souscription n’est envoyée après l’obtention d’un code d’invitation.

## Interface

L’app est en mode clair uniquement, avec le rouge pour seule couleur d’accent, et aucune vue ne projette d’ombre. La barre d’onglets flotte à 24 points des bords ; son rayon est concentrique avec l’écran et toutes les surfaces flottantes le reprennent sur leurs quatre coins. Les textes viennent de la version web, avec « ce téléphone » à la place de « ce navigateur » et une espace insécable devant ? ! : ;. Les titres et les grands nombres sont en Velov Glyphic, une version de Faculty Glyphic dont le 1 tabulaire garde l’approche du 1 proportionnel et qui ajoute l’espace fine insécable du séparateur de milliers ; le reste est en DM Sans.

Chaque onglet est créé à sa première visite puis gardé en vie, masqué quand un autre est affiché. Les cartes ne sont donc jamais reconstruites, et un changement d’onglet ramène simplement la page quittée en haut. Le classement des stations est calculé hors du fil principal, seulement quand la liste, la recherche, le filtre, les favoris ou la position changent. La pastille rouge de la barre d’onglets glisse vers l’onglet choisi avec un léger rebond et un retour haptique ; si « Réduire les animations » est activé, elle glisse simplement, sans s’étirer ni rebondir (`PillMotion.retarget`, `App/Screens/Shell.swift`).

### Identité et comportements iOS

- L’app garde l’identité du site (rouge, titres et nombres en Velov Glyphic, texte en DM Sans, pastilles, cartes, filet de 1 pt) et adopte les comportements d’iOS : vraie navigation avec retour en haut à gauche et glissement retour (bloqué seulement pendant l’envoi d’une écriture), feuilles et menus natifs, retours haptiques, zones de toucher d’au moins 44 pt, une seule échelle d’espacement régulière et aérée.
- L’icône de l’app est « Vélo’v+ » en Faculty Glyphic blanc sur fond rouge, dessinée par `scripts/make-icon.swift`.
- DM Sans n’a pas l’espace fine insécable U+202F : dans un texte en DM Sans, le séparateur de milliers est U+00A0 ; U+202F ne sert qu’en Velov Glyphic.
- Ne jamais ajouter de sixième onglet à la barre flottante, trop serrée. Une page secondaire s’ouvre depuis un bouton en haut de l’onglet lié, en page plein écran poussée, avec le contenu du site (Swift Charts, rouge et gris brume seulement).

### Surfaces flottantes

- Le rayon de la barre d’onglets vient de `concentricCornerRadii` (iOS 27), sinon du rayon de l’écran moins le retrait de 24 pt (`Concentric`, 38 pt sur iPhone 17 Pro).
- Chaque élément flottant reprend ce rayon, identique sur ses quatre coins. Des petits coins en haut avec de grands coins concentriques en bas ont été essayés puis refusés.
- Les feuilles système reçoivent le même rayon avec `presentationCornerRadius` ; les feuilles pleine hauteur gardent les coins du bas de l’écran. Un élément imbriqué prend le rayon intérieur (rayon extérieur moins la marge) ; les cartes qui défilent gardent un rayon de 16.
- La fiche d’une station est une carte flottante au-dessus de la barre d’onglets (barre toujours visible, mêmes retraits de 24 pt sur les côtés, 12 pt d’écart, hauteur selon le contenu). « Plans » et les mentions légales de MapKit passent au-dessus grâce à la zone sûre de la carte, jamais à moitié cachés ; une marge horizontale de zone sûre les aligne sur le bord gauche de la carte de station (`StationMapView.attributionInset`, MapKit ajoute lui-même 11 pt). Vérifier que rien (contrôles de la carte, dernière ligne d’une liste) ne passe sous la barre.
- Dans une feuille qui a sa propre pile de navigation, la page racine et les pages poussées affichent toutes la barre iOS. Une barre masquée sur la racine puis affichée sur la page poussée se place 16 pt trop haut pendant la transition et saute à sa place à la fin (`BikeSheetJumpUITests`).
- La bande réservée au-dessus des graphiques pour l’infobulle reste à 56 pt (`tipBand`, `App/Screens/StatsPage.swift`) : une infobulle de deux lignes mesure environ 52 pt avec ses marges, une bande de 40 pt la couperait.
- Les pages qui défilent passent sous une bande blanche opaque, sous la barre d’état et la barre de navigation en haut, et au bord supérieur de la barre d’onglets en bas (`hidesUnderBars`) : sous le verre, il n’y a que le blanc de la page, jamais un bouton ou une carte rouge qui ferait une traînée rose. La coupe est nette : un dégradé vers le blanc, en masque comme en surimpression, rend le rouge rose.
- Liquid Glass (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`) est réservé aux commandes flottantes : barre d’onglets (l’onglet actif reste une capsule rouge pleine), boutons Compte et Actualiser en haut à droite, commandes et carte de station au-dessus de la carte. Les cartes de contenu, les listes, les formulaires, les statistiques et le bandeau rouge de réservation restent opaques. Protéger avec `#available` sous iOS 26.
- La pastille rouge de la barre est dessinée une seule fois, dans le fond de la barre, placée d’après les cadres mesurés des onglets. Elle voyage vers l’onglet touché comme une bulle liquide : le bord avant mène, le bord arrière traîne, elle s’étire en capsule plus fine puis se contracte avec un petit ressort. Une pastille `matchedGeometryEffect` dans chaque onglet avec une transition d’opacité donnait l’effet d’une disparition puis d’une réapparition et a été refusée. Prouver un changement de cette animation par un enregistrement du simulateur avant de l’installer.

### Menus et champs de choix

- Les filtres utilisent le `Menu` natif et les champs de formulaire une feuille native. Un `Menu { Picker(.inline) }` s’ouvre vers le haut, par-dessus son bouton, quand la place manque en dessous (champs de formulaire au-dessus de la barre d’onglets), ce que le propriétaire a trouvé « détaché » ; une bulle `.popover` avec une flèche était « bizarre ». Répondre aux questions sur les éléments iOS avec la convention de la plateforme, sans inventer d’ancrage maison.
- Les feuilles de choix (Pays, Objet, Trajet, Station pleine) utilisent toutes la même détente `.large` opaque : iOS 26 affiche une feuille `.medium` en verre translucide flottant avec une poignée, et une feuille `.large` opaque sur fond gris groupé. Choisir la détente selon le nombre d’options donnait à un même contrôle un aspect différent d’un champ à l’autre.

## Localisation

- Une seule instance de CoreLocation, gardée pour toute l’app (`Locator.shared`) : son délégué est faible, et une instance créée à chaque appel peut perdre des réponses.
- Le délai de localisation ne démarre qu’une fois l’autorisation accordée : un délai lancé avant la réponse à la demande d’autorisation fait échouer les utilisateurs lents.
- `CLError.locationUnknown` est ignoré et l’app continue d’attendre.

## Diagnostic

Quand une action échoue dans l’app alors qu’elle marche sur le site, comparer d’abord les deux requêtes (adresse, corps, en-têtes, délai) pour écarter la requête elle-même, puis demander le Journal technique au lieu de deviner une cause.

Le Journal technique range à part les écritures et les lectures faites pour une action : les 100 dernières, gardées 14 jours, en plus des 50 dernières autres lectures. Chaque ligne note aussi le protocole, si la connexion était neuve ou réutilisée et les octets envoyés : après un échec, on voit si la requête est partie sur une vieille connexion.

## Règles produit

Ces règles du propriétaire valent pour l’app comme pour le site, où elles sont détaillées dans `docs/design-rules.md`.

- Le rouge est la seule couleur d’accent. Jamais de rose, de saumon ni d’encadré teinté de rouge.
- Aucune ombre portée. Aucun contour de focus.
- Dans un menu ou une liste de choix ouverte, pas de coche : le choix actuel est simplement en rouge. Les feuilles de choix la suivent ; le menu natif des filtres pas encore (voir `docs/parity.md`).
- Rien de souligné. Le texte sélectionné est blanc sur rouge sur le site ; dans l’app, la sélection est dessinée par le système.
- Deux polices seulement : Faculty Glyphic (Velov Glyphic) pour les titres et les grands nombres, DM Sans pour le reste.
- Icônes du jeu gratuit Hugeicons partout, jamais d’icône Pro.
- Barre d’onglets : icônes et libellés noirs, onglet choisi blanc sur sa pastille rouge.
- Des boutons côte à côte ont exactement la même taille, fond de pression compris, quelle que soit la longueur de leur texte. Leur texte n’est jamais réduit : quand le plus long ne tient pas en pleine taille dans la moitié de la largeur, les deux boutons s’empilent sur toute la largeur (`PairedActions`, `App/Design/WriteSheet.swift`). De même, le bouton blanc d’un bandeau rouge passe sous l’horloge, sur toute la largeur, quand il ne tient pas à côté (`RedBanner`, `App/Design/Components.swift`).
- Ouvrir une fenêtre ou une feuille ne décale rien. Un squelette de chargement a exactement la forme du contenu chargé, en une seule étape, avec un reflet gris brume.
- Jamais de badge « Expérimental » : une fonction au format deviné part comme une fonction normale.
- Majuscule en début de ligne, de libellé et après un séparateur (« · », « — ») : « Vélo 27619 · Borne 4 ». Les MAJUSCULES des boutons et des étiquettes restent.
- Un français naturel et court, une idée par phrase, au vouvoiement, sans traduction mot à mot ni enchaînement de propositions.
- Aucune information évidente ni texte d’explication : pas de « à vol d’oiseau », pas de raison sous « Recommandé », pas de note de méthode dans les statistiques, pas de type de vélo dans l’Activité du trajet.
- Les chiffres sont en noir, sans le mot « points » quand le libellé le dit déjà. Ni coût ni durée sur un bouton d’action ; le coût n’apparaît que dans la confirmation. Pas de points sur « Envoyer ».
- Un trajet litigieux se voit tout de suite, sans rien déplier.
- Une seule confirmation, sans liste avant/après ni rappel du solde. Pas d’écran « c’est fait » ni de « Merci ! +5 points » : la feuille se ferme et la page montre le nouvel état, sauf quand le résultat est l’information (le code d’invitation).
- Aucune saisie de moyen de paiement ni achat de formule : les laisser au site officiel.
- Les menus suivent le style iOS, avec la liste attachée à son bouton.
- Remplacer un élément maison par un élément natif seulement avec l’accord du propriétaire.
- Fiche vélo : RÉSERVER et DÉVERROUILLER sont empilés, en pleine largeur et à la même taille de texte ; aucun des deux n’est rétréci (validé par le propriétaire).
- Tout changement de texte ou d’apparence d’un côté est reporté de l’autre dans le même lot, sans attendre qu’on le redemande ; seuls Liquid Glass et les widgets sont propres à l’app.
- Dans tout menu, liste de choix ou sélecteur, le fond d’une ligne touchée ou choisie a la même marge à gauche et à droite, ou va d’un bord à l’autre. Les menus et feuilles natifs d’iOS le font d’eux-mêmes ; les lignes maison (`.row`) débordent du même côté des deux côtés.
- Aucun code, statut HTTP, nom d’erreur ni ligne technique à l’écran. Une erreur passagère (localisation refusée, trop lente ou introuvable, actualisation ratée, action ratée sur un écran qui reste utilisable) s’affiche dans un petit bandeau en haut, au centre : un seul à la fois, fermé par X ou au bout de 5 secondes, lu par VoiceOver (`App/Design/Toast.swift`). Pendant qu’il est affiché, l’en-tête de la page (titre, Actualiser, Compte) est masqué, pour qu’aucun morceau ne dépasse autour du bandeau. Un écran qui ne peut rien afficher garde un message simple et « Réessayer ». Une feuille de confirmation garde son message et l’avertissement d’incertitude. Le détail technique ne va que dans le Journal technique.
- Chaque échec de localisation a son message : refus « Autorisez la localisation dans Réglages pour trouver les stations autour de vous. » (avec « Ouvrir Réglages »), délai « La localisation a pris trop de temps. Réessayez. », position introuvable « Position introuvable pour le moment. ».
- Aucune icône dans un bouton « Itinéraire ». Les autres boutons d’action gardent leur icône, sauf une flèche de lien externe.
- « Plans » et « Mentions légales » d’Apple ne sont jamais masqués ni couverts. Sur la carte des Stations, avec ou sans compte, avec ou sans fiche de station, ils ont la même marge gauche que la barre de recherche et la carte de station (24 pt) et se posent juste au-dessus de l’élément flottant du bas (carte de station ou barre d’onglets), ou, s’il n’y en a pas, juste au-dessus de la zone de l’indicateur d’accueil. Sur la carte de l’accueil, ils prennent la marge intérieure des cartes (16 pt). Un marqueur de station qui tomberait sur eux est retiré de la carte tant qu’il y est, sauf la station choisie.
- Le mode sans compte a exactement le même design qu’avec compte, seulement sans certaines fonctions : aucun composant, rayon, marge ni style propre. Les deux modes passent par la même coque flottante (`FloatingHost`, `App/Screens/Shell.swift`) : même rayon concentrique, même écart de 12 pt au-dessus de l’élément du bas (barre d’onglets avec compte, zone de l’indicateur d’accueil sans compte). Seules les fonctions qui demandent un compte sont masquées ou remplacées par « Se connecter ».
- Une date « prochaine » déjà passée se lit comme un retard : « Prochain contrôle » affiche « En retard » et, dessous, « Prévu le 12 oct. 2026 », jamais « Il y a 18 j ».
- Dans l’alerte « Ignorer les modifications ? », seul « Ignorer » est rouge ; « Continuer la saisie » est en noir.
- Écran de connexion : « Continuer sans compte » juste sous « Se connecter », avec l’écart normal. Aucune place n’est réservée à l’erreur, qui s’affiche dans le bandeau du haut.

## Dépôt

- Aucun agent n’envoie d’écriture au vrai compte Vélo’v, ne se connecte à un vrai compte ni ne teste une version installée sans l’accord explicite du propriétaire pour cette action précise. Les tests simulent le réseau ; `make smoke` ne fait que des lectures publiques.
- Chaque correction d’un défaut arrive avec un test simulé qui échoue avant la correction et passe après.
- Aucun commentaire dans le code, aucun fichier inutile versionné (brouillons, consignes d’agent). Le README est en français et reste utile : ce que fait l’app, comment elle marche, comment la compiler, la tester et l’installer.
- Les identifiants personnels (UDID, identifiant d’équipe Apple, nom, chemins personnels, jetons) restent dans des fichiers locaux ignorés par git, à côté d’un fichier `.example` versionné, comme `Local.xcconfig`.
- Les règles de développement communes au site et à l’app (relecture, publication d’un dépôt, captures) sont dans `docs/development.md` du dépôt web.

## Façon de travailler

- Les bugs se trouvent avant le propriétaire : après chaque lot, une passe QA autonome capture chaque écran et chaque état (avec et sans compte, fiche ouverte et fermée, listes vides, erreurs, chargement, petit et grand iPhone, transitions image par image), audite le code des flux critiques (déverrouillage, réservation, fin de trajet, connexion, erreurs réseau, journal) et passe une co-review Codex croisée avec la review Opus.
- Ce qui est trouvé est corrigé, relu, poussé et installé sans attendre l’accord du propriétaire ; il reçoit un rapport court avec une capture par écran modifié, pour information.
- Seules les actions réelles hors du code demandent son accord : un vrai déverrouillage ou une vraie réservation (cela démarre une location sur son compte), un paiement, un message envoyé en son nom.
- Les petits retours sont livrés en 20 à 30 minutes ; le nettoyage de fond tourne à part sans les bloquer.
