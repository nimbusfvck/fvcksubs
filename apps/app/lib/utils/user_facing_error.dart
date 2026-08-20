String userFacingErrorMessage(Object error, {required String resource}) {
  final message = error.toString().toLowerCase();
  final lowerResource = resource.trim().isEmpty
      ? 'resource'
      : resource.trim().toLowerCase();
  final resourceLabel = _capitalize(lowerResource);

  if (message.contains('404') || message.contains('not found')) {
    return '$resourceLabel not found. Check the URL.';
  }
  if (message.contains('401') || message.contains('403')) {
    return '$resourceLabel access was denied. Make sure the URL is public.';
  }
  if (message.contains('timeout') || message.contains('timed out')) {
    return 'The $lowerResource took too long to respond. Try again.';
  }
  if (message.contains('handshake') ||
      message.contains('certificate') ||
      message.contains('tls')) {
    return 'The secure connection to the $lowerResource failed.';
  }
  if (message.contains('socket') ||
      message.contains('connection') ||
      message.contains('host lookup')) {
    return 'Could not connect to the $lowerResource. Check your connection and URL.';
  }
  if (message.contains('json') ||
      message.contains('malformed') ||
      message.contains('format')) {
    return 'The $lowerResource format is invalid. Use a valid JSON file.';
  }
  if (message.contains('invalid uri') ||
      message.contains('invalid url') ||
      message.contains('no host specified')) {
    return 'Enter a valid $lowerResource URL.';
  }
  return 'Could not load the $lowerResource. Check the URL and try again.';
}

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
