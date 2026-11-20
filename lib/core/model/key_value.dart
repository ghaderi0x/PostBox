import '../util/json_util.dart';

/// One row of a key/value editor (query param, header, form field).
class KeyValue {
  const KeyValue({
    this.key = '',
    this.value = '',
    this.enabled = true,
    this.isFile = false,
  });

  final String key;
  final String value;
  final bool enabled;

  /// Multipart only: [value] is a file path instead of text.
  final bool isFile;

  KeyValue copyWith({
    String? key,
    String? value,
    bool? enabled,
    bool? isFile,
  }) => KeyValue(
    key: key ?? this.key,
    value: value ?? this.value,
    enabled: enabled ?? this.enabled,
    isFile: isFile ?? this.isFile,
  );

  bool get isBlank => key.isEmpty && value.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'value': value,
    'enabled': enabled,
    if (isFile) 'isFile': true,
  };

  factory KeyValue.fromJson(Object? j) {
    final m = asMap(j);
    return KeyValue(
      key: asString(m['key']),
      value: asString(m['value']),
      enabled: asBool(m['enabled'], true),
      isFile: asBool(m['isFile'], false),
    );
  }

  static List<KeyValue> listFromJson(Object? j) =>
      asList(j).map(KeyValue.fromJson).toList();

  static List<Map<String, dynamic>> listToJson(List<KeyValue> l) =>
      l.map((e) => e.toJson()).toList();
}
