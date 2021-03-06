@import LocalAuthentication;

#import "NYPLAccount.h"
#import "NYPLAlertController.h"
#import "NYPLBasicAuth.h"
#import "NYPLBookCoverRegistry.h"
#import "NYPLBookRegistry.h"
#import "NYPLConfiguration.h"
#import "NYPLLinearView.h"
#import "NYPLMyBooksDownloadCenter.h"
#import "NYPLReachability.h"
#import "NYPLSettingsAccountViewController.h"
#import "NYPLSettingsRegistrationViewController.h"
#import "NYPLRootTabBarController.h"
#import "UIView+NYPLViewAdditions.h"
#import "NYPLRegistrationStoryboard.h"
@import CoreLocation;

#if defined(FEATURE_DRM_CONNECTOR)
#import <ADEPT/ADEPT.h>
#endif

#define DO_MASK_BARCODE     1
#if DO_MASK_BARCODE
#import "CHRTextFieldFormatter.h"
#import "NYPLBarcodeTextMask.h"
#endif

typedef NS_ENUM(NSInteger, CellKind) {
  CellKindBarcode,
  CellKindPIN,
  CellKindLogInSignOut,
  CellKindRegistration
};

typedef NS_ENUM(NSInteger, Section) {
  SectionBarcodePin = 0,
  SectionLoginLogout = 1,
  SectionRegistration = 2
};

static CellKind CellKindFromIndexPath(NSIndexPath *const indexPath)
{
  switch(indexPath.section) {
    case 0:
      switch(indexPath.row) {
        case 0:
          return CellKindBarcode;
        case 1:
          return CellKindPIN;
        default:
          @throw NSInvalidArgumentException;
      }
    case 1:
      switch(indexPath.row) {
        case 0:
          return CellKindLogInSignOut;
        default:
          @throw NSInvalidArgumentException;
      }
    case 2:
      return CellKindRegistration;
    default:
      @throw NSInvalidArgumentException;
  }
}

@protocol NYPLTextMasker
- (NSString *)maskedStringFromString:(NSString *)string;
- (NSString *)unmaskedStringFromString:(NSString *)string;
@end

@interface NYPLMaskedTextField : UITextField
@property (nonatomic, strong) NSString *unmaskedText;
@property (nonatomic, strong) id<NYPLTextMasker> premasker;
@end

@implementation NYPLMaskedTextField
@dynamic unmaskedText;
- (NSString *)unmaskedText
{
  if (self.premasker)
    return [self.premasker unmaskedStringFromString:[super text]];
  return [super text];
}

- (void)setUnmaskedText:(NSString *)text
{
  if (self.premasker)
    [super setText:[self.premasker maskedStringFromString:text]];
  else
    [super setText:text];
}
@end

@interface NYPLSettingsAccountViewController () <NSURLSessionDelegate, UITextFieldDelegate, NYPLRegistrationStoryboardDelegate>

#if DO_MASK_BARCODE
@property (nonatomic) CHRTextFieldFormatter *barcodeFieldFormatter;
#endif

@property (nonatomic) NYPLMaskedTextField *barcodeTextField;
@property (nonatomic, copy) void (^completionHandler)();
@property (nonatomic) BOOL hiddenPIN;
@property (nonatomic) UITableViewCell *logInSignOutCell;
@property (nonatomic) UITextField *PINTextField;
@property (nonatomic) NSURLSession *session;
@property (nonatomic) UIButton *PINShowHideButton;

@end

@implementation NYPLSettingsAccountViewController

#pragma mark NSObject

- (instancetype)init
{
  self = [super initWithStyle:UITableViewStyleGrouped];
  if(!self) return nil;
  
  self.title = NSLocalizedString(@"LibraryCard", nil);

  [[NSNotificationCenter defaultCenter]
   addObserver:self
   selector:@selector(accountDidChange)
   name:NYPLAccountDidChangeNotification
   object:nil];
  
  [[NSNotificationCenter defaultCenter]
   addObserver:self
   selector:@selector(keyboardDidShow:)
   name:UIKeyboardWillShowNotification
   object:nil];
  
  [[NSNotificationCenter defaultCenter]
   addObserver:self
   selector:@selector(willResignActive)
   name:UIApplicationWillResignActiveNotification
   object:nil];

  [[NSNotificationCenter defaultCenter]
   addObserver:self
   selector:@selector(willEnterForeground)
   name:UIApplicationWillEnterForegroundNotification
   object:nil];
  
  NSURLSessionConfiguration *const configuration =
    [NSURLSessionConfiguration ephemeralSessionConfiguration];
  
  configuration.timeoutIntervalForResource = 10.0;
  
  self.session = [NSURLSession
                  sessionWithConfiguration:configuration
                  delegate:self
                  delegateQueue:[NSOperationQueue mainQueue]];
  
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark UIViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  self.view.backgroundColor = [NYPLConfiguration backgroundColor];
  
  self.barcodeTextField = [[NYPLMaskedTextField alloc] initWithFrame:CGRectZero];
  self.barcodeTextField.autoresizingMask = (UIViewAutoresizingFlexibleWidth |
                                            UIViewAutoresizingFlexibleHeight);
  self.barcodeTextField.font = [UIFont systemFontOfSize:17];
  self.barcodeTextField.placeholder = NSLocalizedString(@"Barcode", nil);
  self.barcodeTextField.keyboardType = UIKeyboardTypeNumberPad;
  [self.barcodeTextField
   addTarget:self
   action:@selector(textFieldsDidChange)
   forControlEvents:UIControlEventEditingChanged];
  
#if DO_MASK_BARCODE
  self.barcodeFieldFormatter = [[CHRTextFieldFormatter alloc] initWithTextField:self.barcodeTextField mask:[NYPLBarcodeTextMask new]];
  self.barcodeTextField.premasker = (id<NYPLTextMasker>) self.barcodeFieldFormatter;
#endif
  
  self.PINTextField = [[UITextField alloc] initWithFrame:CGRectZero];
  self.PINTextField.autoresizingMask = (UIViewAutoresizingFlexibleWidth |
                                        UIViewAutoresizingFlexibleHeight);
  self.PINTextField.font = [UIFont systemFontOfSize:17];
  self.PINTextField.placeholder = NSLocalizedString(@"PIN", nil);
  self.PINTextField.keyboardType = UIKeyboardTypeNumberPad;
  self.PINTextField.secureTextEntry = YES;
  self.PINTextField.delegate = self;
  [self.PINTextField
   addTarget:self
   action:@selector(textFieldsDidChange)
   forControlEvents:UIControlEventEditingChanged];

  self.PINShowHideButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.PINShowHideButton setTitle:NSLocalizedString(@"Show", nil) forState:UIControlStateNormal];
  [self.PINShowHideButton sizeToFit];
  [self.PINShowHideButton addTarget:self action:@selector(PINShowHideSelected)
                   forControlEvents:UIControlEventTouchUpInside];
  self.PINTextField.rightView = self.PINShowHideButton;
  self.PINTextField.rightViewMode = UITextFieldViewModeAlways;
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
  
  self.hiddenPIN = YES;
  
  [self accountDidChange];
  
  [self.tableView reloadData];
  
  [self updateShowHidePINState];
}

#if defined(FEATURE_DRM_CONNECTOR)
- (void)viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];
  if (![[NYPLADEPT sharedInstance] deviceAuthorized]) {
    if ([[NYPLAccount sharedAccount] hasBarcodeAndPIN]) {
      self.barcodeTextField.unmaskedText = [NYPLAccount sharedAccount].barcode;
      self.PINTextField.text = [NYPLAccount sharedAccount].PIN;
      [self logIn];
    }
  }
}
#endif

#pragma mark UITableViewDelegate

- (void)tableView:(__attribute__((unused)) UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *const)indexPath
{
  switch(CellKindFromIndexPath(indexPath)) {
    case CellKindBarcode:
      [self.barcodeTextField becomeFirstResponder];
      break;
    case CellKindPIN:
      [self.PINTextField becomeFirstResponder];
      break;
    case CellKindLogInSignOut:
      [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
      if([[NYPLAccount sharedAccount] hasBarcodeAndPIN]) {
        UIAlertController *const alertController =
          (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad
           ? [UIAlertController
              alertControllerWithTitle:NSLocalizedString(@"SignOut", nil)
              message:NSLocalizedString(@"SettingsAccountViewControllerLogoutMessage", nil)
              preferredStyle:UIAlertControllerStyleAlert]
           : [UIAlertController
              alertControllerWithTitle:
                NSLocalizedString(@"SettingsAccountViewControllerLogoutMessage", nil)
              message:nil
              preferredStyle:UIAlertControllerStyleActionSheet]);
        [alertController addAction:[UIAlertAction
                                    actionWithTitle:NSLocalizedString(@"SignOut", nil)
                                    style:UIAlertActionStyleDestructive
                                    handler:^(__attribute__((unused)) UIAlertAction *action) {
                                      [self logOut];
                                    }]];
        [alertController addAction:[UIAlertAction
                                    actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                    style:UIAlertActionStyleCancel
                                    handler:nil]];
        [self presentViewController:alertController animated:YES completion:nil];
      } else {
        [self logIn];
      }
      break;
    case CellKindRegistration:
      [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
      NYPLRegistrationStoryboard *registerCardStoryboard = (NYPLRegistrationStoryboard *) [NYPLRegistrationStoryboard storyboardWithName:@"LibraryCard" bundle:nil];
      registerCardStoryboard.delegate = self;
      UINavigationController *rootViewController = [registerCardStoryboard instantiateInitialViewController];
      rootViewController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
      [[NYPLRootTabBarController sharedController]
       safelyPresentViewController:rootViewController
       animated:YES
       completion:nil];
      break;
  }
}

- (void)verifyLocationServicesWithHandler:(void(^)(void))handler
{
  CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
  
  switch (status) {
    case kCLAuthorizationStatusAuthorizedAlways:
      if (handler) handler();
      break;
    case kCLAuthorizationStatusAuthorizedWhenInUse:
      if (handler) handler();
      break;
    case kCLAuthorizationStatusDenied:
    {
      UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Location", nil)
                                                                               message:NSLocalizedString(@"LocationRequiredMessage", nil)
                                                                        preferredStyle:UIAlertControllerStyleAlert];
      
      UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", nil)
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *action) {
                                                           if (action)[UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                                                         }];

      UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                           style:UIAlertActionStyleDestructive
                                                         handler:nil];
      
      [alertController addAction:settingsAction];
      [alertController addAction:cancelAction];
      
      [self presentViewController:alertController
                         animated:NO
                       completion:nil];
      
      break;
    }
    case kCLAuthorizationStatusRestricted:
      if (handler) handler();
      break;
    case kCLAuthorizationStatusNotDetermined:
      if (handler) handler();
      break;
  }
}

#pragma mark UITableViewDataSource

- (UITableViewCell *)tableView:(__attribute__((unused)) UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *const)indexPath
{
  // This is the amount of horizontal padding Apple uses around the titles in cells by default.
  CGFloat const padding = 16;
  
  switch(CellKindFromIndexPath(indexPath)) {
    case CellKindBarcode: {
      UITableViewCell *const cell = [[UITableViewCell alloc]
                                     initWithStyle:UITableViewCellStyleDefault
                                     reuseIdentifier:nil];
      cell.selectionStyle = UITableViewCellSelectionStyleNone;
      {
        CGRect frame = cell.contentView.bounds;
        frame.origin.x += padding;
        frame.size.width -= padding * 2;
        self.barcodeTextField.frame = frame;
        [cell.contentView addSubview:self.barcodeTextField];
      }
      return cell;
    }
    case CellKindPIN: {
      UITableViewCell *const cell = [[UITableViewCell alloc]
                                     initWithStyle:UITableViewCellStyleDefault
                                     reuseIdentifier:nil];
      cell.selectionStyle = UITableViewCellSelectionStyleNone;
      {
        CGRect frame = cell.contentView.bounds;
        frame.origin.x += padding;
        frame.size.width -= padding * 2;
        self.PINTextField.frame = frame;
        [cell.contentView addSubview:self.PINTextField];
      }
      return cell;
    }
    case CellKindLogInSignOut: {
      if(!self.logInSignOutCell) {
        self.logInSignOutCell = [[UITableViewCell alloc]
                                initWithStyle:UITableViewCellStyleDefault
                                reuseIdentifier:nil];
        self.logInSignOutCell.textLabel.font = [UIFont systemFontOfSize:17];
      }
      [self updateLoginLogoutCellAppearance];
      return self.logInSignOutCell;
    }
    case CellKindRegistration: {
      UITableViewCell *const cell = [[UITableViewCell alloc]
                                     initWithStyle:UITableViewCellStyleDefault
                                     reuseIdentifier:nil];
      cell.textLabel.font = [UIFont systemFontOfSize:17];
      cell.textLabel.text = NSLocalizedString(@"SignUp", nil);
      cell.textLabel.textColor = [NYPLConfiguration mainColor];
      return cell;
    }
  }
}

- (NSInteger)numberOfSectionsInTableView:(__attribute__((unused)) UITableView *)tableView
{
  if([[NYPLAccount sharedAccount] hasBarcodeAndPIN] || ![NYPLConfiguration cardCreationEnabled]) {
    // No registration is possible.
    return 2;
  } else {
    // Registration is possible.
    return 3;
  }
}

- (NSInteger)tableView:(__attribute__((unused)) UITableView *)tableView
 numberOfRowsInSection:(NSInteger const)section
{
  switch(section) {
    case SectionBarcodePin:
      return 2;
    case SectionLoginLogout:
      return 1;
    case SectionRegistration:
      return 1;
    default:
      @throw NSInternalInconsistencyException;
  }
}

- (BOOL)textFieldShouldBeginEditing:(__unused UITextField *)textField
{
  return ![[NYPLAccount sharedAccount] hasBarcodeAndPIN];
}

#if DO_MASK_BARCODE
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
  if (textField == self.barcodeTextField) {
    return [self.barcodeFieldFormatter textField:textField shouldChangeCharactersInRange:range replacementString:string];
  } else {
    return YES;
  }
}
#endif

#pragma mark NSURLSessionDelegate

- (void)URLSession:(__attribute__((unused)) NSURLSession *)session
              task:(__attribute__((unused)) NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *const)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                             NSURLCredential *credential))completionHandler
{
  NYPLBasicAuthCustomHandler(challenge,
                             completionHandler,
                             self.barcodeTextField.unmaskedText,
                             self.PINTextField.text);
}

#pragma mark NYPLRegistrationStoryboard delegate

- (void)storyboard:(__attribute__((unused)) NYPLRegistrationStoryboard *)storyboard willDismissWithNewAuthorization:(BOOL)hasNewAuthorization
{
  if (hasNewAuthorization) {
#ifdef FEATURE_DRM_CONNECTOR
    if (![[NYPLADEPT sharedInstance] deviceAuthorized] && [[NYPLAccount sharedAccount] hasBarcodeAndPIN])
      [self logIn];
#endif
  }
}

#pragma mark -

- (void)didSelectReveal
{
  self.hiddenPIN = NO;
  [self.tableView reloadData];
}

- (void)PINShowHideSelected
{
  if(self.PINTextField.text.length > 0 && self.PINTextField.secureTextEntry) {
    LAContext *const context = [[LAContext alloc] init];
    if([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:NULL]) {
      [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
              localizedReason:NSLocalizedString(@"SettingsAccountViewControllerAuthenticationReason", nil)
                        reply:^(__unused BOOL success,
                                __unused NSError *_Nullable error) {
                          if(success) {
                            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                              [self togglePINShowHideState];
                            }];
                          }
                        }];
    } else {
      [self togglePINShowHideState];
    }
  } else {
    [self togglePINShowHideState];
  }
}

- (void)togglePINShowHideState
{
  self.PINTextField.secureTextEntry = !self.PINTextField.secureTextEntry;
  NSString *title = self.PINTextField.secureTextEntry ? @"Show" : @"Hide";
  [self.PINShowHideButton setTitle:NSLocalizedString(title, nil) forState:UIControlStateNormal];
  [self.PINShowHideButton sizeToFit];
  [self.tableView reloadData];
}

- (void)accountDidChange
{
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    if([NYPLAccount sharedAccount].hasBarcodeAndPIN) {
      self.barcodeTextField.unmaskedText = [NYPLAccount sharedAccount].barcode;
      self.barcodeTextField.enabled = NO;
      self.barcodeTextField.textColor = [UIColor grayColor];
      self.PINTextField.text = [NYPLAccount sharedAccount].PIN;
      self.PINTextField.textColor = [UIColor grayColor];
    } else {
      self.barcodeTextField.unmaskedText = nil;
      self.barcodeTextField.enabled = YES;
      self.barcodeTextField.textColor = [UIColor blackColor];
      self.PINTextField.text = nil;
      self.PINTextField.textColor = [UIColor blackColor];
    }
    
    [self.tableView reloadData];
    
    [self updateLoginLogoutCellAppearance];
  }];
}

- (void)updateLoginLogoutCellAppearance
{
  if([[NYPLAccount sharedAccount] hasBarcodeAndPIN]) {
    self.logInSignOutCell.textLabel.text = NSLocalizedString(@"SignOut", nil);
    self.logInSignOutCell.textLabel.textAlignment = NSTextAlignmentCenter;
    self.logInSignOutCell.textLabel.textColor = [UIColor redColor];
    self.logInSignOutCell.userInteractionEnabled = YES;
  } else {
    self.logInSignOutCell.textLabel.text = NSLocalizedString(@"LogIn", nil);
    self.logInSignOutCell.textLabel.textAlignment = NSTextAlignmentNatural;
    BOOL const canLogIn =
      ([self.barcodeTextField.unmaskedText
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length &&
       [self.PINTextField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length);
    if(canLogIn) {
      self.logInSignOutCell.userInteractionEnabled = YES;
      self.logInSignOutCell.textLabel.textColor = [NYPLConfiguration mainColor];
    } else {
      self.logInSignOutCell.userInteractionEnabled = NO;
      self.logInSignOutCell.textLabel.textColor = [UIColor lightGrayColor];
    }
  }
}

- (void)logIn
{
  assert(self.barcodeTextField.unmaskedText.length > 0);
  assert(self.PINTextField.text.length > 0);
  
  [self.barcodeTextField resignFirstResponder];
  [self.PINTextField resignFirstResponder];

  [self setActivityTitleWithText:NSLocalizedString(@"Verifying", nil)];
  
  [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
  
  [self validateCredentials];
}

- (void)logOut
{
  void (^afterDeauthorization)() = ^() {
    [[NYPLMyBooksDownloadCenter sharedDownloadCenter] reset];
    [[NYPLBookRegistry sharedRegistry] reset];
    [[NYPLAccount sharedAccount] removeBarcodeAndPIN];
    [self.tableView reloadData];
  };
  
#if defined(FEATURE_DRM_CONNECTOR)
  if([NYPLADEPT sharedInstance].workflowsInProgress) {
    [self presentViewController:[NYPLAlertController
                                 alertWithTitle:@"SettingsAccountViewControllerCannotLogOutTitle"
                                 message:@"SettingsAccountViewControllerCannotLogOutMessage"]
                       animated:YES
                     completion:nil];
    return;
  }
  
  [self setActivityTitleWithText:NSLocalizedString(@"SigningOut", nil)];
  [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
  
  [[NYPLReachability sharedReachability]
   reachabilityForURL:[NYPLConfiguration circulationURL]
   timeoutInternal:5.0
   handler:^(BOOL reachable) {
     if(reachable) {
       [[NYPLADEPT sharedInstance]
        deauthorizeWithUsername:[[NYPLAccount sharedAccount] barcode]
        password:[[NYPLAccount sharedAccount] PIN]
        completion:^(BOOL success, __unused NSError *error) {
          if(!success) {
            // Even though we failed, all we do is log the error. The reason is
            // that we want the user to be able to log out anyway because the
            // failure is probably due to bad credentials and we do not want the
            // user to have to change their barcode or PIN just to log out. This
            // is only a temporary measure and we'll switch to deauthorizing with
            // a token that will remain invalid indefinitely in the near future.
            NYPLLOG(@"Failed to deauthorize successfully.");
          }
          self.navigationItem.titleView = nil;
          [[UIApplication sharedApplication] endIgnoringInteractionEvents];
          afterDeauthorization();
        }];
     } else {
       self.navigationItem.titleView = nil;
       [[UIApplication sharedApplication] endIgnoringInteractionEvents];
       [self presentViewController:[NYPLAlertController
                                    alertWithTitle:@"SettingsAccountViewControllerLogoutFailed"
                                    message:@"TimedOut"]
                          animated:YES
                        completion:nil];
     }
   }];
#else
  afterDeauthorization();
#endif
}

- (void)setActivityTitleWithText:(NSString *)text
{
  UIActivityIndicatorView *const activityIndicatorView =
  [[UIActivityIndicatorView alloc]
   initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
  
  [activityIndicatorView startAnimating];
  
  UILabel *const titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  titleLabel.text = text;
  titleLabel.font = [UIFont systemFontOfSize:17];
  [titleLabel sizeToFit];
  
  // This view is used to keep the title label centered as in Apple's Settings application.
  UIView *const rightPaddingView = [[UIView alloc] initWithFrame:activityIndicatorView.bounds];
  
  NYPLLinearView *const linearView = [[NYPLLinearView alloc] init];
  linearView.contentVerticalAlignment = NYPLLinearViewContentVerticalAlignmentMiddle;
  linearView.padding = 5.0;
  [linearView addSubview:activityIndicatorView];
  [linearView addSubview:titleLabel];
  [linearView addSubview:rightPaddingView];
  [linearView sizeToFit];
  
  self.navigationItem.titleView = linearView;
}

- (void)validateCredentials
{
  NSMutableURLRequest *const request =
    [NSMutableURLRequest requestWithURL:[NYPLConfiguration loanURL]];
  
  request.HTTPMethod = @"HEAD";
  
  NSURLSessionDataTask *const task =
    [self.session
     dataTaskWithRequest:request
     completionHandler:^(__attribute__((unused)) NSData *data,
                         NSURLResponse *const response,
                         NSError *const error) {
       
       // This cast is always valid according to Apple's documentation for NSHTTPURLResponse.
       NSInteger const statusCode = ((NSHTTPURLResponse *) response).statusCode;
       
       // Success.
       if(statusCode == 200) {
#if defined(FEATURE_DRM_CONNECTOR)
         [[NYPLADEPT sharedInstance]
          authorizeWithVendorID:@"NYPL"
          username:self.barcodeTextField.unmaskedText
          password:self.PINTextField.text
          completion:^(BOOL success, NSError *error) {
            [self authorizationAttemptDidFinish:success error:error];
          }];
#else
         [self authorizationAttemptDidFinish:YES error:nil];
#endif
         return;
       }
       
       self.navigationItem.titleView = nil;
       [[UIApplication sharedApplication] endIgnoringInteractionEvents];
       
       if (error.code == NSURLErrorCancelled) {
         // We cancelled the request when asked to answer the server's challenge a second time
         // because we don't have valid credentials.
         self.PINTextField.text = @"";
         [self textFieldsDidChange];
         [self.PINTextField becomeFirstResponder];
       }
       
       [self showLoginAlertWithError:error];
     }];
  
  [task resume];
}

- (void)showLoginAlertWithError:(NSError *)error
{
  [self presentViewController:[NYPLAlertController alertWithTitle:@"SettingsAccountViewControllerLoginFailed" error:error]
                     animated:YES completion:nil];
}

- (void)textFieldsDidChange
{
  [self updateLoginLogoutCellAppearance];
}

- (void)keyboardDidShow:(NSNotification *const)notification
{
  // This nudges the scroll view up slightly so that the log in button is clearly visible even on
  // older 3:2 iPhone displays. I wish there were a more general way to do this, but this does at
  // least work very well.
  
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
      CGSize const keyboardSize =
      [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
      CGRect visibleRect = self.view.frame;
      visibleRect.size.height -= keyboardSize.height + self.tableView.contentInset.top;
      if(!CGRectContainsPoint(visibleRect,
                              CGPointMake(0, CGRectGetMaxY(self.logInSignOutCell.frame)))) {
        // We use an explicit animation block here because |setContentOffset:animated:| does not seem
        // to work at all.
        [UIView animateWithDuration:0.25 animations:^{
          [self.tableView setContentOffset:CGPointMake(0, -self.tableView.contentInset.top + 20)];
        }];
      }
    }
  }];
}

+ (void)
requestCredentialsUsingExistingBarcode:(BOOL const)useExistingBarcode
authorizeImmediately:(BOOL)authorizeImmediately
completionHandler:(void (^)())handler
{
  NYPLSettingsAccountViewController *const accountViewController = [[self alloc] init];
  
  accountViewController.completionHandler = handler;
  
  // Tell |accountViewController| to create its text fields so we can set their properties.
  [accountViewController view];
  
  if(useExistingBarcode) {
    NSString *const barcode = [NYPLAccount sharedAccount].barcode;
    if(!barcode) {
      @throw NSInvalidArgumentException;
    }
    accountViewController.barcodeTextField.unmaskedText = barcode;
  } else {
    accountViewController.barcodeTextField.unmaskedText = @"";
  }
  
  accountViewController.PINTextField.text = @"";
  
  UIBarButtonItem *const cancelBarButtonItem =
    [[UIBarButtonItem alloc]
     initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
     target:accountViewController
     action:@selector(didSelectCancel)];
  
  accountViewController.navigationItem.leftBarButtonItem = cancelBarButtonItem;
  
  UIViewController *const viewController = [[UINavigationController alloc]
                                            initWithRootViewController:accountViewController];
  viewController.modalPresentationStyle = UIModalPresentationFormSheet;
  
  [[NYPLRootTabBarController sharedController]
   safelyPresentViewController:viewController 
   animated:YES
   completion:nil];
  
  if (authorizeImmediately && [NYPLAccount sharedAccount].hasBarcodeAndPIN) {
    accountViewController.PINTextField.text = [NYPLAccount sharedAccount].PIN;
    [accountViewController logIn];
  } else {
    if(useExistingBarcode) {
      [accountViewController.PINTextField becomeFirstResponder];
    } else {
      [accountViewController.barcodeTextField becomeFirstResponder];
    }
  }
}

+ (void)requestCredentialsUsingExistingBarcode:(BOOL)useExistingBarcode
                             completionHandler:(void (^)())handler
{
  [self requestCredentialsUsingExistingBarcode:useExistingBarcode authorizeImmediately:NO completionHandler:handler];
}

+ (void)authorizeUsingExistingBarcodeAndPinWithCompletionHandler:(void (^)())handler
{
  [self requestCredentialsUsingExistingBarcode:YES authorizeImmediately:YES completionHandler:handler];
}

- (void)didSelectCancel
{
  [self.navigationController.presentingViewController
   dismissViewControllerAnimated:YES
   completion:nil];
}

- (void)authorizationAttemptDidFinish:(BOOL)success error:(NSError *)error
{
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    self.navigationItem.titleView = nil;
    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    
    if(success) {
      [[NYPLAccount sharedAccount] setBarcode:self.barcodeTextField.unmaskedText
                                          PIN:self.PINTextField.text];
      [self dismissViewControllerAnimated:YES completion:^{}];
      void (^handler)() = self.completionHandler;
      self.completionHandler = nil;
      if(handler) handler();
      [[NYPLBookRegistry sharedRegistry] syncWithCompletionHandler:nil];
    } else {
      [self showLoginAlertWithError:error];
    }
  }];
}

- (void)willResignActive
{
  if(!self.PINTextField.secureTextEntry) {
    [self togglePINShowHideState];
  }
}

- (void)updateShowHidePINState
{
  self.PINTextField.rightView.hidden = YES;
  
  // LAPolicyDeviceOwnerAuthentication is only on iOS >= 9.0
  if([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 9) {
    LAContext *const context = [[LAContext alloc] init];
    if([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:NULL]) {
      self.PINTextField.rightView.hidden = NO;
    }
  }
}

- (void)willEnterForeground
{
  // We update the state again in case the user enabled or disabled an authentication mechanism.
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    [self updateShowHidePINState];
  }];
}

@end