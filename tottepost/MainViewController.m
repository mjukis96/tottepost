//
//  MainViewController.m
//  tottepost mainview controller
//
//  Created by Ken Watanabe on 11/12/10.
//  Copyright (c) 2011 cocotomo. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import "MainViewController.h"
#import "PhotoSubmitterSettings.h"
#import "MainViewControllerConstants.h"
#import "TTLang.h"
#import "UIColor-Expanded.h"
#import "AAMFeedbackViewController.h"
#import "UserVoiceAPIKey.h"
#import "UserVoice.h"
#import "UVSession.h"
#import "UVToken.h"
#import "NSData+Digest.h"
#import "FilePhotoSubmitter.h"
#import "YRDropdownView.h"
#import "TottepostSettings.h"
#import "LiteAlbumPhotoSubmitterSettingTableViewController.h"


static NSString *kFilePhotoSubmitterType = @"FilePhotoSubmitter";

//-----------------------------------------------------------------------------
//Private Implementations
//-----------------------------------------------------------------------------
@interface MainViewController(PrivateImplementation)
- (void) setupInitialState: (CGRect)aFrame;
- (void) didSettingButtonTapped: (id)sender;
- (void) didPostButtonTapped: (id)sender;
- (void) didPostCancelButtonTapped: (id)sender;
- (void) didCameraButtonTapped: (id)sender;
- (void) updateCoordinates;
- (void) updateIndicatorCoordinate;
- (void) previewContent:(PhotoSubmitterContentEntity *)content;
- (BOOL) closePreview:(BOOL)force;
- (void) postContent:(PhotoSubmitterContentEntity *)content;
- (void) changeCenterButtonTo: (UIBarButtonItem *)toButton;
- (void) updateCameraController;
- (void) createCameraController;
- (void) firstLaunched;
- (void) onVideoButtonTimer;
- (void) updateCameraIconImageView;
- (void) cleanupVideoMode;
- (BOOL) isVideoCameraAvailable;
- (void) applyCameraConfiguration;
@end

@implementation MainViewController(PrivateImplementation)
#pragma mark -
#pragma mark private methods
/*!
 * Initialize view controller
 */
- (void) setupInitialState: (CGRect) aFrame{
    aFrame.origin.y = 0;
    self.view.frame = aFrame;
    self.view.backgroundColor = [UIColor clearColor];
    refreshCameraNeeded_ = NO;
    [UIApplication sharedApplication].statusBarHidden = YES;
    
    //if you want to set schema suffix, call this before anything else
#ifdef LITE_VERSION
    [PhotoSubmitterManager setPhotoSubmitterCustomSchemaSuffix:@"tottepostlite"];
#else
    [PhotoSubmitterManager setPhotoSubmitterCustomSchemaSuffix:@"tottepostpaid"];
#endif
    
    //free mode
#ifdef LITE_VERSION
    //[PhotoSubmitterManager unregisterAllPhotoSubmitters];
    //[PhotoSubmitterManager registerPhotoSubmitterWithTypeNames:[NSArray arrayWithObjects: @"facebook", @"twitter", @"dropbox", @"minus", @"file", @"mixi", nil]];    
#endif
    
    //photo submitter setting
    [[PhotoSubmitterManager sharedInstance] addPhotoDelegate:self];
    [PhotoSubmitterManager sharedInstance].submitPhotoWithOperations = YES;
    [PhotoSubmitterManager sharedInstance].authControllerDelegate = self;
    [PhotoSubmitterManager sharedInstance].settingViewFactory = self;
    
    //setting view
    settingViewController_ = 
        [[TottepostSettingTableViewController alloc] init];
    settingNavigationController_ = [[UINavigationController alloc] initWithRootViewController:settingViewController_];
    settingNavigationController_.modalPresentationStyle = UIModalPresentationFormSheet;
    settingNavigationController_.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    settingViewController_.delegate = self;
    
    //preview image view
    previewImageView_ = [[PreviewPhotoView alloc] initWithFrame:CGRectZero];
    previewImageView_.delegate = self;
    
    //progress view
    progressTableViewController_ = [[ProgressTableViewController alloc] initWithFrame:CGRectZero andProgressSize:CGSizeMake(MAINVIEW_PROGRESS_WIDTH, MAINVIEW_PROGRESS_HEIGHT)];
    
    //add tool bar
    toolbar_ = [[UIToolbar alloc] initWithFrame:CGRectZero];
    toolbar_.barStyle = UIBarStyleBlack;
    
    if([self isVideoCameraAvailable]){
        cameraModeSwitchView_ = [[CameraModeSwitchView alloc] initWithFrame:CGRectZero];
        cameraModeSwitchView_.delegate = self;
    }
    
    //camera button
    UIButton *customView = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, MAINVIEW_CAMERA_BUTTON_WIDTH, MAINVIEW_CAMERA_BUTTON_HEIGHT)];
    [customView setBackgroundImage:[UIImage imageNamed:@"button_template.png"]forState:UIControlStateNormal];
    [customView addTarget:self action:@selector(didCameraButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    cameraButton_ = [[UIBarButtonItem alloc]initWithCustomView:customView];
    cameraButton_.style = UIBarButtonItemStyleBordered;
    UIImage *cameraIconImage = [UIImage imageNamed:@"camera.png"];
    cameraIconImageView_ = [[UIImageView alloc] initWithImage:cameraIconImage];
    cameraIconImageView_.frame = CGRectMake(MAINVIEW_CAMERA_BUTTON_WIDTH/2 - cameraIconImage.size.width/2, (MAINVIEW_CAMERA_BUTTON_HEIGHT - cameraIconImage.size.height)/2, cameraIconImage.size.width, cameraIconImage.size.height);
    [customView addSubview:cameraIconImageView_];
    
    //comment button
    commentButton_ = [[UIBarButtonItem alloc] init];
            
    //setting button
    settingButton_ = [[UIBarButtonItem alloc] init];
    
    //post button
    postButton_ = [[UIBarButtonItem alloc] initWithTitle:[TTLang localized:@"Main_Post"] style:UIBarButtonItemStyleBordered target:self action:@selector(didPostButtonTapped:)];

    //cancel button
    postCancelButton_ = [[UIBarButtonItem alloc] initWithTitle:[TTLang localized:@"Main_Cancel"] style:UIBarButtonItemStyleBordered target:self action:@selector(didPostCancelButtonTapped:)];
    
    //spacer for centalize camera button 
    flexSpace_ = [[UIBarButtonItem alloc]
                  initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                  target:nil
                  action:nil];
    UIBarButtonItem* spacer =
    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    [toolbar_ setItems:[NSArray arrayWithObjects:commentButton_,spacer, cameraButton_, spacer, settingButton_, nil]];
    
    //setting indicator view
    settingIndicatorView_ = [[SettingIndicatorView alloc] initWithFrame:CGRectZero];
    
    //progress summary
    progressSummaryView_ = [[ProgressSummaryView alloc] initWithFrame:CGRectZero];
    [[PhotoSubmitterManager sharedInstance] addPhotoDelegate: progressSummaryView_];
    [PhotoSubmitterManager sharedInstance].enableGeoTagging = 
      [PhotoSubmitterSettings getInstance].gpsEnabled;
    if([UIDevice currentDevice].orientation == UIDeviceOrientationPortraitUpsideDown){
        orientation_ = UIDeviceOrientationPortraitUpsideDown;
    }else{
        orientation_ = UIDeviceOrientationPortrait;
    }
    lastOrientation_ = orientation_;
    
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone){
        launchImageView_ = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Default.png"]];
        [self.view addSubview:launchImageView_];
    }
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    BOOL isNotFirstLaunched = [defaults boolForKey:@"IsNotFirstLaunched"];
    if(isNotFirstLaunched == false)
    {
        [self firstLaunched];
        [defaults setBool:YES forKey:@"IsNotFirstLaunched"];
    }
}

/*!
 * on setting button tapped, open setting view
 */
- (void) didSettingButtonTapped:(id)sender{
    [UIApplication sharedApplication].statusBarHidden = NO;
    [self presentModalViewController:settingNavigationController_ animated:YES];
    settingViewPresented_ = YES;
}

/*!
 * on comment button tapped, switch toggle comment post
 */
- (void) didCommentButtonTapped:(id)sender{
    [PhotoSubmitterSettings getInstance].commentPostEnabled = ![PhotoSubmitterSettings getInstance].commentPostEnabled;
    [self updateCoordinates];
}

#pragma mark -
#pragma mark coordinates

/*!
 * update control coodinates
 */
- (void)updateCoordinates{ 
    CGRect frame = self.view.frame;
    CGRect screen = [UIScreen mainScreen].bounds;

    frame = CGRectMake(0, 0, screen.size.width, screen.size.height);    
    [previewImageView_ updateWithFrame:frame];
    
    CGSize indicatorContentSize = settingIndicatorView_.contentSize;
    //progress view
    [progressTableViewController_ updateWithFrame:CGRectMake(frame.size.width - MAINVIEW_PROGRESS_WIDTH - MAINVIEW_PROGRESS_PADDING_X, MAINVIEW_PROGRESS_PADDING_Y, MAINVIEW_PROGRESS_WIDTH, frame.size.height - MAINVIEW_PROGRESS_PADDING_Y - MAINVIEW_PROGRESS_HEIGHT - MAINVIEW_TOOLBAR_HEIGHT - (MAINVIEW_PADDING_Y * 2) - indicatorContentSize.height - MAINVIEW_INDICATOR_PADDING_Y)];
    
    //progress summary
    CGRect ptframe = progressTableViewController_.view.frame;
    [progressSummaryView_ updateWithFrame:CGRectMake(ptframe.origin.x, ptframe.origin.y + ptframe.size.height + MAINVIEW_PADDING_Y, MAINVIEW_PROGRESS_WIDTH, MAINVIEW_PROGRESS_HEIGHT)];
    
    //setting indicator
    [self updateIndicatorCoordinate];
    
    //camera mode switch
    cameraModeSwitchView_.frame = CGRectMake(MAINVIEW_PROGRESS_PADDING_X, settingIndicatorView_.frame.origin.y - 16 , 60, 50);
    
    //toolbar
    [toolbar_ setFrame:CGRectMake(0, frame.size.height - MAINVIEW_TOOLBAR_HEIGHT, frame.size.width, MAINVIEW_TOOLBAR_HEIGHT)];
    flexSpace_.width = frame.size.width / 2 - MAINVIEW_CAMERA_BUTTON_WIDTH/2 - MAINVIEW_COMMENT_BUTTON_WIDTH - MAINVIEW_COMMENT_BUTTON_PADDING; 
    
    postButton_.width = MAINVIEW_POST_BUTTON_WIDTH;
    postCancelButton_.width = MAINVIEW_POSTCANCEL_BUTTON_WIDTH;

    CGAffineTransform t;
    switch (orientation_) {
        case UIDeviceOrientationPortrait:
            t = CGAffineTransformMakeRotation(0 * M_PI / 180);
            break;
        case UIDeviceOrientationLandscapeLeft:
            t = CGAffineTransformMakeRotation(90 * M_PI / 180);
            break;
        case UIDeviceOrientationLandscapeRight:
            t = CGAffineTransformMakeRotation(270 * M_PI / 180);
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            t = CGAffineTransformMakeRotation(180 * M_PI / 180);
            break;
        default:
            break;
    }
    
    UIButton *commentButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 42, 42)];
    if([PhotoSubmitterSettings getInstance].commentPostEnabled){
        [commentButton setBackgroundImage:[UIImage imageNamed:@"comment-selected.png"]forState:UIControlStateNormal];
    }else{
        [commentButton setBackgroundImage:[UIImage imageNamed:@"comment.png"]forState:UIControlStateNormal];
    }
    [commentButton addTarget:self action:@selector(didCommentButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    commentButton_.customView = commentButton;

    UIButton *settingButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 42, 42)];
    [settingButton setBackgroundImage:[UIImage imageNamed:@"setting.png"]forState:UIControlStateNormal];
    [settingButton addTarget:self action:@selector(didSettingButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    settingButton_.customView = settingButton;

    [UIView beginAnimations:@"RotateIcon" context:nil];
    commentButton.transform = t;
    settingButton.transform = t;
    cameraIconImageView_.transform = t;
    [UIView commitAnimations];
    
}

/*!
 * update setting indicator view coordinate
 */
-(void)updateIndicatorCoordinate{
    CGRect screen = [UIScreen mainScreen].bounds;
    CGRect frame = CGRectMake(0, 0, screen.size.width, screen.size.height);    
    CGSize indicatorContentSize = settingIndicatorView_.contentSize;
    CGRect psframe = progressSummaryView_.frame;
    settingIndicatorView_.frame = CGRectMake(frame.size.width - indicatorContentSize.width - MAINVIEW_PROGRESS_PADDING_X, psframe.origin.y + psframe.size.height + MAINVIEW_PADDING_Y, indicatorContentSize.width, indicatorContentSize.height);
    [settingIndicatorView_ update];
}

#pragma mark -
#pragma mark photo methods
/*!
 * on camera button tapped
 */
- (void)didCameraButtonTapped:(id)sender
{
    if(imagePicker_.mode == AVFoundationCameraModePhoto){
#if TARGET_IPHONE_SIMULATOR
        imagePicker_.showsCameraControls = NO;
        cameraButton_.enabled = NO;
        NSData *imageData = UIImageJPEGRepresentation([UIImage imageNamed:@"test_image.jpg"], 1.0);
        [self cameraController:nil didFinishPickingImageData:imageData];
#else
        [imagePicker_ takePicture];
#endif
    }else{
#if TARGET_IPHONE_SIMULATOR
        if(videoButtonTimer_ == nil){
            [self cameraControllerDidStartRecordingVideo:nil];
        }else{            
            [self cleanupVideoMode];
            NSURL *url = [[NSBundle mainBundle] URLForResource:@"test_video" withExtension:@"mov"];
            [self cameraController:nil didFinishRecordingVideoToOutputFileURL:url length:4.0 error:nil];
        }
#else
        if(imagePicker_.isRecordingVideo){
            [imagePicker_ stopRecordingVideo];
        }else{
            [imagePicker_ startRecordingVideo];
        }
#endif
    }
    //@throw [[NSException alloc] initWithName:@"some" reason:@"reason" userInfo:nil];
}

/*!
 * post photo
 */
- (void)postContent:(PhotoSubmitterContentEntity *)content{
    PhotoSubmitterManager *manager = [PhotoSubmitterManager sharedInstance];
    if(manager.enabledSubmitterCount == 0){
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[TTLang localized:@"Alert_Error"] message:[TTLang localized:@"Alert_NoSubmittersEnabled"] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
        return;
    }
    
    if(content.isPhoto){
        [manager submitPhoto:(PhotoSubmitterImageEntity *) content];
    }else if(content.isVideo){
        [manager submitVideo:(PhotoSubmitterVideoEntity *)content];
    }
}

#pragma mark -
#pragma mark preview methods
/*!
 * on post button tapped
 */
- (void) didPostButtonTapped:(id)sender{
    if([self closePreview:NO]){
        [self postContent:previewImageView_.content];
    }
}

/*!
 * on post cancel button tapped
 */
- (void) didPostCancelButtonTapped:(id)sender{
    [self closePreview:YES];
}

/*!
 * close preview
 */
- (BOOL)closePreview:(BOOL)force{
    BOOL ret = [previewImageView_ dismiss:force];
    if(ret){
        [self changeCenterButtonTo:cameraButton_];
    }
    [imagePicker_ restartSession];
    return ret;
}

/*!
 * preview content
 */
- (void)previewContent:(PhotoSubmitterContentEntity *)content{
    [self.view addSubview:previewImageView_];
    [previewImageView_ presentWithContent:content videoOrientation:orientation_];
    [self.view bringSubviewToFront:toolbar_];
    [self changeCenterButtonTo:postButton_];
}

/*!
 * toggle camera button <-> post button
 */
- (void)changeCenterButtonTo:(UIBarButtonItem *)toButton{
    NSMutableArray *items = [NSMutableArray arrayWithArray: toolbar_.items];
    if(toButton == cameraButton_){
        int index = [items indexOfObject:postButton_];
        flexSpace_.width += MAINVIEW_CAMERA_BUTTON_WIDTH;
        [items removeObject:postButton_];
        [items removeObject:postCancelButton_];
        [items insertObject:toButton atIndex:index];
    }else{
        int index = [items indexOfObject:cameraButton_];
        flexSpace_.width -= MAINVIEW_CAMERA_BUTTON_WIDTH;
        [items removeObject:cameraButton_];
        [items insertObject:postCancelButton_ atIndex:index];
        [items insertObject:toButton atIndex:index];
    }
    [toolbar_ setItems: items animated:YES];    
}

/*!
 * update cameracontroller
 */
- (void)updateCameraController{
    [imagePicker_.view removeFromSuperview];
    [progressTableViewController_.view removeFromSuperview];
    [settingIndicatorView_ removeFromSuperview];
    [toolbar_ removeFromSuperview];
    [progressSummaryView_ removeFromSuperview];
    [self.view addSubview:imagePicker_.view];
    [self.view addSubview:progressTableViewController_.view];
    [self.view addSubview:settingIndicatorView_];
    [self.view addSubview:toolbar_];
    [self.view addSubview:progressSummaryView_];  
    if([self isVideoCameraAvailable]){
        [self.view addSubview:cameraModeSwitchView_];
    }
    imagePicker_.delegate = self;

    [self updateCoordinates];
}

/*!
 * create camera view
 */
- (void) createCameraController{
    [UIApplication sharedApplication].statusBarHidden = YES;
    if(imagePicker_ == nil){
        imagePicker_ = [[AVFoundationCameraController alloc] initWithFrame:self.view.frame andMode:AVFoundationCameraModePhoto];
        imagePicker_.delegate = self;
        imagePicker_.showsCameraControls = YES;
        imagePicker_.showsShutterButton = NO;
        [self applyCameraConfiguration];
    }
    [self updateCameraController];
}

/*!
 * first launched
 */
- (void) firstLaunched{
    UIAlertView *alert =
    [[UIAlertView alloc] initWithTitle:[TTLang localized:@"FirstAlert_Title"] message:[TTLang localized:@"FirstAlert_Message"]
                              delegate:nil cancelButtonTitle:[TTLang localized:@"FirstAlert_OK"] otherButtonTitles:nil];
    [alert show];
}

/*!
 * on video button timer
 */
- (void)onVideoButtonTimer{
    videoButtonFlush_ = !videoButtonFlush_;
    [self updateCameraIconImageView];
}

/*!
 * update video button
 */
- (void)updateCameraIconImageView{
    if(imagePicker_.mode == AVFoundationCameraModePhoto){
        cameraIconImageView_.image = [UIImage imageNamed:@"camera.png"];
    }else{
        if(videoButtonFlush_){
            cameraIconImageView_.image = [UIImage imageNamed:@"videoButtonActive.png"];
        }else{
            cameraIconImageView_.image = [UIImage imageNamed:@"videoButton.png"];
        }    
    }
}

/*!
 * cleaup video mode
 */
- (void)cleanupVideoMode{
    cameraModeSwitchView_.enabled = YES;
    cameraButton_.enabled = YES;
    imagePicker_.showsCameraControls = YES;
    [videoButtonTimer_ invalidate];
    videoButtonTimer_ = nil;
    videoButtonFlush_ = NO;
    [self updateCameraIconImageView];
}

/*!
 * check for video camera availability
 */
- (BOOL) isVideoCameraAvailable{
#if TARGET_IPHONE_SIMULATOR
    return YES;
#endif
    static BOOL isAlreadyExamined = NO;
    static BOOL result = NO;

    if(isAlreadyExamined){
        return result;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    NSArray *sourceTypes = [UIImagePickerController availableMediaTypesForSourceType:picker.sourceType];
    
    if ([sourceTypes containsObject:(NSString *)kUTTypeMovie]){
        result = YES;
    }
    isAlreadyExamined = YES;
    return result;
}

/*!
 * apply camera configuration
 */
- (void)applyCameraConfiguration{
    imagePicker_.photoPreset = [TottepostSettings sharedInstance].photoPreset.name;
    imagePicker_.videoPreset = [TottepostSettings sharedInstance].videoPreset.name;
    imagePicker_.mode = AVFoundationCameraModePhoto;
    
    if([TottepostSettings sharedInstance].useSilentMode){
        imagePicker_.stillCameraMethod = AVFoundationStillCameraMethodVideoCapture;
    }else{
        imagePicker_.stillCameraMethod = AVFoundationStillCameraMethodStandard;
    }
    if([TottepostSettings sharedInstance].useSilentMode){
        imagePicker_.soundVolume = [TottepostSettings sharedInstance].shutterSoundVolume;
    }
}
@end

//-----------------------------------------------------------------------------
//Public Implementations
//-----------------------------------------------------------------------------
@implementation MainViewController
@synthesize refreshCameraNeeded = refreshCameraNeeded_;

#pragma mark -
#pragma mark public methods
/*!
 * initializer
 */
- (id)initWithFrame:(CGRect)frame
{
    self = [super init];
    if(self){
        [self setupInitialState:frame];
    }
    bool isCameraSupported = [UIImagePickerController isSourceTypeAvailable:
                              UIImagePickerControllerSourceTypeCamera];        
    if (isCameraSupported == false) {
        NSLog(@"camera is not supported");
    }
    return self;
}

/*!
 * application Did Become active
 */
- (void)applicationDidBecomeActive{
    if(settingViewPresented_){
        [settingViewController_ updateSocialAppSwitches];
    }
    [settingIndicatorView_ update];
}

/*!
 * determin refresh needed
 */
- (void)determinRefreshCameraNeeded{
    if(settingViewPresented_){
        refreshCameraNeeded_ = YES;
    }else{
        refreshCameraNeeded_ = NO;
    }
}

#pragma mark -
#pragma mark Image Picker delegate
/*! 
 * take photo
 */
- (void)cameraController:(AVFoundationCameraController *)cameraController didFinishPickingImageData:(NSData *)data{
    [self cleanupVideoMode];
    PhotoSubmitterImageEntity *photo = [[PhotoSubmitterImageEntity alloc] initWithData:data];
    if([PhotoSubmitterSettings getInstance].commentPostEnabled){
        [self previewContent:photo];
    }else{
        [self postContent:photo];
    }    
}

/*!
 * camera controller did initialized
 */
- (void)cameraControllerDidInitialized:(AVFoundationCameraController *)cameraController{
}

/*!
 * camera controller did start to recode video
 */
- (void)cameraControllerDidStartRecordingVideo:(AVFoundationCameraController *)controller{
    cameraModeSwitchView_.enabled = NO;
    videoButtonFlush_ = NO;
    videoButtonTimer_ = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(onVideoButtonTimer) userInfo:nil repeats:YES];
    [videoButtonTimer_ fire];
}

/*!
 * video recording finished
 */
- (void)cameraController:(AVFoundationCameraController *)controller didFinishRecordingVideoToOutputFileURL:(NSURL *)outputFileURL length:(CGFloat)length error:(NSError *)error{
    [self cleanupVideoMode];
    if(error){
        return;
    }
    PhotoSubmitterVideoEntity *video = [[PhotoSubmitterVideoEntity alloc] initWithUrl:outputFileURL];
    
    if([PhotoSubmitterSettings getInstance].commentPostEnabled){
        [self previewContent:video];
    }else{
        [self postContent:video];        
    }
}

#pragma mark -
#pragma mark PhotoSubmitter delegate
/*!
 * photo upload start
 */
- (void)photoSubmitter:(id<PhotoSubmitterProtocol>)photoSubmitter willStartUpload:(NSString *)imageHash{
    if([photoSubmitter.type isEqualToString:kFilePhotoSubmitterType]){
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [progressTableViewController_ addProgressWithType:photoSubmitter.type
                                                  forHash:imageHash];
    });
}

/*!
 * photo submitted
 */
- (void)photoSubmitter:(id<PhotoSubmitterProtocol>)photoSubmitter didSubmitted:(NSString *)imageHash suceeded:(BOOL)suceeded message:(NSString *)message{
    //NSLog(@"%@ submitted.", imageHash);
    
    NSString *msg = [TTLang localized:@"ProgressCell_Completed"];
    int delay = TOTTEPOST_PROGRESS_REMOVE_DELAY;
    if([photoSubmitter.type isEqualToString:kFilePhotoSubmitterType]){
        return;
    }else if(suceeded == NO){
        delay = 0;
        msg = @"";
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [progressTableViewController_ removeProgressWithType:photoSubmitter.type
                                                     forHash:imageHash 
                                                     message:msg delay:delay];
        if(suceeded == NO){
            [YRDropdownView showDropdownInView:self.view 
                                         title:[TTLang localized:@"PS_Upload_Failed"]
                                        detail:[TTLang localized:@"PS_Upload_Failed_Detail"]
                                         image:[UIImage imageNamed:@"unhappyface.png"]
                                      animated:YES 
                                     hideAfter:8.0 
                                    setUIcolor:[UIColor colorWithRed:1 green:0 blue:0 alpha:1] 
                                setPrettylayer:@"glossLayer"];
        }
    });
}

/*!
 * photo upload progress changed
 */
- (void)photoSubmitter:(id<PhotoSubmitterProtocol>)photoSubmitter didProgressChanged:(NSString *)imageHash progress:(CGFloat)progress{
    if([photoSubmitter.type isEqualToString:kFilePhotoSubmitterType]){
        return;
    }
    //NSLog(@"%@, %f", imageHash, progress);
    dispatch_async(dispatch_get_main_queue(), ^{
        [progressTableViewController_ updateProgressWithType:photoSubmitter.type 
                                                     forHash:imageHash progress:progress];
    });
}

/*!
 * photo submitter did canceled
 */
- (void)photoSubmitter:(id<PhotoSubmitterProtocol>)photoSubmitter didCanceled:(NSString *)imageHash{   
    NSString *msg = [TTLang localized:@"ProgressCell_Canceled"];
    if([photoSubmitter.type isEqualToString:kFilePhotoSubmitterType]){
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [progressTableViewController_ removeProgressWithType:photoSubmitter.type
                                                     forHash:imageHash 
                                                     message:msg delay:0];
    });
    
}

#pragma mark -
#pragma mark PreviewPhotoView delegate
/*!
 * request for orientation
 */
- (UIDeviceOrientation)requestForOrientation{
    return orientation_;
}

#pragma mark -
#pragma mark SettingView delegate
/*!
 * did dismiss setting view
 */
- (void)didDismissSettingTableViewController{
    //for iphone heck
    if(self.view.frame.origin.y == MAINVIEW_STATUS_BAR_HEIGHT){
        CGRect frame = self.view.frame;
        frame.origin.y = 0;
        frame.size.height += MAINVIEW_STATUS_BAR_HEIGHT;
        [self.view setFrame:frame];
    }
    if(self.refreshCameraNeeded){
        refreshCameraNeeded_ = NO;
    }else{
        [self updateCoordinates];
    }
    [self updateIndicatorCoordinate];
    settingViewPresented_ = NO;
    
    [self applyCameraConfiguration];    
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad){
        [self performSelector:@selector(viewDidAppear:) withObject:nil afterDelay:1.0];
    }
}

/*!
 * feedback button pressed
 */
- (void)didMailFeedbackButtonPressed{
    isMailFeedbackButtonPressed_ = YES;
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad){
        [self performSelector:@selector(viewDidAppear:) withObject:nil afterDelay:1.0];
    }
}

/*!
 * feedback button pressed
 */
- (void)didUserVoiceFeedbackButtonPressed{
    isUserVoiceFeedbackButtonPressed_ = YES;
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad){
        [self performSelector:@selector(viewDidAppear:) withObject:nil afterDelay:1.0];
    }
}

#pragma mark - PhotoSubmitterAuthControllerDelegate
/*!
 * request UINavigationController to present authentication view
 */
- (UINavigationController *) requestNavigationControllerToPresentAuthenticationView{
    return settingNavigationController_;
}

#pragma mark - PhotoSubmitterSettingViewFactoryProtocol
/*!
 * create setting view
 */
- (id)createSettingViewWithSubmitter:(id<PhotoSubmitterProtocol>)submitter{
#ifdef LITE_VERSION
    if(submitter.isAlbumSupported){
        return [[LiteAlbumPhotoSubmitterSettingTableViewController alloc] initWithType:submitter.type];
    }
#endif
    return nil;
}

#pragma mark - CameraModeSwitchViewDelegate
/*!
 * camera mode switch
 */
- (void)cameraModeSwitchView:(CameraModeSwitchView *)cameraModeSwitchView didModeChangedTo:(AVFoundationCameraMode)mode{
    imagePicker_.mode = mode;
    [self updateCameraIconImageView];
}

#pragma mark -
#pragma mark UIView delegate
/*!
 * auto rotation
 */
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if(interfaceOrientation == UIInterfaceOrientationPortrait){
        return YES;
    }
    return NO;
}

/*!
 * create camera controller when the view appeared
 */
- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [UIApplication sharedApplication].statusBarHidden = YES;
    if(imagePicker_ == nil){
        [self createCameraController];
    }
    if(isMailFeedbackButtonPressed_){
        isMailFeedbackButtonPressed_ = NO;
        isUserVoiceFeedbackButtonPressed_ = NO;
        AAMFeedbackViewController *fv = [[AAMFeedbackViewController alloc] init];
        fv.toRecipients = [NSArray arrayWithObject:@"kentaro.ishitoya@gmail.com"];
        fv.bccRecipients = [NSArray arrayWithObject:@"ken45000@gmail.com"];
        UINavigationController *nvc = [[UINavigationController alloc] initWithRootViewController:fv];
        [self presentModalViewController:nvc animated:YES];
    }else if(isUserVoiceFeedbackButtonPressed_){
        isMailFeedbackButtonPressed_ = NO;
        isUserVoiceFeedbackButtonPressed_ = NO;
        
        [UVSession clearCurrentSession];
        [UserVoice presentUserVoiceModalViewControllerForParent:self
                    andSite:TOTTEPOST_USERVOICE_API_SITE
                     andKey:TOTTEPOST_USERVOICE_API_KEY
                  andSecret:TOTTEPOST_USERVOICE_API_SECRET];
    }
}

/*
 * did rotated device orientation
 */
- (void) didRotatedDeviceOrientation:(UIDeviceOrientation) orientation{
    if(orientation == UIDeviceOrientationPortrait ||
       orientation == UIDeviceOrientationPortraitUpsideDown ||
       orientation == UIDeviceOrientationLandscapeLeft ||
       orientation == UIDeviceOrientationLandscapeRight)
    {
        orientation_ = orientation;
    }
    
    if(orientation_ == lastOrientation_)
    {
        return;
    }
    lastOrientation_ = orientation_;
    [self updateCoordinates];
}
@end
