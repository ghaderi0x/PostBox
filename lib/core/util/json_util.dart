T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> asList(Object? v) => v is List ? v : const <dynamic>[];

String asString(Object? v, [String d = '']) => v is String ? v : d;

int asInt(Object? v, int d) => v is num ? v.toInt() : d;

double asDouble(Object? v, double d) => v is num ? v.toDouble() : d;

bool asBool(Object? v, bool d) => v is bool ? v : d;

int clampInt(int v, int min, int max) => v < min ? min : (v > max ? max : v);

double clampDouble(double v, double min, double max) =>
    v < min ? min : (v > max ? max : v);
