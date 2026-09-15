---
title: Modifier dans le tableau
order: 110
hint: Cliquez sur une cellule Cost, Margin ou Sell et tapez. Entrée enregistre et descend, Tab descend, Maj+Tab remonte, Échap annule.
---

## Cellules modifiables

**Cost**, **Margin** et **Sell** se modifient dans le tableau, comme un chiffrier. Cliquez sur une cellule (la ligne est sélectionnée en même temps), tapez une valeur et appuyez sur :

- **Entrée** ou **Tab** : enregistrer et ouvrir la même cellule sur la ligne suivante.
- **Maj+Tab** : enregistrer et ouvrir la même cellule sur la ligne précédente.
- **Échap** : fermer sans enregistrer.

Cliquer ailleurs enregistre aussi. Un coût saisi ici met la source du coût à Manual; un prix de vente saisi ici est un prix manuel (étiquette **manual**) et la marge le suit.

## Erreurs

Une valeur qui ne peut pas être enregistrée (zéro, négatif, marge au-dessus de 100) affiche un message rouge sous la cellule, qui reste ouverte jusqu'à ce que vous corrigiez ou appuyiez sur Échap.

## Voies identiques

Quand vous tarifez une voie qui a des jumelles dans le même projet (mêmes extrémités, mode et équipement), une barre propose de copier le coût et le prix de vente. **Apply** copie; **Not now** refuse.

## La colonne Miles

La colonne **Miles**, après **History**, n'est pas modifiable : elle affiche la longueur du trajet de la voie en milles, ou en kilomètres quand **km** est choisi dans la barre d'outils. Une petite étiquette indique la provenance de la valeur :

- Sans étiquette : **History**, la médiane des milles facturés sur les chargements trouvés.
- `truck` : un itinéraire de camion Mapbox.
- `route` : un itinéraire routier ordinaire, utilisé quand les limites du camion n'ont pas pu être respectées.
- `approx.` : la distance à vol d'oiseau entre les deux lieux × 1,2.

« — » signifie que la voie n'a pas de distance : survolez-le pour voir la raison (historique pas encore chargé, aucune route trouvée ou pas de coordonnées). **Load history** remplit la colonne. Ouvrir une voie enregistre son itinéraire et remplace une valeur `approx.` par les milles de l'itinéraire quand Mapbox en trouve un; la colonne affiche la nouvelle valeur après le prochain enregistrement de prix, chargement d'historique ou rechargement de la page.

## L'étiquette no rate

Après **Load history**, la cellule **History** affiche l'étiquette **no rate** quand la voie n'a aucun tarif de transporteur avec un prix dans sa devise : la cellule indique **No match**, ou des cotations correspondent mais aucune n'a de prix dans la devise de la voie (pas de médiane). Ouvrez la voie pour voir **Carriers to ask** et **Split-lane options** dans le panneau. **Load history** ne cherche jamais de transporteurs.
