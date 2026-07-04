import 'package:cullimingo/features/metadata/domain/crop_rect.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:xml/xml.dart';

/// Private XMP namespace for marks that have no interop standard (the flag).
const String kCullimingoNs = 'https://cullimingo.app/ns/1.0/';

/// Lightroom/Bridge default colour-label strings (`xmp:Label`).
const Map<ColorLabel, String> _labelToXmp = {
  ColorLabel.red: 'Red',
  ColorLabel.yellow: 'Yellow',
  ColorLabel.green: 'Green',
  ColorLabel.blue: 'Blue',
  ColorLabel.purple: 'Purple',
};

/// Serialises [data] to an XMP packet that Capture One and Lightroom read.
///
/// Cull marks are simple attributes (`xmp:Rating`, `xmp:Label`, our private
/// flag). IPTC Core is split by XMP shape: the language-alternative fields
/// (`dc:description`, `dc:rights`, alt-text) become `rdf:Alt`, the creator an
/// `rdf:Seq`, and the plain fields (`photoshop:`/`Iptc4xmpCore:`) attributes.
String encodeXmp(XmpData data) {
  final attrs = StringBuffer();
  if (data.rating > 0) attrs.write(' xmp:Rating="${data.rating}"');
  final label = _labelToXmp[data.color];
  if (label != null) attrs.write(' xmp:Label="$label"');
  if (data.flag != PickFlag.none) {
    attrs.write(' cullimingo:flag="${data.flag.name}"');
  }
  // Only write a non-trivial orientation — a normal (1) photo needs no override
  // and staying silent keeps untouched sidecars byte-identical to before.
  final orientation = data.orientation;
  if (orientation != null && orientation > 1 && orientation <= 8) {
    attrs.write(' tiff:Orientation="$orientation"');
  }

  final iptc = data.iptc;
  void simple(String name, String value) {
    if (value.isNotEmpty) attrs.write(' $name="${_escape(value)}"');
  }

  // The editable IPTC Date Created wins over the EXIF capture time; empty falls
  // back to the capture time so untouched photos keep today's behaviour.
  final dateCreated = iptc.dateCreatedParsed ?? data.dateCreated;
  if (dateCreated != null) {
    attrs.write(' photoshop:DateCreated="${_isoLocal(dateCreated)}"');
  }

  simple('photoshop:Headline', iptc.headline);
  simple('photoshop:AuthorsPosition', iptc.authorTitle);
  simple('photoshop:Credit', iptc.credit);
  simple('photoshop:Source', iptc.source);
  simple('photoshop:Instructions', iptc.instructions);
  simple('photoshop:City', iptc.city);
  simple('photoshop:State', iptc.state);
  simple('photoshop:Country', iptc.country);
  simple('Iptc4xmpCore:Location', iptc.location);
  simple('Iptc4xmpCore:CountryCode', iptc.countryCode);
  simple('xmpRights:WebStatement', iptc.webStatement);
  simple('photoshop:TransmissionReference', iptc.jobId);
  simple('photoshop:CaptionWriter', iptc.descriptionWriters);
  simple('Iptc4xmpCore:IntellectualGenre', iptc.intellectualGenre);
  simple('photoshop:Category', iptc.category);
  simple('photoshop:Urgency', iptc.urgency);
  simple('cullimingo:EditStatus', iptc.editStatus);
  simple('plus:ModelReleaseStatus', iptc.modelReleaseStatus);
  simple('plus:PropertyReleaseStatus', iptc.propertyReleaseStatus);
  simple('Iptc4xmpExt:AISystemUsed', iptc.aiSystemUsed);
  simple('Iptc4xmpExt:AISystemVersionUsed', iptc.aiSystemVersion);
  simple('Iptc4xmpExt:AIPromptInformation', iptc.aiPromptInfo);
  simple('Iptc4xmpExt:AIPromptWriterName', iptc.aiPromptWriter);
  simple('Iptc4xmpExt:AddlModelInfo', iptc.additionalModelInfo);
  simple('plus:MinorModelAgeDisclosure', iptc.minorModelAgeDisclosure);
  simple('plus:ImageSupplierImageID', iptc.imageSupplierImageId);
  simple('Iptc4xmpExt:DigImageGUID', iptc.digImageGuid);
  final marked = _markedValue(iptc.copyrightStatus);
  if (marked != null) attrs.write(' xmpRights:Marked="$marked"');
  final sourceUri = _digitalSourceUri(iptc.digitalSourceType);
  if (sourceUri != null) {
    attrs.write(' Iptc4xmpExt:DigitalSourceType="${_escape(sourceUri)}"');
  }

  final children = StringBuffer();
  if (iptc.caption.isNotEmpty) {
    children.write(_langAlt('dc:description', iptc.caption));
  }
  if (iptc.title.isNotEmpty) {
    children.write(_langAlt('dc:title', iptc.title));
  }
  if (iptc.copyright.isNotEmpty) {
    children.write(_langAlt('dc:rights', iptc.copyright));
  }
  if (iptc.usageTerms.isNotEmpty) {
    children.write(_langAlt('xmpRights:UsageTerms', iptc.usageTerms));
  }
  if (iptc.altText.isNotEmpty) {
    children.write(_langAlt('Iptc4xmpCore:AltTextAccessibility', iptc.altText));
  }
  if (iptc.creator.isNotEmpty) {
    children.write(_seq('dc:creator', iptc.creator));
  }
  final contact = _creatorContact(
    email: iptc.creatorEmail,
    website: iptc.creatorWebsite,
    address: iptc.creatorAddress,
    city: iptc.creatorCity,
    region: iptc.creatorRegion,
    postalCode: iptc.creatorPostalCode,
    country: iptc.creatorCountry,
    phone: iptc.creatorPhone,
  );
  if (contact != null) children.write(contact);
  final supplier = _imageSupplier(iptc.imageSupplierName, iptc.imageSupplierId);
  if (supplier != null) children.write(supplier);
  void commaBag(String prop, String csv) {
    final values = _splitComma(csv);
    if (values.isNotEmpty) children.write(_bag(prop, values));
  }

  commaBag('Iptc4xmpCore:SubjectCode', iptc.subjectCodes);
  commaBag('Iptc4xmpExt:PersonInImage', iptc.personsShown);
  commaBag('Iptc4xmpExt:OrganisationInImageName', iptc.featuredOrgName);
  commaBag('Iptc4xmpExt:OrganisationInImageCode', iptc.featuredOrgCode);
  commaBag('Iptc4xmpCore:Scene', iptc.iptcScene);
  commaBag('photoshop:SupplementalCategories', iptc.supplementalCategories);
  commaBag('plus:ModelReleaseID', iptc.modelReleaseIds);
  commaBag('plus:PropertyReleaseID', iptc.propertyReleaseIds);
  commaBag('Iptc4xmpExt:ModelAge', iptc.modelAge);
  if (iptc.event.isNotEmpty) {
    children.write(_langAlt('Iptc4xmpExt:Event', iptc.event));
  }
  // The created location as an Iptc4xmpExt structure — the only standards-valid
  // home for World Region and Location ID (which have no flat form). City/state/
  // country still ride the flat photoshop:* attributes for LR/C1.
  final createdLocation = _locationResource(
    sublocation: iptc.location,
    city: iptc.city,
    state: iptc.state,
    country: iptc.country,
    countryCode: iptc.countryCode,
    worldRegion: iptc.worldRegion,
    locationId: iptc.locationId,
  );
  if (iptc.worldRegion.isNotEmpty || iptc.locationId.isNotEmpty) {
    children.write(
      '   <Iptc4xmpExt:LocationCreated rdf:parseType="Resource">\n'
      '$createdLocation'
      '   </Iptc4xmpExt:LocationCreated>\n',
    );
  }

  // Repeatable structured tables (all XMP-only).
  children
    ..write(
      _structArray('Iptc4xmpExt:LocationShown', [
        for (final l in iptc.locationsShown)
          _locationResource(
            sublocation: l.sublocation,
            city: l.city,
            state: l.state,
            country: l.country,
            countryCode: l.countryCode,
            worldRegion: l.worldRegion,
            locationId: l.locationId,
          ),
      ], seq: false),
    )
    ..write(
      _structArray('Iptc4xmpExt:ArtworkOrObject', [
        for (final a in iptc.artwork) _artworkResource(a),
      ], seq: false),
    )
    ..write(
      _structArray('plus:ImageCreator', [
        for (final e in iptc.imageCreators)
          _entityResource(e, 'ImageCreatorName', 'ImageCreatorID'),
      ], seq: true),
    )
    ..write(
      _structArray('plus:CopyrightOwner', [
        for (final e in iptc.copyrightOwners)
          _entityResource(e, 'CopyrightOwnerName', 'CopyrightOwnerID'),
      ], seq: true),
    )
    ..write(
      _structArray('plus:Licensor', [
        for (final l in iptc.licensors) _licensorResource(l),
      ], seq: true),
    )
    ..write(
      _structArray('Iptc4xmpExt:RegistryId', [
        for (final r in iptc.registryEntries) _registryResource(r),
      ], seq: false),
    );

  final lis = data.keywords
      .map((k) => '     <rdf:li>${_escape(k)}</rdf:li>')
      .join('\n');
  final subject = data.keywords.isEmpty
      ? ''
      : '   <dc:subject>\n'
            '    <rdf:Bag>\n'
            '$lis\n'
            '    </rdf:Bag>\n'
            '   </dc:subject>\n';

  return '<?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>\n'
      '<x:xmpmeta xmlns:x="adobe:ns:meta/">\n'
      ' <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
      '  <rdf:Description rdf:about=""\n'
      '    xmlns:xmp="http://ns.adobe.com/xap/1.0/"\n'
      '    xmlns:dc="http://purl.org/dc/elements/1.1/"\n'
      '    xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"\n'
      '    xmlns:Iptc4xmpCore="http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/"\n'
      '    xmlns:Iptc4xmpExt="http://iptc.org/std/Iptc4xmpExt/2008-02-29/"\n'
      '    xmlns:xmpRights="http://ns.adobe.com/xap/1.0/rights/"\n'
      '    xmlns:plus="http://ns.useplus.org/ldf/xmp/1.0/"\n'
      '    xmlns:tiff="http://ns.adobe.com/tiff/1.0/"\n'
      '    xmlns:cullimingo="$kCullimingoNs"$attrs>\n'
      '$subject'
      '$children'
      '  </rdf:Description>\n'
      ' </rdf:RDF>\n'
      '</x:xmpmeta>\n'
      '<?xpacket end="w"?>';
}

/// ISO 8601 without sub-seconds or zone (XMP treats a naive local time as
/// "local to where it was taken", which is exactly what EXIF gives us).
String _isoLocal(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// A language-alternative property (`<prop><rdf:Alt><rdf:li xml:lang=…>`).
String _langAlt(String prop, String value) =>
    '   <$prop>\n'
    '    <rdf:Alt>\n'
    '     <rdf:li xml:lang="x-default">${_escape(value)}</rdf:li>\n'
    '    </rdf:Alt>\n'
    '   </$prop>\n';

/// The `xmpRights:Marked` boolean for a free-text copyright status, or null
/// (don't assert it) for "unknown"/blank/anything non-canonical.
String? _markedValue(String status) => switch (status.trim().toLowerCase()) {
  'copyrighted' => 'True',
  'public domain' => 'False',
  _ => null,
};

/// Friendly `digitalSourceType` value → IPTC controlled-vocabulary URI.
const Map<String, String> _digitalSourceUris = {
  'photo': 'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
  'ai-generated':
      'http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia',
  'composite':
      'http://cv.iptc.org/newscodes/digitalsourcetype/compositeSynthetic',
};

/// Resolves a free-text source type to its IPTC URI: a known keyword maps to
/// its vocabulary URI, an already-URI value passes through, anything else is
/// dropped (null) so we never assert a bogus provenance claim.
String? _digitalSourceUri(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  if (v.startsWith('http')) return v;
  return _digitalSourceUris[v.toLowerCase()];
}

/// Maps an IPTC source-type URI back to its friendly keyword, or returns the
/// raw URI when it's outside our small keyword set.
String _digitalSourceFromUri(String uri) {
  for (final entry in _digitalSourceUris.entries) {
    if (entry.value == uri) return entry.key;
  }
  return uri.startsWith('http') ? uri : '';
}

/// The nested `Iptc4xmpCore:CreatorContactInfo` block (work address, phone,
/// email, URL). Returns null when every part is empty, so the caller can skip
/// the wrapper entirely.
String? _creatorContact({
  required String email,
  required String website,
  required String address,
  required String city,
  required String region,
  required String postalCode,
  required String country,
  required String phone,
}) {
  final parts = <String, String>{
    'CiAdrExtadr': address,
    'CiAdrCity': city,
    'CiAdrRegion': region,
    'CiAdrPcode': postalCode,
    'CiAdrCtry': country,
    'CiTelWork': phone,
    'CiEmailWork': email,
    'CiUrlWork': website,
  };
  if (parts.values.every((v) => v.isEmpty)) return null;
  final sb = StringBuffer()
    ..write('   <Iptc4xmpCore:CreatorContactInfo rdf:parseType="Resource">\n');
  for (final entry in parts.entries) {
    if (entry.value.isEmpty) continue;
    sb.write(
      '    <Iptc4xmpCore:${entry.key}>${_escape(entry.value)}'
      '</Iptc4xmpCore:${entry.key}>\n',
    );
  }
  return (sb..write('   </Iptc4xmpCore:CreatorContactInfo>\n')).toString();
}

/// The PLUS `plus:ImageSupplier` seq (a single supplier: name + ID). Returns
/// null when both parts are empty.
String? _imageSupplier(String name, String id) {
  if (name.isEmpty && id.isEmpty) return null;
  final sb = StringBuffer()
    ..write('   <plus:ImageSupplier>\n    <rdf:Seq>\n')
    ..write('     <rdf:li rdf:parseType="Resource">\n');
  if (name.isNotEmpty) {
    sb.write(
      '      <plus:ImageSupplierName>${_escape(name)}'
      '</plus:ImageSupplierName>\n',
    );
  }
  if (id.isNotEmpty) {
    sb.write(
      '      <plus:ImageSupplierID>${_escape(id)}</plus:ImageSupplierID>\n',
    );
  }
  return (sb
        ..write('     </rdf:li>\n    </rdf:Seq>\n   </plus:ImageSupplier>\n'))
      .toString();
}

/// The inner sub-fields of an `Iptc4xmpExt` Location structure (used by both
/// `LocationCreated` and each `LocationShown` entry). Emits only the non-empty
/// parts; `LocationId` is a Bag per the standard.
String _locationResource({
  String sublocation = '',
  String city = '',
  String state = '',
  String country = '',
  String countryCode = '',
  String worldRegion = '',
  String locationId = '',
}) {
  final sb = StringBuffer();
  void el(String prop, String value) {
    if (value.isNotEmpty) sb.write('    <$prop>${_escape(value)}</$prop>\n');
  }

  el('Iptc4xmpExt:Sublocation', sublocation);
  el('Iptc4xmpExt:City', city);
  el('Iptc4xmpExt:ProvinceState', state);
  el('Iptc4xmpExt:CountryName', country);
  el('Iptc4xmpExt:CountryCode', countryCode);
  el('Iptc4xmpExt:WorldRegion', worldRegion);
  if (locationId.isNotEmpty) {
    sb.write(
      '    <Iptc4xmpExt:LocationId>\n'
      '     <rdf:Bag><rdf:li>${_escape(locationId)}</rdf:li></rdf:Bag>\n'
      '    </Iptc4xmpExt:LocationId>\n',
    );
  }
  return sb.toString();
}

/// A repeatable structured property (`LocationShown`, `ArtworkOrObject`,
/// `ImageCreator`…): an rdf:Bag (or Seq) of `parseType="Resource"` entries.
/// [entries] are the pre-rendered inner XML per record; blank entries are
/// skipped, and the whole property is omitted when nothing remains.
String _structArray(
  String prop,
  List<String> entries, {
  required bool seq,
}) {
  final nonEmpty = [
    for (final e in entries)
      if (e.isNotEmpty) e,
  ];
  if (nonEmpty.isEmpty) return '';
  final container = seq ? 'Seq' : 'Bag';
  final lis = StringBuffer();
  for (final inner in nonEmpty) {
    lis.write('     <rdf:li rdf:parseType="Resource">\n$inner     </rdf:li>\n');
  }
  return '   <$prop>\n    <rdf:$container>\n$lis'
      '    </rdf:$container>\n   </$prop>\n';
}

/// The inner sub-elements of one `Iptc4xmpExt:ArtworkOrObject` entry.
String _artworkResource(IptcArtwork a) {
  final sb = StringBuffer();
  void el(String prop, String value) {
    if (value.isNotEmpty) sb.write('    <$prop>${_escape(value)}</$prop>\n');
  }

  el('Iptc4xmpExt:AOTitle', a.title);
  el('Iptc4xmpExt:AOCreator', a.creator);
  el('Iptc4xmpExt:AOSource', a.source);
  el('Iptc4xmpExt:AOCopyrightNotice', a.copyrightNotice);
  return sb.toString();
}

/// The inner sub-elements of one PLUS entity (image creator / copyright owner),
/// using the given name/ID property locals under the `plus:` namespace.
String _entityResource(IptcEntity e, String nameProp, String idProp) {
  final sb = StringBuffer();
  void el(String prop, String value) {
    if (value.isNotEmpty) {
      sb.write('    <plus:$prop>${_escape(value)}</plus:$prop>\n');
    }
  }

  el(nameProp, e.name);
  el(idProp, e.identifier);
  return sb.toString();
}

/// The inner sub-elements of one `plus:Licensor` entry.
String _licensorResource(IptcLicensor l) {
  final sb = StringBuffer();
  void el(String prop, String value) {
    if (value.isNotEmpty) {
      sb.write('    <plus:$prop>${_escape(value)}</plus:$prop>\n');
    }
  }

  el('LicensorName', l.name);
  el('LicensorID', l.id);
  el('LicensorTelephone1', l.phone);
  el('LicensorEmail', l.email);
  el('LicensorURL', l.url);
  return sb.toString();
}

/// The inner sub-elements of one `Iptc4xmpExt:RegistryId` entry.
String _registryResource(IptcRegistryEntry r) {
  final sb = StringBuffer();
  void el(String prop, String value) {
    if (value.isNotEmpty) {
      sb.write(
        '    <Iptc4xmpExt:$prop>${_escape(value)}</Iptc4xmpExt:$prop>\n',
      );
    }
  }

  el('RegItemId', r.itemId);
  el('RegOrgId', r.organisationId);
  return sb.toString();
}

/// Splits a comma-separated field into its trimmed, non-empty values.
List<String> _splitComma(String csv) => [
  for (final v in csv.split(','))
    if (v.trim().isNotEmpty) v.trim(),
];

/// An unordered-bag property (`<prop><rdf:Bag><rdf:li>…`).
String _bag(String prop, List<String> values) {
  final lis = values
      .map((v) => '     <rdf:li>${_escape(v)}</rdf:li>')
      .join('\n');
  return '   <$prop>\n    <rdf:Bag>\n$lis\n    </rdf:Bag>\n   </$prop>\n';
}

/// An ordered-sequence property (`<prop><rdf:Seq><rdf:li>`).
String _seq(String prop, String value) =>
    '   <$prop>\n'
    '    <rdf:Seq>\n'
    '     <rdf:li>${_escape(value)}</rdf:li>\n'
    '    </rdf:Seq>\n'
    '   </$prop>\n';

/// Parses an XMP packet back into [XmpData]. Tolerant of namespace prefixes and
/// missing fields; returns defaults for anything absent. Plain IPTC fields are
/// read from either an attribute or an element (Lightroom/Bridge write elements).
XmpData decodeXmp(String source) {
  final doc = XmlDocument.parse(source);
  final desc = doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'Description')
      .firstOrNull;
  if (desc == null) return const XmpData();

  String? attr(String local) {
    for (final a in desc.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  // The repeatable structured arrays. Their record sub-fields (a LocationShown
  // entry's City, a Licensor's LicensorName…) must never satisfy a *flat*
  // field's element lookup — a sidecar whose only city is inside LocationShown
  // has no flat city. LocationCreated is deliberately absent: it's singular,
  // so its parts are a legitimate fallback source for the flat location.
  const structuredArrays = {
    'LocationShown',
    'ArtworkOrObject',
    'ImageCreator',
    'CopyrightOwner',
    'Licensor',
    'RegistryId',
  };
  bool inStructuredArray(XmlElement e) => e.ancestors
      .whereType<XmlElement>()
      .any((a) => structuredArrays.contains(a.name.local));

  // The first element in the doc whose local name matches — used for the plain
  // IPTC fields when they're written as elements rather than attributes.
  // Skips anything nested in a repeatable structured array (see above).
  XmlElement? element(String local) => doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == local && !inStructuredArray(e))
      .firstOrNull;

  // A plain string property: attribute form first, else a leaf element's text.
  String simple(String local) {
    final a = attr(local);
    if (a != null && a.isNotEmpty) return a;
    final el = element(local);
    if (el != null && el.childElements.isEmpty) {
      final text = el.innerText.trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  // Every non-empty `rdf:li` text under the element named [parentLocal].
  List<String> lisUnder(String parentLocal) {
    final parent = element(parentLocal);
    if (parent == null) return const [];
    return parent.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'li')
        .map((e) => e.innerText.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // A language-alternative (or bare) field: first `rdf:li`, else leaf text.
  String langAltOrSimple(String local) {
    final lis = lisUnder(local);
    return lis.isNotEmpty ? lis.first : simple(local);
  }

  // The direct `rdf:li` entries of the Bag/Seq inside [parentLocal] — one per
  // structured record (not the li's nested inside a record, e.g. LocationId).
  List<XmlElement> itemsUnder(String parentLocal) {
    final parent = element(parentLocal);
    if (parent == null) return const [];
    final container = parent.childElements
        .where((e) => e.name.local == 'Bag' || e.name.local == 'Seq')
        .firstOrNull;
    if (container == null) return const [];
    return container.childElements.where((e) => e.name.local == 'li').toList();
  }

  // A named sub-field's text within one structured record [item]: a leaf
  // element's text, else the first nested `rdf:li` (langAlt / Bag) text.
  String childOf(XmlElement item, String local) {
    for (final e in item.descendants.whereType<XmlElement>()) {
      if (e.name.local != local) continue;
      if (e.childElements.isEmpty) {
        final t = e.innerText.trim();
        if (t.isNotEmpty) return t;
      } else {
        final li = e.descendants
            .whereType<XmlElement>()
            .where((x) => x.name.local == 'li')
            .firstOrNull;
        final t = li?.innerText.trim() ?? '';
        if (t.isNotEmpty) return t;
      }
    }
    return '';
  }

  // A part of the created-location struct, scoped so a LocationShown entry's
  // WorldRegion/LocationId never leaks into the flat created-location fields.
  final created = element('LocationCreated');
  String createdPart(String local) =>
      created == null ? '' : childOf(created, local);

  final locationsShown = [
    for (final item in itemsUnder('LocationShown'))
      IptcLocation(
        sublocation: childOf(item, 'Sublocation'),
        city: childOf(item, 'City'),
        state: childOf(item, 'ProvinceState'),
        country: childOf(item, 'CountryName'),
        countryCode: childOf(item, 'CountryCode'),
        worldRegion: childOf(item, 'WorldRegion'),
        locationId: childOf(item, 'LocationId'),
      ),
  ].where((l) => !l.isEmpty).toList();

  final artwork = [
    for (final item in itemsUnder('ArtworkOrObject'))
      IptcArtwork(
        title: childOf(item, 'AOTitle'),
        creator: childOf(item, 'AOCreator'),
        source: childOf(item, 'AOSource'),
        copyrightNotice: childOf(item, 'AOCopyrightNotice'),
      ),
  ].where((a) => !a.isEmpty).toList();

  final imageCreators = [
    for (final item in itemsUnder('ImageCreator'))
      IptcEntity(
        name: childOf(item, 'ImageCreatorName'),
        identifier: childOf(item, 'ImageCreatorID'),
      ),
  ].where((e) => !e.isEmpty).toList();

  final licensors = [
    for (final item in itemsUnder('Licensor'))
      IptcLicensor(
        name: childOf(item, 'LicensorName'),
        id: childOf(item, 'LicensorID'),
        phone: childOf(item, 'LicensorTelephone1'),
        email: childOf(item, 'LicensorEmail'),
        url: childOf(item, 'LicensorURL'),
      ),
  ].where((l) => !l.isEmpty).toList();

  final registryEntries = [
    for (final item in itemsUnder('RegistryId'))
      IptcRegistryEntry(
        itemId: childOf(item, 'RegItemId'),
        organisationId: childOf(item, 'RegOrgId'),
      ),
  ].where((r) => !r.isEmpty).toList();

  final copyrightOwners = [
    for (final item in itemsUnder('CopyrightOwner'))
      IptcEntity(
        name: childOf(item, 'CopyrightOwnerName'),
        identifier: childOf(item, 'CopyrightOwnerID'),
      ),
  ].where((e) => !e.isEmpty).toList();

  final creatorLis = lisUnder('creator');
  final iptc = IptcCore(
    caption: langAltOrSimple('description'),
    headline: simple('Headline'),
    creator: creatorLis.isNotEmpty ? creatorLis.join(', ') : simple('creator'),
    authorTitle: simple('AuthorsPosition'),
    copyright: langAltOrSimple('rights'),
    credit: simple('Credit'),
    source: simple('Source'),
    instructions: simple('Instructions'),
    location: simple('Location'),
    city: simple('City'),
    state: simple('State'),
    country: simple('Country'),
    countryCode: simple('CountryCode'),
    altText: langAltOrSimple('AltTextAccessibility'),
    subjectCodes: lisUnder('SubjectCode').join(', '),
    title: langAltOrSimple('title'),
    creatorEmail: simple('CiEmailWork'),
    creatorWebsite: simple('CiUrlWork'),
    creatorAddress: simple('CiAdrExtadr'),
    creatorCity: simple('CiAdrCity'),
    creatorRegion: simple('CiAdrRegion'),
    creatorPostalCode: simple('CiAdrPcode'),
    creatorCountry: simple('CiAdrCtry'),
    creatorPhone: simple('CiTelWork'),
    dateCreated: simple('DateCreated'),
    additionalModelInfo: simple('AddlModelInfo'),
    modelAge: lisUnder('ModelAge').join(', '),
    minorModelAgeDisclosure: simple('MinorModelAgeDisclosure'),
    imageSupplierName: simple('ImageSupplierName'),
    imageSupplierId: simple('ImageSupplierID'),
    imageSupplierImageId: simple('ImageSupplierImageID'),
    digImageGuid: simple('DigImageGUID'),
    copyrightStatus: _statusFromMarked(simple('Marked')),
    usageTerms: langAltOrSimple('UsageTerms'),
    webStatement: simple('WebStatement'),
    jobId: simple('TransmissionReference'),
    digitalSourceType: _digitalSourceFromUri(simple('DigitalSourceType')),
    aiSystemUsed: simple('AISystemUsed'),
    aiSystemVersion: simple('AISystemVersionUsed'),
    aiPromptInfo: simple('AIPromptInformation'),
    aiPromptWriter: simple('AIPromptWriterName'),
    descriptionWriters: simple('CaptionWriter'),
    personsShown: lisUnder('PersonInImage').join(', '),
    featuredOrgName: lisUnder('OrganisationInImageName').join(', '),
    featuredOrgCode: lisUnder('OrganisationInImageCode').join(', '),
    intellectualGenre: simple('IntellectualGenre'),
    iptcScene: lisUnder('Scene').join(', '),
    event: langAltOrSimple('Event'),
    category: simple('Category'),
    supplementalCategories: lisUnder('SupplementalCategories').join(', '),
    urgency: simple('Urgency'),
    editStatus: simple('EditStatus'),
    worldRegion: createdPart('WorldRegion'),
    locationId: createdPart('LocationId'),
    modelReleaseStatus: simple('ModelReleaseStatus'),
    modelReleaseIds: lisUnder('ModelReleaseID').join(', '),
    propertyReleaseStatus: simple('PropertyReleaseStatus'),
    propertyReleaseIds: lisUnder('PropertyReleaseID').join(', '),
    locationsShown: locationsShown,
    artwork: artwork,
    imageCreators: imageCreators,
    copyrightOwners: copyrightOwners,
    licensors: licensors,
    registryEntries: registryEntries,
  );

  return XmpData(
    rating: int.tryParse(attr('Rating') ?? '') ?? 0,
    color: _labelFromXmp(attr('Label')),
    flag: _flagFromXmp(attr('flag')),
    keywords: lisUnder('subject'),
    iptc: iptc,
    dateCreated: DateTime.tryParse(simple('DateCreated')),
    orientation: _orientationFromXmp(attr('Orientation')),
    crop: _cropFromXmp(attr),
  );
}

/// Parses `tiff:Orientation` back to a 1–8 value, or null when absent/invalid.
int? _orientationFromXmp(String? raw) {
  final n = int.tryParse(raw?.trim() ?? '');
  return (n != null && n >= 1 && n <= 8) ? n : null;
}

/// Reads a Lightroom/Camera-Raw crop (`crs:HasCrop` + `crs:Crop*`) via the
/// packet's [attr] lookup. Returns null unless `HasCrop` is true and the four
/// edges parse — Cullimingo only displays this, so a partial record is ignored.
///
/// Skips the crop when `crs:AlreadyApplied="True"`: that marks a rendered
/// derivative (e.g. a Lightroom-exported JPEG) whose pixels are *already*
/// cropped, while the crop rectangle still describes the un-cropped original.
/// Overlaying it on the baked-in result would dim valid image content.
CropRect? _cropFromXmp(String? Function(String) attr) {
  if ((attr('HasCrop') ?? '').trim().toLowerCase() != 'true') return null;
  final applied = (attr('AlreadyApplied') ?? '').trim().toLowerCase() == 'true';
  if (applied) return null;
  final left = double.tryParse(attr('CropLeft') ?? '');
  final top = double.tryParse(attr('CropTop') ?? '');
  final right = double.tryParse(attr('CropRight') ?? '');
  final bottom = double.tryParse(attr('CropBottom') ?? '');
  if (left == null || top == null || right == null || bottom == null) {
    return null;
  }
  return CropRect(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    angle: double.tryParse(attr('CropAngle') ?? '') ?? 0,
  );
}

/// Maps `xmpRights:Marked` back to a readable copyright status.
String _statusFromMarked(String marked) =>
    switch (marked.trim().toLowerCase()) {
      'true' => 'copyrighted',
      'false' => 'public domain',
      _ => '',
    };

ColorLabel _labelFromXmp(String? raw) {
  if (raw == null) return ColorLabel.none;
  final lower = raw.trim().toLowerCase();
  for (final entry in _labelToXmp.entries) {
    if (entry.value.toLowerCase() == lower) return entry.key;
  }
  return ColorLabel.none;
}

PickFlag _flagFromXmp(String? raw) => switch (raw?.trim().toLowerCase()) {
  'pick' => PickFlag.pick,
  'reject' => PickFlag.reject,
  _ => PickFlag.none,
};

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
