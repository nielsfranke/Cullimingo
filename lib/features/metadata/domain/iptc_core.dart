import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';

/// The three sections the IPTC fields group into, in the order a journalist
/// fills them: what the photo shows, where it was taken, who to credit.
enum IptcFieldGroup {
  /// Caption / headline / alt-text — what the photo shows.
  description('Description'),

  /// Sub-location / city / state / country — where it was taken.
  location('Location'),

  /// Creator / credit / copyright / instructions — who to credit and rights.
  credit('Credit & rights'),

  /// Editorial workflow — category, urgency, edit status (legacy IIM).
  status('Status'),

  /// Model / property release status + IDs (PLUS).
  releases('Models & releases'),

  /// Digital source type + AI system/prompt — provenance (IPTC 2025.1).
  ai('AI & provenance');

  const IptcFieldGroup(this.label);

  /// Section header text.
  final String label;
}

/// Every editable IPTC Core field, in display order, with its label, section
/// and whether it wants a multi-line editor. Drives both the read-only
/// inspector display and the editor form so the two never drift apart. The enum
/// name doubles as the JSON storage key (see [IptcCore.toJson]).
enum IptcField {
  /// Caption / description.
  caption('Caption', IptcFieldGroup.description, multiline: true),

  /// Headline.
  headline('Headline', IptcFieldGroup.description),

  /// Date the photo was created (`photoshop:DateCreated`). Stored as an ISO
  /// 8601 local string; empty means "use the capture time". Rendered with a
  /// date/time picker, not a plain text field.
  dateCreated('Date created', IptcFieldGroup.description, mergeable: false),

  /// Title / object name — the story slug (AP uses this).
  title('Title / Slug', IptcFieldGroup.description),

  /// Alt-text for accessibility.
  altText('Alt text', IptcFieldGroup.description, multiline: true),

  /// IPTC Media Topics / subject codes (comma-separated `medtop:` QCodes).
  subjectCodes('Media topics', IptcFieldGroup.description, mergeable: false),

  /// Who wrote the caption / description (`photoshop:CaptionWriter`).
  descriptionWriters('Description writers', IptcFieldGroup.description),

  /// People shown in the image (comma-separated `Iptc4xmpExt:PersonInImage`).
  personsShown('Persons shown', IptcFieldGroup.description, mergeable: false),

  /// Featured organisation names (comma-separated).
  featuredOrgName('Featured org', IptcFieldGroup.description, mergeable: false),

  /// Featured organisation codes (comma-separated).
  featuredOrgCode(
    'Featured org code',
    IptcFieldGroup.description,
    mergeable: false,
  ),

  /// Intellectual genre — the nature of the item
  /// (`Iptc4xmpCore:IntellectualGenre`).
  intellectualGenre('Intellectual genre', IptcFieldGroup.description),

  /// IPTC scene codes (comma-separated `Iptc4xmpCore:Scene`).
  iptcScene('IPTC scene', IptcFieldGroup.description, mergeable: false),

  /// The event the image documents (`Iptc4xmpExt:Event`).
  event('Event', IptcFieldGroup.location),

  /// Sub-location within the city.
  location('Sublocation', IptcFieldGroup.location),

  /// City.
  city('City', IptcFieldGroup.location),

  /// Province / state.
  state('State / Province', IptcFieldGroup.location),

  /// Country name.
  country('Country', IptcFieldGroup.location),

  /// ISO country code.
  countryCode('ISO code', IptcFieldGroup.location, mergeable: false),

  /// World region — the created location's continent/region
  /// (`Iptc4xmpExt:LocationCreated/Iptc4xmpExt:WorldRegion`).
  worldRegion('World region', IptcFieldGroup.location),

  /// Location identifier for the created location
  /// (`Iptc4xmpExt:LocationCreated/Iptc4xmpExt:LocationId`).
  locationId('Location ID', IptcFieldGroup.location, mergeable: false),

  /// Creator / photographer.
  creator('Creator', IptcFieldGroup.credit),

  /// Creator's job title.
  authorTitle('Job title', IptcFieldGroup.credit),

  /// Creator's work email (contact info).
  creatorEmail('Creator email', IptcFieldGroup.credit),

  /// Creator's work website (contact info).
  creatorWebsite('Creator website', IptcFieldGroup.credit),

  /// Creator's work postal address (`CreatorContactInfo/CiAdrExtadr`).
  creatorAddress('Creator address', IptcFieldGroup.credit, multiline: true),

  /// Creator's work city (`CreatorContactInfo/CiAdrCity`).
  creatorCity('Creator city', IptcFieldGroup.credit),

  /// Creator's work state/region (`CreatorContactInfo/CiAdrRegion`).
  creatorRegion('Creator state/region', IptcFieldGroup.credit),

  /// Creator's work postal code (`CreatorContactInfo/CiAdrPcode`).
  creatorPostalCode('Creator postcode', IptcFieldGroup.credit),

  /// Creator's work country (`CreatorContactInfo/CiAdrCtry`).
  creatorCountry('Creator country', IptcFieldGroup.credit),

  /// Creator's work phone (`CreatorContactInfo/CiTelWork`).
  creatorPhone('Creator phone', IptcFieldGroup.credit),

  /// Credit line.
  credit('Credit', IptcFieldGroup.credit),

  /// Original owner / source.
  source('Source', IptcFieldGroup.credit),

  /// Copyright notice.
  copyright('Copyright', IptcFieldGroup.credit),

  /// Copyright status (copyrighted / public domain).
  copyrightStatus('Copyright status', IptcFieldGroup.credit, mergeable: false),

  /// Rights usage terms — how the image may be used.
  usageTerms('Usage terms', IptcFieldGroup.credit, multiline: true),

  /// Web statement of rights — the rights/licensing URL.
  webStatement('Rights URL', IptcFieldGroup.credit),

  /// Special instructions / handling notes.
  instructions('Instructions', IptcFieldGroup.credit, multiline: true),

  /// Job identifier / transmission reference — the wire routing/story ID.
  jobId('Job ID / Transmission', IptcFieldGroup.credit),

  /// Image supplier name (`plus:ImageSupplier/ImageSupplierName`).
  imageSupplierName('Image supplier', IptcFieldGroup.credit),

  /// Image supplier identifier (`plus:ImageSupplier/ImageSupplierID`).
  imageSupplierId('Supplier ID', IptcFieldGroup.credit, mergeable: false),

  /// Supplier's own ID for the image (`plus:ImageSupplierImageID`).
  imageSupplierImageId(
    'Supplier image ID',
    IptcFieldGroup.credit,
    mergeable: false,
  ),

  /// Category — a legacy 3-letter subject abbreviation (`photoshop:Category`).
  category('Category', IptcFieldGroup.status, mergeable: false),

  /// Supplemental categories, comma-separated
  /// (`photoshop:SupplementalCategories`).
  supplementalCategories(
    'Supplemental categories',
    IptcFieldGroup.status,
    mergeable: false,
  ),

  /// Urgency / editorial priority, 0–8 (`photoshop:Urgency`).
  urgency('Urgency', IptcFieldGroup.status, mergeable: false),

  /// Edit status — a free-text workflow note (legacy IIM 2:07).
  editStatus('Edit status', IptcFieldGroup.status),

  /// Globally-unique image identifier (`Iptc4xmpExt:DigImageGUID`).
  digImageGuid('Image GUID', IptcFieldGroup.status, mergeable: false),

  /// Model release status (`plus:ModelReleaseStatus`).
  modelReleaseStatus('Model release', IptcFieldGroup.releases),

  /// Model release document IDs, comma-separated (`plus:ModelReleaseID`).
  modelReleaseIds(
    'Model release IDs',
    IptcFieldGroup.releases,
    mergeable: false,
  ),

  /// Property release status (`plus:PropertyReleaseStatus`).
  propertyReleaseStatus('Property release', IptcFieldGroup.releases),

  /// Property release document IDs, comma-separated (`plus:PropertyReleaseID`).
  propertyReleaseIds(
    'Property release IDs',
    IptcFieldGroup.releases,
    mergeable: false,
  ),

  /// Free-text notes about the model(s) (`Iptc4xmpExt:AddlModelInfo`).
  additionalModelInfo(
    'Additional model info',
    IptcFieldGroup.releases,
    multiline: true,
  ),

  /// Age(s) of the model(s), comma-separated (`Iptc4xmpExt:ModelAge`, a Bag).
  modelAge('Model age', IptcFieldGroup.releases, mergeable: false),

  /// Minor model age disclosure (`plus:MinorModelAgeDisclosure`).
  minorModelAgeDisclosure(
    'Minor model age disclosure',
    IptcFieldGroup.releases,
    mergeable: false,
  ),

  /// Digital source type — photo / ai-generated / composite (IPTC 2025.1).
  digitalSourceType('Source type', IptcFieldGroup.ai, mergeable: false),

  /// Name of the AI system used, if any.
  aiSystemUsed('AI system', IptcFieldGroup.ai),

  /// Version of the AI system used.
  aiSystemVersion('AI system version', IptcFieldGroup.ai),

  /// The prompt used to generate/edit the image.
  aiPromptInfo('AI prompt', IptcFieldGroup.ai, multiline: true),

  /// Who wrote the AI prompt.
  aiPromptWriter('AI prompt writer', IptcFieldGroup.ai);

  const IptcField(
    this.label,
    this.group, {
    this.multiline = false,
    this.mergeable = true,
  });

  /// Human-readable field label.
  final String label;

  /// The section this field belongs to.
  final IptcFieldGroup group;

  /// Whether the editor should render a multi-line text area.
  final bool multiline;

  /// Whether a template may Prefix/Append this field's value (free text), or
  /// only Replace it. False for comma-separated bags (media topics, persons,
  /// scenes…) and controlled-vocabulary codes, where splicing text with a space
  /// would corrupt the value.
  final bool mergeable;
}

/// The descriptive IPTC Core fields that travel in an XMP sidecar alongside the
/// cull marks (`XmpData`). Unlike the cull marks, these are the fields a
/// photojournalist captions with: who/what/where, credit and rights. They
/// round-trip with Capture One / Lightroom / Bridge via the standard `dc:`,
/// `photoshop:` and `Iptc4xmpCore:` namespaces.
///
/// Part of the journalist captioning track (`BUILD_PLAN.md` Phase 9, Layer 1 —
/// an extension of the green Phase 4 sidecar engine).
class IptcCore {
  /// Creates an IPTC Core payload; every field defaults to empty.
  const IptcCore({
    this.caption = '',
    this.headline = '',
    this.creator = '',
    this.authorTitle = '',
    this.copyright = '',
    this.credit = '',
    this.source = '',
    this.instructions = '',
    this.location = '',
    this.city = '',
    this.state = '',
    this.country = '',
    this.countryCode = '',
    this.altText = '',
    this.subjectCodes = '',
    this.title = '',
    this.creatorEmail = '',
    this.creatorWebsite = '',
    this.creatorAddress = '',
    this.creatorCity = '',
    this.creatorRegion = '',
    this.creatorPostalCode = '',
    this.creatorCountry = '',
    this.creatorPhone = '',
    this.dateCreated = '',
    this.additionalModelInfo = '',
    this.modelAge = '',
    this.minorModelAgeDisclosure = '',
    this.imageSupplierName = '',
    this.imageSupplierId = '',
    this.imageSupplierImageId = '',
    this.digImageGuid = '',
    this.copyrightStatus = '',
    this.usageTerms = '',
    this.webStatement = '',
    this.jobId = '',
    this.digitalSourceType = '',
    this.aiSystemUsed = '',
    this.aiSystemVersion = '',
    this.aiPromptInfo = '',
    this.aiPromptWriter = '',
    this.descriptionWriters = '',
    this.personsShown = '',
    this.featuredOrgName = '',
    this.featuredOrgCode = '',
    this.intellectualGenre = '',
    this.iptcScene = '',
    this.event = '',
    this.category = '',
    this.supplementalCategories = '',
    this.urgency = '',
    this.editStatus = '',
    this.worldRegion = '',
    this.locationId = '',
    this.modelReleaseStatus = '',
    this.modelReleaseIds = '',
    this.propertyReleaseStatus = '',
    this.propertyReleaseIds = '',
    this.locationsShown = const [],
    this.artwork = const [],
    this.imageCreators = const [],
    this.copyrightOwners = const [],
    this.licensors = const [],
    this.registryEntries = const [],
  });

  /// Rebuilds an [IptcCore] from the compact map written by [toJson]; missing
  /// keys default to empty.
  factory IptcCore.fromJson(Map<String, dynamic> json) {
    String s(String key) => json[key] as String? ?? '';
    return IptcCore(
      caption: s('caption'),
      headline: s('headline'),
      creator: s('creator'),
      authorTitle: s('authorTitle'),
      copyright: s('copyright'),
      credit: s('credit'),
      source: s('source'),
      instructions: s('instructions'),
      location: s('location'),
      city: s('city'),
      state: s('state'),
      country: s('country'),
      countryCode: s('countryCode'),
      altText: s('altText'),
      subjectCodes: s('subjectCodes'),
      title: s('title'),
      creatorEmail: s('creatorEmail'),
      creatorWebsite: s('creatorWebsite'),
      creatorAddress: s('creatorAddress'),
      creatorCity: s('creatorCity'),
      creatorRegion: s('creatorRegion'),
      creatorPostalCode: s('creatorPostalCode'),
      creatorCountry: s('creatorCountry'),
      creatorPhone: s('creatorPhone'),
      dateCreated: s('dateCreated'),
      additionalModelInfo: s('additionalModelInfo'),
      modelAge: s('modelAge'),
      minorModelAgeDisclosure: s('minorModelAgeDisclosure'),
      imageSupplierName: s('imageSupplierName'),
      imageSupplierId: s('imageSupplierId'),
      imageSupplierImageId: s('imageSupplierImageId'),
      digImageGuid: s('digImageGuid'),
      copyrightStatus: s('copyrightStatus'),
      usageTerms: s('usageTerms'),
      webStatement: s('webStatement'),
      jobId: s('jobId'),
      digitalSourceType: s('digitalSourceType'),
      aiSystemUsed: s('aiSystemUsed'),
      aiSystemVersion: s('aiSystemVersion'),
      aiPromptInfo: s('aiPromptInfo'),
      aiPromptWriter: s('aiPromptWriter'),
      descriptionWriters: s('descriptionWriters'),
      personsShown: s('personsShown'),
      featuredOrgName: s('featuredOrgName'),
      featuredOrgCode: s('featuredOrgCode'),
      intellectualGenre: s('intellectualGenre'),
      iptcScene: s('iptcScene'),
      event: s('event'),
      category: s('category'),
      supplementalCategories: s('supplementalCategories'),
      urgency: s('urgency'),
      editStatus: s('editStatus'),
      worldRegion: s('worldRegion'),
      locationId: s('locationId'),
      modelReleaseStatus: s('modelReleaseStatus'),
      modelReleaseIds: s('modelReleaseIds'),
      propertyReleaseStatus: s('propertyReleaseStatus'),
      propertyReleaseIds: s('propertyReleaseIds'),
      locationsShown: parseRecords(
        json['locationsShown'],
        IptcLocation.fromJson,
        (l) => l.isEmpty,
      ),
      artwork: parseRecords(
        json['artwork'],
        IptcArtwork.fromJson,
        (a) => a.isEmpty,
      ),
      imageCreators: parseRecords(
        json['imageCreators'],
        IptcEntity.fromJson,
        (e) => e.isEmpty,
      ),
      copyrightOwners: parseRecords(
        json['copyrightOwners'],
        IptcEntity.fromJson,
        (e) => e.isEmpty,
      ),
      licensors: parseRecords(
        json['licensors'],
        IptcLicensor.fromJson,
        (l) => l.isEmpty,
      ),
      registryEntries: parseRecords(
        json['registryEntries'],
        IptcRegistryEntry.fromJson,
        (r) => r.isEmpty,
      ),
    );
  }

  /// Caption / description (`dc:description`, a language-alternative).
  final String caption;

  /// Headline — a short, publishable synopsis (`photoshop:Headline`).
  final String headline;

  /// Creator / photographer (`dc:creator`, an ordered sequence).
  final String creator;

  /// The creator's job title (`photoshop:AuthorsPosition`).
  final String authorTitle;

  /// Copyright notice (`dc:rights`, a language-alternative).
  final String copyright;

  /// Credit line — who to credit on publication (`photoshop:Credit`).
  final String credit;

  /// Original owner / source of the photo (`photoshop:Source`).
  final String source;

  /// Special instructions / rights usage terms (`photoshop:Instructions`).
  final String instructions;

  /// Sublocation within the city (`Iptc4xmpCore:Location`).
  final String location;

  /// City (`photoshop:City`).
  final String city;

  /// Province / state (`photoshop:State`).
  final String state;

  /// Country name (`photoshop:Country`).
  final String country;

  /// ISO 3166-1 alpha country code (`Iptc4xmpCore:CountryCode`).
  final String countryCode;

  /// Alt-text for accessibility (`Iptc4xmpCore:AltTextAccessibility`, added in
  /// the IPTC 2025.1 standard). Increasingly required by newsrooms.
  final String altText;

  /// Media Topics / subject codes as a comma-separated list of `medtop:`
  /// QCodes (`Iptc4xmpCore:SubjectCode`, an rdf:Bag). The M editor's
  /// autocomplete over the bundled vocabulary fills these.
  final String subjectCodes;

  /// Title / object name — the story slug (`dc:title`).
  final String title;

  /// Creator's work email (`Iptc4xmpCore:CreatorContactInfo/CiEmailWork`).
  final String creatorEmail;

  /// Creator's work website (`Iptc4xmpCore:CreatorContactInfo/CiUrlWork`).
  final String creatorWebsite;

  /// Creator's work postal address
  /// (`Iptc4xmpCore:CreatorContactInfo/CiAdrExtadr`).
  final String creatorAddress;

  /// Creator's work city (`Iptc4xmpCore:CreatorContactInfo/CiAdrCity`).
  final String creatorCity;

  /// Creator's work state/region (`Iptc4xmpCore:CreatorContactInfo/CiAdrRegion`).
  final String creatorRegion;

  /// Creator's work postal code (`Iptc4xmpCore:CreatorContactInfo/CiAdrPcode`).
  final String creatorPostalCode;

  /// Creator's work country (`Iptc4xmpCore:CreatorContactInfo/CiAdrCtry`).
  final String creatorCountry;

  /// Creator's work phone (`Iptc4xmpCore:CreatorContactInfo/CiTelWork`).
  final String creatorPhone;

  /// Date the photo was created (`photoshop:DateCreated`, IIM 2:55/2:60) as an
  /// ISO 8601 local string. Empty means "use the capture time" on write.
  final String dateCreated;

  /// Free-text notes about the model(s) (`Iptc4xmpExt:AddlModelInfo`).
  final String additionalModelInfo;

  /// Age(s) of the model(s), comma-separated (`Iptc4xmpExt:ModelAge`, a Bag).
  final String modelAge;

  /// Minor model age disclosure (`plus:MinorModelAgeDisclosure`).
  final String minorModelAgeDisclosure;

  /// Image supplier name (`plus:ImageSupplier/plus:ImageSupplierName`).
  final String imageSupplierName;

  /// Image supplier identifier (`plus:ImageSupplier/plus:ImageSupplierID`).
  final String imageSupplierId;

  /// Supplier's own ID for the image (`plus:ImageSupplierImageID`).
  final String imageSupplierImageId;

  /// Globally-unique image identifier (`Iptc4xmpExt:DigImageGUID`).
  final String digImageGuid;

  /// Copyright status — "copyrighted"/"public domain" (`xmpRights:Marked`).
  final String copyrightStatus;

  /// Rights usage terms (`xmpRights:UsageTerms`, a language-alternative).
  final String usageTerms;

  /// Web statement of rights — the rights URL (`xmpRights:WebStatement`).
  final String webStatement;

  /// Job identifier / transmission reference — wire routing / story ID
  /// (`photoshop:TransmissionReference`).
  final String jobId;

  /// Digital source type — a friendly value (photo / ai-generated / composite)
  /// mapped to the IPTC controlled-vocabulary URI
  /// (`Iptc4xmpExt:DigitalSourceType`).
  final String digitalSourceType;

  /// Name of the AI system used (`Iptc4xmpExt:AISystemUsed`, 2025.1).
  final String aiSystemUsed;

  /// Version of the AI system used (`Iptc4xmpExt:AISystemVersionUsed`).
  final String aiSystemVersion;

  /// The generation/edit prompt (`Iptc4xmpExt:AIPromptInformation`).
  final String aiPromptInfo;

  /// Who wrote the AI prompt (`Iptc4xmpExt:AIPromptWriterName`).
  final String aiPromptWriter;

  /// Who wrote the caption/description (`photoshop:CaptionWriter`, IIM 2:122).
  final String descriptionWriters;

  /// People shown in the image, comma-separated (`Iptc4xmpExt:PersonInImage`,
  /// an rdf:Bag).
  final String personsShown;

  /// Featured organisation names, comma-separated
  /// (`Iptc4xmpExt:OrganisationInImageName`, an rdf:Bag).
  final String featuredOrgName;

  /// Featured organisation codes, comma-separated
  /// (`Iptc4xmpExt:OrganisationInImageCode`, an rdf:Bag).
  final String featuredOrgCode;

  /// Intellectual genre — the nature of the item, e.g. "Actuality"
  /// (`Iptc4xmpCore:IntellectualGenre`).
  final String intellectualGenre;

  /// IPTC scene codes, comma-separated (`Iptc4xmpCore:Scene`, an rdf:Bag).
  final String iptcScene;

  /// The event the image documents (`Iptc4xmpExt:Event`, a
  /// language-alternative).
  final String event;

  /// Category — legacy 3-letter subject abbreviation (`photoshop:Category`,
  /// IIM 2:15).
  final String category;

  /// Supplemental categories, comma-separated
  /// (`photoshop:SupplementalCategories`, an rdf:Bag; IIM 2:20, repeatable).
  final String supplementalCategories;

  /// Urgency / editorial priority, "0"–"8" (`photoshop:Urgency`, IIM 2:10).
  final String urgency;

  /// Edit status — a free-text workflow note. IIM 2:07 only (no XMP standard),
  /// so it round-trips through our private `cullimingo:` namespace.
  final String editStatus;

  /// World region of the created location
  /// (`Iptc4xmpExt:LocationCreated/Iptc4xmpExt:WorldRegion`).
  final String worldRegion;

  /// Location identifier of the created location
  /// (`Iptc4xmpExt:LocationCreated/Iptc4xmpExt:LocationId`).
  final String locationId;

  /// Model release status (`plus:ModelReleaseStatus`).
  final String modelReleaseStatus;

  /// Model release document IDs, comma-separated (`plus:ModelReleaseID`, Bag).
  final String modelReleaseIds;

  /// Property release status (`plus:PropertyReleaseStatus`).
  final String propertyReleaseStatus;

  /// Property release document IDs, comma-separated (`plus:PropertyReleaseID`,
  /// a Bag).
  final String propertyReleaseIds;

  /// Places shown in the image (`Iptc4xmpExt:LocationShown`, a Bag of Location
  /// structures). A repeatable table, not a flat field.
  final List<IptcLocation> locationsShown;

  /// Artworks / objects shown in the image (`Iptc4xmpExt:ArtworkOrObject`).
  final List<IptcArtwork> artwork;

  /// PLUS image creators (`plus:ImageCreator`, a Seq of name/ID structures).
  final List<IptcEntity> imageCreators;

  /// PLUS copyright owners (`plus:CopyrightOwner`, a Seq of name/ID structures).
  final List<IptcEntity> copyrightOwners;

  /// PLUS licensors (`plus:Licensor`, a Seq of contact structures).
  final List<IptcLicensor> licensors;

  /// Registry entries (`Iptc4xmpExt:RegistryId`, a Bag of item/org IDs).
  final List<IptcRegistryEntry> registryEntries;

  /// A compact map holding only the non-empty fields (for DB/JSON storage). The
  /// flat fields are strings; the repeatable tables serialise as JSON arrays,
  /// hence the `dynamic` value type.
  Map<String, dynamic> toJson() => {
    if (caption.isNotEmpty) 'caption': caption,
    if (headline.isNotEmpty) 'headline': headline,
    if (creator.isNotEmpty) 'creator': creator,
    if (authorTitle.isNotEmpty) 'authorTitle': authorTitle,
    if (copyright.isNotEmpty) 'copyright': copyright,
    if (credit.isNotEmpty) 'credit': credit,
    if (source.isNotEmpty) 'source': source,
    if (instructions.isNotEmpty) 'instructions': instructions,
    if (location.isNotEmpty) 'location': location,
    if (city.isNotEmpty) 'city': city,
    if (state.isNotEmpty) 'state': state,
    if (country.isNotEmpty) 'country': country,
    if (countryCode.isNotEmpty) 'countryCode': countryCode,
    if (altText.isNotEmpty) 'altText': altText,
    if (subjectCodes.isNotEmpty) 'subjectCodes': subjectCodes,
    if (title.isNotEmpty) 'title': title,
    if (creatorEmail.isNotEmpty) 'creatorEmail': creatorEmail,
    if (creatorWebsite.isNotEmpty) 'creatorWebsite': creatorWebsite,
    if (creatorAddress.isNotEmpty) 'creatorAddress': creatorAddress,
    if (creatorCity.isNotEmpty) 'creatorCity': creatorCity,
    if (creatorRegion.isNotEmpty) 'creatorRegion': creatorRegion,
    if (creatorPostalCode.isNotEmpty) 'creatorPostalCode': creatorPostalCode,
    if (creatorCountry.isNotEmpty) 'creatorCountry': creatorCountry,
    if (creatorPhone.isNotEmpty) 'creatorPhone': creatorPhone,
    if (dateCreated.isNotEmpty) 'dateCreated': dateCreated,
    if (additionalModelInfo.isNotEmpty)
      'additionalModelInfo': additionalModelInfo,
    if (modelAge.isNotEmpty) 'modelAge': modelAge,
    if (minorModelAgeDisclosure.isNotEmpty)
      'minorModelAgeDisclosure': minorModelAgeDisclosure,
    if (imageSupplierName.isNotEmpty) 'imageSupplierName': imageSupplierName,
    if (imageSupplierId.isNotEmpty) 'imageSupplierId': imageSupplierId,
    if (imageSupplierImageId.isNotEmpty)
      'imageSupplierImageId': imageSupplierImageId,
    if (digImageGuid.isNotEmpty) 'digImageGuid': digImageGuid,
    if (copyrightStatus.isNotEmpty) 'copyrightStatus': copyrightStatus,
    if (usageTerms.isNotEmpty) 'usageTerms': usageTerms,
    if (webStatement.isNotEmpty) 'webStatement': webStatement,
    if (jobId.isNotEmpty) 'jobId': jobId,
    if (digitalSourceType.isNotEmpty) 'digitalSourceType': digitalSourceType,
    if (aiSystemUsed.isNotEmpty) 'aiSystemUsed': aiSystemUsed,
    if (aiSystemVersion.isNotEmpty) 'aiSystemVersion': aiSystemVersion,
    if (aiPromptInfo.isNotEmpty) 'aiPromptInfo': aiPromptInfo,
    if (aiPromptWriter.isNotEmpty) 'aiPromptWriter': aiPromptWriter,
    if (descriptionWriters.isNotEmpty) 'descriptionWriters': descriptionWriters,
    if (personsShown.isNotEmpty) 'personsShown': personsShown,
    if (featuredOrgName.isNotEmpty) 'featuredOrgName': featuredOrgName,
    if (featuredOrgCode.isNotEmpty) 'featuredOrgCode': featuredOrgCode,
    if (intellectualGenre.isNotEmpty) 'intellectualGenre': intellectualGenre,
    if (iptcScene.isNotEmpty) 'iptcScene': iptcScene,
    if (event.isNotEmpty) 'event': event,
    if (category.isNotEmpty) 'category': category,
    if (supplementalCategories.isNotEmpty)
      'supplementalCategories': supplementalCategories,
    if (urgency.isNotEmpty) 'urgency': urgency,
    if (editStatus.isNotEmpty) 'editStatus': editStatus,
    if (worldRegion.isNotEmpty) 'worldRegion': worldRegion,
    if (locationId.isNotEmpty) 'locationId': locationId,
    if (modelReleaseStatus.isNotEmpty) 'modelReleaseStatus': modelReleaseStatus,
    if (modelReleaseIds.isNotEmpty) 'modelReleaseIds': modelReleaseIds,
    if (propertyReleaseStatus.isNotEmpty)
      'propertyReleaseStatus': propertyReleaseStatus,
    if (propertyReleaseIds.isNotEmpty) 'propertyReleaseIds': propertyReleaseIds,
    if (locationsShown.isNotEmpty)
      'locationsShown': [for (final l in locationsShown) l.toJson()],
    if (artwork.isNotEmpty) 'artwork': [for (final a in artwork) a.toJson()],
    if (imageCreators.isNotEmpty)
      'imageCreators': [for (final e in imageCreators) e.toJson()],
    if (copyrightOwners.isNotEmpty)
      'copyrightOwners': [for (final e in copyrightOwners) e.toJson()],
    if (licensors.isNotEmpty)
      'licensors': [for (final l in licensors) l.toJson()],
    if (registryEntries.isNotEmpty)
      'registryEntries': [for (final r in registryEntries) r.toJson()],
  };

  /// The parsed [dateCreated], or null when unset/unparseable — the write path
  /// prefers this over the EXIF capture time.
  DateTime? get dateCreatedParsed =>
      dateCreated.isEmpty ? null : DateTime.tryParse(dateCreated);

  /// This photo's value for [field] (empty string when unset). Lets the
  /// inspector and editor iterate [IptcField] without a per-field switch.
  String valueFor(IptcField field) => switch (field) {
    IptcField.caption => caption,
    IptcField.headline => headline,
    IptcField.creator => creator,
    IptcField.authorTitle => authorTitle,
    IptcField.credit => credit,
    IptcField.source => source,
    IptcField.copyright => copyright,
    IptcField.instructions => instructions,
    IptcField.location => location,
    IptcField.city => city,
    IptcField.state => state,
    IptcField.country => country,
    IptcField.countryCode => countryCode,
    IptcField.altText => altText,
    IptcField.subjectCodes => subjectCodes,
    IptcField.title => title,
    IptcField.creatorEmail => creatorEmail,
    IptcField.creatorWebsite => creatorWebsite,
    IptcField.creatorAddress => creatorAddress,
    IptcField.creatorCity => creatorCity,
    IptcField.creatorRegion => creatorRegion,
    IptcField.creatorPostalCode => creatorPostalCode,
    IptcField.creatorCountry => creatorCountry,
    IptcField.creatorPhone => creatorPhone,
    IptcField.dateCreated => dateCreated,
    IptcField.additionalModelInfo => additionalModelInfo,
    IptcField.modelAge => modelAge,
    IptcField.minorModelAgeDisclosure => minorModelAgeDisclosure,
    IptcField.imageSupplierName => imageSupplierName,
    IptcField.imageSupplierId => imageSupplierId,
    IptcField.imageSupplierImageId => imageSupplierImageId,
    IptcField.digImageGuid => digImageGuid,
    IptcField.copyrightStatus => copyrightStatus,
    IptcField.usageTerms => usageTerms,
    IptcField.webStatement => webStatement,
    IptcField.jobId => jobId,
    IptcField.digitalSourceType => digitalSourceType,
    IptcField.aiSystemUsed => aiSystemUsed,
    IptcField.aiSystemVersion => aiSystemVersion,
    IptcField.aiPromptInfo => aiPromptInfo,
    IptcField.aiPromptWriter => aiPromptWriter,
    IptcField.descriptionWriters => descriptionWriters,
    IptcField.personsShown => personsShown,
    IptcField.featuredOrgName => featuredOrgName,
    IptcField.featuredOrgCode => featuredOrgCode,
    IptcField.intellectualGenre => intellectualGenre,
    IptcField.iptcScene => iptcScene,
    IptcField.event => event,
    IptcField.category => category,
    IptcField.supplementalCategories => supplementalCategories,
    IptcField.urgency => urgency,
    IptcField.editStatus => editStatus,
    IptcField.worldRegion => worldRegion,
    IptcField.locationId => locationId,
    IptcField.modelReleaseStatus => modelReleaseStatus,
    IptcField.modelReleaseIds => modelReleaseIds,
    IptcField.propertyReleaseStatus => propertyReleaseStatus,
    IptcField.propertyReleaseIds => propertyReleaseIds,
  };

  /// A copy with [changes] applied over the current values. A field absent from
  /// [changes] is left as-is; a field mapped to `''` is cleared. This is the
  /// batch-edit primitive: the editor sends only the fields the user touched,
  /// so untouched fields keep each photo's existing value.
  IptcCore withOverrides(Map<IptcField, String> changes) => IptcCore.fromJson({
    ...toJson(),
    for (final entry in changes.entries) entry.key.name: entry.value,
  });

  /// A copy with the given structured tables replaced. A null argument leaves
  /// that table as-is; a non-null one (even empty) sets it. All flat fields are
  /// preserved.
  IptcCore withStructured({
    List<IptcLocation>? locationsShown,
    List<IptcArtwork>? artwork,
    List<IptcEntity>? imageCreators,
    List<IptcEntity>? copyrightOwners,
    List<IptcLicensor>? licensors,
    List<IptcRegistryEntry>? registryEntries,
  }) => IptcCore.fromJson({
    ...toJson(),
    if (locationsShown != null)
      'locationsShown': [for (final l in locationsShown) l.toJson()],
    if (artwork != null) 'artwork': [for (final a in artwork) a.toJson()],
    if (imageCreators != null)
      'imageCreators': [for (final e in imageCreators) e.toJson()],
    if (copyrightOwners != null)
      'copyrightOwners': [for (final e in copyrightOwners) e.toJson()],
    if (licensors != null) 'licensors': [for (final l in licensors) l.toJson()],
    if (registryEntries != null)
      'registryEntries': [for (final r in registryEntries) r.toJson()],
  });

  /// Whether every field is blank, i.e. there is nothing to write.
  bool get isEmpty =>
      caption.isEmpty &&
      headline.isEmpty &&
      creator.isEmpty &&
      authorTitle.isEmpty &&
      copyright.isEmpty &&
      credit.isEmpty &&
      source.isEmpty &&
      instructions.isEmpty &&
      location.isEmpty &&
      city.isEmpty &&
      state.isEmpty &&
      country.isEmpty &&
      countryCode.isEmpty &&
      altText.isEmpty &&
      subjectCodes.isEmpty &&
      title.isEmpty &&
      creatorEmail.isEmpty &&
      creatorWebsite.isEmpty &&
      creatorAddress.isEmpty &&
      creatorCity.isEmpty &&
      creatorRegion.isEmpty &&
      creatorPostalCode.isEmpty &&
      creatorCountry.isEmpty &&
      creatorPhone.isEmpty &&
      dateCreated.isEmpty &&
      additionalModelInfo.isEmpty &&
      modelAge.isEmpty &&
      minorModelAgeDisclosure.isEmpty &&
      imageSupplierName.isEmpty &&
      imageSupplierId.isEmpty &&
      imageSupplierImageId.isEmpty &&
      digImageGuid.isEmpty &&
      copyrightStatus.isEmpty &&
      usageTerms.isEmpty &&
      webStatement.isEmpty &&
      jobId.isEmpty &&
      digitalSourceType.isEmpty &&
      aiSystemUsed.isEmpty &&
      aiSystemVersion.isEmpty &&
      aiPromptInfo.isEmpty &&
      aiPromptWriter.isEmpty &&
      descriptionWriters.isEmpty &&
      personsShown.isEmpty &&
      featuredOrgName.isEmpty &&
      featuredOrgCode.isEmpty &&
      intellectualGenre.isEmpty &&
      iptcScene.isEmpty &&
      event.isEmpty &&
      category.isEmpty &&
      supplementalCategories.isEmpty &&
      urgency.isEmpty &&
      editStatus.isEmpty &&
      worldRegion.isEmpty &&
      locationId.isEmpty &&
      modelReleaseStatus.isEmpty &&
      modelReleaseIds.isEmpty &&
      propertyReleaseStatus.isEmpty &&
      propertyReleaseIds.isEmpty &&
      locationsShown.isEmpty &&
      artwork.isEmpty &&
      imageCreators.isEmpty &&
      copyrightOwners.isEmpty &&
      licensors.isEmpty &&
      registryEntries.isEmpty;
}
