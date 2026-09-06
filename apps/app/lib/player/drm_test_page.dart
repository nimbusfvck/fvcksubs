import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import '../widgets/app_page_bar.dart';
import 'widgets/video_player_vod.dart';

const _widevineTestStream = PlayableStream(
  url:
      'https://storage.googleapis.com/shaka-demo-assets/sintel-widevine/dash.mpd',
  format: StreamFormat.dash,
  drm: DrmConfig(
    scheme: DrmScheme.widevine,
    licenseUrl: 'https://cwip-shaka-proxy.appspot.com/no_auth',
  ),
  label: 'Shaka Sintel Widevine',
);

const _clearKeyTestStream = PlayableStream(
  url:
      'https://raw.githubusercontent.com/tinusneethling/betterplayer/ClearKeySupport/example/assets/testvideo_encrypt.mp4',
  drm: DrmConfig(
    scheme: DrmScheme.clearKey,
    clearKeyJson:
        '{"type":"temporary","keys":[{"kty":"oct","kid":"88XgNh5mVLKPgEnHeLI5Rg","k":"pGMaFTpEPfnu0FkwQ9t1GQ"},{"kty":"oct","kid":"q7onHovPVSu9LoakNKml2Q","k":"aeqoAqZ2Ovl56NGUD7iDkg"}]}',
  ),
  label: 'ClearKey',
);

const _fairPlayTestStream = PlayableStream(
  url:
      'https://pbs.github.io/test-streams/pbs/test-pattern-drm/pbs-bars_avc.m3u8',
  headers: <String, String>{
    'X-AxDRM-Message':
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewogICJ2ZXJzaW9uIjogMSwKICAiY29tX2tleV9pZCI6ICI2OWU1NDA4OC1lOWUwLTQ1MzAtOGMxYS0xZWI2ZGNkMGQxNGUiLAogICJtZXNzYWdlIjogewogICAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgICAidmVyc2lvbiI6IDIsCiAgICAibGljZW5zZSI6IHsKICAgICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogICAgfSwKICAgICJjb250ZW50X2tleXNfc291cmNlIjogewogICAgICAiaW5saW5lIjogWwogICAgICAgIHsKICAgICAgICAgICJpZCI6ICIzMDJmODBkZC00MTFlLTQ4ODYtYmNhNS1iYjFmODAxOGEwMjQiLAogICAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAicm9LQWcwdDdKaTFpNDNmd3YremZ0UT09IiwKICAgICAgICAgICJ1c2FnZV9wb2xpY3kiOiAiUG9saWN5IEEiCiAgICAgICAgfQogICAgICBdCiAgICB9LAogICAgImNvbnRlbnRfa2V5X3VzYWdlX3BvbGljaWVzIjogWwogICAgICB7CiAgICAgICAgIm5hbWUiOiAiUG9saWN5IEEiLAogICAgICAgICJwbGF5cmVhZHkiOiB7CiAgICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAgICJwbGF5X2VuYWJsZXJzIjogWwogICAgICAgICAgICAiNzg2NjI3RDgtQzJBNi00NEJFLThGODgtMDhBRTI1NUIwMUE3IgogICAgICAgICAgXQogICAgICAgIH0KICAgICAgfQogICAgXQogIH0KfQ._NfhLVY7S6k8TJDWPeMPhUawhympnrk6WAZHOVjER6M',
  },
  format: StreamFormat.hls,
  drm: DrmConfig(
    scheme: DrmScheme.fairPlay,
    certificateUrl: 'https://tools.axinom.com/FPScert/fairplay.cer',
    licenseUrl: 'https://drm-fairplay-licensing.axprod.net/AcquireLicense',
  ),
  label: 'PBS AVC FairPlay',
);

/// Debug-only page for exercising the native Android and Apple DRM integrations.
class DrmTestPage extends StatefulWidget {
  const DrmTestPage({super.key});

  @override
  State<DrmTestPage> createState() => _DrmTestPageState();
}

class _DrmTestPageState extends State<DrmTestPage> {
  int _selectedStreamIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final streams = isAndroid
        ? const [_widevineTestStream, _clearKeyTestStream]
        : isApple
        ? const [_fairPlayTestStream]
        : const <PlayableStream>[];
    final selectedIndex = _selectedStreamIndex < streams.length
        ? _selectedStreamIndex
        : 0;
    final stream = streams.isEmpty ? null : streams[selectedIndex];
    final implementation = isAndroid
        ? 'Android DRM'
        : isApple
        ? 'Apple FairPlay'
        : 'Unsupported platform';

    return Scaffold(
      appBar: const AppPageBar(title: 'DRM test streams'),
      body: stream == null
          ? Center(
              child: Text(
                'No DRM test stream is configured for this platform.',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onDarkSoft,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$implementation · ${stream.label}',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                      if (streams.length > 1) ...[
                        const SizedBox(height: AppSpacing.sm),
                        DropdownButton<int>(
                          value: _selectedStreamIndex,
                          items: [
                            for (var i = 0; i < streams.length; i++)
                              DropdownMenuItem<int>(
                                value: i,
                                child: Text(streams[i].label),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedStreamIndex = value);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: VideoPlayerVodView(
                    key: ValueKey<String>(stream.url),
                    stream: stream,
                  ),
                ),
              ],
            ),
    );
  }
}
