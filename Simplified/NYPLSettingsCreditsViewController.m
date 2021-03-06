#import "NYPLConfiguration.h"
#import "NYPLSettings.h"

#import "NYPLSettingsCreditsViewController.h"

@interface NYPLSettingsCreditsViewController ()

@property (nonatomic) UIWebView *webView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIActivityIndicatorView *activityIndicatorView;

@end

static NSString * const fallbackCreditsNoticeURLString = @"www.librarysimplified.org/acknowledgments.html";

@implementation NYPLSettingsCreditsViewController

#pragma mark NSObject

- (instancetype)init
{
  self = [super init];
  if(!self) return nil;
  
  self.title = NSLocalizedString(@"Acknowledgements", nil);
  
  return self;
}

#pragma mark UIViewController
- (void)viewDidLoad
{
  [super viewDidLoad];
  
  self.view.backgroundColor = [NYPLConfiguration backgroundColor];
  
  self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
  self.webView.autoresizingMask = (UIViewAutoresizingFlexibleHeight
                                   | UIViewAutoresizingFlexibleWidth);
  self.webView.backgroundColor = [NYPLConfiguration backgroundColor];
  self.webView.delegate = self;
  
  NSURL *url = [[NYPLSettings sharedSettings] acknowledgmentsURL];
  if (!url) {
    url = [NSURL URLWithString:fallbackCreditsNoticeURLString];
  }
  
  NSURLRequest *const request = [NSURLRequest requestWithURL:url
                                                 cachePolicy:NSURLRequestUseProtocolCachePolicy
                                             timeoutInterval:15.0];
  
  [self.webView loadRequest:
   request];
  [self.view addSubview:self.webView];
  
  self.activityIndicatorView =
  [[UIActivityIndicatorView alloc]
   initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
  self.activityIndicatorView.center = self.view.center;
  self.activityIndicatorView.autoresizingMask = (UIViewAutoresizingFlexibleWidth |
                                                 UIViewAutoresizingFlexibleHeight);
  [self.activityIndicatorView startAnimating];
  [self.view addSubview:self.activityIndicatorView];
}

#pragma mark NSURLConnectionDelegate
- (void)webView:(__attribute__((unused)) UIWebView *)webView didFailLoadWithError:(__attribute__((unused)) NSError *)error {
  [self.activityIndicatorView stopAnimating];
  UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"ConnectionFailed", nil)
                                                                           message:NSLocalizedString(@"ConnectionFailed", nil)
                                                                    preferredStyle:UIAlertControllerStyleAlert];
  
  UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                         style:UIAlertActionStyleDestructive
                                                       handler:nil];
  
  UIAlertAction *reloadAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Reload", nil)
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *reloadAction) {
                                                         if (reloadAction) {
                                                           NSURL *url = [[NYPLSettings sharedSettings] acknowledgmentsURL];
                                                           if (!url) {
                                                             url = [NSURL URLWithString:fallbackCreditsNoticeURLString];
                                                           }
                                                           
                                                           NSURLRequest *const request = [NSURLRequest requestWithURL:url
                                                                                                          cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                                                                      timeoutInterval:15.0];
                                                           
                                                           [self.webView loadRequest:
                                                            request];
                                                         }
                                                       }];
  
  [alertController addAction:reloadAction];
  [alertController addAction:cancelAction];
  [self presentViewController:alertController
                     animated:NO
                   completion:nil];
}

-(void)webViewDidFinishLoad:(__attribute__((unused)) UIWebView *)webView {
  [self.activityIndicatorView stopAnimating];
}

-(BOOL)webView:(__attribute__((unused)) UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(__attribute__((unused)) UIWebViewNavigationType)navigationType {
  if ([[[request URL] absoluteString] isEqualToString:[[[NYPLSettings sharedSettings] acknowledgmentsURL] absoluteString]]) {
    return YES;
  }
  else if ([[[request URL] absoluteString] isEqualToString:fallbackCreditsNoticeURLString]) {
    return YES;
  }
  
  return NO;
}

@end
