// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/lsp_protocol/protocol_generated.dart';
import 'package:analyzer/src/test_utilities/test_code_format.dart';
import 'package:collection/collection.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../utils/test_code_extensions.dart';
import 'server_abstract.dart';

void main() {
  defineReflectiveSuite(() {
    // These tests cover the LSP handler. A complete set of Type Hierarchy tests
    // are in 'test/src/computer/type_hierarchy_computer_test.dart'.
    defineReflectiveTests(PrepareTypeHierarchyTest);
    defineReflectiveTests(TypeHierarchySupertypesTest);
    defineReflectiveTests(TypeHierarchySubtypesTest);
  });
}

abstract class AbstractTypeHierarchyTest extends AbstractLspAnalysisServerTest {
  /// Code being tested in the main file.
  late TestCode code;

  /// Another file for testing cross-file content.
  late final String otherFilePath;
  late final Uri otherFileUri;
  late TestCode otherCode;

  /// The result of the last prepareTypeHierarchy call.
  TypeHierarchyItem? prepareResult;

  late final dartCodeUri = Uri.file(convertPath('/sdk/lib/core/core.dart'));

  /// Matches a [TypeHierarchyItem] for [Object] with an 'extends' relationship.
  Matcher get _isExtendsObject => TypeMatcher<TypeHierarchyItem>()
      .having((e) => e.name, 'name', 'Object')
      .having((e) => e.uri, 'uri', dartCodeUri)
      .having((e) => e.kind, 'kind', SymbolKind.Class)
      .having((e) => e.detail, 'detail', 'extends')
      .having((e) => e.selectionRange, 'selectionRange', _isValidRange)
      .having((e) => e.range, 'range', _isValidRange);

  /// Matches a valid [Position].
  Matcher get _isValidPosition => TypeMatcher<Position>()
      .having((e) => e.line, 'line', greaterThanOrEqualTo(0))
      .having((e) => e.character, 'character', greaterThanOrEqualTo(0));

  /// Matches a [Range] with valid [Position]s.
  Matcher get _isValidRange => TypeMatcher<Range>()
      .having((e) => e.start, 'start', _isValidPosition)
      .having((e) => e.end, 'end', _isValidPosition);

  @override
  void setUp() {
    super.setUp();
    otherFilePath = join(projectFolderPath, 'lib', 'other.dart');
    otherFileUri = Uri.file(otherFilePath);
  }

  /// Matches a [TypeHierarchyItem] with the given values.
  Matcher _isItem(
    String name,
    Uri uri, {
    String? detail,
    required Range selectionRange,
    required Range range,
  }) =>
      TypeMatcher<TypeHierarchyItem>()
          .having((e) => e.name, 'name', name)
          .having((e) => e.uri, 'uri', uri)
          .having((e) => e.kind, 'kind', SymbolKind.Class)
          .having((e) => e.detail, 'detail', detail)
          .having((e) => e.selectionRange, 'selectionRange', selectionRange)
          .having((e) => e.range, 'range', range);

  /// Parses [content] and calls 'textDocument/prepareTypeHierarchy' at the
  /// marked location.
  Future<void> _prepareTypeHierarchy(String content,
      {String? otherContent}) async {
    code = TestCode.parse(content);
    newFile(mainFilePath, code.code);

    if (otherContent != null) {
      otherCode = TestCode.parse(otherContent);
      newFile(otherFilePath, otherCode.code);
    }

    await initialize();
    final result = await prepareTypeHierarchy(
      mainFileUri,
      code.position.position,
    );
    prepareResult = result?.singleOrNull;
  }
}

@reflectiveTest
class PrepareTypeHierarchyTest extends AbstractTypeHierarchyTest {
  Future<void> test_class() async {
    final content = '''
/*[0*/class /*[1*/MyC^lass1/*1]*/ {}/*0]*/
''';
    await _prepareTypeHierarchy(content);
    expect(
      prepareResult,
      _isItem(
        'MyClass1',
        mainFileUri,
        range: code.ranges[0].range,
        selectionRange: code.ranges[1].range,
      ),
    );
  }

  Future<void> test_nonClass() async {
    final content = '''
int? a^a;
''';
    await _prepareTypeHierarchy(content);
    expect(prepareResult, isNull);
  }

  Future<void> test_whitespace() async {
    final content = '''
int? a;
^
int? b;
''';
    await _prepareTypeHierarchy(content);
    expect(prepareResult, isNull);
  }
}

@reflectiveTest
class TypeHierarchySubtypesTest extends AbstractTypeHierarchyTest {
  List<TypeHierarchyItem>? subtypes;

  Future<void> test_anotherFile() async {
    final content = '''
class MyCl^ass1 {}
''';
    final otherContent = '''
import 'main.dart';

/*[0*/class /*[1*/MyClass2/*1]*/ extends MyClass1 {}/*0]*/
''';
    await _fetchSubtypes(content, otherContent: otherContent);
    expect(
        subtypes,
        equals([
          _isItem(
            'MyClass2',
            otherFileUri,
            detail: 'extends',
            range: otherCode.ranges[0].range,
            selectionRange: otherCode.ranges[1].range,
          ),
        ]));
  }

  Future<void> test_extends() async {
    final content = '''
class MyCla^ss1 {}
/*[0*/class /*[1*/MyClass2/*1]*/ extends MyClass1 {}/*0]*/
''';
    await _fetchSubtypes(content);
    expect(
        subtypes,
        equals([
          _isItem(
            'MyClass2',
            mainFileUri,
            detail: 'extends',
            range: code.ranges[0].range,
            selectionRange: code.ranges[1].range,
          ),
        ]));
  }

  Future<void> test_implements() async {
    final content = '''
class MyCla^ss1 {}
/*[0*/class /*[1*/MyClass2/*1]*/ implements MyClass1 {}/*0]*/
''';
    await _fetchSubtypes(content);
    expect(
        subtypes,
        equals([
          _isItem(
            'MyClass2',
            mainFileUri,
            detail: 'implements',
            range: code.ranges[0].range,
            selectionRange: code.ranges[1].range,
          ),
        ]));
  }

  Future<void> test_on() async {
    final content = '''
class MyCla^ss1 {}
/*[0*/mixin /*[1*/MyMixin1/*1]*/ on MyClass1 {}/*0]*/
''';
    await _fetchSubtypes(content);
    expect(
        subtypes,
        equals([
          _isItem(
            'MyMixin1',
            mainFileUri,
            detail: 'constrained to',
            range: code.ranges[0].range,
            selectionRange: code.ranges[1].range,
          ),
        ]));
  }

  Future<void> test_with() async {
    final content = '''
mixin MyMi^xin1 {}
/*[0*/class /*[1*/MyClass1/*1]*/ with MyMixin1 {}/*0]*/
''';
    await _fetchSubtypes(content);
    expect(
        subtypes,
        equals([
          _isItem(
            'MyClass1',
            mainFileUri,
            detail: 'mixes in',
            range: code.ranges[0].range,
            selectionRange: code.ranges[1].range,
          ),
        ]));
  }

  /// Parses [content], calls 'textDocument/prepareTypeHierarchy' at the
  /// marked location and then calls 'typeHierarchy/subtypes' with the result.
  Future<void> _fetchSubtypes(String content, {String? otherContent}) async {
    await _prepareTypeHierarchy(content, otherContent: otherContent);
    subtypes = await typeHierarchySubtypes(prepareResult!);
  }
}

@reflectiveTest
class TypeHierarchySupertypesTest extends AbstractTypeHierarchyTest {
  List<TypeHierarchyItem>? supertypes;

  Future<void> test_anotherFile() async {
    final content = '''
import 'other.dart';

class MyCla^ss2 extends MyClass1 {}
''';
    final otherContent = '''
/*[0*/class /*[1*/MyClass1/*1]*/ {}/*0]*/
''';
    await _fetchSupertypes(content, otherContent: otherContent);
    expect(
        supertypes,
        equals([
          _isItem(
            'MyClass1',
            otherFileUri,
            detail: 'extends',
            range: otherCode.ranges[0].range,
            selectionRange: otherCode.ranges[1].range,
          ),
        ]));
  }

  Future<void> test_extends() async {
    final content = '''
/*[0*/class /*[1*/MyClass1/*1]*/ {}/*0]*/
class MyCla^ss2 extends MyClass1 {}
''';
    await _fetchSupertypes(content);
    expect(
        supertypes,
        equals([
          _isItem(
            'MyClass1',
            mainFileUri,
            detail: 'extends',
            range: code.ranges[0].range,
            selectionRange: code.ranges[1].range,
          ),
        ]));
  }

  Future<void> test_implements() async {
    final content = '''
/*[0*/class /*[1*/MyClass1/*1]*/ {}/*0]*/
class MyCla^ss2 implements MyClass1 {}
''';
    await _fetchSupertypes(content);
    expect(
        supertypes,
        equals([
          _isExtendsObject,
          _isItem(
            'MyClass1',
            mainFileUri,
            detail: 'implements',
            range: code.ranges[0].range,
            selectionRange: code.ranges[1].range,
          ),
        ]));
  }

  Future<void> test_on() async {
    final content = '''
/*[0*/class /*[1*/MyClass1/*1]*/ {}/*0]*/
mixin MyMix^in1 on MyClass1 {}
''';
    await _fetchSupertypes(content);
    expect(
        supertypes,
        equals([
          _isItem(
            'MyClass1',
            mainFileUri,
            detail: 'constrained to',
            range: code.ranges[0].range,
            selectionRange: code.ranges[1].range,
          ),
        ]));
  }

  Future<void> test_with() async {
    final content = '''
/*[0*/mixin /*[1*/MyMixin1/*1]*/ {}/*0]*/
class MyCla^ss1 with MyMixin1 {}
''';
    await _fetchSupertypes(content);
    expect(
        supertypes,
        equals([
          _isExtendsObject,
          _isItem(
            'MyMixin1',
            mainFileUri,
            detail: 'mixes in',
            range: code.ranges[0].range,
            selectionRange: code.ranges[1].range,
          ),
        ]));
  }

  /// Parses [content], calls 'textDocument/prepareTypeHierarchy' at the
  /// marked location and then calls 'typeHierarchy/supertypes' with the result.
  Future<void> _fetchSupertypes(String content, {String? otherContent}) async {
    await _prepareTypeHierarchy(content, otherContent: otherContent);
    supertypes = await typeHierarchySupertypes(prepareResult!);
  }
}
