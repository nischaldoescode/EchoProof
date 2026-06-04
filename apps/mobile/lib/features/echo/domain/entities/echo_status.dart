// canonical echo status enum for echoproof
// single source of truth imported by engine, widgets, and db layer
// never redefine this enum anywhere else in the codebase

/// represents every possible lifecycle state of an echo
/// the trust engine transitions echoes between these states automatically
/// admin overrides can force verified or rejected regardless of engine output
enum EchoStatus {
  /// newly created no community signals yet
  pendingVerification,

  /// has some signals, not yet verified
  active,

  /// report score crossed 20 reduced visibility
  underReview,

  /// trust score >= 50, confidence >= 70% community approved
  verified,

  /// high support and high challenge genuinely contested
  controversial,

  /// net negative trust score more challenges than support
  disputed,

  /// report score >= 70 blurred in feed, viewable on tap
  hidden,

  /// admin-forced rejection
  rejected;

  static EchoStatus fromString(String value) {
    switch (value) {
      case 'pending_verification':
        return EchoStatus.pendingVerification;
      case 'active':
        return EchoStatus.active;
      case 'under_review':
        return EchoStatus.underReview;
      case 'verified':
        return EchoStatus.verified;
      case 'controversial':
        return EchoStatus.controversial;
      case 'disputed':
        return EchoStatus.disputed;
      case 'hidden':
        return EchoStatus.hidden;
      case 'rejected':
        return EchoStatus.rejected;
      default:
        return EchoStatus.active; // safe fallback
    }
  }

  /// human-readable label shown in ui
  String get displayLabel => switch (this) {
        EchoStatus.pendingVerification => 'Awaiting echoes...',
        EchoStatus.active => 'Active',
        EchoStatus.underReview => 'Under community review',
        EchoStatus.verified => 'Verified by community',
        EchoStatus.controversial => 'Controversial — community split',
        EchoStatus.disputed => 'Disputed',
        EchoStatus.hidden => 'Hidden',
        EchoStatus.rejected => 'Rejected',
      };

  /// whether community can interact (support/challenge) with this echo
  bool get isInteractable => switch (this) {
        EchoStatus.hidden => false,
        EchoStatus.rejected => false,
        _ => true,
      };
}
