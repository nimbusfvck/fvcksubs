String safePlaybackUrlForLog(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '<invalid-url>';
  }

  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

String redactPlaybackLogText(Object? value) {
  final text = value?.toString() ?? '';
  return text.replaceAllMapped(RegExp(r'https?://[^\s\]\[<>{},]+'), (match) {
    final rawUrl = match.group(0)!;
    final trailing = rawUrl.endsWith('.') || rawUrl.endsWith(',')
        ? rawUrl.substring(rawUrl.length - 1)
        : '';
    final url = trailing.isEmpty
        ? rawUrl
        : rawUrl.substring(0, rawUrl.length - 1);
    return '${safePlaybackUrlForLog(url)}$trailing';
  });
}
