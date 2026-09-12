---
title: Téléverser un fichier de voies et faire la correspondance
order: 70
hint: Téléversez le .xlsx ou .csv du client, associez ses colonnes à nos champs (la correspondance est mémorisée par client), puis importez.
---

## Le fichier

Formats acceptés : `.xlsx`, `.xlsm`, `.xls`, `.csv`, jusqu'à 3 Mo et 2 000 voies par projet. La première ligne doit contenir les en-têtes. Un second téléversement dans le même projet ajoute les lignes à la suite.

## Correspondance des colonnes

L'outil devine quelle colonne est la ville d'origine, le code postal de destination, le mode, l'équipement, la quantité, etc., et montre un échantillon de chacune. Corrigez avec les listes déroulantes. L'origine et la destination ont besoin d'au moins une ville ou un code postal chacune. La correspondance est mémorisée pour le prochain fichier de ce client.

## Import

**Import lanes** crée une voie par ligne et associe chaque extrémité à un lieu connu. La ligne de résumé dit « imported N, skipped N, unresolved ends N ». Les lignes ignorées n'avaient pas d'origine ou de destination utilisable; les extrémités non résolues sont des voies dont la ville n'a pas pu être appariée - voir **Extrémités non résolues**.
