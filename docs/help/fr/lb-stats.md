---
title: Lire les statistiques
order: 40
hint: Une boîte par devise : min, médiane, moyenne, max sur les cotations tarifées, et un prix de vente suggéré à partir de la marge saisie.
---

## Une boîte par devise

Les statistiques ne sont jamais mélangées entre devises. Chaque boîte indique combien de cotations correspondent et combien avaient un prix, puis le minimum, la médiane, la moyenne et le maximum des cotations tarifées.

## Marge et prix de vente suggéré

Saisissez un pourcentage de marge (15 par défaut) ou cliquez sur **15%** / **20%**. La boîte affiche **Sell (median)** et **Sell (average)** : le coût médian ou moyen plus cette marge. Ce sont des suggestions, pas des prix; rien n'est enregistré ici.

## Milles du trajet et itinéraires de camion

L'encadré **Statistics** indique aussi la longueur du trajet :

- **Trip: 1,234 mi · median of 12 loads** : la médiane des milles facturés sur les chargements trouvés. Les soumissions n'ont pas de milles et ne comptent pas.
- **Truck route: 1,260 mi · 21.5 h** : l'itinéraire de camion Mapbox entre les deux lieux, avec ses heures de route. **Regular route** signifie plutôt que les limites du camion n'ont pas pu être respectées : un itinéraire routier ordinaire est affiché.

L'itinéraire de camion relie toujours les deux lieux choisis, même après une recherche par **Province / état** ou par **Préfixe postal** : **Truck route** donne alors la distance de ville à ville, tandis que **Trip** couvre tous les chargements trouvés par la recherche plus large.

Chaque boîte de devise ajoute **Rate per mile (median)** : la médiane du total de chaque cotation tarifée divisé par les milles de son chargement, dans la devise de la boîte.

Après une recherche avec une origine et une destination, la carte trace l'itinéraire de camion (épingles A et B, l'itinéraire principal et jusqu'à deux variantes, une ligne de légende par itinéraire) à la place de l'aperçu simple; une recherche par rayon garde l'aperçu de son rayon sous l'itinéraire, et sans itinéraire, l'aperçu reste. L'itinéraire est demandé une seule fois à Mapbox par paire de lieux, puis enregistré : la recherche suivante sur la même voie le réutilise, et **Refresh route** le redemande. Le tableau des résultats a une colonne **Miles** (les soumissions affichent « — »), et l'export CSV la contient.

Les boutons **mi** et **km** dans l'en-tête de l'encadré changent toutes les distances de la page, taux par mille compris. Le choix est retenu dans ce navigateur, et l'onglet RFP Tool l'utilise aussi.

## Carriers to ask

Quand une recherche ne trouve aucun tarif de transporteur avec un prix dans la devise filtrée (dans n'importe quelle devise quand **Currency** est à All), et que les deux extrémités sont des lieux de la liste, l'encadré **Carriers to ask** apparaît sous **Statistics**, au-dessus de la carte. Il nomme des transporteurs qui connaissent la voie, pour que vous sachiez à qui demander un prix. Il n'affiche jamais de montant.

L'en-tête se lit « No carrier rate on this lane in CAD. These carriers quoted or moved it before; amounts are not shown. » (sans « in CAD » quand aucune devise n'est filtrée). Chaque transporteur affiche :

- son nom, avec un lien vers le compte du transporteur quand vous pouvez ouvrir ce compte;
- **3 moved · 5 quoted · last seen 2026-07-08** : les chargements qu'il a transportés (cotations acceptées et tronçons d'envois fractionnés) et ceux qu'il a cotés;
- où il a été trouvé : **Quote**, **Split leg** ou les deux;
- le badge **Blacklisted** quand le compte du transporteur est sur la liste noire. Ces transporteurs restent dans la liste pour que vous les reconnaissiez; ne leur demandez pas de prix.

L'encadré cherche d'abord sur la même voie, sur les 3 dernières années, avec la précision de votre recherche à chaque extrémité (une extrémité par rayon utilise sa ville) et ses filtres de mode, d'équipement et de matières dangereuses; la période, la devise, le statut des cotations et la source ne s'appliquent pas. Si personne n'est trouvé, il affiche les 10 principaux transporteurs de la voie de province à province (ou d'État à État) sur la dernière année, classés selon les chargements transportés : « No carrier on this exact lane. Top carriers on QC to ON over the last year. » Cette deuxième étape est sautée quand les deux extrémités ont été cherchées par province ou par État. Si aucune étape ne trouve de transporteur, l'encadré indique « No carrier found on this lane or on its state or province lane. » Les comptes de transporteurs intersociétés de Trans-Pro ne sont jamais listés.

« The list may be incomplete. » signifie que l'encadré s'est arrêté plus tôt pour rester dans les limites de Salesforce. Si l'encadré ne se charge pas, cliquez sur **Retry**.

## Split-lane options

Au bas de la page, sous les résultats, **Split-lane options** montre comment la voie a été transportée en deux tronçons ou plus par des transporteurs différents. Rien n'est cherché avant que vous cliquiez sur le bouton : les résultats directs passent toujours en premier. Le bouton est masqué quand une extrémité n'est pas un lieu de la liste.

- **History** : les envois fractionnés sur la voie des 12 derniers mois (selon la date du chargement client), regroupés par point de transfert, du plus grand nombre d'envois au plus petit : « Via Laredo, TX · SFMN Park ITC Laredo yard · 34 shipments ». Chaque ligne de tronçon donne la voie du tronçon, ses transporteurs avec le nombre de tronçons que chacun a transportés, et le coût médian du tronçon : « Leg 1 General Escobedo, NL → Laredo, TX · Q Transportes (18), Fletes Mex (9) · median 1,248 CAD ». « Total per shipment, median 6,453 CAD (31 shipments) » est la médiane du total des tronçons de chaque envoi, calculée sur les envois dont tous les tronçons ont un coût. Un tronçon sans coût n'affiche que les noms des transporteurs. Les envois dont un tronçon est annulé, ou confié à un transporteur intersociétés, sont exclus.
- **Estimate** : quand la voie n'a aucun historique d'envoi fractionné, l'encadré essaie les points de transfert actifs de la liste gérée par l'administrateur (aujourd'hui Laredo TX, San Diego CA et Calexico CA) qui n'ajoutent pas plus d'environ 10 % de distance, jusqu'à 3, le plus proche en premier : « Estimate via Laredo, TX · +6 % distance ». Chaque tronçon affiche ses transporteurs et le coût médian des chargements transportés sur ce tronçon pendant la dernière année. Saisissez les frais de cour, de transbordement ou de cross-dock dans **Handoff cost** : **Estimate total** est la médiane du tronçon 1 + la médiane du tronçon 2 + ces frais. Un tronçon sans coût ne donne pas de total. Sans historique ni point de transfert assez proche, l'encadré indique « No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate. »

Les boutons **CAD** et **USD** de l'en-tête de l'encadré changent tous ses montants. L'encadré s'ouvre dans la devise filtrée, ou en CAD. Les coûts des tronçons sont enregistrés en CAD; en USD, le coût de chaque chargement est converti au taux de change USD de Salesforce à la date de ce chargement, et la note « Converted at the USD rate of 2026-08-11. » donne la date de début du taux le plus récent utilisé (« No USD exchange rate is available. » quand Salesforce n'en a aucun). **Direct median 5,800 CAD** reprend la médiane des **Statistics** de votre recherche dans la devise de l'encadré, pour comparer; elle est masquée quand la recherche n'a pas de médiane dans cette devise. Un transporteur de tronçon sur la liste noire porte le badge **Blacklisted**. « The list may be incomplete. » et **Retry** fonctionnent comme dans **Carriers to ask**. Dans Lane Benchmark, l'encadré sert seulement à vous informer; pour utiliser un coût fractionné, tarifez la voie dans l'onglet RFP Tool.

## Doublons

La même cotation peut apparaître sur plusieurs chargements. Les lignes identiques (même transporteur, voie, mode, équipement et total) sont comptées une fois; l'en-tête indique combien de doublons ont été retirés.
