/// The repeatable, structured IPTC records — the tables Photo Mechanic exposes
/// (Location Shown, Artwork or Object, Image Creators, Copyright Owners).
/// Unlike the flat `IptcField` strings, each is a *list of records*, so they
/// live outside the generic string map and get their own table editors. All
/// are XMP-only (no IIM equivalent). Pure value objects: immutable,
/// JSON-round-trippable, with an `isEmpty` used to drop blank rows.
library;

/// One place shown in (or where the image was created) — an `Iptc4xmpExt`
/// Location structure.
class IptcLocation {
  /// Creates a location record; every part defaults to empty.
  const IptcLocation({
    this.sublocation = '',
    this.city = '',
    this.state = '',
    this.country = '',
    this.countryCode = '',
    this.worldRegion = '',
    this.locationId = '',
  });

  /// Rebuilds from the map written by [toJson]; missing keys default to empty.
  factory IptcLocation.fromJson(Map<String, dynamic> json) {
    String s(String k) => json[k] as String? ?? '';
    return IptcLocation(
      sublocation: s('sublocation'),
      city: s('city'),
      state: s('state'),
      country: s('country'),
      countryCode: s('countryCode'),
      worldRegion: s('worldRegion'),
      locationId: s('locationId'),
    );
  }

  /// Sublocation within the city (`Iptc4xmpExt:Sublocation`).
  final String sublocation;

  /// City (`Iptc4xmpExt:City`).
  final String city;

  /// Province / state (`Iptc4xmpExt:ProvinceState`).
  final String state;

  /// Country name (`Iptc4xmpExt:CountryName`).
  final String country;

  /// ISO country code (`Iptc4xmpExt:CountryCode`).
  final String countryCode;

  /// World region (`Iptc4xmpExt:WorldRegion`).
  final String worldRegion;

  /// Location identifier (`Iptc4xmpExt:LocationId`).
  final String locationId;

  /// Whether every part is blank (a row worth dropping).
  bool get isEmpty =>
      sublocation.isEmpty &&
      city.isEmpty &&
      state.isEmpty &&
      country.isEmpty &&
      countryCode.isEmpty &&
      worldRegion.isEmpty &&
      locationId.isEmpty;

  /// A compact map holding only the non-empty parts.
  Map<String, dynamic> toJson() => {
    if (sublocation.isNotEmpty) 'sublocation': sublocation,
    if (city.isNotEmpty) 'city': city,
    if (state.isNotEmpty) 'state': state,
    if (country.isNotEmpty) 'country': country,
    if (countryCode.isNotEmpty) 'countryCode': countryCode,
    if (worldRegion.isNotEmpty) 'worldRegion': worldRegion,
    if (locationId.isNotEmpty) 'locationId': locationId,
  };

  /// Returns a copy with every field passed through [f] — used to expand
  /// `{variables}`/`=codes=` in template table cells per photo.
  IptcLocation mapStrings(String Function(String) f) => IptcLocation(
    sublocation: f(sublocation),
    city: f(city),
    state: f(state),
    country: f(country),
    countryCode: f(countryCode),
    worldRegion: f(worldRegion),
    locationId: f(locationId),
  );
}

/// An artwork or object shown in the image (`Iptc4xmpExt:ArtworkOrObject`).
class IptcArtwork {
  /// Creates an artwork record; every part defaults to empty.
  const IptcArtwork({
    this.title = '',
    this.creator = '',
    this.source = '',
    this.copyrightNotice = '',
  });

  /// Rebuilds from the map written by [toJson].
  factory IptcArtwork.fromJson(Map<String, dynamic> json) {
    String s(String k) => json[k] as String? ?? '';
    return IptcArtwork(
      title: s('title'),
      creator: s('creator'),
      source: s('source'),
      copyrightNotice: s('copyrightNotice'),
    );
  }

  /// Title of the work (`Iptc4xmpExt:AOTitle`).
  final String title;

  /// Creator of the work (`Iptc4xmpExt:AOCreator`).
  final String creator;

  /// Source / holding institution (`Iptc4xmpExt:AOSource`).
  final String source;

  /// Copyright notice for the work (`Iptc4xmpExt:AOCopyrightNotice`).
  final String copyrightNotice;

  /// Whether every part is blank.
  bool get isEmpty =>
      title.isEmpty &&
      creator.isEmpty &&
      source.isEmpty &&
      copyrightNotice.isEmpty;

  /// A compact map holding only the non-empty parts.
  Map<String, dynamic> toJson() => {
    if (title.isNotEmpty) 'title': title,
    if (creator.isNotEmpty) 'creator': creator,
    if (source.isNotEmpty) 'source': source,
    if (copyrightNotice.isNotEmpty) 'copyrightNotice': copyrightNotice,
  };

  /// Returns a copy with every field passed through [f].
  IptcArtwork mapStrings(String Function(String) f) => IptcArtwork(
    title: f(title),
    creator: f(creator),
    source: f(source),
    copyrightNotice: f(copyrightNotice),
  );
}

/// A named entity with an identifier — a PLUS Image Creator or Copyright Owner.
class IptcEntity {
  /// Creates an entity; both parts default to empty.
  const IptcEntity({this.name = '', this.identifier = ''});

  /// Rebuilds from the map written by [toJson].
  factory IptcEntity.fromJson(Map<String, dynamic> json) => IptcEntity(
    name: json['name'] as String? ?? '',
    identifier: json['identifier'] as String? ?? '',
  );

  /// The entity's name.
  final String name;

  /// The entity's identifier (often a URI).
  final String identifier;

  /// Whether both parts are blank.
  bool get isEmpty => name.isEmpty && identifier.isEmpty;

  /// A compact map holding only the non-empty parts.
  Map<String, dynamic> toJson() => {
    if (name.isNotEmpty) 'name': name,
    if (identifier.isNotEmpty) 'identifier': identifier,
  };

  /// Returns a copy with both fields passed through [f].
  IptcEntity mapStrings(String Function(String) f) =>
      IptcEntity(name: f(name), identifier: f(identifier));
}

/// A PLUS licensor (`plus:Licensor`): who to contact to license the image.
/// A practical subset of the PLUS structure — name, ID, phone, email, URL.
class IptcLicensor {
  /// Creates a licensor record; every part defaults to empty.
  const IptcLicensor({
    this.name = '',
    this.id = '',
    this.phone = '',
    this.email = '',
    this.url = '',
  });

  /// Rebuilds from the map written by [toJson].
  factory IptcLicensor.fromJson(Map<String, dynamic> json) {
    String s(String k) => json[k] as String? ?? '';
    return IptcLicensor(
      name: s('name'),
      id: s('id'),
      phone: s('phone'),
      email: s('email'),
      url: s('url'),
    );
  }

  /// Licensor name (`plus:LicensorName`).
  final String name;

  /// Licensor identifier (`plus:LicensorID`).
  final String id;

  /// Licensor work phone (`plus:LicensorTelephone1`).
  final String phone;

  /// Licensor work email (`plus:LicensorEmail`).
  final String email;

  /// Licensor web URL (`plus:LicensorURL`).
  final String url;

  /// Whether every part is blank.
  bool get isEmpty =>
      name.isEmpty &&
      id.isEmpty &&
      phone.isEmpty &&
      email.isEmpty &&
      url.isEmpty;

  /// A compact map holding only the non-empty parts.
  Map<String, dynamic> toJson() => {
    if (name.isNotEmpty) 'name': name,
    if (id.isNotEmpty) 'id': id,
    if (phone.isNotEmpty) 'phone': phone,
    if (email.isNotEmpty) 'email': email,
    if (url.isNotEmpty) 'url': url,
  };

  /// Returns a copy with every field passed through [f].
  IptcLicensor mapStrings(String Function(String) f) => IptcLicensor(
    name: f(name),
    id: f(id),
    phone: f(phone),
    email: f(email),
    url: f(url),
  );
}

/// A registry entry (`Iptc4xmpExt:RegistryId`): an image's ID in some registry,
/// as an item ID plus the organisation that issued it.
class IptcRegistryEntry {
  /// Creates a registry record; both parts default to empty.
  const IptcRegistryEntry({this.itemId = '', this.organisationId = ''});

  /// Rebuilds from the map written by [toJson].
  factory IptcRegistryEntry.fromJson(Map<String, dynamic> json) =>
      IptcRegistryEntry(
        itemId: json['itemId'] as String? ?? '',
        organisationId: json['organisationId'] as String? ?? '',
      );

  /// The image's ID within the registry (`Iptc4xmpExt:RegItemId`).
  final String itemId;

  /// The registering organisation's ID (`Iptc4xmpExt:RegOrgId`).
  final String organisationId;

  /// Whether both parts are blank.
  bool get isEmpty => itemId.isEmpty && organisationId.isEmpty;

  /// A compact map holding only the non-empty parts.
  Map<String, dynamic> toJson() => {
    if (itemId.isNotEmpty) 'itemId': itemId,
    if (organisationId.isNotEmpty) 'organisationId': organisationId,
  };

  /// Returns a copy with both fields passed through [f].
  IptcRegistryEntry mapStrings(String Function(String) f) =>
      IptcRegistryEntry(itemId: f(itemId), organisationId: f(organisationId));
}

/// Parses a JSON list into records via [fromJson], dropping empty ones.
List<T> parseRecords<T>(
  Object? raw,
  T Function(Map<String, dynamic>) fromJson,
  bool Function(T) isEmpty,
) {
  if (raw is! List) return const [];
  return [
    for (final entry in raw)
      if (entry is Map)
        if (fromJson(entry.cast<String, dynamic>()) case final r
            when !isEmpty(r))
          r,
  ];
}
