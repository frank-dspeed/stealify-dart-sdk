// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of "core_patch.dart";

@pragma("wasm:import", "dart2wasm.doubleToString")
external String _doubleToString(double v);

@pragma("wasm:import", "dart2wasm.toFixed")
external String _toFixed(double d, double digits);

@pragma("wasm:import", "dart2wasm.toExponential")
external String _toExponential1(double d);

@pragma("wasm:import", "dart2wasm.toExponential")
external String _toExponential2(double d, double fractionDigits);

@pragma("wasm:import", "dart2wasm.toPrecision")
external String _toPrecision(double d, double precision);

@pragma("wasm:import", "dart2wasm.parseDouble")
external double _parseDouble(String doubleString);

@patch
class double {
  @patch
  static double parse(String source,
      [@deprecated double onError(String source)?]) {
    double? result = tryParse(source);
    if (result == null) {
      throw FormatException('Invalid double $source');
    }
    return result;
  }

  @patch
  static double? tryParse(String source) {
    double result = _parseDouble(source);
    if (result.isNaN) {
      String trimmed = source.trim();
      if (!(trimmed == 'NaN' || trimmed == '+NaN' || trimmed == '-NaN')) {
        return null;
      }
    }
    return result;
  }
}

@pragma("wasm:entry-point")
class _BoxedDouble implements double {
  // A boxed double contains an unboxed double.
  @pragma("wasm:entry-point")
  double value = 0.0;

  static const int _signMask = 0x8000000000000000;
  static const int _exponentMask = 0x7FF0000000000000;
  static const int _mantissaMask = 0x000FFFFFFFFFFFFF;

  int get hashCode {
    int bits = doubleToIntBits(this);
    if (bits == _signMask) bits = 0; // 0.0 == -0.0
    return mix64(bits);
  }

  int get _identityHashCode => hashCode;

  double operator +(num other) => this + other.toDouble(); // Intrinsic +
  double operator -(num other) => this - other.toDouble(); // Intrinsic -
  double operator *(num other) => this * other.toDouble(); // Intrinsic *
  double operator /(num other) => this / other.toDouble(); // Intrinsic /

  int operator ~/(num other) {
    return _truncDiv(this, other.toDouble());
  }

  static int _truncDiv(double a, double b) {
    return (a / b).toInt();
  }

  double operator %(num other) {
    return _modulo(this, other.toDouble());
  }

  static double _modulo(double a, double b) {
    double rem = a - (a / b).truncateToDouble() * b;
    if (rem == 0.0) return 0.0;
    if (rem < 0.0) {
      if (b < 0.0) {
        return rem - b;
      } else {
        return rem + b;
      }
    }
    return rem;
  }

  double remainder(num other) {
    return _remainder(this, other.toDouble());
  }

  static double _remainder(double a, double b) {
    return a - (a / b).truncateToDouble() * b;
  }

  external double operator -();

  bool operator ==(Object other) {
    return other is double
        ? this == other // Intrinsic ==
        : other is int
            ? this == other.toDouble() // Intrinsic ==
            : false;
  }

  bool operator <(num other) => this < other.toDouble(); // Intrinsic <
  bool operator >(num other) => this > other.toDouble(); // Intrinsic >
  bool operator >=(num other) => this >= other.toDouble(); // Intrinsic >=
  bool operator <=(num other) => this <= other.toDouble(); // Intrinsic <=

  bool get isNegative {
    int bits = doubleToIntBits(this);
    return (bits & _signMask) != 0;
  }

  bool get isInfinite {
    int bits = doubleToIntBits(this);
    return (bits & _exponentMask) == _exponentMask &&
        (bits & _mantissaMask) == 0;
  }

  bool get isNaN {
    int bits = doubleToIntBits(this);
    return (bits & _exponentMask) == _exponentMask &&
        (bits & _mantissaMask) != 0;
  }

  bool get isFinite {
    int bits = doubleToIntBits(this);
    return (bits & _exponentMask) != _exponentMask;
  }

  double abs() {
    // Handle negative 0.0.
    if (this == 0.0) return 0.0;
    return this < 0.0 ? -this : this;
  }

  double get sign {
    if (this > 0.0) return 1.0;
    if (this < 0.0) return -1.0;
    return this; // +/-0.0 or NaN.
  }

  int round() => roundToDouble().toInt();
  int floor() => floorToDouble().toInt();
  int ceil() => ceilToDouble().toInt();
  int truncate() => truncateToDouble().toInt();

  external double roundToDouble();
  external double floorToDouble();
  external double ceilToDouble();
  external double truncateToDouble();

  num clamp(num lowerLimit, num upperLimit) {
    if (lowerLimit.compareTo(upperLimit) > 0) {
      throw new ArgumentError(lowerLimit);
    }
    if (lowerLimit.isNaN) return lowerLimit;
    if (this.compareTo(lowerLimit) < 0) return lowerLimit;
    if (this.compareTo(upperLimit) > 0) return upperLimit;
    return this;
  }

  external int toInt();

  double toDouble() {
    return this;
  }

  static const int CACHE_SIZE_LOG2 = 3;
  static const int CACHE_LENGTH = 1 << (CACHE_SIZE_LOG2 + 1);
  static const int CACHE_MASK = CACHE_LENGTH - 1;
  // Each key (double) followed by its toString result.
  static final List _cache = new List.filled(CACHE_LENGTH, null);
  static int _cacheEvictIndex = 0;

  String toString() {
    // TODO(koda): Consider starting at most recently inserted.
    for (int i = 0; i < CACHE_LENGTH; i += 2) {
      // Need 'identical' to handle negative zero, etc.
      if (identical(_cache[i], this)) {
        return _cache[i + 1];
      }
    }
    // TODO(koda): Consider optimizing all small integral values.
    if (identical(0.0, this)) {
      return "0.0";
    }
    String result = _doubleToString(value);
    // Replace the least recently inserted entry.
    _cache[_cacheEvictIndex] = this;
    _cache[_cacheEvictIndex + 1] = result;
    _cacheEvictIndex = (_cacheEvictIndex + 2) & CACHE_MASK;
    return result;
  }

  String toStringAsFixed(int fractionDigits) {
    // See ECMAScript-262, 15.7.4.5 for details.

    // Step 2.
    if (fractionDigits < 0 || fractionDigits > 20) {
      throw new RangeError.range(fractionDigits, 0, 20, "fractionDigits");
    }

    // Step 3.
    double x = this;

    // Step 4.
    if (isNaN) return "NaN";

    // Step 5 and 6 skipped. Will be dealt with by native function.

    // Step 7.
    if (x >= 1e21 || x <= -1e21) {
      return x.toString();
    }

    return _toStringAsFixed(fractionDigits);
  }

  String _toStringAsFixed(int fractionDigits) =>
      _toFixed(value, fractionDigits.toDouble());

  String toStringAsExponential([int? fractionDigits]) {
    // See ECMAScript-262, 15.7.4.6 for details.

    // The EcmaScript specification checks for NaN and Infinity before looking
    // at the fractionDigits. In Dart we are consistent with toStringAsFixed and
    // look at the fractionDigits first.

    // Step 7.
    if (fractionDigits != null) {
      if (fractionDigits < 0 || fractionDigits > 20) {
        throw new RangeError.range(fractionDigits, 0, 20, "fractionDigits");
      }
    }

    if (isNaN) return "NaN";
    if (this == double.infinity) return "Infinity";
    if (this == -double.infinity) return "-Infinity";

    return _toStringAsExponential(fractionDigits);
  }

  String _toStringAsExponential(int? fractionDigits) {
    if (fractionDigits == null) {
      return _toExponential1(value);
    } else {
      return _toExponential2(value, fractionDigits.toDouble());
    }
  }

  String toStringAsPrecision(int precision) {
    // See ECMAScript-262, 15.7.4.7 for details.

    // The EcmaScript specification checks for NaN and Infinity before looking
    // at the fractionDigits. In Dart we are consistent with toStringAsFixed and
    // look at the fractionDigits first.

    // Step 8.
    if (precision < 1 || precision > 21) {
      throw new RangeError.range(precision, 1, 21, "precision");
    }

    if (isNaN) return "NaN";
    if (this == double.infinity) return "Infinity";
    if (this == -double.infinity) return "-Infinity";

    return _toStringAsPrecision(precision);
  }

  String _toStringAsPrecision(int fractionDigits) =>
      _toPrecision(value, fractionDigits.toDouble());

  // Order is: NaN > Infinity > ... > 0.0 > -0.0 > ... > -Infinity.
  int compareTo(num other) {
    const int EQUAL = 0, LESS = -1, GREATER = 1;
    if (this < other) {
      return LESS;
    } else if (this > other) {
      return GREATER;
    } else if (this == other) {
      if (this == 0.0) {
        bool thisIsNegative = isNegative;
        bool otherIsNegative = other.isNegative;
        if (thisIsNegative == otherIsNegative) {
          return EQUAL;
        }
        return thisIsNegative ? LESS : GREATER;
      } else if (other is int) {
        // Compare as integers as it is more precise if the integer value is
        // outside of MIN_EXACT_INT_TO_DOUBLE..MAX_EXACT_INT_TO_DOUBLE range.
        const int MAX_EXACT_INT_TO_DOUBLE = 9007199254740992; // 2^53.
        const int MIN_EXACT_INT_TO_DOUBLE = -MAX_EXACT_INT_TO_DOUBLE;
        if ((MIN_EXACT_INT_TO_DOUBLE <= other) &&
            (other <= MAX_EXACT_INT_TO_DOUBLE)) {
          return EQUAL;
        }
        const bool limitIntsTo64Bits = ((1 << 64) == 0);
        if (limitIntsTo64Bits) {
          // With integers limited to 64 bits, double.toInt() clamps
          // double value to fit into the MIN_INT64..MAX_INT64 range.
          // MAX_INT64 is not precisely representable as double, so
          // integers near MAX_INT64 compare as equal to (MAX_INT64 + 1) when
          // represented as doubles.
          // There is no similar problem with MIN_INT64 as it is precisely
          // representable as double.
          const double maxInt64Plus1AsDouble = 9223372036854775808.0;
          if (this >= maxInt64Plus1AsDouble) {
            return GREATER;
          }
        }
        return toInt().compareTo(other);
      } else {
        return EQUAL;
      }
    } else if (isNaN) {
      return other.isNaN ? EQUAL : GREATER;
    } else {
      // Other is NaN.
      return LESS;
    }
  }
}
