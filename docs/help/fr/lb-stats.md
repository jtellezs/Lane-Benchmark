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

## Doublons

La même cotation peut apparaître sur plusieurs chargements. Les lignes identiques (même transporteur, voie, mode, équipement et total) sont comptées une fois; l'en-tête indique combien de doublons ont été retirés.
