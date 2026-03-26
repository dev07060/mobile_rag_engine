import '../src/rust/api/error.dart';

/// Extension to provide user-friendly error messages from RagError.
extension RagErrorUi on RagError {
  /// A user-friendly message suitable for UI display (Snackbars, Dialogs).
  String get userFriendlyMessage {
    return when(
      databaseError: (_) =>
          'A database error occurred. Please try again later.',
      ioError: (_) =>
          'Cannot read or write files. Please check storage permissions.',
      modelLoadError: (_) =>
          'Failed to load the AI model. Please restart the app.',
      invalidInput: (msg) => 'Invalid input: $msg',
      staleSearchHandle: (_) =>
          'The search results are no longer current. Please run the search again.',
      concurrentMutation: (_) =>
          'The underlying collection changed during search. Please try again.',
      internalError: (_) => 'A temporary internal error occurred.',
      unknown: (_) => 'An unknown error occurred.',
    );
  }

  /// The technical details for debugging (same as original message).
  String get technicalMessage {
    return when(
      databaseError: (msg) => msg,
      ioError: (msg) => msg,
      modelLoadError: (msg) => msg,
      invalidInput: (msg) => msg,
      staleSearchHandle: (msg) => msg,
      concurrentMutation: (msg) => msg,
      internalError: (msg) => msg,
      unknown: (msg) => msg,
    );
  }
}
