---
title: Lire la tendance de la voie
order: 45
hint: Neuf fenêtres d'une semaine à trois ans, chacune regroupée par jour, semaine ou mois selon sa durée. Les points creux marquent les périodes avec trop peu de tarifs pour leur taille.
---

## Sous les statistiques

L'encadré **Lane trend** se trouve directement sous **Statistics**, pour la voie déjà cherchée : un axe horizontal de périodes, une ligne passant par la médiane de chaque période, et une bande ombrée entre le tarif le plus bas et le plus haut de cette période. Pointez un point pour voir sa période, sa médiane et son nombre de tarifs.

## La fenêtre

**1 week**, **2 weeks**, **1 month**, **2 months**, **3 months**, **6 months**, **1 year**, **2 years** et **3 years** choisissent jusqu'où le graphique remonte; **1 year** est la valeur par défaut. Changer de fenêtre redemande le serveur et redessine le graphique.

## Comment le graphique regroupe les tarifs

La taille d'une période suit la fenêtre choisie, ce n'est pas quelque chose que vous réglez à part : **1 week**, **2 weeks** et **1 month** regroupent les tarifs par jour; **2 months** et **3 months** les regroupent par semaine; **6 months** et au-delà les regroupent par mois. C'est Apex qui décide laquelle à partir de la fenêtre, si bien que l'axe, la règle des points creux ci-dessous et la phrase de résumé s'accordent toujours sur le type de période dont ils parlent.

## Les points creux

Un point creux marque une période avec trop peu de tarifs pour sa taille — trois pour un mois, deux pour une semaine — et il est laissé hors de la ligne de médiane. Son plus bas et son plus haut colorent quand même la bande, et il compte quand même dans le total sous le graphique : une période creuse est une preuve, seulement pas une preuve sur laquelle la ligne doit s'appuyer. Aux périodes d'un jour, rien n'est jamais marqué creux : une période n'existe que si elle contient au moins un tarif, et un seul tarif suffit pour un jour.

## Sur une voie peu active

Une période n'apparaît que si elle contient un tarif, donc sur une voie peu active récemment, les fenêtres les plus courtes — **1 week** et **2 weeks** surtout — peuvent montrer très peu de points, parfois aucun. C'est la fenêtre qui fait exactement ce qu'elle doit faire : montrer ce qui existe réellement. Une fenêtre plus longue se remplit en général davantage.

## Il suit le filtre Market test

Le graphique lit la même voie et le même filtre **Market test** (**Include**, **Exclude** ou **Only**) qui a produit les statistiques au-dessus de lui. Changez le filtre et les deux se redessinent ensemble, pour que la tendance ne décrive jamais un autre ensemble de tarifs que la médiane sous laquelle elle se trouve.

## Quand il n'y a pas assez d'historique

Avec moins de deux périodes ayant assez de tarifs à considérer fiables, l'encadré indique qu'il n'y a pas assez d'historique pour montrer une tendance, plutôt que de dessiner un cadre vide.

## « The trend may be incomplete. »

Une voie très active sur une longue fenêtre peut contenir plus de lignes que le graphique ne peut en lire sans risque en un seul appel. Le cas échéant, le graphique est quand même dessiné à partir de ce qu'il a lu, avec cette note en dessous — réduisez la fenêtre pour voir le reste.

## Dans quelle période un tarif se place

Chaque tarif est placé sur l'axe selon le jour où il a été enregistré, et non selon le jour où la marchandise doit partir. Une cotation demandée aujourd'hui renseigne sur le marché d'aujourd'hui, que le camion roule la semaine prochaine ou le mois prochain. La fenêtre choisie compte ce même jour : tout tarif que le graphique trouve est donc un tarif qu'il peut placer — rien n'est écarté en silence, et la période la plus récente est aussi complète que les plus anciennes.

## Les tarifs que le graphique laisse de côté

Une ligne sans tarif, et une ligne dont le total transporteur est zéro, ne sont pas des prix fixés par un marché : le graphique les laisse de côté — exactement comme le font déjà la médiane, le plus bas et le plus haut dans **Statistics** au-dessus. Le nombre de tarifs d'une période est donc le nombre de tarifs non nuls, qui peut être inférieur au nombre de lignes que le tableau des résultats montre pour cette même période.
