import 'dart:convert';

/// The parts of a multipart/form-data body the fake server read: text fields
/// by name, and file parts as name to filename.
({Map<String, String> fields, Map<String, String> files}) multipartParts(
  List<int> body,
) {
  final text = latin1.decode(body);
  final boundary = text.substring(0, text.indexOf('\r\n'));
  final fields = <String, String>{};
  final files = <String, String>{};
  for (final part in text.split(boundary)) {
    final split = part.indexOf('\r\n\r\n');
    if (split < 0) continue;
    final head = part.substring(0, split);
    final name = RegExp(r'name="([^"]*)"').firstMatch(head)?.group(1);
    if (name == null) continue;
    var value = part.substring(split + 4);
    if (value.endsWith('\r\n')) value = value.substring(0, value.length - 2);
    final filename = RegExp(r'filename="([^"]*)"').firstMatch(head)?.group(1);
    if (filename != null) {
      files[name] = filename;
    } else {
      fields[name] = utf8.decode(latin1.encode(value));
    }
  }
  return (fields: fields, files: files);
}
