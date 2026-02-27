## Trinity Generator

This package is a code generator for the Trinity package.

## Usage

```dart
import 'package:trinity_generator/trinity_generator.dart';

part 'my_node.readable.dart';

@Readable()
class MyNode extends NodeInterface{
  final String name;

  MyNode(this.name);
}
```

Then the generated file

```dart
// ...

class ReadableMyNode {
  final MyNode _node;
  const ReadableMyNode(this._node);

  String get name => _node.name.readable.value;

  ///These properties belong to NodeInterface
  Object? get error => _node.error.value;
  bool get hasError => error != null;
  bool get isLoading => _node.isLoading.value;
}
```
