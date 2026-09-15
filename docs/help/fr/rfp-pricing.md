---
title: Tarifer une voie
order: 100
hint: Choisissez une source de coût (une soumission, la médiane de l'historique ou un montant saisi), fixez une marge ou un prix de vente, puis Save price.
---

## Le panneau

Cliquez sur une voie pour ouvrir son panneau à droite. Il reste visible pendant que vous faites défiler le tableau.

## Source du coût

- **Bid** : choisissez un des tarifs de transporteur enregistrés pour cette voie. Le coût est le tarif de la soumission.
- **History median** : la médiane du dernier chargement d'historique.
- **Manual** : saisissez le coût vous-même.

## Marge ou prix de vente

Saisissez un **Margin %** et le prix de vente suit (« Sell follows the margin »), ou saisissez un **Sell** et la marge suit (« Margin follows the sell »). Un prix de vente saisi est conservé quand le coût change plus tard; le tableau lui met l'étiquette **manual**. Saisissez un **Margin %** pour revenir au mode marge; le prix de vente est alors recalculé à partir de la marge.

## Enregistrer

**Save price** écrit le coût, la marge et le prix de vente sur la voie et la marque **Priced**. **Add carrier rate** enregistre une nouvelle soumission pour cette voie; elle apparaît ensuite dans la liste des soumissions du panneau et dans le choix **Bid**. Pour l'utiliser, passez **Cost source** à **Bid**, choisissez-la dans la liste **Bid**, puis cliquez sur **Save price**.

## Milles du trajet et itinéraires de camion

Sous le titre de la voie, le panneau affiche ses milles et leur source (voir **Charger l'historique**). À côté des prix, **Cost per mile** et **Sell per mile** divisent le coût et le prix de vente par ces milles et suivent ce que vous tapez.

Les boutons **mi** et **km** de la barre d'outils, à côté de **Include RFP bids**, font passer le tableau, le panneau et la légende de la carte des milles aux kilomètres; les valeurs par mille deviennent des valeurs par kilomètre. Le choix est retenu dans ce navigateur, et Lane Benchmark s'ouvre avec la même unité.

À l'ouverture du panneau, l'itinéraire s'affiche sur la carte : l'épingle A au point de départ, l'épingle B à la destination, l'itinéraire principal en trait bleu épais et jusqu'à deux variantes en orange et en gris. La légende donne la distance et les heures de route de chaque itinéraire. Un **Truck route** respecte les limites du camion du Truck Routing Setting (par défaut 4,11 m de haut, 2,6 m de large, 36,29 t); quand Mapbox ne peut pas les respecter, le panneau affiche plutôt un itinéraire routier ordinaire, sous le titre « Regular route — truck limits could not be met ». Mapbox n'a pas d'option pour les matières dangereuses : une voie hazmat reçoit le même itinéraire que les autres.

L'itinéraire est demandé une seule fois à Mapbox par paire de lieux, puis enregistré; rouvrir la voie le réutilise. **Refresh route** interroge Mapbox de nouveau et remplace l'itinéraire enregistré. Quand les milles de la voie ne viennent pas de History, les milles et les heures de l'itinéraire sont écrits sur la voie (Truck route ou Regular route); des milles History ne sont jamais remplacés. Si Mapbox ne répond pas, le panneau indique « The truck route is not available right now. » et la voie garde ses milles. Quand Mapbox ne trouve aucune route, même sans limites de camion (de l'autre côté d'un plan d'eau sans traversier, par exemple), la voie affiche **No route**.

L'export Excel contient, pour chaque voie, les colonnes Miles, Km, Miles source, Route hours, Cost per mile et Sell per mile.

## Résultats

Sous le formulaire, les lignes d'historique de la voie sont listées exactement comme Lane Benchmark les montre, pour voir quelles cotations ont fait la médiane.
