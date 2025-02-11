// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore: import_of_legacy_library_into_null_safe
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' show basenameWithoutExtension, dirname;

Builder i18NextJsonResolverFactory(BuilderOptions options) => JsonResolver();

class JsonResolver extends Builder {
  static const suffix = '.i18next.export';

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    await buildStep.writeAsString(buildStep.inputId.changeExtension(suffix),
        buildStep.readAsString(buildStep.inputId));
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        '.dart': [suffix]
      };
}

String _capitalize(String text) {
  return "${text.substring(0, 1).toUpperCase()}${text.substring(1, text.length)}";
}

String _generateClassName(String text, {bool isPrivate = false}) {
  final className = _capitalize(text);
  return isPrivate ? "_$className" : className;
}

String _generatePath(List<String> path, String key) {
  return [...path, key].join(".");
}

Builder i18NextClassGeneratorFactory(BuilderOptions options) =>
    I18NextClassGenerator(
        globPattern: options.config['glob_pattern'],
        outFile: options.config['out_file']);

_safeVarialbeName(String key) {
  key = key.replaceAll(RegExp("[- \\/\(\)]"), "_");
  if (['return', 'void'].any((element) => element == key)) {
    key = 'z${key}';
  }
  return key;
}

class I18NextClassGenerator implements Builder {
  String globPattern;
  String outFile;

  I18NextClassGenerator({required this.globPattern, required this.outFile});
  /*
    ===Useful snippets===

    buildStep.findAssets(Glob('lib/i18next/(**)')) // Retuns a list, useful for getting info on files contained in folders, remove the "()" wrapping the "**"

    buildStep.readAsString(buildStep.inputId)  // This returns the content of the .json

    file.writeAsStringSync(await buildStep.readAsString(buildStep.inputId),
        mode: FileMode
            .append); //appends the json content to the new dart file, remove append mode if want to rewrite the file

    file.writeAsStringSync(
        r'class Messages { const Messages(); ButtonMessages get button => ButtonExampleMessages(this); UsersMessages get users => UsersExampleMessages(this);}',
        mode: FileMode.append); //example of appending dart code into new dart file 
  I18NextClassGenerator({
    this.globPattern,
    this..append),
    this.FileMode.append),
  );
    required this.FileMode.append),
  });

    jsonDecode(await buildStep.readAsString(buildStep.inputId)) //Convert json content to dart maps.           

    RegExp(r'(?<={{).*?(?=}})').allMatches(value).toList().length; //Gets amount of dynamic text in a string.

    parameterName.allMatches(value).toList()[0].group(0)  //returns dynamic variable name of first element
   */

  @override
  Future build(BuildStep buildStep) async {
    final allJsonFiles = await buildStep.findAssets(Glob(globPattern)).toList();

    Map<String, Map<String, Map<String, dynamic>>> languageMapping = {};

    for (var jsonFile in allJsonFiles) {
      var language = basenameWithoutExtension(dirname(jsonFile.path));
      var namespace = basenameWithoutExtension(jsonFile.path);
      var json = jsonDecode(await buildStep.readAsString(jsonFile));
      languageMapping[language] ??= {};
      languageMapping[language]?[namespace] = json;
    }
    JsonEncoder encoder = const JsonEncoder.withIndent('  ');

    // validation
    for (var ns in languageMapping.entries) {}

    // generate class file
    var jsonList = languageMapping.entries.first.value.entries;
    final library = LibraryBuilder();
    var topLevelClass = ClassBuilder();
    library.directives.add(Directive.import('package:i18next/i18next.dart'));
    library.directives
        .add(Directive.import('package:json_annotation/json_annotation.dart'));
    library.directives.add(
        Directive.part('${outFile.split('/').last.split('.').first}.g.dart'));

    topLevelClass
      ..name = 'I18n'
      ..fields.add(Field((fb) => fb
        ..name =
            'i18next' // adds a variable with name of 'i18nxt' eg: final I18Next i18next;
        ..modifier = FieldModifier.final$ //Gives it the type of final
        ..type = const Reference('I18Next')))
      ..constructors
          .add(Constructor((cb) => cb.requiredParameters.add(Parameter((p) => p
            ..name = 'i18next' //Affects class constructor
            ..toThis = true))));

    topLevelClass.methods.add(Method((mb) => mb
      ..static = true
      ..requiredParameters.add(Parameter((p) => p..name = 'context'))
      ..name = 'I18n of'
      ..body = Code('return I18n(I18Next.of(context)!);')));

    jsonList.forEach((element) {
      final className = _generateClassName(element.key, isPrivate: true);
      topLevelClass.methods.add(Method((mb) => mb
        ..returns = Reference(className)
        ..type = MethodType.getter
        ..name = _safeVarialbeName(element.key)
        ..body = Code('return $className(\i18next\);')));
    });

    library.body.add(topLevelClass.build());

    List<ClassBuilder> _generateClasses({
      required String namespace,
      required String classname,
      required Map<String, dynamic> json,
      List<String> path = const [],
    }) {
      var _class = ClassBuilder();
      List<ClassBuilder> classes = [];

      // generate constructor and required I18Next variable
      _class
        ..name = classname
        ..annotations.add(
          const Reference('JsonSerializable(createFactory: false)'),
        )
        ..fields.add(
          Field(
            (fb) => fb
              ..name =
                  'i18next' // adds a variable with name of 'i18nxt' eg: final I18Next i18next;
              ..modifier = FieldModifier.final$ //Gives it the type of final
              ..type = const Reference('I18Next')
              ..annotations.add(
                const Reference(
                    'JsonKey(includeFromJson: false, includeToJson: false)'),
              ),
          ),
        )
        ..constructors.add(
          Constructor(
            (cb) => cb.requiredParameters.add(
              Parameter(
                (p) => p
                  ..name = 'i18next' //Affects class constructor
                  ..toThis = true,
              ),
            ),
          ),
        );

      // ListBuilder<Method> methods = ListBuilder();
      for (var translationPair in json.entries) {
        final _translationKey = translationPair.key;
        final _translationValue = translationPair.value;
        // Handles strings with interpolation
        if (_translationValue.runtimeType == String &&
            RegExp(r'(?<={{).*?(?=}})')
                .allMatches(_translationValue)
                .isNotEmpty) {
          var matches = RegExp(r'(?<={{).*?(?=}})')
              .allMatches(_translationValue)
              .toList();
          var translatedMatches =
              matches.map((e) => e.group(0)).toSet().toList();
          Map i18nVariables = {};
          var parameters = {};
          dynamic containsObject; //Checks whether interpolation contains "."
          for (var i in translatedMatches) {
            if (i!.contains('.')) {
              containsObject = true;
              // Removes everything after the '.' if i is an object
              translatedMatches.insert(
                  translatedMatches.indexOf(i), i.toString().split('.')[0]);
              translatedMatches.removeAt(translatedMatches.indexOf(i));
              i = i.substring(0, i.indexOf('.'));
              var keyToString = i;
              keyToString = '"$i"'; // Convert key value to be wrapped by ""
              i18nVariables[keyToString] = i;
              // Refilters the list
              translatedMatches = translatedMatches.toSet().toList();
            }
            // If contains second value eg: uppercase
            else if (i.contains(',')) {
              containsObject = true;
              // Removes everything after the '.' if i is an object
              translatedMatches.insert(
                  translatedMatches.indexOf(i), i.toString().split(',')[0]);
              translatedMatches.removeAt(translatedMatches.indexOf(i));
              i = i.substring(0, i.indexOf(','));
              var keyToString = i;
              keyToString = '"$i"'; // Convert key value to be wrapped by ""
              i18nVariables[keyToString] = i;
              // Refilters the list
              translatedMatches = translatedMatches.toSet().toList();
            }
            // Everything else that isn't "count" goes in here.
            else if (i != 'count') {
              var keyToString = i;
              keyToString = '"$i"'; // Convert key value to be wrapped by ""
              containsObject = true;
              i18nVariables[keyToString] = i;
              // Refilters the list
              translatedMatches = translatedMatches.toSet().toList();
            } else {
              parameters[i] = i;
            }
          }
          _class.methods.add(
            Method(
              (mb) => mb
                ..returns = const Reference("String")
                ..requiredParameters.add(
                    Parameter((p) => p..name = translatedMatches.join(",")))
                ..name = _translationKey
                ..annotations.add(
                  Reference(
                    "JsonKey(name: '${_safeVarialbeName(_translationKey)}')",
                  ),
                )
                ..body = Code(
                    'return i18next!.t(\'$namespace:${_generatePath(path, _translationKey)}\'${containsObject == true ? ", variables: $i18nVariables" : ""}${parameters.toString().isNotEmpty ? ', ' + parameters.toString().substring(1, parameters.toString().length - 1) : ""});'),
            ),
          );
        }
        //Handles nested types
        else if (_translationValue.runtimeType != String) {
          final _classname = "$classname${_capitalize(_translationKey)}";
          final subClass = _generateClasses(
            namespace: namespace,
            classname: _classname,
            json: _translationValue,
            path: [...path, _translationKey],
          );
          classes.addAll(subClass);
          final resp = _generateClassName(_classname);

          _class.methods.add(
            Method((mb) => mb
              ..returns = Reference(resp)
              ..type = MethodType.getter
              ..name = _safeVarialbeName(_translationKey)
              ..annotations.add(
                Reference(
                  "JsonKey(name: '${_safeVarialbeName(_translationKey)}')",
                ),
              )
              ..body = Code("return $resp(i18next);")),
          );
        } else {
          _class.methods.add(
            Method(
              (mb) => mb
                ..returns = const Reference("String")
                ..type = MethodType.getter
                ..name = _safeVarialbeName(_translationKey)
                ..annotations.add(
                  Reference(
                    "JsonKey(name: '${_safeVarialbeName(_translationKey)}')",
                  ),
                )
                ..body = Code(
                    'return i18next!.t(\'$namespace:${_generatePath(path, _translationKey)}\');'),
            ),
          );
        }
      }

      final serializedClassname = classname.replaceAll(RegExp(r'_'), '');

      _class.methods.add(
        Method(
          (mb) => mb
            ..returns = const Reference("Map<String, dynamic>")
            ..name = 'toJson'
            ..body = Code(
              'return _\$${serializedClassname}ToJson(this);',
            ),
        ),
      );

      classes.add(_class);
      return classes;
    }

    // Loops through the files in en-US
    languageMapping.entries.first.value.entries.forEach((entry) {
      var namespace = entry.key; //json file name
      final generatedClasses = _generateClasses(
        namespace: namespace,
        classname: _generateClassName(namespace, isPrivate: true),
        json: entry.value,
      );
      for (var generatedClass in generatedClasses) {
        library.body.add(generatedClass.build());
      }
    });

    final emitter = DartEmitter();
    final finalFile = DartFormatter()
        .format('${library.build().accept(emitter)}'); //dart file content
    File file = File(outFile);
    file.writeAsStringSync(finalFile);
  }

  @override
  final buildExtensions = const {
    r'$lib$': ['i18next.dart']
  };
}
