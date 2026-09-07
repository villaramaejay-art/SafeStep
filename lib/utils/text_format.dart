/// Small text helpers, so the app never has to write "contact(s)".
///
/// The parenthesised plural is the mark of software nobody finished. It costs
/// one function to never do it again.
class TextFormat {
  const TextFormat._();

  /// "1 contact", "2 contacts". Pass [plural] when adding an s is wrong.
  static String count(int value, String singular, [String? plural]) {
    if (value == 1) return '1 $singular';
    return '$value ${plural ?? '${singular}s'}';
  }

  /// The noun on its own, matched to [value]: "contact" / "contacts".
  static String noun(int value, String singular, [String? plural]) {
    return value == 1 ? singular : (plural ?? '${singular}s');
  }
}
