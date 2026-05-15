// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_intent.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UserIntent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserIntent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'UserIntent()';
}


}

/// @nodoc
class $UserIntentCopyWith<$Res>  {
$UserIntentCopyWith(UserIntent _, $Res Function(UserIntent) __);
}


/// Adds pattern-matching-related methods to [UserIntent].
extension UserIntentPatterns on UserIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UserIntent_Summary value)?  summary,TResult Function( UserIntent_Define value)?  define,TResult Function( UserIntent_ExpandKnowledge value)?  expandKnowledge,TResult Function( UserIntent_General value)?  general,TResult Function( UserIntent_InvalidCommand value)?  invalidCommand,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UserIntent_Summary() when summary != null:
return summary(_that);case UserIntent_Define() when define != null:
return define(_that);case UserIntent_ExpandKnowledge() when expandKnowledge != null:
return expandKnowledge(_that);case UserIntent_General() when general != null:
return general(_that);case UserIntent_InvalidCommand() when invalidCommand != null:
return invalidCommand(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UserIntent_Summary value)  summary,required TResult Function( UserIntent_Define value)  define,required TResult Function( UserIntent_ExpandKnowledge value)  expandKnowledge,required TResult Function( UserIntent_General value)  general,required TResult Function( UserIntent_InvalidCommand value)  invalidCommand,}){
final _that = this;
switch (_that) {
case UserIntent_Summary():
return summary(_that);case UserIntent_Define():
return define(_that);case UserIntent_ExpandKnowledge():
return expandKnowledge(_that);case UserIntent_General():
return general(_that);case UserIntent_InvalidCommand():
return invalidCommand(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UserIntent_Summary value)?  summary,TResult? Function( UserIntent_Define value)?  define,TResult? Function( UserIntent_ExpandKnowledge value)?  expandKnowledge,TResult? Function( UserIntent_General value)?  general,TResult? Function( UserIntent_InvalidCommand value)?  invalidCommand,}){
final _that = this;
switch (_that) {
case UserIntent_Summary() when summary != null:
return summary(_that);case UserIntent_Define() when define != null:
return define(_that);case UserIntent_ExpandKnowledge() when expandKnowledge != null:
return expandKnowledge(_that);case UserIntent_General() when general != null:
return general(_that);case UserIntent_InvalidCommand() when invalidCommand != null:
return invalidCommand(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String query)?  summary,TResult Function( String term)?  define,TResult Function( String query)?  expandKnowledge,TResult Function( String query)?  general,TResult Function( String command,  String reason)?  invalidCommand,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UserIntent_Summary() when summary != null:
return summary(_that.query);case UserIntent_Define() when define != null:
return define(_that.term);case UserIntent_ExpandKnowledge() when expandKnowledge != null:
return expandKnowledge(_that.query);case UserIntent_General() when general != null:
return general(_that.query);case UserIntent_InvalidCommand() when invalidCommand != null:
return invalidCommand(_that.command,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String query)  summary,required TResult Function( String term)  define,required TResult Function( String query)  expandKnowledge,required TResult Function( String query)  general,required TResult Function( String command,  String reason)  invalidCommand,}) {final _that = this;
switch (_that) {
case UserIntent_Summary():
return summary(_that.query);case UserIntent_Define():
return define(_that.term);case UserIntent_ExpandKnowledge():
return expandKnowledge(_that.query);case UserIntent_General():
return general(_that.query);case UserIntent_InvalidCommand():
return invalidCommand(_that.command,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String query)?  summary,TResult? Function( String term)?  define,TResult? Function( String query)?  expandKnowledge,TResult? Function( String query)?  general,TResult? Function( String command,  String reason)?  invalidCommand,}) {final _that = this;
switch (_that) {
case UserIntent_Summary() when summary != null:
return summary(_that.query);case UserIntent_Define() when define != null:
return define(_that.term);case UserIntent_ExpandKnowledge() when expandKnowledge != null:
return expandKnowledge(_that.query);case UserIntent_General() when general != null:
return general(_that.query);case UserIntent_InvalidCommand() when invalidCommand != null:
return invalidCommand(_that.command,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class UserIntent_Summary extends UserIntent {
  const UserIntent_Summary({required this.query}): super._();
  

 final  String query;

/// Create a copy of UserIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserIntent_SummaryCopyWith<UserIntent_Summary> get copyWith => _$UserIntent_SummaryCopyWithImpl<UserIntent_Summary>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserIntent_Summary&&(identical(other.query, query) || other.query == query));
}


@override
int get hashCode => Object.hash(runtimeType,query);

@override
String toString() {
  return 'UserIntent.summary(query: $query)';
}


}

/// @nodoc
abstract mixin class $UserIntent_SummaryCopyWith<$Res> implements $UserIntentCopyWith<$Res> {
  factory $UserIntent_SummaryCopyWith(UserIntent_Summary value, $Res Function(UserIntent_Summary) _then) = _$UserIntent_SummaryCopyWithImpl;
@useResult
$Res call({
 String query
});




}
/// @nodoc
class _$UserIntent_SummaryCopyWithImpl<$Res>
    implements $UserIntent_SummaryCopyWith<$Res> {
  _$UserIntent_SummaryCopyWithImpl(this._self, this._then);

  final UserIntent_Summary _self;
  final $Res Function(UserIntent_Summary) _then;

/// Create a copy of UserIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? query = null,}) {
  return _then(UserIntent_Summary(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class UserIntent_Define extends UserIntent {
  const UserIntent_Define({required this.term}): super._();
  

 final  String term;

/// Create a copy of UserIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserIntent_DefineCopyWith<UserIntent_Define> get copyWith => _$UserIntent_DefineCopyWithImpl<UserIntent_Define>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserIntent_Define&&(identical(other.term, term) || other.term == term));
}


@override
int get hashCode => Object.hash(runtimeType,term);

@override
String toString() {
  return 'UserIntent.define(term: $term)';
}


}

/// @nodoc
abstract mixin class $UserIntent_DefineCopyWith<$Res> implements $UserIntentCopyWith<$Res> {
  factory $UserIntent_DefineCopyWith(UserIntent_Define value, $Res Function(UserIntent_Define) _then) = _$UserIntent_DefineCopyWithImpl;
@useResult
$Res call({
 String term
});




}
/// @nodoc
class _$UserIntent_DefineCopyWithImpl<$Res>
    implements $UserIntent_DefineCopyWith<$Res> {
  _$UserIntent_DefineCopyWithImpl(this._self, this._then);

  final UserIntent_Define _self;
  final $Res Function(UserIntent_Define) _then;

/// Create a copy of UserIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? term = null,}) {
  return _then(UserIntent_Define(
term: null == term ? _self.term : term // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class UserIntent_ExpandKnowledge extends UserIntent {
  const UserIntent_ExpandKnowledge({required this.query}): super._();
  

 final  String query;

/// Create a copy of UserIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserIntent_ExpandKnowledgeCopyWith<UserIntent_ExpandKnowledge> get copyWith => _$UserIntent_ExpandKnowledgeCopyWithImpl<UserIntent_ExpandKnowledge>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserIntent_ExpandKnowledge&&(identical(other.query, query) || other.query == query));
}


@override
int get hashCode => Object.hash(runtimeType,query);

@override
String toString() {
  return 'UserIntent.expandKnowledge(query: $query)';
}


}

/// @nodoc
abstract mixin class $UserIntent_ExpandKnowledgeCopyWith<$Res> implements $UserIntentCopyWith<$Res> {
  factory $UserIntent_ExpandKnowledgeCopyWith(UserIntent_ExpandKnowledge value, $Res Function(UserIntent_ExpandKnowledge) _then) = _$UserIntent_ExpandKnowledgeCopyWithImpl;
@useResult
$Res call({
 String query
});




}
/// @nodoc
class _$UserIntent_ExpandKnowledgeCopyWithImpl<$Res>
    implements $UserIntent_ExpandKnowledgeCopyWith<$Res> {
  _$UserIntent_ExpandKnowledgeCopyWithImpl(this._self, this._then);

  final UserIntent_ExpandKnowledge _self;
  final $Res Function(UserIntent_ExpandKnowledge) _then;

/// Create a copy of UserIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? query = null,}) {
  return _then(UserIntent_ExpandKnowledge(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class UserIntent_General extends UserIntent {
  const UserIntent_General({required this.query}): super._();
  

 final  String query;

/// Create a copy of UserIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserIntent_GeneralCopyWith<UserIntent_General> get copyWith => _$UserIntent_GeneralCopyWithImpl<UserIntent_General>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserIntent_General&&(identical(other.query, query) || other.query == query));
}


@override
int get hashCode => Object.hash(runtimeType,query);

@override
String toString() {
  return 'UserIntent.general(query: $query)';
}


}

/// @nodoc
abstract mixin class $UserIntent_GeneralCopyWith<$Res> implements $UserIntentCopyWith<$Res> {
  factory $UserIntent_GeneralCopyWith(UserIntent_General value, $Res Function(UserIntent_General) _then) = _$UserIntent_GeneralCopyWithImpl;
@useResult
$Res call({
 String query
});




}
/// @nodoc
class _$UserIntent_GeneralCopyWithImpl<$Res>
    implements $UserIntent_GeneralCopyWith<$Res> {
  _$UserIntent_GeneralCopyWithImpl(this._self, this._then);

  final UserIntent_General _self;
  final $Res Function(UserIntent_General) _then;

/// Create a copy of UserIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? query = null,}) {
  return _then(UserIntent_General(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class UserIntent_InvalidCommand extends UserIntent {
  const UserIntent_InvalidCommand({required this.command, required this.reason}): super._();
  

 final  String command;
 final  String reason;

/// Create a copy of UserIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserIntent_InvalidCommandCopyWith<UserIntent_InvalidCommand> get copyWith => _$UserIntent_InvalidCommandCopyWithImpl<UserIntent_InvalidCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserIntent_InvalidCommand&&(identical(other.command, command) || other.command == command)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,command,reason);

@override
String toString() {
  return 'UserIntent.invalidCommand(command: $command, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $UserIntent_InvalidCommandCopyWith<$Res> implements $UserIntentCopyWith<$Res> {
  factory $UserIntent_InvalidCommandCopyWith(UserIntent_InvalidCommand value, $Res Function(UserIntent_InvalidCommand) _then) = _$UserIntent_InvalidCommandCopyWithImpl;
@useResult
$Res call({
 String command, String reason
});




}
/// @nodoc
class _$UserIntent_InvalidCommandCopyWithImpl<$Res>
    implements $UserIntent_InvalidCommandCopyWith<$Res> {
  _$UserIntent_InvalidCommandCopyWithImpl(this._self, this._then);

  final UserIntent_InvalidCommand _self;
  final $Res Function(UserIntent_InvalidCommand) _then;

/// Create a copy of UserIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? command = null,Object? reason = null,}) {
  return _then(UserIntent_InvalidCommand(
command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
