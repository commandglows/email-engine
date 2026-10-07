---
artifact: implementation_spec
metadata_schema_version: "1.0"
artifact_version: "1.0.0"
project: email-sidebar-app
created: "2026-10-07"
updated: "2026-10-07"
status: reviewed
source_skill: sg-development
scope: gmail-support-rich-email
owner: Diane
confidence: high
risk_level: high
security_impact: yes
docs_impact: yes
linked_systems: [app, newsletter_studio_flutter, source_sidebar_flutter, CommandGlows, Gmail, Mutant Mail]
depends_on: [shipglows_data/technical/design-system-authority.md]
supersedes: []
evidence:
  - "27 tests serveur support et TypeScript ciblé passent sous Doppler commandglows/dev."
  - "20 tests app, 20 tests newsletter et 26 tests sidebar passent."
  - "Parcours intégré inspecté à 1500x1600 et 390x844 avec données fictives."
next_review: "2026-11-07"
next_step: "Vérifier le parcours sur une boîte Gmail autorisée après déploiement coordonné."
---

# Support email enrichi

Objectif : pièces jointes entrantes et sortantes, réponse à tous, lecture HTML
enrichie et recherche exhaustive côté serveur dans les boîtes Gmail autorisées.

## Contrat prêt

- Le serveur CommandGlows garde l'autorité admin, les tokens Gmail et les
  destinataires. Aucun destinataire arbitraire fourni par Flutter.
- Réponse simple et réponse à tous montrent les destinataires avant confirmation.
  Les participants sans routage autorisé bloquent la réponse à tous.
- Fichiers : téléchargement authentifié ; maximum 10 fichiers et 3 Mio au total
  pour une réponse. Validation des tailles et du MIME avant toute réservation.
- HTML assaini côté serveur, affichage natif Flutter sans exécution de scripts,
  sans images externes ; ouverture des liens HTTPS seulement après action humaine.
- Recherche Gmail serveur sur toute la boîte, résultats paginés ; distinction
  explicite avec le filtre local de la liste commune.
- Les résultats incertains restent verrouillés durablement ; aucun renvoi automatique.

## Execution Batches

1. Backend : `commandglows_site/src/lib/email/support`, tests support et
   documentation `gmail-support-api.md`. Propriétaire : agent backend.
2. Intégration : dépôt email-engine, modèles, adapters, lecteur et tests Flutter.
   Propriétaire : agent principal, également responsable de l'intégration finale.

## Vérification

Tests serveur : destinataires, MIME multipart, téléchargements scindés par
boîte/message, HTML hostile, recherche au-delà de l'INBOX et pagination.
Tests Flutter : mapping API, contenu enrichi, sélection/suppression des fichiers,
confirmation de réponse à tous et recherche paginée. Analyse statique des surfaces
modifiées. Les contrôles locaux ne prouvent pas OAuth ou réception réelle.

## Skill Run History

- 2026-10-07 : `$sg-docs update` aligne le contrat Gmail backend, la navigation
  technique CommandGlows et la documentation opérateur de l'app sur les preuves
  disponibles. Métadonnées et cohérence locale vérifiées.

## Current Chantier Flow

- Documentation des deux dépôts alignée sur les capacités et contrôles locaux.
- Étape suivante : session hébergée avec boîte autorisée, OAuth Gmail, vérification
  du routage Mutant Mail, puis preuve de réception réelle avant activation.

## État

2026-10-07 : implémentation locale et vérification terminées ; pas d'envoi ni déploiement.

## Preuves et limites

- Pièces jointes : tests MIME multipart, limite 3 Mio, fichiers inline Gmail,
  autorisation du téléchargement, ajout/retrait et téléchargement dans l'interface.
- Réponse à tous : destinataires dérivés serveur, participants non vérifiés bloqués,
  confirmation dans l'interface et verrou durable couvrant mode et fichiers.
- HTML : tests de contenus hostiles, rendu enrichi et bascule texte seul ; texte
  de secours pour HTML seul, aucune ressource externe automatique.
- Recherche : Gmail metadata sur toute la boîte, curseurs conservant la requête,
  test intégré de deux pages et test serveur de conversation volumineuse.
- App : analyse sans problème. Serveur : TypeScript ciblé passe ; contrôle Astro
  global sans erreur ni avertissement, avec un hint préexistant.
- Packages : 20 tests newsletter et 26 tests sidebar passent. Le contrôle de
  dérive visuelle relève `Colors.black54` dans la sidebar, déjà présent dans HEAD.
- Captures locales issues de fixtures : desktop et mobile inspectés. Elles ne
  prouvent ni session Clerk hébergée, ni OAuth Gmail, ni réception réelle.

Reçu de délégation : 1 agent backend, batches de mutation séparés ; intégration
Flutter et revue finale par l'agent principal. Aucun fichier hors scope modifié.
