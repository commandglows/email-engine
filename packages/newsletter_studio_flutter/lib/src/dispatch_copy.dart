/// Texts of [DispatchPanel]. The defaults are the project wording; a host with
/// another destination model overrides the fields it needs. A label missing from
/// a map falls back to its default, then to a generic label.
class DispatchPanelCopy {
  const DispatchPanelCopy({
    this.title = 'Dispatch vers les projets',
    this.intro =
        'Saisissez uniquement les éléments à transmettre et à conserver dans les files privées.',
    this.consentBody =
        'Le texte de cet email et le nom ou la description des projets candidats seront transmis au fournisseur IA configuré dans votre compte. '
        'Ses règles de conservation s’appliquent. Les suggestions restent privées et aucun projet ne recevra de contribution avant votre confirmation.',
    this.confirmIntro =
        'Ce contenu sera conservé dans la file privée de chaque projet sélectionné.',
    this.validationError =
        'Renseignez un résumé, de un à cinq projets et une confiance entre 0 et 1, ou laissez-la vide.',
    this.emptyDestinations = 'Aucune destination projet configurée.',
    this.unavailableSubtitle = 'Connexion ou autorisation projet indisponible',
    this.acceptedReceipt = 'Reçu en revue privée',
    this.terminalReceipt = 'Échec définitif',
    this.terminalAdvice = 'Cette destination ne peut plus recevoir cet apport.',
    this.filterHint = 'Filtrer les destinations',
    this.kindLabels = defaultKindLabels,
    this.contributionTypeLabels = defaultContributionTypeLabels,
    this.receiptAdvice = const {},
  });

  static const Map<String, String> defaultKindLabels = {
    'content_draft': 'Ébauche ContentGlows',
    'content_in_progress': 'Contenu en cours',
    'content_idea': 'Idée',
    'idea_pool': 'Idea Pool',
    'published_article': 'Article publié',
    'new_content': 'Nouveau contenu',
    'project': 'Projet',
  };

  static const Map<String, String> defaultContributionTypeLabels = {
    'newsletter_inspiration': 'Inspiration de newsletter',
    'thematic_source': 'Source thématique',
    'potential_task': 'Tâche potentielle',
    'other': 'Autre',
  };

  final String title,
      intro,
      consentBody,
      confirmIntro,
      validationError,
      emptyDestinations,
      unavailableSubtitle,
      acceptedReceipt,
      terminalReceipt,
      terminalAdvice,
      filterHint;

  /// Keyed by destination `kind`.
  final Map<String, String> kindLabels;

  /// Keyed by contribution type code, which is fixed by the lab contract.
  final Map<String, String> contributionTypeLabels;

  /// Advice keyed by receipt `errorCode`, checked before the built-in advice.
  final Map<String, String> receiptAdvice;
}
