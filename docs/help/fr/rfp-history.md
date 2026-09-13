---
title: Charger l'historique
order: 90
hint: Load history lance une recherche Lane Benchmark par voie. Choisissez précision, période, rayon et si les soumissions des autres RFP comptent, puis lisez « N loads + M bids · median ».
---

## Lancer

Réglez **History precision** (City, Province ou Radius), **Lookback (days)**, **Radius** et son **Unit**, et **Include RFP bids**, puis cliquez sur **Load history**. Les voies sont traitées par lots avec une barre de progression; **Stop** arrête après le lot en cours. **Refresh history** relance toutes les voies; **Retry failed** ne relance que celles marquées Failed.

## Repli sur le rayon

Avec la précision City, une voie dont la ville n'a pas d'historique est recherchée à nouveau dans le rayon. L'infobulle de la cellule History indique la précision utilisée, par exemple `RADIUS-50KM`.

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
