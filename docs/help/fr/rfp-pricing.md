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
- **Split** : le total d'une option de voie fractionnée, rempli par **Use as cost** (voir plus bas). Ce n'est pas un choix offert : il n'apparaît que lorsqu'il est la source de la voie, après **Use as cost** ou sur une voie enregistrée ainsi, et choisir une autre source le remplace.

## Marge ou prix de vente

Saisissez un **Margin %** et le prix de vente suit (« Sell follows the margin »), ou saisissez un **Sell** et la marge suit (« Margin follows the sell »). Un prix de vente saisi est conservé quand le coût change plus tard; le tableau lui met l'étiquette **manual**. Saisissez un **Margin %** pour revenir au mode marge; le prix de vente est alors recalculé à partir de la marge.

## Enregistrer

**Save price** écrit le coût, la marge et le prix de vente sur la voie et la marque **Priced**. **Add carrier rate** enregistre une nouvelle soumission pour cette voie; elle apparaît ensuite dans la liste des soumissions du panneau et dans le choix **Bid**. Pour l'utiliser, passez **Cost source** à **Bid**, choisissez-la dans la liste **Bid**, puis cliquez sur **Save price**.

## Milles du trajet et itinéraires de camion

Sous le titre de la voie, le panneau affiche ses milles et leur source (voir **Charger l'historique**). À côté des prix, **Cost per mile** et **Sell per mile** divisent le coût et le prix de vente par ces milles et suivent ce que vous saisissez.

Les boutons **mi** et **km** de la barre d'outils, à côté de **Include RFP bids**, font passer le tableau, le panneau et la légende de la carte des milles aux kilomètres; les valeurs par mille deviennent des valeurs par kilomètre. Le choix est retenu dans ce navigateur, et Lane Benchmark s'ouvre avec la même unité.

À l'ouverture du panneau, l'itinéraire s'affiche sur la carte : l'épingle A au point de départ, l'épingle B à la destination, l'itinéraire principal en trait bleu épais et jusqu'à deux variantes en orange et en gris. La légende donne la distance et les heures de route de chaque itinéraire. Un **Truck route** respecte les limites de camion définies dans Truck Routing Setting (par défaut 4,11 m de haut, 2,6 m de large, 36,29 t); quand Mapbox ne peut pas les respecter, le panneau affiche plutôt un itinéraire routier ordinaire, sous le titre « Regular route — truck limits could not be met ». Mapbox n'a pas d'option pour les matières dangereuses : une voie hazmat reçoit le même itinéraire que les autres.

L'itinéraire est demandé une seule fois à Mapbox par paire de lieux, puis enregistré; rouvrir la voie le réutilise. **Refresh route** interroge Mapbox de nouveau et remplace l'itinéraire enregistré. Quand les milles de la voie ne viennent pas de History, les milles et les heures de l'itinéraire sont écrits sur la voie (Truck route ou Regular route); des milles History ne sont jamais remplacés. Si Mapbox ne répond pas, le panneau indique « The truck route is not available right now. » et la voie garde ses milles. Quand Mapbox ne trouve aucune route, même sans limites de camion (de l'autre côté d'un plan d'eau sans traversier, par exemple), la voie affiche **No route**.

Pendant un **Load history** ou une action en lot, le panneau met sa demande d'itinéraire en attente : la carte affiche son indicateur de chargement, **Refresh route** attend, et l'itinéraire est demandé à la fin du traitement.

L'export Excel contient, pour chaque voie, les colonnes Miles, Km, Miles source, Route hours, Cost per mile et Sell per mile.

## Résultats

Sous le formulaire, les lignes d'historique de la voie sont listées exactement comme Lane Benchmark les montre, pour voir quelles cotations ont fait la médiane.

## Carriers to ask

Quand les résultats d'historique de la voie n'ont aucun tarif de transporteur avec un prix dans la devise de la voie, le panneau affiche **Carriers to ask** sous ces résultats : les transporteurs qui ont déjà coté ou transporté la voie, par leur nom seulement, jamais avec un montant. L'en-tête se lit « No carrier rate on this lane in USD. These carriers quoted or moved it before; amounts are not shown. » Les deux extrémités doivent être associées à des lieux, et l'encadré se charge à l'ouverture de la voie, jamais pendant **Load history** (le tableau affiche plutôt l'étiquette **no rate**; voir **Modifier dans le tableau**). Les deux étapes (la même voie sur 3 ans, puis les 10 principaux transporteurs de la voie de province à province ou d'État à État), le badge **Blacklisted**, le lien vers le compte et **Retry** fonctionnent comme dans Lane Benchmark (voir **Lire les statistiques**).

## Split-lane options

Sous les résultats d'historique (après **Carriers to ask** quand il est affiché), cliquez sur **Split-lane options** pour voir l'historique fractionné de la voie, ou des estimations par un point de transfert, comme l'explique **Lire les statistiques**. L'encadré s'ouvre dans la devise de la voie, et **Direct median** est la médiane des résultats d'historique du panneau dans la devise de l'encadré.

## Use as cost

Tant que l'encadré affiche la devise de la voie, chaque option qui a un total offre **Use as cost**. Une option d'historique utilise sa médiane du total par envoi; une estimation utilise son **Estimate total** : saisissez donc d'abord son **Handoff cost** (0 est accepté). **Use as cost** inscrit ce total dans **Cost**, met **Cost source** à **Split** et retire la soumission choisie; la marge et le prix de vente suivent comme pour tout autre coût. Rien n'est enregistré avant que vous cliquiez sur **Save price**. Quand vous passez l'encadré à l'autre devise, le bouton est remplacé par « Switch to USD to use a split cost. » (sur une voie en USD; « Switch to CAD… » sur une voie en CAD). La barre des voies identiques copie un coût Split comme n'importe quel autre coût.
