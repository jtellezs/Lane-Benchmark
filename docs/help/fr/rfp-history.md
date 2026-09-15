---
title: Charger l'historique
order: 90
hint: Load history lance une recherche Lane Benchmark par voie. Choisissez précision, période, rayon et si les soumissions des autres RFP comptent, puis lisez « N loads + M bids · median ».
---

## Lancer

Réglez **History precision** (City, Province ou Radius), **Lookback (days)**, **Radius** et son **Unit**, et **Include RFP bids**, puis cliquez sur **Load history**. Les voies sont traitées par lots avec une barre de progression; **Stop** arrête après le lot en cours. **Refresh history** relance toutes les voies; **Retry failed** ne relance que celles marquées Failed.

## Repli sur le rayon

Avec la précision City, une voie dont la ville n'a pas d'historique est recherchée à nouveau dans le rayon. Sur une voie qui a une médiane, l'infobulle de la cellule History indique la précision utilisée, par exemple `RADIUS-50KM`.

## Include RFP bids

Activé (par défaut), les soumissions enregistrées sur **d'autres** projets RFP comptent avec les chargements, même après leur date de validité, tant qu'elles sont dans la période. Les soumissions du projet que vous tarifez ne sont jamais comptées - ce sont vos propres données. La cellule History se lit alors « 5 loads + 1 bid · median 5500.00 ». Désactivé, seuls les chargements comptent.

## Lire la cellule

- `12 · median 5800.00` : douze cotations correspondent, la médiane des tarifées est 5 800.
- `3 · no median` : trois correspondent mais aucune n'avait de prix.
- **No match** : rien dans la période à cette précision.
- **Failed** : la recherche a rencontré une erreur.
- **Unresolved** : une extrémité n'est pas un lieu connu.
- **Pending** : pas encore lancé.

Les statistiques n'utilisent que les cotations dans la devise de la voie.

## Milles du trajet et itinéraires de camion

**Load history** remplit aussi la colonne **Miles** de chaque voie traitée, sans interroger Mapbox. Il prend la première source disponible :

1. **History** : la médiane des milles facturés (le champ Distance (Miles) de Revenova, rempli par PC\*Miler) sur les chargements trouvés par la recherche, à la précision utilisée par l'historique. Les soumissions n'ont pas de milles et ne comptent pas.
2. **Truck route** ou **Regular route** : les milles et les heures de route d'un itinéraire déjà enregistré pour les deux lieux de la voie, lors de l'ouverture d'une voie ou d'une recherche Lane Benchmark.
3. **Approx** : la distance à vol d'oiseau entre les deux lieux × 1,2, le rapport mesuré sur un an de chargements facturés.

Une voie reçoit **No coordinates** quand une extrémité n'est pas associée à un lieu ou n'a pas de position sur la carte, et **No route** quand Mapbox n'a trouvé aucune route entre les deux lieux. Une paire de lieux pour laquelle Mapbox n'a trouvé aucune route garde **No route** et aucun mille, plutôt qu'une distance approximative. Les milles facturés ont toujours priorité : ouvrir une voie ne remplace jamais des milles History par ceux d'un itinéraire. Le sens compte : Montréal → Toronto et Toronto → Montréal sont deux itinéraires distincts.
