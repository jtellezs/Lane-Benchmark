---
title: Lire la tendance de la voie
order: 45
hint: Une ligne mensuelle du tarif médian de la voie, avec une bande du plus bas au plus haut et une fenêtre 6 months/1 year/3 years. Les points creux sont des mois avec moins de trois tarifs.
---

## Sous les statistiques

L'encadré **Lane trend** se trouve directement sous **Statistics**, pour la voie déjà cherchée : un axe horizontal de mois, une ligne passant par la médiane de chaque mois, et une bande ombrée entre le tarif le plus bas et le plus haut de ce mois. Pointez un point pour voir son mois, sa médiane et son nombre de tarifs.

## Les points creux

Un mois avec moins de trois tarifs est dessiné comme un point creux et laissé hors de la ligne de médiane : trois tarifs ne suffisent pas pour parler de marché. Son plus bas et son plus haut colorent quand même la bande, et il compte quand même dans le total « X months » sous le graphique : un mois creux est une preuve, seulement pas une preuve sur laquelle la ligne doit s'appuyer.

## La fenêtre

**6 months**, **1 year** et **3 years** choisissent jusqu'où le graphique remonte; **1 year** est la valeur par défaut. Changer de fenêtre redemande le serveur et redessine le graphique.

## Il suit le filtre Market test

Le graphique lit la même voie et le même filtre **Market test** (**Include**, **Exclude** ou **Only**) qui a produit les statistiques au-dessus de lui. Changez le filtre et les deux se redessinent ensemble, pour que la tendance ne décrive jamais un autre ensemble de tarifs que la médiane sous laquelle elle se trouve.

## Quand il n'y a pas assez d'historique

Avec moins de deux mois ayant assez de tarifs à considérer fiables, l'encadré indique qu'il n'y a pas assez d'historique pour montrer une tendance, plutôt que de dessiner un cadre vide.

## « The trend may be incomplete. »

Une voie très active sur une longue fenêtre peut contenir plus de lignes que le graphique ne peut en lire sans risque en un seul appel. Le cas échéant, le graphique est quand même dessiné à partir de ce qu'il a lu, avec cette note en dessous — réduisez la fenêtre pour voir le reste.

## Des tarifs comptés hors de la fenêtre

Le graphique retient les tarifs créés dans la fenêtre choisie, puis place chacun sur l'axe selon le jour de la cotation ou le jour à partir duquel il est valide — une date différente. Un tarif créé dans la fenêtre peut donc, selon cette seconde date, se retrouver daté dans un mois hors de la fenêtre. Plutôt que de l'écarter sans le dire, l'encadré compte combien de tarifs ont eu ce sort et montre ce nombre sous le graphique.
