// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'migration_meta.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$EmbeddingFingerprintGate {
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is EmbeddingFingerprintGate);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'EmbeddingFingerprintGate()';
  }
}

/// @nodoc
class $EmbeddingFingerprintGateCopyWith<$Res> {
  $EmbeddingFingerprintGateCopyWith(
      EmbeddingFingerprintGate _, $Res Function(EmbeddingFingerprintGate) __);
}

/// Adds pattern-matching-related methods to [EmbeddingFingerprintGate].
extension EmbeddingFingerprintGatePatterns on EmbeddingFingerprintGate {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(EmbeddingFingerprintGate_RequiresInitialBaseline value)?
        requiresInitialBaseline,
    TResult Function(EmbeddingFingerprintGate_Ok value)? ok,
    TResult Function(EmbeddingFingerprintGate_Mismatch value)? mismatch,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case EmbeddingFingerprintGate_RequiresInitialBaseline()
          when requiresInitialBaseline != null:
        return requiresInitialBaseline(_that);
      case EmbeddingFingerprintGate_Ok() when ok != null:
        return ok(_that);
      case EmbeddingFingerprintGate_Mismatch() when mismatch != null:
        return mismatch(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(
            EmbeddingFingerprintGate_RequiresInitialBaseline value)
        requiresInitialBaseline,
    required TResult Function(EmbeddingFingerprintGate_Ok value) ok,
    required TResult Function(EmbeddingFingerprintGate_Mismatch value) mismatch,
  }) {
    final _that = this;
    switch (_that) {
      case EmbeddingFingerprintGate_RequiresInitialBaseline():
        return requiresInitialBaseline(_that);
      case EmbeddingFingerprintGate_Ok():
        return ok(_that);
      case EmbeddingFingerprintGate_Mismatch():
        return mismatch(_that);
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(EmbeddingFingerprintGate_RequiresInitialBaseline value)?
        requiresInitialBaseline,
    TResult? Function(EmbeddingFingerprintGate_Ok value)? ok,
    TResult? Function(EmbeddingFingerprintGate_Mismatch value)? mismatch,
  }) {
    final _that = this;
    switch (_that) {
      case EmbeddingFingerprintGate_RequiresInitialBaseline()
          when requiresInitialBaseline != null:
        return requiresInitialBaseline(_that);
      case EmbeddingFingerprintGate_Ok() when ok != null:
        return ok(_that);
      case EmbeddingFingerprintGate_Mismatch() when mismatch != null:
        return mismatch(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? requiresInitialBaseline,
    TResult Function()? ok,
    TResult Function(String stored, String current,
            PlatformInt64 remainingChunks, bool resumeInProgress)?
        mismatch,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case EmbeddingFingerprintGate_RequiresInitialBaseline()
          when requiresInitialBaseline != null:
        return requiresInitialBaseline();
      case EmbeddingFingerprintGate_Ok() when ok != null:
        return ok();
      case EmbeddingFingerprintGate_Mismatch() when mismatch != null:
        return mismatch(_that.stored, _that.current, _that.remainingChunks,
            _that.resumeInProgress);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() requiresInitialBaseline,
    required TResult Function() ok,
    required TResult Function(String stored, String current,
            PlatformInt64 remainingChunks, bool resumeInProgress)
        mismatch,
  }) {
    final _that = this;
    switch (_that) {
      case EmbeddingFingerprintGate_RequiresInitialBaseline():
        return requiresInitialBaseline();
      case EmbeddingFingerprintGate_Ok():
        return ok();
      case EmbeddingFingerprintGate_Mismatch():
        return mismatch(_that.stored, _that.current, _that.remainingChunks,
            _that.resumeInProgress);
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? requiresInitialBaseline,
    TResult? Function()? ok,
    TResult? Function(String stored, String current,
            PlatformInt64 remainingChunks, bool resumeInProgress)?
        mismatch,
  }) {
    final _that = this;
    switch (_that) {
      case EmbeddingFingerprintGate_RequiresInitialBaseline()
          when requiresInitialBaseline != null:
        return requiresInitialBaseline();
      case EmbeddingFingerprintGate_Ok() when ok != null:
        return ok();
      case EmbeddingFingerprintGate_Mismatch() when mismatch != null:
        return mismatch(_that.stored, _that.current, _that.remainingChunks,
            _that.resumeInProgress);
      case _:
        return null;
    }
  }
}

/// @nodoc

class EmbeddingFingerprintGate_RequiresInitialBaseline
    extends EmbeddingFingerprintGate {
  const EmbeddingFingerprintGate_RequiresInitialBaseline() : super._();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is EmbeddingFingerprintGate_RequiresInitialBaseline);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'EmbeddingFingerprintGate.requiresInitialBaseline()';
  }
}

/// @nodoc

class EmbeddingFingerprintGate_Ok extends EmbeddingFingerprintGate {
  const EmbeddingFingerprintGate_Ok() : super._();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is EmbeddingFingerprintGate_Ok);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'EmbeddingFingerprintGate.ok()';
  }
}

/// @nodoc

class EmbeddingFingerprintGate_Mismatch extends EmbeddingFingerprintGate {
  const EmbeddingFingerprintGate_Mismatch(
      {required this.stored,
      required this.current,
      required this.remainingChunks,
      required this.resumeInProgress})
      : super._();

  final String stored;
  final String current;

  /// Number of chunk rows still tagged with a non-current fingerprint.
  /// Useful for surfacing a "resume from N%" UI without an extra
  /// round-trip to count chunks.
  final PlatformInt64 remainingChunks;

  /// True when `embedding_fingerprint_pending` already equals
  /// `current_fingerprint` — i.e. a reembed was previously started and
  /// can simply continue without a fresh user confirmation.
  final bool resumeInProgress;

  /// Create a copy of EmbeddingFingerprintGate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $EmbeddingFingerprintGate_MismatchCopyWith<EmbeddingFingerprintGate_Mismatch>
      get copyWith => _$EmbeddingFingerprintGate_MismatchCopyWithImpl<
          EmbeddingFingerprintGate_Mismatch>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is EmbeddingFingerprintGate_Mismatch &&
            (identical(other.stored, stored) || other.stored == stored) &&
            (identical(other.current, current) || other.current == current) &&
            (identical(other.remainingChunks, remainingChunks) ||
                other.remainingChunks == remainingChunks) &&
            (identical(other.resumeInProgress, resumeInProgress) ||
                other.resumeInProgress == resumeInProgress));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, stored, current, remainingChunks, resumeInProgress);

  @override
  String toString() {
    return 'EmbeddingFingerprintGate.mismatch(stored: $stored, current: $current, remainingChunks: $remainingChunks, resumeInProgress: $resumeInProgress)';
  }
}

/// @nodoc
abstract mixin class $EmbeddingFingerprintGate_MismatchCopyWith<$Res>
    implements $EmbeddingFingerprintGateCopyWith<$Res> {
  factory $EmbeddingFingerprintGate_MismatchCopyWith(
          EmbeddingFingerprintGate_Mismatch value,
          $Res Function(EmbeddingFingerprintGate_Mismatch) _then) =
      _$EmbeddingFingerprintGate_MismatchCopyWithImpl;
  @useResult
  $Res call(
      {String stored,
      String current,
      PlatformInt64 remainingChunks,
      bool resumeInProgress});
}

/// @nodoc
class _$EmbeddingFingerprintGate_MismatchCopyWithImpl<$Res>
    implements $EmbeddingFingerprintGate_MismatchCopyWith<$Res> {
  _$EmbeddingFingerprintGate_MismatchCopyWithImpl(this._self, this._then);

  final EmbeddingFingerprintGate_Mismatch _self;
  final $Res Function(EmbeddingFingerprintGate_Mismatch) _then;

  /// Create a copy of EmbeddingFingerprintGate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? stored = null,
    Object? current = null,
    Object? remainingChunks = null,
    Object? resumeInProgress = null,
  }) {
    return _then(EmbeddingFingerprintGate_Mismatch(
      stored: null == stored
          ? _self.stored
          : stored // ignore: cast_nullable_to_non_nullable
              as String,
      current: null == current
          ? _self.current
          : current // ignore: cast_nullable_to_non_nullable
              as String,
      remainingChunks: null == remainingChunks
          ? _self.remainingChunks
          : remainingChunks // ignore: cast_nullable_to_non_nullable
              as PlatformInt64,
      resumeInProgress: null == resumeInProgress
          ? _self.resumeInProgress
          : resumeInProgress // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

// dart format on
