---
title: Lire la tendance de la voie
order: 45
hint: Une ligne mensuelle du tarif médian de la voie, avec une bande du plus bas au plus haut et une fenêtre 6 months/1 year. Les points creux sont des mois avec moins de trois tarifs.
---

## Sous les statistiques

L'encadré **Lane trend** se trouve directement sous **Statistics**, pour la voie déjà cherchée : un axe horizontal de mois, une ligne passant par la médiane de chaque mois, et une bande ombrée entre le tarif le plus bas et le plus haut de ce mois. Pointez un point pour voir son mois, sa médiane et son nombre de tarifs.

## Les points creux

Un mois avec moins de trois tarifs est dessiné comme un point creux et laissé hors de la ligne de médiane : trois tarifs ne suffisent pas pour parler de marché. Son plus bas et son plus haut colorent quand même la bande, et il compte quand même dans le total « X months » sous le graphique : un mois creux est une preuve, seulement pas une preuve sur laquelle la ligne doit s'appuyer.

## La fenêtre

**6 months** et **1 year** choisissent jusqu'où le graphique remonte; **1 year** est la valeur par défaut. Changer de fenêtre redemande le serveur et redessine le graphique.

## Il suit le filtre Market test

Le graphique lit la même voie et le même filtre **Market test** (**Include**, **Exclude** ou **Only**) qui a produit les statistiques au-dessus de lui. Changez le filtre et les deux se redessinent ensemble, pour que la tendance ne décrive jamais un autre ensemble de tarifs que la médiane sous laquelle elle se trouve.

## Quand il n'y a pas assez d'historique

Avec moins de deux mois ayant assez de tarifs à considérer fiables, l'encadré indique qu'il n'y a pas assez d'historique pour montrer une tendance, plutôt que de dessiner un cadre vide.

## « The trend may be incomplete. »

Une voie très active sur une longue fenêtre peut contenir plus de lignes que le graphique ne peut en lire sans risque en un seul appel. Le cas échéant, le graphique est quand même dessiné à partir de ce qu'il a lu, avec cette note en dessous — réduisez la fenêtre pour voir le reste.

## Le mois dans lequel un tarif se place

Chaque tarif est placé sur l'axe selon le jour où il a été enregistré, et non selon le jour où la marchandise doit partir. Une cotation demandée aujourd'hui renseigne sur le marché d'aujourd'hui, que le camion roule la semaine prochaine ou le mois prochain. La fenêtre choisie compte ce même jour : tout tarif que le graphique trouve est donc un tarif qu'il peut placer — rien n'est écarté en silence, et le mois courant est aussi complet que les plus anciens.

## Les tarifs que le graphique laisse de côté

Une ligne sans tarif, et une ligne dont le total transporteur est zéro, ne sont pas des prix fixés par un marché : le graphique les laisse de côté — exactement comme le font déjà la médiane, le plus bas et le plus haut dans **Statistics** au-dessus. Le nombre de tarifs d'un mois est donc le nombre de tarifs non nuls, qui peut être inférieur au nombre de lignes que le tableau des résultats montre pour ce même mois.
