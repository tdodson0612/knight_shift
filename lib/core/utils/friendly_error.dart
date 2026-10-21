// lib/core/utils/friendly_error.dart
//
// Turns an exception into a sentence a person can read. Server steps
// (create_company, accept_invite, clock_in, ...) raise plain-English
// messages, which arrive here as PostgrestException.message.

import 'package:supabase_flutter/supabase_flutter.dart';

String friendlyError(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is AuthException) return error.message;

  final text = error.toString();
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : text;
}
