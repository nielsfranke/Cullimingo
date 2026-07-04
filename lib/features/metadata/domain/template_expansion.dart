import 'package:cullimingo/features/metadata/domain/code_replacements.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:cullimingo/features/metadata/domain/template_variables.dart';

/// Expands one string: code replacements first, then `{variables}` — so a code
/// can itself expand to text that contains a variable (e.g. `=copy=` holding
/// `© {year} Name`).
String expandTemplateText(
  String input, {
  required Map<String, String> vars,
  required CodeReplacements codes,
}) => expandVariables(expandCodes(input, codes), vars);

/// Returns a copy of [template] with every field value and keyword expanded for
/// one photo's [vars] and the shared [codes] table. The apply path expands
/// per-photo (variables like `{name}`/`{seq}` differ per photo) and then hands
/// the result to `applyTemplate`, so merge modes still apply unchanged.
/// Table cells expand per photo too, so `{date}`/`{name}`/`=codes=` work
/// inside a boilerplate location or artwork row.
IptcTemplate expandTemplate(
  IptcTemplate template, {
  required Map<String, String> vars,
  required CodeReplacements codes,
}) =>
    template.mapValues((s) => expandTemplateText(s, vars: vars, codes: codes));
