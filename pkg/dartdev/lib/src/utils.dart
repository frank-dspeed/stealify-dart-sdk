// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// For commands where we are able to initialize the [ArgParser], this value
/// is used as the usageLineLength.
int? get dartdevUsageLineLength =>
    stdout.hasTerminal ? stdout.terminalColumns : null;

/// Try parsing [maybeUri] as a file uri or [maybeUri] itself if that fails.
String maybeUriToFilename(String maybeUri) {
  try {
    return Uri.parse(maybeUri).toFilePath();
  } catch (_) {
    return maybeUri;
  }
}

/// Given a data structure which is a Map of String to dynamic values, return
/// the same structure (`Map<String, dynamic>`) with the correct runtime types.
Map<String, dynamic> castStringKeyedMap(dynamic untyped) {
  final Map<dynamic, dynamic> map = untyped! as Map<dynamic, dynamic>;
  return map.cast<String, dynamic>();
}

/// Emit the given word with the correct pluralization.
String pluralize(String word, int count) => count == 1 ? word : '${word}s';

/// Make an absolute [filePath] relative to [dir] (for display purposes).
String relativePath(String filePath, Directory dir) {
  var root = dir.absolute.path;
  if (filePath.startsWith(root)) {
    return filePath.substring(root.length + 1);
  }
  return filePath;
}

/// String utility to trim some suffix from the end of a [String].
String trimEnd(String s, String? suffix) {
  if (suffix != null && suffix.isNotEmpty && s.endsWith(suffix)) {
    return s.substring(0, s.length - suffix.length);
  }
  return s;
}

extension FileSystemEntityExtension on FileSystemEntity {
  String get name => p.basename(path);

  bool get isDartFile => this is File && p.extension(path) == '.dart';
}

/// Wraps [text] to the given [width], if provided.
String wrapText(String text, {int? width}) {
  if (width == null) {
    return text;
  }

  var buffer = StringBuffer();
  var lineMaxEndIndex = width;
  var lineStartIndex = 0;

  while (true) {
    if (lineMaxEndIndex >= text.length) {
      buffer.write(text.substring(lineStartIndex, text.length));
      break;
    } else {
      var lastSpaceIndex = text.lastIndexOf(' ', lineMaxEndIndex);
      if (lastSpaceIndex == -1 || lastSpaceIndex <= lineStartIndex) {
        // No space between [lineStartIndex] and [lineMaxEndIndex]. Get the
        // _next_ space.
        lastSpaceIndex = text.indexOf(' ', lineMaxEndIndex);
        if (lastSpaceIndex == -1) {
          // No space at all after [lineStartIndex].
          lastSpaceIndex = text.length;
          buffer.write(text.substring(lineStartIndex, lastSpaceIndex));
          break;
        }
      }
      buffer.write(text.substring(lineStartIndex, lastSpaceIndex));
      buffer.writeln();
      lineStartIndex = lastSpaceIndex + 1;
    }
    lineMaxEndIndex = lineStartIndex + width;
  }
  return buffer.toString();
}

// A valid Dart identifier that can be used for a package, i.e. no
// capital letters.
// https://dart.dev/guides/language/language-tour#important-concepts
final RegExp _identifierRegExp = RegExp(r'^[a-z_][a-z\d_]*$');

// non-contextual dart keywords.
// https://dart.dev/guides/language/language-tour#keywords
const Set<String> _keywords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'inout',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'native',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'out',
  'part',
  'patch',
  'required',
  'rethrow',
  'return',
  'set',
  'show',
  'source',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

/// Whether [name] is a valid Pub package.
bool isValidPackageName(String name) =>
    _identifierRegExp.hasMatch(name) && !_keywords.contains(name);

/// Convert a directory name into a reasonably legal pub package name.
String normalizeProjectName(String name) {
  name = name.replaceAll('-', '_').replaceAll(' ', '_');
  // Strip any extension (like .dart).
  var dotIndex = name.indexOf('.');
  if (dotIndex >= 0) {
    name = name.substring(0, dotIndex);
  }
  return name;
}
