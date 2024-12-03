// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "EmulationCoordinator.h"

#import <GLKit/GLKit.h>

#import "Common/WindowSystemInfo.h"

#import "Core/Boot/Boot.h"
#import "Core/BootManager.h"
#import "Core/Core.h"
#import "Core/System.h"

#import "VideoCommon/RenderBase.h"
#import "VideoCommon/Present.h"

#import "EmulationBootParameter.h"
#import "HostNotifications.h"
#import "HostQueue.h"

@implementation EmulationCoordinator {
  GLKView* _mtkView;
  CAEAGLLayer* _metalLayer;
  UIView* _mainDisplayView;
}

@synthesize userRequestedPause = _userRequestedPause;

+ (EmulationCoordinator*)shared {
  static EmulationCoordinator* sharedInstance = nil;
  static dispatch_once_t onceToken;

  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });

  return sharedInstance;
}

- (id)init {
  if (self = [super init]) {
    _mtkView = [[GLKView alloc] init];
    _mtkView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    _metalLayer = (CAEAGLLayer*)_mtkView.layer;
    
    self.isExternalDisplayConnected = false;
  }
  
  return self;
}

- (void)setIsExternalDisplayConnected:(bool)connected {
  self->_isExternalDisplayConnected = connected;
  
  if (!_isExternalDisplayConnected) {
    [self requestDisplayOnSuperview:_mainDisplayView];
  }
}

- (void)registerMainDisplayView:(UIView*)mainView {
  _mainDisplayView = mainView;
  
  if (!self.isExternalDisplayConnected) {
    [self requestDisplayOnSuperview:mainView];
  }
}

- (void)registerExternalDisplayView:(UIView*)externalView {
  [self requestDisplayOnSuperview:externalView];
}

- (void)requestDisplayOnSuperview:(UIView*)superview {
  [_mtkView removeFromSuperview];
  
  [superview addSubview:_mtkView];
  [_mtkView setFrame:superview.bounds];
  
  if (g_presenter) {
    g_presenter->ResizeSurface();
  }
}

- (void)runEmulationWithBootParameter:(EmulationBootParameter*)bootParameter {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [self emulationLoopWithBootParameter:bootParameter];
  });
}

- (void)emulationLoopWithBootParameter:(EmulationBootParameter*)bootParameter {
  dispatch_sync(dispatch_get_main_queue(), ^{
    Core::UndeclareAsHostThread();
  });

  DOLHostQueueRunSync(^{
    __block WindowSystemInfo wsi;
    wsi.type = WindowSystemType::iOS;
    wsi.render_surface = (__bridge void*)self->_metalLayer;
    wsi.render_surface_scale = UIScreen.mainScreen.scale;
    
    std::unique_ptr<BootParameters> boot = [bootParameter generateDolphinBootParameter];
    
    if (!BootManager::BootCore(Core::System::GetInstance(), std::move(boot), wsi)) {
      PanicAlertFmt("Failed to init core!");
    }
  });
  
  while (Core::GetState(Core::System::GetInstance()) == Core::State::Starting) {
    [NSThread sleepForTimeInterval:0.025];
  }
  
  [[NSNotificationCenter defaultCenter] postNotificationName:DOLEmulationDidStartNotification object:self userInfo:nil];
  
  while (Core::IsRunning(Core::System::GetInstance())) {
    [NSThread sleepForTimeInterval:0.025];
  }
  
  dispatch_sync(dispatch_get_main_queue(), ^{
    Core::DeclareAsHostThread();
  });
  
  [[NSNotificationCenter defaultCenter] postNotificationName:DOLEmulationDidEndNotification object:self userInfo:nil];
  
  _mainDisplayView = nil;
}

- (bool)userRequestedPause {
  return _userRequestedPause;
}

- (void)setUserRequestedPause:(bool)userRequestedPause {
  if (userRequestedPause == _userRequestedPause) {
    return;
  }
  
  DOLHostQueueRunSync(^{
    Core::SetState(Core::System::GetInstance(), userRequestedPause ? Core::State::Paused : Core::State::Running);
  });
  
  _userRequestedPause = userRequestedPause;
}

@end
