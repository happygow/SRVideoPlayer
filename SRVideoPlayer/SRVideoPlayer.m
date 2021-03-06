//
//  SRVideoPlayer.m
//  SRVideoPlayer
//
//  Created by https://github.com/guowilling on 17/1/5.
//  Copyright © 2017年 SR. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "Masonry.h"
#import "SRVideoPlayer.h"
#import "SRPlayerLayerView.h"
#import "SRVideoProgressTip.h"
#import "SRVideoTopBar.h"
#import "SRVideoBottomBar.h"
#import "SRBrightnessView.h"
#import "SRVideoDownloader.h"

static const CGFloat kTopBottomBarH = 60;

#define SRVideoPlayerImageName(fileName) [@"SRVideoPlayer.bundle" stringByAppendingPathComponent:fileName]

static NSString * const SRVideoPlayerItemStatusKeyPath           = @"status";
static NSString * const SRVideoPlayerItemLoadedTimeRangesKeyPath = @"loadedTimeRanges";

typedef NS_ENUM(NSUInteger, SRControlType) {
    SRControlTypeProgress,
    SRControlTypeVoice,
    SRControlTypeLight,
    SRControlTypeNone = 999
};

@interface SRVideoPlayer() <UIGestureRecognizerDelegate, SRVideoTopBarBarDelegate, SRVideoBottomBarDelegate>

@property (nonatomic, strong) NSURL *videoURL;

@property (nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic, strong) UIView *touchView;

@property (nonatomic, assign, readwrite) SRVideoPlayerState playerState;
@property (nonatomic, assign) UIInterfaceOrientation currentOrientation;

@property (nonatomic, assign) BOOL moved;
@property (nonatomic, assign) BOOL controlHasJudged;
@property (nonatomic, assign) SRControlType controlType;

@property (nonatomic, assign) BOOL isFullScreen;
@property (nonatomic, assign) BOOL isDragingSlider;
@property (nonatomic, assign) BOOL isManualPaused;

@property (nonatomic, assign) CGPoint touchBeginPoint;
@property (nonatomic, assign) CGFloat touchBeginVoiceValue;

@property (nonatomic, assign) NSTimeInterval videoDuration;
@property (nonatomic, assign) NSTimeInterval videoCurrent;

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, strong) NSObject *playbackTimeObserver;

@property (nonatomic, weak  ) UIView *playerView;
@property (nonatomic, weak  ) UIView *playerSuperView;
@property (nonatomic, assign) CGRect  playerViewOriginalRect;
@property (nonatomic, strong) SRPlayerLayerView *playerLayerView;

@property (nonatomic, strong) SRVideoTopBar *topBar;
@property (nonatomic, strong) SRVideoBottomBar *bottomBar;
@property (nonatomic, strong) SRVideoProgressTip *videoProgressTip;
@property (nonatomic, strong) MPVolumeView *volumeView;
@property (nonatomic, strong) UISlider *volumeSlider;
@property (nonatomic, strong) UIButton *replayBtn;

@end

@implementation SRVideoPlayer

- (void)dealloc {
    NSLog(@"%s", __func__);
    [self destroyPlayer];
}

#pragma mark - Lazy Load

- (SRPlayerLayerView *)playerLayerView {
    if (!_playerLayerView) {
        _playerLayerView = [[SRPlayerLayerView alloc] init];
    }
    return _playerLayerView;
}

- (SRVideoTopBar *)topBar {
    if (!_topBar) {
        _topBar = [SRVideoTopBar videoTopBar];
        _topBar.delegate = self;
    }
    return _topBar;
}

- (SRVideoBottomBar *)bottomBar {
    if (!_bottomBar) {
        _bottomBar = [SRVideoBottomBar videoBottomBar];
        _bottomBar.delegate = self;
        _bottomBar.userInteractionEnabled = NO;
    }
    return _bottomBar;
}

- (UIActivityIndicatorView *)activityIndicatorView {
    if (!_activityIndicatorView) {
        _activityIndicatorView = [[UIActivityIndicatorView alloc] init];
    }
    return _activityIndicatorView;
}

- (UIView *)touchView {
    if (!_touchView) {
        _touchView = [[UIView alloc] init];
        _touchView.backgroundColor = [UIColor clearColor];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(touchViewTapAction:)];
        tap.delegate = self;
        [_touchView addGestureRecognizer:tap];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(touchViewPanAction:)];
        pan.delegate = self;
        [_touchView addGestureRecognizer:pan];
        
        _touchView.userInteractionEnabled = NO;
    }
    return _touchView;
}

- (MPVolumeView *)volumeView {
    if (!_volumeView) {
        _volumeView = [[MPVolumeView alloc] init];
        _volumeView.showsRouteButton = NO;
        _volumeView.showsVolumeSlider = NO;
        for (UIView *view in _volumeView.subviews) {
            if ([NSStringFromClass(view.class) isEqualToString:@"MPVolumeSlider"]) {
                _volumeSlider = (UISlider *)view;
                break;
            }
        }
    }
    return _volumeView;
}

- (SRVideoProgressTip *)videoProgressTip {
    if (!_videoProgressTip) {
        _videoProgressTip = [[SRVideoProgressTip alloc] init];
        _videoProgressTip.hidden = YES;
        _videoProgressTip.layer.cornerRadius = 10.0;
    }
    return _videoProgressTip;
}

- (UIButton *)replayBtn {
    if (!_replayBtn) {
        _replayBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [_replayBtn setImage:[UIImage imageNamed:SRVideoPlayerImageName(@"replay")] forState:UIControlStateNormal];
        [_replayBtn addTarget:self action:@selector(replayAction) forControlEvents:UIControlEventTouchUpInside];
        _replayBtn.hidden = YES;
    }
    return _replayBtn;
}

#pragma mark - Init Methods

+ (instancetype)playerWithVideoURL:(NSURL *)videoURL playerView:(UIView *)playerView playerSuperView:(UIView *)playerSuperView {
    return [[SRVideoPlayer alloc] initWithVideoURL:videoURL playerView:playerView playerSuperView:playerSuperView];
}

- (instancetype)initWithVideoURL:(NSURL *)videoURL playerView:(UIView *)playerView playerSuperView:(UIView *)playerSuperView {
    if (self = [super init]) {
        _videoURL = videoURL;
        _playerState = SRVideoPlayerStateBuffering;
        _playerEndAction = SRVideoPlayerEndActionStop;
        
        _playerView = playerView;
        _playerView.backgroundColor = [UIColor blackColor];
        _playerView.userInteractionEnabled = YES;
        
        _playerViewOriginalRect = playerView.frame;
        _playerSuperView = playerSuperView;
        
        [self setupSubViews];
        [self setupOrientation];
    }
    return self;
}

- (void)setupSubViews {
    __weak typeof(self) weakSelf = self;
    
    [_playerView addSubview:self.playerLayerView];
    [self.playerLayerView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.bottom.right.mas_equalTo(0);
    }];
    
    [_playerView addSubview:self.topBar];
    [self.topBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.mas_equalTo(0);
        make.height.mas_equalTo(kTopBottomBarH);
    }];
    
    [_playerView addSubview:self.bottomBar];
    [self.bottomBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.mas_equalTo(0);
        make.bottom.equalTo(weakSelf.playerView);
        make.height.mas_equalTo(kTopBottomBarH);
    }];
    
    [_playerView addSubview:self.activityIndicatorView];
    [self.activityIndicatorView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.centerY.equalTo(weakSelf.playerLayerView);
        make.width.height.mas_equalTo(44);
    }];
    
    [_playerView addSubview:self.touchView];
    [self.touchView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.equalTo(weakSelf.playerLayerView);
        make.top.equalTo(weakSelf.playerLayerView).offset(44);
        make.bottom.equalTo(weakSelf.playerLayerView).offset(-44);
    }];
    
    [_playerView addSubview:self.videoProgressTip];
    [self.videoProgressTip mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(weakSelf.playerView);
        make.width.equalTo(@150);
        make.height.equalTo(@90);
    }];
    
    [_playerView addSubview:self.replayBtn];
    [self.replayBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(weakSelf.playerView);
    }];
    
    [_playerView addSubview:self.volumeView];
    
    [SRBrightnessView sharedBrightnessView];
}

- (void)setupOrientation {
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationPortrait:
            _currentOrientation = UIInterfaceOrientationPortrait;
            break;
        case UIDeviceOrientationLandscapeLeft:
            _currentOrientation = UIInterfaceOrientationLandscapeLeft;
            break;
        case UIDeviceOrientationLandscapeRight:
            _currentOrientation = UIInterfaceOrientationLandscapeRight;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            _currentOrientation = UIInterfaceOrientationPortraitUpsideDown;
            break;
        default:
            break;
    }
    // notice: must set the app only support portrait orientation
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationDidChange) name:UIDeviceOrientationDidChangeNotification object:nil];
}

#pragma mark - Monitor Methods

- (void)orientationDidChange {
    UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
    switch (orientation) {
        case UIDeviceOrientationPortrait:
            [self changeToOrientation:UIInterfaceOrientationPortrait];
            break;
        case UIDeviceOrientationLandscapeLeft:
            [self changeToOrientation:UIInterfaceOrientationLandscapeLeft];
            break;
        case UIDeviceOrientationLandscapeRight:
            [self changeToOrientation:UIInterfaceOrientationLandscapeRight];
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            [self changeToOrientation:UIInterfaceOrientationPortraitUpsideDown];
            break;
        default:
            break;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    AVPlayerItem *playerItem = (AVPlayerItem *)object;
    if ([keyPath isEqualToString:SRVideoPlayerItemStatusKeyPath]) {
        NSLog(@"SRVideoPlayerItemStatusKeyPath");
        switch (playerItem.status) {
            case AVPlayerStatusReadyToPlay:
            {
                NSLog(@"AVPlayerStatusReadyToPlay");
                [self.activityIndicatorView stopAnimating];
                [self.player play];
                _playerState = SRVideoPlayerStatePlaying;
                if ([self.delegate respondsToSelector:@selector(videoPlayerDidPlay:)]) {
                    [self.delegate videoPlayerDidPlay:self];
                }
                self.bottomBar.userInteractionEnabled = YES;
                self.touchView.userInteractionEnabled = YES; // prevents the crash that caused by dragging before the video has not load successfully
                
                _videoDuration = playerItem.duration.value / playerItem.duration.timescale; // total time of the video
                self.bottomBar.totalTimeLabel.text = [self formatTimeWith:(long)ceil(_videoDuration)];
                self.bottomBar.playingProgressSlider.minimumValue = 0.0;
                self.bottomBar.playingProgressSlider.maximumValue = _videoDuration;
                
                __weak __typeof(self)weakSelf = self;
                _playbackTimeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:NULL usingBlock:^(CMTime time) {
                    __strong __typeof(weakSelf)strongSelf = weakSelf;
                    if (strongSelf.isDragingSlider) {
                        return;
                    }
                    if (strongSelf.isManualPaused) {
                        return;
                    }
                    if (strongSelf.activityIndicatorView.isAnimating) {
                        [strongSelf.activityIndicatorView stopAnimating];
                    }
                    strongSelf.playerState = SRVideoPlayerStatePlaying;
                    CGFloat currentTime = playerItem.currentTime.value / playerItem.currentTime.timescale;
                    strongSelf.bottomBar.currentTimeLabel.text = [strongSelf formatTimeWith:(long)ceil(currentTime)];
                    [strongSelf.bottomBar.playingProgressSlider setValue:currentTime animated:YES];
                    strongSelf.videoCurrent = currentTime;
                    if (strongSelf.videoCurrent > strongSelf.videoDuration) {
                        strongSelf.videoCurrent = strongSelf.videoDuration;
                    }
                }];
                break;
            }
            case AVPlayerStatusFailed:
            {
                // loading video error which usually a resource issue
                NSLog(@"AVPlayerStatusReadyToPlay");
                NSLog(@"player error: %@", _player.error);
                NSLog(@"playerItem error: %@", _playerItem.error);
                _playerState = SRVedioPlayerStateFailed;
                [self.activityIndicatorView stopAnimating];
                [self destroyPlayer];
                break;
            }
            case AVPlayerStatusUnknown:
            {
                NSLog(@"AVPlayerStatusUnknown");
                break;
            }
        }
    }
    if ([keyPath isEqualToString:SRVideoPlayerItemLoadedTimeRangesKeyPath]) {
        NSLog(@"SRVideoPlayerItemLoadedTimeRangesKeyPath");
        CMTimeRange timeRange = [playerItem.loadedTimeRanges.firstObject CMTimeRangeValue]; // buffer area
        NSTimeInterval timeBuffered = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration); // buffer progress
        NSTimeInterval timeTotal = CMTimeGetSeconds(playerItem.duration);
        [self.bottomBar.cacheProgressView setProgress:timeBuffered / timeTotal animated:YES];
    }
}

- (void)playerItemDidPlayToEnd:(NSNotification *)notification {
    _playerState = SRVideoPlayerStateFinished;
    switch (_playerEndAction) {
        case SRVideoPlayerEndActionStop:
            self.topBar.hidden    = YES;
            self.bottomBar.hidden = YES;
            self.replayBtn.hidden = NO;
            break;
        case SRVideoPlayerEndActionLoop:
            [self replayAction];
            break;
        case SRVideoPlayerEndActionDestroy:
            [self destroyPlayer];
            break;
    }
}

- (void)applicationWillResignActive {
    if (!_playerItem) {
        return;
    }
    [self.player pause];
    _playerState = SRVideoPlayerStatePaused;
    [self.bottomBar.playPauseBtn setImage:[UIImage imageNamed:SRVideoPlayerImageName(@"start")] forState:UIControlStateNormal];
}

- (void)applicationDidBecomeActive {
    if (!_playerItem) {
        return;
    }
    if (_isManualPaused) {
        return;
    }
    [self.player play];
    _playerState = SRVideoPlayerStatePlaying;
    [self.bottomBar.playPauseBtn setImage:[UIImage imageNamed:SRVideoPlayerImageName(@"pause")] forState:UIControlStateNormal];
}

- (void)replayAction {
    [self seekToTimeWithSeconds:0];
    
    self.topBar.hidden    = NO;
    self.bottomBar.hidden = NO;
    self.replayBtn.hidden = YES;
    
    [self timingHideTopBottomBar];
}

#pragma mark - Player Methods

- (void)play {
    if (!_videoURL) {
        return;
    }
    if ([_videoURL.absoluteString containsString:@"http"] || [_videoURL.absoluteString containsString:@"https"]) {
        NSString *cachePath = [[SRVideoDownloader sharedDownloader] querySandboxWithURL:_videoURL];
        if (cachePath) {
            _videoURL = [NSURL fileURLWithPath:cachePath];
        }
    }
    [self setupPlayer];
}

- (void)pause {
    if (!_playerItem) {
        return;
    }
    [_player pause];
    _isManualPaused = YES;
    _playerState = SRVideoPlayerStatePaused;
    if ([self.delegate respondsToSelector:@selector(videoPlayerDidPause:)]) {
        [self.delegate videoPlayerDidPause:self];
    }
    [self.bottomBar.playPauseBtn setImage:[UIImage imageNamed:SRVideoPlayerImageName(@"start")] forState:UIControlStateNormal];
}

- (void)resume {
    if (!_playerItem) {
        return;
    }
    [_player play];
    _isManualPaused = NO;
    _playerState = SRVideoPlayerStatePlaying;
    if ([self.delegate respondsToSelector:@selector(videoPlayerDidResume:)]) {
        [self.delegate videoPlayerDidResume:self];
    }
    [self.bottomBar.playPauseBtn setImage:[UIImage imageNamed:SRVideoPlayerImageName(@"pause")] forState:UIControlStateNormal];
}

- (void)setupPlayer {
    _playerItem = [AVPlayerItem playerItemWithURL:_videoURL];
    _player = [AVPlayer playerWithPlayerItem:_playerItem];
    [(AVPlayerLayer *)self.playerLayerView.layer setPlayer:_player];
    
    [_playerItem addObserver:self forKeyPath:SRVideoPlayerItemStatusKeyPath options:NSKeyValueObservingOptionNew context:nil];
    [_playerItem addObserver:self forKeyPath:SRVideoPlayerItemLoadedTimeRangesKeyPath options:NSKeyValueObservingOptionNew context:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidPlayToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    [self.activityIndicatorView startAnimating];
}

- (void)destroyPlayer {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_player) {
        if (_playerState == SRVideoPlayerStatePlaying) {
            [_player pause];
        }
        [_player removeTimeObserver:_playbackTimeObserver];
        [_playerItem removeObserver:self forKeyPath:SRVideoPlayerItemStatusKeyPath];
        [_playerItem removeObserver:self forKeyPath:SRVideoPlayerItemLoadedTimeRangesKeyPath];
        _player = nil;
        _playerItem = nil;
        _playbackTimeObserver = nil;
    }
    [_playerView removeFromSuperview];
    if ([self.delegate respondsToSelector:@selector(videoPlayerDidDestroy:)]) {
        [self.delegate videoPlayerDidDestroy:self];
    }
}

#pragma mark - Orientation Methods

- (void)changeToOrientation:(UIInterfaceOrientation)orientation {
    if (_currentOrientation == orientation) {
        return;
    }
    _currentOrientation = orientation;
    
    [_playerView removeFromSuperview];
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
        case UIInterfaceOrientationPortraitUpsideDown:
        {
            __weak typeof(self) weakSelf = self;
            [_playerSuperView addSubview:_playerView];
            [_playerView mas_remakeConstraints:^(MASConstraintMaker *make) {
                make.top.left.width.height.mas_equalTo(CGRectGetMinY(weakSelf.playerViewOriginalRect));
            }];
            [_bottomBar.changeScreenBtn setImage:[UIImage imageNamed:SRVideoPlayerImageName(@"full_screen")] forState:UIControlStateNormal];
            break;
        }
        case UIInterfaceOrientationLandscapeLeft:
        case UIInterfaceOrientationLandscapeRight:
        {
            [[UIApplication sharedApplication].keyWindow addSubview:_playerView];
            [_playerView mas_remakeConstraints:^(MASConstraintMaker *make) {
                make.width.height.equalTo(@([UIScreen mainScreen].bounds.size.height));
                make.center.equalTo([UIApplication sharedApplication].keyWindow);
            }];
            [_bottomBar.changeScreenBtn setImage:[UIImage imageNamed:SRVideoPlayerImageName(@"small_screen")] forState:UIControlStateNormal];
            break;
        }
        default:
            break;
    }
    [UIView animateWithDuration:0.5 animations:^{
        _playerView.transform = [self getTransformWithOrientation:orientation];
    }];
    
    [[UIApplication sharedApplication].keyWindow bringSubviewToFront:[SRBrightnessView sharedBrightnessView]];
}

- (CGAffineTransform)getTransformWithOrientation:(UIInterfaceOrientation)orientation {
    if (orientation == UIInterfaceOrientationPortrait) {
        [self updateToVerticalOrientation];
        return CGAffineTransformIdentity;
    } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        [self updateToHorizontalOrientation];
        return CGAffineTransformMakeRotation(M_PI_2);
    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        [self updateToHorizontalOrientation];
        return CGAffineTransformMakeRotation(-M_PI_2);
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        [self updateToVerticalOrientation];
        return CGAffineTransformMakeRotation(M_PI);
    }
    return CGAffineTransformIdentity;
}

- (void)updateToVerticalOrientation {
    _isFullScreen = NO;
    [[UIApplication sharedApplication] setStatusBarHidden:NO];
}

- (void)updateToHorizontalOrientation {
    _isFullScreen = YES;
    [[UIApplication sharedApplication] setStatusBarHidden:YES];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (_controlHasJudged) {
        return NO;
    } else {
        return YES;
    }
}

- (void)touchViewTapAction:(UITapGestureRecognizer *)tap {
    if (self.bottomBar.hidden) {
        [self showTopBottomBar];
    } else {
        [self hideTopBottomBar];
    }
}

- (void)touchViewPanAction:(UIPanGestureRecognizer *)pan {
    [self showTopBottomBar];
    CGPoint touchPoint = [pan locationInView:pan.view];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _touchBeginPoint = touchPoint;
        _moved = NO;
        _controlHasJudged = NO;
        _touchBeginVoiceValue = _volumeSlider.value;
    }
    if (pan.state == UIGestureRecognizerStateChanged) {
        if (fabs(touchPoint.x - _touchBeginPoint.x) < 10 && fabs(touchPoint.y - _touchBeginPoint.y) < 10) {
            return;
        }
        _moved = YES;
        if (!_controlHasJudged) {
            float tan = fabs(touchPoint.y - _touchBeginPoint.y) / fabs(touchPoint.x - _touchBeginPoint.x);
            if (tan < 1 / sqrt(3)) { // sliding angle is less than 30 degrees
                _controlType = SRControlTypeProgress;
                _controlHasJudged = YES;
            } else if (tan > sqrt(3)) { // sliding angle is greater than 60 degrees
                if (_touchBeginPoint.x < pan.view.frame.size.width / 2) { // the left side of the screen controls the brightness
                    _controlType = SRControlTypeLight;
                } else { // the right side of the screen controls the volume
                    _controlType = SRControlTypeVoice;
                }
                _controlHasJudged = YES;
            } else {
                _controlType = SRControlTypeNone;
            }
        }
        if (_controlType == SRControlTypeProgress) {
            NSTimeInterval videoCurrentTime = [self videoCurrentTimeWithTouchPoint:touchPoint];
            if (videoCurrentTime > _videoCurrent) {
                [self.videoProgressTip setTipImageViewImage:[UIImage imageNamed:SRVideoPlayerImageName(@"progress_right")]];
            } else if(videoCurrentTime < _videoCurrent) {
                [self.videoProgressTip setTipImageViewImage:[UIImage imageNamed:SRVideoPlayerImageName(@"progress_left")]];
            }
            self.videoProgressTip.hidden = NO;
            [self.videoProgressTip setTipLabelText:[NSString stringWithFormat:@"%@ / %@",
                                                    [self formatTimeWith:(long)videoCurrentTime],
                                                    self.bottomBar.totalTimeLabel.text]];
        } else if (_controlType == SRControlTypeVoice) {
            float voiceValue = _touchBeginVoiceValue - ((touchPoint.y - _touchBeginPoint.y) / CGRectGetHeight(pan.view.frame));
            if (voiceValue < 0) {
                self.volumeSlider.value = 0;
            } else if (voiceValue > 1) {
                self.volumeSlider.value = 1;
            } else {
                self.volumeSlider.value = voiceValue;
            }
        } else if (_controlType == SRControlTypeLight) {
            [UIScreen mainScreen].brightness -= ((touchPoint.y - _touchBeginPoint.y) / 5000);
        } else if (_controlType == SRControlTypeNone) {
            if (self.bottomBar.hidden) {
                [self showTopBottomBar];
            } else {
                [self hideTopBottomBar];
            }
        }
    }
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        _controlHasJudged = NO;
        if (_moved && _controlType == SRControlTypeProgress) {
            self.videoProgressTip.hidden = YES;
            [self seekToTimeWithSeconds:[self videoCurrentTimeWithTouchPoint:touchPoint]];
            [self.bottomBar.playPauseBtn setImage:[UIImage imageNamed:SRVideoPlayerImageName(@"pause")] forState:UIControlStateNormal];
        }
    }
}

#pragma mark - SRVideoTopBarBarDelegate

- (void)videoTopBarDidClickCloseBtn {
    [self destroyPlayer];
}

- (void)videoTopBarDidClickDownloadBtn {
    [[SRVideoDownloader sharedDownloader] downloadVideoOfURL:_videoURL progress:^(CGFloat progress) {
        NSLog(@"downloadVideo progress: %.2f", progress);
    } completion:^(NSString *cacheVideoPath, NSError *error) {
        if (cacheVideoPath) {
            NSLog(@"cacheVideoPath: %@", cacheVideoPath);
        } else {
            NSLog(@"error: %@", error);
        }
    }];
}

#pragma mark - SRVideoBottomBarDelegate

- (void)videoBottomBarDidClickPlayPauseBtn {
    if (!_playerItem) {
        return;
    }
    switch (_playerState) {
        case SRVideoPlayerStatePlaying:
            [self pause];
            break;
        case SRVideoPlayerStatePaused:
            [self resume];
            break;
        default:
            break;
    }
    [self timingHideTopBottomBar];
}

- (void)videoBottomBarDidClickChangeScreenBtn {
    if (_isFullScreen) {
        [self changeToOrientation:UIInterfaceOrientationPortrait];
    } else {
        [self changeToOrientation:UIInterfaceOrientationLandscapeLeft];
    }
    [self timingHideTopBottomBar];
}

- (void)videoBottomBarDidTapSlider:(UISlider *)slider withTap:(UITapGestureRecognizer *)tap {
    CGPoint touchPoint = [tap locationInView:slider];
    float value = (touchPoint.x / slider.frame.size.width) * slider.maximumValue;
    self.bottomBar.currentTimeLabel.text = [self formatTimeWith:(long)ceil(value)];
    [self seekToTimeWithSeconds:value];
    [self.bottomBar.playPauseBtn setImage:[UIImage imageNamed:SRVideoPlayerImageName(@"pause")] forState:UIControlStateNormal];
    [self timingHideTopBottomBar];
}

- (void)videoBottomBarChangingSlider:(UISlider *)slider {
    _isDragingSlider = YES;
    self.bottomBar.currentTimeLabel.text = [self formatTimeWith:(long)ceil(slider.value)];
    [self timingHideTopBottomBar];
}

- (void)videoBottomBarDidEndChangeSlider:(UISlider *)slider {
    // delay to prevent the sliding point from jumping
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        _isDragingSlider = NO;
    });
    self.bottomBar.currentTimeLabel.text = [self formatTimeWith:(long)ceil(slider.value)];
    [self seekToTimeWithSeconds:slider.value];
    [self.bottomBar.playPauseBtn setImage:[UIImage imageNamed:SRVideoPlayerImageName(@"pause")] forState:UIControlStateNormal];
    [self timingHideTopBottomBar];
}

#pragma mark - Assist Methods

- (NSString *)formatTimeWith:(long)time {
    NSString *formatTime = nil;
    if (time < 3600) {
        formatTime = [NSString stringWithFormat:@"%02li:%02li", lround(floor(time / 60.0)), lround(floor(time / 1.0)) % 60];
    } else {
        formatTime = [NSString stringWithFormat:@"%02li:%02li:%02li", lround(floor(time / 3600.0)), lround(floor(time % 3600) / 60.0), lround(floor(time / 1.0)) % 60];
    }
    return formatTime;
}

- (void)seekToTimeWithSeconds:(CGFloat)seconds {
    if (_playerState == SRVideoPlayerStateStopped) {
        return;
    }
    seconds = MAX(0, seconds);
    seconds = MIN(seconds, _videoDuration);
    [self.player pause];
    [self.player seekToTime:CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC) completionHandler:^(BOOL finished) {
        [self.player play];
        _isManualPaused = NO;
        _playerState = SRVideoPlayerStatePlaying;
        if (!_playerItem.isPlaybackLikelyToKeepUp) {
            _playerState = SRVideoPlayerStateBuffering;
            [self.activityIndicatorView startAnimating];
        }
    }];
}

- (NSTimeInterval)videoCurrentTimeWithTouchPoint:(CGPoint)touchPoint {
    float videoCurrentTime = _videoCurrent + 99 * ((touchPoint.x - _touchBeginPoint.x) / [UIScreen mainScreen].bounds.size.width);
    if (videoCurrentTime > _videoDuration) {
        videoCurrentTime = _videoDuration;
    }
    if (videoCurrentTime < 0) {
        videoCurrentTime = 0;
    }
    return videoCurrentTime;
}

- (void)showTopBottomBar {
    if (_playerState != SRVideoPlayerStatePlaying) {
        return;
    }
    self.topBar.hidden = NO;
    self.bottomBar.hidden = NO;
    [self timingHideTopBottomBar];
}

- (void)hideTopBottomBar {
    if (_playerState != SRVideoPlayerStatePlaying) {
        return;
    }
    self.topBar.hidden = YES;
    self.bottomBar.hidden = YES;
}

- (void)timingHideTopBottomBar {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideTopBottomBar) object:nil];
    [self performSelector:@selector(hideTopBottomBar) withObject:nil afterDelay:5.0];
}

#pragma mark - Public Methods

- (void)setVideoName:(NSString *)videoName {
    _videoName = videoName;
    
    [_topBar setTitle:videoName];
}

@end
