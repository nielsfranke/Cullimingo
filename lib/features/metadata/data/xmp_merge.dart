import 'package:cullimingo/features/metadata/data/xmp_codec.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:xml/xml.dart';

// The namespace URIs encodeXmp writes under.
const String _nsXmp = 'http://ns.adobe.com/xap/1.0/';
const String _nsDc = 'http://purl.org/dc/elements/1.1/';
const String _nsPhotoshop = 'http://ns.adobe.com/photoshop/1.0/';
const String _nsIptcCore = 'http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/';
const String _nsIptcExt = 'http://iptc.org/std/Iptc4xmpExt/2008-02-29/';
const String _nsXmpRights = 'http://ns.adobe.com/xap/1.0/rights/';
const String _nsPlus = 'http://ns.useplus.org/ldf/xmp/1.0/';
const String _nsTiff = 'http://ns.adobe.com/tiff/1.0/';

/// The reserved `xml:` namespace (for `xml:lang`), bound in every document.
const String _nsXml = 'http://www.w3.org/XML/1998/namespace';

/// Every property [encodeXmp] can write, keyed by namespace URI. A merge
/// removes exactly these from the existing packet — attribute *or* element
/// form, wherever they live — and re-adds the current values. Everything else
/// (`crs:*` develop settings and crop, GPS, `lr:hierarchicalSubject`, …) is
/// foreign and passes through untouched. Keep this in sync with [encodeXmp]:
/// a property written but not listed here duplicates on every merge; one
/// listed but no longer written can never be cleared.
const Map<String, Set<String>> _ownedByNs = {
  _nsXmp: {'Rating', 'Label'},
  kCullimingoNs: {'flag', 'StackId', 'EditStatus'},
  _nsTiff: {'Orientation'},
  _nsDc: {'subject', 'description', 'title', 'rights', 'creator'},
  _nsPhotoshop: {
    'DateCreated',
    'Headline',
    'AuthorsPosition',
    'Credit',
    'Source',
    'Instructions',
    'City',
    'State',
    'Country',
    'TransmissionReference',
    'CaptionWriter',
    'Category',
    'Urgency',
    'SupplementalCategories',
  },
  _nsIptcCore: {
    'Location',
    'CountryCode',
    'IntellectualGenre',
    'AltTextAccessibility',
    'SubjectCode',
    'Scene',
    'CreatorContactInfo',
  },
  _nsIptcExt: {
    'AISystemUsed',
    'AISystemVersionUsed',
    'AIPromptInformation',
    'AIPromptWriterName',
    'AddlModelInfo',
    'DigImageGUID',
    'DigitalSourceType',
    'PersonInImage',
    'OrganisationInImageName',
    'OrganisationInImageCode',
    'Event',
    'ModelAge',
    'LocationCreated',
    'LocationShown',
    'ArtworkOrObject',
    'RegistryId',
  },
  _nsXmpRights: {'WebStatement', 'Marked', 'UsageTerms'},
  _nsPlus: {
    'ModelReleaseStatus',
    'PropertyReleaseStatus',
    'MinorModelAgeDisclosure',
    'ImageSupplierImageID',
    'ImageSupplier',
    'ImageCreator',
    'CopyrightOwner',
    'Licensor',
    'ModelReleaseID',
    'PropertyReleaseID',
  },
};

/// Preferred prefixes when the existing packet has no binding of its own.
const Map<String, String> _canonicalPrefix = {
  _nsXmp: 'xmp',
  kCullimingoNs: 'cullimingo',
  _nsTiff: 'tiff',
  _nsDc: 'dc',
  _nsPhotoshop: 'photoshop',
  _nsIptcCore: 'Iptc4xmpCore',
  _nsIptcExt: 'Iptc4xmpExt',
  _nsXmpRights: 'xmpRights',
  _nsPlus: 'plus',
  'http://www.w3.org/1999/02/22-rdf-syntax-ns#': 'rdf',
};

/// Rewrites [existing] (a full XMP packet) so it carries [data]'s values for
/// every Cullimingo-owned property while leaving all foreign properties —
/// Lightroom develop settings, GPS, hierarchical keywords, anything we don't
/// model — untouched. This is what makes a rating keystroke safe on a sidecar
/// that Lightroom or Capture One also writes to.
///
/// Owned properties are matched by namespace URI + local name in both
/// attribute and element form, across every top-level `rdf:Description`
/// (exiftool splits them per namespace). The fresh values land on the first
/// description. Throws on unparseable input — callers fall back to a fresh
/// [encodeXmp] packet, matching how readers treat a corrupt sidecar.
String mergeXmp(String existing, XmpData data) {
  final doc = XmlDocument.parse(existing);
  // Top-level descriptions only: rdf:Description also appears *inside*
  // foreign structured properties (a crs mask, an exiftool struct), and those
  // inner ones must never be stripped.
  final descs = [
    for (final el in doc.descendants.whereType<XmlElement>())
      if (el.name.local == 'Description' &&
          el.parent is XmlElement &&
          (el.parent! as XmlElement).name.local == 'RDF')
        el,
  ];
  if (descs.isEmpty) {
    throw const FormatException('XMP packet has no rdf:Description');
  }

  bool owned(String? uri, String local) =>
      uri != null && (_ownedByNs[uri]?.contains(local) ?? false);

  for (final desc in descs) {
    desc.attributes.removeWhere(
      (a) => owned(_attributeUri(desc, a), a.name.local),
    );
    desc.children.removeWhere(
      (c) => c is XmlElement && owned(_elementUri(c), c.name.local),
    );
  }

  // Render the current values as a fresh packet and graft its description's
  // attributes and children onto the first existing description, translating
  // prefixes into the target document's bindings.
  final freshDesc = XmlDocument.parse(encodeXmp(data)).descendants
      .whereType<XmlElement>()
      .firstWhere((e) => e.name.local == 'Description');
  final target = descs.first;

  // In-scope bindings at the target; `namespaces` yields nearest-first, so
  // putIfAbsent keeps the innermost prefix per URI. The default namespace
  // (empty prefix) is unusable for our prefixed properties, so it's skipped.
  final byPrefix = <String, String>{};
  final byUri = <String, String>{};
  for (final n in target.namespaces) {
    byPrefix.putIfAbsent(n.prefix, () => n.uri);
    if (n.prefix.isNotEmpty) byUri.putIfAbsent(n.uri, () => n.prefix);
  }

  String? prefixFor(String? uri) {
    if (uri == null || uri.isEmpty) return null;
    if (uri == _nsXml) return 'xml';
    final bound = byUri[uri];
    if (bound != null) return bound;
    final base = _canonicalPrefix[uri] ?? 'ns';
    var pick = base;
    var n = 1;
    while (byPrefix.containsKey(pick)) {
      pick = '$base${++n}';
    }
    target.attributes.add(XmlAttribute(XmlName.namespace(name: pick), uri));
    byPrefix[pick] = uri;
    byUri[uri] = pick;
    return pick;
  }

  XmlElement graft(XmlElement e) => XmlElement(
    XmlName.parts(e.name.local, prefix: prefixFor(_elementUri(e))),
    [
      for (final a in e.attributes)
        if (!_isXmlnsDeclaration(a))
          XmlAttribute(
            XmlName.parts(a.name.local, prefix: prefixFor(_attributeUri(e, a))),
            a.value,
          ),
    ],
    [
      for (final c in e.children)
        if (c is XmlElement) graft(c) else if (c is XmlText) XmlText(c.value),
    ],
  );

  for (final a in freshDesc.attributes) {
    if (_isXmlnsDeclaration(a)) continue;
    if (a.name.local == 'about') continue; // the target keeps its own rdf:about
    target.attributes.add(
      XmlAttribute(
        XmlName.parts(
          a.name.local,
          prefix: prefixFor(_attributeUri(freshDesc, a)),
        ),
        a.value,
      ),
    );
  }
  for (final c in freshDesc.childElements) {
    target.children.add(graft(c));
  }
  return doc.toXmlString();
}

bool _isXmlnsDeclaration(XmlAttribute a) =>
    a.name.prefix == 'xmlns' || a.name.qualified == 'xmlns';

// xml 7 does not resolve namespace URIs at parse time, so look the prefix up
// in the node's in-scope bindings (nearest declaration wins).
String? _elementUri(XmlElement e) =>
    e.name.namespaceUri ?? _lookupPrefix(e, e.name.prefix ?? '');

// Per the XML spec an unprefixed attribute has *no* namespace (the default
// namespace does not apply to attributes).
String? _attributeUri(XmlElement owner, XmlAttribute a) {
  final prefix = a.name.prefix;
  if (prefix == null) return a.name.namespaceUri;
  return a.name.namespaceUri ?? _lookupPrefix(owner, prefix);
}

String? _lookupPrefix(XmlElement scope, String prefix) {
  for (final n in scope.namespaces) {
    if (n.prefix == prefix) return n.uri;
  }
  return null;
}
