---
title: À quoi servent ces outils
order: 10
hint: Lane Benchmark montre ce qu'une voie a coûté récemment; l'outil RFP tarifie la liste de voies d'un client à partir de cet historique et des soumissions des transporteurs.
---

## Deux outils, une seule source

**Lane Benchmark** répond à « combien cette voie a-t-elle coûté récemment? ». Vous choisissez une origine, une destination, la précision de la correspondance et la période. L'outil renvoie toutes les cotations de transporteurs correspondantes tirées des chargements Revenova, plus les soumissions enregistrées dans l'outil RFP, avec des statistiques par devise et un prix de vente suggéré.

**L'outil RFP** tarifie une demande complète d'un client. Vous téléversez le fichier de voies du client, l'outil associe les extrémités de chaque voie à des lieux connus, charge le même historique voie par voie, et vous laisse fixer un coût, une marge et un prix de vente pour chaque voie - une à la fois, directement dans le tableau, ou en lot - puis exporter la liste tarifée vers Excel.

## D'où viennent les chiffres

- **Chargements** : cotations de transporteurs sur des chargements Revenova, appariées par origine et destination.
- **Soumissions** : tarifs de transporteurs enregistrés dans l'outil RFP sans chargement (une cotation reçue pour un appel d'offres). Elles portent l'étiquette **Bid** et une date d'expiration.

Les deux sources sont limitées par la fenêtre de recherche (jours depuis la création de la cotation ou de la soumission).

## À qui s'adresser

L'accès est donné par les ensembles d'autorisations `Lane_Benchmark_User` et `RFP_Tool_User`. Si un onglet manque ou qu'un bouton est grisé avec un message d'autorisation, demandez à votre administrateur Salesforce.
