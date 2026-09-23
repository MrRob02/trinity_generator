import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

enum EnumDefaultSignals { error, loading }

class NodeGenerator extends Generator {
  @override
  String? generate(LibraryReader library, BuildStep buildStep) {
    final buffer = StringBuffer();

    for (final cls in library.classes) {
      if (!_hasReadableAnnotation(cls)) continue;
      if (!_extendsNodeInterface(cls)) continue;

      final signalFields = _getSignalFields(cls);
      // if (signalFields.isEmpty) continue;
      final className = cls.name;
      final readableName = 'Readable$className';

      buffer.writeln('class $readableName {');
      buffer.writeln('  final $className _node;');
      buffer.writeln('  const $readableName(this._node);');
      buffer.writeln();

      for (final field in signalFields) {
        if (field.isPrivate) continue;
        final isNullable = _isNullableSignal(field.type);
        final valueType = _resolveSignalValueType(field);
        final accessor = _isBaseSignalOnly(_unwrapNullable(field.type))
            ? (isNullable ? '?.value' : '.value')
            : (isNullable ? '?.readable.value' : '.readable.value');
        buffer.writeln(
          '  $valueType get ${field.name} => '
          '_node.${field.name}$accessor;',
        );
      }
      buffer.writeln('  Object? get error => _node.error.value;');
      buffer.writeln('  bool get hasError => error != null;');
      buffer.writeln('  bool get isLoading => _node.isLoading.value;');
      buffer.writeln(
        '  bool get fullScreenLoading => _node.fullScreenLoading.value;',
      );

      buffer.writeln('}');
      buffer.writeln();
    }

    if (buffer.isEmpty) return null;
    // Obtiene el nombre del archivo fuente para el part of
    final sourceUri = library.element.firstFragment.source.uri;
    final fileName = sourceUri.pathSegments.last;
    return "part of '$fileName';\n\n$buffer";
  }

  // Returns true if the class is annotated with @Readable or @readable
  bool _hasReadableAnnotation(ClassElement cls) {
    return cls.metadata.annotations.any(
      (a) => a.element?.enclosingElement?.name == 'Readable',
    );
  }

  // Sube la cadena de herencia buscando NodeInterface
  bool _extendsNodeInterface(ClassElement cls) {
    var supertype = cls.supertype;
    while (supertype != null) {
      if (supertype.element.name == 'NodeInterface') return true;
      supertype = supertype.element.supertype;
    }
    return false;
  }

  // Campos cuyo tipo sea Signal<T> o derive de él.
  // Incluye campos con inicializador inline (late final x = registerSignal(...))
  // y también campos `late` declarados con tipo explícito pero inicializados
  // en el constructor (late final Signal<T> x; → this.x = registerSignal(...)).
  List<FieldElement> _getSignalFields(ClassElement cls) {
    return cls.fields
        .where(
          (f) =>
              !f.isOriginGetterSetter &&
              (_isSignal(f.type) || _isNullableSignal(f.type)),
        )
        .toList();
  }

  /// Returns true when [type] is a nullable signal type, e.g. `Signal<T>?`.
  bool _isNullableSignal(DartType type) {
    if (type is! InvalidType && type.nullabilitySuffix == NullabilitySuffix.question) {
      return _isSignal(_unwrapNullable(type));
    }
    return false;
  }

  /// Strips the `?` suffix from a nullable type, returning the underlying type.
  DartType _unwrapNullable(DartType type) {
    if (type is InterfaceType && type.nullabilitySuffix == NullabilitySuffix.question) {
      // Re-wrap as non-nullable by accessing the element's type directly.
      return type.element.thisType;
    }
    return type;
  }

  bool _isSignal(DartType type) {
    if (type is! InterfaceType) return false;
    if (type.nullabilitySuffix == NullabilitySuffix.question) return false;
    if (type.element.name == 'Signal') return true;
    return type.element.allSupertypes.any(
      (t) => t.element.name == 'BaseSignal',
    );
  }

  /// Returns true when the type derives from BaseSignal but NOT from Signal
  /// (i.e. it has no .readable — access via .value directly).
  /// Pass the already-unwrapped (non-nullable) type.
  bool _isBaseSignalOnly(DartType type) {
    if (type is! InterfaceType) return false;
    if (type.element.name == 'BaseSignal') return true;
    final supertypes = type.element.allSupertypes;
    final hasBaseSignal = supertypes.any((t) => t.element.name == 'BaseSignal');
    final hasSignal = supertypes.any((t) => t.element.name == 'Signal');
    return hasBaseSignal && !hasSignal;
  }

  // Extrae T de Signal<T> (o Signal<T>?), subiendo supertypes si hace falta.
  // Si el campo es nullable, el tipo resultante también es nullable (T?).
  String _resolveSignalValueType(FieldElement field) {
    final rawType = field.type;
    final isNullable = _isNullableSignal(rawType);
    // Use rawType directly — an InterfaceType with NullabilitySuffix.question
    // already carries the concrete type arguments (e.g. Signal<String>?).
    // _unwrapNullable would call element.thisType which strips instantiation
    // back to the raw generic (e.g. Signal<V>), losing the actual type arg.
    if (rawType is! InterfaceType) return isNullable ? 'dynamic?' : 'dynamic';

    String valueType;

    // Si el tipo ya ES Signal<T>, tomamos el argumento directo
    if (rawType.element.name == 'Signal') {
      if (rawType.typeArguments.isEmpty) {
        valueType = 'dynamic';
      } else {
        valueType = rawType.typeArguments.first.getDisplayString();
      }
    } else {
      // Si es subtype (BridgeSignal, ProtectedSignal, etc.), buscamos en los
      // supertypes del TIPO INSTANCIADO (no del elemento).
      // Primero intentamos con Signal<T>; si no existe (e.g. ProtectedSignal
      // hereda directamente de BaseSignal<T>), caemos a BaseSignal<T>.
      final allSupertypes = rawType.allSupertypes;

      final signalType =
          allSupertypes.where((t) => t.element.name == 'Signal').firstOrNull ??
          allSupertypes
              .where((t) => t.element.name == 'BaseSignal')
              .firstOrNull;

      if (signalType == null || signalType.typeArguments.isEmpty) {
        valueType = 'dynamic';
      } else {
        valueType = signalType.typeArguments.first.getDisplayString();
      }
    }

    // If the field itself is nullable, the exposed getter must also be nullable.
    // Avoid double `?` if the inner type is already nullable (e.g. Signal<T?>).
    if (isNullable && !valueType.endsWith('?')) {
      valueType = '$valueType?';
    }

    return valueType;
  }
}
