# Choix de conception

Ce document rassemble les règles que le code respecte et les raisons de quelques choix moins évidents. L’app suit la [version web](https://github.com/DailyXplorer/velov-compagnon) : mêmes textes, mêmes règles, mêmes hypothèses sur l’API.

## Écritures

Toute requête qui modifie le compte part exactement une fois par confirmation de l’utilisateur. Elle ne passe jamais par le client de lecture, qui sait réessayer, et n’est jamais renvoyée, quelle que soit la réponse. Pour un déverrouillage, la borne a pu s’ouvrir sans que la réponse arrive ; pour une réservation, des points ont pu être débités.

Un échec est classé comme refus certain ou comme résultat incertain, à la manière de `isUncertain` côté web. Sont des refus certains les erreurs détectées sur le téléphone avant tout envoi (codes `local.`), les erreurs 4xx accompagnées d’un code et les états d’échec explicites du déverrouillage. Tout le reste est incertain : absence de réponse, délai dépassé, erreur 5xx ou page de passerelle, réponse 2xx illisible, erreur 4xx sans code, et l’état `TIME_OUT` d’un déverrouillage. Après un résultat incertain, la feuille ne propose plus que « Fermer ». Le succès d’une écriture se lit dans `transactionState`, jamais dans le seul statut HTTP.

La notation d’un vélo envoie une note par appui sur « Envoyer » : les étoiles sont le choix et le bouton vaut confirmation. Le téléchargement d’un justificatif est un POST qui ne fait que lire ; il part donc sans confirmation, une requête par appui.

Avant une réservation, l’app relit les identifiants de la station et du vélo, que le corps de la requête exige. Avant « 15 minutes de plus », elle revérifie que la station choisie est pleine et retrouve l’abonnement qui loue réellement le vélo. Avant un changement du renouvellement automatique, elle vérifie que Vélo’v l’autorise, puis relit l’état réel ; si cette relecture échoue, l’écriture n’est pas répétée et l’état reste inconnu. Un corps invalide ne quitte jamais le téléphone.

## Codes d’invitation

Le code obtenu contre des points est la seule preuve du débit. L’app vérifie donc que le stockage local est lisible et inscriptible avant le débit, puis écrit le code sur le téléphone avant toute autre chose. Un stockage illisible n’est jamais écrasé, car un ancien code peut encore s’y trouver. Les codes sont rangés dans Application Support sous une clé qui ne contient pas l’adresse du compte. Un débit qui a pu avoir lieu n’est jamais reproposé depuis la même feuille.

## Lectures

Les lectures sont réessayées seulement sur les erreurs 502, 503 et 504, au plus trois fois et 8 secondes chacune, jamais après un délai dépassé : la passerelle de Cyclocity renvoie un 502 nu à environ une requête sur cinq. Une seule lecture tourne à la fois pour une même clé, et un échec n’est jamais mis en cache. La liste des stations sert la dernière version connue en cas de panne. Les vélos d’une station sont gardés 15 secondes pour la liste, mais une réservation les relit toujours. L’historique complet, utilisé par les statistiques, est lu page par page et gardé 10 minutes.

Les réponses sont lues champ par champ : un champ obligatoire mal formé fait échouer la lecture, un champ facultatif mal formé devient simplement absent, et un vélo mal formé est ignoré sans perdre la station.

## Connexion et session

La connexion est une seule tentative ; un refus est affiché avec le message de Vélo’v et n’est jamais réessayé. Rien ne permet d’affirmer que Vélo’v limite un compte à un seul appareil : l’app n’en fait pas l’hypothèse et ne déconnecte jamais les autres sessions.

L’identifiant d’appareil est créé une fois, gardé dans le trousseau et conservé après une déconnexion, car un nouvel identifiant ressemblerait à un autre téléphone. Les jetons sont dans le trousseau, lisibles après le premier déverrouillage, jamais synchronisés. Une seule actualisation de session tourne à la fois, puisqu’un jeton d’actualisation ne sert qu’une fois, et seul un refus de ce jeton met fin à la session. Les identifiants ne sont envoyés qu’aux pages du domaine d’authentification de Vélo’v, et le jeton d’identité est vérifié (signature RS256, émetteur, audience, nonce, expiration).

## Fin de trajet

Pendant un trajet, l’app interroge les trajets en cours toutes les 20 secondes, seulement au premier plan, une requête à la fois et pendant 3 heures au plus. Elle vérifie aussitôt en revenant au premier plan. Il n’y a ni tâche de fond ni notification, car iOS ne maintiendrait pas une interrogation aussi fréquente en arrière-plan. Après un déverrouillage, l’app attend jusqu’à 2 minutes que le trajet apparaisse.

Quand le vélo est raccroché, l’app relit le compte pour le prix et les réservations, ce qui termine toute Activité en direct restante. « Plus tard », comme toute autre façon de fermer la fiche « Trajet terminé », est mémorisé par trajet ; au lancement, l’app propose une seule fois le dernier trajet encore notable. La notation reste ouverte 3 heures après la fin du trajet.

## Activité en direct

L’Activité en direct de la réservation est démarrée et arrêtée par l’app seule : aucun jeton push n’est demandé et il n’y a pas d’App Group. Si iOS la refuse, rien d’autre n’en dépend et le bandeau de l’app reste affiché. Le widget utilise les mêmes icônes et les deux mêmes polices que l’app. Les captures de l’écran verrouillé et de la Dynamic Island dessinent les vues du widget sur une maquette, car un script ne peut pas verrouiller le simulateur.

L’Activité « trajet en cours » démarre après un déverrouillage réussi, ou quand l’app ouverte voit un trajet en cours sans activité affichée, et remplace alors celle de la réservation. Le temps écoulé avance seul grâce à Text(timerInterval:), sans mise à jour quand l’app est fermée. Elle se termine quand l’app voit le trajet fini et garde la durée finale 5 minutes ; une réponse vide dans les 2 minutes qui suivent le déverrouillage ne la termine pas. Elle devient périmée 4 heures après le départ et est retirée au lancement suivant. Les minutes gratuites de l’abonnement ne sont affichées nulle part : aucun champ chiffré lu par l’app ne les donne.

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

Chaque onglet est créé à sa première visite puis gardé en vie, masqué quand un autre est affiché. Les cartes ne sont donc jamais reconstruites, et un changement d’onglet ramène simplement la page quittée en haut. Le classement des stations est calculé hors du fil principal, seulement quand la liste, la recherche, le filtre, les favoris ou la position changent. La pastille rouge de la barre d’onglets glisse vers l’onglet choisi avec un léger rebond et un retour haptique, ou apparaît en fondu si « Réduire les animations » est activé.
