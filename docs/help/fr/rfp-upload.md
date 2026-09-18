---
title: Téléverser un fichier de voies et faire la correspondance
order: 70
hint: Téléversez le .xlsx ou .csv du client, associez ses colonnes à nos champs (la correspondance est mémorisée par client), puis importez.
---

## Partir du modèle

**Download lane template** se trouve sur la liste des projets de l'outil RFP, à côté de **New project**, et de nouveau sous le sélecteur de fichier une fois sur l'écran de téléversement. Vous obtenez une feuille vide dont les en-têtes de colonnes sont ceux que ce téléversement reconnaît : un fichier rempli à partir de ce modèle n'exige donc aucune colonne à associer à la main. La ligne d'exemple nomme des lieux qui ne se résolvent pas, elle est donc ignorée plutôt que transformée en voie.

## Le fichier

Formats acceptés : `.xlsx`, `.xlsm`, `.xls`, `.csv`, jusqu'à 3 Mo et 2 000 lignes par fichier; gardez un projet sous 2 000 voies au total, le tableau n'en affiche pas plus. La première ligne doit contenir les en-têtes. Un second téléversement dans le même projet ajoute les lignes à la suite.

## Correspondance des colonnes

L'outil devine quelle colonne est la ville d'origine, le code postal de destination, le mode, l'équipement, la quantité, etc., et montre un échantillon de chacune. Corrigez avec les listes déroulantes. Associez les deux colonnes de ville, ou les deux colonnes de code postal. La correspondance est mémorisée pour le prochain fichier de ce client.

## Import

**Import lanes** crée une voie par ligne et associe chaque extrémité à un lieu connu. La ligne de résumé dit « imported N, skipped N, unresolved ends N ». Les lignes ignorées n'avaient ni origine ni destination; une ligne à laquelle il manque une extrémité est importée avec cette extrémité Unresolved. Les extrémités non résolues sont des voies dont la ville n'a pas pu être appariée - voir **Extrémités non résolues**.
