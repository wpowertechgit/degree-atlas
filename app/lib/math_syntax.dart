/// Markdown syntaxes for TeX math, shared by the reader and the note export.
///
/// `$...$` is inline and `$$...$$` display math (a multi-line `$$` block uses LatexBlockSyntax). The inline
/// rule replaces the package's LatexInlineSyntax, which only closes `$` before a space or `?!.,:` and so runs
/// "$I$; $A$" or "($x$)" together into one broken formula. Here the opening `$` is not followed by a space,
/// the closing `$` is not preceded by a space and not followed by a digit, so "$5 and $10" stays text.
library;

import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart' show LatexBlockSyntax;
import 'package:markdown/markdown.dart' as md;

class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'\$\$([^$\n]+?)\$\$|\$(?![\s$])((?:\\.|[^\\$\n])+?)(?<!\s)\$(?!\d)', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match m) {
    final display = m[1] != null;
    parser.addNode(md.Element.text('latex', display ? m[1]! : m[2]!)..attributes['MathStyle'] = display ? 'display' : 'text');
    return true;
  }
}

/// GitHub-flavoured Markdown plus math; the 'latex' elements carry `MathStyle` = `text` or `display`.
final mathExtensionSet = md.ExtensionSet(
  [...md.ExtensionSet.gitHubFlavored.blockSyntaxes, LatexBlockSyntax()],
  [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, MathInlineSyntax()],
);
