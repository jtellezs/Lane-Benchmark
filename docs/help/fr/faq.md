---
title: Questions et problèmes
order: 150
hint: No match, Failed, historique ancien, mauvaise devise, onglet absent : les causes habituelles et quoi faire.
---

## « No match » sur une voie

Les extrémités sont résolues mais aucune cotation ni soumission ne correspond dans la période et la précision. Augmentez le rayon (la précision City s'y rabat déjà), allongez la période, ou activez **Include RFP bids**, puis cliquez sur **Refresh history**. Les filtres de mode et d'équipement n'existent que dans Lane Benchmark.

## « Failed » sur une voie

La recherche elle-même a échoué (souvent un délai dépassé sur un très grand rayon). Cliquez sur **Retry failed**; si ça persiste, réduisez le rayon ou la période.

## L'historique semble ancien

L'historique est un instantané pris quand vous avez cliqué sur Load ou Refresh. **Refresh history** en prend un nouveau.

## La médiane est dans la mauvaise devise

Les statistiques n'utilisent que les cotations dans la devise de la voie (celle du projet). Une voie avec des cotations en USD seulement n'a pas de médiane en CAD; enregistrez une soumission ou saisissez le coût.

## Je ne vois pas l'onglet, ou un bouton dit que je manque d'autorisation

Demandez à votre administrateur les ensembles d'autorisations `Lane_Benchmark_User` et `RFP_Tool_User`.

## Quelque chose cloche

Envoyez à votre administrateur le nom du projet, le numéro de la voie et ce que vous attendiez. Les changements à ces outils passent par une demande de tirage (pull request), donc le correctif sera suivi.
