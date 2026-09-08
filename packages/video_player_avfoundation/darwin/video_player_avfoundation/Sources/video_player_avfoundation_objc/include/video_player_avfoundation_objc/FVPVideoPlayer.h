// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import AVFoundation;

#import "./VideoPlayerInstanceMessages.g.h"
#import "FVPAVFactory.h"
#import "FVPVideoEventListener.h"
#import "FVPViewProvider.h"

#if TARGET_OS_OSX
@import FlutterMacOS;
#else
@import Flutter;
#endif

NS_ASSUME_NONNULL_BEGIN

/// FVPVideoPlayer manages video playback using AVPlayer.
/// It provides methods for controlling playback, adjusting volume, and handling seeking.
/// This class contains all functionalities needed to manage video playback in platform views and is
/// typically used alongside NativeVideoViewFactory. If you need to display a video using a
/// texture, use FVPTextureBasedVideoPlayer instead.
@interface FVPVideoPlayer : NSObject <FVPVideoPlayerInstanceApi>
/// The AVPlayer instance used for video playback.
@property(nonatomic, readonly) AVPlayer *player;
/// Indicates whether the video player has been disposed.
@property(nonatomic, readonly) BOOL disposed;
/// Indicates whether the video player is set to loop.
@property(nonatomic) BOOL isLooping;
/// The current playback position of the video, in milliseconds.
@property(nonatomic, readonly) int64_t position;
/// The event listener to report video events to.
@property(nonatomic, nullable) NSObject<FVPVideoEventListener> *eventListener;
/// A block that will be called when dispose is called.
@property(nonatomic, nullable, copy) void (^onDisposed)(void);

#if TARGET_OS_IOS
/// Supplies the visible platform-view layer as the source for Picture in Picture.
///
/// The native platform view is created after the player, so the view factory
/// wires its presentation layer back into the player once both objects exist.
- (void)setPictureInPicturePlayerLayer:(AVPlayerLayer *)playerLayer;

/// Supplies the visible platform view so it can stop intercepting touches
/// while the app is showing native PiP and the caller underneath is usable.
- (void)setPictureInPicturePlayerView:(UIView *)view;

/// Enables or disables automatic inline Picture in Picture for this player.
- (void)setPictureInPictureAutomaticallyFromInline:(BOOL)enabled;
#endif

/// Initializes a new instance of FVPVideoPlayer with the given AVPlayerItem, AV factory, and view
/// provider.
- (instancetype)initWithPlayerItem:(NSObject<FVPAVPlayerItem> *)item
                         avFactory:(id<FVPAVFactory>)avFactory
                      viewProvider:(NSObject<FVPViewProvider> *)viewProvider;

@end

NS_ASSUME_NONNULL_END
