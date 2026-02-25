/// Annotation that marks a [NodeInterface] class for code generation.
///
/// When a class is annotated with [@Readable], the [NodeGenerator]
/// will generate a `Readable<ClassName>` wrapper exposing the readable
/// values of all [Signal] fields.
///
/// Example:
/// ```dart
/// @Readable()
/// class CounterNode extends NodeInterface {
///   final counter = Signal(0);
/// }
/// ```
class Readable {
  const Readable();
}

/// Convenience constant so you can write `@readable` instead of `@Readable()`.
const readable = Readable();
