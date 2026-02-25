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