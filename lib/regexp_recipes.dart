import 'package:meta/meta.dart';


sealed class RegExpRecipe {
  final List<RegExpRecipe> sources;
  final GroupTracker _tracker;
  final RegExpTag tag;
  var _hasCompiled = false;

  RegExpRecipe(this.sources, this._tracker, {this.tag = RegExpTag.none});

  String compile() {
    _hasCompiled = true;
    return _expr;
  }
  late final _expr = _createExpr();
  bool get hasCompiled => _hasCompiled;

  int positionOf(GroupRef ref) => _tracker.getPosition(ref);
  /// A special "uncaptured" version of this recipe that ignores all captures within it
  late final withCapturesIgnored = TrackedRegExpRecipe(
    this,
    (expr) => expr,
    tracker: _tracker.markAllIgnored(),
    tag: RegExpTag.uncapture,
  );

  @mustBeOverridden
  RegExpRecipe copy({RegExpTag? tag});
  String _createExpr();
}

enum RegExpTag {
  none,
  capture, uncapture,
  either, chars, concat,
  aheadIs, aheadIsNot,
  behindIs, behindIsNot,
}


final class BaseRegExpRecipe extends RegExpRecipe {
  final String expr;

  BaseRegExpRecipe(this.expr, {super.tag}) : super(const [], GroupTracker());

  @override
  BaseRegExpRecipe copy({
    String? expr,
    RegExpTag? tag,
  }) => BaseRegExpRecipe(
    expr ?? this.expr,
    tag: tag ?? this.tag,
  );
  
  @override
  String _createExpr() => expr;
}

final class AugmentedRegExpRecipe extends RegExpRecipe {
  final RegExpRecipe source;
  final Augmenter augment;

  AugmentedRegExpRecipe(this.source, this.augment, {super.tag}) : super([source], source._tracker);

  @override
  AugmentedRegExpRecipe copy({
    RegExpRecipe? source,
    Augmenter? augment,
    RegExpTag? tag,
  }) => AugmentedRegExpRecipe(
    source ?? this.source,
    augment ?? this.augment,
    tag: tag ?? this.tag,
  );

  @override
  String _createExpr() => augment(source.compile());
}
typedef Augmenter = String Function(String expr);

final class JoinedRegExpRecipe extends RegExpRecipe {
  final String joinBy;

  JoinedRegExpRecipe(List<RegExpRecipe> sources, this.joinBy, {super.tag}) : 
    super(
      sources,
      GroupTracker.combine(
        sources.map((source) => source._tracker),
      ),
    );

  @override
  JoinedRegExpRecipe copy({
    List<RegExpRecipe>? sources,
    String? joinBy,
    RegExpTag? tag,
  }) => JoinedRegExpRecipe(
    sources ?? this.sources,
    joinBy ?? this.joinBy,
    tag: tag ?? this.tag,
  );

  @override
  String _createExpr() {
    return sources
      .map((source) => source.compile())
      .join(joinBy);
  }
}


final class InvertibleRegExpRecipe extends AugmentedRegExpRecipe {
  final bool inverted;

  InvertibleRegExpRecipe(super.source, super.augment, {required this.inverted, super.tag});

  @override
  InvertibleRegExpRecipe copy({
    RegExpRecipe? source,
    Augmenter? augment,
    bool? inverted,
    RegExpTag? tag,
  }) => InvertibleRegExpRecipe(
    source ?? this.source,
    augment ?? this.augment,
    inverted: inverted ?? this.inverted,
    tag: tag ?? this.tag,
  );
}

final class TrackedRegExpRecipe extends AugmentedRegExpRecipe {
  @override
  late final GroupTracker _tracker;

  TrackedRegExpRecipe(
    super.source,
    super.augment,
    {
      GroupRef? ref,
      GroupTracker? tracker,
      super.tag,
    }
  ) {
    var newTracker = tracker ?? source._tracker.increment();
    if (ref != null) {
      newTracker = newTracker.startTracking(ref);
    }
    _tracker = newTracker;
  }

  @override
  TrackedRegExpRecipe copy({
    RegExpRecipe? source,
    Augmenter? augment,
    GroupTracker? tracker,
    RegExpTag? tag,
  }) => TrackedRegExpRecipe(
    source ?? this.source,
    augment ?? this.augment,
    tracker: tracker ?? this._tracker,
    tag: tag ?? this.tag,
  );
}


class GroupRef {
  var _positionUsed = false;
  bool get positionUsed => _positionUsed;
}

// TODO: document operation meanings
final class GroupTracker {
  final Map<GroupRef, int> _positions;
  final int _groupCount;
  final Set<GroupRef> _previouslyIgnoredRefs;

  const GroupTracker._create(this._positions, this._groupCount, this._previouslyIgnoredRefs);
  const GroupTracker(): this._create(const {}, 0, const {});

  GroupTracker startTracking(GroupRef newRef, [int position = 1]) {
    var isDuplicate = _positions.containsKey(newRef);
    if (isDuplicate) throw ArgumentError("Ref is invalid because it was used multiple times!", "ref");

    assert (!_positions.containsKey(newRef));
    return GroupTracker._create(
      {
        ..._positions,
        newRef: position,
      },
      _groupCount,
      _previouslyIgnoredRefs,
    );
  }

  int getPosition(GroupRef ref) {
    if (!_positions.containsKey(ref)) {
      var ignoredHint = _previouslyIgnoredRefs.contains(ref) ?
        " (It was previously tracked, then later ignored.)" : "";
      throw ArgumentError("Position not tracked for ref!$ignoredHint", "ref");
    }
    ref._positionUsed = true;
    return _positions[ref]!;
  }

  int get groupCount => _groupCount;

  GroupTracker increment([int by = 1]) => GroupTracker._create(
    {
      for (var MapEntry(key: groupRef, value: position) in _positions.entries)
        groupRef: position + by,
    },
    _groupCount + by,
    _previouslyIgnoredRefs,
  );

  GroupTracker markAllIgnored() => GroupTracker._create(
    const {},
    _groupCount,
    {
      ..._previouslyIgnoredRefs,
      ..._positions.keys,
    },
  );

  static GroupTracker combine(Iterable<GroupTracker> trackers) {
    var combinedPositions = <GroupRef, int>{};
    var totalGroupCount = 0;
    var combinedPreviouslyIgnoredRefs = <GroupRef>{};

    for (var tracker in trackers) {
      for (var MapEntry(key: groupRef, value: position) in tracker._positions.entries) {
        if (!combinedPositions.containsKey(groupRef)) {
          combinedPositions[groupRef] = position + totalGroupCount;
        } else {
          throw ArgumentError("""
A GroupRef was reused in multiple places.
This is not allowed since this makes the GroupRef an unreliable reference.
Try using more (unique) GroupRefs or use `recipe.withCapturesIgnored` to discard some."""
          );
        }

        combinedPreviouslyIgnoredRefs.addAll(tracker._previouslyIgnoredRefs);
      }
      totalGroupCount += tracker._groupCount;
    }

    return GroupTracker._create(combinedPositions, totalGroupCount, combinedPreviouslyIgnoredRefs);
  }
}
