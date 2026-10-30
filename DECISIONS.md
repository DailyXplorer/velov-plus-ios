# Choix de conception

Ce document rassemble les règles que le code respecte et les raisons de quelques choix moins évidents. L’app suit la [version web](https://github.com/DailyXplorer/velov-plus) : mêmes textes, mêmes règles, mêmes hypothèses sur l’API.

## Écritures

Toute requête qui modifie le compte part exactement une fois par confirmation de l’utilisateur. Elle ne passe jamais par le client de lecture, qui sait réessayer, et n’est jamais renvoyée, quelle que soit la réponse. Pour un déverrouillage, la borne a pu s’ouvrir sans que la réponse arrive ; pour une réservation, des points ont pu être débités.

Un échec est classé comme refus certain ou comme résultat incertain, à la manière de `isUncertain` côté web. Sont des refus certains les erreurs détectées sur le téléphone avant tout envoi (codes `local.`), les erreurs 4xx accompagnées d’un code et les états d’échec explicites du déverrouillage. Tout le reste est incertain : absence de réponse, délai dépassé, erreur 5xx ou page de passerelle, réponse 2xx illisible, erreur 4xx sans code, redirection, et l’état `TIME_OUT` d’un déverrouillage. Une écriture ne suit jamais de redirection. Une réservation n’est réussie que si la réponse décrit la réservation demandée ; un 2xx vide ou étranger reste incertain. Après un résultat incertain, la feuille ne propose plus que « Fermer » ou « Vérifier ». Le succès d’une écriture se lit dans `transactionState`, jamais dans le seul statut HTTP.

Un résultat incertain n’expire jamais avec le temps : il garde sa cible et la valeur voulue jusqu’à une vérification ciblée. Le déverrouillage est confirmé par un trajet du même vélo, et infirmé seulement sans trajet passé 2 minutes ; la réservation par la liste des réservations ; la note, le profil, les favoris, l’utilisation automatique et le renouvellement par une relecture comparée à la valeur voulue au moment de l’envoi. Un état inchangé ne vaut refus qu’après 2 minutes, le temps que Vélo’v l’affiche.

Une réponse arrivée après une déconnexion ou un changement de compte est ignorée, et un jeton actualisé à ce moment n’est jamais enregistré.

La notation d’un vélo envoie une note par appui sur « Envoyer » : les étoiles sont le choix et le bouton vaut confirmation. Le téléchargement d’un justificatif est un POST qui ne fait que lire ; il part donc sans confirmation, une requête par appui.

Avant une réservation, l’app relit les identifiants de la station et du vélo, que le corps de la requête exige. Avant « 15 minutes de plus », elle revérifie que la station choisie est pleine et retrouve l’abonnement qui loue réellement le vélo. Avant un changement du renouvellement automatique, elle vérifie que Vélo’v l’autorise, puis relit l’état réel ; si cette relecture échoue, l’écriture n’est pas répétée et l’état reste inconnu. Un corps invalide ne quitte jamais le téléphone.

## Codes d’invitation

Le code obtenu contre des points est la seule preuve du débit. L’app vérifie donc que le stockage local est lisible et inscriptible avant le débit, puis écrit le code sur le téléphone avant toute autre chose. Un stockage illisible n’est jamais écrasé, car un ancien code peut encore s’y trouver. Les codes sont rangés dans Application Support sous une clé qui ne contient pas l’adresse du compte. Un débit qui a pu avoir lieu n’est jamais reproposé depuis la même feuille. Un solde, même inchangé ou plus élevé, ne prouve pas l’absence de débit : seul l’historique des points lu jusqu’à sa dernière page, sans débit du montant depuis l’envoi et au moins 2 minutes après, permet « Je n’ai pas été débité, réessayer ». Sinon la feuille propose « Fermer » et le service client.

## Lectures

Les lectures sont réessayées seulement sur les erreurs 502, 503 et 504, au plus trois fois et 8 secondes chacune, jamais après un délai dépassé : la passerelle de Cyclocity renvoie un 502 nu à environ une requête sur cinq. Une seule lecture tourne à la fois pour une même clé, et un échec n’est jamais mis en cache. La liste des stations sert la dernière version connue en cas de panne. Les vélos d’une station sont gardés 15 secondes pour la liste, mais une réservation les relit toujours. L’historique complet, utilisé par les statistiques, est lu page par page et gardé 10 minutes, 1 minute s’il est partiel ; l’écran suit la même durée et oublie ses statistiques à la fin d’un trajet, à un changement de compte et après une écriture qui touche aux trajets ou aux points. Seule une page vide prouve qu’un historique est complet, et un solde n’est jamais calculé sur un historique de points partiel. Les réservations sont relues une seule fois à la fois, au plus toutes les 5 secondes hors écriture.

Les réponses sont lues champ par champ : un champ obligatoire mal formé fait échouer la lecture, un champ facultatif mal formé devient simplement absent, et un vélo mal formé est ignoré sans perdre la station.

## Connexion et session

La connexion est une seule tentative ; un refus est affiché avec le message de Vélo’v et n’est jamais réessayé. Rien ne permet d’affirmer que Vélo’v limite un compte à un seul appareil : l’app n’en fait pas l’hypothèse et ne déconnecte jamais les autres sessions.

Le site, l’app et tout nouveau portage se connectent avec le client Keycloak `vls-web-lyon` (`Cyclocity.clientId`, `Packages/VelovCore/Sources/VelovCore/HTTP.swift`). Le client de l’app officielle, `vls-ios-lyon`, impose un seul appareil par compte : l’étape du formulaire d’appareil répond 4xx « Ce compte est déjà en cours d’utilisation sur un autre appareil », alors qu’un code erroné renvoie le formulaire de connexion avec un 200. `vls-web-lyon` laisse le site et l’app connectés ensemble (observé, non confirmé par l’opérateur). Quand un nouveau client reçoit ce refus, vérifier d’abord son identifiant de client avant de demander de se déconnecter ailleurs. Les pages de refus sont longues : l’app en extrait la phrase qui contient « autre appareil » ou « another device » (`HTMLForm.serverRefusal`) au lieu d’afficher un « refusé » générique.

L’identifiant d’appareil est créé une fois, gardé dans le trousseau et conservé après une déconnexion, car un nouvel identifiant ressemblerait à un autre téléphone. Les jetons sont dans le trousseau, lisibles après le premier déverrouillage, jamais synchronisés. Une seule actualisation de session tourne à la fois, puisqu’un jeton d’actualisation ne sert qu’une fois, et seul un refus de ce jeton met fin à la session. Les identifiants ne sont envoyés qu’aux pages du domaine d’authentification de Vélo’v, et le jeton d’identité est vérifié (signature RS256, émetteur, audience, nonce, expiration).

## Fin de trajet

Pendant un trajet, l’app interroge les trajets en cours toutes les 20 secondes, seulement au premier plan, une requête à la fois et pendant 3 heures au plus. Elle vérifie aussitôt en revenant au premier plan. Il n’y a ni tâche de fond ni notification, car iOS ne maintiendrait pas une interrogation aussi fréquente en arrière-plan. Une notification « trajet terminé, notez le vélo » app fermée demanderait des notifications push, donc un compte développeur payant ; `BGAppRefresh` est gratuit mais iOS le lance quand il veut, de quelques minutes à quelques heures plus tard, et le propriétaire l’a refusé. Ne reproposer ni l’un ni l’autre sans compte payant. Après un déverrouillage, l’app attend jusqu’à 2 minutes que le trajet apparaisse.

Quand le vélo est raccroché, l’app relit le compte pour le prix et les réservations, ce qui termine toute Activité en direct restante. « Plus tard », comme toute autre façon de fermer la fiche « Trajet terminé », est mémorisé par trajet ; au lancement, l’app propose une seule fois le dernier trajet encore notable. La notation reste ouverte 3 heures après la fin du trajet.

## Activité en direct

L’Activité en direct de la réservation est démarrée et arrêtée par l’app seule : aucun jeton push n’est demandé et il n’y a pas d’App Group. Si iOS la refuse, rien d’autre n’en dépend et le bandeau de l’app reste affiché. Le widget utilise les mêmes icônes et les deux mêmes polices que l’app. Les captures de l’écran verrouillé et de la Dynamic Island dessinent les vues du widget sur une maquette, car un script ne peut pas verrouiller le simulateur.

L’Activité « trajet en cours » démarre après un déverrouillage réussi, ou quand l’app ouverte voit un trajet en cours sans activité affichée, et remplace alors celle de la réservation. Le temps écoulé avance seul grâce à Text(timerInterval:), sans mise à jour quand l’app est fermée. Elle se termine quand l’app voit le trajet fini et garde la durée finale 5 minutes ; une réponse vide dans les 2 minutes qui suivent le déverrouillage ne la termine pas. Elle devient périmée 4 heures après le départ et est retirée au lancement suivant. Elle affiche la station de départ et le numéro du vélo, sans son type : comme pour la réservation, le type n’y sert à rien. Les minutes gratuites de l’abonnement ne sont affichées nulle part : aucun champ chiffré lu par l’app ne les donne.

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
- La fiche d’une station est une carte flottante au-dessus de la barre d’onglets (barre toujours visible, mêmes retraits de 24 pt sur les côtés, 12 pt d’écart, hauteur selon le contenu). « Plans » et les mentions légales de MapKit passent au-dessus grâce à la zone sûre de la carte, jamais à moitié cachés. Vérifier que rien (contrôles de la carte, dernière ligne d’une liste) ne passe sous la barre.
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

## Règles produit

Ces règles du propriétaire valent pour l’app comme pour le site, où elles sont détaillées dans `docs/design-rules.md`.

- Le rouge est la seule couleur d’accent. Jamais de rose, de saumon ni d’encadré teinté de rouge.
- Aucune ombre portée. Aucun contour de focus.
- Dans un menu ou une liste de choix ouverte, pas de coche : le choix actuel est simplement en rouge. L’app ne suit pas encore cette règle (voir `docs/parity.md`).
- Rien de souligné. Le texte sélectionné est blanc sur rouge sur le site ; dans l’app, la sélection est dessinée par le système.
- Deux polices seulement : Faculty Glyphic (Velov Glyphic) pour les titres et les grands nombres, DM Sans pour le reste.
- Icônes du jeu gratuit Hugeicons partout, jamais d’icône Pro.
- Barre d’onglets : icônes et libellés noirs, onglet choisi blanc sur sa pastille rouge.
- Des boutons côte à côte ont exactement la même taille, fond de pression compris, quelle que soit la longueur de leur texte.
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
- Tout changement de texte ou d’apparence d’un côté est reporté de l’autre dans le même lot, sans attendre qu’on le redemande ; seuls Liquid Glass et les widgets sont propres à l’app.

## Dépôt

- Aucun agent n’envoie d’écriture au vrai compte Vélo’v, ne se connecte à un vrai compte ni ne teste une version installée sans l’accord explicite du propriétaire pour cette action précise. Les tests simulent le réseau ; `make smoke` ne fait que des lectures publiques.
- Chaque correction d’un défaut arrive avec un test simulé qui échoue avant la correction et passe après.
- Aucun commentaire dans le code, aucun fichier inutile versionné (brouillons, consignes d’agent). Le README est en français et reste utile : ce que fait l’app, comment elle marche, comment la compiler, la tester et l’installer.
- Les identifiants personnels (UDID, identifiant d’équipe Apple, nom, chemins personnels, jetons) restent dans des fichiers locaux ignorés par git, à côté d’un fichier `.example` versionné, comme `Local.xcconfig`.
- Les règles de développement communes au site et à l’app (relecture, publication d’un dépôt, captures) sont dans `docs/development.md` du dépôt web.
