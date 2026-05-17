// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RagError {

 String get field0;
/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagErrorCopyWith<RagError> get copyWith => _$RagErrorCopyWithImpl<RagError>(this as RagError, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RagError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RagErrorCopyWith<$Res>  {
  factory $RagErrorCopyWith(RagError value, $Res Function(RagError) _then) = _$RagErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RagErrorCopyWithImpl<$Res>
    implements $RagErrorCopyWith<$Res> {
  _$RagErrorCopyWithImpl(this._self, this._then);

  final RagError _self;
  final $Res Function(RagError) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field0 = null,}) {
  return _then(_self.copyWith(
field0: null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RagError].
extension RagErrorPatterns on RagError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RagError_DatabaseError value)?  databaseError,TResult Function( RagError_IoError value)?  ioError,TResult Function( RagError_ModelLoadError value)?  modelLoadError,TResult Function( RagError_InvalidInput value)?  invalidInput,TResult Function( RagError_StaleSearchHandle value)?  staleSearchHandle,TResult Function( RagError_ConcurrentMutation value)?  concurrentMutation,TResult Function( RagError_InternalError value)?  internalError,TResult Function( RagError_UnsupportedMigrationVersion value)?  unsupportedMigrationVersion,TResult Function( RagError_EmbeddingFingerprintMismatch value)?  embeddingFingerprintMismatch,TResult Function( RagError_Unknown value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RagError_DatabaseError() when databaseError != null:
return databaseError(_that);case RagError_IoError() when ioError != null:
return ioError(_that);case RagError_ModelLoadError() when modelLoadError != null:
return modelLoadError(_that);case RagError_InvalidInput() when invalidInput != null:
return invalidInput(_that);case RagError_StaleSearchHandle() when staleSearchHandle != null:
return staleSearchHandle(_that);case RagError_ConcurrentMutation() when concurrentMutation != null:
return concurrentMutation(_that);case RagError_InternalError() when internalError != null:
return internalError(_that);case RagError_UnsupportedMigrationVersion() when unsupportedMigrationVersion != null:
return unsupportedMigrationVersion(_that);case RagError_EmbeddingFingerprintMismatch() when embeddingFingerprintMismatch != null:
return embeddingFingerprintMismatch(_that);case RagError_Unknown() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RagError_DatabaseError value)  databaseError,required TResult Function( RagError_IoError value)  ioError,required TResult Function( RagError_ModelLoadError value)  modelLoadError,required TResult Function( RagError_InvalidInput value)  invalidInput,required TResult Function( RagError_StaleSearchHandle value)  staleSearchHandle,required TResult Function( RagError_ConcurrentMutation value)  concurrentMutation,required TResult Function( RagError_InternalError value)  internalError,required TResult Function( RagError_UnsupportedMigrationVersion value)  unsupportedMigrationVersion,required TResult Function( RagError_EmbeddingFingerprintMismatch value)  embeddingFingerprintMismatch,required TResult Function( RagError_Unknown value)  unknown,}){
final _that = this;
switch (_that) {
case RagError_DatabaseError():
return databaseError(_that);case RagError_IoError():
return ioError(_that);case RagError_ModelLoadError():
return modelLoadError(_that);case RagError_InvalidInput():
return invalidInput(_that);case RagError_StaleSearchHandle():
return staleSearchHandle(_that);case RagError_ConcurrentMutation():
return concurrentMutation(_that);case RagError_InternalError():
return internalError(_that);case RagError_UnsupportedMigrationVersion():
return unsupportedMigrationVersion(_that);case RagError_EmbeddingFingerprintMismatch():
return embeddingFingerprintMismatch(_that);case RagError_Unknown():
return unknown(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RagError_DatabaseError value)?  databaseError,TResult? Function( RagError_IoError value)?  ioError,TResult? Function( RagError_ModelLoadError value)?  modelLoadError,TResult? Function( RagError_InvalidInput value)?  invalidInput,TResult? Function( RagError_StaleSearchHandle value)?  staleSearchHandle,TResult? Function( RagError_ConcurrentMutation value)?  concurrentMutation,TResult? Function( RagError_InternalError value)?  internalError,TResult? Function( RagError_UnsupportedMigrationVersion value)?  unsupportedMigrationVersion,TResult? Function( RagError_EmbeddingFingerprintMismatch value)?  embeddingFingerprintMismatch,TResult? Function( RagError_Unknown value)?  unknown,}){
final _that = this;
switch (_that) {
case RagError_DatabaseError() when databaseError != null:
return databaseError(_that);case RagError_IoError() when ioError != null:
return ioError(_that);case RagError_ModelLoadError() when modelLoadError != null:
return modelLoadError(_that);case RagError_InvalidInput() when invalidInput != null:
return invalidInput(_that);case RagError_StaleSearchHandle() when staleSearchHandle != null:
return staleSearchHandle(_that);case RagError_ConcurrentMutation() when concurrentMutation != null:
return concurrentMutation(_that);case RagError_InternalError() when internalError != null:
return internalError(_that);case RagError_UnsupportedMigrationVersion() when unsupportedMigrationVersion != null:
return unsupportedMigrationVersion(_that);case RagError_EmbeddingFingerprintMismatch() when embeddingFingerprintMismatch != null:
return embeddingFingerprintMismatch(_that);case RagError_Unknown() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  databaseError,TResult Function( String field0)?  ioError,TResult Function( String field0)?  modelLoadError,TResult Function( String field0)?  invalidInput,TResult Function( String field0)?  staleSearchHandle,TResult Function( String field0)?  concurrentMutation,TResult Function( String field0)?  internalError,TResult Function( String field0,  PlatformInt64 field1,  PlatformInt64 field2)?  unsupportedMigrationVersion,TResult Function( String field0,  String field1,  PlatformInt64 field2)?  embeddingFingerprintMismatch,TResult Function( String field0)?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RagError_DatabaseError() when databaseError != null:
return databaseError(_that.field0);case RagError_IoError() when ioError != null:
return ioError(_that.field0);case RagError_ModelLoadError() when modelLoadError != null:
return modelLoadError(_that.field0);case RagError_InvalidInput() when invalidInput != null:
return invalidInput(_that.field0);case RagError_StaleSearchHandle() when staleSearchHandle != null:
return staleSearchHandle(_that.field0);case RagError_ConcurrentMutation() when concurrentMutation != null:
return concurrentMutation(_that.field0);case RagError_InternalError() when internalError != null:
return internalError(_that.field0);case RagError_UnsupportedMigrationVersion() when unsupportedMigrationVersion != null:
return unsupportedMigrationVersion(_that.field0,_that.field1,_that.field2);case RagError_EmbeddingFingerprintMismatch() when embeddingFingerprintMismatch != null:
return embeddingFingerprintMismatch(_that.field0,_that.field1,_that.field2);case RagError_Unknown() when unknown != null:
return unknown(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  databaseError,required TResult Function( String field0)  ioError,required TResult Function( String field0)  modelLoadError,required TResult Function( String field0)  invalidInput,required TResult Function( String field0)  staleSearchHandle,required TResult Function( String field0)  concurrentMutation,required TResult Function( String field0)  internalError,required TResult Function( String field0,  PlatformInt64 field1,  PlatformInt64 field2)  unsupportedMigrationVersion,required TResult Function( String field0,  String field1,  PlatformInt64 field2)  embeddingFingerprintMismatch,required TResult Function( String field0)  unknown,}) {final _that = this;
switch (_that) {
case RagError_DatabaseError():
return databaseError(_that.field0);case RagError_IoError():
return ioError(_that.field0);case RagError_ModelLoadError():
return modelLoadError(_that.field0);case RagError_InvalidInput():
return invalidInput(_that.field0);case RagError_StaleSearchHandle():
return staleSearchHandle(_that.field0);case RagError_ConcurrentMutation():
return concurrentMutation(_that.field0);case RagError_InternalError():
return internalError(_that.field0);case RagError_UnsupportedMigrationVersion():
return unsupportedMigrationVersion(_that.field0,_that.field1,_that.field2);case RagError_EmbeddingFingerprintMismatch():
return embeddingFingerprintMismatch(_that.field0,_that.field1,_that.field2);case RagError_Unknown():
return unknown(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  databaseError,TResult? Function( String field0)?  ioError,TResult? Function( String field0)?  modelLoadError,TResult? Function( String field0)?  invalidInput,TResult? Function( String field0)?  staleSearchHandle,TResult? Function( String field0)?  concurrentMutation,TResult? Function( String field0)?  internalError,TResult? Function( String field0,  PlatformInt64 field1,  PlatformInt64 field2)?  unsupportedMigrationVersion,TResult? Function( String field0,  String field1,  PlatformInt64 field2)?  embeddingFingerprintMismatch,TResult? Function( String field0)?  unknown,}) {final _that = this;
switch (_that) {
case RagError_DatabaseError() when databaseError != null:
return databaseError(_that.field0);case RagError_IoError() when ioError != null:
return ioError(_that.field0);case RagError_ModelLoadError() when modelLoadError != null:
return modelLoadError(_that.field0);case RagError_InvalidInput() when invalidInput != null:
return invalidInput(_that.field0);case RagError_StaleSearchHandle() when staleSearchHandle != null:
return staleSearchHandle(_that.field0);case RagError_ConcurrentMutation() when concurrentMutation != null:
return concurrentMutation(_that.field0);case RagError_InternalError() when internalError != null:
return internalError(_that.field0);case RagError_UnsupportedMigrationVersion() when unsupportedMigrationVersion != null:
return unsupportedMigrationVersion(_that.field0,_that.field1,_that.field2);case RagError_EmbeddingFingerprintMismatch() when embeddingFingerprintMismatch != null:
return embeddingFingerprintMismatch(_that.field0,_that.field1,_that.field2);case RagError_Unknown() when unknown != null:
return unknown(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class RagError_DatabaseError extends RagError {
  const RagError_DatabaseError(this.field0): super._();
  

@override final  String field0;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagError_DatabaseErrorCopyWith<RagError_DatabaseError> get copyWith => _$RagError_DatabaseErrorCopyWithImpl<RagError_DatabaseError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError_DatabaseError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RagError.databaseError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RagError_DatabaseErrorCopyWith<$Res> implements $RagErrorCopyWith<$Res> {
  factory $RagError_DatabaseErrorCopyWith(RagError_DatabaseError value, $Res Function(RagError_DatabaseError) _then) = _$RagError_DatabaseErrorCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RagError_DatabaseErrorCopyWithImpl<$Res>
    implements $RagError_DatabaseErrorCopyWith<$Res> {
  _$RagError_DatabaseErrorCopyWithImpl(this._self, this._then);

  final RagError_DatabaseError _self;
  final $Res Function(RagError_DatabaseError) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RagError_DatabaseError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RagError_IoError extends RagError {
  const RagError_IoError(this.field0): super._();
  

@override final  String field0;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagError_IoErrorCopyWith<RagError_IoError> get copyWith => _$RagError_IoErrorCopyWithImpl<RagError_IoError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError_IoError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RagError.ioError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RagError_IoErrorCopyWith<$Res> implements $RagErrorCopyWith<$Res> {
  factory $RagError_IoErrorCopyWith(RagError_IoError value, $Res Function(RagError_IoError) _then) = _$RagError_IoErrorCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RagError_IoErrorCopyWithImpl<$Res>
    implements $RagError_IoErrorCopyWith<$Res> {
  _$RagError_IoErrorCopyWithImpl(this._self, this._then);

  final RagError_IoError _self;
  final $Res Function(RagError_IoError) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RagError_IoError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RagError_ModelLoadError extends RagError {
  const RagError_ModelLoadError(this.field0): super._();
  

@override final  String field0;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagError_ModelLoadErrorCopyWith<RagError_ModelLoadError> get copyWith => _$RagError_ModelLoadErrorCopyWithImpl<RagError_ModelLoadError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError_ModelLoadError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RagError.modelLoadError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RagError_ModelLoadErrorCopyWith<$Res> implements $RagErrorCopyWith<$Res> {
  factory $RagError_ModelLoadErrorCopyWith(RagError_ModelLoadError value, $Res Function(RagError_ModelLoadError) _then) = _$RagError_ModelLoadErrorCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RagError_ModelLoadErrorCopyWithImpl<$Res>
    implements $RagError_ModelLoadErrorCopyWith<$Res> {
  _$RagError_ModelLoadErrorCopyWithImpl(this._self, this._then);

  final RagError_ModelLoadError _self;
  final $Res Function(RagError_ModelLoadError) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RagError_ModelLoadError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RagError_InvalidInput extends RagError {
  const RagError_InvalidInput(this.field0): super._();
  

@override final  String field0;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagError_InvalidInputCopyWith<RagError_InvalidInput> get copyWith => _$RagError_InvalidInputCopyWithImpl<RagError_InvalidInput>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError_InvalidInput&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RagError.invalidInput(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RagError_InvalidInputCopyWith<$Res> implements $RagErrorCopyWith<$Res> {
  factory $RagError_InvalidInputCopyWith(RagError_InvalidInput value, $Res Function(RagError_InvalidInput) _then) = _$RagError_InvalidInputCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RagError_InvalidInputCopyWithImpl<$Res>
    implements $RagError_InvalidInputCopyWith<$Res> {
  _$RagError_InvalidInputCopyWithImpl(this._self, this._then);

  final RagError_InvalidInput _self;
  final $Res Function(RagError_InvalidInput) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RagError_InvalidInput(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RagError_StaleSearchHandle extends RagError {
  const RagError_StaleSearchHandle(this.field0): super._();
  

@override final  String field0;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagError_StaleSearchHandleCopyWith<RagError_StaleSearchHandle> get copyWith => _$RagError_StaleSearchHandleCopyWithImpl<RagError_StaleSearchHandle>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError_StaleSearchHandle&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RagError.staleSearchHandle(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RagError_StaleSearchHandleCopyWith<$Res> implements $RagErrorCopyWith<$Res> {
  factory $RagError_StaleSearchHandleCopyWith(RagError_StaleSearchHandle value, $Res Function(RagError_StaleSearchHandle) _then) = _$RagError_StaleSearchHandleCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RagError_StaleSearchHandleCopyWithImpl<$Res>
    implements $RagError_StaleSearchHandleCopyWith<$Res> {
  _$RagError_StaleSearchHandleCopyWithImpl(this._self, this._then);

  final RagError_StaleSearchHandle _self;
  final $Res Function(RagError_StaleSearchHandle) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RagError_StaleSearchHandle(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RagError_ConcurrentMutation extends RagError {
  const RagError_ConcurrentMutation(this.field0): super._();
  

@override final  String field0;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagError_ConcurrentMutationCopyWith<RagError_ConcurrentMutation> get copyWith => _$RagError_ConcurrentMutationCopyWithImpl<RagError_ConcurrentMutation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError_ConcurrentMutation&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RagError.concurrentMutation(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RagError_ConcurrentMutationCopyWith<$Res> implements $RagErrorCopyWith<$Res> {
  factory $RagError_ConcurrentMutationCopyWith(RagError_ConcurrentMutation value, $Res Function(RagError_ConcurrentMutation) _then) = _$RagError_ConcurrentMutationCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RagError_ConcurrentMutationCopyWithImpl<$Res>
    implements $RagError_ConcurrentMutationCopyWith<$Res> {
  _$RagError_ConcurrentMutationCopyWithImpl(this._self, this._then);

  final RagError_ConcurrentMutation _self;
  final $Res Function(RagError_ConcurrentMutation) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RagError_ConcurrentMutation(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RagError_InternalError extends RagError {
  const RagError_InternalError(this.field0): super._();
  

@override final  String field0;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagError_InternalErrorCopyWith<RagError_InternalError> get copyWith => _$RagError_InternalErrorCopyWithImpl<RagError_InternalError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError_InternalError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RagError.internalError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RagError_InternalErrorCopyWith<$Res> implements $RagErrorCopyWith<$Res> {
  factory $RagError_InternalErrorCopyWith(RagError_InternalError value, $Res Function(RagError_InternalError) _then) = _$RagError_InternalErrorCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RagError_InternalErrorCopyWithImpl<$Res>
    implements $RagError_InternalErrorCopyWith<$Res> {
  _$RagError_InternalErrorCopyWithImpl(this._self, this._then);

  final RagError_InternalError _self;
  final $Res Function(RagError_InternalError) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RagError_InternalError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RagError_UnsupportedMigrationVersion extends RagError {
  const RagError_UnsupportedMigrationVersion(this.field0, this.field1, this.field2): super._();
  

@override final  String field0;
 final  PlatformInt64 field1;
 final  PlatformInt64 field2;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagError_UnsupportedMigrationVersionCopyWith<RagError_UnsupportedMigrationVersion> get copyWith => _$RagError_UnsupportedMigrationVersionCopyWithImpl<RagError_UnsupportedMigrationVersion>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError_UnsupportedMigrationVersion&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1)&&(identical(other.field2, field2) || other.field2 == field2));
}


@override
int get hashCode => Object.hash(runtimeType,field0,field1,field2);

@override
String toString() {
  return 'RagError.unsupportedMigrationVersion(field0: $field0, field1: $field1, field2: $field2)';
}


}

/// @nodoc
abstract mixin class $RagError_UnsupportedMigrationVersionCopyWith<$Res> implements $RagErrorCopyWith<$Res> {
  factory $RagError_UnsupportedMigrationVersionCopyWith(RagError_UnsupportedMigrationVersion value, $Res Function(RagError_UnsupportedMigrationVersion) _then) = _$RagError_UnsupportedMigrationVersionCopyWithImpl;
@override @useResult
$Res call({
 String field0, PlatformInt64 field1, PlatformInt64 field2
});




}
/// @nodoc
class _$RagError_UnsupportedMigrationVersionCopyWithImpl<$Res>
    implements $RagError_UnsupportedMigrationVersionCopyWith<$Res> {
  _$RagError_UnsupportedMigrationVersionCopyWithImpl(this._self, this._then);

  final RagError_UnsupportedMigrationVersion _self;
  final $Res Function(RagError_UnsupportedMigrationVersion) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,Object? field2 = null,}) {
  return _then(RagError_UnsupportedMigrationVersion(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as PlatformInt64,null == field2 ? _self.field2 : field2 // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class RagError_EmbeddingFingerprintMismatch extends RagError {
  const RagError_EmbeddingFingerprintMismatch(this.field0, this.field1, this.field2): super._();
  

@override final  String field0;
 final  String field1;
 final  PlatformInt64 field2;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagError_EmbeddingFingerprintMismatchCopyWith<RagError_EmbeddingFingerprintMismatch> get copyWith => _$RagError_EmbeddingFingerprintMismatchCopyWithImpl<RagError_EmbeddingFingerprintMismatch>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError_EmbeddingFingerprintMismatch&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1)&&(identical(other.field2, field2) || other.field2 == field2));
}


@override
int get hashCode => Object.hash(runtimeType,field0,field1,field2);

@override
String toString() {
  return 'RagError.embeddingFingerprintMismatch(field0: $field0, field1: $field1, field2: $field2)';
}


}

/// @nodoc
abstract mixin class $RagError_EmbeddingFingerprintMismatchCopyWith<$Res> implements $RagErrorCopyWith<$Res> {
  factory $RagError_EmbeddingFingerprintMismatchCopyWith(RagError_EmbeddingFingerprintMismatch value, $Res Function(RagError_EmbeddingFingerprintMismatch) _then) = _$RagError_EmbeddingFingerprintMismatchCopyWithImpl;
@override @useResult
$Res call({
 String field0, String field1, PlatformInt64 field2
});




}
/// @nodoc
class _$RagError_EmbeddingFingerprintMismatchCopyWithImpl<$Res>
    implements $RagError_EmbeddingFingerprintMismatchCopyWith<$Res> {
  _$RagError_EmbeddingFingerprintMismatchCopyWithImpl(this._self, this._then);

  final RagError_EmbeddingFingerprintMismatch _self;
  final $Res Function(RagError_EmbeddingFingerprintMismatch) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,Object? field2 = null,}) {
  return _then(RagError_EmbeddingFingerprintMismatch(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as String,null == field2 ? _self.field2 : field2 // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class RagError_Unknown extends RagError {
  const RagError_Unknown(this.field0): super._();
  

@override final  String field0;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RagError_UnknownCopyWith<RagError_Unknown> get copyWith => _$RagError_UnknownCopyWithImpl<RagError_Unknown>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RagError_Unknown&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RagError.unknown(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RagError_UnknownCopyWith<$Res> implements $RagErrorCopyWith<$Res> {
  factory $RagError_UnknownCopyWith(RagError_Unknown value, $Res Function(RagError_Unknown) _then) = _$RagError_UnknownCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RagError_UnknownCopyWithImpl<$Res>
    implements $RagError_UnknownCopyWith<$Res> {
  _$RagError_UnknownCopyWithImpl(this._self, this._then);

  final RagError_Unknown _self;
  final $Res Function(RagError_Unknown) _then;

/// Create a copy of RagError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RagError_Unknown(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
