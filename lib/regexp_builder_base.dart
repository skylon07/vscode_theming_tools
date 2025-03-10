import './regexp_recipes.dart';
import './regexp_normalization.dart';
import './syntax_definition.dart';


abstract base class RegExpBuilder<CollectionT> {
  CollectionT createCollection();


  // base/fundamental recipe creation functions

  RegExpRecipe exactly(String string) => 
    _escapedPattern(string, RegExp(r"[.?*+\-()\[\]{}\^$|\\]"));

  RegExpRecipe _escapedPattern(String exprStr, RegExp? escapeExpr) {
    String expr;
    if (escapeExpr != null) {
      expr = exprStr.replaceAllMapped(escapeExpr, (match) => "\\${match[0]}");
    } else {
      expr = exprStr;
    }
    return normalize(BaseRegExpRecipe(expr));
  }

  RegExpRecipe chars(String charSet) => _chars(charSet, invert: false);

  RegExpRecipe notChars(String charSet) => _chars(charSet, invert: true);

  RegExpRecipe _chars(String charSet, {bool invert = false}) {
    var baseRecipe = _escapedPattern(charSet, RegExp(r"[\[\]\^\/\-]"));
    var augment = (expr) => "[${invert ? "^":""}${expr.replaceAll("..", "-")}]";
    return normalize(InvertibleRegExpRecipe(baseRecipe, augment, inverted: invert, tag: RegExpTag.chars));
  }


  // basic composition operations

  RegExpRecipe capture(RegExpRecipe inner, [GroupRef? ref]) {
    var augment = (expr) => "($expr)";
    return normalize(TrackedRegExpRecipe(inner, augment, ref: ref, tag: RegExpTag.capture));
  }

  RegExpRecipe concat(List<RegExpRecipe> recipes) => 
    capture(_join(recipes, joinBy: "", tag: RegExpTag.concat));

  RegExpPair pair({required RegExpRecipe begin, required RegExpRecipe end}) => RegExpPair(begin, end);

  RegExpRecipe _augment(RegExpRecipe recipe, String Function(String expr) mapExpr, {RegExpTag tag = RegExpTag.none}) =>
    normalize(AugmentedRegExpRecipe(recipe, mapExpr, tag: tag));

  RegExpRecipe _join(List<RegExpRecipe> recipes, {required String joinBy, RegExpTag tag = RegExpTag.none}) {
    if (recipes.isEmpty) throw ArgumentError("Joining list should not be empty.", "recipes"); 
    return normalize(JoinedRegExpRecipe(recipes, joinBy, tag: tag));
  }


  // "constant" recipies

  late final nothing = exactly("");
  late final anything = _escapedPattern(".", null);


  // repitition and optionality
  
  RegExpRecipe optional(RegExpRecipe inner) =>
    _augment(inner, (expr) => "$expr?");

  RegExpRecipe zeroOrMore(RegExpRecipe inner) =>
    _augment(inner, (expr) => "$expr*");

  RegExpRecipe oneOrMore(RegExpRecipe inner) =>
    _augment(inner, (expr) => "$expr+");

  RegExpRecipe repeatEqual(int times, RegExpRecipe inner) =>
    _augment(inner, (expr) => "$expr{$times}");
    
  RegExpRecipe repeatAtLeast(int times, RegExpRecipe inner) =>
    _augment(inner, (expr) => "$expr{$times,}");

  RegExpRecipe repeatAtMost(int times, RegExpRecipe inner) =>
    _augment(inner, (expr) => "$expr{,$times}");

  RegExpRecipe repeatBetween(RegExpRecipe inner, int lowTimes, int highTimes) =>
    _augment(inner, (expr) => "$expr{$lowTimes,$highTimes}");

  RegExpRecipe either(List<RegExpRecipe> branches) =>
    capture(_join(branches, joinBy: r"|", tag: RegExpTag.either));


  // "look around" operations

  RegExpRecipe aheadIs(RegExpRecipe inner) => 
    _augment(inner, (expr) => "(?=$expr)", tag: RegExpTag.aheadIs);

  RegExpRecipe aheadIsNot(RegExpRecipe inner) => 
    _augment(inner, (expr) => "(?!$expr)", tag: RegExpTag.aheadIsNot);

  RegExpRecipe behindIs(RegExpRecipe inner) => 
    _augment(inner, (expr) => "(?<=$expr)", tag: RegExpTag.behindIs);

  RegExpRecipe behindIsNot(RegExpRecipe inner) => 
    _augment(inner, (expr) => "(?<!$expr)", tag: RegExpTag.behindIsNot);

  
  // anchors

  RegExpRecipe startsWith(RegExpRecipe inner) =>
    _augment(inner, (expr) => "^$expr");

  RegExpRecipe endsWith(RegExpRecipe inner) =>
    _augment(inner, (expr) => "$expr\$");

  RegExpRecipe startsAndEndsWith(RegExpRecipe inner) =>
    _augment(inner, (expr) => "^$expr\$");


  // spacing

  late final _anySpace = _escapedPattern(r"\s*", null);
  late final _reqSpace = _escapedPattern(r"\s+", null);

  RegExpRecipe space({required bool req}) => req ? _reqSpace : _anySpace;

  RegExpRecipe spaceBefore(RegExpRecipe inner) =>
    concat([_anySpace, inner]);
  
  RegExpRecipe spaceReqBefore(RegExpRecipe inner) =>
    concat([_reqSpace, inner]);

  RegExpRecipe spaceAfter(RegExpRecipe inner) =>
    concat([inner, _anySpace]);
  
  RegExpRecipe spaceReqAfter(RegExpRecipe inner) =>
    concat([inner, _reqSpace]);
    
  RegExpRecipe spaceAround(RegExpRecipe inner) =>
    concat([_anySpace, inner, _anySpace]);
  
  RegExpRecipe spaceReqAround(RegExpRecipe inner) =>
    concat([_reqSpace, inner, _reqSpace]);

  RegExpRecipe spaceAroundReqBefore(RegExpRecipe inner) =>
    concat([_reqSpace, inner, _anySpace]);
  
  RegExpRecipe spaceAroundReqAfter(RegExpRecipe inner) =>
    concat([_anySpace, inner, _reqSpace]);

  RegExpRecipe phrase(String string) {
    var inner = _augment(
      exactly(string),
      (expr) => expr.replaceAll(r" ", r"\s+"),
    );
    return concat([
      behindIs(either([
        startsWith(nothing),
        _nonWordChar,
      ])),
      inner,
      aheadIs(either([
        _nonWordChar,
        endsWith(nothing),
      ])),
    ]);
  }

  late final _nonWordChar = notChars(r"a..zA..Z0..9_$"); // dart chars -- should work for most languages
}


final class _BlankBuilder extends RegExpBuilder<()> {
  @override
  () createCollection() => ();
}
final regExpBuilder = _BlankBuilder();
