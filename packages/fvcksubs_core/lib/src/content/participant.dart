import 'package:equatable/equatable.dart';

import 'image_ref.dart';

/// One side of a contest, or one competitor in an event.
///
/// [score] is a `String`, not an `int`: a football score is `"2"`, a lap time
/// is `"1'23.456"`, a set score is `"6-4"`. The app renders it verbatim and
/// never parses it — that would be the app knowing what a vertical means.
class Participant extends Equatable {
  /// Creates a participant.
  const Participant({
    required this.name,
    this.shortName,
    this.logo,
    this.color,
    this.score,
  });

  /// Builds a [Participant] from decoded JSON.
  factory Participant.fromJson(Map<String, Object?> json) => Participant(
    name: json['name'] as String,
    shortName: json['shortName'] as String?,
    logo: ImageRef.fromJson(json['logo']),
    color: json['color'] as String?,
    score: json['score'] as String?,
  );

  /// Display name (`"Manchester United"`, `"Marc Marquez"`).
  final String name;

  /// A shorter form of [name], when the catalog provides one
  /// (`"Bolton"` for `"Bolton Wanderers"`). Broadcast sources abbreviate far
  /// more often than the catalog does, so carrying this alongside the full
  /// name gives cross-extension name matching (see `EventMatchResolver`) a
  /// second, usually closer, spelling to try — at no cost when it isn't set.
  final String? shortName;

  /// Optional logo/portrait.
  final ImageRef? logo;

  /// Optional accent colour, `#RRGGBB` (a shirt colour, a livery — whatever
  /// the catalog has), or `null` when the extension doesn't have one. A
  /// generated banner uses this in place of artwork when there's no
  /// item artwork; the app otherwise treats it as opaque, same as
  /// every other display field.
  final String? color;

  /// Current score/result as a display string, or `null` before it exists.
  final String? score;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'name': name,
    if (shortName != null) 'shortName': shortName,
    if (logo != null) 'logo': logo!.toJson(),
    if (color != null) 'color': color,
    if (score != null) 'score': score,
  };

  @override
  List<Object?> get props => [name, shortName, logo, color, score];
}
