import 'package:equatable/equatable.dart';

import 'image_ref.dart';

/// Optional visual identity supplied by an event's competition or organizer.
///
/// The app treats these values as display data. A missing value leaves the
/// corresponding participant or generated fallback in charge of the artwork.
class EventBranding extends Equatable {
  /// Creates optional event branding.
  const EventBranding({this.logo, this.primaryColor, this.secondaryColor});

  /// Builds branding from decoded JSON.
  factory EventBranding.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {'logo', 'primaryColor', 'secondaryColor'});

    final primaryColor = _optionalColor(json['primaryColor'], 'primaryColor');
    final secondaryColor = _optionalColor(
      json['secondaryColor'],
      'secondaryColor',
    );
    final logo = ImageRef.fromJson(json['logo']);
    if (logo == null && primaryColor == null && secondaryColor == null) {
      throw const FormatException(
        'event branding must contain a logo or color',
      );
    }

    return EventBranding(
      logo: logo,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
    );
  }

  /// Optional competition, tournament, or organizer mark.
  final ImageRef? logo;

  /// Optional primary background color as `#RRGGBB`.
  final String? primaryColor;

  /// Optional secondary background color as `#RRGGBB`.
  final String? secondaryColor;

  /// Encodes branding for the extension boundary.
  Map<String, Object?> toJson() => {
    if (logo != null) 'logo': logo!.toJson(),
    if (primaryColor != null) 'primaryColor': primaryColor,
    if (secondaryColor != null) 'secondaryColor': secondaryColor,
  };

  @override
  List<Object?> get props => [logo, primaryColor, secondaryColor];
}

String? _optionalColor(Object? value, String field) {
  if (value == null) return null;
  if (value is! String || !_isHexColor(value)) {
    throw FormatException('event branding.$field must be a #RRGGBB color');
  }
  return value;
}

bool _isHexColor(String value) {
  final normalized = value.startsWith('#') ? value.substring(1) : '';
  if (normalized.length != 6) return false;
  return int.tryParse(normalized, radix: 16) != null;
}

void _rejectUnknown(Map<String, Object?> json, Set<String> allowed) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('event branding has unsupported field "$key"');
    }
  }
}
